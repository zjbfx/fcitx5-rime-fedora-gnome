# fcitx5 + Rime 一键安装（Fedora GNOME）

在 Fedora GNOME（Wayland）上安装并配置 **fcitx5 + Rime**：默认简体中文、Rime 作为默认输入法、GNOME 顶栏中英状态符号正常、候选框跟随光标（通过 kimpanel 扩展）。

已在 **Fedora 45 Workstation / GNOME Shell 51.1 / Wayland** 上验证。

## 快速开始

```bash
git clone https://github.com/zjbfx/fcitx5-rime-fedora-gnome.git
cd fcitx5-rime-fedora-gnome
./install.sh
```

然后**必须注销并重新登录**（环境变量和 GNOME 扩展只在登录时生效）。

重新登录后验证：

```bash
./verify.sh   # exit 0 = 全部正常
```

> 给 AI agent 的说明见 [AGENTS.md](AGENTS.md)。

## 安装内容

| 项目 | 作用 |
| --- | --- |
| `fcitx5` `fcitx5-rime` `brise` | 输入法框架、Rime 引擎、官方词库（luna_pinyin） |
| `fcitx5-autostart` | 登录自启，并接管/替换 `ibus-daemon` |
| `fcitx5-configtool` | 图形化配置（`fcitx5-configtool` 命令） |
| `fcitx5-gtk` `fcitx5-qt` | GTK / Qt 客户端支持 |
| `~/.config/environment.d/fcitx5.conf` | `XMODIFIERS` / `QT_IM_MODULE` / `QT_IM_MODULES` |
| `~/.config/fcitx5/profile` | 默认输入法设为 Rime |
| `~/.local/share/fcitx5/rime/luna_pinyin.custom.yaml` | 默认输出简体；方案名改为"明月拼音"（顶栏取首字"明"作为中英状态符号，避免古字"朙"被误认为乱码） |
| GNOME kimpanel 扩展 | 从 extensions.gnome.org 下载**匹配当前 GNOME Shell 版本**的 kimpanel，解决 Wayland 下候选框位置错误 |

## 使用

| 快捷键 | 功能 |
| --- | --- |
| `Ctrl+Space` | 中英文切换 |
| `Ctrl+Shift+4` | 简体 / 繁体切换（默认简体） |

图形配置：运行 `fcitx5-configtool`。

## 验证

```bash
./verify.sh
```

检查项：fcitx5 进程、IBus 总线归属、当前输入法、会话环境变量、kimpanel 扩展与 D-Bus 服务、Rime 简体默认值。

## 故障排查

- **装完没反应 / 还是原来的输入法**：没有注销重登。环境变量在 `environment.d`，扩展在登录时加载。
- **候选框位置不对**：确认 kimpanel 已启用：
  `gnome-extensions list --enabled | grep kimpanel`
  GNOME 51 上**不能**用 Fedora 仓库的 `gnome-shell-extension-kimpanel`（其依赖要求 GNOME < 51，会直接冲突）；本项目从 extensions.gnome.org 安装匹配版本。
- **顶栏中英状态符号是怪字**：项目已把方案名改为"明月拼音"，顶栏显示"明"。如果你手动改过 Rime 方案名，顶栏会显示名称首字。
- **fcitx5 没有接管 ibus**：`busctl --user list | grep org.freedesktop.IBus` 的进程应为 `fcitx5`。若不是，确认 `fcitx5-autostart` 已安装后重新登录。
- **交互式问题**：非交互环境（agent/CI）需要免密码 sudo，否则脚本以退出码 4 结束。

## 卸载

```bash
./uninstall.sh                    # 移除配置和 kimpanel，保留软件包与词库
./uninstall.sh --remove-packages  # 同时卸载软件包
./uninstall.sh --purge            # 同时删除 ~/.local/share/fcitx5
```

卸载后注销重登，GNOME 会回到 ibus。

## 设计说明

- 不修改 `/etc`，不删除 ibus 软件包；通过 `fcitx5-autostart` 在会话内接管 IBus 总线（fcitx5 内置 IBus 前端，GNOME 的 text-input 直接走 fcitx5）。
- 脚本可重复执行；已有配置文件会备份为 `*.bak.<时间戳>`。
- 仅在 Fedora 上检测通过（其它发行版以退出码 3 结束）。

## 测试环境

- Fedora Linux 45 (Workstation), GNOME Shell 51.1, Wayland
- fcitx5 5.1.23, fcitx5-rime 5.1.15, brise 0.38, kimpanel 扩展 v94
