# 集成配置

[English](integrations.md) | [文档中心](README.zh-CN.md) | [中文 README](../README.zh-CN.md)

先安装 Global Pet Assistant，启动一次应用，然后运行内置配置向导。把 DMG 拖到
`/Applications` 不会自动修改终端或 coding agent 配置；配置向导会在写入外部文件
前展示计划。

```bash
open /Applications/GlobalPetAssistant.app
curl -fsS http://127.0.0.1:17321/healthz
```

`healthz` 应该返回 JSON。如果失败，先确认应用正在运行，再安装任何集成。

## 配置向导

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/Tools/setup-integrations.sh
```

这个向导会使用 app 内置的 `petctl`。DMG 安装不会自动把 `petctl` 加到 `PATH`；
如果需要，可以通过 `petctl-shim` 模块选择性创建全局命令入口。

常用非交互命令：

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/bin/petctl install --dry-run
/Applications/GlobalPetAssistant.app/Contents/Resources/bin/petctl install --with kitty,codex --yes
/Applications/GlobalPetAssistant.app/Contents/Resources/bin/petctl doctor
/Applications/GlobalPetAssistant.app/Contents/Resources/bin/petctl uninstall kitty --dry-run
```

## 选择路径

| 路径 | 适合场景 | 发送内容 |
| --- | --- | --- |
| [Kitty Plugin](#kitty-plugin) | 主要在 kitty 里工作的终端流。 | 命令开始/结束、退出码、工作目录和终端上下文。 |
| [Codex Hooks](#codex-hooks) | Coding agent 会话。 | Running、等待批准、completed turn 和持久 thread 提醒。 |

## Kitty Plugin

Kitty plugin 会安装一个 kitty global watcher。它观察 shell 命令的开始/结束，
并把本地 `terminal-plugin` 事件发送给 Global Pet Assistant。

它不需要 tmux，默认也不会修改 shell 启动文件。

### 安装

推荐：

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/bin/petctl install --with kitty
```

手动模块脚本：

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/plugins/kitty/install.sh
```

第一次安装后需要完全退出并重新打开 kitty。只开一个新 tab 不一定会让所有 kitty
配置加载 watcher。

### 验证

在 kitty 中运行：

```zsh
sleep 3
false
```

预期结果：

- `sleep 3` 显示短暂 success flash。
- `false` 显示短暂 failure flash。

### 文件

| 路径 | 用途 |
| --- | --- |
| `~/.config/kitty/global-pet-assistant/` | 已安装 watcher、插件配置、shell integration 和本地环境文件。 |
| `~/.config/kitty/kitty.conf` | 会被加入一个托管 include block。 |

### 卸载

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/bin/petctl uninstall kitty
```

这只会删除 Global Pet Assistant 托管的文件和标记配置块。

## Codex Hooks

Codex hooks 会通过 app 内置的 `global-pet-agent-bridge` 把 Codex 生命周期事件
发送给本地应用。它适合让宠物展示 agent 会话状态，而不仅仅是 shell 命令结果。

### 安装

推荐：

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/bin/petctl install --with codex
```

手动模块脚本：

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/plugins/codex/install.sh
```

安装后重启 Codex session。安装器会把托管 hook 写入 `~/.codex/hooks.json`，
并启用：

```toml
[features]
codex_hooks = true
```

预期结果：

- 提交 Codex prompt 后，会话显示为 running。
- 需要批准时显示为 waiting。
- turn 完成后显示在 thread panel 中，直到手动关闭。

### 禁用

临时禁用一个 shell 中的 hook：

```bash
export GLOBAL_PET_ASSISTANT_DISABLE_CODEX_HOOKS=1
```

如需永久移除：

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/bin/petctl uninstall codex
```

## 本地事件 API

脚本也可以直接通过 `petctl` 或 localhost HTTP 发送事件。

```bash
petctl notify --source local-build --level success --title "Build passed"
petctl state running --source codex-cli --message "Editing files"
```

如果直接写 HTTP，先读取本地 token：

```bash
PET_TOKEN="$(tr -d '\r\n' < ~/.global-pet-assistant/token)"
curl -X POST http://127.0.0.1:17321/events \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $PET_TOKEN" \
  -d '{"source":"ci","type":"build.failed","level":"danger","title":"CI failed"}'
```

未知 source 可以发送状态通知，但 click action 只会对 allowlist 中的 source 生效。

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
