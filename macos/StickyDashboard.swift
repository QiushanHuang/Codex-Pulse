import SwiftUI
import AppKit

struct StickyDashboard:View {
    @ObservedObject var model:PulseModel
    @Environment(\.openWindow) private var openWindow

    private var controls:some View {
        HStack(spacing:7) {
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

    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            if let notice=model.configurationNotice {
                Text(notice).font(.caption2).foregroundStyle(.orange)
            }
            if !model.running {
                Text("监控已暂停 · 保留最近采样").font(.caption2).foregroundStyle(.orange)
            }
            PulseCard(snapshot:model.snapshot,expanded:true,headerControls:AnyView(controls),adaptiveForeground:true)
        }
        .padding(12)
        .frame(minWidth:320,idealWidth:344,maxWidth:440,minHeight:320,alignment:.topLeading)
        .background(PulseWindowBackground())
        .preferredColorScheme(model.appearance.preferredScheme).tint(pulseMint)
        .environment(\.locale,Locale(identifier:"zh_CN"))
        .background(WindowModeRegistration(mode:.sticky,coordinator:model.windows).allowsHitTesting(false).accessibilityHidden(true))
        .background(StickyWindowAccessor(pinned:model.stickyPinned).allowsHitTesting(false).accessibilityHidden(true))
        .onAppear {
            model.statusBar?.openWindow = {id in model.presentWindow(id,using:{openWindow(id:$0)})}
        }
    }
}
