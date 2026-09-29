import AppKit
import SwiftUI

final class SidebarPanel:NSPanel {
    var acceptsKeyboard=false
    var primaryEventHandler:((NSEvent)->Bool)?
    var contextMenuProvider:(()->NSMenu?)?
    var contextMenuBegan:(()->Void)?
    var contextMenuEnded:(()->Void)?
    var presentContextMenu:(NSMenu,NSEvent,NSView)->Void = {menu,event,view in
        NSMenu.popUpContextMenu(menu,with:event,for:view)
    }
    override var canBecomeKey:Bool {acceptsKeyboard}
    override var canBecomeMain:Bool {false}
    func contextMenu(for event:NSEvent)->NSMenu? {
        guard event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) else {return nil}
        return contextMenuProvider?()
    }
    override func sendEvent(_ event:NSEvent) {
        // Route before SwiftUI buttons and glass hit-testing consume the event.
        guard let menu=contextMenu(for:event),let contentView else {
            if primaryEventHandler?(event) == true {return}
            super.sendEvent(event);return
        }
        contextMenuBegan?()
        defer {contextMenuEnded?()}
        presentContextMenu(menu,event,contentView)
    }
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
    private var resizeObserver:NSObjectProtocol?
    private var preservingResizeFrame=false
    private var resizeSession:SidebarResizeSession?
    private var currentScreenID=""
    private var dragOrigin:CGFloat?
    private var dragPosition:Double?
    private var hovering:Set<String>=[]
    private var pendingPreferences:DesktopPreferences?
    private var configurationScheduled=false
    private var presentationReady=false
    private var contextMenuTracking=false
    private var pointerAnchor:NSPoint?
    private var freeDragOrigin:NSPoint?
    private var freeDragging=false
    var eventScreenLocation:(NSEvent)->NSPoint?={event in
        guard let point=event.cgEvent?.location,let main=NSScreen.screens.first else{return nil}
        return NSPoint(x:point.x,y:main.frame.maxY-point.y)
    }
    var displays:[DesktopDisplay] {NSScreen.screens.map{DesktopDisplay(id:Self.screenID($0),name:$0.localizedName,frame:$0.visibleFrame)}}
    var selectedDisplayID:String {screen.map{Self.screenID($0)} ?? ""}
    func selectDisplay(_ id:String) {
        guard displays.contains(where:{$0.id==id}) else{return}
        model?.saveDesktopSettings(["sidebarScreenID":id])
    }
    func trackMenu(_ tracking:Bool) {
        contextMenuTracking=tracking
        if tracking {hideTimer?.invalidate();hideTimer=nil} else {scheduleHide()}
    }

    init(model:PulseModel) {
        self.model=model
        super.init()
        screenObserver=NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,object:nil,queue:.main){[weak self] _ in
            MainActor.assumeIsolated {self?.objectWillChange.send();self?.positionPanels()}
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
        var mask:NSWindow.StyleMask=[.borderless,.nonactivatingPanel]
        if keyboard {mask.insert(.resizable)}
        let panel=SidebarPanel(contentRect:.zero,styleMask:mask,backing:.buffered,defer:false)
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
        for surface in [handle,detail] {
            surface.contextMenuProvider={[weak self] in self?.makeContextMenu()}
            surface.contextMenuBegan={[weak self] in
                self?.contextMenuTracking=true;self?.hideTimer?.invalidate();self?.hideTimer=nil
            }
            surface.contextMenuEnded={[weak self] in
                self?.contextMenuTracking=false;self?.scheduleHide()
            }
        }
        handle.primaryEventHandler={[weak self] event in self?.handlePointer(event) ?? false}
        detail.primaryEventHandler={[weak self] event in self?.handleResizePointer(event) ?? false}
        handlePanel=handle;detailPanel=detail
        keyObserver=NotificationCenter.default.addObserver(forName:NSWindow.didResignKeyNotification,object:detail,queue:.main){[weak self] _ in
            MainActor.assumeIsolated {if self?.contextMenuTracking != true && self?.resizeSession == nil {self?.dismiss()}}
        }
        resizeObserver=NotificationCenter.default.addObserver(forName:NSWindow.didEndLiveResizeNotification,object:detail,queue:.main){[weak self] _ in
            MainActor.assumeIsolated {self?.rememberDetailSize()}
        }
        positionPanels();handle.orderFrontRegardless()
        scheduleHide()
    }
    private func disable() {
        hideTimer?.invalidate();hideTimer=nil
        removeEventMonitors()
        if let keyObserver {NotificationCenter.default.removeObserver(keyObserver)};keyObserver=nil
        if let resizeObserver {NotificationCenter.default.removeObserver(resizeObserver)};resizeObserver=nil
        preservingResizeFrame=false
        resizeSession=nil
        handlePanel?.orderOut(nil);detailPanel?.orderOut(nil)
        handlePanel?.contentView=nil;detailPanel?.contentView=nil
        handlePanel=nil;detailPanel=nil
        hovering.removeAll();dragOrigin=nil;dragPosition=nil;interaction.reset()
        contextMenuTracking=false;pointerAnchor=nil;freeDragOrigin=nil;freeDragging=false
    }
    func positionPanels() {
        guard preferences.sidebarEnabled,pointerAnchor==nil,let screen else{return}
        currentScreenID=Self.screenID(screen)
        let handle=SidebarGeometry.handle(in:screen.visibleFrame,side:preferences.sidebarSide,
                                         position:dragPosition ?? preferences.sidebarPosition,tucked:interaction.tucked)
        handlePanel?.setFrame(handle,display:true)
        let height=preferences.sidebarDetailHeight.map{CGFloat($0)} ?? preferences.sidebarContent.preferredHeight(quotaCount:model?.snapshot.windows.count ?? 0,taskCount:model?.snapshot.tasks.count ?? 0)
        let width=CGFloat(preferences.sidebarDetailWidth ?? 376)
        guard let detail=detailPanel else{return}
        detail.contentMinSize=NSSize(width:min(300,max(1,screen.visibleFrame.width-16)),height:min(200,max(1,screen.visibleFrame.height-16)))
        detail.contentMaxSize=NSSize(width:min(960,max(1,screen.visibleFrame.width-16)),height:min(1200,max(1,screen.visibleFrame.height-16)))
        guard !detail.inLiveResize,!preservingResizeFrame,resizeSession == nil else{return}
        detail.setFrame(SidebarGeometry.detail(in:screen.visibleFrame,handle:handle,side:preferences.sidebarSide,preferredHeight:height,preferredWidth:width),display:true)
    }
    private func rememberDetailSize() {
        guard let detail=detailPanel,let screen,!preservingResizeFrame else{return}
        var frame=detail.frame
        frame.origin.x=max(screen.visibleFrame.minX+8,min(frame.minX,screen.visibleFrame.maxX-frame.width-8))
        frame.origin.y=max(screen.visibleFrame.minY+8,min(frame.minY,screen.visibleFrame.maxY-frame.height-8))
        if frame != detail.frame {detail.setFrame(frame,display:true)}
        preservingResizeFrame=true
        model?.saveDesktopSettings(["sidebarDetailWidth":Double(frame.width.rounded()),"sidebarDetailHeight":Double(frame.height.rounded())])
        DispatchQueue.main.async {[weak self] in self?.preservingResizeFrame=false}
    }
    func handleResizePointer(_ event:NSEvent)->Bool {
        guard let detail=detailPanel,let screen else{return false}
        switch event.type {
        case .leftMouseDown:
            resizeSession=SidebarResizeSession(frame:detail.frame,point:detail.convertPoint(toScreen:event.locationInWindow))
            return resizeSession != nil
        case .leftMouseDragged:
            guard let resizeSession else{return false}
            let point=eventScreenLocation(event) ?? detail.convertPoint(toScreen:event.locationInWindow)
            detail.setFrame(resizeSession.frame(at:point,in:screen.visibleFrame),display:true)
            return true
        case .leftMouseUp:
            guard let session=resizeSession else{return false}
            resizeSession=nil
            if detail.frame != session.original {rememberDetailSize()}
            return true
        default:return false
        }
    }

    func hover(_ inside:Bool,surface:String) {
        guard pointerAnchor==nil,resizeSession==nil else{return}
        if inside {hovering.insert(surface)} else {hovering.remove(surface)}
        interaction.hover(!hovering.isEmpty)
        positionPanels();scheduleHide()
    }
    private func scheduleHide() {
        hideTimer?.invalidate();hideTimer=nil
        guard preferences.sidebarEnabled,pointerAnchor==nil,!contextMenuTracking,interaction.autoHide,!interaction.pointerInside,!interaction.expanded,dragOrigin==nil else{return}
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
        if resizeSession != nil {resizeSession=nil;rememberDetailSize()}
        interaction.dismiss();removeEventMonitors();detailPanel?.orderOut(nil)
        hovering.remove("detail");interaction.hover(!hovering.isEmpty)
        scheduleHide()
    }
    func handlePointer(_ event:NSEvent)->Bool {
        guard let handle=handlePanel else{return false}
        let point=eventScreenLocation(event) ?? handle.convertPoint(toScreen:event.locationInWindow)
        switch event.type {
        case .leftMouseDown:
            hideTimer?.invalidate();hideTimer=nil
            interaction.hover(true);positionPanels()
            pointerAnchor=point;freeDragOrigin=handle.frame.origin;freeDragging=false
            return true
        case .leftMouseDragged:
            guard let anchor=pointerAnchor,let origin=freeDragOrigin else{return false}
            guard freeDragging || hypot(point.x-anchor.x,point.y-anchor.y)>=4 else{return true}
            if !freeDragging {freeDragging=true;dismiss()}
            handle.setFrameOrigin(NSPoint(x:origin.x+point.x-anchor.x,y:origin.y+point.y-anchor.y))
            return true
        case .leftMouseUp:
            guard let anchor=pointerAnchor else{return false}
            let moved=freeDragging,click=hypot(point.x-anchor.x,point.y-anchor.y)<4
            pointerAnchor=nil;freeDragOrigin=nil;freeDragging=false
            hovering.removeAll();interaction.hover(false)
            if moved {finishDrag(at:point)} else if click {toggleDetails()} else {positionPanels();scheduleHide()}
            return true
        default:return false
        }
    }
    func finishDrag(at point:NSPoint) {
        if let target=DesktopDocking.target(at:point,displays:displays) {applyDock(target);return}
        showFloating(at:point,preset:.custom)
    }
    func place(_ preset:DesktopPositionPreset,on screenID:String,x:Double=0.5,y:Double=0.5) {
        guard let model else{return}
        if preset == .custom {model.saveDesktopSettings(["positionPreset":preset.rawValue]);return}
        guard let display=displays.first(where:{$0.id==screenID}) ?? displays.first else{return}
        if let side=preset.side {
            applyDock(DesktopDockTarget(screenID:display.id,side:side,position:preset.position),preset:preset)
            model.windows.hideSticky()
        } else {showFloating(at:DesktopPlacement.point(x:x,y:y,in:display.frame),preset:preset)}
    }
    func placeCustomSticky(on screenID:String,x:Double,y:Double) {
        guard let display=displays.first(where:{$0.id==screenID}) ?? displays.first else{return}
        showFloating(at:DesktopPlacement.point(x:x,y:y,in:display.frame),preset:.custom)
    }
    private func floatingSettings(at point:NSPoint,preset:DesktopPositionPreset)->[String:Any] {
        guard let display=displays.first(where:{$0.frame.contains(point)}) ?? displays.first else{return [:]}
        let fractions=DesktopPlacement.fractions(point,in:display.frame)
        return ["positionPreset":preset.rawValue,"placementScreenID":display.id,"stickyPositionX":Double(fractions.x),"stickyPositionY":Double(fractions.y)]
    }
    private func showFloating(at point:NSPoint,preset:DesktopPositionPreset) {
        guard let model,model.windows.hasWindow(.sticky) || model.statusBar?.openWindow != nil else {positionPanels();scheduleHide();return}
        model.windows.placeNextSticky(at:point)
        var settings=floatingSettings(at:point,preset:preset);settings["sidebarEnabled"]=false
        model.saveDesktopSettings(settings)
        if !model.windows.presentExisting(.sticky) {model.statusBar?.openWindow?("sticky")}
    }
    @discardableResult func dockSticky(_ window:NSWindow)->Bool {
        guard let model else{return false}
        guard let target=DesktopDocking.target(for:window.frame,displays:displays) else {
            model.saveDesktopSettings(floatingSettings(at:NSPoint(x:window.frame.midX,y:window.frame.midY),preset:.custom))
            return false
        }
        model.stickyExpansion?.dismiss();applyDock(target);model.windows.hideStickyForDocking(window)
        return true
    }
    private func applyDock(_ target:DesktopDockTarget,preset:DesktopPositionPreset = .custom) {
        hovering.removeAll();interaction.reset()
        model?.saveDesktopSettings(["sidebarEnabled":true,"sidebarSide":target.side.rawValue,"sidebarScreenID":target.screenID,"sidebarPosition":target.position,"placementScreenID":target.screenID,"positionPreset":preset.rawValue])
        DispatchQueue.main.async {[weak self] in
            guard let self else{return}
            self.interaction.setAutoHide(self.preferences.sidebarAutoHide)
            self.positionPanels();self.scheduleHide()
        }
    }
    func makeContextMenu()->NSMenu {
        let menu=NSMenu();menu.autoenablesItems=false
        guard let model else{return menu}
        func item(_ title:String,_ id:String,selected:Bool=false,_ action:@escaping ()->Void)->NSMenuItem {
            let result=MiniRingMenuAction.item(title,selected:selected,action:action)
            result.identifier=NSUserInterfaceItemIdentifier(id)
            return result
        }
        menu.addItem(item(interaction.expanded ? "收起详情":"展开详情","sidebar.details"){[weak self] in self?.toggleDetails()})
        menu.addItem(.separator())
        let center=NSMenuItem(title:"环内显示",action:nil,keyEquivalent:"")
        center.identifier=NSUserInterfaceItemIdentifier("sidebar.center")
        let centerMenu=NSMenu()
        for choice in RingCenterContent.allCases {
            centerMenu.addItem(item(choice.title,"sidebar.center."+choice.rawValue,selected:model.desktopPreferences.ringCenter==choice){[weak model] in
                model?.saveDesktopSettings(["ringCenter":choice.rawValue])
            })
        }
        center.submenu=centerMenu;menu.addItem(center)
        let autoHide=model.desktopPreferences.sidebarAutoHide
        menu.addItem(item("自动隐藏","sidebar.autoHide",selected:autoHide){[weak model] in model?.saveDesktopSettings(["sidebarAutoHide":!autoHide])})
        let side=NSMenuItem(title:"停靠位置",action:nil,keyEquivalent:"")
        let sideMenu=NSMenu()
        for choice in SidebarSide.allCases {
            sideMenu.addItem(item(choice.title,"sidebar.side."+choice.rawValue,selected:model.desktopPreferences.sidebarSide==choice){[weak model] in
                model?.saveDesktopSettings(["sidebarSide":choice.rawValue])
            })
        }
        side.submenu=sideMenu;menu.addItem(side)
        let displayItem=NSMenuItem(title:"显示器",action:nil,keyEquivalent:"")
        displayItem.identifier=NSUserInterfaceItemIdentifier("sidebar.displays")
        let displayMenu=NSMenu()
        for (index,display) in displays.enumerated() {
            displayMenu.addItem(item("\(index+1). \(display.name)","sidebar.display."+display.id,selected:selectedDisplayID==display.id){[weak self] in self?.selectDisplay(display.id)})
        }
        displayItem.submenu=displayMenu;menu.addItem(displayItem)
        menu.addItem(.separator())
        menu.addItem(item("自定义面板宽高…","sidebar.size"){[weak self,weak model] in
            self?.dismiss();model?.settingsCategory = .desktop;model?.statusBar?.openWindow?("settings")
        })
        menu.addItem(item("外观与侧边栏设置…","sidebar.settings"){[weak self,weak model] in
            self?.dismiss();model?.settingsCategory = .desktop;model?.statusBar?.openWindow?("settings")
        })
        menu.addItem(item("余额与重置券…","sidebar.reset"){[weak self,weak model] in
            self?.dismiss();model?.route = .quota;model?.statusBar?.openWindow?("dashboard")
        })
        menu.addItem(item("打开工作台","sidebar.workbench"){[weak self,weak model] in
            self?.dismiss();model?.statusBar?.openWindow?("dashboard")
        })
        menu.addItem(.separator())
        menu.addItem(item("关闭侧边栏","sidebar.close"){[weak model] in model?.saveDesktopSettings(["sidebarEnabled":false])})
        return menu
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
            MainActor.assumeIsolated {if self?.contextMenuTracking != true {self?.dismiss()}}
        }
        localEvents=NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown,.keyDown]){[weak self] event in
            let consumed=MainActor.assumeIsolated {
                guard let self,!self.contextMenuTracking else{return false}
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
        if let resizeObserver {NotificationCenter.default.removeObserver(resizeObserver)}
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
            .desktopAppearance(model.desktopPreferences)
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
            .desktopAppearance(model.desktopPreferences)
            .preferredColorScheme(model.appearance.preferredScheme)
            .environment(\.locale,Locale(identifier:"zh_CN"))
    }
}
