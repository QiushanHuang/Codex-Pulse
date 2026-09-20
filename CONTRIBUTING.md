# Contributing

Report reproducible issues with the app version, macOS version, processor type and
steps. For lighting issues, include the keyboard model/layout, connection type and
G HUB version. Remove task titles, account details, device identifiers and private
paths from logs or screenshots before sharing them.

Discuss new hardware adapters before implementing them. Device discovery is not
proof of a matching layout. Preserve explicit device selection, fail-closed ownership
handoff and restoration of temporary control. Never infer a successful physical
result solely from an API response or preview.

Run the checks in [building.md](docs/building.md). Use synthetic fixtures; live tests
under `tests/live-*.mjs` and `tests/probe-*.mjs` are manual hardware tools and are not
part of CI. Keep quota units, freshness and unknown states explicit. Include focused
regression evidence for behavior changes and screenshots for interface changes.
Do not commit local histories, credentials, configuration, backups or build outputs.

Source contributions use the project MIT license. Preserve existing attribution.

## 中文

报告问题时请提供版本、macOS、芯片类型和复现步骤。灯光问题请补充键盘型号与布局、
连接方式及 G HUB 版本；分享前清除任务标题、账户信息、设备标识和私人路径。

新增设备适配请先讨论，不能把“发现设备”当作布局匹配。保留明确选择、接管失败即停止和
临时控制恢复机制。接口成功与屏幕预览不等于实体效果通过验证。

按[构建说明](docs/building.md#中文)运行检查，测试使用模拟数据。
`tests/live-*.mjs` 与 `tests/probe-*.mjs` 是人工硬件工具，不纳入 CI。
行为变更附回归依据，界面变更附预览；不要提交真实数据、令牌、配置、备份或构建产物。
