# 集成配置

[English](integrations.md) | [README 中文](../README.zh-CN.md)

先安装 Global Pet Assistant，启动一次应用，然后二选一配置一个集成。

```bash
open /Applications/GlobalPetAssistant.app
curl -fsS http://127.0.0.1:17321/healthz
```

`healthz` 应该返回 JSON。如果失败，先确认应用正在运行，再安装集成。

## 二选一

- 如果你使用 **kitty**，并且想要命令开始/结束反馈和终端上下文，选
  **Kitty plugin**。
- 如果你想要 Codex 的生命周期事件，例如 running、等待批准、turn 完成，选
  **Codex hooks**。

之后也可以两个都装；先只装一个更容易排查信号来源。

## Kitty Plugin

Kitty plugin 会安装一个 kitty global watcher。它观察 shell 命令的开始/结束，
并把本地 terminal-plugin 事件发送给 Global Pet Assistant。默认不需要 tmux，
也不修改 shell 启动文件。

从 release app 安装：

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/plugins/kitty/install.sh
```

第一次安装后需要完全退出并重新打开 kitty。只开一个新 tab 不一定会加载 watcher。

在 kitty 中验证：

```zsh
sleep 3
false
```

预期结果：

- `sleep 3` 显示短暂 success flash。
- `false` 显示短暂 failure flash。

相关文件：

| Path | 用途 |
| --- | --- |
| `~/.config/kitty/global-pet-assistant/` | 已安装的 watcher 和插件配置。 |
| `~/.config/kitty/kitty.conf` | 会被加入一个托管 include block。 |

卸载：

```bash
rm -rf "$HOME/.config/kitty/global-pet-assistant"
```

然后从 `~/.config/kitty/kitty.conf` 删除 Global Pet Assistant 标记的 include
block。

## Codex Hooks

Codex hooks 会通过 app 内置的 `global-pet-agent-bridge` 把 Codex 生命周期事件
发送给本地应用。它适合让宠物展示 Codex 会话状态，而不仅仅是 shell 命令结果。

从 release app 安装：

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/Tools/install-codex-hooks.sh
```

安装后重启 Codex session。安装器会把托管 hook 写入 `~/.codex/hooks.json`，并启用：

```toml
[features]
codex_hooks = true
```

预期结果：

- 提交 Codex prompt 后，会话显示为 running。
- 需要批准时显示为 waiting。
- turn 完成后显示在 thread panel 中，直到用户手动关闭。

临时禁用一个 shell 中的 hook：

```bash
export GLOBAL_PET_ASSISTANT_DISABLE_CODEX_HOOKS=1
```

如需永久移除，从 `~/.codex/hooks.json` 删除包含
`global-pet-agent-bridge --source codex` 的托管命令。

## 排查

检查应用是否可达：

```bash
curl -fsS http://127.0.0.1:17321/healthz
```

查看最近日志：

```bash
tail -n 50 ~/.global-pet-assistant/logs/runtime.jsonl
tail -n 50 ~/.global-pet-assistant/logs/events.jsonl
tail -n 50 ~/.global-pet-assistant/logs/agent-hooks.jsonl
```

如果集成停止工作，先确认应用正在运行，再重启应该发出事件的 terminal 或 Codex
session。
