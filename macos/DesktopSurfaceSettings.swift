import AppKit
import SwiftUI

struct DesktopSurfaceSettings:View {
    @ObservedObject var model:PulseModel
    @Environment(\.openWindow) private var openWindow
    @State private var position=0.5
    private var preferences:DesktopPreferences {model.desktopPreferences}
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
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
            Text("半透明圆钮停靠在屏幕边缘，点击查看额度与最近任务。也可用 ⌘⇧B 开关。").font(.caption).foregroundStyle(.secondary)
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
                    Text("也可以沿屏幕边缘上下拖动圆钮。").font(.caption).foregroundStyle(.secondary)
                }
                Picker("详情面板",selection:Binding(get:{preferences.sidebarStyle},set:{model.saveDesktopSettings(["sidebarStyle":$0.rawValue])})) {
                    ForEach(SidebarStyle.allCases) {Text($0.title).tag($0)}
                }.pickerStyle(.segmented)
                Divider()
                Text("详情显示内容").font(.headline)
                ForEach(SidebarSection.allCases) {section in
                    Toggle(section.title,isOn:Binding(get:{preferences.sidebarContent.sections.contains(section)},set:{model.saveDesktopSettings([section.key:$0])}))
                        .disabled(section.requiresQuota && !preferences.sidebarContent.shows(.quota))
                }
                Stepper("最多显示 \(preferences.sidebarContent.taskLimit) 个任务",value:Binding(get:{preferences.sidebarContent.taskLimit},set:{model.saveDesktopSettings(["sidebarTaskLimit":$0])}),in:1...8)
                    .disabled(!preferences.sidebarContent.shows(.tasks))
                Text("取消勾选即可隐藏；显示内容较少时，面板会自动缩短。").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("点击外部或按 Esc 收起详情。").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("展开详情"){model.sidebar?.toggleDetails()}
                }
            }.disabled(!preferences.sidebarEnabled)
        }
        .onAppear {position=preferences.sidebarPosition}
        .onChange(of:preferences.sidebarPosition) {_,value in position=value}
    }
}
