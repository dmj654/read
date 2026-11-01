#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ReadingApp · 触发 GitHub Actions 未签名打包流水线并取回 IPA。

用途
----
在 Windows / 任意有 git + python3 + curl 的机器上，用一枚细粒度 PAT 完成：
    推送代码 → 手动触发 workflow_dispatch → 轮询状态 → 下载制品 → 解包出 .ipa
失败时自动拉取失败 job 的日志尾部，便于直接定位编译错误。

用法
----
    # 完整流程（推荐）
    GH_TOKEN=github_pat_xxx python scripts/ci_fetch_ipa.py

    # 已经推送过，只重新触发一次构建
    GH_TOKEN=github_pat_xxx python scripts/ci_fetch_ipa.py --skip-push

    # 跑签名版流水线（需已配好 4 个 Secrets）
    GH_TOKEN=github_pat_xxx python scripts/ci_fetch_ipa.py --workflow ci.yml

    # 只看状态不下载
    GH_TOKEN=github_pat_xxx python scripts/ci_fetch_ipa.py --no-download

安全
----
token 只从环境变量读取，绝不写入磁盘、绝不打印全文（日志里仅显示前 8 位 + 长度）。
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

API = "https://api.github.com"
REPO_DEFAULT = "dmj654/read"
UA = "ReadingApp-CI-Fetcher/1.0"

# 轮询参数
POLL_INTERVAL = 15          # 秒
RUN_START_TIMEOUT = 300     # 等 run 出现的最长秒数
RUN_TOTAL_TIMEOUT = 3600    # 单次构建最长等待秒数（macOS 首次跑 + 解析 SPM 通常 8~15 分钟）


# ── 基础工具 ────────────────────────────────────────────────────────────────

def log(msg: str) -> None:
    print(msg, flush=True)


def mask(token: str) -> str:
    if not token:
        return "(空)"
    return f"{token[:8]}…(len={len(token)})"


def api(
    method: str,
    path: str,
    token: str,
    body: dict | None = None,
    accept: str = "application/vnd.github+json",
    timeout: int = 30,
    retries: int = 3,
) -> tuple[int, dict | list | None]:
    """调用 GitHub REST API，返回 (status, parsed_json)。

    对 TLS 中断 / 连接重置等瞬时故障做退避重试；HTTP 错误码不重试，直接返回。
    """
    url = path if path.startswith("http") else f"{API}{path}"
    data = json.dumps(body).encode() if body is not None else None

    last_err: str = ""
    for attempt in range(1, retries + 1):
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Authorization", f"Bearer {token}")
        req.add_header("Accept", accept)
        req.add_header("X-GitHub-Api-Version", "2022-11-28")
        req.add_header("User-Agent", UA)
        if data is not None:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                raw = resp.read()
                return resp.status, (json.loads(raw) if raw else None)
        except urllib.error.HTTPError as exc:
            raw = exc.read()
            try:
                parsed = json.loads(raw) if raw else None
            except json.JSONDecodeError:
                parsed = {"raw": raw.decode("utf-8", "replace")}
            return exc.code, parsed
        except (urllib.error.URLError, OSError) as exc:
            # SSL: UNEXPECTED_EOF / 连接被代理重置 → 重试
            last_err = f"{type(exc).__name__}: {exc}"
            if attempt < retries:
                time.sleep(1.5 * attempt)
                continue
    return 0, {"error": f"网络不可达: {last_err}"}


def die(msg: str, code: int = 1) -> "NoReturn":  # type: ignore[name-defined]
    log(f"\n✗ {msg}")
    sys.exit(code)


def human(seconds: int) -> str:
    m, s = divmod(int(seconds), 60)
    return f"{m}分{s:02d}秒" if m else f"{s}秒"


# ── 第一步：推送 ────────────────────────────────────────────────────────────

