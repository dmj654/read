#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""挑选可用的 iPhone / iPad 模拟器，输出可直接 eval 的 shell 变量。

用法：
    eval "$(python3 scripts/pick_simulators.py)"
    echo "$IPHONE_ID $IPAD_ID"

可选：
    python3 scripts/pick_simulators.py --list          # 人读列表
    python3 scripts/pick_simulators.py --json dev.json # 从已保存的 simctl JSON 解析（离线自测用）
    python3 scripts/pick_simulators.py --prefer-max    # 改为「最新 runtime 优先」

选型规则（默认）：在**满足部署目标 iOS 17.0** 的 runtime 里取**最低**的那个，同 runtime 下按设备名
升序取第一个 iPhone 与第一个 iPad。

为什么默认取最低而不是最新：本工程部署目标是 iOS 17，验收应当尽量贴近下限；更关键的是，
模拟器 runtime 越新、与工程声明的工具链差得越远，越容易踩到与新系统绑定、与本工程无关的
运行时问题（例如曾遇到的 iOS 26 模拟器上 JavaScriptCore 在 `evaluateScript` 处 SIGSEGV）。
团队踩过的坑：默认取最新会挑到 iOS 26.x，把一次无关的系统行为变化误判成业务缺陷。
"""

import json
import subprocess
import sys


def load_devices(json_path=None):
    if json_path:
        with open(json_path, "r", encoding="utf-8") as handle:
            return json.load(handle)

    proc = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "available", "-j"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr or "xcrun simctl 执行失败\n")
        sys.exit(1)
    return json.loads(proc.stdout)


def runtime_version(runtime_id):
    """com.apple.CoreSimulator.SimRuntime.iOS-17-5 -> (17, 5)"""
    tail = runtime_id.rsplit(".", 1)[-1]
    if not tail.startswith("iOS-"):
        return (0, 0)
    parts = tail[4:].split("-")
    numbers = []
    for part in parts:
        try:
            numbers.append(int(part))
        except ValueError:
            numbers.append(0)
    return tuple(numbers)


def main():
    args = sys.argv[1:]
    json_path = None
    if "--json" in args:
        index = args.index("--json")
        json_path = args[index + 1]
        del args[index:index + 2]
    want_list = "--list" in args

    data = load_devices(json_path)

    candidates = []
    for runtime_id, devices in data.get("devices", {}).items():
        if "iOS" not in runtime_id:
            continue
        version = runtime_version(runtime_id)
        for device in devices:
            if not device.get("isAvailable", True):
                continue
            candidates.append((version, device.get("name", ""), device.get("udid", "")))

    # 默认：在满足部署目标（iOS 17.0）的 runtime 中取最低者。
    # 有意不用「最新 runtime 优先」——那会把镜像里预装的 iOS 26 模拟器选出来，
    # 与工程声明的 iOS 17 工具链相差 9 个大版本，验收结果不再能代表真实用户环境。
    min_version = (17, 0)
    eligible = [c for c in candidates if c[0] >= min_version]
    if not eligible:
        sys.stderr.write(
            "未找到 iOS 17.0 及以上的可用模拟器，退化为全部可用 runtime 中最新的一个\n"
        )
        eligible = candidates

    # 低版本优先，其次设备名字典序
    eligible.sort(key=lambda item: (item[0][0], item[0][1], item[1]))
    if "--prefer-max" in args:
        # 反向优先：强制在新系统上做兼容性验证时使用
        eligible.sort(key=lambda item: (-item[0][0], -item[0][1], item[1]))
    candidates = eligible

    if not candidates:
        sys.stderr.write("未找到任何可用 iOS 模拟器；请先安装 iOS runtime：xcrun simctl list runtimes\n")
        return 1

    if want_list:
        for version, name, udid in candidates:
            print("iOS %s\t%s\t%s" % (".".join(str(v) for v in version), name, udid))
        return 0

    def pick(prefix):
        for version, name, udid in candidates:
            if name.startswith(prefix):
                return version, name, udid
        return None

    iphone = pick("iPhone")
    ipad = pick("iPad")

    if iphone is None:
        sys.stderr.write("未找到可用 iPhone 模拟器\n")
        return 1
    if ipad is None:
        sys.stderr.write("未找到可用 iPad 模拟器；iPad 验证需要至少一个 iPad 设备，可用 xcrun simctl create 创建\n")
        return 1

    def quote(value):
        return "'" + value.replace("'", "'\\''") + "'"

    print("IPHONE_ID=%s" % quote(iphone[2]))
    print("IPHONE_NAME=%s" % quote(iphone[1]))
    print("IPHONE_RUNTIME=%s" % quote(".".join(str(v) for v in iphone[0])))
    print("IPAD_ID=%s" % quote(ipad[2]))
    print("IPAD_NAME=%s" % quote(ipad[1]))
    print("IPAD_RUNTIME=%s" % quote(".".join(str(v) for v in ipad[0])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
