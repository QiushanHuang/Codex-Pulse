import AppKit
import SwiftUI

struct DesktopSurfaceSettings:View {
    @ObservedObject var model:PulseModel
    @Environment(\.openWindow) private var openWindow
    @State private var position=0.5
    @State private var detailWidth=376.0
    @State private var detailHeight=570.0
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var preferences:DesktopPreferences {model.desktopPreferences}
    private var placementDisplayID:String {
        let ids=NSScreen.screens.map{SidebarController.screenID($0)}
        if ids.contains(preferences.placementScreenID) {return preferences.placementScreenID}
        if ids.contains(preferences.sidebarScreenID) {return preferences.sidebarScreenID}
        return NSScreen.main.map{SidebarController.screenID($0)} ?? ids.first ?? ""
    }
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            Text("液态玻璃与圆环配色").font(.headline)
            Picker("外观预设",selection:Binding(get:{preferences.glassPreset},set:{model.saveDesktopSettings($0.configuration)})) {
                ForEach(GlassPreset.allCases) {Text($0.title).tag($0)}
            }.pickerStyle(.segmented)
            Text("清透保留更轻的原生折射；柔雾增强背景模糊；高对比适合复杂桌面。修改下方参数会进入自定义。")
                .font(.caption).foregroundStyle(.secondary)
            Picker("玻璃质感",selection:Binding(get:{preferences.glassMaterial},set:{model.saveDesktopSettings(["glassMaterial":$0.rawValue,"glassPreset":"custom"])})) {
                ForEach(GlassMaterial.allCases) {Text($0.title).tag($0)}
            }.pickerStyle(.segmented).disabled(reduceTransparency)
            HStack {
                Text("玻璃透明度")
                Slider(value:Binding(get:{preferences.glassTransparency},set:{model.saveDesktopSettings(["glassTransparency":$0,"glassPreset":"custom"])}),in:0...1,step:0.05)
                    .accessibilityLabel("玻璃透明度")
                Text("\(Int((preferences.glassTransparency*100).rounded()))%").monospacedDigit().frame(width:44,alignment:.trailing)
            }.disabled(reduceTransparency)
            Text(reduceTransparency ? "系统已开启减少透明度，当前使用实色背景。":"越高越通透；保留系统原生折射与模糊，仅调整底色覆盖。")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing:24) {
                ColorPicker("外环 · 套餐",selection:Binding(get:{RingPalette.color(preferences.outerRingColor,fallback:pulseMint)},set:{model.saveDesktopSettings(["outerRingColor":RingPalette.hex($0),"glassPreset":"custom"])}),supportsOpacity:false)
                ColorPicker("内环",selection:Binding(get:{RingPalette.color(preferences.innerRingColor,fallback:pulseCredit)},set:{model.saveDesktopSettings(["innerRingColor":RingPalette.hex($0),"glassPreset":"custom"])}),supportsOpacity:false)
                Button("恢复默认外观") {
                    var values=GlassPreset.crystal.configuration;values["outerRingColor"]=NSNull();values["innerRingColor"]=NSNull()
                    model.saveDesktopSettings(values)
                }
            }
            HStack {
                Spacer()
                QuotaRing(remaining:70,stale:false,size:88,credits:PulseCredits(balance:128.5,unlimited:false),resetCredits:2)
                    .padding(12).background(SidebarSurface()).desktopAppearance(preferences)
                VStack(alignment:.leading,spacing:4) {
                    Text("外观预览").font(.callout)
                    Text("示例数据 · 不影响真实额度").font(.caption).foregroundStyle(.secondary)
                    Text("低额度警示仍保留红色。 ").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Divider()
            Text("圆环中心").font(.headline)
            Picker("环内显示",selection:Binding(get:{preferences.ringCenter},set:{model.saveDesktopSettings(["ringCenter":$0.rawValue])})) {
                ForEach(RingCenterContent.allCases) {Text($0.title).tag($0)}
            }.pickerStyle(.segmented)
            Text("便签、迷你圆环与侧边栏共用此选项；也可右键便签切换。Credit 余额为用量点数，可用重置次数为重置券数量；切换显示不会使用重置券。").font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("位置预设与自定义").font(.headline)
            Picker("目标显示器",selection:Binding(get:{placementDisplayID},set:{model.saveDesktopSettings(["placementScreenID":$0])})) {
                ForEach(NSScreen.screens,id:\.self) {screen in Text(screen.localizedName).tag(SidebarController.screenID(screen))}
            }
            Picker("位置预设",selection:Binding(get:{preferences.positionPreset},set:{model.sidebar?.place($0,on:placementDisplayID)})) {
                ForEach(DesktopPositionPreset.allCases) {Text($0.title).tag($0)}
            }
            Text("位置预设立即应用；自定义坐标在点击按钮后应用为便签。").font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("横向").frame(width:32,alignment:.leading)
                Slider(value:Binding(get:{preferences.stickyPositionX},set:{model.saveDesktopSettings(["stickyPositionX":$0,"positionPreset":"custom"])}),in:0...1,step:0.01).accessibilityLabel("自定义便签横向位置")
                Text("\(Int((preferences.stickyPositionX*100).rounded()))%").monospacedDigit().frame(width:44)
            }
            HStack {
                Text("纵向").frame(width:32,alignment:.leading)
                Slider(value:Binding(get:{preferences.stickyPositionY},set:{model.saveDesktopSettings(["stickyPositionY":$0,"positionPreset":"custom"])}),in:0...1,step:0.01).accessibilityLabel("自定义便签纵向位置")
                Text("\(Int((preferences.stickyPositionY*100).rounded()))%").monospacedDigit().frame(width:44)
            }
            HStack {
                Text("横向从左到右，纵向从下到上；自动避开越界。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("应用便签位置") {model.sidebar?.placeCustomSticky(on:placementDisplayID,x:preferences.stickyPositionX,y:preferences.stickyPositionY)}
            }
            Divider()
            Text("便签大小").font(.headline)
            Picker("展示框",selection:Binding(get:{preferences.stickySize},set:{model.setStickySize($0)})) {
                ForEach(StickySize.allCases) {Text($0.title).tag($0)}
            }.pickerStyle(.segmented)
            Text("\(Int(preferences.stickyContentSize.width)) × \(Int(preferences.stickyContentSize.height)) · \(preferences.stickySize.detail)")
                .font(.caption).foregroundStyle(.secondary)
            if preferences.stickySize == .mini {
                HStack {
                    Text("圆环直径").font(.callout)
                    Slider(value:Binding(get:{preferences.miniDiameter},set:{model.setMiniDiameter($0)}),in:MiniRingSizing.range,step:1).accessibilityLabel("圆环直径")
                    Text("\(Int(preferences.miniDiameter))").monospacedDigit().frame(width:30,alignment:.trailing)
                    Button("重置"){model.setMiniDiameter(96)}
                }
                Text("可在 40–160 点之间调整，也可直接右键圆环拖动大小滑块。").font(.caption).foregroundStyle(.secondary)
            }
            Picker("单击圆环临时展开",selection:Binding(get:{preferences.miniClickAction},set:{model.setMiniClickAction($0)})) {
                ForEach(MiniRingClickAction.allCases) {Text($0.title).tag($0)}
            }.pickerStyle(.segmented)
            Text("圆环保持原样；再次单击、点击外部或按 Esc 收起。拖动时也会收起浮层。").font(.caption).foregroundStyle(.secondary)
            HStack {
                Toggle("便签置顶",isOn:Binding(get:{model.stickyPinned},set:{model.setStickyPinned($0)}))
                Spacer()
                Button("打开便签"){model.presentWindow("sticky",using:{openWindow(id:$0)})}
            }
            Divider()
            Toggle("启用屏幕侧边栏",isOn:Binding(get:{preferences.sidebarEnabled},set:{model.saveDesktopSettings(["sidebarEnabled":$0])}))
                .font(.headline)
            Text("拖到左右边缘可停靠，拖入屏幕内部变为便签；便签拖回边缘可重新停靠。右键菜单和设置中可选择显示器。也可用 ⌘⇧B 开关。").font(.caption).foregroundStyle(.secondary)
            VStack(alignment:.leading,spacing:16) {
                Picker("圆钮内容",selection:Binding(get:{preferences.sidebarBadge},set:{model.saveDesktopSettings(["sidebarBadge":$0.rawValue])})) {
                    ForEach(SidebarBadge.allCases) {Text($0.title).tag($0)}
                }.pickerStyle(.segmented)
                Picker("停靠位置",selection:Binding(get:{preferences.sidebarSide},set:{model.saveDesktopSettings(["sidebarSide":$0.rawValue])})) {
                    ForEach(SidebarSide.allCases) {Text($0.title).tag($0)}
                }.pickerStyle(.segmented)
                Picker("显示器",selection:Binding(get:{preferences.sidebarScreenID},set:{model.saveDesktopSettings(["sidebarScreenID":$0])})) {
                    Text("当前显示器").tag("")
                    ForEach(NSScreen.screens,id:\.self) {screen in
                        Text(screen.localizedName).tag(SidebarController.screenID(screen))
                    }
                    if !preferences.sidebarScreenID.isEmpty,!NSScreen.screens.contains(where:{SidebarController.screenID($0)==preferences.sidebarScreenID}) {
                        Text("已断开的显示器（暂用当前屏幕）").tag(preferences.sidebarScreenID)
                    }
                }
                Picker("显示方式",selection:Binding(get:{preferences.sidebarAutoHide},set:{model.saveDesktopSettings(["sidebarAutoHide":$0])})) {
                    Text("自动隐藏").tag(true)
                    Text("始终显示").tag(false)
                }.pickerStyle(.segmented)
                Text(preferences.sidebarAutoHide ? "移开鼠标 1.2 秒后收起到窄边；移入唤回圆钮，点击展开详情。":"圆钮保持可见；点击展开详情，再点一次收起。")
                    .font(.caption).foregroundStyle(.secondary)
                VStack(alignment:.leading,spacing:8) {
                    Text("垂直位置").font(.callout)
                    HStack {
                        Text("下").font(.caption).foregroundStyle(.secondary)
                        Slider(value:$position,in:0...1,onEditingChanged:{editing in
                            if !editing {model.saveDesktopSettings(["sidebarPosition":position])}
                        }).accessibilityLabel("侧边栏垂直位置")
                        Text("上").font(.caption).foregroundStyle(.secondary)
                        Button("居中"){position=0.5;model.saveDesktopSettings(["sidebarPosition":0.5])}
                    }
                    Text("也可自由拖动圆钮跨屏移动，松手时自动选择所在显示器。").font(.caption).foregroundStyle(.secondary)
                }
                Picker("详情面板",selection:Binding(get:{preferences.sidebarStyle},set:{model.saveDesktopSettings(["sidebarStyle":$0.rawValue])})) {
                    ForEach(SidebarStyle.allCases) {Text($0.title).tag($0)}
                }.pickerStyle(.segmented)
                Divider()
                Text("展开面板尺寸").font(.headline)
                HStack(spacing:10) {
                    Text("宽")
                    TextField("面板宽度",value:$detailWidth,format:.number.precision(.fractionLength(0))).textFieldStyle(.roundedBorder).frame(width:72)
                    Text("高")
                    TextField("面板高度",value:$detailHeight,format:.number.precision(.fractionLength(0))).textFieldStyle(.roundedBorder).frame(width:72)
                    Text("点").foregroundStyle(.secondary)
                    Spacer(minLength:0)
                    Button("应用尺寸") {
                        model.saveDesktopSettings(["sidebarDetailWidth":SidebarDetailSizing.normalized(detailWidth,in:SidebarDetailSizing.widthRange) ?? 376,"sidebarDetailHeight":SidebarDetailSizing.normalized(detailHeight,in:SidebarDetailSizing.heightRange) ?? 570])
                    }
                    Button("恢复自适应") {model.saveDesktopSettings(["sidebarDetailWidth":NSNull(),"sidebarDetailHeight":NSNull()])}
                }
                Text("也可拖动面板边缘或边角调整。宽 300–960 点，高 200–1200 点；实际大小不超过所在显示器。")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                Text("详情显示内容").font(.headline)
                ForEach(SidebarSection.allCases) {section in
                    Toggle(section.title,isOn:Binding(get:{preferences.sidebarContent.sections.contains(section)},set:{model.saveDesktopSettings([section.key:$0])}))
                        .disabled(section.requiresQuota && !preferences.sidebarContent.shows(.quota))
                }
                Stepper("最多显示 \(preferences.sidebarContent.taskLimit) 个任务",value:Binding(get:{preferences.sidebarContent.taskLimit},set:{model.saveDesktopSettings(["sidebarTaskLimit":$0])}),in:1...8)
                    .disabled(!preferences.sidebarContent.shows(.tasks))
                Text("取消勾选即可隐藏；自适应模式随内容调整高度，自定义尺寸会保持。").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("点击外部或按 Esc 收起详情。").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("展开详情"){model.sidebar?.toggleDetails()}
                }
            }.disabled(!preferences.sidebarEnabled)
        }
        .onAppear {position=preferences.sidebarPosition;syncDetailSize()}
        .onChange(of:preferences.sidebarPosition) {_,value in position=value}
        .onChange(of:preferences.sidebarDetailWidth) {_,_ in syncDetailSize()}
        .onChange(of:preferences.sidebarDetailHeight) {_,_ in syncDetailSize()}
    }
    private func syncDetailSize() {
        detailWidth=preferences.sidebarDetailWidth ?? 376
        detailHeight=preferences.sidebarDetailHeight ?? Double(preferences.sidebarContent.preferredHeight(quotaCount:model.snapshot.windows.count,taskCount:model.snapshot.tasks.count))
    }

}
