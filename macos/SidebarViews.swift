import AppKit
import SwiftUI

struct DesktopQuotaRing:View {
    let value:DesktopQuotaValue
    var lineWidth:CGFloat=6
    var fontSize:CGFloat=32
    private var color:Color {value.remaining == nil ? .gray:(value.remaining ?? 100)<=10 ? .red:pulseMint}
    var body:some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.10),style:StrokeStyle(lineWidth:lineWidth,dash:value.remaining == nil ? [3,4]:[]))
            if value.remaining != nil {
                Circle().trim(from:0,to:value.fraction)
                    .stroke(color,style:StrokeStyle(lineWidth:lineWidth,lineCap:.round)).rotationEffect(.degrees(-90))
            }
            Text(value.number).font(.system(size:fontSize,weight:.semibold,design:.rounded)).monospacedDigit()
                .foregroundStyle(value.remaining == nil ? Color.secondary:.primary)
        }.padding(lineWidth/2).aspectRatio(1,contentMode:.fit)
            .accessibilityElement(children:.ignore).accessibilityLabel(value.summary)
    }
}

struct DesktopQuotaMeter:View {
    let remaining:Double?
    let stale:Bool
    private var fraction:CGFloat {guard let remaining,remaining.isFinite else{return 0};return CGFloat(max(0,min(100,remaining))/100)}
    private var color:Color {stale ? .gray:(remaining ?? 100)<=10 ? .red:pulseMint}
    var body:some View {
        GeometryReader {geometry in
            Capsule().fill(Color.primary.opacity(0.08))
                .overlay(alignment:.leading) {Capsule().fill(color).frame(width:geometry.size.width*fraction)}
        }.frame(height:5)
            .accessibilityElement().accessibilityLabel("剩余额度")
            .accessibilityValue(remaining.map{String(format:"%.0f%%",$0)} ?? "未知")
    }
}

struct SidebarMaterial:NSViewRepresentable {
    func makeNSView(context:Context)->NSVisualEffectView {
        let view=NSVisualEffectView()
        view.material = .hudWindow;view.blendingMode = .behindWindow;view.state = .active
        return view
    }
    func updateNSView(_ view:NSVisualEffectView,context:Context) {}
}

struct SidebarSurface:View {
    var style:SidebarStyle = .glass
    var radius:CGFloat=22
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body:some View {
        Group {
            if style == .glass && !reduceTransparency {
                SidebarMaterial().overlay(Color(nsColor:.windowBackgroundColor).opacity(0.22))
            } else {Color(nsColor:.windowBackgroundColor)}
        }
        .clipShape(RoundedRectangle(cornerRadius:radius))
        .overlay(RoundedRectangle(cornerRadius:radius).strokeBorder(Color.primary.opacity(0.12),lineWidth:0.8))
    }
}

