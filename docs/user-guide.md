<a id="english"></a>

# User guide

[English](#english) · [简体中文](#中文) · [README](../README.md)

## Everyday use

Launch Codex Pulse after signing in to Codex. **总览** (Overview) summarizes the current
quota, running tasks and items needing attention. **任务** (Tasks) searches and filters
the latest 30 local unarchived sessions, with a detail pane and a link back to Codex.
**额度与趋势** (Quota & Trends) shows the actual account windows and recent history.
At least five minutes of continuous observations are needed for a consumption estimate.

The menu-bar waveform offers Open, Sticky Mode, Settings and Quit. Settings switches
between a plain waveform and a waveform with a lower quota arc. The arc represents
the lowest remaining main Codex quota; unavailable data has a dashed arc. Appearance
can follow the system or use light/dark mode independently of keyboard colors.

Use **⌘⇧M** for sticky mode. The pin keeps this card above ordinary windows; it is not
a promise to cover protected dialogs or every full-screen Space. Switching between
the card and workbench hides the other window, preserving page state. Settings remains
independent. Closing windows does not stop monitoring; Quit does.

Add a widget using macOS **Edit Widgets → Codex Pulse**. It reads the local snapshot;
macOS controls scheduling, so its timestamp matters. Open the app for fresh data.
To start at login, add `/Applications/Codex Pulse.app` to macOS Login Items.

## Device setup and effects

1. Start G HUB, connect a full-size G913 using LIGHTSPEED or USB and disable onboard mode.
2. In **设备**, explicitly select the supported layout. Pulse controls only one selected
   device and does not automatically switch to another when it disconnects.
3. In **联动规则**, enable linking. Use the one/two/three/four-task demos to inspect the
   keypad, or completion/reset/low-quota demos to inspect signals. Demos return to live
   state automatically; ending a demo early does not change quota or task history.
4. Choose task styles and a 2–30 second cycle. Adjust global and per-region brightness;
   their values multiply. Zero disables that region. F1–F10 are reserved for quota,
   the logo for the alert, and the keypad for task signals. F11/F12 belong to other keys.
5. Configure idle dimming (30 seconds–30 minutes), dimmed brightness and sleep
   (1–120 minutes, later than dimming). G HUB/keyboard applies these settings. The
   five-second full-white test is for visual comparison, not a photometric measurement.

**灯效工作室** offers 48 presets, 10 palettes, five brightness layouts and eight zones:
G1–G5, letters, number row, modifiers, space, navigation, arrows and Esc/F11/F12.
Search by name/color/effect, filter categories or page through presets. Paging alone
does not change the active effect. Select a preset to save/apply it.

**设计预览** simulates offline; clicking its keycaps only changes the preview.
**实机发送帧** displays colors sent to the device. The display and keyboard may differ.
Ordinary typing can drive reactive effects after Input Monitoring authorization.
Physical G1–G5 independent keypress detection is not implemented; the existing macros
are preserved and ordinary keys can still drive effects in the G-key region.

## Input Monitoring

Quota, task monitoring and non-reactive lighting do not require key-event access.
Enable **响应普通键盘输入** only if you want typing-driven effects. In macOS
**Privacy & Security → Input Monitoring**, enable the installed Codex Pulse and quit/reopen
it. **设置 → 隐私与诊断** shows permission checks, listener status and event counters.
A verified listener plus increasing counters confirms delivery to Pulse, not LED behavior.

Ad-hoc builds can change identity on update. If permission is enabled but the listener
still fails after reopening, remove the old Pulse entry and add the current app with
**+**, then enable and reopen it. Secure Input can temporarily prevent events.
Pulse neither modifies TCC databases nor resets system permissions automatically.

## CLI and recovery

Source checkout, with Python 3.9+ and Node 22+ available:

```sh
python3 scripts/pulse.py status
python3 scripts/pulse.py lights-on
python3 scripts/pulse.py lights-off
python3 scripts/pulse.py preview --scene running --tasks 4
python3 scripts/pulse.py preview --scene reset
python3 scripts/pulse.py restore
```

`status` prints task titles and status; redact this output before sharing it.
`lights-on/off` updates the running monitor's switch. `restore` disables linking and
recovers recorded temporary device control; it does not factory-reset the keyboard.
Quit the app before running `python3 scripts/pulse.py run`; a process lock prevents
multiple monitors for the same data directory. `once --data-dir /path/to/isolated-data`
is useful for isolated read-only sampling; it can still contact the account service.

For an installed release, use its bundled tools without installing Python or Node:

```sh
PULSE_RESOURCES="/Applications/Codex Pulse.app/Contents/Resources"
export PATH="$PULSE_RESOURCES/runtime/node/bin:$PATH"
"$PULSE_RESOURCES/runtime/python/bin/python3" -B \
  "$PULSE_RESOURCES/backend/scripts/pulse.py" status
# Replace status with restore for temporary lighting recovery.
```

For an unexpected force-quit, reopen Pulse to use its recorded recovery information,
or run `restore`. If another tool owns an unrecorded temporary preview, close that tool
first. Do not delete recovery files while lighting control is still active.

## Update and uninstall

Quit Pulse normally to release lighting, keep a copy of the previous app and back up
`~/Library/Application Support/CodexPulse/`, then replace the app in Applications.
Do not run the downloaded copy and installed copy simultaneously. Launch the new app,
check fresh timestamps and check Input Monitoring if reactive effects are enabled.
Source users can use `scripts/install_macos.py` after quitting; it creates an app backup
and verifies the launched build. This installer is separate from building.

To uninstall, disable linking, quit, remove any Login Item, then move the app to Trash.
Local settings/history are retained. Only remove the data folder after you no longer
need its history or device recovery information; removing it is irreversible without
a backup. If you enabled the legacy source login agent, first run
`python3 scripts/login_agent.py disable` from that checkout.

---

<a id="中文"></a>

## 中文

[English](#english) · [简体中文](#中文)

### 日常使用

登录 Codex 后启动 Pulse。**总览**显示额度、运行中任务和需要关注的状态；
**任务**支持搜索和筛选本机最近 30 个未归档会话，在详情中可回到 Codex。
**额度与趋势**显示服务端实际窗口与近期历史，消耗估计至少需要五分钟连续样本。

菜单栏提供打开工作台、便签、设置和退出。设置中可选择纯波形或波形加下半环，
半环表示主 Codex 窗口中最低剩余额度；数据不可用时显示虚线。
外观可跟随系统或固定深浅色，与键盘颜色独立。

**⌘⇧M**进入便签，用图钉切换普通窗口之上的置顶；不保证覆盖系统安全弹窗或所有全屏空间。
便签与工作台互斥显示，保留页面状态；设置窗口独立。关闭窗口不停止监控，退出才会停止。

在系统**编辑小组件 → Codex Pulse**中添加小组件，注意“更新于”时间。
刷新由 macOS 控制，需要及时数据时打开应用。登录启动可通过系统登录项添加应用。

### 设备与灯效

1. 运行 G HUB，连接 LIGHTSPEED 或 USB 的完整布局 G913，关闭板载模式。
2. 在**设备**中明确选择兼容布局。一次只控制一台设备，断线不自动切换。
3. 在**联动规则**开启联动，可测试 1/2/3/4 任务及结束、重置、低额度演示。
   演示自动返回实时状态，也可提前结束，不改额度或任务历史。
4. 选择任务动画风格和 2–30 秒周期；全局与分区亮度相乘，0% 熄灭该区。
   F1–F10 保留给额度，Logo 表示提醒，小键盘表示任务；F11/F12 属于其他区域。
5. 设置空闲降亮（30 秒–30 分钟）、降亮后亮度及休眠（1–120 分钟，晚于降亮）。
   这些参数交给 G HUB/键盘执行；五秒满白自检仅供目视比较，不是实体光度测量。

**灯效工作室**提供 48 个预设、10 组色板、5 种亮度布局及 G1–G5、字母、数字行、修饰键、
空格、导航、方向键、Esc/F11/F12 八区。支持名称/颜色/效果搜索、分类、翻页。
翻页不应用，点击预设才保存并应用。

**设计预览**可离线模拟，点击其中键帽只改变画面；**实机发送帧**显示软件输出，
与实体亮度可能不同。输入监控获准后，普通按键可以驱动交互效果。
尚不支持实体 G1–G5 独立按下检测；原宏不变，普通按键仍能驱动 G 区灯效。

### 输入监控授权

额度、任务和非交互灯效不需要按键权限。需要打字联动时，开启**响应普通键盘输入**，
在系统**隐私与安全性 → 输入监控**开启安装后的 Pulse，再退出重开。
**设置 → 隐私与诊断**显示预检、实际监听和计数；监听已验证且计数增加才说明事件到达，
仍不等于实体灯光已验证。

Ad-hoc 更新可能改变应用身份。如果开关已打开、重开后监听仍失败，可删除旧条目，
用 **＋** 添加当前应用，开启并重开。安全输入模式也可能临时阻止事件。
Pulse 不自动修改 TCC 数据库或重置系统权限。

### 命令行与异常恢复

源码目录中安装 Python 3.9+ 和 Node 22+ 后可使用：

```sh
python3 scripts/pulse.py status
python3 scripts/pulse.py lights-on
python3 scripts/pulse.py lights-off
python3 scripts/pulse.py preview --scene running --tasks 4
python3 scripts/pulse.py preview --scene reset
python3 scripts/pulse.py restore
```

`status`包含任务标题，分享前需脱敏。灯光开关通知正在运行的后台；`restore`关闭联动并
恢复已记录的临时设备控制，不是恢复键盘出厂设置。运行`run`前先退出应用，进程锁会阻止
同一目录下多个后台。`once --data-dir /path/to/isolated-data`可隔离诊断，但仍可能查询账户服务。

安装版无需另装解释器：

```sh
PULSE_RESOURCES="/Applications/Codex Pulse.app/Contents/Resources"
export PATH="$PULSE_RESOURCES/runtime/node/bin:$PATH"
"$PULSE_RESOURCES/runtime/python/bin/python3" -B \
  "$PULSE_RESOURCES/backend/scripts/pulse.py" status
# 将 status 换成 restore 可恢复临时灯光控制。
```

异常强杀后可重开应用，或执行`restore`使用已记录的恢复信息。
其他工具有未记录的临时预览时，请先关闭该工具；灯光仍接管时不要删除恢复文件。

### 更新与卸载

正常退出并释放灯光，保留旧应用，备份`~/Library/Application Support/CodexPulse/`，
再替换应用程序目录中的版本。不要同时启动下载目录和安装目录中的两份应用。
新版本启动后检查更新时间；启用了按键响应时再检查输入监控。
源码用户可在退出后使用`install_macos.py`，它会备份旧包并验证启动状态；构建本身不安装。

卸载时先关闭联动、退出，移除系统登录项，再把应用移入废纸篓。
本地数据默认保留；确定不再需要历史与设备恢复信息后才删除数据目录，且应先备份。
若曾启用源码版登录代理，先在原目录运行`python3 scripts/login_agent.py disable`。
