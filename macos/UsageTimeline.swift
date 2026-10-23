import SwiftUI
import AppKit
import Charts
import Combine

@MainActor final class UsageTimelineLoader:ObservableObject {
    @Published private(set) var report:UsageHistoryReply?
    @Published private(set) var busy=false
    @Published private(set) var error:String?
    private var child:Process?
    private var revision=UUID()
    func cancel() {revision=UUID();if child?.isRunning == true {child?.terminate()};child=nil;busy=false}
    func load(account:String?,window:UsageTimeWindow,task:String) {
        cancel();report=nil;error=nil
        guard window.valid else {error="结束时间必须晚于开始时间。";return}
        guard let account,!account.isEmpty else {error="等待账号信息后即可查询历史。";return}
        guard let resources=Bundle.main.resourceURL,let python=Bundle.main.infoDictionary?["PulsePython"] as? String else {
            error="当前预览未连接历史数据库。";return
        }
        let process=Process(),output=Pipe(),request=revision
        process.executableURL=PulseRuntimePaths.resolve(python,resources:resources)
        process.currentDirectoryURL=resources.appendingPathComponent("backend")
        process.arguments=["-B","-m","codex_pulse.usage_history","--data-dir",PulsePaths.data.path,
                           "--account",account,"--start",String(window.start.timeIntervalSince1970),"--end",String(window.end.timeIntervalSince1970)]
        if !task.isEmpty {process.arguments! += ["--task",task]}
        process.standardOutput=output;process.standardError=FileHandle.nullDevice
        do {try process.run();child=process;busy=true}
        catch {self.error="无法启动本地历史查询。";return}
        DispatchQueue.global(qos:.userInitiated).async {[weak self] in
            let data=output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let value=try? JSONDecoder().decode(UsageHistoryReply.self,from:data)
            Task {@MainActor [weak self] in
                guard let self,self.revision==request else{return}
                self.busy=false;self.child=nil
                if process.terminationStatus==0,let value {self.report=value}
                else {self.error="历史查询未完成，请重试；已有记录会保留。"}
            }
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+15) {[weak self] in
            guard let self,self.revision==request,self.busy else{return}
            self.cancel();self.error="历史查询超时，请缩小时间范围后重试。"
        }
    }
}

