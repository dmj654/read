# P5 macOS 本地验收命令清单

> 适用范围：在 macOS（Xcode 15+，iOS 17+ 模拟器）上完成 P0–P5 全量验收，覆盖**四项必检**：全量单元测试、iPhone/iPad 双目的地、代码覆盖率、工程文件合规。
> 所有命令可直接复制到终端执行，且**默认在仓库根目录**（`ReadingApp/`，与 `ReadingApp.xcodeproj` 同级）下运行。
> 配套脚本已随仓库提供：`scripts/acceptance.sh`、`scripts/check_project.py`、`scripts/pick_simulators.py`、`scripts/coverage_report.py`。

---

## 零、先补齐的前置条件（重要）

本次验收前发现并修复了一个会让**全新 clone 直接失败**的问题：仓库原先**没有共享 scheme**（`ReadingApp.xcodeproj` 下只有 `project.pbxproj`）。Xcode 首次打开工程时会自动生成 scheme，但那些 scheme 写在 `xcuserdata/`（不进版本库），所以干净机器上 `xcodebuild -scheme ReadingApp` 会报 *does not contain a scheme named "ReadingApp"*。

现已补入版本库：

```
ReadingApp.xcodeproj/xcshareddata/xcschemes/ReadingApp.xcscheme
```

环境自检（三条，全部有正常输出才继续）：

```bash
xcodebuild -version
xcrun simctl list runtimes | grep iOS
xcodebuild -list -project ReadingApp.xcodeproj
```

`xcodebuild -list` 的 `Schemes:` 段必须出现 `ReadingApp`——这是后续所有命令的前提。

---

## 一、一键跑完四项验收

```bash
bash scripts/acceptance.sh
```

带覆盖率门槛（低于 60% 直接失败）：

```bash
COVERAGE_THRESHOLD=0.60 bash scripts/acceptance.sh
```

只跑某个测试类做快速回归：

```bash
ONLY_TESTING=ReadingAppTests/P5Tests bash scripts/acceptance.sh
```

脚本按顺序执行：环境自检 → iPhone 全量测试（采覆盖率）→ iPad 全量测试 → 覆盖率报告 → 工程合规校验，任一环节失败即以非 0 退出。产物落在 `build/reports/`：

| 文件 | 内容 |
| --- | --- |
| `Result-iPhone.xcresult` | iPhone 目的地全量测试结果（含覆盖率数据） |
| `Result-iPad.xcresult` | iPad 目的地全量测试结果 |
| `coverage-summary.txt` | 分 target 覆盖率 + 核心文件关注清单 + 最低覆盖 Top10 |
| `coverage.json` | `xccov` 原始 JSON，便于归档与二次分析 |
| `project-check.txt` | 工程合规校验明细 + 隐私清单 `plutil` 结果 |

下面四项给出**等价的单条命令**，便于逐项排查或按需拆分执行。

---

## 二、第一项：全量单元测试执行

### 2.1 解析可用模拟器（后续命令复用）

```bash
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

eval "$(python3 scripts/pick_simulators.py)"
echo "iPhone: $IPHONE_NAME [$IPHONE_ID]  iPad: $IPAD_NAME [$IPAD_ID]"
```

脚本自动选取**最新 iOS runtime** 下的第一个 iPhone 与第一个 iPad；想验证「最低支持系统 iOS 17」的兼容性，改用：

```bash
eval "$(python3 scripts/pick_simulators.py --prefer-min)"
```

列出全部候选（含 runtime 与 UDID）：

```bash
python3 scripts/pick_simulators.py --list
```

> 也可以手工指定固定目的地，例如 `-destination 'platform=iOS Simulator,name=iPhone 15,OS=17.0'`。设备名会随 Xcode 版本变化，先查再写更稳：`xcrun simctl list devices available | grep -E "iPhone|iPad"`。

### 2.2 全量测试（iPhone 目的地，采集覆盖率）

```bash
xcodebuild test \
  -project ReadingApp.xcodeproj \
  -scheme ReadingApp \
  -destination "platform=iOS Simulator,id=$IPHONE_ID" \
  -derivedDataPath build/DerivedData \
  -resultBundlePath build/reports/Result-iPhone.xcresult \
  -enableCodeCoverage YES \
  -parallel-testing-enabled NO
```

