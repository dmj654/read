# 贡献指南 / Contributing

感谢你愿意参与「开源阅读 · iOS」。本项目以 MIT 许可开源，欢迎 Issue 与 Pull Request。

---

## 一、开始之前

1. 先搜索现有 [Issue](../../issues)，避免重复提交。
2. 较大的功能或架构改动，请先开 Issue 描述动机与方案，达成一致后再动手，避免白做。
3. **请勿在仓库、Issue、PR 中提交任何书源规则文件或书源集合。** 书源属于用户自行维护的数据，随仓库分发会带来版权与合规风险。

---

## 二、开发环境

- macOS + Xcode 15 及以上
- iOS 17.0 模拟器或真机
- Swift 5.9

```bash
git clone <your-repo-url> ReadingApp
cd ReadingApp
open ReadingApp.xcodeproj
```

首次打开请在 *Signing & Capabilities* 里选择自己的 Team，并将 `PRODUCT_BUNDLE_IDENTIFIER` 改为你自己的标识（默认 `com.example.ReadingApp`）。

---

## 三、代码规范

### 分层

严格遵守既有 MVVM 模块边界，不新建并行体系：

```
Views → ViewModels → Services → Models/Data
```

- `Views/`：只做展示与交互，不写解析逻辑、不直接发网络请求。
- `ViewModels/`：`@Observable`，持有状态与动作，可被单测直接实例化。
- `Services/`：无 UI 依赖，全部可注入（`URLSessionProtocol`、`FileStoring`、`CredentialStoring`、`PageDownloading` 等）。
- `Parsing/`：规则引擎，纯函数优先。

### 硬性约定

- 平台最低版本 iOS 17，**不得**引入 iOS 18+ API（`onChange(of:)` 用双参数或 `{ _ in }` 形式）。
- 持久化只走 SwiftData，不混用 CoreData。
- 网络请求统一走 `NetworkService`，不自建 `URLSession`。
- 颜色与间距用 `DesignSystem.swift` 里的 `Palette` / `Spacing`，不硬编码色值。
- 无障碍文案统一用 `A11yLabels` 生成，保证朗读一致性与可测性。
- 密码、Token 只进 Keychain，禁止写库或写日志。

### 风格

- 4 空格缩进；类型与函数用 `///` 文档注释说明「为什么」，而非复述「做了什么」。
- 每个新类型/函数尽量小且单一职责；超过 300 行的文件考虑拆分。
- 提交信息用祈使句，格式建议：`feat(comic): 支持卷轴模式预加载`、`fix(sync): 修正版本号递增`。

---

## 四、测试要求

**所有 PR 必须附带或更新单元测试**，且测试必须零网络、零真实站点依赖。

| 场景 | 做法 |
| --- | --- |
| 网络请求 | 注入实现 `URLSessionProtocol` 的桩，断言 URL / 方法 / Header / Body |
| HTML 解析 | 使用 `ReadingAppTests/Fixtures/` 下的本地 fixture |
| 下载链路 | 使用 `StubDownloadRunner` / `StubPageDownloader` |
| 同步 | 使用 `StubWebDAV` + 内存 `ModelContainer`（`PersistenceController.inMemory()`） |
| 布局 / 无障碍 | 抽纯函数（参考 `LayoutResolver` / `A11yLabels`），直接断言字符串与枚举 |

本地跑测试：

```bash
xcodebuild test -scheme ReadingApp -destination 'platform=iOS Simulator,name=iPhone 15'
```

CI 配置见 `.github/workflows/ci.yml`。

---

## 五、提交 PR

1. 从 `main` 切出分支：`feat/xxx`、`fix/xxx`、`docs/xxx`。
2. 保证 `xcodebuild test` 全绿，且无新增编译警告。
3. PR 描述里写清：**动机 / 改动点 / 测试覆盖 / 已知限制**。
4. 涉及 UI 的改动请附 iPhone 与 iPad 两张截图；涉及无障碍的改动请附 VoiceOver 走查结论。
5. 一个 PR 只做一件事，避免「顺手重构」混入功能提交。

---

## 六、报告问题

提 Issue 时请附：

- iOS 版本、设备型号（iPhone / iPad）、App 版本；
- 复现步骤（越具体越好）；
- 预期行为 vs 实际行为；
- 若涉及解析失败，请提供**脱敏后**的页面结构片段（删除站点域名与正文内容）。

---

## 七、许可

提交 PR 即表示你同意以 [MIT](LICENSE) 许可贡献你的代码。
