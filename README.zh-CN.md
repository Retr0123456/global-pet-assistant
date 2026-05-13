# Global Pet Assistant

<p align="center">
  <img src="Assets/AppIcon/AppIcon.png" width="112" height="112" alt="Global Pet Assistant icon">
</p>

<p align="center">
  一个本地优先的 macOS 桌面宠物，把 coding agent、终端和构建状态变成屏幕上的小伙伴。
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

Global Pet Assistant 是给本地开发工作流用的原生 AppKit 小工具。它会渲染一个透明、
常驻桌面的宠物，接收可信本地集成发来的事件，并把这些事件变成宠物动作、短状态
提示和持久的 agent 线程提醒。

它刻意保持轻量：不需要托管账号，不依赖云端 relay，默认也没有公网 webhook 监听。
你的工具只会和 `127.0.0.1` 上受本地 bearer token 保护的服务通信。

## 亮点

| 模块 | 能力 |
| --- | --- |
| 原生桌面宠物 | 透明 AppKit 窗口、拖拽移动、边缘吸附、尺寸调整、菜单栏控制和流畅 spritesheet 动画。 |
| Coding agent 状态 | Codex hooks 支持 running、等待批准、completed、review 等状态。 |
| 终端反馈 | Kitty watcher plugin 提供命令开始/结束 flash，不需要修改 shell 启动文件。 |
| 本地事件 API | `petctl` 和 localhost HTTP 事件入口，可接入脚本、构建和本地工具。 |
| 持久提醒 | thread panel 会保留长期提醒，直到用户手动关闭，而不是像 toast 一样自动消失。 |
| 保守动作系统 | 通知点击只能打开 allowlist 里的 App、URL、文件、文件夹或受支持终端/会话目标。 |
| 宠物资源包 | 可导入 Codex 兼容的 `1536x1872` spritesheet 资源包到应用自己的宠物目录。 |

## 安装

从 [GitHub Releases](https://github.com/Retr0123456/global-pet-assistant/releases/latest)
下载最新 DMG，打开后把 `GlobalPetAssistant.app` 拖到 `/Applications`。先启动一次
应用，然后运行内置配置向导：

```bash
open /Applications/GlobalPetAssistant.app
/Applications/GlobalPetAssistant.app/Contents/Resources/Tools/setup-integrations.sh
```

DMG 安装只会复制 app，不会自动修改终端或 coding agent 配置。配置向导会先显示
将要修改的外部文件，创建备份，然后让你选择 Kitty 命令反馈、Codex 会话提醒等
集成。

当前 beta 版本还没有 notarize。如果 macOS 阻止首次启动，可以在 Finder 中
Control-click -> Open，或在 System Settings 中允许打开。手动安装和非交互命令见
[集成配置](docs/integrations.zh-CN.md)。

## 工作方式

```text
本地工具 / agent / terminal plugin
        |
        v
petctl, Codex hooks, Kitty watcher, localhost HTTP
        |
        v
本地事件路由 + action allowlist
        |
        v
宠物动画、flash 消息或 thread 提醒
```

Global Pet Assistant 会把运行状态放在 `~/.global-pet-assistant`：

| 路径 | 用途 |
| --- | --- |
| `~/.global-pet-assistant/token` | 本地事件写入用的 bearer token。 |
| `~/.global-pet-assistant/config.json` | source allowlist、宠物导入路径和运行偏好。 |
| `~/.global-pet-assistant/logs/` | runtime、event 和 hook 日志。 |
| `~/.global-pet-assistant/pets/` | 已导入或内置安装的宠物资源包。 |

## 文档

建议从这里开始：

- [文档中心](docs/README.zh-CN.md)：安装、集成、架构和维护入口。
- [集成配置](docs/integrations.zh-CN.md)：Kitty plugin 和 Codex hooks。
- [Architecture](docs/architecture.md)：渲染器、事件 API、动作模型和本地安全边界。
- [Assets and Licensing](docs/assets-and-licensing.md)：图标和宠物资源授权规则。
- [Security Policy](SECURITY.md)：本地事件服务、token、日志和漏洞报告。
- [Contributing](CONTRIBUTING.md)：开发流程和 PR 要求。

## 开发

环境要求：

- macOS 26 SDK 或更新版本，用于当前 AppKit 界面。
- Swift 6.2 或更新版本。
- Xcode Command Line Tools。

```bash
swift build
swift test
Tools/package-debug-app.sh
open .build/GlobalPetAssistant.app
```

运行时 smoke check：

```bash
swift run GlobalPetAssistant
Tools/verify-event-runtime.sh
```

`Tools/verify-event-runtime.sh` 会自己启动 app。如果本地 `17321` 端口被已运行的
app 占用，先退出旧实例。

## 隐私

Global Pet Assistant 是本地优先的：

- 事件服务只绑定 `127.0.0.1`。
- 事件写入需要 `Authorization: Bearer <token>`。
- 不需要托管账号或云端 telemetry。
- 未知 source 可以发送状态通知，但不能打开 App、URL、文件、文件夹或终端窗口。

更具体的运行模型见 [Privacy](PRIVACY.md) 和 [Security Policy](SECURITY.md)。

## 卸载

退出应用，删除应用包；如果也想删除应用状态，再删除本地状态目录：

```bash
rm -rf /Applications/GlobalPetAssistant.app
rm -rf ~/.global-pet-assistant
```

如果安装过集成，也清理它们的托管配置：

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/bin/petctl uninstall kitty,codex
```

单个模块的清理方式见 [集成配置](docs/integrations.zh-CN.md)。
