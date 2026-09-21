<a id="english"></a>

# Installation and troubleshooting

[English](#english) · [简体中文](#中文) · [README](../README.md)

## First launch

The v2.1.3 arm64 download is ad-hoc signed, not signed with a Developer ID certificate
and not Apple-notarized. Verify its SHA-256 against the same release's checksums, copy
the app into Applications and attempt to open it. If macOS blocks it, look in System
Settings → Privacy & Security for Open Anyway and confirm only for the downloaded
Codex Pulse you intended to run. Availability and wording vary with macOS/policy.
A managed Mac may require its administrator; a signature check alone does not bypass
Gatekeeper. Do not globally disable system security protections.
See [Apple’s first-launch guidance](https://support.apple.com/en-us/102445).

```sh
codesign --verify --deep --strict "/Applications/Codex Pulse.app"
```

This verifies the bundle's seal, not Apple notarization or developer identity. If the
archive checksum differs, obtain a fresh copy before continuing. If the seal fails,
do not use that bundle. A source build is an alternative if you have the build tools.

## Symptoms

| Symptom | Check / action |
| --- | --- |
| No quota or stale quota | Open Codex, check sign-in/network and wait one 60-second sample; check the app's timestamp and diagnostic message |
| Codex CLI not found | Install Codex.app or ChatGPT.app in `/Applications` or `~/Applications`; a CLI-only setup must expose `codex` to the app's environment, not just an interactive shell |
| Background exited / already running | Quit duplicate copies; inspect `monitor.log`; reopen once the old monitor has exited |
| Widget absent or delayed | Launch the installed app once, reopen Edit Widgets; system scheduling and ad-hoc extension policy may still delay/prevent availability |
| Keyboard discovered but disabled | Verify exact model/layout; discovery is broader than supported control |
| No lighting | Start G HUB, turn off onboard mode, use LIGHTSPEED/USB, select the device and enable linking; Bluetooth is not verified |
| Another preview is active | Stop the other lighting tool first; Pulse does not silently steal an unknown preview |
| Typing has no effect | Use a reactive preset, enable ordinary keyboard response and check actual listener status/counters in Privacy & Diagnostics |
| Permission enabled but listener fails after update | Quit/reopen; if identity changed, replace the old Input Monitoring entry with the current installed app |
| Dim lights | Check global × region brightness, idle dimming and G HUB settings; compare the five-second white self-test |
| Window seems missing | Check the menu bar; sticky and workbench modes intentionally hide each other |

Input Monitoring status is established by the running app, not inferred from an old
checkbox. Secure Input may temporarily block events. G HUB's private local interface
can change between releases. If the documented recovery fails, report the version,
keyboard model/connection and sanitized diagnostic output.

## Data and useful files

`~/Library/Application Support/CodexPulse/` contains `config.json`, `snapshot.json`,
`history.sqlite`, `monitor.log`, input-status/identity summaries and lighting recovery
files. The exact set depends on features used. Back up this directory before manual
configuration changes. Never attach it wholesale to a public issue: it contains task
titles, paths and device information even though Pulse does not copy login tokens or
save conversation text.

An app update may require granting Input Monitoring again. Successful software tests,
valid code signatures and emitted frames do not prove physical lighting behavior or
long-term battery usage. macOS 14 is the deployment target; this release was built and
checked on a newer Apple Silicon Mac, not a clean macOS 14 installation.

---

<a id="中文"></a>

## 中文

[English](#english) · [简体中文](#中文)

### 首次打开

v2.1.3 arm64 包为 ad-hoc 签名，没有 Developer ID 证书，也未经 Apple 公证。
核对同一 Release 的 SHA-256，复制到应用程序后尝试打开。
如被阻止，在系统设置 → 隐私与安全性中查找“仍要打开”，只确认你主动下载的 Pulse。
不同 macOS 和管理策略可能没有相同入口；受管理设备可能需要管理员处理。
不要全局关闭系统安全保护。也可以使用源码构建。

```sh
codesign --verify --deep --strict "/Applications/Codex Pulse.app"
```

这只检查包完整性，不代表 Apple 公证或开发者证书。
校验和不一致时重新下载；签名封装校验失败时不要继续使用该包。

### 常见问题

| 现象 | 检查与处理 |
| --- | --- |
| 额度缺失或过期 | 检查 Codex 登录与网络，等待一次 60 秒采样，查看更新时间和诊断信息 |
| 找不到 Codex CLI | 把 Codex.app/ChatGPT.app 放入 `/Applications` 或 `~/Applications`；单独 CLI 必须对应用启动环境可见，终端能找到并不充分 |
| 后台退出或已被占用 | 退出重复副本，查看 `monitor.log`，旧进程退出后再启动 |
| 没有小组件或更新慢 | 启动安装后的应用再打开小组件面板；系统调度及 ad-hoc 扩展策略仍可能延迟或阻止显示 |
| 发现键盘但无法选择 | 核对型号与布局；发现范围大于支持控制的范围 |
| 没有灯光 | 检查 G HUB、板载模式、LIGHTSPEED/USB、设备选择和联动开关；蓝牙未验证 |
| 已有其他预览 | 先关闭其他灯光工具，Pulse 不会强行接管未知预览 |
| 打字没有效果 | 选择交互预设、开启普通按键响应，查看隐私诊断中的实际监听与计数 |
| 更新后开关已开启但监听失败 | 退出重开；若身份变化，移除旧输入监控条目并添加当前应用 |
| 灯光很暗 | 检查全局×分区亮度、空闲降亮与 G HUB，用五秒白光自检比较 |
| 窗口消失 | 从菜单栏打开；便签与工作台按设计互斥显示 |

安全输入可能暂时阻止按键事件，G HUB 更新可能改变私有接口。
恢复仍失败时，请报告版本、键盘型号/连接方式和已脱敏的诊断输出。

### 数据与验证边界

数据目录为`~/Library/Application Support/CodexPulse/`，按所用功能包含配置、快照、历史、
日志、输入状态与灯光恢复记录。手动修改前先备份；不要整体上传到公开 Issue，
其中仍可能含任务标题、路径和设备信息。

更新后可能需要重新授权输入监控。软件测试、签名和发送帧不等于实体灯效或长期耗电已验证。
macOS 14 是部署目标；本次是在较新的 Apple Silicon Mac 上构建检查，未完成全新 macOS 14 验证。
