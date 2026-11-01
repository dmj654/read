# 开源阅读 · iOS

对标 Android「开源阅读 Legado」的 iOS 原生阅读器：**小说 + 漫画统一书架**，Swift + SwiftUI 编写，iOS 17+，本地优先，无账号、无追踪、无内置内容。

- 纯工具属性：App 不提供任何书籍内容，全部内容来自你自行导入或添加的书源规则。
- 数据本地优先：书架、进度、书源、下载记录全部保存在设备上（SwiftData / 文件系统）。
- 可选自建同步：通过你自己的 WebDAV / NAS 在多设备间同步「进度 + 书源 + 设置」，密码只进系统钥匙串。
- 兼容 Legado 书源规则格式，可直接导入现成书源 JSON。

> **想直接装到手机上用？** 推代码到 GitHub，Actions 会自动跑测试并打出**已签名的 Development IPA**，下载后即可装到已登记 UDID 的设备。
> 证书与 Secrets 配置见 **[docs/签名打包与证书配置.md](docs/签名打包与证书配置.md)**；没有开发者账号时也可改成未签名构建 + Sideloadly 本地签名，见 **[docs/交付与安装指南.md](docs/交付与安装指南.md)**。

---

## 功能概览

| 模块 | 能力 |
| --- | --- |
| 书架 | 网格 / 列表双视图、搜索过滤、小说与漫画混排并带类型徽标 |
| 发现 | 关键词跨书源聚合搜索 → 书籍详情 → 一键入架 |
| 书源 | 导入 / 启用停用 / 删除 Legado 规则（搜索、详情、目录、正文、图片页） |
| 小说阅读 | 目录切换、正文分页、翻页与进度、字号随系统 Dynamic Type 缩放 |
| 漫画阅读 | 单页 / 双页 / 卷轴三种模式、大图分块渲染（CATiledLayer）、亮度与增强、广告页过滤 |
| 下载 | 后台 URLSession 断点续传、暂停/继续/清理、进程重启后续传 |
| 同步 | WebDAV / NAS，最后写入胜出合并 + 版本单调递增 + 本地双写备份 |
| 无障碍 | VoiceOver 全主流程覆盖、Reduce Motion、Dynamic Type、语义色适配深色模式 |
| 多端 | iPhone 标签栏 / iPad 侧边栏多列自适应，支持 iPad 多任务与台前调度 |

---

## 环境要求

- Xcode 15 及以上
- iOS 17.0 及以上（SwiftData / `@Observable` 依赖）
- Swift 5.9

依赖通过 Swift Package Manager 自动解析：