**预期**：末尾出现 `** TEST SUCCEEDED **`，退出码 0；用例总数覆盖 P0–P5（`ReadingAppTests` 全量）。

### 2.3 冒烟 / 单类 / 跳过

```bash
# 只跑 P5（布局判定 + 无障碍文案，秒级）
xcodebuild test -project ReadingApp.xcodeproj -scheme ReadingApp \
  -destination "platform=iOS Simulator,id=$IPHONE_ID" \
  -only-testing:ReadingAppTests/P5Tests

# 只跑解析与规则引擎（P0/P1 基线）
xcodebuild test -project ReadingApp.xcodeproj -scheme ReadingApp \
  -destination "platform=iOS Simulator,id=$IPHONE_ID" \
  -only-testing:ReadingAppTests/RuleEngineTests \
  -only-testing:ReadingAppTests/ReplaySuiteTests

# 跳过耗时的漫画容器用例
xcodebuild test -project ReadingApp.xcodeproj -scheme ReadingApp \
  -destination "platform=iOS Simulator,id=$IPHONE_ID" \
  -skip-testing:ReadingAppTests/P3ServicesTests
```

### 2.4 查看失败用例

```bash
# Xcode 16+
xcrun xcresulttool get test-results summary --path build/reports/Result-iPhone.xcresult

# Xcode 15
xcrun xcresulttool get --format json --path build/reports/Result-iPhone.xcresult \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(d.get('actions',{}).get('_values',[]), ensure_ascii=False)[:2000])"

# 图形化（推荐）
open build/reports/Result-iPhone.xcresult
```

### 2.5 Release 构建冒烟（可选，抓 Release 专属问题）

```bash
xcodebuild build \
  -project ReadingApp.xcodeproj \
  -scheme ReadingApp \
  -configuration Release \
  -destination "platform=iOS Simulator,id=$IPHONE_ID" \
  CODE_SIGNING_ALLOWED=NO
```

---

## 三、第二项：iPhone / iPad 双目的地验证

### 3.1 iPad 全量测试

```bash
xcodebuild test \
  -project ReadingApp.xcodeproj \
  -scheme ReadingApp \
  -destination "platform=iOS Simulator,id=$IPAD_ID" \
  -derivedDataPath build/DerivedData \
  -resultBundlePath build/reports/Result-iPad.xcresult \
  -parallel-testing-enabled NO
```

**预期**：`** TEST SUCCEEDED **`。iPad idiom 下同一批用例必须与 iPhone 一致全绿——这验证了常规宽度布局相关代码（`LayoutResolver` → `NavigationSplitView`）在 iPad 目标的编译与运行期均无问题。

### 3.2 双目的地一次跑完（单一 `xcodebuild` 调用）

```bash
xcodebuild test \
  -project ReadingApp.xcodeproj \
  -scheme ReadingApp \
  -destination "platform=iOS Simulator,id=$IPHONE_ID" \
  -destination "platform=iOS Simulator,id=$IPAD_ID" \
  -enableCodeCoverage YES \
  -resultBundlePath build/reports/Result-both.xcresult
```

> 注意：多 `-destination` 会并行执行到多个模拟器，`xcresult` 中按设备分 action 记录；排查问题建议仍用上面的分次执行，日志更清晰。

### 3.3 目的地可用性排查

```bash
# 列出该 scheme 支持的全部目的地
xcodebuild -showdestinations -project ReadingApp.xcodeproj -scheme ReadingApp

# 已安装 runtime
xcrun simctl list runtimes

# 若没有 iPad 模拟器，创建一个（示例：iPad Pro 11 英寸 + iOS 17.5）
xcrun simctl create "iPad Pro (11-inch) (4th generation)" \
  "iPad Pro (11-inch) (4th generation)" \
  com.apple.CoreSimulator.SimRuntime.iOS-17-5
```

### 3.4 iPad 适配的构建设置核对

```bash
xcodebuild -showBuildSettings \
  -project ReadingApp.xcodeproj -scheme ReadingApp \
  | grep -E "TARGETED_DEVICE_FAMILY|SUPPORTED_PLATFORMS|IPHONEOS_DEPLOYMENT_TARGET|PRODUCT_BUNDLE_IDENTIFIER|MARKETING_VERSION"
```

