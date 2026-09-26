import SwiftUI
import AppKit

struct StickyDashboard:View {
    @ObservedObject var model:PulseModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    private var controls:some View {
        HStack(spacing:7) {
            Menu {
                ForEach(StickySize.allCases) { size in
                    Button {model.setStickySize(size)} label: {
                        if model.desktopPreferences.stickySize == size {Label(size.title,systemImage:"checkmark")}
                        else {Text(size.title)}
                    }
                }
            } label: {Image(systemName:"rectangle.compress.vertical")}
                .menuStyle(.borderlessButton).fixedSize()
                .help("便签大小").accessibilityLabel("便签大小")
            Button {model.setStickyPinned(!model.stickyPinned)} label: {
                Image(systemName:model.stickyPinned ? "pin.fill":"pin")
                    .foregroundStyle(model.stickyPinned ? pulseMint:Color.secondary)
            }.help(model.stickyPinned ? "取消置顶":"置顶便签")
                .accessibilityLabel(model.stickyPinned ? "取消置顶":"置顶便签")
                .accessibilityAddTraits(model.stickyPinned ? .isSelected:[])
            Button {model.presentWindow("dashboard",using:{openWindow(id:$0)})} label: {
                Image(systemName:"arrow.up.left.and.arrow.down.right")
            }.help("打开完整工作台").accessibilityLabel("打开完整工作台")
        }.font(.system(size:10)).buttonStyle(.plain)
    }

    private var visualCard:some View {
        StickyCardContent(snapshot:model.snapshot,size:model.desktopPreferences.stickySize,running:model.running,
                          notice:model.configurationNotice,controls:AnyView(controls),miniDiameter:model.desktopPreferences.miniDiameter)
    }
    @ViewBuilder private var interactiveCard:some View {
        if model.desktopPreferences.stickySize == .mini {
            let value=DesktopQuotaValue(remaining:model.snapshot.primary?.remaining,fresh:!model.snapshot.stale && model.running)
            MiniRingInteraction(summary:value.summary,remaining:value.remaining,
                    onClick:model.desktopPreferences.miniClickAction.target.map {target in {anchor in model.stickyExpansion?.toggle(target,from:anchor)}},
                    onDragBegin:{model.stickyExpansion?.dismiss()},
                    clickDescription:model.desktopPreferences.miniClickAction.hint,makeMenu:miniMenu)
            .frame(width:model.desktopPreferences.miniDiameter,height:model.desktopPreferences.miniDiameter)
            .allowsHitTesting(true)
        } else {visualCard.contextMenu {regularMenu}}
    }
    var body:some View {
        interactiveCard
        .preferredColorScheme(model.appearance.preferredScheme).tint(pulseMint)
        .environment(\.locale,Locale(identifier:"zh_CN"))
        .background(WindowModeRegistration(mode:.sticky,coordinator:model.windows).allowsHitTesting(false).accessibilityHidden(true))
        .background(StickyWindowAccessor(pinned:model.stickyPinned,contentSize:model.desktopPreferences.stickyContentSize,
                                        resizable:model.desktopPreferences.stickySize == .standard,
                                        circular:model.desktopPreferences.stickySize == .mini).allowsHitTesting(false).accessibilityHidden(true))
        .onAppear {
            model.statusBar?.openWindow = {id in model.presentWindow(id,using:{openWindow(id:$0)})}
            model.sidebar?.start()
        }
    }
    @ViewBuilder private var regularMenu:some View {
            ForEach(StickySize.allCases) {size in
                Button {model.setStickySize(size)} label: {
                    if model.desktopPreferences.stickySize == size {Label(size.title+"便签",systemImage:"checkmark")}
                    else {Text(size.title+"便签")}
                }
            }
            Divider()
            Button(model.stickyPinned ? "取消置顶":"置顶便签"){model.setStickyPinned(!model.stickyPinned)}
            Button("打开完整工作台"){model.presentWindow("dashboard",using:{openWindow(id:$0)})}
            Button("便签与侧边栏设置") {model.settingsCategory = .desktop;openWindow(id:"settings")}
            Divider()
            Button("关闭便签"){dismissWindow(id:"sticky")}
    }
    private func miniMenu()->NSMenu {
        let menu=NSMenu();menu.autoenablesItems=false
        let slider=NSMenuItem();slider.view=MiniRingSizeMenuView(diameter:model.desktopPreferences.miniDiameter,change:{model.setMiniDiameter($0)})
        menu.addItem(slider)
        let presets=NSMenuItem(title:"常用尺寸",action:nil,keyEquivalent:"")
        let sizes=NSMenu()
        for diameter in [48.0,64,80,96,128] {
            sizes.addItem(MiniRingMenuAction.item("\(Int(diameter)) 点",selected:model.desktopPreferences.miniDiameter==diameter){model.setMiniDiameter(diameter)})
        }
        presets.submenu=sizes;menu.addItem(presets)
        menu.addItem(MiniRingMenuAction.item("恢复默认大小（96 点）"){model.setMiniDiameter(96)})
        let clickOptions=NSMenuItem(title:"左键单击后",action:nil,keyEquivalent:"")
        let actions=NSMenu()
        for action in MiniRingClickAction.allCases {
            actions.addItem(MiniRingMenuAction.item(action.title,selected:model.desktopPreferences.miniClickAction==action){model.setMiniClickAction(action)})
        }
        clickOptions.submenu=actions;menu.addItem(clickOptions)
        menu.addItem(.separator())
        menu.addItem(MiniRingMenuAction.item("置顶便签",selected:model.stickyPinned){model.setStickyPinned(!model.stickyPinned)})
        for size in StickySize.allCases {
            menu.addItem(MiniRingMenuAction.item(size.title+"便签",selected:model.desktopPreferences.stickySize==size){model.setStickySize(size)})
        }
        menu.addItem(.separator())
        menu.addItem(MiniRingMenuAction.item("便签与侧边栏设置"){model.settingsCategory = .desktop;model.presentWindow("settings",using:{openWindow(id:$0)})})
        menu.addItem(MiniRingMenuAction.item("打开完整工作台"){model.presentWindow("dashboard",using:{openWindow(id:$0)})})
        menu.addItem(MiniRingMenuAction.item("关闭便签"){dismissWindow(id:"sticky")})
        return menu
    }
}