def do_push(repo: str, token: str, branch: str, cwd: Path) -> bool:
    """用 git 协议推送。返回 True 表示成功；False 表示可回退到 API 推送。"""
    log("\n[1/5] 推送代码到 GitHub（git 协议）…")
    if not (cwd / ".git").exists():
        die(f"{cwd} 不是 git 仓库。请先 `git init` 并提交，或用 --skip-push。")

    # 用 x-access-token 形式认证，避免 token 落到 .git/config 里
    remote = f"https://x-access-token:{token}@github.com/{repo}.git"
    cmd = ["git", "push", remote, f"HEAD:{branch}", "--force-with-lease"]
    log(f"      $ git push https://x-access-token:***@github.com/{repo}.git HEAD:{branch}")

    proc = subprocess.run(
        cmd, cwd=str(cwd), capture_output=True, text=True, encoding="utf-8", errors="replace"
    )
    out = (proc.stdout or "") + (proc.stderr or "")
    # 万一 token 出现在输出里，先脱敏再打印
    out = out.replace(token, "***")
    if out.strip():
        for line in out.strip().splitlines():
            log(f"      {line}")
    if proc.returncode != 0:
        if "stale info" in out or "rejected" in out:
            log("      · force-with-lease 被拒，改用普通推送重试一次 …")
            proc = subprocess.run(
                ["git", "push", remote, f"HEAD:{branch}"],
                cwd=str(cwd), capture_output=True, text=True,
                encoding="utf-8", errors="replace",
            )
            out = ((proc.stdout or "") + (proc.stderr or "")).replace(token, "***")
            for line in out.strip().splitlines():
                log(f"      {line}")
        if proc.returncode != 0:
            log("      ✗ git 推送失败（可能是网络/代理阻断了 github.com:443）")
            return False
    log("      ✓ 推送完成")
    return True


# ── 第一步（备用通道）：Git Data API 推送 ───────────────────────────────────

def _ls_files(cwd: Path) -> list[tuple[str, str]]:
    """返回 [(相对路径, git mode)]，mode 形如 100644 / 100755。"""
    proc = subprocess.run(
        ["git", "ls-files", "--stage", "-z"],
        cwd=str(cwd), capture_output=True,
    )
    if proc.returncode != 0:
        die("git ls-files 失败，无法枚举待推送文件。")
    out: list[tuple[str, str]] = []
    for rec in proc.stdout.split(b"\0"):
        if not rec:
            continue
        meta, _, path = rec.partition(b"\t")
        parts = meta.split(b" ")
        if len(parts) < 2:
            continue
        out.append((path.decode("utf-8"), parts[0].decode()))
    return out


def _put_contents(repo: str, token: str, path: str, cwd: Path, message: str, branch: str) -> dict:
    """用 Contents API 写单个文件（空仓库也能用，会创建提交）。"""
    raw = (cwd / path).read_bytes()
    quoted = urllib.parse.quote(path, safe="/")
    status, res = api(
        "PUT",
        f"/repos/{repo}/contents/{quoted}",
        token,
        {
            "message": f"{message}\n\n+ {path}",
            "content": base64.b64encode(raw).decode("ascii"),
            "branch": branch,
        },
    )
    if status not in (200, 201) or not isinstance(res, dict):
        die(f"写入文件失败（{path}，HTTP {status}）：{res}")
    return res