**预期**：`TARGETED_DEVICE_FAMILY = 1,2`（iPhone + iPad）、`IPHONEOS_DEPLOYMENT_TARGET = 17.0`。

### 3.5 需人工目视的部分（自动化测不到）

在 iPad 模拟器上启动 App 后逐项确认：

1. 竖屏 → 底部标签栏；横屏/全屏 → 侧边栏 + 详情多列。
2. 从侧边栏切换五个分区，选中态保持、内容随之切换。
3. iPad 分屏（Slide Over / Split View）下宽度落入 compact 时自动回落到标签栏。
4. 书架网格列数随宽度自适应，封面不拉伸变形。
5. 阅读器正文在 iPad 上限制最大行宽（720pt），长行可读。

---

## 四、第三项：代码覆盖率统计

### 4.1 原生 `xccov` 三种视图

```bash
# ① 分 target 汇总
xcrun xccov view --report build/reports/Result-iPhone.xcresult

# ② 只列 target（更紧凑）
xcrun xccov view --report --only-targets build/reports/Result-iPhone.xcresult

# ③ 逐文件明细（路径 + 覆盖行数）
xcrun xccov view --file-list build/reports/Result-iPhone.xcresult

# ④ 精确到行（某单个文件）
xcrun xccov view --archive --file ReadingApp/Parsing/RuleEngine.swift \
  build/reports/Result-iPhone.xcresult
```

### 4.2 结构化报告 + 门槛判定（推荐）

```bash
python3 scripts/coverage_report.py \
  build/reports/Result-iPhone.xcresult \
  --threshold 0.60 \
  --json-out build/reports/coverage.json
```

输出四段：各 Target 覆盖率、应用整体覆盖率、**核心逻辑关注清单**（`RuleEngine` / `WebDAVClient` / `SyncService` / `ComicSourceService` / `DownloadManager` / `ReaderPagination` / `DesignSystem` 等）、**覆盖率最低的 10 个文件**。

退出码语义：`0` 达标（或未设门槛），`1` 低于门槛。

离线复盘（不重跑测试，直接读已归档 JSON）：

```bash
python3 scripts/coverage_report.py --report-json build/reports/coverage.json --threshold 0.60
```

### 4.3 覆盖率基线建议

| 范围 | 建议门槛 | 说明 |
| --- | --- | --- |
| 解析 / 网络 / 同步 / 下载等服务层 | ≥ 80% | 全量有桩单测覆盖，应显著高于视图层 |
| 应用整体 | ≥ 60% | 视图层不计入硬门槛（SwiftUI 声明式 body 难以单测） |
| `Views/*` | 仅记录不设门槛 | 靠人工走查 + VoiceOver 验收 |

> `DesignSystem.swift` 是纯逻辑（`LayoutResolver` / `A11yLabels` / `ReaderMotionPolicy`）与设计令牌混编，覆盖率应接近 100%；若明显偏低，说明 P5 单测没跑到。

---

## 五、第四项：工程文件合规校验

### 5.1 一键校验（17 项）

```bash
python3 scripts/check_project.py
```

**预期**：末行 `== 结论：全部通过 ==`，退出码 0。当前基线 = **17 项全通过**：Section 14/14 成对、BuildFile 67 条、FileReference 76 条、ID 全局唯一 179 个、每个 BuildFile 恰好挂一个构建阶段、每个 FileReference 恰好归一个分组、磁盘文件 74 个全部已注册、注册路径全部存在、隐私清单已挂 Resources、隐私清单合法且零追踪、未声明收集数据类型、设备族含 iPad、DisplayName 已设置、`UIRequiresFullScreen=NO`、共享 scheme 存在、scheme 指向真实 target、scheme 含测试目标。

CI 中转义输出用：

```bash
python3 scripts/check_project.py --quiet
```

### 5.2 手工等价命令（逐条可单独验证）

