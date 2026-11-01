#!/usr/bin/env bash
#
# P5 macOS 本地验收 · 一体化脚本
#
# 一次跑完四项验收：
#   1) 全量单元测试（iPhone 目的地，采集覆盖率）
#   2) 全量单元测试（iPad 目的地，验证 iPad target 可构建且用例全绿）
#   3) 覆盖率统计（分 target / 核心文件关注清单 / 最低覆盖文件 Top10）
#   4) 工程文件合规校验（pbxproj 结构、引用闭环、资源挂载、隐私清单、共享 scheme）
#
# 用法：
#   bash scripts/acceptance.sh
#   COVERAGE_THRESHOLD=0.60 bash scripts/acceptance.sh      # 覆盖率低于 60% 视为失败
#   ONLY_TESTING=ReadingAppTests/P5Tests bash scripts/acceptance.sh   # 只跑某个测试类
#
# 产物：
#   build/reports/Result-iPhone.xcresult
#   build/reports/Result-iPad.xcresult
#   build/reports/coverage-summary.txt
#   build/reports/project-check.txt
#
set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="ReadingApp"
PROJECT="ReadingApp.xcodeproj"
DERIVED="build/DerivedData"
OUT="build/reports"
COVERAGE_THRESHOLD="${COVERAGE_THRESHOLD:-0}"

ONLY_ARGS=()
if [[ -n "${ONLY_TESTING:-}" ]]; then
  ONLY_ARGS=(-only-testing:"${ONLY_TESTING}")
fi

step()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
fatal() { printf '\033[31m[失败] %s\033[0m\n' "$*" >&2; exit 1; }
ok()    { printf '\033[32m[通过] %s\033[0m\n' "$*"; }

# ---------------------------------------------------------------- 0. 环境自检
step "0/4 环境自检"

command -v xcodebuild >/dev/null 2>&1 || fatal "未找到 xcodebuild：请安装 Xcode 并执行 sudo xcode-select -s /Applications/Xcode.app"
xcodebuild -version
echo ""

xcrun simctl list runtimes | grep -E "iOS" || fatal "未安装任何 iOS 模拟器 runtime"

xcodebuild -list -project "$PROJECT" > /dev/null 2>&1 || fatal "读取工程失败：确认在仓库根目录、且 $PROJECT 完整"

SIM_ENV="$(python3 scripts/pick_simulators.py)" || fatal "无法自动挑选模拟器，请检查上方输出"
eval "$SIM_ENV"

echo ""
echo "iPhone 目的地：$IPHONE_NAME (iOS $IPHONE_RUNTIME)  [$IPHONE_ID]"
echo "iPad   目的地：$IPAD_NAME (iOS $IPAD_RUNTIME)  [$IPAD_ID]"

rm -rf "$OUT"
mkdir -p "$OUT"

# ------------------------------------------------- 1. 全量测试 · iPhone
step "1/4 全量单元测试 · iPhone（--enableCodeCoverage YES）"

xcodebuild test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$IPHONE_ID" \
  -derivedDataPath "$DERIVED" \
  -resultBundlePath "$OUT/Result-iPhone.xcresult" \
  -enableCodeCoverage YES \
  -parallel-testing-enabled NO \
  ${ONLY_ARGS[@]+"${ONLY_ARGS[@]}"} \
  -quiet \
  || fatal "iPhone 目的地测试失败：用 Xcode 打开 $OUT/Result-iPhone.xcresult 查看失败用例"

ok "iPhone 目的地全量测试通过"

# ------------------------------------------------- 2. 全量测试 · iPad
step "2/4 全量单元测试 · iPad（验证 iPad idiom 下可构建、用例全绿）"

xcodebuild test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$IPAD_ID" \
  -derivedDataPath "$DERIVED" \
  -resultBundlePath "$OUT/Result-iPad.xcresult" \
  -enableCodeCoverage NO \
  -parallel-testing-enabled NO \
  ${ONLY_ARGS[@]+"${ONLY_ARGS[@]}"} \
  -quiet \
  || fatal "iPad 目的地测试失败：用 Xcode 打开 $OUT/Result-iPad.xcresult 查看失败用例"

ok "iPad 目的地全量测试通过（横向/常规宽度布局相关代码在 iPad idiom 下无编译或运行期问题）"

# ------------------------------------------------- 3. 覆盖率
step "3/4 代码覆盖率统计"

if ! python3 scripts/coverage_report.py \
      "$OUT/Result-iPhone.xcresult" \
      --threshold "$COVERAGE_THRESHOLD" \
      --json-out "$OUT/coverage.json" \
      | tee "$OUT/coverage-summary.txt"; then
  fatal "覆盖率未达到门槛（COVERAGE_THRESHOLD=$COVERAGE_THRESHOLD），详见 $OUT/coverage-summary.txt"
fi

# ------------------------------------------------- 4. 工程合规
step "4/4 工程文件合规校验"

if ! python3 scripts/check_project.py | tee "$OUT/project-check.txt"; then
  fatal "工程文件合规校验未通过，详见 $OUT/project-check.txt"
fi

if command -v plutil >/dev/null 2>&1; then
  plutil -lint ReadingApp/PrivacyInfo.xcprivacy | tee -a "$OUT/project-check.txt" \
    || fatal "PrivacyInfo.xcprivacy 不是合法 plist"
fi

# ------------------------------------------------- 总结
step "验收结论：四项全部通过"
echo "  Result（iPhone） : $OUT/Result-iPhone.xcresult"
echo "  Result（iPad）   : $OUT/Result-iPad.xcresult"
echo "  覆盖率报告        : $OUT/coverage-summary.txt"
echo "  合规校验报告      : $OUT/project-check.txt"
echo ""
echo "提示：xccov 明细可用  xcrun xccov view --report $OUT/Result-iPhone.xcresult"
echo "      Xcode 图形化     open $OUT/Result-iPhone.xcresult"