// Also used by synthetic visual checks; no monitor or configuration access here.
struct StickyCardContent:View {
    let snapshot:PulseSnapshot
    let size:StickySize
    var running=true
    var notice:String?=nil
    var controls:AnyView?=nil
    var miniDiameter:Double=96
    private var remaining:Double? {guard let value=snapshot.primary?.remaining,value.isFinite else{return nil};return max(0,min(100,value))}
    private var status:String { !running ? "监控已暂停":snapshot.stale ? "数据待更新":"\(snapshot.activeCount) 个任务运行中" }
    var body:some View {
        Group {
            if size == .mini {
                let value=DesktopQuotaValue(remaining:snapshot.primary?.remaining,fresh:!snapshot.stale && running)
                let diameter=MiniRingSizing.normalized(miniDiameter)
                DesktopQuotaRing(value:value,lineWidth:max(2.5,diameter/16),fontSize:diameter/3).padding(max(2.5,diameter*5/96))
                    .frame(width:diameter,height:diameter)
                    .background(PulseWindowBackground().clipShape(Circle()))
                    .contentShape(Circle())
                    .help((notice ?? value.summary)+" · 拖动移动，右键打开菜单")
                    .accessibilityHint("拖动移动，右键打开便签菜单")
            } else if size == .standard {
                // Preserve the original sticky layout, padding and resizing range.
                VStack(alignment:.leading,spacing:8) {
                    if let notice {Text(notice).font(.caption2).foregroundStyle(.orange)}
                    if !running {Text("监控已暂停 · 保留最近采样").font(.caption2).foregroundStyle(.orange)}
                    PulseCard(snapshot:snapshot,expanded:true,headerControls:controls,adaptiveForeground:true)
                }
                .padding(12)
                .frame(minWidth:320,idealWidth:344,maxWidth:440,minHeight:320,alignment:.topLeading)
            } else {smallContent}
        }.background {if size != .mini {PulseWindowBackground()}}
    }
    private var smallContent:some View {
        VStack(alignment:.leading,spacing:8) {
                HStack(spacing:5) {
                    Image(systemName:"waveform.path").foregroundStyle(pulseMint)
                    Text("PULSE").font(.system(size:10,weight:.bold,design:.rounded)).tracking(1.2)
                    Spacer(minLength:2)
                    if let controls {controls}
                }
                HStack(alignment:.firstTextBaseline,spacing:8) {
                    Text(remaining.map{String(format:"%.0f",$0)} ?? "—")
                        .font(.system(size:36,weight:.semibold,design:.rounded)).monospacedDigit()
                    Text("% 剩余").font(.system(size:10)).foregroundStyle(.secondary)
                    Spacer(minLength:0)
                    Text(snapshot.primary?.label ?? "额度").font(.caption).foregroundStyle(.secondary)
                }
                DesktopQuotaMeter(remaining:remaining,stale:snapshot.stale)
                if size == .compact {
                    let metrics=StickyQuotaMetrics(quota:snapshot.primary,fresh:!snapshot.stale && running)
                    HStack {
                        Text("重置").foregroundStyle(.secondary)
                        Spacer()
                        if metrics.secondsToReset != nil,let reset=snapshot.primary?.reset {
                            Text(Date(timeIntervalSince1970:reset),style:.relative)
                        } else {Text("等待更新").foregroundStyle(.secondary)}
                    }.font(.system(size:11))
                    HStack {
                        Text("消耗速度").foregroundStyle(.secondary)
                        Spacer()
                        Text(metrics.rate.map{String(format:"%.1f 百分点 / 小时",$0)} ?? "积累样本中")
                    }.font(.system(size:11))
                }
                HStack(spacing:5) {
                    Circle().fill(snapshot.stale || !running ? .orange:pulseMint).frame(width:5,height:5)
                    Text(notice ?? status).font(.system(size:10)).foregroundStyle(notice == nil ? Color.secondary:.orange).lineLimit(1).help(notice ?? status)
                    Spacer(minLength:0)
                }
        }
        .padding(12)
        .frame(width:size.contentSize.width,height:size.contentSize.height,alignment:.topLeading)
    }
}
