# Global Pet Assistant

<p align="center">
  <img src="Assets/AppIcon/AppIcon.png" width="112" height="112" alt="Global Pet Assistant icon">
</p>

<p align="center">
  一个本地优先的 macOS 桌面宠物，用来显示 coding agent、终端和构建状态。
</p>

<p align="center">
  <a href="README.md">English</a>
  · <a href="docs/README.zh-CN.md">文档中心</a>
  · <a href="docs/integrations.zh-CN.md">集成配置</a>
  · <a href="https://github.com/Retr0123456/global-pet-assistant/releases/latest">下载</a>
</p>

<p align="center">
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-MIT-blue.svg"></a>
  <a href="https://github.com/Retr0123456/global-pet-assistant/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/Retr0123456/global-pet-assistant?sort=semver"></a>
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS-lightgrey.svg">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-6.2-orange.svg">
</p>

Global Pet Assistant 会渲染一个透明、常驻桌面的宠物，把可信本地事件变成宠物动作、
命令 flash 和持久 agent 线程提醒。它只在本地 `127.0.0.1` 运行，并使用本地 bearer
token；不需要托管账号，也不依赖云端 relay。

## 能做什么

- 显示 Codex 会话状态，例如 running、等待批准和 completed turn。
- 通过内置 Kitty watcher 显示命令开始/结束 flash。
- 通过 `petctl` 或 localhost HTTP 接收脚本、构建和本地工具事件。
- 只打开 allowlist 中的 App、URL、文件、文件夹或受支持终端目标。
- 导入 Codex 兼容宠物资源包到应用自己的宠物目录。

## 安装

从 [GitHub Releases](https://github.com/Retr0123456/global-pet-assistant/releases/latest)
下载最新 DMG，把 `GlobalPetAssistant.app` 拖到 `/Applications`，先启动一次，然后运行：

```bash
open /Applications/GlobalPetAssistant.app
/Applications/GlobalPetAssistant.app/Contents/Resources/Tools/setup-integrations.sh
```

DMG 只会复制 app。配置向导会先显示将要修改的外部配置文件，创建备份，然后让你选择
要启用的集成。

当前 beta 版本还没有 notarize。如果 macOS 阻止首次启动，可以在 Finder 中
Control-click -> Open，或在 System Settings 中允许打开。

## 文档

- [集成配置](docs/integrations.zh-CN.md)：交互式配置、Kitty、Codex 和清理方式。
- [文档中心](docs/README.zh-CN.md)：架构、资源、安全和维护说明。
- [Privacy](PRIVACY.md) 和 [Security Policy](SECURITY.md)：本地服务、token 和日志模型。

## 开发

环境要求：macOS 26 SDK、Swift 6.2 和 Xcode Command Line Tools。

```bash
swift build
swift test
Tools/package-debug-app.sh
open .build/GlobalPetAssistant.app
```

运行时 smoke check：

```bash
Tools/verify-event-runtime.sh
```

## 卸载

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/bin/petctl uninstall kitty,codex
rm -rf /Applications/GlobalPetAssistant.app
rm -rf ~/.global-pet-assistant
```

单个模块的清理方式见 [集成配置](docs/integrations.zh-CN.md)。
