#!/usr/bin/env bash
#
# P0.23 测试基线与覆盖率运行器（单目的地，历史基线脚本）
#
# ⚠️ 已被 scripts/acceptance.sh 取代：后者覆盖 iPhone + iPad 双目的地、覆盖率门槛判定
#    与工程文件合规校验，并自动挑选可用模拟器（不再硬编码 OS=17.0）。
#    本脚本仅保留用于复现 P0 基线，新流程请执行：bash scripts/acceptance.sh
#
# 在 iOS 17 模拟器上跑全量测试，并产出 RuleEngine / NetworkService 的覆盖率报告。
# 用法：bash scripts/run_tests.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."

DERIVED="DerivedData"
RESULT="$PWD/Result.xcresult"

rm -rf "$DERIVED" "$RESULT"

echo "==> xcodebuild test (scheme ReadingApp, iOS 17 Simulator, coverage on)"
xcodebuild test \
  -scheme ReadingApp \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.0' \
  -derivedDataPath "$DERIVED" \
  -resultBundlePath "$RESULT" \
  -enableCodeCoverage YES \
  -quiet

echo "==> Coverage (all targets)"
xcrun xccov view --report "$RESULT" || true

echo "==> Done. P0 基线测试通过（退出码 0 即绿）。"