struct UsageTimelineView:View {
    let snapshot:PulseSnapshot
    var fixture:UsageHistoryReply?=nil
    @StateObject private var loader=UsageTimelineLoader()
    @State private var window=UsageTimeWindow.recent(86400)
    @State private var preset="24h"
    @State private var metric:UsageTimelineMetric = .creditBalance
    @State private var quotaID=""
    @State private var taskID=""
    @State private var taskSearch=""
    @State private var hover:Date?
    @State private var dragStart:Date?
    @State private var dragEnd:Date?
    init(snapshot:PulseSnapshot,fixture:UsageHistoryReply?=nil,metric:UsageTimelineMetric = .creditBalance) {
        self.snapshot=snapshot;self.fixture=fixture;_metric=State(initialValue:metric)
        if let fixture {
            _window=State(initialValue:UsageTimeWindow(start:Date(timeIntervalSince1970:fixture.start),end:Date(timeIntervalSince1970:fixture.end)))
            _preset=State(initialValue:fixture.end-fixture.start == 3600 ? "1h":"custom")
        }
    }
    private let refresh=Timer.publish(every:30,on:.main,in:.common).autoconnect()
    private var report:UsageHistoryReply? {fixture ?? loader.report}
    private var points:[UsageTimelinePoint] {metric.points(report,quotaID:quotaID)}
    private var visibleWindow:UsageTimeWindow {
        if let fixture {return .init(start:Date(timeIntervalSince1970:fixture.start),end:Date(timeIntervalSince1970:fixture.end))}
        return window
    }
    private var requestKey:String {"\(snapshot.accountKey ?? ""):\(window.start.timeIntervalSince1970):\(window.end.timeIntervalSince1970):\(taskID)"}
    private var filteredTasks:[UsageTaskSummary] {(report?.tasks ?? []).filter{taskSearch.isEmpty || $0.title.localizedCaseInsensitiveContains(taskSearch)}}
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            HStack {
                Label("时段分析",systemImage:"chart.xyaxis.line").font(.title3.weight(.semibold))
                Spacer()
                if loader.busy {ProgressView().controlSize(.small)}
                Button("刷新",systemImage:"arrow.clockwise") {reload()}.disabled(loader.busy)
            }
            timeControls
            Picker("查看指标",selection:$metric) {
                ForEach(UsageTimelineMetric.allCases) {Text($0.title).tag($0)}
            }.pickerStyle(.segmented)
            if metric == .quota {
                Picker("额度窗口",selection:$quotaID) {
                    Text("主额度窗口").tag("")
                    ForEach(report?.quotas ?? []) {Text($0.label).tag($0.id)}
                    if !quotaID.isEmpty,report?.quotas.contains(where:{$0.id==quotaID}) != true {Text("已选窗口 · 此时段暂无记录").tag(quotaID)}
                }.frame(maxWidth:340)
            }
            if metric == .tokens || metric == .tokenRate {
                Picker("本机任务",selection:$taskID) {
                    Text("所有已记录的本机任务").tag("")
                    ForEach(report?.tasks ?? []) {Text($0.title).tag($0.id)}
                    if !taskID.isEmpty,report?.tasks.contains(where:{$0.id==taskID}) != true {Text("选中任务 · 此时段暂无记录").tag(taskID)}
                }.frame(maxWidth:480)
            }
            metrics
            if let error=snapshot.historyError {Label(error,systemImage:"externaldrive.badge.exclamationmark").font(.caption).foregroundStyle(.orange)}
            if let error=loader.error {Label(error,systemImage:"exclamationmark.triangle").font(.caption).foregroundStyle(.orange)}
            chart
            HStack {
                Text("\(visibleWindow.start.formatted(date:.abbreviated,time:.shortened)) — \(visibleWindow.end.formatted(date:.abbreviated,time:.shortened))")
                Spacer()
                Text(TimeZone.current.abbreviation() ?? TimeZone.current.identifier)
            }.font(.caption).foregroundStyle(.secondary)
            taskTable
            Text("Credit 为当前账号余额的观测变化，下降与补充独立记录，不能据此分摊任务费用。本机 Token 来自已记录任务的累计差值，不包含未被本机观察到的任务，也不等于账号全部用量。仅统计完整落在所选时段内的相邻记录；首条累计值不计消耗，跨边界的增量不插值。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            if let since=report?.accountRecordedFrom {
                Text("Credit 记录始于 \(Date(timeIntervalSince1970:since).formatted(date:.abbreviated,time:.shortened))；更早的余额无法补录。监控暂停期间会留下采样间隔。").font(.caption).foregroundStyle(.secondary)
            } else if !loader.busy {
                Text("尚无 Credit 历史。监控运行并收到新余额后开始记录；至少两次有效采样才能计算消耗。").font(.caption).foregroundStyle(.secondary)
            }
            if let since=report?.taskRecordedFrom {
                Text("本机 Token 记录始于 \(Date(timeIntervalSince1970:since).formatted(date:.abbreviated,time:.shortened))；既有会话仅恢复可读元数据范围内的记录。").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(20).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:16))
        .task(id:requestKey) {
            guard fixture==nil else{return}
            do {try await Task.sleep(for:.milliseconds(200))} catch {return}
            reload()
        }
        .onReceive(refresh) {_ in
            guard fixture==nil,preset != "custom" else{return}
            applyPreset(preset)
        }
        .onDisappear {loader.cancel()}
    }
    private var timeControls:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Picker("时间范围",selection:Binding(get:{preset},set:{applyPreset($0)})) {
                    Text("近 1 小时").tag("1h");Text("近 6 小时").tag("6h");Text("近 24 小时").tag("24h")
                    Text("近 7 天").tag("7d");Text("近 30 天").tag("30d");Text("自定义").tag("custom")
                }.frame(maxWidth:230)
                Spacer()
                Button {change(window.shifted(-0.5))} label:{Image(systemName:"chevron.left")}.help("向前查看半个时段").accessibilityLabel("前一时段")
                Button {change(window.zoom(0.5))} label:{Image(systemName:"plus.magnifyingglass")}.help("放大时间范围").accessibilityLabel("放大时间范围")
                Button {change(window.zoom(2))} label:{Image(systemName:"minus.magnifyingglass")}.help("缩小时间范围").accessibilityLabel("缩小时间范围")
                Button {change(window.shifted(0.5))} label:{Image(systemName:"chevron.right")}.help("向后查看半个时段").accessibilityLabel("后一时段")
            }
            if preset == "custom" {
                ViewThatFits(in:.horizontal) {
                    HStack {dateInput("开始",isStart:true);dateInput("结束",isStart:false)}
                    VStack(alignment:.leading) {dateInput("开始",isStart:true);dateInput("结束",isStart:false)}
                }
                if !window.valid {Text("结束时间必须晚于开始时间。").font(.caption).foregroundStyle(.orange)}
            }
        }
    }
    private func dateInput(_ title:String,isStart:Bool)->some View {
        DatePicker(title,selection:Binding(get:{isStart ? window.start:window.end},set:{date in
            if isStart {window.start=date} else {window.end=date}
        }),displayedComponents:[.date,.hourAndMinute]).datePickerStyle(.field)
    }
    private func amount(_ value:Double?,suffix:String="")->String {value.map{PulseUsageFormat.compact($0)+suffix} ?? "—"}
    private var metrics:some View {
        HStack(alignment:.top,spacing:20) {
            metricCell("Credit 观测消耗",amount(report?.credit.decreased,suffix:" cr"),tint:pulseCredit)
            metricCell("Credit 补充 / 上调",amount(report?.credit.increased,suffix:" cr"),tint:pulseMint)
            metricCell("时段 Token 增量",amount(report?.tokens),tint:.cyan)
            metricCell("平均 Token / 分钟",amount(report?.tokenPerMinute),tint:.cyan)
        }
    }
    private func metricCell(_ label:String,_ value:String,tint:Color)->some View {
        VStack(alignment:.leading,spacing:6) {
            Text(label).font(.system(size:10)).foregroundStyle(.secondary)
            Text(value).font(.system(size:19,weight:.semibold,design:.rounded)).foregroundStyle(tint).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private var chart:some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {
                Text(metric.unit).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let hover,let point=points.min(by:{abs($0.at-hover.timeIntervalSince1970)<abs($1.at-hover.timeIntervalSince1970)}) {
                    Text("\(point.date.formatted(date:.abbreviated,time:.standard)) · \(amount(point.value)) \(metric.unit)")
                        .font(.caption).monospacedDigit().lineLimit(1)
                }
            }.frame(minHeight:18)
            Chart {
                ForEach(points) {point in
                    if metric.bars {
                        BarMark(x:.value("时间",point.date),y:.value(metric.unit,point.value))
                            .foregroundStyle(metric == .creditDrop ? pulseCredit:.cyan)
                    } else {
                        LineMark(x:.value("时间",point.date),y:.value(metric.unit,point.value),series:.value("采样段",point.segment))
                            .foregroundStyle(metric == .creditBalance ? pulseCredit:pulseMint).lineStyle(StrokeStyle(lineWidth:2))
                        if points.count<40 {PointMark(x:.value("时间",point.date),y:.value(metric.unit,point.value)).symbolSize(16).foregroundStyle(metric == .creditBalance ? pulseCredit:pulseMint)}
                    }
                }
                if let hover {RuleMark(x:.value("查看时间",hover)).foregroundStyle(.secondary.opacity(0.5)).lineStyle(StrokeStyle(dash:[3,3]))}
                if let a=dragStart,let b=dragEnd {RectangleMark(xStart:.value("开始",min(a,b)),xEnd:.value("结束",max(a,b))).foregroundStyle(.cyan.opacity(0.12))}
            }
            .chartXScale(domain:visibleWindow.start...max(visibleWindow.end,visibleWindow.start.addingTimeInterval(1)))
            .chartYScale(domain:yDomain)
            .chartYAxis {AxisMarks(position:.leading)}
            .chartXAxis {AxisMarks(values:.automatic(desiredCount:5))}
            .chartOverlay {proxy in
                GeometryReader {geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover {phase in
                            if case .active(let location)=phase,let frame=proxy.plotFrame {
                                hover=proxy.value(atX:location.x-geometry[frame].minX,as:Date.self)
                            } else {hover=nil}
                        }
                        .gesture(DragGesture(minimumDistance:3).onChanged {value in
                            guard let frame=proxy.plotFrame else{return}
                            let x=geometry[frame].minX
                            dragStart=proxy.value(atX:value.startLocation.x-x,as:Date.self)
                            dragEnd=proxy.value(atX:value.location.x-x,as:Date.self)
                        }.onEnded {_ in
                            if let a=dragStart,let b=dragEnd,let next=visibleWindow.selection(a,b) {change(next)}
                            dragStart=nil;dragEnd=nil
                        })
                }
            }
            .frame(height:220)
            .overlay {if points.isEmpty {Text(loader.busy ? "正在查询…":"此时段暂无可绘制的记录").font(.callout).foregroundStyle(.secondary).allowsHitTesting(false)}}
            .accessibilityLabel(metric.title+"时间趋势")
            Text(metric == .tokenRate ? "速度按时间桶内已记录的 Token 增量折算为每分钟。拖动图表选取时段，或使用上方按钮缩放；悬停可查看采样值。":"拖动图表选取时段，或使用上方按钮缩放；悬停可查看采样值。空白不代表零用量。")
                .font(.caption).foregroundStyle(.secondary)
            if (report?.credit.gaps ?? 0)>0 {Text("所选时段包含较长采样间隔，Credit 下降保留为区间观测，不推测其发生时刻或实时速度。").font(.caption).foregroundStyle(.orange)}
        }
    }
    private var yDomain:ClosedRange<Double> {
        if metric == .quota {return 0...100}
        let low=points.map(\.value).min() ?? 0,high=points.map(\.value).max() ?? 1
        if metric.bars {return 0...max(1,high*1.08)}
        let padding=max(1,(high-low)*0.15)
        return (low-padding)...(high+padding)
    }
    private var taskTable:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Text("任务消耗与速度").font(.headline)
                Spacer()
                TextField("搜索任务",text:$taskSearch).textFieldStyle(.roundedBorder).frame(maxWidth:220)
            }
            HStack {
                Text("本机任务").frame(maxWidth:.infinity,alignment:.leading)
                Text("时段增量").frame(width:94,alignment:.trailing)
                Text("Token / 分钟").frame(width:105,alignment:.trailing)
            }.font(.caption).foregroundStyle(.secondary)
            if filteredTasks.isEmpty {Text("此时段尚无任务 Token 记录。").font(.callout).foregroundStyle(.secondary)}
            ForEach(Array(filteredTasks.prefix(50))) {task in
                HStack(spacing:12) {
                    Button {taskID=task.id;metric = .tokens} label:{
                        VStack(alignment:.leading,spacing:4) {
                            Text(task.title).font(.callout).lineLimit(1)
                            Text("\(task.samples) 次记录 · \(Date(timeIntervalSince1970:task.firstAt).formatted(date:.omitted,time:.shortened))—\(Date(timeIntervalSince1970:task.lastAt).formatted(date:.omitted,time:.shortened))\(task.adjustments>0 ? " · 计数已校正":"")")
                                .font(.system(size:10)).foregroundStyle(.secondary)
                        }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).help("查看该任务的 Token 时间分布")
                    Text(amount(task.tokens)).monospacedDigit().frame(width:94,alignment:.trailing)
                    Text(amount(task.perMinute)).monospacedDigit().frame(width:105,alignment:.trailing)
                }.padding(.vertical,5)
            }
            if filteredTasks.count>50 {Text("显示前 50 项；可搜索指定任务。").font(.caption).foregroundStyle(.secondary)}
            Text("任务速度＝时段内已记录增量 ÷ 首末采样间隔，包含等待和空闲；单次采样显示 —。点击任务可查看其时间分布。").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func applyPreset(_ value:String) {
        preset=value
        if let seconds=["1h":3600.0,"6h":21600,"24h":86400,"7d":604800,"30d":2592000][value] {window = .recent(seconds)}
    }
    private func change(_ value:UsageTimeWindow) {preset="custom";window=value;hover=nil}
    private func reload() {if fixture==nil {loader.load(account:snapshot.accountKey,window:window,task:taskID)}}
}
