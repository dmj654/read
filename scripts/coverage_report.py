#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从 xcresult 中读取代码覆盖率并输出可读报告。

用法：
    python3 scripts/coverage_report.py build/reports/Result-iPhone.xcresult
    python3 scripts/coverage_report.py Result.xcresult --threshold 0.60
    python3 scripts/coverage_report.py Result.xcresult --json-out coverage.json

参数：
    --threshold <0-1>   应用目标整体行覆盖率低于该值时以退出码 1 结束（默认 0 = 不设门槛）
    --json-out <path>   同时把原始 xccov JSON 落盘，便于归档或二次分析

退出码：0 达标；1 未达标或读取失败。
"""

import json
import subprocess
import sys

# 关注清单：这些文件是解析/网络/同步/下载等核心逻辑，覆盖率应显著高于视图层
WATCHLIST = [
    "RuleEngine.swift",
    "Services.swift",
    "WebDAVClient.swift",
    "SyncService.swift",
    "SyncModels.swift",
    "CredentialStore.swift",
    "ComicSourceService.swift",
    "ComicContainer.swift",
    "DownloadManager.swift",
    "DownloadQueue.swift",
    "ReaderPagination.swift",
    "DesignSystem.swift",
]


def run_xccov(result_path):
    proc = subprocess.run(
        ["xcrun", "xccov", "view", "--report", "--json", result_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr or "xcrun xccov 执行失败\n")
        return None
    try:
        return json.loads(proc.stdout)
    except ValueError as error:
        sys.stderr.write("无法解析 xccov JSON：%s\n" % error)
        return None


def percent(value):
    return "%.1f%%" % (value * 100.0)


def main():
    args = sys.argv[1:]
    if not args:
        sys.stderr.write(__doc__)
        return 2

    threshold = 0.0
    json_out = None
    report_in = None
    if "--threshold" in args:
        index = args.index("--threshold")
        threshold = float(args[index + 1])
        del args[index:index + 2]
    if "--json-out" in args:
        index = args.index("--json-out")
        json_out = args[index + 1]
        del args[index:index + 2]
    if "--report-json" in args:
        # 直接从已保存的 xccov JSON 生成报告（离线复盘 / CI 归档后二次分析）
        index = args.index("--report-json")
        report_in = args[index + 1]
        del args[index:index + 2]

    result_path = args[0] if args else ""
    if report_in:
        with open(report_in, "r", encoding="utf-8") as handle:
            report = json.load(handle)
        print("读取已保存的覆盖报告：%s" % report_in)
    else:
        report = run_xccov(result_path)
    if report is None:
        return 1

    if json_out:
        with open(json_out, "w", encoding="utf-8") as handle:
            json.dump(report, handle, ensure_ascii=False, indent=2)
        print("原始覆盖数据已写入：%s" % json_out)

    targets = report.get("targets", [])
    if not targets:
        sys.stderr.write("报告中没有任何 target，测试可能未真正执行\n")
        return 1

    print("")
    print("== 各 Target 行覆盖率 ==")
    for target in targets:
        print("  %-28s %s  (%d/%d 行)" % (
            target.get("name", "?"),
            percent(target.get("lineCoverage", 0.0)),
            target.get("coveredLines", 0),
            target.get("executableLines", 0),
        ))

    app_target = None
    for target in targets:
        name = target.get("name", "")
        if "Tests" in name or "xctest" in name:
            continue
        if name.startswith("ReadingApp"):
            app_target = target
            break

    if app_target is None:
        sys.stderr.write("未在报告里找到应用主 target（ReadingApp），无法计算整体覆盖率\n")
        return 1

    files = app_target.get("files", [])
    overall = app_target.get("lineCoverage", 0.0)

    print("")
    print("== 应用整体覆盖率 ==")
    print("  %s  (%d/%d 行)" % (
        percent(overall),
        app_target.get("coveredLines", 0),
        app_target.get("executableLines", 0),
    ))

    by_name = {}
    for item in files:
        by_name[item.get("name", "")] = item

    print("")
    print("== 核心逻辑关注清单 ==")
    for name in WATCHLIST:
        item = by_name.get(name)
        if item is None:
            print("  %-26s 未出现在报告中（可能未参与编译或已被裁剪）" % name)
            continue
        print("  %-26s %s  (%d/%d 行)" % (
            name,
            percent(item.get("lineCoverage", 0.0)),
            item.get("coveredLines", 0),
            item.get("executableLines", 0),
        ))

    testable = [f for f in files if (f.get("executableLines") or 0) >= 20]
    testable.sort(key=lambda f: f.get("lineCoverage", 0.0))
    print("")
    print("== 覆盖率最低的 10 个文件（可执行行 ≥ 20）==")
    for item in testable[:10]:
        print("  %-34s %s  (%d/%d 行)" % (
            item.get("name", "?"),
            percent(item.get("lineCoverage", 0.0)),
            item.get("coveredLines", 0),
            item.get("executableLines", 0),
        ))

    print("")
    if threshold > 0:
        if overall + 1e-9 < threshold:
            print("== 结论：整体覆盖率 %s 低于门槛 %s ==" % (percent(overall), percent(threshold)))
            return 1
        print("== 结论：整体覆盖率 %s，达到门槛 %s ==" % (percent(overall), percent(threshold)))
    else:
        print("== 结论：覆盖率报告已生成（未设门槛）==")
    return 0


if __name__ == "__main__":
    sys.exit(main())
