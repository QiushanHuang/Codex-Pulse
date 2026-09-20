<a id="english"></a>

# Codex Pulse

[![English](https://img.shields.io/badge/Language-English-24292f)](#english)
[![简体中文](https://img.shields.io/badge/语言-简体中文-1677ff)](#中文)

[![Release](https://img.shields.io/github/v/release/QiushanHuang/Codex-Pulse)](https://github.com/QiushanHuang/Codex-Pulse/releases)
[![CI](https://github.com/QiushanHuang/Codex-Pulse/actions/workflows/ci.yml/badge.svg)](https://github.com/QiushanHuang/Codex-Pulse/actions/workflows/ci.yml)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111827)](https://github.com/QiushanHuang/Codex-Pulse/releases/latest)
[![Apple Silicon](https://img.shields.io/badge/Apple_Silicon-arm64-5ee8ba)](https://github.com/QiushanHuang/Codex-Pulse/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

![Codex Pulse — your Codex activity, at a glance](assets/branding/banner.svg)

**Keep Codex quota, task status and keyboard signals in one place—and spend less time checking on them.**
Codex Pulse is a native macOS companion that keeps background work visible in the
menu bar, a pinnable card and, optionally, a compatible keyboard.

## Why choose Codex Pulse?

When Codex is working while you code, read or use another app, three questions keep
coming up: **Is it still running? Does anything need attention? How much quota is left?**
Pulse puts those answers within reach so you can keep your current work in view.

| Common approach | Where it gets in the way | How Pulse helps |
| --- | --- | --- |
| Reopen Codex to check on background work | Repeated window switching interrupts the task in front of you | Glance at the menu bar or pin a compact status card above your other windows |
| Check a remaining-quota percentage | A number alone gives little context about consumption or the next reset | See remaining quota, reset times, a one-hour trend and a consumption estimate together |
| Check several task windows separately | It takes more effort to see what is running and what needs attention | Search and filter the latest 30 local unarchived tasks, then jump back to the relevant task |
| Use a decorative keyboard preset | The lighting does not tell you about your Codex work | Turn a supported G913 into a quota bar, running-task display and completion/reset signal |

**The difference is how these features work together:** quota and task information
stay available as you move between the full workbench, sticky card and optional
keyboard display. You can use the workbench without a keyboard, and enable hardware
control only for a device you explicitly select.

## Where it fits

- **Work in an editor or browser while a task runs.** Keep the sticky card nearby and
  return to Codex when a turn ends or a task needs attention.
- **Plan your next stretch of work.** Check remaining quota, its recent consumption
  and the next reset before deciding what to run next. Estimates reflect recent
  samples; they are not a guarantee of how long future work will last.
- **Make a desk setup useful.** Give a compatible keyboard meaningful work signals,
  then personalize the remaining regions with 48 presets, 10 palettes and eight zones.

Native SwiftUI interface · Local settings and history · Optional keyboard linking ·
Python and Node.js included in the download.

**[Download for Apple Silicon](https://github.com/QiushanHuang/Codex-Pulse/releases/latest)**
· [Read the quick-start guide](#start-here)

![Codex Pulse workbench](docs/images/workbench.png)

*Previews use synthetic demo data. The application currently uses a Chinese interface;
this README and the operating guides are available in English and Chinese.*

## Install

Download **`Codex-Pulse-v2.1.2-macos-arm64.dmg`** from
[Releases](https://github.com/QiushanHuang/Codex-Pulse/releases/latest), open it and drag
**Codex Pulse.app** to **Applications**. A ZIP containing the same app is also available.
The download includes Python and Node.js; **Homebrew, Xcode and a separate runtime
installation are not needed to run the release**.

| Requirement | Details |
| --- | --- |
| Mac | Apple Silicon; macOS 14 or newer |
| Codex | A signed-in Codex desktop installation in `/Applications` or `~/Applications`, or a `codex` CLI visible to the app |
| Keyboard lighting, optional | Logitech G HUB running; G913 full-size over LIGHTSPEED or USB; onboard memory mode off |
| Reactive typing effects, optional | macOS Input Monitoring permission for Codex Pulse |

**This release is ad-hoc signed and is not Apple-notarized.** macOS may block its first
launch. After verifying the download, try opening it once, then use **System Settings →
Privacy & Security → Open Anyway** if offered. Do not disable Gatekeeper globally.
See [installation and troubleshooting](docs/troubleshooting.md) for details and limits.

To verify a downloaded archive, download `SHA256SUMS.txt` from the same release and run:

```sh
shasum -a 256 Codex-Pulse-v2.1.2-macos-arm64.dmg
```

Compare the result with the matching line in `SHA256SUMS.txt`.
The published binary is arm64, not universal. Intel source builds are not verified.

## Start here

1. Open Codex and sign in, then launch **Codex Pulse**.
2. Open **总览** (Overview) or **额度与趋势** (Quota & Trends). Quota is sampled every
   60 seconds; task events are checked every 5 seconds.
3. Open **任务** (Tasks) to search, filter and return to a task in Codex.
4. Choose **便签模式** (Sticky Mode), or press **⌘⇧M**. Pin the card with its pin button.
   Switching modes hides the other main window and keeps the shared monitor running.
5. Open **设置** (Settings) with **⌘,** for appearance, monitoring, privacy diagnostics
   and widget guidance. Closing a window leaves the app in the menu bar; Quit stops it.

<p align="center"><img src="docs/images/sticky.png" width="360" alt="Compact sticky card with example quota, consumption rate and tasks"></p>

Add Codex Pulse through macOS **Edit Widgets** for small, medium or large widgets.
Widget refresh is scheduled by macOS and may be delayed; use the app for current data.
For login startup, add the installed app in **System Settings → General → Login Items**.

## Connect a keyboard

Open **键盘联动 → 设备** (Keyboard → Devices), select the compatible device explicitly,
then enable linking in **联动规则** (Linking Rules). Discovery alone does not mean support.
The validated adapter targets the **G913 full-size layout**; G915 is marked unverified,
and other layouts are not enabled for control.

| Region / signal | Meaning |
| --- | --- |
| F1–F10 | Lowest remaining quota among the main Codex windows; 10% per key, with a partial last segment |
| Keyboard logo | Low mint when healthy; steady red at 25% or below, with a separate alert switch |
| Numeric keypad | Distinct running patterns for one, two, three, or four-plus active tasks |
| Green completion sequence | A locally observed task turn ended; it does not certify the task's outcome |
| Purple reset sequence | A reset supported by observed server-window changes |
| Gray quota indicators | Missing or stale data |

The **灯效工作室** (Lighting Studio) has search, categories, pagination, independent
zone brightness and editable timing. Browsing pages does not apply a preset; clicking
one does. **设计预览** (Design Preview) works offline; **实机发送帧** (Sent Frames) shows
software output, not a measurement of physical LED brightness.

![Lighting studio with synthetic demo state](docs/images/studio.png)

Control uses G HUB's local, private temporary-preview interface. Turning linking off
or quitting releases it. Saved G HUB profiles and key assignments are not rewritten;
configured idle-dimming and sleep settings are applied to the keyboard. G HUB updates
can break this integration. See the [user guide](docs/user-guide.md) for demos, effects,
permissions, recovery, updates and removal.

## Understand the data

- Quota is read through the installed Codex App Server. Pulse does not start model turns,
  send task instructions or redeem reset credits. It is an independent project, not an
  OpenAI or Logitech product.
- Windows use the labels and durations actually returned by the server. `primary` does
  not necessarily mean five hours; Spark is shown separately when available.
- Consumption is **quota percentage points per hour**, estimated after at least five
  minutes of continuous samples. It is not tokens per second. Resets, account changes
  and long gaps invalidate the estimate.
- The local task list covers the latest 30 unarchived sessions. Remote machines and
  ChatGPT conversations are outside this scope. Unknown states remain unknown.
- Data stays in `~/Library/Application Support/CodexPulse/`: settings, 30-day history,
  task titles/status, event summaries and device recovery records. Pulse does not store
  conversation bodies or copy login tokens. Codex's own authenticated server connection
  is still needed to read account quota.
- Reactive effects keep bounded key events in memory (up to 64 events / 8 seconds), not
  typed text on disk. Physical G1–G5 press events are not currently supported.

## Build and contribute

Source builds need macOS 14+, full Xcode, Python 3.9+ and Node.js 22+.
There are no application-level pip or npm dependencies.

```sh
git clone https://github.com/QiushanHuang/Codex-Pulse.git
cd Codex-Pulse
python3 scripts/build_macos.py
open "build/Codex Pulse.app"
```

Quit an app running from `build/` before rebuilding it. Local builds use external
runtimes and ad-hoc signing by default. See [building and packaging](docs/building.md)
for SDK selection, the complete test commands, embedded runtimes and signing.

[User guide](docs/user-guide.md) · [Troubleshooting](docs/troubleshooting.md) ·
[Contributing](CONTRIBUTING.md) · [Changelog](CHANGELOG.md) ·
[v2.1.2 release notes](docs/releases/v2.1.2.md)

Created and maintained by **[Qiushan (QiushanHuang)](https://github.com/QiushanHuang)**.
See [contributors and attribution](CONTRIBUTORS.md). Source code and original artwork
use the [MIT License](LICENSE); bundled runtimes retain their
[third-party licenses](THIRD_PARTY_NOTICES.md).

---

<a id="中文"></a>

## 中文

[![English](https://img.shields.io/badge/Language-English-24292f)](#english)
[![简体中文](https://img.shields.io/badge/语言-简体中文-1677ff)](#中文)

**把 Codex 的额度、任务状态与键盘提示放在一起，少切几次窗口。**
Codex Pulse 是原生 macOS 辅助工作台，让后台工作的状态出现在菜单栏、可置顶便签，
以及可选的兼容键盘上。

### 为什么需要它，为什么选它？

让 Codex 在后台工作时，你可能正在写代码、读文档或处理另一件事，却总想确认：
**任务还在跑吗？有没有需要处理的状态？额度还剩多少？**
Pulse 把这些信息放到随时能看到的位置，让你继续专注于眼前的工作。

| 常见做法 | 使用中的不便 | Pulse 如何改善 |
| --- | --- | --- |
| 反复打开 Codex 查看后台状态 | 来回切换窗口，打断正在做的事 | 菜单栏快速查看，或把紧凑便签置顶在其他窗口上方 |
| 只看一个剩余额度百分比 | 难以同时判断消耗速度和下次重置时间 | 在一起查看剩余额度、重置时间、近一小时趋势和消耗估计 |
| 分别打开多个任务确认进展 | 不容易快速找到运行中或需要关注的任务 | 集中搜索、筛选本机最近 30 个未归档任务，再跳回对应任务 |
| 使用装饰性的键盘灯效 | 灯光好看，却不能告诉你 Codex 的工作状态 | 让兼容 G913 显示额度条、运行任务动画，以及结束和重置提示 |

**它的特点在于把这些功能连起来：**完整工作台用于集中查看，便签用于伴随工作，
兼容键盘用于灯光提示，围绕同一组额度与任务信息协作。
没有键盘也能使用工作台；需要联动时，再明确选择一台受支持设备。

### 哪些场景适合用？

- **任务在跑，你继续写代码或看资料。** 把便签放在旁边，看到轮次结束或需要关注的状态后，
  再回到 Codex 处理。
- **开始下一段工作前，先看看额度。** 同时查看剩余额度、近期消耗和重置时间，帮助安排下一步。
  消耗估计基于近期样本，不保证未来工作一定能持续相同时间。
- **让桌面上的键盘多一点用途。** 用灯光表示工作状态，再用 48 个预设、10 组色板和八区亮度
  调整其他区域，把状态提示与日常配色放在同一套设置里。

原生 SwiftUI 界面 · 配置与历史本地保存 · 键盘联动可选 · 下载包内置 Python 与 Node.js。

**[下载 Apple Silicon 版本](https://github.com/QiushanHuang/Codex-Pulse/releases/latest)**
· [查看快速开始](#快速开始)

![Codex Pulse 工作台，使用模拟数据](docs/images/workbench.png)

*展示图使用模拟数据。应用目前以中文为主，README 与操作文档提供中英说明。
顶部语言徽标直接跳到本页中文区域，不会打开另一个 Markdown 文件。*

### 安装

前往 [Releases](https://github.com/QiushanHuang/Codex-Pulse/releases/latest)，下载
**`Codex-Pulse-v2.1.2-macos-arm64.dmg`**，打开后把 **Codex Pulse.app** 拖到
**Applications（应用程序）**。也提供包含同一应用的 ZIP。
下载包已内置 Python 与 Node.js，**运行时无需安装 Homebrew、Xcode 或额外解释器**。

| 条件 | 说明 |
| --- | --- |
| Mac | Apple Silicon，macOS 14 及以上 |
| Codex | 安装在 `/Applications` 或 `~/Applications` 并已登录的 Codex 桌面应用；或应用可找到的 `codex` CLI |
| 键盘联动（可选） | G HUB 正在运行，完整布局 G913 通过 LIGHTSPEED 或 USB 连接，关闭板载模式 |
| 普通按键交互（可选） | 为 Codex Pulse 授予 macOS 输入监控权限 |

**当前版本使用 ad-hoc 签名，未经过 Apple 公证。** 首次打开可能被系统阻止。
核对下载文件后先尝试打开，再在 **系统设置 → 隐私与安全性** 中使用系统提供的
**仍要打开**。不要全局关闭 Gatekeeper。详细流程与限制见[安装排障](docs/troubleshooting.md#中文)。

从同一 Release 下载 `SHA256SUMS.txt`，执行以下命令并与对应行比较：

```sh
shasum -a 256 Codex-Pulse-v2.1.2-macos-arm64.dmg
```

发布包为 arm64，并非通用二进制；尚未验证 Intel 源码构建。

### 快速开始

1. 打开并登录 Codex，然后启动 **Codex Pulse**。
2. 在 **总览** 或 **额度与趋势** 查看数据；额度每 60 秒采样，任务事件每 5 秒检查。
3. 在 **任务** 搜索、筛选，点击相应入口回到 Codex。
4. 选择 **便签模式** 或按 **⌘⇧M**，用图钉切换置顶。便签与完整工作台互斥显示，
   切换时共用后台持续运行。
5. 按 **⌘,** 打开 **设置**，管理外观、监控、隐私诊断与小组件说明。
   关闭窗口后应用留在菜单栏；选择退出后后台停止。

<p align="center"><img src="docs/images/sticky.png" width="360" alt="便签模式：示例额度、消耗速度、预计耗尽时间和最近任务"></p>

在 macOS **编辑小组件** 中搜索 Codex Pulse，可添加小、中、大三种尺寸。
小组件刷新由系统调度，可能延后；及时数据请查看应用。
需要开机启动时，在 **系统设置 → 通用 → 登录项** 中添加安装后的应用。

### 连接键盘

进入 **键盘联动 → 设备**，明确选择兼容设备，再到 **联动规则** 开启联动。
发现设备不等于支持控制。目前真实验证的是 **G913 完整布局**；
G915 标记为尚未验证，其他型号或布局不开放控制。

| 区域或提示 | 含义 |
| --- | --- |
| F1–F10 | 主 Codex 窗口中最低剩余额度，每键 10%，最后一格按比例调暗 |
| 键盘 Logo | 正常为低亮薄荷绿；≤25% 为红色常亮，可单独关闭提醒 |
| 数字小键盘 | 分别显示 1、2、3、4 个及以上运行任务的动画 |
| 绿色结束动画 | 观察到本机任务轮次结束，不代表任务目标或结果已验收 |
| 紫色重置动画 | 服务端窗口变化提供了实际重置证据 |
| 灰色额度提示 | 数据缺失或已过期 |

**灯效工作室** 支持搜索、分类、翻页、分区亮度和时长调整。
翻页只浏览，点击预设才应用。**设计预览** 可离线运行；
**实机发送帧** 表示软件输出，不等于对实体 LED 亮度的测量。

![灯效工作室，使用模拟数据](docs/images/studio.png)

灯光通过 G HUB 的本机私有临时预览接口控制，关闭联动或退出应用时释放。
不会改写 G HUB 保存的配色与按键分配；空闲降亮和休眠参数会按配置写入键盘。
G HUB 更新可能影响接口兼容性。演示、灯效、授权、异常恢复、更新和卸载见
[完整操作指南](docs/user-guide.md#中文)。

### 如何理解数据

- 额度通过已安装 Codex 的 App Server 读取；不会发起模型轮次、发送任务指令或消耗重置券。
  本项目独立开发，并非 OpenAI 或 Logitech 官方产品。
- 按服务端实际返回的窗口标签与周期显示；`primary` 不固定代表五小时，Spark 可用时单独展示。
- 消耗速度是 **额度百分点／小时**，需至少五分钟连续样本，并非 token/秒。
  重置、切换账户或长时间断线后会重新积累样本。
- 任务只覆盖本机最近 30 个未归档会话，不包含远程机器和 ChatGPT 对话；证据不足时保留未知状态。
- 数据保存在 `~/Library/Application Support/CodexPulse/`：配置、30 天历史、任务标题与状态、
  事件摘要和设备恢复记录；不保存会话正文，不复制登录令牌。额度查询仍需要 Codex 自身的认证网络连接。
- 按键交互只在内存保留最多 64 项／8 秒的按键事件，不把输入文本写入磁盘。
  目前不支持实体 G1–G5 独立按下事件。

### 源码构建与贡献

需要 macOS 14+、完整 Xcode、Python 3.9+、Node.js 22+；应用无需额外 pip/npm 依赖。

```sh
git clone https://github.com/QiushanHuang/Codex-Pulse.git
cd Codex-Pulse
python3 scripts/build_macos.py
open "build/Codex Pulse.app"
```

若正在运行 `build/` 中的应用，请先退出再构建。本地构建默认使用外部解释器与 ad-hoc 签名。
SDK 选择、完整测试命令、运行时打包及签名见[构建说明](docs/building.md#中文)。

[操作指南](docs/user-guide.md#中文) · [常见问题](docs/troubleshooting.md#中文) ·
[贡献指南](CONTRIBUTING.md) · [更新记录](CHANGELOG.md) ·
[v2.1.2 发布说明](docs/releases/v2.1.2.md)

作者与维护者：**[Qiushan（QiushanHuang）](https://github.com/QiushanHuang)**。
贡献署名见 [CONTRIBUTORS.md](CONTRIBUTORS.md)。源码与原创图形采用 [MIT 许可](LICENSE)，
内置运行时保留各自的[第三方许可](THIRD_PARTY_NOTICES.md)。

[↑ Back to English / 返回英文](#english)
