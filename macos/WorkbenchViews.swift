import SwiftUI
import AppKit

private let workbenchSurface = Color(nsColor: .controlBackgroundColor).opacity(0.72)

struct WorkbenchShell: View {
    @ObservedObject var model: PulseModel
    @Environment(\.openWindow) private var openWindow
    @State private var selectedTaskID: String?

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 220)
            Divider()
            VStack(spacing: 0) {
                if let notice = model.configurationNotice {
                    WorkbenchNotice(message: notice, symbol: "exclamationmark.triangle")
                        .padding(.horizontal, 28).padding(.top, 16)
                }
                if let error = model.error {
                    WorkbenchNotice(message: error, symbol: "exclamationmark.circle")
                        .padding(.horizontal, 28).padding(.top, 12)
                }
                InputAttentionNotice(model:model).padding(.horizontal,28)
                page.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(PulseWindowBackground())
        .frame(minWidth: 1024, idealWidth: 1280, minHeight: 700, idealHeight: 820)
        .tint(pulseMint)
        .preferredColorScheme(model.appearance.preferredScheme)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path").font(.system(size: 25, weight: .semibold)).foregroundStyle(pulseMint)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Codex Pulse").font(.system(size: 20, weight: .semibold))
                    Text("额度有数，进度可见。").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 20).padding(.top, 30).padding(.bottom, 32)
            navigationGroup("Codex 工作台", routes: [.overview, .tasks, .quota])
            Divider().padding(.horizontal, 20).padding(.vertical, 23)
            navigationGroup("键盘联动", routes: [.devices, .rules, .studio])
            Spacer(minLength: 20)
            VStack(alignment: .leading, spacing: 17) {
                Button { model.presentWindow("sticky",using:{openWindow(id:$0)}) } label: {
                    Label("便签模式",systemImage:"rectangle.portrait").frame(maxWidth:.infinity,alignment:.leading)
                }.buttonStyle(.plain).help("打开常驻桌面的监控小窗")
                Button { openWindow(id: "settings") } label: {
                    Label("设置", systemImage: "gearshape").frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).keyboardShortcut(",", modifiers: .command)
                HStack {
                    Label("外观", systemImage: "circle.lefthalf.filled").foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        ForEach(PulseAppearance.allCases) { appearance in
                            Button { model.setAppearance(appearance) } label: {
                                Label(appearance.title, systemImage: model.appearance == appearance ? "checkmark" : appearance.symbol)
                            }
                        }
                    } label: { Text(model.appearance.title) }
                    .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("选择外观")
                }.font(.callout)
                Divider()
                HStack(spacing: 8) {
                    Circle().fill(model.running ? pulseMint : Color.orange).frame(width: 7, height: 7)
                    Text(model.running ? "后台运行中" : "后台未运行").font(.caption)
                }
                Text(model.snapshot.generatedAt > 0 ? "更新于 \(workbenchDate(model.snapshot.generatedAt))" : "等待首次数据")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(20)
        }.background(Color(nsColor: .underPageBackgroundColor).opacity(0.35))
    }

    private func navigationGroup(_ title: String, routes: [WorkbenchRoute]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.bottom, 5)
            ForEach(routes) { route in
                Button { model.route = route } label: {
                    HStack(spacing: 12) {
                        Image(systemName: route.symbol).font(.system(size: 17)).frame(width: 22)
                        Text(route.title).font(.system(size: 14, weight: model.route == route ? .semibold : .regular))
                        Spacer(minLength: 0)
                        if route == .tasks, model.snapshot.activeCount > 0 {
                            Text("\(model.snapshot.activeCount)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }.padding(.horizontal, 12).padding(.vertical, 11)
                        .foregroundStyle(model.route == route ? pulseMint : Color.primary)
                        .background(model.route == route ? pulseMint.opacity(0.13) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(model.route == route ? .isSelected : [])
            }
        }.padding(.horizontal, 12)
    }

    @ViewBuilder private var page: some View {
        switch model.route {
        case .overview:
            WorkbenchOverview(model: model) { task in selectedTaskID = task.id; model.route = .tasks }
        case .tasks:
            WorkbenchTaskPage(model: model, selectedID: $selectedTaskID)
        case .quota:
            WorkbenchQuotaPage(model: model)
        case .devices:
            WorkbenchDevicesPage(model: model)
        case .rules:
            WorkbenchRulesPage(model: model)
        case .studio:
            VStack(spacing: 0) {
                WorkbenchDeviceContext(model: model).padding(.horizontal, 24).padding(.top, 18)
                AmbientLibraryPage(model: model) { model.route = .rules }
            }
        }
    }
}

private struct WorkbenchHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 29, weight: .bold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WorkbenchNotice: View {
    let message: String
    var symbol = "info.circle"
    var body: some View {
        Label {
            Text(message).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        } icon: { Image(systemName: symbol).foregroundStyle(.orange) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct WorkbenchEmptyState: View {
    let title: String
    let detail: String
    let symbol: String
    var body: some View {
        VStack(spacing: 13) {
            Image(systemName: symbol).font(.system(size: 30, weight: .light)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 430)
        }.frame(maxWidth: .infinity).padding(32)
    }
}

private struct WorkbenchOverview: View {
    @ObservedObject var model: PulseModel
    let chooseTask: (PulseTask) -> Void
    private var currentTasks: [PulseTask] { Array(WorkbenchTasks.filtered(model.snapshot.tasks).prefix(4)) }
    private var attentionCount: Int { WorkbenchTasks.filtered(model.snapshot.tasks, filter: .attention).count }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 27) {
                WorkbenchHeader(title: "工作总览", subtitle: "\(Date().formatted(.dateTime.locale(Locale(identifier:"zh_CN")).month().day().weekday(.wide)))  ·  本机")
                quotaSummary
                HStack(spacing: 14) {
                    metric("运行中", value: model.snapshot.activeCount, symbol: "bolt", color: pulseMint)
                    metric("需要关注", value: attentionCount, symbol: "exclamationmark.circle", color: .orange)
                    metric("今日轮次结束", value: model.snapshot.completedToday, symbol: "checkmark.circle", color: .secondary)
                }
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("当前任务").font(.title3.weight(.semibold))
                        Spacer()
                        Button { model.route = .tasks } label: { Label("查看任务", systemImage: "arrow.right") }
                            .buttonStyle(.plain).foregroundStyle(pulseMint)
                    }
                    WorkbenchTaskFreshness(snapshot: model.snapshot)
                    if currentTasks.isEmpty {
                        WorkbenchEmptyState(title: "还没有任务记录", detail: "打开 Codex 开始任务后，可在这里查看本机最近的会话状态。", symbol: "list.bullet.rectangle")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(currentTasks) { task in
                                Button { chooseTask(task) } label: {
                                    HStack(spacing: 13) {
                                        Image(systemName: "doc.text").font(.title3).foregroundStyle(.secondary)
                                            .frame(width: 38, height: 42).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(task.title.isEmpty ? "未命名任务" : task.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                                            Text("本机 Codex").font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 8)
                                        WorkbenchTaskBadge(task: task).frame(width: 92, alignment: .leading)
                                        Text(workbenchDate(task.at)).font(.caption).foregroundStyle(.secondary).frame(width: 105, alignment: .trailing)
                                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                    }.padding(.vertical, 13).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                if task.id != currentTasks.last?.id { Divider() }
                            }
                        }
                    }
                }
                Button { model.route = .devices } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "keyboard").font(.title2).foregroundStyle(pulseMint)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.selectedDevice?.name ?? (model.selectedDeviceKey != nil ? "所选设备暂不可用" : "让键盘同步工作状态")).font(.headline)
                            Text(deviceSummary).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("查看设备").font(.callout)
                        Image(systemName: "chevron.right").font(.caption)
                    }.padding(18).background(workbenchSurface, in: RoundedRectangle(cornerRadius: 12)).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }.padding(28)
        }
    }
    private var deviceSummary: String {
        if model.deviceInventory.isStale() { return "设备状态待刷新；Codex 工作台可独立使用" }
        if let selected = model.selectedDeviceKey, model.deviceInventory.activeKey == selected { return model.snapshot.keyboard.message }
        if model.selectedDeviceKey != nil { return "已保留设备选择 · \(model.lighting ? "等待联动" : "灯光关闭")" }
        return "键盘联动可选 · 从已验证的设备开始"
    }
    private func metric(_ title: String, value: Int, symbol: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 5) {
                Text("\(value)").font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(17).frame(maxWidth: .infinity).background(workbenchSurface, in: RoundedRectangle(cornerRadius: 12))
    }
    private var quotaSummary: some View {
        HStack(spacing: 23) {
            if let quota = model.snapshot.primary ?? model.snapshot.windows.first {
                VStack(alignment: .leading, spacing: 9) {
                    Text(quota.label).font(.headline)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(quota.remaining, specifier: "%.0f")").font(.system(size: 47, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("% 剩余").font(.callout).foregroundStyle(.secondary)
                    }.foregroundStyle(model.snapshot.stale ? Color.secondary : pulseMint)
                    Text(model.snapshot.stale ? "历史数据 · 等待更新" : "最近采样 \(workbenchDate(model.snapshot.quotaAt))")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(minWidth: 175, alignment: .leading)
                Sparkline(points: quota.history).frame(maxWidth: .infinity).frame(height: 78)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("额度尚不可用").font(.title2.weight(.semibold))
                    Text("登录 Codex 后等待首次采样。任务与设备仍可分别查看。")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: 10) {
                Button("查看任务") { model.route = .tasks }.buttonStyle(.borderedProminent)
                Button("额度详情") { model.route = .quota }.buttonStyle(.bordered)
            }.controlSize(.large)
        }.padding(24).frame(minHeight: 146).background(workbenchSurface, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct WorkbenchTaskFreshness: View {
    let snapshot: PulseSnapshot
    var body: some View {
        if let error = snapshot.taskError {
            WorkbenchNotice(message: "任务更新失败：\(error)。下方如有记录，为最近一次已采集状态。", symbol: "exclamationmark.triangle")
        } else if snapshot.generatedAt <= 0 || Date().timeIntervalSince1970 - snapshot.generatedAt > 30 {
            WorkbenchNotice(message: "任务数据尚未更新；显示的是最近一次采集记录。", symbol: "clock")
        }
    }
}

private struct WorkbenchTaskBadge: View {
    let task: PulseTask
    private var color: Color {
        task.status == "active" || task.status == "completed" ? pulseMint : task.status == "failed" ? .red : .orange
    }
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: task.status == "completed" ? "checkmark.circle.fill" : task.status == "active" ? "circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: task.status == "active" ? 7 : 11))
            Text(task.label).font(.callout)
        }.foregroundStyle(color).accessibilityElement(children: .combine)
    }
}