struct SidebarHandle:View {
    let snapshot:PulseSnapshot
    let tucked:Bool
    let expanded:Bool
    let side:SidebarSide
    var badge:SidebarBadge = .waveform
    var running=true
    var action:()->Void
    private var quota:DesktopQuotaValue {DesktopQuotaValue(remaining:snapshot.primary?.remaining,fresh:!snapshot.stale && running)}
    var body:some View {
        Button(action:action) {
            ZStack {
                SidebarSurface(radius:tucked ? 6:24)
                if tucked {
                    Capsule().fill(snapshot.stale ? Color.secondary:pulseMint).frame(width:3,height:22)
                } else if badge == .remaining {
                    DesktopQuotaRing(value:quota,lineWidth:2.5,fontSize:18).padding(4)
                } else {
                    Circle().trim(from:0,to:CGFloat(quota.fraction))
                        .stroke(snapshot.stale ? Color.secondary:pulseMint,style:StrokeStyle(lineWidth:2.2,lineCap:.round))
                        .rotationEffect(.degrees(-90)).padding(4)
                    Image(systemName:expanded ? (side == .left ? "chevron.left":"chevron.right"):"waveform.path")
                        .font(.system(size:18,weight:.medium)).foregroundStyle(pulseMint)
                }
            }.frame(maxWidth:.infinity,maxHeight:.infinity).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(expanded ? "收起侧边详情":"打开侧边详情")
        .accessibilityValue(quota.summary)
        .help("\(quota.summary) · 点击展开，沿边缘上下拖动")
    }
}

struct SidebarDetailContent:View {
    let snapshot:PulseSnapshot
    var running=true
    var style:SidebarStyle = .glass
    var content=SidebarContent()
    var openTask:(PulseTask)->Void={_ in}
    var openWorkbench:()->Void={}
    var openSettings:()->Void={}
    var close:()->Void={}
    @State private var page=0
    private var tasks:[PulseTask] {Array(WorkbenchTasks.filtered(snapshot.tasks).prefix(8))}
    private var taskStale:Bool {snapshot.taskError != nil || Date().timeIntervalSince1970-snapshot.generatedAt>30}
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack(spacing:10) {
                Image(systemName:"waveform.path").font(.system(size:21)).foregroundStyle(pulseMint)
                VStack(alignment:.leading,spacing:3) {
                    Text("Codex Pulse").font(.system(size:17,weight:.semibold,design:.rounded))
                    Text(!running ? "监控已暂停":snapshot.stale ? "等待最新采样":"工作状态，一眼可见")
                        .font(.system(size:11)).foregroundStyle(!running || snapshot.stale ? .orange:.secondary)
                }
                Spacer()
                Button(action:close) {Image(systemName:"xmark").frame(width:24,height:24)}
                    .buttonStyle(.plain).help("收起侧边详情（Esc）").accessibilityLabel("收起侧边详情")
            }
            if content.shows(.summary) {
                HStack(spacing:10) {
                    summary("运行中",value:"\(snapshot.activeCount)",symbol:"circle.dotted")
                    summary("今日结束",value:"\(snapshot.completedToday)",symbol:"checkmark.circle")
                }
            }
            if content.showsTabs {
                Picker("查看内容",selection:$page) {
                    Text("额度总览").tag(0)
                    Text("最近任务").tag(1)
                }.pickerStyle(.segmented).labelsHidden()
            }
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    if page == 0 || !content.showsTabs {
                        if content.shows(.quota) {
                            if snapshot.windows.isEmpty {
                                empty("等待额度数据",detail:"开始监控后，额度会显示在这里。",symbol:"chart.bar")
                            } else {
                                ForEach(snapshot.windows) {quota in quotaRow(quota)}
                            }
                        }
                        if content.hasQuotaPage,let error=snapshot.quotaError {Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true)}
                        if content.shows(.tasks) {
                            if content.shows(.quota) {Divider()}
                            HStack {
                                Text("最近任务").font(.system(size:12,weight:.semibold));Spacer()
                                if content.showsTabs {Button("单独查看"){page=1}.font(.caption).buttonStyle(.plain).foregroundStyle(pulseMint)}
                            }
                            taskList(limit:content.taskLimit)
                        }
                        if content.shows(.trend) {
                            VStack(alignment:.leading,spacing:6) {
                                Text("额度趋势 · 自动缩放").font(.system(size:11)).foregroundStyle(.secondary)
                                let primary=snapshot.primary
                                Sparkline(points:primary?.history ?? []).frame(height:46)
                            }
                        }
                    } else {
                        taskList(limit:content.taskLimit)
                    }
                    if !content.hasBody && !content.shows(.summary) {
                        Button("选择要显示的内容",action:openSettings).buttonStyle(.bordered)
                            .frame(maxWidth:.infinity).padding(.vertical,16)
                    }
                }.padding(.vertical,2)
            }.scrollIndicators(.hidden)
            HStack {
                Button(action:openWorkbench) {Label("工作台",systemImage:"arrow.up.left.and.arrow.down.right")}
                    .buttonStyle(.bordered).controlSize(.small)
                Spacer()
                let updatedAt=content.hasQuotaPage ? snapshot.quotaAt:snapshot.generatedAt
                if updatedAt>0 {Text(Date(timeIntervalSince1970:updatedAt),style:.time).font(.system(size:10)).foregroundStyle(.secondary)}
                Button(action:openSettings) {Image(systemName:"slider.horizontal.3").frame(width:26,height:26)}
                    .buttonStyle(.plain).help("便签与侧边栏设置").accessibilityLabel("便签与侧边栏设置")
            }
        }
        .padding(20)
        .background(SidebarSurface(style:style))
        .tint(pulseMint)
        .onChange(of:content) {_,_ in page=0}
    }
    private func summary(_ title:String,value:String,symbol:String)->some View {
        HStack(spacing:8) {
            Image(systemName:symbol).foregroundStyle(pulseMint)
            VStack(alignment:.leading,spacing:3) {
                Text(value).font(.system(size:21,weight:.semibold,design:.rounded)).monospacedDigit()
                Text(title).font(.system(size:10)).foregroundStyle(.secondary)
            }
            Spacer(minLength:0)
        }.padding(12).frame(maxWidth:.infinity).background(Color.primary.opacity(0.045),in:RoundedRectangle(cornerRadius:12))
    }
    private func quotaRow(_ quota:QuotaWindow)->some View {
        let value=quota.remaining.isFinite ? max(0,min(100,quota.remaining)):nil
        let metrics=StickyQuotaMetrics(quota:quota,fresh:!snapshot.stale && running)
        return VStack(alignment:.leading,spacing:8) {
            HStack(alignment:.firstTextBaseline) {
                Text("\(quota.name) · \(quota.label)").font(.system(size:12,weight:.medium)).lineLimit(1)
                Spacer(minLength:4)
                Text(value.map{String(format:"%.0f%%",$0)} ?? "—").font(.system(size:21,weight:.semibold,design:.rounded)).monospacedDigit()
            }
            DesktopQuotaMeter(remaining:value,stale:snapshot.stale)
            if content.shows(.reset) {
                HStack {
                    if metrics.secondsToReset != nil,let reset=quota.reset {
                        Text("重置");Text(Date(timeIntervalSince1970:reset),style:.relative)
                    } else {Text("重置时间待更新")}
                }.font(.system(size:10)).foregroundStyle(.secondary)
            }
            if content.shows(.consumption) {
                Text(metrics.rate.map{String(format:"消耗 %.1f 百分点/时",$0)} ?? "消耗速度 · 积累样本中").font(.system(size:10)).foregroundStyle(.secondary)
                if let hours=metrics.hoursLeft {
                    Text(String(format:"按近期速度约可用 %.1f 小时",hours)).font(.system(size:10)).foregroundStyle(.secondary)
                }
            }
        }
    }
    @ViewBuilder private func taskList(limit:Int)->some View {
        if taskStale || !running {
            Text(snapshot.taskError ?? (!running ? "监控已暂停 · 保留最近任务":"任务数据待更新"))
                .font(.caption).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true)
        }
        if tasks.isEmpty {
            empty("暂无最近任务",detail:"读取本机会话状态后显示在这里。",symbol:"list.bullet.rectangle")
        } else {
            ForEach(Array(tasks.prefix(limit))) {task in
                Button {openTask(task)} label: {
                    HStack(alignment:.top,spacing:9) {
                        Circle().fill(task.color).frame(width:6,height:6).padding(.top,5)
                        VStack(alignment:.leading,spacing:5) {
                            Text(task.title.isEmpty ? "未命名任务":task.title).font(.system(size:12,weight:.medium)).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading)
                            HStack {Text(task.label);Spacer();Text(Date(timeIntervalSince1970:task.at),style:.time)}
                                .font(.system(size:10)).foregroundStyle(.secondary)
                        }
                        Image(systemName:"arrow.up.right").font(.system(size:9)).foregroundStyle(.secondary).padding(.top,3)
                    }.padding(10).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:10))
                }.buttonStyle(.plain).disabled(WorkbenchTasks.taskURL(for:task)==nil)
                    .help("在 Codex 中打开任务")
            }
        }
    }
    private func empty(_ title:String,detail:String,symbol:String)->some View {
        VStack(alignment:.leading,spacing:8) {
            Label(title,systemImage:symbol).font(.callout)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,12)
    }
}
