# 隐私政策 / Privacy Policy

**生效日期：2026-01-01**
**适用产品：开源阅读 · iOS（Bundle ID：`com.example.ReadingApp`）**

本文件与应用内「设置 → 隐私与开源 → 隐私说明」页内容同源，二者如有差异以本文件为准。

---

## 一、总述

开源阅读 · iOS 是一款**纯本地工具型**应用。我们不运营任何服务器，不设账号体系，不采集任何个人信息，也不接入任何第三方分析、广告或归因 SDK。

**一句话说明：你的书架、阅读进度、书源规则与下载内容只存在你自己的设备上。**

---

## 二、我们不收集的信息

| 类别 | 是否收集 | 说明 |
| --- | --- | --- |
| 姓名 / 手机号 / 邮箱 | 否 | 无注册登录流程 |
| 设备标识符（IDFA / IDFV） | 否 | 不读取广告标识符，不做归因 |
| 位置信息 | 否 | 不申请定位权限 |
| 通讯录 / 相册 / 麦克风 / 摄像头 | 否 | 不申请上述任何权限 |
| 阅读行为 / 使用时长 / 点击流 | 否 | 无埋点、无统计 SDK |
| 崩溃日志 | 否 | 不接入第三方崩溃上报；系统级崩溃报告由你在 iOS 设置中自行决定是否共享给 Apple |
| 剪贴板内容 | 否 | 仅在粘贴书源链接时由你主动触发读取 |

隐私清单 `ReadingApp/PrivacyInfo.xcprivacy` 中：

- `NSPrivacyTracking = false`
- `NSPrivacyTrackingDomains = []`
- `NSPrivacyCollectedDataTypes = []`

---

## 三、本地存储的数据

以下数据保存在 App 沙盒内，卸载 App 即随之删除：

| 数据 | 位置 | 用途 |
| --- | --- | --- |
| 书架、阅读进度 | SwiftData 数据库 | 恢复阅读位置、书架展示 |
| 书源规则 | SwiftData 数据库 | 按你导入的规则解析站点 |
| 阅读偏好（字号、阅读模式、亮度） | UserDefaults | 记住你的阅读设置 |
| 下载的章节 / 漫画图片 | App 沙盒 `Library/Books` | 离线阅读 |
| 同步配置（服务器地址、用户名） | SwiftData 数据库 | 自建同步 |
| 同步密码 | **系统钥匙串（Keychain）** | 仅用于你配置的 WebDAV 认证，不写数据库、不进同步文件 |

---

## 四、网络访问

App 仅在以下场景发起网络请求，且请求**直接发往你指定的目标**，不经过任何中间代理或我方服务器：

1. 使用书源搜索书籍；
2. 加载章节正文或漫画图片页；
3. 下载离线内容；
4. 你手动触发（或开启自动同步后）的 WebDAV / NAS 同步。

请求目标由你导入的书源规则或你填写的同步地址决定，我们无法感知、记录或干预这些请求。

---

## 五、数据共享

我们不向任何第三方共享、转让或公开你的数据——因为我们根本不持有你的数据。唯一的对外数据传输发生在你主动配置的 WebDAV / NAS 同步中，接收方是你自己的服务器。

---

## 六、儿童隐私

本应用不面向儿童设计，不收集任何年龄信息，也不收集任何个人信息。

---

## 七、内容来源与版权

本应用不内置、不托管、不分发任何书籍或漫画内容。所有内容均由使用者自行添加的书源从第三方站点获取，版权归原站点与作者所有。使用者应自行确保其使用行为符合内容提供方的服务条款与所在地法律法规。

---

## 八、你的权利

由于我们不持有你的任何数据，删除权、导出权、更正权在物理上已由你完全掌握：

- 删除单本书：书架左滑删除；
- 删除全部数据：卸载 App；
- 导出数据：通过 WebDAV 同步自行导出 JSON 快照。

---

## 九、政策变更

若未来版本引入任何数据采集能力，我们会在本文件与应用内隐私页同步更新，并在版本更新说明中明确告知。当前版本（0.1.0）不存在任何采集行为。

---

## 十、联系方式

如对本政策有疑问，请通过仓库 Issue 反馈：`<your-repo-url>/issues`。

---

# Privacy Policy (English Summary)

ReadingApp for iOS is a **local-only, tool-type** application. We do not operate any server, require no account, collect no personal data, and integrate no third-party analytics, advertising, or attribution SDKs.

- All bookshelf data, reading progress, source rules, and downloaded content stay on your device.
- The only network requests are those you trigger: source-based search, chapter/page loading, downloads, and your own WebDAV/NAS sync.
- The sync password is stored exclusively in the iOS Keychain.
- Privacy manifest declares `NSPrivacyTracking = false` and an empty `NSPrivacyCollectedDataTypes`.
- This app ships no built-in content; all content is obtained through source rules you add yourself.
