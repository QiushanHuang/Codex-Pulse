import AppKit
import SwiftUI

final class SidebarPanel:NSPanel {
    var acceptsKeyboard=false
    override var canBecomeKey:Bool {acceptsKeyboard}
    override var canBecomeMain:Bool {false}
}

@MainActor final class SidebarController:NSObject,ObservableObject {
    @Published private(set) var interaction=SidebarInteraction()
    private weak var model:PulseModel?
    private var preferences=DesktopPreferences()
    private(set) var handlePanel:SidebarPanel?
    private(set) var detailPanel:SidebarPanel?
    private var hideTimer:Timer?
    private var globalClick:Any?
    private var localEvents:Any?
    private var screenObserver:NSObjectProtocol?
    private var keyObserver:NSObjectProtocol?
    private var currentScreenID=""
    private var dragOrigin:CGFloat?
    private var dragPosition:Double?
    private var hovering:Set<String>=[]
    private var pendingPreferences:DesktopPreferences?
    private var configurationScheduled=false
    private var presentationReady=false

    init(model:PulseModel) {
        self.model=model
        super.init()
        screenObserver=NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,object:nil,queue:.main){[weak self] _ in
            MainActor.assumeIsolated {self?.positionPanels()}
        }
    }
    static func screenID(_ screen:NSScreen)->String {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? ""
    }
    private var screen:NSScreen? {
        if !preferences.sidebarScreenID.isEmpty,let match=NSScreen.screens.first(where:{Self.screenID($0)==preferences.sidebarScreenID}) {return match}
        if let match=NSScreen.screens.first(where:{Self.screenID($0)==currentScreenID}) {return match}
        return NSScreen.main ?? NSScreen.screens.first
    }
    func configure(_ next:DesktopPreferences) {
        // PulseModel may be initialized inside SwiftUI's StateObject graph update.
        // Creating/layouting another NSHostingView there reenters AttributeGraph.
        // Apply the latest settings after that update, coalescing rapid changes.
        pendingPreferences=next
        guard presentationReady,!configurationScheduled else{return}
        configurationScheduled=true
        DispatchQueue.main.async {[weak self] in
            guard let self,let next=self.pendingPreferences else{return}
            self.pendingPreferences=nil;self.configurationScheduled=false
            self.applyConfiguration(next)
        }
    }
    func start() {
        // The first SwiftUI window must establish its openWindow actions before
        // a floating panel can become the application's first visible window.
        guard !presentationReady else{return}
        presentationReady=true
        configure(pendingPreferences ?? preferences)
    }
    private func applyConfiguration(_ next:DesktopPreferences) {
        let changed=preferences != next
        preferences=next
        guard next.sidebarEnabled else {disable();return}
        if handlePanel==nil {createPanels()}
        if changed {
            interaction.setAutoHide(next.sidebarAutoHide)
            positionPanels()
            scheduleHide()
        }
        applyAppearance()
    }
    func applyAppearance() {
        guard let model else{return}
        let appearance:NSAppearance?=model.appearance == .system ? nil:NSAppearance(named:model.appearance == .dark ? .darkAqua:.aqua)
        handlePanel?.appearance=appearance;detailPanel?.appearance=appearance
    }
    private func panel(title:String,keyboard:Bool)->SidebarPanel {
        let panel=SidebarPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.title=title;panel.acceptsKeyboard=keyboard;panel.isFloatingPanel=true
        panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=true
        panel.hidesOnDeactivate=false;panel.isReleasedWhenClosed=false
        panel.level = .floating;panel.acceptsMouseMovedEvents=true
        panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle]
        panel.isMovable=false;panel.isMovableByWindowBackground=false
        return panel
    }
    private func createPanels() {
        guard let model else{return}
        let handle=panel(title:"Codex Pulse 侧边入口",keyboard:false)
        let detail=panel(title:"Codex Pulse 侧边详情",keyboard:true)
        handle.identifier=NSUserInterfaceItemIdentifier("pulse-sidebar-handle")
        detail.identifier=NSUserInterfaceItemIdentifier("pulse-sidebar-detail")
        handle.contentView=NSHostingView(rootView:SidebarHandleRoot(model:model,controller:self))
        detail.contentView=NSHostingView(rootView:SidebarDetailRoot(model:model,controller:self))
        handlePanel=handle;detailPanel=detail
        keyObserver=NotificationCenter.default.addObserver(forName:NSWindow.didResignKeyNotification,object:detail,queue:.main){[weak self] _ in
            MainActor.assumeIsolated {self?.dismiss()}
        }
        positionPanels();handle.orderFrontRegardless()
        scheduleHide()
    }
    private func disable() {
        hideTimer?.invalidate();hideTimer=nil
        removeEventMonitors()
        if let keyObserver {NotificationCenter.default.removeObserver(keyObserver)};keyObserver=nil
        handlePanel?.orderOut(nil);detailPanel?.orderOut(nil)
        handlePanel?.contentView=nil;detailPanel?.contentView=nil
        handlePanel=nil;detailPanel=nil
        hovering.removeAll();dragOrigin=nil;dragPosition=nil;interaction.reset()
    }
    func positionPanels() {
        guard preferences.sidebarEnabled,let screen else{return}
        currentScreenID=Self.screenID(screen)
        let handle=SidebarGeometry.handle(in:screen.visibleFrame,side:preferences.sidebarSide,
                                         position:dragPosition ?? preferences.sidebarPosition,tucked:interaction.tucked)
        handlePanel?.setFrame(handle,display:true)
        let height=preferences.sidebarContent.preferredHeight(quotaCount:model?.snapshot.windows.count ?? 0,taskCount:model?.snapshot.tasks.count ?? 0)
        detailPanel?.setFrame(SidebarGeometry.detail(in:screen.visibleFrame,handle:handle,side:preferences.sidebarSide,preferredHeight:height),display:true)
    }
    func hover(_ inside:Bool,surface:String) {
        if inside {hovering.insert(surface)} else {hovering.remove(surface)}
        interaction.hover(!hovering.isEmpty)
        positionPanels();scheduleHide()
    }
    private func scheduleHide() {
        hideTimer?.invalidate();hideTimer=nil
        guard preferences.sidebarEnabled,interaction.autoHide,!interaction.pointerInside,!interaction.expanded,dragOrigin==nil else{return}
        hideTimer=Timer.scheduledTimer(withTimeInterval:1.2,repeats:false){[weak self] _ in
            MainActor.assumeIsolated {
                guard let self else{return}
                self.interaction.hideIfIdle();self.positionPanels();self.hideTimer=nil
            }
        }
    }
    func toggleDetails() {
        guard preferences.sidebarEnabled else{return}
        if interaction.expanded {dismiss();return}
        interaction.toggleDetails();hideTimer?.invalidate();hideTimer=nil
        positionPanels();detailPanel?.makeKeyAndOrderFront(nil)
        detailPanel?.makeFirstResponder(nil)
        installEventMonitors()
    }
    func dismiss() {
        guard interaction.expanded else{return}
        interaction.dismiss();removeEventMonitors();detailPanel?.orderOut(nil)
        hovering.remove("detail");interaction.hover(!hovering.isEmpty)
        scheduleHide()
    }
    func drag(by translation:CGFloat,ended:Bool) {
        guard let screen,let handle=handlePanel else{return}
        hideTimer?.invalidate();hideTimer=nil
        if dragOrigin==nil {dragOrigin=handle.frame.midY}
        dragPosition=SidebarGeometry.position(centerY:(dragOrigin ?? handle.frame.midY)-translation,in:screen.visibleFrame)
        positionPanels()
        if ended {
            let position=dragPosition ?? preferences.sidebarPosition
            dragOrigin=nil;dragPosition=nil
            model?.saveDesktopSettings(["sidebarPosition":position,"sidebarScreenID":Self.screenID(screen)])
            positionPanels();scheduleHide()
        }
    }
    private func installEventMonitors() {
        removeEventMonitors()
        // Mouse-only global observation does not need Input Monitoring permission.
        globalClick=NSEvent.addGlobalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown]){[weak self] _ in
            MainActor.assumeIsolated {self?.dismiss()}
        }
        localEvents=NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown,.keyDown]){[weak self] event in
            let consumed=MainActor.assumeIsolated {
                guard let self else{return false}
                if event.type == .keyDown {
                    if event.keyCode==53,event.window === self.detailPanel {self.dismiss();return true}
                } else if event.window !== self.detailPanel && event.window !== self.handlePanel {self.dismiss()}
                return false
            }
            return consumed ? nil:event
        }
    }
    private func removeEventMonitors() {
        if let globalClick {NSEvent.removeMonitor(globalClick)};globalClick=nil
        if let localEvents {NSEvent.removeMonitor(localEvents)};localEvents=nil
    }
    deinit {
        hideTimer?.invalidate()
        if let screenObserver {NotificationCenter.default.removeObserver(screenObserver)}
        if let keyObserver {NotificationCenter.default.removeObserver(keyObserver)}
        if let globalClick {NSEvent.removeMonitor(globalClick)}
        if let localEvents {NSEvent.removeMonitor(localEvents)}
    }
}