def do_push_via_api(repo: str, token: str, branch: str, cwd: Path, message: str) -> None:
    """当 git 协议走不通时，用 REST API 直接写仓库。

    关键限制：GitHub 的 Git Data API（blobs/trees/commits）在**完全空仓库**上会返回
    `409 Git Repository is empty.`。因此空仓库必须先用 Contents API 写入一个文件，
    造出首个提交，之后才能批量建树提交。

    需要 token 具备 repo（Contents 写）+ workflow（推送 .github/workflows 必需）。
    """
    log("\n[1/5·备用] 改用 REST API 推送（绕过 git 协议）…")

    files = _ls_files(cwd)
    if not files:
        die("暂存区为空，没有可推送的文件。")
    log(f"      待推送 {len(files)} 个文件")

    # ── 判定远端是否为空 ──
    status, ref = api("GET", f"/repos/{repo}/git/ref/heads/{branch}", token)
    remote_empty = status != 200

    if remote_empty:
        log("      远端为空仓库 → 先用 Contents API 造首个提交")
        # 优先用 README.md 作为引导文件，其次取第一个文件
        order = {p: i for i, (p, _) in enumerate(files)}
        boot = "README.md" if "README.md" in order else files[0][0]
        res = _put_contents(repo, token, boot, cwd, message, branch)
        commit_sha = res.get("commit", {}).get("sha")
        log(f"      ✓ 引导提交 {str(commit_sha)[:10]}（{boot}）")
        files = [(p, m) for p, m in files if p != boot]

        status, ref = api("GET", f"/repos/{repo}/git/ref/heads/{branch}", token)
        if status != 200 or not isinstance(ref, dict):
            die(f"引导提交后仍读不到分支引用（HTTP {status}）：{ref}")

    parent_sha = ref["object"]["sha"]
    log(f"      父提交 {parent_sha[:10]}")

    # ── 批量通道：blobs → tree → commit → ref ──
    bulk_ok = True
    tree_entries: list[dict] = []
    for idx, (path, mode) in enumerate(files, 1):
        raw = (cwd / path).read_bytes()
        st, res = api(
            "POST",
            f"/repos/{repo}/git/blobs",
            token,
            {"content": base64.b64encode(raw).decode("ascii"), "encoding": "base64"},
        )
        if st not in (200, 201) or not isinstance(res, dict) or "sha" not in res:
            log(f"      ！blob 失败（{path}，HTTP {st}）：{res}")
            bulk_ok = False
            break
        tree_entries.append(
            {
                "path": path,
                "mode": "100755" if mode == "100755" else "100644",
                "type": "blob",
                "sha": res["sha"],
            }
        )
        if idx % 20 == 0 or idx == len(files):
            log(f"      blob {idx}/{len(files)}")

    if bulk_ok:
        # 取父提交的 tree 作为 base_tree，保留引导提交里的文件
        st, parent_commit = api("GET", f"/repos/{repo}/git/commits/{parent_sha}", token)
        base_tree = None
        if st == 200 and isinstance(parent_commit, dict):
            base_tree = parent_commit.get("tree", {}).get("sha")

        tree_body: dict = {"tree": tree_entries}
        if base_tree:
            tree_body["base_tree"] = base_tree

        st, tree = api("POST", f"/repos/{repo}/git/trees", token, tree_body)
        if st in (200, 201) and isinstance(tree, dict):
            st, commit = api(
                "POST",
                f"/repos/{repo}/git/commits",
                token,
                {"message": message, "tree": tree["sha"], "parents": [parent_sha]},
            )
            if st in (200, 201) and isinstance(commit, dict):
                st2, _ = api(
                    "PATCH",
                    f"/repos/{repo}/git/refs/heads/{branch}",
                    token,
                    {"sha": commit["sha"], "force": True},
                )
                if st2 in (200, 201):
                    log(f"      ✓ 批量提交 {commit['sha'][:10]}（{len(tree_entries)} 个文件）")
                else:
                    bulk_ok = False
                    log(f"      ！更新分支引用失败（HTTP {st2}）")
            else:
                bulk_ok = False
                log(f"      ！创建 commit 失败（HTTP {st}）：{commit}")
        else:
            bulk_ok = False
            log(f"      ！创建 tree 失败（HTTP {st}）：{tree}")

    # ── 逐文件兜底通道 ──
    if not bulk_ok:
        log("      改用逐文件 Contents API 写入（较慢）…")
        for idx, (path, _mode) in enumerate(files, 1):
            _put_contents(repo, token, path, cwd, message, branch)
            if idx % 10 == 0 or idx == len(files):
                log(f"      文件 {idx}/{len(files)}")

    # ── 回读校验（重点确认 workflow 文件真的落库）──
    status, check = api("GET", f"/repos/{repo}/contents/.github/workflows?ref={branch}", token)
    if status == 200 and isinstance(check, list):
        names = sorted(item.get("name", "") for item in check)
        log(f"      ✓ .github/workflows 已入库: {names}")
        if "ci-unsigned.yml" not in names:
            die("ci-unsigned.yml 未出现在仓库中，无法触发流水线。")
    else:
        die(f"回读 .github/workflows 失败（HTTP {status}）：{check}")

    status, head = api("GET", f"/repos/{repo}/branches/{branch}", token)
    if status == 200 and isinstance(head, dict):
        log(f"      ✓ 分支 {branch} @ {head.get('commit', {}).get('sha', '?')[:10]}")
    log("      ✓ 推送完成（API 通道）")



# ── 第二步：触发 ────────────────────────────────────────────────────────────

def do_dispatch(repo: str, token: str, workflow: str, branch: str) -> datetime:
    log(f"\n[2/5] 触发 workflow: {workflow} @ {branch} …")
    dispatched_at = datetime.now(timezone.utc)

    # 先确认 workflow 存在且可用
    status, data = api("GET", f"/repos/{repo}/actions/workflows", token)
    if status == 401:
        die("401 未授权：token 无效或已过期。")
    if status == 403:
        die("403 权限不足：请确认 token 具备 Actions: Read and write。")
    if status != 200 or not isinstance(data, dict):
        die(f"读取 workflow 列表失败（HTTP {status}）：{data}")

    names = [w.get("path", "").split("/")[-1] for w in data.get("workflows", [])]
    log(f"      仓库内已注册 workflow: {names or '（无）'}")
    if workflow not in names:
        die(
            f"仓库里没有 {workflow}。说明代码没推上去，或 .github/workflows/ 被 .gitignore 排除。\n"
            f"       排查：git ls-files .github/workflows"
        )

    status, data = api(
        "POST",
        f"/repos/{repo}/actions/workflows/{workflow}/dispatches",
        token,
        body={"ref": branch},
    )
    if status not in (204, 201):
        die(f"触发失败（HTTP {status}）：{data}")
    log("      ✓ 已触发，等待 Runner 接单 …")
    return dispatched_at