```bash
# ① Section 数量对等（两行输出应相同）
grep -c "^/\* Begin .* section \*/" ReadingApp.xcodeproj/project.pbxproj
grep -c "^/\* End .* section \*/"   ReadingApp.xcodeproj/project.pbxproj

# ② BuildFile 与 FileReference 条数
grep -c "isa = PBXBuildFile;"          ReadingApp.xcodeproj/project.pbxproj
grep -c "isa = PBXFileReference;"      ReadingApp.xcodeproj/project.pbxproj

# ③ 声明 ID 是否有重复（无输出即通过）
grep -oE "^\t\t[A-Z]{1,2}[0-9A-F]{20,28} /\*" ReadingApp.xcodeproj/project.pbxproj \
  | sort | uniq -d

# ④ 隐私清单语法与内容
plutil -lint ReadingApp/PrivacyInfo.xcprivacy
plutil -p ReadingApp/PrivacyInfo.xcprivacy

# ⑤ iPad 支持与包信息
grep -n "TARGETED_DEVICE_FAMILY\|INFOPLIST_KEY_CFBundleDisplayName\|UIRequiresFullScreen" \
  ReadingApp.xcodeproj/project.pbxproj

# ⑥ 共享 scheme 合法性与内容
xmllint --noout ReadingApp.xcodeproj/xcshareddata/xcschemes/ReadingApp.xcscheme
grep -E "BlueprintIdentifier|BuildableName" ReadingApp.xcodeproj/xcshareddata/xcschemes/ReadingApp.xcscheme

# ⑦ 源码是否全部注册（列出未注册的 .swift，无输出即通过）
python3 scripts/check_project.py --quiet
```

### 5.3 顺手做的静态检查（可选）

