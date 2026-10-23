# Time-range usage history / 时段用量分析

Open **Quota & Usage → Time-range analysis** (额度与用量 → 时段分析).
Choose the last hour, six hours, day, week, month, or a custom local start/end time.
Use the magnifier buttons to zoom, arrows to move the range, or drag across a chart
to select a smaller interval. Hover to inspect sample values. Select Credit balance,
Credit consumption, remaining quota, local task Token increments, or Token speed.
Click a task row or use the task selector to inspect its Token distribution.

- **Credit:** successful full account reads persist balance observations locally.
  Consumption means observed balance decreases; refills/upward adjustments are
  counted separately. Unknown/unlimited observations break the series. Long gaps
  are visible and never assigned a fabricated current rate. Account changes never
  become Credit consumption. These observations are not an itemized billing ledger.
- **Task Token:** store only task ID/title, timestamp and cumulative counters from
  the existing bounded local session metadata reader. The first counter is a baseline;
  adjacent increases are consumption, counter decreases are corrections. Duplicate
  records are ignored. Existing cumulative totals are never summed as new usage.
  On first use, only metadata in the existing bounded startup tail can be recovered.
- **Scope:** Credit/quota belong to the signed-in account; local task counters are
  scoped to the machine, not attributed to that account. Remote/cloud-only tasks
  without local observations are outside coverage. Service daily account totals
  remain in the separate daily/weekly panel and are not added to local task counters.
- **Intervals and speed:** count only adjacent observation intervals whose two
  endpoints are inside the requested range. Do not interpolate boundary-crossing
  increments. Task average speed is observed Token increase divided by time between
  first/last samples in the range, including waiting/idle time. A single sample is
  unknown, not zero. The speed chart shows increments per adaptive time bucket,
  normalized to tokens/minute; it is not instantaneous model decoding throughput.
- **Storage:** additive tables in `~/Library/Application Support/CodexPulse/history.sqlite`.
  Existing quota history is retained; automatic thirty-day expiry is removed.
  New Credit/task observations are kept locally across app restarts. Older missing
  Credit balances cannot be recovered. Queries are read-only and off the UI thread;
  chart density is reduced while retaining first/last points and extrema.

## 中文

在 **额度与用量 → 时段分析** 选择快捷时间范围，或指定本地时区的起止日期和时间。
放大／缩小按钮调整时间尺度，左右按钮移动半个时段，拖动图表可选取更小区间，悬停查看采样值。
可切换 Credit 余额、Credit 消耗、套餐额度、Token 用量和 Token 速度；点击任务查看其分布。

Credit 在监控运行且成功读取账号余额时记录，下降与补充／上调分别统计。它属于账号级观测，
不能可靠分摊给任务，也不等于逐笔账单。更新前没有保存的 Credit 历史无法补录。

Token 采用已有本机会话的累计计数差值，首条仅作基线，不将历史总量当作新增消耗。
首次启动只补读已有读取器有界范围内的元数据；重复记录不重复累计，计数回退按校正处理。
本机任务 Token 不等于当前账号全部 Token，与服务每日／每周统计独立展示。

仅统计两端都位于查询区间内的相邻记录，边界增量不插值。任务速度是所选时段内已观测增量
除以首末采样间隔，包含等待和空闲；单次采样或缺失显示 —。速度图按时间桶折算 Token/分钟，
不代表模型瞬时生成速度。暂停监控和服务延迟可能留下采样空档。

历史保存在原有本地 SQLite 中，新增表不覆盖旧记录，并停止原有的套餐历史 30 天自动过期。
查询不访问外部服务，不执行额度重置。图表缩放只改变查看范围，不改变底层记录。
