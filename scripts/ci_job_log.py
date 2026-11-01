#!/usr/bin/env python3
"""拉取指定 run 的 job 全量日志，并抽取失败用例，避免被日志噪音淹没。

用法:
  GH_TOKEN=... python scripts/ci_job_log.py --run 41322768584 [--grep PATTERN]
"""
import argparse
import json
import os
import ssl
import sys
import urllib.request
from pathlib import Path

API = "https://api.github.com"


class _StripAuthOnRedirect(urllib.request.HTTPRedirectHandler):
    """日志端点会 302 到 objects.githubusercontent.com（预签名 URL）。

    预签名 URL 自带凭据，若把 Authorization 一并转发过去，对方返回 401。
    因此跨主机重定向时手动剥掉鉴权头。
    """

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        new = super().redirect_request(req, fp, code, msg, headers, newurl)
        if new is not None:
            new.headers.pop("Authorization", None)
            new.headers.pop("authorization", None)
        return new


_OPENER = urllib.request.build_opener(
    _StripAuthOnRedirect(),
    urllib.request.HTTPSHandler(context=ssl.create_default_context()),
)


def api(path, token, accept="application/vnd.github+json", raw=False):
    req = urllib.request.Request(API + path, headers={
        "Authorization": f"Bearer {token}",
        "Accept": accept,
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "ci-job-log",
    })
    with _OPENER.open(req, timeout=180) as r:
        data = r.read()
    return data if raw else json.loads(data)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default="dmj654/read")
    ap.add_argument("--run", required=True)
    ap.add_argument("--grep", default=None)
    ap.add_argument("--out", default="build/ci")
    args = ap.parse_args()

    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if not token:
        sys.exit("缺少 GH_TOKEN")

    jobs = api(f"/repos/{args.repo}/actions/runs/{args.run}/jobs", token)["jobs"]
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    for job in jobs:
        name = job["name"]
        print(f"\n===== {name}  [{job['conclusion']}]  id={job['id']}")

        # 步骤级结论
        for st in job.get("steps", []):
            mark = {"success": "OK ", "failure": "FAIL", "skipped": "--"}.get(st["conclusion"], ".. ")
            print(f"  {mark} {st['name']}")

        if job["conclusion"] == "success":
            continue

        log = api(f"/repos/{args.repo}/actions/jobs/{job['id']}/logs", token,
                  accept="application/vnd.github+json", raw=True).decode("utf-8", "replace")
        safe = "".join(c if c.isalnum() or c in "-_." else "_" for c in name)
        path = out_dir / f"job-{job['id']}-{safe}.log"
        path.write_text(log, encoding="utf-8")
        print(f"  日志 -> {path}  ({len(log)} 字符)")

        keys = ["✗", "error:", "failed", "FAIL", "Failing", "assert", "AssertionError",
                "Executed", "Test Suite", "XCTAssert", "expect", "Crash", "BUILD FAILED",
                "** TEST", "error: -[", "error: :"]
        lines = log.splitlines()
        shown = set()
        print("\n  ── 关键行 ──")
        n = 0
        for ln in lines:
            body = ln.split("Z ", 1)[-1] if ln[:4].isdigit() else ln
            if any(k in body for k in keys):
                if "CoreData: error" in body or "Failed to stat" in body:
                    continue
                t = body.strip()[:220]
                if t in shown:
                    continue
                shown.add(t)
                print("   ", t)
                n += 1
                if n >= 80:
                    print("    …（已截断）")
                    break


if __name__ == "__main__":
    main()