```bash
# SwiftLint（未安装则跳过）
brew list swiftlint >/dev/null 2>&1 && swiftlint lint --quiet --path ReadingApp

# 检查是否残留硬编码语义色（P5 后视图层应统一走 Palette）
grep -rn "foregroundStyle(\.red)\|foregroundStyle(\.green)\|foregroundStyle(\.orange)" \
  ReadingApp/Views || echo "无硬编码语义色残留"

# 检查是否残留 iOS 16 旧签名 onChange（形如 `{ newValue in`；正确写法是 `{ _ in` 或 `{ _, new in`）
grep -rn "onChange(of: [^)]*) { [a-zA-Z]" ReadingApp || echo "无旧签名 onChange 残留"

# 检查强解包与 try! 等风险写法
grep -rn "try! \|as! " ReadingApp --include=*.swift || echo "无 try! / as! 强解包"
```

---

## 六、第五项（可选）：本地复现 CI 的 Archive + IPA 打包

CI 在测试通过后会打 Release 包并产出**未签名 IPA**。想在本机复现同一产物，按下面三步执行。

### 6.1 Release Archive（关闭代码签名）

```bash
xcodebuild archive \
  -project ReadingApp.xcodeproj \
  -scheme ReadingApp \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/ReadingApp.xcarchive \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="" \
  DEVELOPMENT_TEAM=""
```

### 6.2 打包成 IPA（Payload 直压）

```bash
APP_PATH="build/ReadingApp.xcarchive/Products/Applications/ReadingApp.app"

rm -rf build/ipa && mkdir -p build/ipa/Payload
cp -R "$APP_PATH" build/ipa/Payload/
( cd build/ipa && zip -qry ../ReadingApp-unsigned.ipa Payload )

unzip -l build/ReadingApp-unsigned.ipa > build/ipa-listing.txt
grep -qE "Payload/ReadingApp\.app/ReadingApp[[:space:]]*$" build/ipa-listing.txt \
  && echo "IPA 结构校验通过"
ls -lh build/ReadingApp-unsigned.ipa
```

### 6.3 校验与安装边界

```bash
# 检查架构与签名状态
lipo -info "build/ReadingApp.xcarchive/Products/Applications/ReadingApp.app/ReadingApp"
codesign -dv --verbose=2 "build/ReadingApp.xcarchive/Products/Applications/ReadingApp.app" 2>&1 | head
```

| 用途 | 未签名 IPA 是否可用 |
| --- | --- |
| CI 交付验证、体积/结构核对 | ✅ 可用 |
| 二次签名后装真机（Sideloadly / AltStore / 企业重签） | ✅ 可用 |
| 直接安装到未越狱真机 | ❌ 不可用（缺签名） |
| 提交 App Store / TestFlight | ❌ 不可用（需 `-exportArchive` + 证书 + 描述文件） |

> 需要「已签名 IPA + 正规导出」时，按 `.github/workflows/ci.yml` 中被注释掉的「导入证书 → `xcodebuild -exportArchive`」两步配置 Secrets（`BUILD_CERTIFICATE_BASE64` / `P12_PASSWORD` / `PROVISIONING_PROFILE_BASE64` / `DEVELOPMENT_TEAM`）即可启用。

---

## 附录 A：本次验收预期基线

| 项目 | 预期 |
| --- | --- |
| iPhone 全量测试 | `TEST SUCCEEDED`，退出码 0 |
| iPad 全量测试 | `TEST SUCCEEDED`，退出码 0（用例数与 iPhone 相同） |
| 应用整体覆盖率 | ≥ 60%（服务层 ≥ 80%） |
| 工程合规校验 | 17 项全通过，退出码 0 |
| 隐私清单 | `plutil -lint` 输出 `OK`，`NSPrivacyTracking = false` |
| 设备族 | `TARGETED_DEVICE_FAMILY = 1,2` |

---

## 附录 B：常见报错对照表

| 报错 | 原因 | 处理 |
| --- | --- | --- |
| `does not contain a scheme named "ReadingApp"` | 共享 scheme 缺失，或未在仓库根目录执行 | 确认 `ReadingApp.xcodeproj/xcshareddata/xcschemes/ReadingApp.xcscheme` 存在；`pwd` 应为仓库根 |
| `resultBundlePath ... already exists` | 上一次产物未清理 | `rm -rf build/reports/*.xcresult` 后重跑 |
| `Unable to find a destination matching` | 设备名与当前 Xcode 不匹配 | 用 `-destination ...id=$IPHONE_ID`，或先 `xcrun simctl list devices available` |
| `未找到可用 iPad 模拟器` | 只装了 iPhone device set | 按 §3.3 用 `xcrun simctl create` 创建 |
| 覆盖率为 0% / 报告无 target | 测试未真正执行，或未开 `-enableCodeCoverage YES` | 先看 `xcresult` 里是否有 test action |
| `xcrun xccov` 报 JSON 解析失败 | Xcode 版本差异导致字段变化 | 用 `scripts/coverage_report.py --report-json` 读已存 JSON 排错 |
| 合规校验报「磁盘文件全部已注册」失败 | 新增 Swift 文件后忘记在 Xcode/target 里加 | 在 Xcode 中「Add Files to ReadingApp」勾选对应 target，或按现有 `F/B` 编号规律补 `project.pbxproj` |
| 合规校验报「注册路径全部存在」失败 | pbxproj 引用了已删除的文件 | 删除失效 FileReference 及其 BuildFile |
| `plutil` 报 `Unexpected character` | 隐私清单被编辑器写成非 XML 或含非法转义 | 用 `plutil -lint` 定位行号后修正 |

---

## 附录 C：本轮新增的验收工具

| 文件 | 作用 |
| --- | --- |
| `scripts/acceptance.sh` | 四项验收一体化执行，产物统一落 `build/reports/` |
| `scripts/check_project.py` | pbxproj 结构与引用闭环、资源挂载、隐私清单、共享 scheme 共 17 项校验 |
| `scripts/pick_simulators.py` | 自动挑选 iPhone/iPad 模拟器，输出可 `eval` 的 shell 变量；支持 `--prefer-min`、`--list`、`--json` |
| `scripts/coverage_report.py` | 覆盖率分 target / 关注清单 / 最低覆盖 Top10，支持 `--threshold` 门槛与 `--json-out` / `--report-json` |
| `ReadingApp.xcodeproj/xcshareddata/xcschemes/ReadingApp.xcscheme` | 共享 scheme（修复干净 clone 无法 `xcodebuild -scheme` 的问题） |
| `.github/workflows/ci.yml` | CI 全流程：合规校验（快速失败）→ `acceptance.sh`（双目的地测试 + 覆盖率）→ Release Archive（关闭签名）→ 导出未签名 IPA → 上传制品（保留 30 天） |
| `docs/交付与安装指南.md` | 从推代码 → 触发 Actions → 下载 IPA → Windows 用 Sideloadly 安装（含 7 天重签说明、打包失败排查）的端到端操作手册 |
