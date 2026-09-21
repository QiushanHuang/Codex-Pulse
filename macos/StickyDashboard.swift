import SwiftUI
import AppKit

struct StickyDashboard:View {
    @ObservedObject var model:PulseModel
    @Environment(\.openWindow) private var openWindow
    private var quota:QuotaWindow? {model.snapshot.primary ?? model.snapshot.windows.first}
    private var historical:Bool {model.snapshot.stale || !model.running}
    private var metrics:StickyQuotaMetrics {StickyQuotaMetrics(quota:quota,fresh:!historical)}
    private var recentTasks:[PulseTask] {Array(WorkbenchTasks.filtered(model.snapshot.tasks).prefix(3))}
    private func showWorkbench(_ route:WorkbenchRoute?=nil) {
        if let route {model.route=route}
        model.presentWindow("dashboard",using:{openWindow(id:$0)})
    }
    var body:some View {
        VStack(spacing:0) {
            HStack(spacing:10) {
                Label("CODEX PULSE",systemImage:"waveform.path").font(.system(size:11,weight:.semibold)).tracking(1.4)
                Spacer(minLength:6)
                Button {model.setStickyPinned(!model.stickyPinned)} label: {
                    Image(systemName:model.stickyPinned ? "pin.fill":"pin")
                        .foregroundStyle(model.stickyPinned ? pulseMint:Color.secondary)
                        .frame(width:24,height:24)
                }.buttonStyle(.plain)
                    .help(model.stickyPinned ? "取消置顶":"置顶便签")
                    .accessibilityLabel(model.stickyPinned ? "取消置顶":"置顶便签")
                    .accessibilityAddTraits(model.stickyPinned ? .isSelected:[])
                Button {showWorkbench()} label: {
                    Image(systemName:"arrow.up.left.and.arrow.down.right").frame(width:24,height:24)
                }.buttonStyle(.plain).help("打开完整工作台").accessibilityLabel("打开完整工作台")
            }.padding(.horizontal,16).padding(.vertical,8)
            Divider()
            ScrollView {
                VStack(alignment:.leading,spacing:12) {
                    if let notice=model.configurationNotice {
                        Text(notice).font(.caption).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true)
                    }
                    if !model.running {
                        Label("监控已暂停 · 保留最近采样",systemImage:"pause.circle").font(.caption).foregroundStyle(.orange)
                    }
                    quotaSummary
                    if let quota {
                        VStack(alignment:.leading,spacing:6) {
                            HStack {
                                Text("近一小时趋势").font(.caption.weight(.medium))
                                Spacer()
                                if historical {Text("历史数据").font(.caption2).foregroundStyle(.secondary)}
                            }
                            Sparkline(points:quota.history).frame(height:36)
                            if let first=quota.history.first,let last=quota.history.last,quota.history.count>1 {
                                HStack {Text("\(first.remaining,specifier:"%.0f")% → \(last.remaining,specifier:"%.0f")%");Spacer();Button("查看额度"){showWorkbench(.quota)}.buttonStyle(.plain).foregroundStyle(pulseMint)}
                                    .font(.caption2)
                            }
                        }
                    }
                    Divider()
                    VStack(alignment:.leading,spacing:7) {
                        HStack {
                            Text("最近任务").font(.caption.weight(.semibold))
                            Spacer()
                            Button("查看全部"){showWorkbench(.tasks)}.font(.caption).buttonStyle(.plain).foregroundStyle(pulseMint)
                        }
                        if model.snapshot.taskError != nil || Date().timeIntervalSince1970-model.snapshot.generatedAt>30 {
                            Text("任务状态待更新").font(.caption2).foregroundStyle(.orange)
                        }
                        if recentTasks.isEmpty {
                            Text("暂无本机任务，开始使用 Codex 后会显示在这里。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                        } else {
                            ForEach(recentTasks) {task in
                                HStack(alignment:.top,spacing:7) {
                                    Circle().fill(task.color).frame(width:5,height:5).padding(.top,5)
                                    Text(task.title.isEmpty ? "未命名任务":task.title).font(.system(size:12,weight:.medium)).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading)
                                    Text(task.label).font(.system(size:10)).foregroundStyle(task.color).padding(.top,1)
                                }
                            }
                        }
                    }
                }.padding(12)
            }
            Divider()
            HStack(spacing:7) {
                Circle().fill(model.running ? pulseMint:Color.orange).frame(width:6,height:6)
                Text(model.running ? "监控运行中":"监控已暂停")
                Spacer(minLength:4)
                Text(model.snapshot.generatedAt>0 ? "更新 "+Date(timeIntervalSince1970:model.snapshot.generatedAt).formatted(.dateTime.locale(Locale(identifier:"zh_CN")).hour().minute()):"等待数据")
                    .foregroundStyle(.secondary)
                Button {model.refresh()} label:{Image(systemName:"arrow.clockwise")}.buttonStyle(.plain)
                    .help("刷新已采集数据").accessibilityLabel("刷新便签显示")
            }.font(.system(size:10)).padding(.horizontal,16).padding(.vertical,9)
        }
        .frame(minWidth:320,idealWidth:360,maxWidth:440,minHeight:400,idealHeight:400,maxHeight:800)
        .background(PulseWindowBackground())
        .preferredColorScheme(model.appearance.preferredScheme).tint(pulseMint)
        .background(WindowModeRegistration(mode:.sticky,coordinator:model.windows).allowsHitTesting(false).accessibilityHidden(true))
        .background(StickyWindowAccessor(pinned:model.stickyPinned).allowsHitTesting(false).accessibilityHidden(true))
        .onAppear {
            model.statusBar?.openWindow = {id in model.presentWindow(id,using:{openWindow(id:$0)})}
        }
    }
    private func resetCaption(_ reset:Double)->String {
        guard let seconds=metrics.secondsToReset else{return "重置时间待确认"}
        let hours=Int(seconds/3600),days=hours/24
        if days>0 {return "预计重置 \(days)天\(hours%24)小时"}
        if hours>0 {return "预计重置 \(hours)小时"}
        return "预计重置 \(max(1,Int(seconds/60)))分钟"
    }
    private var quotaSummary:some View {
        VStack(alignment:.leading,spacing:8) {
            HStack(spacing:14) {
                QuotaRing(remaining:quota?.remaining,stale:historical,size:76)
                VStack(alignment:.leading,spacing:5) {
                    Text(quota.map{$0.name+" · "+$0.label} ?? "等待额度数据").font(.system(size:13,weight:.semibold)).fixedSize(horizontal:false,vertical:true)
                    if let rate=metrics.rate {
                        Text("\(rate,specifier:"%.1f") 百分点 / 小时").font(.system(size:12,weight:.medium,design:.monospaced)).foregroundStyle(pulseMint)
                    } else {Text(historical ? "消耗速度待更新":"消耗速度 · 积累样本中").font(.system(size:11)).foregroundStyle(.secondary)}
                    if let hours=metrics.hoursLeft {
                        Text("预计约 \(hours,specifier:"%.1f") 小时用完").font(.system(size:11,weight:.medium)).foregroundStyle(pulseMint)
                            .help("按近期消耗速度估算，实际用完时间可能变化")
                    } else {Text(historical ? "预计用完时间待更新":"预计用完 · 暂不可估算").font(.system(size:10)).foregroundStyle(.secondary)}
                    if let reset=quota?.reset {
                        Text(resetCaption(reset)).font(.system(size:10)).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            HStack {
                Label("\(model.snapshot.activeCount) 运行",systemImage:"circle.dotted")
                Spacer()
                Label("\(model.snapshot.completedToday) 今日轮次结束",systemImage:"checkmark.circle")
            }.font(.system(size:11)).foregroundStyle(.secondary)
        }.padding(.vertical,2)
    }
}