private struct SidebarHandleRoot:View {
    @ObservedObject var model:PulseModel
    @ObservedObject var controller:SidebarController
    var body:some View {
        SidebarHandle(snapshot:model.snapshot,tucked:controller.interaction.tucked,expanded:controller.interaction.expanded,
                      side:model.desktopPreferences.sidebarSide,badge:model.desktopPreferences.sidebarBadge,running:model.running,action:{controller.toggleDetails()})
            .onHover {controller.hover($0,surface:"handle")}
            .simultaneousGesture(DragGesture(minimumDistance:4).onChanged {controller.drag(by:$0.translation.height,ended:false)}
                .onEnded {controller.drag(by:$0.translation.height,ended:true)})
            .preferredColorScheme(model.appearance.preferredScheme)
            .environment(\.locale,Locale(identifier:"zh_CN"))
    }
}

private struct SidebarDetailRoot:View {
    @ObservedObject var model:PulseModel
    @ObservedObject var controller:SidebarController
    var body:some View {
        SidebarDetailContent(snapshot:model.snapshot,running:model.running,style:model.desktopPreferences.sidebarStyle,
            content:model.desktopPreferences.sidebarContent,
            openTask:{task in controller.dismiss();model.openTask(task)},
            openWorkbench:{controller.dismiss();model.statusBar?.openWindow?("dashboard")},
            openSettings:{controller.dismiss();model.settingsCategory = .desktop;model.statusBar?.openWindow?("settings")},
            close:{controller.dismiss()})
            .onHover {controller.hover($0,surface:"detail")}
            .preferredColorScheme(model.appearance.preferredScheme)
            .environment(\.locale,Locale(identifier:"zh_CN"))
    }
}
