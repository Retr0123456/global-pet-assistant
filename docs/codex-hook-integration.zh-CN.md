# Codex Hook 集成

[English](codex-hook-integration.md) | [集成配置](integrations.zh-CN.md)

Codex hooks 会通过 app 内置的 `global-pet-agent-bridge` 把 Codex 生命周期事件
发送给 Global Pet Assistant。如果你希望宠物展示 Codex 会话状态，例如 running、
等待批准和 turn 完成提醒，就使用这个集成。

## 安装

先安装 Global Pet Assistant，并启动一次：

```bash
open /Applications/GlobalPetAssistant.app
curl -fsS http://127.0.0.1:17321/healthz
```

安装 app 内置 hooks：

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/Tools/install-codex-hooks.sh
```

安装后重启 Codex sessions。

## 安装了什么

安装器会把托管条目写入 `~/.codex/hooks.json`，并在 `~/.codex/config.toml`
中启用 Codex hooks：

```toml
[features]
codex_hooks = true
```

托管 hook 命令包含：

```text
global-pet-agent-bridge --source codex
```

## 预期行为

- `UserPromptSubmit` 会把 Codex session 标记为 running。
- `PermissionRequest` 会把 session 标记为 waiting。
- `Stop` 会把 turn 标记为 completed，并显示到 thread panel，直到用户手动关闭。

## 禁用

临时禁用当前 shell 中的 hooks：

```bash
export GLOBAL_PET_ASSISTANT_DISABLE_CODEX_HOOKS=1
```

如需移除集成，从 `~/.codex/hooks.json` 删除包含
`global-pet-agent-bridge --source codex` 的托管命令。

## 日志

```bash
tail -n 50 ~/.global-pet-assistant/logs/agent-hooks.jsonl
tail -n 50 ~/.global-pet-assistant/logs/runtime.jsonl
tail -n 50 ~/.global-pet-assistant/logs/events.jsonl
```

如果你想比较 Kitty 和 Codex hooks，见
[集成配置](integrations.zh-CN.md)。
