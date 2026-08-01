# 西瓜IPA助手 (XiguaStore)

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

[SideStore](https://github.com/SideStore/SideStore) 的分支,面向**第一次接触侧载的中文用户**做了精简。

配套图文教程:<https://sideloadstore.pages.dev>

上游基线:[`3716182`](https://github.com/SideStore/SideStore/commit/3716182678af66ae6b2c75dfb52ba0c6f60d616b)

---

## 这个分支改了什么

### 品牌
- 应用名 **西瓜IPA助手**,独立 Bundle ID `com.xiguastore.XiguaStore`,不与官方 SideStore 冲突
- 换成西瓜图标(iOS 要求图标不透明、且系统自己切圆角,所以源图铺了白底、未预切圆角)

### 内置软件源
首次启动自动添加「西瓜IPA助手」源,用户不用手动加。

源**追加**在官方源旁边而不是替换它——`altStoreSourceURL` 同时是 App 的自我更新通道,替换掉就没法自更新了。用户手动删掉后也不会在下次启动被塞回来。

相关代码:`AltStoreCore/Model/Source.swift`、`AltStoreCore/Model/DatabaseManager/DatabaseManager.swift`

### 界面精简

底部 Tab 从 5 个减到 3 个(Browse / My Apps / Settings):

| 移除 | 原因 |
|---|---|
| News | 除非源主动推送公告,否则永远是空白页 |
| Sources | 源已内置,普通用户不需要管理 |

被隐藏的 Tab 仍保留在 `allViewControllers` 里,深链依然能跳转;这种情况下会以模态方式弹出,并**自动加一个「完成」按钮**——否则用户会被困在一个没有 Tab 栏可返回的页面里。

设置里移除了:赞助链接、备用图标(全是 SideStore 品牌的)、上游测试版通道。

**刻意保留**的三项,砍掉会让用户卡死:

- **Background Refresh** —— 关掉后所有 App 会在 7 天后静默失效
- **Anisette Servers** —— 登录 Apple ID 必需,公共服务器经常挂,必须能换
- **Reset Pairing File** —— 配对出问题时唯一的自救手段

## 构建

```bash
git submodule update --init --recursive
xcodebuild -project AltStore.xcodeproj -scheme SideStore -configuration Debug -sdk iphoneos
```

签名配置复制 `CodeSigning.xcconfig.sample` 为 `CodeSigning.xcconfig`(已 gitignore),填自己的 Team ID。

`minimuxer` 现在通过 SPM 引用预编译的 `IDevice` xcframework,**不需要**配置 Rust 的 iOS 交叉编译目标。

### 一个构建上的坑

项目的 **Release 配置也定义了 `DEBUG`**(`SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG BETA`),而 `AppDelegate` 里有:

```swift
#if DEBUG && targetEnvironment(simulator)
UserDefaults.standard.isDebugModeEnabled = true
#endif
```

结果是**模拟器上连 Release 版都会强制开启 debug 模式**,依赖 `isDebugModeEnabled` 的隐藏逻辑在模拟器里看不出效果(真机不受影响)。本分支的界面裁剪因此改为无条件隐藏,避免行为随构建配置漂移。

## 许可证

本项目继承上游的 **AGPL-3.0**,见 [LICENSE](LICENSE)。

AGPL 是强 Copyleft:**任何人分发本项目或其修改版,都必须同样以 AGPL-3.0 公开完整源码。** 本仓库即为履行该义务而公开。

上游 SideStore 的原始 README 保留为 [README-upstream.md](README-upstream.md),原作者署名保留在应用内的 Credits 页面。

本项目与 SideStore 团队、AltStore 作者**无任何隶属或背书关系**。