# ── 第三步：等 run 出现并跑完 ───────────────────────────────────────────────

def find_run(repo: str, token: str, workflow: str, since: datetime) -> dict:
    log("\n[3/5] 等待构建运行 …")
    deadline = time.time() + RUN_START_TIMEOUT
    while time.time() < deadline:
        status, data = api(
            "GET",
            f"/repos/{repo}/actions/workflows/{workflow}/runs?per_page=10&event=workflow_dispatch",
            token,
        )
        if status == 200 and isinstance(data, dict):
            for run in data.get("workflow_runs", []):
                created = run.get("created_at", "")
                try:
                    created_dt = datetime.strptime(created, "%Y-%m-%dT%H:%M:%SZ").replace(
                        tzinfo=timezone.utc
                    )
                except ValueError:
                    continue
                # 留 60 秒时钟容差
                if created_dt >= since.replace(microsecond=0) - timedelta(seconds=60):
                    return run
        time.sleep(POLL_INTERVAL)
    die(f"等了 {human(RUN_START_TIMEOUT)} 仍未见新的运行记录。请到 Actions 页面确认。")
    raise AssertionError  # 不可达


def wait_run(repo: str, token: str, run: dict) -> dict:
    run_id = run["id"]
    log(f"      运行 #{run.get('run_number')}  id={run_id}")
    log(f"      链接: {run.get('html_url')}")
    deadline = time.time() + RUN_TOTAL_TIMEOUT
    last_state = ""
    started = time.time()
    while time.time() < deadline:
        status, data = api("GET", f"/repos/{repo}/actions/runs/{run_id}", token)
        if status != 200 or not isinstance(data, dict):
            log(f"      · 查询状态返回 HTTP {status}，稍后重试")
            time.sleep(POLL_INTERVAL)
            continue

        state = f"{data.get('status')}/{data.get('conclusion') or '-'}"
        if state != last_state:
            log(f"      [{human(time.time() - started)}] {state}")
            last_state = state

        if data.get("status") == "completed":
            return data
        time.sleep(POLL_INTERVAL)

    die(f"构建超过 {human(RUN_TOTAL_TIMEOUT)} 仍未结束，已放弃等待。请到 Actions 页面查看。")
    raise AssertionError  # 不可达


def dump_failure(repo: str, token: str, run_id: int) -> None:
    """构建失败时，把失败 job 的步骤和日志尾部打出来。"""
    log("\n───── 失败诊断 ─────")
    status, data = api("GET", f"/repos/{repo}/actions/runs/{run_id}/jobs", token)
    if status != 200 or not isinstance(data, dict):
        log(f"  无法读取 job 列表（HTTP {status}）")
        return

    failed_jobs = []
    for job in data.get("jobs", []):
        if job.get("conclusion") == "failure":
            failed_jobs.append(job)
            log(f"\n  Job: {job.get('name')}  ({job.get('html_url')})")
            for step in job.get("steps", []):
                mark = {"success": "✓", "failure": "✗", "skipped": "·"}.get(
                    step.get("conclusion") or "", "…"
                )
                log(f"    {mark} {step.get('name')}")

    if not failed_jobs:
        log("  未找到 conclusion=failure 的 job，可能是 cancelled 或启动失败。")
        return

    # 下载原始日志（zip），只挑失败 job 的段落
    job_id = failed_jobs[0]["id"]
    tmp = Path("build") / f"logs-{run_id}.zip"
    tmp.parent.mkdir(parents=True, exist_ok=True)
    log(f"\n  下载日志: {job_id} …")
    rc = subprocess.run(
        [
            "curl", "-sSL", "-o", str(tmp),
            "-H", f"Authorization: Bearer {token}",
            "-H", "Accept: application/vnd.github+json",
            "-H", f"User-Agent: {UA}",
            f"{API}/repos/{repo}/actions/jobs/{job_id}/logs",
        ],
        capture_output=True,
    )
    if rc.returncode != 0 or not tmp.exists():
        log("  日志下载失败。")
        return

    try:
        with zipfile.ZipFile(tmp) as zf:
            text = "\n".join(
                zf.read(n).decode("utf-8", "replace") for n in zf.namelist()
            )
    except zipfile.BadZipFile:
        text = tmp.read_text(encoding="utf-8", errors="replace")

    # 抓 Swift 编译错误 / xcodebuild 错误
    lines = text.splitlines()
    keys = re.compile(
        r"(error:|error :|fatal error|undefined symbol|cannot find|"
        r"Cannot find .+ in scope|No such module|xcodebuild: error|The following build commands failed)",
        re.IGNORECASE,
    )
    hits = [ln for ln in lines if keys.search(ln)]
    if hits:
        log("\n  关键错误行（去重后前 40 条）：")
        seen = set()
        shown = 0
        for ln in hits:
            s = ln.strip()
            if s in seen or not s:
                continue
            seen.add(s)
            log(f"    {s[:300]}")
            shown += 1
            if shown >= 40:
                break
    else:
        log("\n  未匹配到编译错误关键字，输出最后 40 行：")
        for ln in lines[-40:]:
            log(f"    {ln[:300]}")


