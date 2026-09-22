# Changelog

## Unreleased — 2026-09-22

- Refresh Widget extension registration after local installation and remove the source build registration. This prevents an old extension process/version from producing rejected timelines after an update.
- Add `python3 scripts/install_macos.py --repair-widget` to repair the installed Widget without replacing the app or clearing other widgets.

### 中文

- 本机安装后重新注册 Widget 扩展并移除构建来源的旧注册，避免更新后沿用旧扩展版本，导致时间线被系统拒绝、Widget 显示空白。
- 新增 `python3 scripts/install_macos.py --repair-widget`，可单独修复已安装小组件，不替换主应用，不清除其他小组件。

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
