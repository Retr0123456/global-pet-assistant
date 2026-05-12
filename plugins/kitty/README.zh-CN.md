# Global Pet Assistant Kitty Plugin

[English](README.md) | [集成配置](../../docs/integrations.zh-CN.md) | [中文 README](../../README.zh-CN.md)

Kitty plugin 会把 kitty 中的 shell 活动连接到 Global Pet Assistant。它安装一个
kitty global watcher，观察命令开始/结束，并把本地 `terminal-plugin` 事件发送给
应用。

如果你想让长命令、失败命令和终端里的 coding-agent 上下文在桌面宠物上给出轻量
反馈，并且不想修改 shell 启动文件，就用它。

## 安装

先安装 Global Pet Assistant，并启动一次：

```bash
open /Applications/GlobalPetAssistant.app
curl -fsS http://127.0.0.1:17321/healthz
```

安装 app 内置插件：

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/plugins/kitty/install.sh
```

第一次安装后，需要完全退出并重新打开 kitty。

## 验证

在 kitty 中运行：

```zsh
sleep 3
false
```

预期结果：

- `sleep 3` 显示短暂 success flash。
- `false` 显示短暂 failure flash。

## 安装文件

| 路径 | 用途 |
| --- | --- |
| `~/.config/kitty/global-pet-assistant/` | Watcher、插件配置、shell integration 和本地环境文件。 |
| `~/.config/kitty/kitty.conf` | 会被加入一个带标记的 include block。 |

插件只会把事件发送给本地 app。它不需要 tmux，也不会打开公网监听。

## 卸载

```bash
rm -rf "$HOME/.config/kitty/global-pet-assistant"
```

然后从 `~/.config/kitty/kitty.conf` 删除 Global Pet Assistant 标记的 include
block。

如果你想比较 Kitty 和 Codex hooks，见
[集成配置](../../docs/integrations.zh-CN.md)。