private struct WorkbenchTaskPage: View {
    @ObservedObject var model: PulseModel
    @Binding var selectedID: String?
    @State private var query = ""
    @State private var filter: TaskStatusFilter = .all
    private var tasks: [PulseTask] { WorkbenchTasks.filtered(model.snapshot.tasks, query: query, filter: filter) }
    private var selectedTask: PulseTask? { tasks.first { $0.id == selectedID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            WorkbenchHeader(title: "任务", subtitle: "本机最近 30 个未归档会话")
            WorkbenchTaskFreshness(snapshot: model.snapshot)
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 15) {
                    Picker("任务状态", selection: $filter) {
                        ForEach(TaskStatusFilter.allCases) { item in Text(item.title).tag(item) }
                    }.pickerStyle(.segmented)
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("搜索任务名称或 ID", text: $query).textFieldStyle(.plain)
                        if !query.isEmpty {
                            Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("清除任务搜索")
                        }
                    }.padding(10).background(workbenchSurface, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08)))
                    HStack {
                        Text("任务名称"); Spacer(); Text("状态").frame(width: 86, alignment: .leading)
                    }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 11)
                    if tasks.isEmpty {
                        WorkbenchEmptyState(title: model.snapshot.tasks.isEmpty ? "还没有任务记录" : "没有匹配的任务", detail: model.snapshot.tasks.isEmpty ? "任务开始后会在这里显示。本页只读取会话元数据。" : "尝试其他关键词或状态筛选。", symbol: "list.bullet.rectangle")
                        if !query.isEmpty || filter != .all {
                            Button("清除筛选") { query = ""; filter = .all }.frame(maxWidth: .infinity)
                        }
                        Spacer()
                    } else {
                        List(selection: $selectedID) {
                            ForEach(tasks) { task in
                                HStack(alignment: .center, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text(task.title.isEmpty ? "未命名任务" : task.title).font(.system(size: 14, weight: .medium)).lineLimit(2)
                                        Text("更新于 \(workbenchDate(task.at))").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 4)
                                    WorkbenchTaskBadge(task: task).frame(width: 86, alignment: .leading)
                                }.padding(.vertical, 8).tag(task.id)
                            }
                        }.listStyle(.plain).scrollContentBackground(.hidden)
                    }
                    HStack {
                        Text("\(tasks.count) 个会话"); Spacer(); Text("按状态与最近活动排序")
                    }.font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity)
                Divider()
                taskDetail.id(selectedTask.map{$0.id+$0.title}).frame(width: 250, alignment: .topLeading)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.padding(28)
            .onAppear { reconcileSelection() }
            .onChange(of: tasks.map(\.id)) { _, _ in reconcileSelection() }
    }
    private func reconcileSelection() {
        if !tasks.contains(where: { $0.id == selectedID }) { selectedID = tasks.first?.id }
    }
    @ViewBuilder private var taskDetail: some View {
        if let task = selectedTask {
            ScrollView {
                VStack(alignment: .leading, spacing: 21) {
                    Text(task.title.isEmpty ? "未命名任务" : task.title).font(.title2.weight(.semibold)).textSelection(.enabled)
                    WorkbenchTaskBadge(task: task)
                    Divider()
                    detailLine("来源", value: "本机 Codex")
                    detailLine("最近活动", value: workbenchDate(task.at, includeYear: true))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("会话 ID").font(.caption).foregroundStyle(.secondary)
                        Text(task.id).font(.system(.caption, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                    Button { model.openTask(task) } label: {
                        Label("在 Codex 中打开", systemImage: "arrow.up.right.square").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered).controlSize(.large).disabled(WorkbenchTasks.taskURL(for: task) == nil)
                    if WorkbenchTasks.taskURL(for: task) == nil {
                        Text("当前记录缺少可用的会话标识，无法直接定位。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if task.status == "completed" {
                        Text("轮次结束表示这次回复已结束，不代表整个任务目标已经完成。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    Label("键盘联动", systemImage: "keyboard").font(.headline)
                    Text(model.selectedDevice?.name ?? "尚未选择设备").font(.callout)
                    Text(model.deviceInventory.isStale() ? "设备状态待刷新" : model.snapshot.keyboard.message).font(.caption).foregroundStyle(.secondary)
                    Button("查看设备") { model.route = .devices }.buttonStyle(.plain).foregroundStyle(pulseMint)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "sidebar.right").font(.title2).foregroundStyle(.secondary)
                Text("选择一个任务").font(.headline)
                Text("查看状态、最近活动，并跳转到 Codex 继续工作。")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
    private func detailLine(_ title: String, value: String) -> some View {
        HStack(alignment: .top) { Text(title).foregroundStyle(.secondary); Spacer(); Text(value).multilineTextAlignment(.trailing) }.font(.callout)
    }
}

private struct WorkbenchQuotaPage: View {
    @ObservedObject var model: PulseModel
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    WorkbenchHeader(title: "额度与趋势", subtitle: "按服务返回的额度窗口展示 · 仅查看，不消耗重置券")
                    if let error = model.snapshot.quotaError {
                        WorkbenchNotice(message: "额度更新失败：\(error)", symbol: "exclamationmark.triangle")
                    } else if model.snapshot.stale {
                        WorkbenchNotice(message: "额度数据已过期。下方保留最近一次采样，不能代表当前剩余额度。", symbol: "clock")
                    }
                    if model.snapshot.windows.isEmpty {
                        WorkbenchEmptyState(title: "等待额度数据", detail: "确认 Codex 已登录，后台会定期刷新额度。未知额度不会显示为 0。", symbol: "chart.xyaxis.line")
                    } else if model.snapshot.windows.count == 1, let quota = model.snapshot.windows.first {
                        quotaCard(quota, expanded: true)
                    } else {
                        // Never reserve empty adaptive columns. At compact widths each window gets a complete row.
                        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 18), count: geometry.size.width >= 936 ? 2 : 1)
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(model.snapshot.windows) { quota in quotaCard(quota, expanded: false) }
                        }
                    }
                    HStack {
                        Label("最近采样", systemImage: "clock").foregroundStyle(.secondary)
                        Text(workbenchDate(model.snapshot.quotaAt, includeYear: true))
                        Spacer()
                        if let credits = model.snapshot.resetCredits { Text("重置券 \(credits) 张").foregroundStyle(.secondary) }
                    }.font(.callout)
                    let resets = Array(model.snapshot.events.filter { $0.kind == "reset" }.suffix(5).reversed())
                    if !resets.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("已观察到的额度重置").font(.headline)
                            ForEach(Array(resets.enumerated()), id: \.offset) { _, event in
                                HStack { Text(event.message); Spacer(); Text(workbenchDate(event.at)).foregroundStyle(.secondary) }.font(.callout)
                            }
                        }.padding(20).background(workbenchSurface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    Text("趋势来自本机已采样数据；预计重置时间由服务返回，实际变化以之后采样为准。")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(28)
            }
        }
    }
    private func quotaCard(_ quota: QuotaWindow, expanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: expanded ? 22 : 18) {
            HStack(alignment: .center, spacing: 22) {
                if expanded {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(quota.label).font(.title3.weight(.semibold))
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text("\(quota.remaining, specifier: "%.0f")%")
                                .font(.system(size: 49, weight: .semibold, design: .rounded)).monospacedDigit()
                                .foregroundStyle(model.snapshot.stale ? Color.secondary : pulseMint)
                            Text("剩余").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 9) {
                        Text(quota.name).font(.headline)
                        Text("已使用 \(quota.used, specifier: "%.1f")%")
                            .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                        Label(model.snapshot.stale ? "历史采样" : "最新采样", systemImage: model.snapshot.stale ? "clock" : "checkmark.circle")
                            .font(.caption).foregroundStyle(model.snapshot.stale ? Color.secondary : pulseMint)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(quota.label).font(.title3.weight(.semibold))
                        Text(quota.name).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    QuotaRing(remaining: quota.remaining, stale: model.snapshot.stale, size: 75)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("近一小时额度趋势").font(.headline)
                    Spacer()
                    Text("\(quota.history.count) 个采样点").font(.caption).foregroundStyle(.secondary)
                }
                Sparkline(points: quota.history).frame(height: expanded ? 240 : 150)
                if let first = quota.history.first, let last = quota.history.last, quota.history.count > 1 {
                    HStack { Text(workbenchDate(first.at)); Spacer(); Text(workbenchDate(last.at)) }
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            if expanded {
                HStack(alignment: .top, spacing: 22) {
                    quotaDetail("预计重置", value: quota.reset.map { workbenchDate($0) } ?? "未提供", symbol: "arrow.clockwise")
                    quotaDetail("近期消耗速度", value: burnRateText(quota), symbol: "speedometer")
                    quotaDetail("预计耗尽", value: exhaustionText(quota), symbol: "hourglass")
                }
            } else {
                VStack(spacing: 10) {
                    HStack { Text("预计重置").foregroundStyle(.secondary); Spacer(); Text(quota.reset.map { workbenchDate($0) } ?? "未提供") }
                    HStack { Text("近期消耗速度").foregroundStyle(.secondary); Spacer(); Text(burnRateText(quota)) }
                    HStack { Text("预计耗尽").foregroundStyle(.secondary); Spacer(); Text(exhaustionText(quota)) }
                }.font(.callout)
            }
        }.padding(expanded ? 24 : 21).frame(maxWidth: .infinity, alignment: .leading)
            .background(workbenchSurface, in: RoundedRectangle(cornerRadius: 12))
    }
    private func quotaDetail(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 15, weight: .medium)).monospacedDigit().fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func burnRateText(_ quota: QuotaWindow) -> String {
        guard !model.snapshot.stale else { return "数据待更新" }
        guard quota.history.count >= 2, let rate = quota.burnRate, rate.isFinite, rate >= 0 else { return "暂不可估算" }
        return String(format: "%.1f 百分点 / 小时", rate)
    }
    private func exhaustionText(_ quota: QuotaWindow) -> String {
        guard !model.snapshot.stale else { return "数据待更新" }
        guard quota.history.count >= 2, let hours = quota.hoursLeft, hours.isFinite, hours >= 0 else { return "暂不可估算" }
        return String(format: "约 %.1f 小时后", hours)
    }
}

private struct WorkbenchDevicesPage: View {
    @ObservedObject var model: PulseModel
    @State private var inspectedID: String?
    private var inventory: DeviceInventory { model.deviceInventory }
    private var inspected: KeyboardDevice? {
        inventory.devices.first { $0.id == inspectedID } ?? model.selectedDevice ?? inventory.devices.first
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                WorkbenchHeader(title: "设备", subtitle: "选择用于状态联动的键盘 · 同时联动一台设备")
                Button { model.rescanDevices() } label: { Label("查找设备", systemImage: "arrow.clockwise") }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
            if inventory.isStale() {
                WorkbenchNotice(message: "设备列表尚未刷新。请查找设备，连接与接管状态以新发现结果为准。", symbol: "clock")
            } else if inventory.status != "ready" {
                WorkbenchNotice(message: inventory.message, symbol: "exclamationmark.triangle")
            }
            if let selected = model.selectedDeviceKey, !inventory.devices.contains(where: { $0.key == selected }) {
                WorkbenchNotice(message: "所选设备暂不可用，已保留选择。重新连接后可恢复；不会自动切换到另一台键盘。", symbol: "keyboard")
            }
            if inventory.devices.isEmpty {
                noDevices
            } else {
                HStack(alignment: .top, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("发现的设备（\(inventory.devices.count)）").font(.caption).foregroundStyle(.secondary)
                        ForEach(inventory.devices) { device in deviceRow(device) }
                        Spacer()
                    }.frame(width: 205)
                    Divider()
                    if let device = inspected { deviceDetail(device).frame(maxWidth: .infinity, maxHeight: .infinity) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text("可被发现不代表可控制。仅在型号、连接方式与键位布局经过验证后开放联动。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(28)
    }
    private var noDevices: some View {
        VStack(spacing: 18) {
            WorkbenchEmptyState(title: "还没有发现键盘", detail: "Codex 工作台不依赖键盘。需要联动时，请连接兼容设备并打开 Logitech G HUB。", symbol: "keyboard")
            VStack(alignment: .leading, spacing: 13) {
                Label("在 G HUB 中确认设备在线", systemImage: "1.circle")
                Label("使用已验证的 LIGHTSPEED 或有线连接", systemImage: "2.circle")
                Label("返回此页，点击“查找设备”", systemImage: "3.circle")
            }.font(.callout).foregroundStyle(.secondary)
            Button("返回工作总览") { model.route = .overview }.buttonStyle(.bordered)
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func deviceRow(_ device: KeyboardDevice) -> some View {
        Button { inspectedID = device.id } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "keyboard").font(.title3).foregroundStyle(device.isVerified ? pulseMint : Color.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    Text(device.name).font(.callout.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                    Text(device.connection).font(.caption).foregroundStyle(.secondary)
                    Text(device.supportLabel).font(.caption).foregroundStyle(device.isVerified ? pulseMint : Color.secondary)
                    if model.selectedDeviceKey == device.key { Text("已选择").font(.caption2).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(inspected?.id == device.id ? pulseMint.opacity(0.12) : workbenchSurface, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).accessibilityAddTraits(inspected?.id == device.id ? .isSelected : [])
    }
    private func deviceDetail(_ device: KeyboardDevice) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(device.name).font(.title.weight(.semibold))
                    Text("\(device.connection) · \(device.provider.uppercased())").foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Label(device.supportLabel, systemImage: device.isVerified ? "checkmark.seal.fill" : "info.circle")
                        .foregroundStyle(device.isVerified ? pulseMint : Color.secondary)
                    if !inventory.isStale() { Text(["ACTIVE": "设备在线", "INACTIVE": "设备离线", "UNKNOWN": "连接待确认"][device.state] ?? "连接待确认").foregroundStyle(.secondary) }
                }.font(.callout)
                Image(systemName: "keyboard").resizable().scaledToFit().foregroundStyle(pulseMint.opacity(0.8))
                    .frame(maxWidth: .infinity).frame(height: 110).padding(.vertical, 14)
                    .accessibilityHidden(true)
                Text(device.reason).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if device.isVerified, !device.capabilities.isEmpty {
                    Divider()
                    Text("适配能力").font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), alignment: .leading)], alignment: .leading, spacing: 12) {
                        ForEach(device.capabilities, id: \.self) { capability in
                            Label(capabilityLabel(capability), systemImage: "checkmark.circle").font(.callout).foregroundStyle(pulseMint)
                        }
                    }
                }
                Divider()
                if model.selectedDeviceKey == device.key {
                    Label("已选择此设备", systemImage: "checkmark.circle.fill").foregroundStyle(pulseMint)
                    Text(inventory.isStale() ? "等待刷新设备状态" : (model.snapshot.keyboard.status == "error" || (model.lighting && model.snapshot.keyboard.status == "stale")) ? model.snapshot.keyboard.message : inventory.activeKey == device.key ? model.snapshot.keyboard.message : "选择已保存 · \(model.lighting ? "等待联动接管" : "灯光尚未开启")")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("配置联动") { model.route = .rules }.buttonStyle(.borderedProminent)
                        Button("灯效工作室") { model.route = .studio }.buttonStyle(.bordered)
                    }.controlSize(.large)
                } else {
                    Button("选择此设备") { model.selectDevice(device) }.buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(!device.selectable || !device.isVerified || inventory.isStale() || inventory.status != "ready")
                    Text("切换时先释放当前设备，再尝试接管所选设备。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func capabilityLabel(_ value: String) -> String {
        ["quota": "额度显示", "quotaBar": "额度显示", "quota-keys": "额度功能键", "logo": "Logo 提醒", "keypad": "任务状态区域", "numpad": "数字小键盘", "gkeys": "G 键灯光", "g-keys": "G 键灯光", "per-key-rgb": "逐键灯光", "perKeyRGB": "逐键灯光", "ambient": "非功能区灯效", "reactive": "输入响应", "temporary-viewer": "临时接管与恢复", "idle-policy": "空闲省电"][value] ?? value
    }
}

private struct WorkbenchDeviceContext: View {
    @ObservedObject var model: PulseModel
    private var status: String {
        if (model.snapshot.keyboard.status == "error" || (model.lighting && model.snapshot.keyboard.status == "stale")) {return model.snapshot.keyboard.message}
        guard model.deviceReady else { return "可浏览设计 · 等待可用设备" }
        guard model.lighting else { return model.deviceInventory.activeKey != nil ? "正在停止联动 · 等待归还设备":"联动未开启" }
        guard let selected = model.selectedDeviceKey, model.deviceInventory.activeKey == selected else { return "联动已开启 · 等待接管" }
        return model.snapshot.keyboard.message
    }
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "keyboard").foregroundStyle(pulseMint)
            Text(model.selectedDevice?.name ?? (model.selectedDeviceKey != nil ? "所选设备暂不可用" : "尚未选择设备")).font(.callout.weight(.medium))
            Text(status)
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("设备管理") { model.route = .devices }.buttonStyle(.plain).foregroundStyle(pulseMint)
        }.padding(12).background(workbenchSurface, in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct WorkbenchRulesPage: View {
    @ObservedObject var model: PulseModel
    @State private var showBrightness = false
    private let rules: [(String, String, String)] = [
        ("额度变化", "功能键额度条", "用灯光长度显示剩余额度"),
        ("任务运行", "任务状态区域", "按运行数量切换动效"),
        ("轮次结束", "任务状态区域", "绿光提示本轮回复结束"),
        ("失败或中断", "任务状态区域", "提醒需要关注"),
        ("额度重置 / 低额度", "Logo 提醒区", "区分重置提示与额度不足")
    ]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                WorkbenchHeader(title: "联动规则", subtitle: "把工作状态变成清晰的键盘提示")
                WorkbenchDeviceContext(model: model)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rules, id: \.0) { trigger, zone, effect in
                        HStack(spacing: 14) {
                            Text(trigger).font(.callout.weight(.medium)).frame(width: 130, alignment: .leading)
                            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
                            Text(zone).font(.callout).frame(width: 120, alignment: .leading)
                            Text(effect).font(.callout).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }.padding(.vertical, 13)
                        if trigger != rules.last?.0 { Divider() }
                    }
                }.padding(.horizontal, 18).background(workbenchSurface, in: RoundedRectangle(cornerRadius: 12))
                if model.selectedDevice?.isVerified == true, model.selectedDevice?.layoutId != nil {
                    LightingPanel(model: model).padding(20).background(workbenchSurface, in: RoundedRectangle(cornerRadius: 12))
                    DisclosureGroup("亮度与省电", isExpanded: $showBrightness) {
                        LightSettingsSheet(model: model, embedded: true).padding(.top, 18)
                    }.padding(20).background(workbenchSurface, in: RoundedRectangle(cornerRadius: 12))
                } else {
                    WorkbenchEmptyState(title: "选择设备后配置联动", detail: "每种布局都有自己的可用区域。选择已验证设备后，会显示匹配的配置；Codex 工作台始终可用。", symbol: "keyboard")
                    HStack {
                        Button("选择设备") { model.route = .devices }.buttonStyle(.borderedProminent)
                        Button("浏览灯效") { model.route = .studio }.buttonStyle(.bordered)
                    }.frame(maxWidth: .infinity)
                }
            }.padding(28)
        }
    }
}

private func workbenchDate(_ timestamp: Double, includeYear: Bool = false) -> String {
    guard timestamp.isFinite, timestamp > 0 else { return "尚未更新" }
    let date = Date(timeIntervalSince1970: timestamp)
    if includeYear { return date.formatted(.dateTime.locale(Locale(identifier:"zh_CN")).year().month().day().hour().minute()) }
    if Calendar.current.isDateInToday(date) { return "今天 \(date.formatted(.dateTime.locale(Locale(identifier:"zh_CN")).hour().minute()))" }
    return date.formatted(.dateTime.locale(Locale(identifier:"zh_CN")).month().day().hour().minute())
}
