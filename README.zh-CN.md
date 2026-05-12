# Global Pet Assistant

[English](README.md)

Global Pet Assistant 是一个轻量级 macOS 桌面宠物，用来展示本地开发通知。它以
一个小型 AppKit 浮窗宠物运行，只监听本机事件，并把工具状态转换成宠物动作、
短状态提示和可操作的线程提醒。

## 它是什么

- 一个常驻桌面的透明 macOS 宠物。
- 一个本地优先的开发通知入口。
- 一个可以被 Codex、Kitty、构建脚本和本地工具驱动的状态展示层。

## 可以做什么

- 播放 Codex 兼容宠物资源的 idle、running、waiting、success、failure、
  review、waving、jumping、running-left、running-right 等动作。
- 显示命令结果、构建状态和本地工具通知的短暂 flash 消息。
- 显示编码 agent 会话的长期 thread panel 提醒，直到用户手动关闭。
- 打开可信通知动作，例如 App、URL、文件、文件夹，或受支持的终端/会话目标。
- 从菜单栏或宠物右键菜单启动 Focus Timer。
- 从菜单切换兼容宠物资源包。
- 从宠物右键菜单的 `Resize Pet` 打开大小滑杆并调整宠物尺寸。
- 将应用状态、日志、导入的宠物和本地 token 保存在
  `~/.global-pet-assistant`。

## 安装

从 [GitHub Releases 页面](https://github.com/Retr0123456/global-pet-assistant/releases/latest)
下载最新 DMG，打开后把 `GlobalPetAssistant.app` 拖到 `/Applications`。

启动应用：

```bash
open /Applications/GlobalPetAssistant.app
```

当前 beta 版本还没有 notarize。如果 macOS 阻止首次启动，可以在 Finder 中
Control-click -> Open，或在 System Settings 中允许打开。

## 推荐集成

先二选一配置：

- **Kitty plugin**：如果你使用 kitty，并且想要命令 flash 反馈和终端上下文，
  优先选它。它通过 kitty watcher 观察命令开始/结束，不需要改 shell 启动文件。
- **Codex hooks**：如果你主要想要 Codex 生命周期事件，例如 running、等待批准、
  turn 完成提醒，优先选它。

查看简洁配置文档：
[集成配置](docs/integrations.zh-CN.md)。

## 隐私与本地性

Global Pet Assistant 是本地优先的。应用只监听 localhost，首次启动时生成本地
bearer token，本地 helper 工具会读取这个 token。它不需要云账号。

## 卸载

退出应用，删除应用包；如果你也想删除应用状态，再删除本地状态目录：

```bash
rm -rf /Applications/GlobalPetAssistant.app
rm -rf ~/.global-pet-assistant
```
