#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""工程文件合规校验（P5.6）。

校验 `ReadingApp.xcodeproj/project.pbxproj` 与 `xcshareddata/xcschemes/` 的结构完整性，
避免「文件写了但没注册」「注册了但文件不存在」「ID 重复导致 Xcode 打开报错」这类隐性问题。

用法：
    python3 scripts/check_project.py            # 校验并打印明细
    python3 scripts/check_project.py --quiet    # 只打印失败项与总结

退出码：0 = 全部通过；1 = 存在失败项。
仅依赖 Python 标准库，macOS 自带 /usr/bin/python3 可直接运行。
"""

import os
import plistlib
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT_DIR = os.path.join(ROOT, "ReadingApp.xcodeproj")
PBX_PATH = os.path.join(PROJECT_DIR, "project.pbxproj")
SCHEME_PATH = os.path.join(PROJECT_DIR, "xcshareddata", "xcschemes", "ReadingApp.xcscheme")
SOURCE_DIRS = ["ReadingApp", "ReadingAppTests"]

FAILURES = []
QUIET = "--quiet" in sys.argv[1:]


def check(name, ok, detail=""):
    if ok:
        if not QUIET:
            print("  [ OK ] " + name)
    else:
        print("  [FAIL] " + name + (("  ->  " + detail) if detail else ""))
        FAILURES.append(name)
    return ok


def read_text(path):
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read()


def main():
    print("== 工程文件合规校验 ==")
    print("工程：%s" % PBX_PATH)

    if not os.path.isfile(PBX_PATH):
        print("  [FAIL] project.pbxproj 不存在")
        return 1
    text = read_text(PBX_PATH)

    # 1) Section 完整性
    begins = re.findall(r"/\* Begin (\w+) section \*/", text)
    ends = re.findall(r"/\* End (\w+) section \*/", text)
    check(
        "Section 成对出现（Begin %d / End %d）" % (len(begins), len(ends)),
        len(begins) == len(ends) and sorted(begins) == sorted(ends),
        "缺失或多余：%s" % (set(begins) ^ set(ends)),
    )

    # 2) BuildFile -> FileReference 闭环
    build_files = re.findall(
        r"^\t\t(B[0-9A-F]{20,28}) /\* (.+?) \*/ = \{isa = PBXBuildFile; fileRef = (F[0-9A-F]{20,28})",
        text,
        re.M,
    )
    file_refs = {}
    for ref_id, name, path in re.findall(
        r"^\t\t(F[0-9A-F]{20,28}) /\* (.+?) \*/ = \{isa = PBXFileReference;[^}]*?path = ([^;]+);",
        text,
        re.M,
    ):
        file_refs[ref_id] = path.strip().strip('"')

    check(
        "BuildFile 共 %d 条，FileReference 共 %d 条" % (len(build_files), len(file_refs)),
        len(build_files) > 0 and len(file_refs) > 0,
        "解析为 0，正则可能已过期",
    )

    dangling = [(bid, name) for bid, name, fid in build_files if fid not in file_refs]
    check("每个 BuildFile 都指向已声明的 FileReference", not dangling, str(dangling))

    # 3) ID 唯一性（仅声明行；分组成员行以 4 个制表符缩进，不会被误匹配）
    declared = re.findall(r"^\t\t([A-Z]{1,2}[0-9A-F]{20,28}) /\* [^*]* \*/ = \{", text, re.M)
    seen = {}
    for ident in declared:
        seen[ident] = seen.get(ident, 0) + 1
    duplicates = sorted([k for k, v in seen.items() if v > 1])
    check("声明 ID 全局唯一（共 %d 个）" % len(seen), not duplicates, str(duplicates))

    # 4) 每个 BuildFile 恰好进一个构建阶段；每个 FileReference 恰好进一个分组
    bad_phase = []
    for bid, name, _ in build_files:
        if len(re.findall(r"\b" + bid + r" /\* [^*]+ \*/,\n", text)) != 1:
            bad_phase.append(name)
    check("每个 BuildFile 恰好挂载到一个构建阶段", not bad_phase, str(bad_phase))

    bad_group = []
    for fid, path in file_refs.items():
        if len(re.findall(r"\b" + fid + r" /\* [^*]+ \*/,\n", text)) != 1:
            bad_group.append(path)
    check("每个 FileReference 恰好归属一个分组", not bad_group, str(bad_group))

    # 5) 磁盘文件 <-> 工程注册 双向一致
    on_disk = set()
    for sub in SOURCE_DIRS:
        base = os.path.join(ROOT, sub)
        for dirpath, _, filenames in os.walk(base):
            for filename in filenames:
                on_disk.add(filename)
    registered = set(file_refs.values())

    unregistered = sorted(f for f in on_disk if f not in registered)
    check(
        "磁盘文件全部已注册（%d 个）" % len(on_disk),
        not unregistered,
        "未注册：%s" % unregistered,
    )

    stale = sorted(
        p for p in registered
        if p not in on_disk and not p.endswith((".app", ".xctest"))  # 产物引用不落在源码目录
    )
    check("注册路径全部存在", not stale, "失效引用：%s" % stale)

    # 6) 隐私清单挂载
    check(
        "PrivacyInfo.xcprivacy 已挂载到 Resources 构建阶段",
        "PrivacyInfo.xcprivacy in Resources" in text,
        "资源阶段缺少该条目，App Store 隐私清单不会随包分发",
    )
    privacy_path = os.path.join(ROOT, "ReadingApp", "PrivacyInfo.xcprivacy")
    if os.path.isfile(privacy_path):
        try:
            with open(privacy_path, "rb") as handle:
                manifest = plistlib.load(handle)
            check(
                "PrivacyInfo.xcprivacy 是合法 plist 且声明零追踪",
                manifest.get("NSPrivacyTracking") is False,
                "NSPrivacyTracking 必须为 false",
            )
            check(
                "隐私清单未声明收集任何数据类型",
                manifest.get("NSPrivacyCollectedDataTypes") == [],
                "若确需收集，请同步更新 PRIVACY.md 与应用内隐私页",
            )
        except Exception as error:  # noqa: BLE001
            check("PrivacyInfo.xcprivacy 可被解析", False, str(error))
    else:
        check("PrivacyInfo.xcprivacy 文件存在", False, privacy_path)

    # 7) iPad 适配构建设置
    target_family = re.findall(r'TARGETED_DEVICE_FAMILY = "?([0-9,]+)"?;', text)
    check(
        'TARGETED_DEVICE_FAMILY 含 iPhone 与 iPad（"1,2"）',
        target_family and all("1" in v.split(",") and "2" in v.split(",") for v in target_family),
        str(target_family),
    )
    check(
        "CFBundleDisplayName 在 Debug/Release 均已设置",
        text.count("INFOPLIST_KEY_CFBundleDisplayName") == 2,
        "出现 %d 次，应为 2 次" % text.count("INFOPLIST_KEY_CFBundleDisplayName"),
    )
    check(
        "UIRequiresFullScreen = NO（支持 iPad 多任务）",
        "INFOPLIST_KEY_UIRequiresFullScreen = NO;" in text,
        "缺失该设置会禁用 iPad 分屏/台前调度",
    )

    # 8) 共享 scheme
    if not os.path.isfile(SCHEME_PATH):
        check("共享 scheme 存在", False, SCHEME_PATH + " 缺失，xcodebuild -scheme 将失败")
    else:
        scheme = read_text(SCHEME_PATH)
        section = re.search(
            r"/\* Begin PBXNativeTarget section \*/(.*?)/\* End PBXNativeTarget section \*/",
            text,
            re.S,
        )
        target_id_set = set(
            re.findall(r"^\t\t(T[0-9A-F]{20,28}) /\*", section.group(1) if section else "", re.M)
        )
        scheme_ids = set(re.findall(r'BlueprintIdentifier = "([^"]+)"', scheme))
        check("共享 scheme 存在（ReadingApp.xcscheme）", True)
        check(
            "scheme 的 BlueprintIdentifier 均指向真实 target",
            bool(scheme_ids) and scheme_ids.issubset(target_id_set),
            "scheme=%s / targets=%s" % (sorted(scheme_ids), sorted(target_id_set)),
        )
        check(
            "scheme 包含测试目标 ReadingAppTests",
            "ReadingAppTests.xctest" in scheme,
            "缺少测试目标时 xcodebuild test 无事可做",
        )

    # 总结
    total = len(FAILURES)
    print("")
    if total == 0:
        print("== 结论：全部通过 ==")
        return 0
    print("== 结论：%d 项失败 ==" % total)
    for name in FAILURES:
        print("   - " + name)
    return 1


if __name__ == "__main__":
    sys.exit(main())