# ── 第四步：下载制品 ────────────────────────────────────────────────────────

def download_artifacts(repo: str, token: str, run_id: int, out_dir: Path) -> list[Path]:
    log("\n[4/5] 下载制品 …")
    out_dir.mkdir(parents=True, exist_ok=True)

    status, data = api("GET", f"/repos/{repo}/actions/runs/{run_id}/artifacts", token)
    if status != 200 or not isinstance(data, dict):
        die(f"读取制品列表失败（HTTP {status}）：{data}")

    items = data.get("artifacts", [])
    if not items:
        die("该次运行没有产出任何制品（构建可能在打包前就失败了）。")

    log("      制品清单：")
    for a in items:
        log(f"        · {a['name']}  {a['size_in_bytes'] / 1024 / 1024:.1f} MB")

    # 优先 IPA，其次 dSYM/报告
    def rank(a: dict) -> int:
        n = a["name"].lower()
        if "ipa" in n:
            return 0
        if "dsym" in n:
            return 1
        return 2

    ipas: list[Path] = []
    for a in sorted(items, key=rank):
        if rank(a) > 0:
            continue
        name = a["name"]
        zpath = out_dir / f"{name}.zip"
        log(f"      下载 {name} …")
        rc = subprocess.run(
            [
                "curl", "-sSL", "--retry", "3", "-o", str(zpath),
                "-H", f"Authorization: Bearer {token}",
                "-H", "Accept: application/vnd.github+json",
                "-H", f"User-Agent: {UA}",
                a["archive_download_url"],
            ],
        )
        if rc.returncode != 0 or not zpath.exists() or zpath.stat().st_size == 0:
            log(f"      ✗ {name} 下载失败")
            continue

        extract_dir = out_dir / name
        extract_dir.mkdir(parents=True, exist_ok=True)
        try:
            with zipfile.ZipFile(zpath) as zf:
                zf.extractall(extract_dir)
        except zipfile.BadZipFile:
            log(f"      ✗ {name} 不是合法 zip（可能是鉴权失败返回的 JSON）")
            log(f"        {zpath.read_text(encoding='utf-8', errors='replace')[:300]}")
            continue

        for p in extract_dir.rglob("*.ipa"):
            target = out_dir / p.name
            if p != target:
                target.write_bytes(p.read_bytes())
            ipas.append(target)
            zpath.unlink(missing_ok=True)

    if not ipas:
        die("制品里没有找到 .ipa 文件。构建可能止步于 Archive 阶段，请回看上面的失败诊断。")
    return ipas


# ── 第五步：校验并汇报 ──────────────────────────────────────────────────────

def inspect_ipa(path: Path) -> None:
    log("\n[5/5] 校验 IPA 结构 …")
    size_mb = path.stat().st_size / 1024 / 1024
    log(f"      文件: {path}")
    log(f"      大小: {size_mb:.2f} MB")

    try:
        with zipfile.ZipFile(path) as zf:
            names = zf.namelist()
    except zipfile.BadZipFile:
        die(f"{path} 不是合法 zip，IPA 已损坏。")

    info_plists = [n for n in names if re.match(r"Payload/[^/]+\.app/Info\.plist$", n)]
    execs = [
        n for n in names
        if re.fullmatch(r"Payload/[^/]+\.app/[^/.]+", n)
    ]
    if not info_plists:
        die("IPA 内缺少 Payload/*.app/Info.plist，结构异常。")

    log(f"      Payload: {info_plists[0].split('/')[1]}")
    log(f"      可执行: {', '.join(execs[:3]) or '（未找到，可能是纯资源包）'}")
    log(f"      文件数: {len(names)}")

    # 未签名包常见标志：没有 _CodeSignature 目录
    signed = any("_CodeSignature/" in n for n in names)
    log(f"      签名:   {'已签名（含 _CodeSignature）' if signed else '未签名（需 Sideloadly 自签安装）'}")


