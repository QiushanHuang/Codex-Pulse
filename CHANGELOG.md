# Changelog

## Unreleased — desktop surfaces (2026-09-26)

These changes are available in the source branch. The latest packaged download is
still [v2.1.3](https://github.com/QiushanHuang/Codex-Pulse/releases/tag/v2.1.3).

### Added

- Three sticky sizes: a quota ring with a saved **40–160-point diameter**, a narrower
  **220-point Compact** card, and the existing Standard card.
- A native ring context menu with a size slider, presets, pinning, mode selection
  and window actions. Drag anywhere inside the visible circle, including its rim.
- Configurable ring clicks: **no expansion**, **Compact panel**, or **Standard panel**.
  Details open temporarily beside the ring without changing its size, position or
  saved mode. Click again, click outside, press Escape, use Close or drag the ring
  to dismiss. Drag release does not trigger a click.
- An optional translucent screen-edge sidebar, toggled with **⌘⇧B**. Choose the
  display, left/right edge, vertical position, auto-hide or always-visible behavior,
  waveform or remaining-quota badge, and glass or solid detail panel.
- Selectable sidebar sections: quota, reset time, consumption estimate, task counts,
  recent tasks and trend. Choose **1–8 tasks**; panels shorten when less is shown.
- A **便签与侧边栏** (Sticky & Sidebar) Settings page. Existing workbench, Standard
  sticky mode, widgets and keyboard controls remain available; the sidebar is off
  by default and ring clicks default to no expansion.

### Fixed

- Real mouse dragging on the mini ring, including small rings and edge hits. Drawing
  and mouse handling share one native view; transparent corners are excluded.
- Startup with a saved enabled sidebar: restore its windows after the main scene
  and window actions are ready.
- Settings action alignment in the input-attention notice.
- Restore the Widget's original layout and fixed mint palette independently of app
  appearance. Refresh its registration after local installation to avoid stale
  extension timelines. `python3 scripts/install_macos.py --repair-widget` repairs
  registration without replacing the app or clearing other widgets.

### 中文

以上更新已进入源码分支；当前公开下载包仍为
[v2.1.3](https://github.com/QiushanHuang/Codex-Pulse/releases/tag/v2.1.3)。

- **三种便签尺寸：**迷你圆环支持保存 40–160 点直径，紧凑便签收窄至 220 点，标准便签保留。
- **圆环右键菜单：**直接调整大小滑块、预设尺寸、置顶、模式与窗口操作；圆环内部和边缘均可拖动。
- **单击临时展开：**可选不展开、紧凑浮层或标准浮层。圆环保持原来的大小、位置和模式；
  再次单击、点击外部、按 Esc、点击关闭或拖动圆环均可收起。拖动松手不会误触发单击。
- **可选侧边栏：**按 ⌘⇧B 开关半透明侧边圆钮，支持选择显示器、左右侧、垂直位置、
  自动隐藏或常驻、波形或剩余数字，以及毛玻璃或实色详情面板。
- **自选详情内容：**勾选额度、重置时间、消耗估计、任务统计、最近任务和趋势，
  任务数量可选 1–8 条；内容减少时面板自动缩短。
- **集中设置：**新增「便签与侧边栏」设置页，原工作台、标准便签、小组件和键盘功能保留。
  侧边栏默认关闭，圆环单击默认不展开。
- **交互与启动修复：**修复小圆环真实鼠标拖动无响应、边缘命中不准，以及启用侧边栏后重启可能崩溃。
- **既有界面修复：**调整输入提示栏中的设置按钮；小组件恢复原始布局和固定薄荷绿配色，
  本机安装后刷新扩展注册。可通过 `python3 scripts/install_macos.py --repair-widget` 单独修复注册。

## 2.1.3 — 2026-09-21

- Add a persistent **Show in Dock** switch in General settings. Hiding the Dock icon keeps the menu-bar entry and background monitoring available.
- Restore the selected dashboard or sticky view when reopening from the Dock; add native application-hide menu actions.
- Load the canonical waveform-and-quota app icon explicitly to avoid stale Dock artwork.
- Reuse the Widget card layout in sticky mode, with quota, consumption rate, reset time, trend and three recent tasks; retain pin and workbench controls.
- Match the workbench and sticky dark backgrounds to the visible gray-teal Widget surface.
- Fix the blue focus ring automatically appearing on **View Settings** when opening the dashboard. Deliberate keyboard navigation still shows native focus indicators.

Available as Apple Silicon DMG and ZIP downloads with bundled Python and Node.js. Ad-hoc signed; not Apple-notarized.

### 中文

- 通用设置新增可保存的「在 Dock 中显示」开关；隐藏图标后保留菜单栏入口与后台监控。
- 从 Dock 重新打开时恢复工作台或便签，并增加原生隐藏应用菜单入口。
- 显式加载统一的波形与额度半环图标，避免 Dock 沿用旧图案。
- 便签复用 Widget 的排版：额度圆环、消耗速度、重置时间、趋势与三条最近任务，保留置顶及返回工作台按钮。
- 主界面和便签的深色背景按 Widget 实际显示的灰青色亮面校准。
- 修复主窗口打开时「查看设置」自动出现蓝色焦点框；通过键盘主动导航时仍保留焦点提示。

提供内置 Python 和 Node.js 的 Apple Silicon DMG、ZIP 下载包。当前为 ad-hoc 签名，未经 Apple 公证。


## 2.1.2 — 2026-09-20

First public GitHub release of Codex Pulse.

- Native quota/task workbench, menu-bar indicator, sticky mode and WidgetKit extension.
- G913 full-size adapter, explicit device selection, task signals and 48-preset lighting studio.
- Original waveform-and-quota identity shared by the app icon and repository.
- English and Chinese README in one page, with language badge anchors.
- Apple Silicon app distribution with bundled Python 3.13.15 and Node.js 22.23.2.
- Runtime paths follow the app when moved; both Codex.app and ChatGPT.app installations are discovered.
- Installation, usage, troubleshooting, contribution and packaging guides; runtime license notices.

Ad-hoc signed; not Apple-notarized. Intel and clean-machine macOS 14 behavior are
not verified. The app interface remains primarily Chinese.

### 中文

首次公开发布：原生额度/任务工作台、菜单栏、便签与小组件，G913 完整布局联动和
48 预设灯效工作室；统一原创 Logo、同页双语 README 与完整操作文档。
Apple Silicon 下载包内置 Python/Node，移动应用后仍能定位解释器，并识别
Codex.app 与 ChatGPT.app。当前为 ad-hoc 签名、未公证版本；未验证 Intel 和
全新 macOS 14 机器，应用界面仍以中文为主。
