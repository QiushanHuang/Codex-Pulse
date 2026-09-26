import AppKit
import SwiftUI

@MainActor final class StickyExpansionController {
    private weak var model:PulseModel?
    private weak var anchor:NSView?
    private var localEvents:Any?
    private var globalEvents:Any?
    private(set) var panel:SidebarPanel?
    private(set) var mode:StickySize?
    init(model:PulseModel) {self.model=model}

    func toggle(_ mode:StickySize,from anchor:NSView) {
        if panel != nil {dismiss();return}
        guard mode != .mini,let model,let window=anchor.window,
              let screen=window.screen ?? NSScreen.main else{return}
        self.anchor=anchor;self.mode=mode
        let panel=SidebarPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.acceptsKeyboard=true;panel.isFloatingPanel=true
        panel.title="Codex Pulse 临时详情";panel.identifier=NSUserInterfaceItemIdentifier("mini-sticky-details")
        panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=true
        panel.hidesOnDeactivate=false;panel.isReleasedWhenClosed=false;panel.level = .floating
        panel.collectionBehavior=[.fullScreenAuxiliary,.ignoresCycle]
        let rect=window.convertToScreen(anchor.convert(anchor.bounds,to:nil))
        let frame=StickyExpansionGeometry.frame(anchor:rect,in:screen.visibleFrame,size:mode.contentSize)
        panel.contentView=NSHostingView(rootView:StickyExpansionContent(model:model,mode:mode,close:{[weak self] in self?.dismiss()})
            .frame(width:frame.width,height:frame.height))
        self.panel=panel
        panel.setFrame(frame,display:true);panel.makeKeyAndOrderFront(nil);panel.makeFirstResponder(nil)
        globalEvents=NSEvent.addGlobalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown]){[weak self] _ in
            MainActor.assumeIsolated {self?.dismiss()}
        }
        localEvents=NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown,.keyDown]){[weak self] event in
            let consumed=MainActor.assumeIsolated {
                guard let self else{return false}
                if event.type == .keyDown {
                    if event.keyCode==53,event.window === self.panel {self.dismiss();return true}
                } else if event.window !== self.panel && event.window !== self.anchor?.window {self.dismiss()}
                return false
            }
            return consumed ? nil:event
        }
    }
    func synchronize(_ preferences:DesktopPreferences) {
        if let mode,preferences.stickySize != .mini || preferences.miniClickAction.target != mode {dismiss()}
    }
    func dismiss() {
        if let localEvents {NSEvent.removeMonitor(localEvents)};localEvents=nil
        if let globalEvents {NSEvent.removeMonitor(globalEvents)};globalEvents=nil
        panel?.orderOut(nil);panel?.contentView=nil;panel=nil;mode=nil;anchor=nil
    }
    deinit {
        if let localEvents {NSEvent.removeMonitor(localEvents)}
        if let globalEvents {NSEvent.removeMonitor(globalEvents)}
    }
}

private struct StickyExpansionContent:View {
    @ObservedObject var model:PulseModel
    let mode:StickySize
    let close:()->Void
    var body:some View {
        StickyCardContent(snapshot:model.snapshot,size:mode,running:model.running,notice:model.configurationNotice,
            controls:AnyView(HStack(spacing:9) {
                Button {close();model.statusBar?.openWindow?("dashboard")} label:{Image(systemName:"arrow.up.left.and.arrow.down.right")}
                    .help("打开工作台").accessibilityLabel("打开工作台")
                Button(action:close) {Image(systemName:"xmark")}.help("收起临时详情").accessibilityLabel("收起临时详情")
            }.font(.system(size:10)).buttonStyle(.plain)))
            .clipShape(RoundedRectangle(cornerRadius:16))
            .preferredColorScheme(model.appearance.preferredScheme)
            .environment(\.locale,Locale(identifier:"zh_CN"))
    }
}
