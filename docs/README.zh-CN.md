# 文档中心

[English](README.md) | [中文 README](../README.zh-CN.md)

这里是 Global Pet Assistant 的项目地图。想使用应用，先看运行和集成文档；想改
集成、通知或安全边界，再进入架构文档。

## 用户指南

| 文档 | 适合查看 |
| --- | --- |
| [集成配置](integrations.zh-CN.md) | 安装 Kitty 命令反馈或 Codex 会话 hooks。 |
| [Codex Hook Integration](codex-hook-integration.zh-CN.md) | 理解 Codex hook 事件和内置示例。 |
| [Kitty Plugin README](../plugins/kitty/README.zh-CN.md) | Kitty 专属安装、验证和清理。 |
| [Assets and Licensing](assets-and-licensing.md) | App 图标、内置宠物和第三方宠物资源规则。 |
| [Privacy](../PRIVACY.md) | 应用在本地保存什么，以及日志可能包含什么。 |
| [Security Policy](../SECURITY.md) | 本地事件服务、token 模型和漏洞报告。 |

## 架构

| 文档 | 范围 |
| --- | --- |
| [Architecture](architecture.md) | 产品定义、原生运行时、事件 API、状态机、动作系统和安全模型。 |
| [Agent Discovery Architecture](agent-discovery-architecture.md) | Coding-agent provider、session 和 projection 的建模方式。 |
| [Terminal Plugin Transport Architecture](terminal-plugin-transport-architecture.md) | 可信 terminal plugin transport 和终端上下文。 |
| [Codex Session Listening Refactor Plan](codex-session-listening-refactor-plan.md) | Codex session listening 与 hook ingestion 的迁移计划。 |
| [Kitty Terminal Transport Implementation Plan](kitty-terminal-transport-implementation-plan.md) | 首个 terminal plugin transport 的实现细节。 |

## 规划与维护

| 文档 | 范围 |
| --- | --- |
| [Daily Driver MVP](daily-driver-mvp.md) | 作为日常开发陪伴工具的产品形态。 |
| [Desktop Experience Plan](desktop-experience-plan.md) | 宠物行为、桌面交互和视觉体验计划。 |
| [Release Candidate Plan](release-candidate-plan.md) | RC 前稳定性 checklist。 |
| [Post-RC Roadmap](post-rc-roadmap.md) | RC 后续路线图。 |
| [Open Source Checklist](open-source-checklist.md) | 仓库公开发布前的项目卫生检查。 |
| [TODO](../TODO.md) | 实现阶段 checklist。 |

## 开发检查

发布代码改动前先跑：

```bash
swift build
swift test
```

改集成行为时，再跑对应的专项检查：

```bash
Tools/verify-codex-hook-events.sh
Tools/verify-kitty-plugin.sh
Tools/verify-event-runtime.sh
```

`Tools/verify-event-runtime.sh` 会启动 app。如果本地 `17321` 端口已经被正在运行的
app 占用，先退出旧实例。
