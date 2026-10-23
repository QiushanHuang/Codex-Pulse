<a id="english"></a>

# Quota refresh and task reminders

[English](#english) · [简体中文](#中文) · [README](../README.md)

These features are in the current source candidate, not the published 2.1.3 package.

Quota uses the signed-in Codex account's read-only app-server interface. Active
turns are sampled every 15 seconds; idle accounts every 120 seconds. Starting or
ending a turn and manual refresh trigger an extra read. Account update events are
accepted when available, but a separate app-server cannot promise live events from
another client. Service-side accounting can also lag. Daily usage stays on a
five-minute interval. There is no continuously loaded website or browser engine.

On macOS, file changes wake local task monitoring and the native UI. Writes are
coalesced to at most one task scan per second, with a 15-second fallback health
check. Changed sessions read appended lifecycle metadata rather than repeatedly
parsing the entire tail. Other platforms keep a five-second fallback task check.

Open **Settings → General → Task reminders → Notification delivery**. Choose
**Pulse cards**, **macOS notifications**, **Both**, or **Off**. Selecting one channel
avoids duplicate popups; existing preferences are preserved. Sound has its own
control, and Off also silences reminder sounds. Pulse offers 14 local macOS sounds plus Silent for each event: completion, question, approval, failure, interruption and confirmed quota reset. Defaults use distinct sounds; selections persist across restarts. Each row has a Preview button, independent of the master switch. Sound plays independently of system-banner presentation. Notification content is
silent to avoid a duplicate cue, and bursts are coalesced. The sound follows the
current output device/volume. Simultaneous events play one cue, prioritizing failure, approval, question, interruption, reset, then completion; silent events do not consume the sound budget. Choose **Allow system notifications** when
ready. Cards remain usable if macOS notifications are denied. They slide in briefly,
respect Reduce Motion and preserve keyboard focus. At most three are shown;
completion cards disappear after nine seconds, pending-action cards after eighteen.
Tasks still appear in the sidebar and task list after a card disappears.

Question requests also use explicit local tool-call and reply records when a runtime path does not emit hooks.
Only IDs and lifecycle state are retained. Startup scans at most 2 MiB per recent session;
streaming updates read appended bytes and keep outstanding requests in the small metadata cache.
When approval metadata is outside that tail, the indexed turn start costs at most
one additional 64 KiB read, cached for that turn.

Completion signals use local recorded turn endings. They mean a turn ended, not
that a project goal was accepted. Restarting Pulse does not replay historic endings.

For permission and question reminders, click **Connect Codex permission and
question reminders**. This backs up and merges `~/.codex/hooks.json`, preserving
other handlers. Review and trust the added hooks in Codex, then start a new turn.
The bridge records task/turn IDs, event time, status and opaque correlation keys;
it never stores commands, question text, outputs or login tokens, or approves,
denies or answers anything. Normal tool completion clears its matching request;
asynchronous question requests remain until a user prompt. Interrupt/end events
clear stale requests. Pending signals expire after 24 hours.

An approval-request hook runs before the approval decision. Pulse checks the
recorded reviewer for that exact turn: **Approve for me / Auto-review** stays quiet;
manual approval waits three seconds before a permission reminder. A resolved
request is cleared using the canonical command's opaque fingerprint. When the
reviewer cannot be established, Pulse does not label the request as awaiting a
person. Explicit question and completion reminders continue normally. See the
[Auto-review documentation](https://learn.chatgpt.com/docs/sandboxing/auto-review).

Hooks must be enabled and supported in the Codex runtime executing the task.
Untrusted hooks do not run. Cloud-only and remote tasks without local records or
this bridge are outside coverage. See the official [Codex Hooks documentation](https://learn.chatgpt.com/docs/hooks).
Do not automatically run the bridge installer on another host.

The menu's **OpenAI Status** item opens [status.openai.com](https://status.openai.com)
below Tibo's X link. This is a service-status page; personal quota comes from the
account interface described in the [app-server documentation](https://learn.chatgpt.com/docs/app-server).

<a id="中文"></a>

## 中文

[English](#english) · [简体中文](#中文)

这些功能属于当前源码候选版，已发布的 2.1.3 包仍保留旧行为。

额度继续从已登录 Codex 的只读接口获取。任务运行时每 15 秒读取、空闲时每 120 秒读取；
任务开始或结束、手动刷新会补读。收到接口更新事件时也会更新，但独立 app-server 不能保证
收到其他客户端的实时事件，服务端记账本身也可能延迟。每日用量仍每五分钟读取。

macOS 用文件变化唤醒任务监控和界面，流式写入最多每秒扫描一次，另有每 15 秒的健康检查。
会话变化只读新增生命周期记录，不反复解析整个文件尾部。无需常驻网页或浏览器引擎。

在 **设置 → 通用 → 任务提醒 → 通知方式** 选择 **Pulse 卡片**、**macOS 通知**、
**同时显示** 或 **关闭**。选择单一方式可避免重复弹窗；已有设置会保留。
提示音单独控制，选择「关闭」时提醒也不会响。
开启「提醒提示音」后，Pulse 在新事件到来时直接播放短音，连续事件会合并；
系统通知内容不再另响一遍。完成、需要回答、等待审批、失败、中断、额度重置分别使用不同默认音效；
每类可选 14 种 macOS 音效或静音，选择会保存。每行「试听」不受声音总开关限制。
同批事件按失败、审批、问答、中断、重置、完成的优先级播放一种声音，静音事件不占用播放间隔。
声音跟随当前输出设备／音量。额度重置只使用服务端已确认的 reset 事件，不按倒计时推测。
点击 **允许系统通知** 请求 macOS 授权；即使关闭系统通知，卡片仍可使用。
卡片短暂滑入，遵循“减少动态效果”，不抢键盘焦点，最多同时显示三张。
完成卡片九秒后消失，待处理卡片十八秒后消失；之后仍可在侧边栏和任务列表处理。

当前问答工具如果没有触发 Hooks，会补读本机明确的工具请求和用户回复记录，只保留 ID 与生命周期状态。
启动时每个最近会话最多读取 2 MiB，后续只读新增记录；未回答的请求不会被流式记录挤出缓存。
审批模式不在尾部时，通过轮次索引额外读取最多 64 KiB，并缓存当前轮次的结果。
异步提问时模型仍可运行，运行计数会保留。启动会提示仍待处理的请求，不重播历史完成任务。

完成提醒表示 **轮次结束**，不代表整个目标通过验收；重启不会重播历史结束记录。
权限和问题提醒需点击 **连接 Codex 权限与问题提醒**，此操作会备份并合并
`~/.codex/hooks.json`，保留其他 Hooks。之后在 Codex 中审阅、信任新增 Hooks，并开始新轮次。
桥接只记录任务／轮次 ID、状态、时间和关联指纹，不保存命令、问题、输出或登录令牌，
也不会替你授权、拒绝或回答。工具结束解除匹配请求，异步问题保留到用户输入；
中断或会话结束会清理，未处理信号最多保留 24 小时。

权限请求事件发生在审批决定之前。Pulse 会核对该轮次的审批模式：
**Approve for me／自动审批** 不触发「需要你授权」提醒；人工审批持续等待三秒才提示。
工具结束时用实际命令的关联指纹清除请求，避免审批描述差异留下旧提醒。
若无法确认审批模式，暂不把请求标为需要人工授权；明确的问答和完成提醒仍正常工作。
详见官方[自动审批文档](https://learn.chatgpt.com/docs/sandboxing/auto-review)。

执行任务的 Codex 运行时必须支持并启用这些 Hooks。没有本机记录或桥接的云端／远程任务
不在监控范围内；未经信任的 Hooks 不会运行。详见官方[Codex Hooks 文档](https://learn.chatgpt.com/docs/hooks)。

菜单栏 Tibo 下方的 **OpenAI 服务状态** 打开[官方状态页](https://status.openai.com)。
个人额度仍由[账号接口](https://learn.chatgpt.com/docs/app-server)提供。