| 依赖 | 用途 |
| --- | --- |
| [Kanna](https://github.com/tidwall/Kanna) | XPath / CSS 选择器解析 |
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | CBZ / ZIP 漫画容器解包 |
| swift-log | 本地结构化日志 |

PDFKit、SwiftData、JavaScriptCore、Security 等能力直接使用系统框架，无额外依赖。

---

## 构建与测试

```bash
git clone <your-repo-url> ReadingApp
cd ReadingApp
open ReadingApp.xcodeproj
```

> 首次打开请在 *Signing & Capabilities* 中选择你自己的 Team，并把 `PRODUCT_BUNDLE_IDENTIFIER` 从 `com.example.ReadingApp` 改成你自己的标识。

命令行构建与测试：

```bash
# 一体化验收：iPhone + iPad 双目的地全量测试 + 覆盖率 + 工程合规（推荐）
bash scripts/acceptance.sh

# 覆盖率门槛（低于 60% 直接失败）
COVERAGE_THRESHOLD=0.60 bash scripts/acceptance.sh

# 只想跑单个测试类
ONLY_TESTING=ReadingAppTests/P5Tests bash scripts/acceptance.sh
```

也可以逐条执行：

```bash
xcodebuild build -project ReadingApp.xcodeproj -scheme ReadingApp \
  -destination 'platform=iOS Simulator,name=iPhone 15'

xcodebuild test -project ReadingApp.xcodeproj -scheme ReadingApp \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -enableCodeCoverage YES

python3 scripts/check_project.py        # 工程文件合规校验（17 项）
```

完整的四项验收命令清单（含 iPad 目的地、覆盖率门槛、工程合规逐条命令、报错对照表）见
[docs/P5-macOS验收命令清单.md](docs/P5-macOS验收命令清单.md)。

单元测试全部为**零网络**用例：网络层通过 `URLSessionProtocol` 注入桩实现，解析用例走本地 HTML / JSON fixture，不依赖任何真实站点。

---

## 云端自动打包（GitHub Actions）

仓库内置**两条流水线**，互不干扰：

| 文件 | Actions 侧名称 | 触发 | 产物 |
| --- | --- | --- | --- |
| `ci.yml` | `CI` | push main + 手动 | **已签名** Development IPA |
| `ci-unsigned.yml` | `CI (Unsigned)` | 仅手动 | 未签名 IPA（备用，供本地重签） |

签名版流程：

```
Xcode 15.4 + iOS 17 校验 → SPM 缓存 → 工程合规校验
  → 全量测试（iPhone + iPad 双目的地）→ 覆盖率统计
  → 校验签名 Secrets → 导入 .p12 证书 + .mobileprovision 到钥匙串
  → Release Archive（手动签名）→ 导出 Development IPA
  → codesign 严格校验 → 上传制品（保留 30 天）→ 清理临时钥匙串
```

- 运行环境：`macos-14` + Xcode 15.4，目标 iOS 17
- 签名材料全部走 GitHub Secrets：`BUILD_CERTIFICATE_BASE64` / `P12_PASSWORD` / `PROVISIONING_PROFILE_BASE64` / `TEAM_ID`（可选 `BUNDLE_ID`、`PROFILE_SPECIFIER`）
- 产物是**已签名、可直接安装**的 Development IPA（需目标设备 UDID 已登记在描述文件中）
- 制品：`ReadingApp-development-ipa`（安装包）、`ReadingApp-dSYM`（符号表）、`build-reports`（覆盖率 / 合规 / 签名报告）
- 手动触发时可选 `development` / `ad-hoc` / `app-store-connect` 三种导出方式
- 签名链路出问题时可先跑 `CI (Unsigned)`（无需任何证书）拿到未签名包，用 Sideloadly 本地重签验证功能，不阻塞其他工作

| 我想… | 看这份 |
| --- | --- |
| 配证书、配 Secrets、排查签名失败 | **[docs/签名打包与证书配置.md](docs/签名打包与证书配置.md)** |
| 从推代码到装上手机的完整流程 | **[docs/交付与安装指南.md](docs/交付与安装指南.md)** |

---

## 目录结构

```
ReadingApp/                     # 仓库根
├── ReadingApp/                 # App 源码
│   ├── App/                    # 应用入口、AppDelegate（后台下载系统回调桥接）
│   ├── Models/                 # SwiftData 实体：Book / SourceRule / AppSettings / DownloadRecord / SyncConfig
│   ├── Data/                   # PersistenceController（ModelContainer 装配）
│   ├── Parsing/                # RuleEngine（XPath/CSS/正则/JS 沙箱）、SourceImporter
│   ├── Services/               # 网络、搜索、正文、漫画容器与缓存、下载、WebDAV、同步、凭据
│   ├── ViewModels/             # @Observable MVVM 视图模型
│   ├── Views/                  # SwiftUI 视图 + DesignSystem（布局/无障碍/设计令牌）
│   └── PrivacyInfo.xcprivacy   # App Store 隐私清单（零追踪）
├── ReadingAppTests/            # 单元测试（零网络，含 HTML/JSON fixture）
├── ReadingApp.xcodeproj/       # 工程文件 + 共享 scheme
├── scripts/                    # 验收脚本：acceptance / check_project / pick_simulators / coverage_report
├── docs/                       # 开发文档（macOS 验收命令清单等）
├── .github/workflows/          # ci.yml（签名打包）+ ci-unsigned.yml（未签名备用）
├── README.md · PRIVACY.md · LICENSE · CONTRIBUTING.md
```

设计文档与分阶段 TDD 任务清单见同级 `开源阅读iOS版设计/` 目录（P0–P5）。

---

## 隐私

**不采集、不上报、不追踪。** 无账号体系、无三方分析 / 广告 SDK、不读取广告标识符。

- 应用内：设置 →「隐私与开源」→「隐私说明」
- 仓库内：[PRIVACY.md](PRIVACY.md)
- 随包分发：`ReadingApp/PrivacyInfo.xcprivacy`（`NSPrivacyTracking = false`，收集数据类型为空）

---

## 免责声明

本项目仅供技术学习与个人阅读使用。App 不内置、不分发、不托管任何书籍或漫画内容，所有内容均由使用者自行添加的书源从第三方站点获取，版权归原站点与作者所有。请遵守内容提供方的服务条款与所在地法律法规，勿将本工具用于任何侵权或违法用途。

---

## 许可

[MIT](LICENSE)