def main() -> None:
    ap = argparse.ArgumentParser(
        description="触发 ReadingApp 的 GitHub Actions 流水线并取回 IPA"
    )
    ap.add_argument("--repo", default=REPO_DEFAULT, help=f"owner/name，默认 {REPO_DEFAULT}")
    ap.add_argument("--workflow", default="ci-unsigned.yml",
                    help="ci-unsigned.yml（未签名，默认）或 ci.yml（签名版）")
    ap.add_argument("--branch", default="main")
    ap.add_argument("--cwd", default=".", help="本地工程目录，默认当前目录")
    ap.add_argument("--out", default="dist", help="IPA 输出目录，默认 ./dist")
    ap.add_argument("--skip-push", action="store_true", help="跳过推送，直接触发构建")
    ap.add_argument("--push-mode", choices=["auto", "git", "api"], default="auto",
                    help="auto=先试 git 再回退 API（默认）；git=仅 git；api=仅 API")
    ap.add_argument("--no-download", action="store_true", help="只等待结果，不下载制品")
    args = ap.parse_args()

    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN") or ""
    if not token.strip():
        die(
            "未提供 token。用法：\n"
            "  GH_TOKEN=github_pat_xxx python scripts/ci_fetch_ipa.py\n"
            "Windows CMD:  set GH_TOKEN=github_pat_xxx && python scripts/ci_fetch_ipa.py\n"
            "Windows PS :  $env:GH_TOKEN='github_pat_xxx'; python scripts/ci_fetch_ipa.py"
        )
    token = token.strip()

    cwd = Path(args.cwd).resolve()
    log("=" * 68)
    log("ReadingApp · 云端构建取包")
    log(f"  仓库    : {args.repo}")
    log(f"  流水线  : {args.workflow}")
    log(f"  分支    : {args.branch}")
    log(f"  本地目录: {cwd}")
    log(f"  token   : {mask(token)}")
    log("=" * 68)

    # token 自检
    status, me = api("GET", "/user", token)
    if status == 200 and isinstance(me, dict):
        log(f"  token 归属: {me.get('login')}")
    elif status in (401, 403):
        die(f"token 校验失败（HTTP {status}）：{me}")
    else:
        log(f"  （跳过 /user 校验，HTTP {status}——细粒度 token 未开 Profile 读取属正常）")

    if not args.skip_push:
        pushed = False
        if args.push_mode in ("auto", "git"):
            pushed = do_push(args.repo, token, args.branch, cwd)
        if not pushed and args.push_mode in ("auto", "api"):
            commit_msg = subprocess.run(
                ["git", "log", "-1", "--pretty=%B"], cwd=str(cwd),
                capture_output=True, text=True, encoding="utf-8", errors="replace",
            ).stdout.strip() or "chore: 同步 ReadingApp 源码"
            do_push_via_api(args.repo, token, args.branch, cwd, commit_msg)
        elif not pushed:
            die("git 推送失败，且 --push-mode=git 不允许回退到 API 通道。")
    else:
        log("\n[1/5] 跳过推送（--skip-push）")

    since = do_dispatch(args.repo, token, args.workflow, args.branch)
    run = find_run(args.repo, token, args.workflow, since)
    final = wait_run(args.repo, token, run)

    conclusion = final.get("conclusion")
    log(f"\n  最终结论: {conclusion}")
    log(f"  运行链接: {final.get('html_url')}")

    if conclusion != "success":
        dump_failure(args.repo, token, run["id"])
        die(f"构建未成功（{conclusion}）。以上为诊断信息。")

    if args.no_download:
        log("\n完成（按 --no-download 跳过下载）。")
        return

    ipas = download_artifacts(args.repo, token, run["id"], Path(args.out).resolve())
    for ipa in ipas:
        inspect_ipa(ipa)
    log("\n✓ 全部完成。可安装的包：")
    for ipa in ipas:
        log(f"    {ipa}")


if __name__ == "__main__":
    main()
