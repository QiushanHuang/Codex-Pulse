import AppKit
import SwiftUI

@MainActor enum DesktopFixture {
    static var now:Double {Date().timeIntervalSince1970}
    static var demoUsage:AccountUsage {
        let formatter=DateFormatter();formatter.dateFormat="yyyy-MM-dd"
        return AccountUsage(days:(0..<56).map {index in
            UsageDay(date:formatter.string(from:Calendar.current.date(byAdding:.day,value:-index,to:Date())!),tokens:((index*17)%23+1)*125000)
        },lifetimeTokens:251_234_567)
    }
    static var snapshot:PulseSnapshot {
        PulseSnapshot(generatedAt:now,quotaAt:now,windows:[
            QuotaWindow(id:"short",bucket:"codex",name:"Codex",label:"5 小时",used:24,remaining:76,reset:now+8400,burnRate:6.2,hoursLeft:12.3,history:(0..<12).map{QuotaPoint(at:now-Double(11-$0)*300,remaining:88-Double($0))}),
            QuotaWindow(id:"weekly",bucket:"codex",name:"Codex",label:"每周",used:38,remaining:62,reset:now+264000,burnRate:2.1,hoursLeft:29.5,history:(0..<12).map{QuotaPoint(at:now-Double(11-$0)*300,remaining:68-Double($0)*0.55)})
        ],tasks:[
            PulseTask(id:"12345678-1234-1234-1234-123456789001",title:"完善桌面状态面板",status:"active",at:now-20,tokensUsed:1234567,inputTokens:1214567,outputTokens:20000,cachedInputTokens:1000000),
            PulseTask(id:"12345678-1234-1234-1234-123456789002",title:"检查新版本的界面与快捷操作",status:"active",at:now-60,tokensUsed:42800),
            PulseTask(id:"12345678-1234-1234-1234-123456789003",title:"整理本周工作记录",status:"completed",at:now-600,tokensUsed:9360)
        ],events:[],quotaError:nil,taskError:nil,resetCredits:2,credits:PulseCredits(balance:128.5,unlimited:false),accountKey:String(repeating:"a",count:64),resetVouchers:[ResetVoucher(id:"demo",expiresAt:now+86400*3,grantedAt:now-100)],usage:demoUsage,usageAt:now,keyboard:KeyboardState(status:"off",message:"演示数据"))
    }
    static func model()->PulseModel {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("pulse-desktop-preview-"+UUID().uuidString)
        if CommandLine.arguments.contains("--drag-repro") {
            _=try! PulseConfigurationStore(directory:directory).update {
                $0["appearance"]="dark"
                $0["windowSettings"]=["stickySize":"mini","miniDiameter":44,"stickyPinned":true]
            }
        }
        if CommandLine.arguments.contains("--startup-check") {
            _=try! PulseConfigurationStore(directory:directory).saveWindowSettings(["sidebarEnabled":true,"sidebarBadge":"remaining"])
        }
        if CommandLine.arguments.contains("--resize-repro") {
            _=try! PulseConfigurationStore(directory:directory).saveWindowSettings(["sidebarEnabled":true,"sidebarAutoHide":false,"sidebarShowTasks":false])
            FileHandle.standardError.write(Data("PREVIEW_CONFIG \(directory.path)\n".utf8))
        }
        let model=PulseModel(startMonitoring:false,configurationDirectory:directory)
        model.snapshot=snapshot;model.running=true;model.deviceInventory = .empty
        return model
    }
}

@main struct DesktopSurfaceChecks {
    @MainActor static func main() throws {
        if CommandLine.arguments.contains("--startup-check") {
            if #available(macOS 15.0,*) {SidebarStartupCheckApp.main()}
            else {throw NSError(domain:"StartupCheckRequiresMacOS15",code:1)}
            return
        }
        if CommandLine.arguments.contains("--interactive") {DesktopPreviewApp.main();return}
        _=NSApplication.shared
        let model=DesktopFixture.model()
        let sticky=NSWindow(contentRect:NSRect(x:100,y:200,width:344,height:344),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        sticky.contentView=NSHostingView(rootView:StickyDashboard(model:model))
        sticky.orderFront(nil)
        func settle(_ time:TimeInterval=0.15) {RunLoop.main.run(until:Date().addingTimeInterval(time))}
        settle()
        // An AppKit popup must respect the SwiftUI width proposal even when a
        // different display has a much longer name than the selected display.
        let selector=NSHostingView(rootView:SidebarDisplayPicker(displays:[
            DesktopDisplay(id:"short",name:"Mi Monitor (1)",frame:.zero),
            DesktopDisplay(id:"long",name:"External Ultrawide Studio Display With A Very Long Name",frame:.zero)
        ],selected:"short",select:{_ in},tracking:{_ in}).frame(width:140,height:24))
        let selectorWindow=NSWindow(contentRect:NSRect(x:100,y:100,width:140,height:24),styleMask:.borderless,backing:.buffered,defer:false)
        selectorWindow.contentView=selector;selectorWindow.orderFront(nil);settle()
        func findPopup(_ view:NSView)->NSPopUpButton? {
            if let popup=view as? NSPopUpButton {return popup}
            for child in view.subviews {if let popup=findPopup(child) {return popup}}
            return nil
        }
        guard let popup=findPopup(selector) else {preconditionFailure("missing display selector")}
        let popupRect=popup.convert(popup.bounds,to:selector)
        precondition(popupRect.minX>=(-0.5) && popupRect.maxX<=selector.bounds.maxX+0.5,"native display selector must stay inside the proposed width: \(popupRect), host \(selector.bounds)")
        selectorWindow.orderOut(nil)
        for size in [StickySize.mini,.compact,.standard,.mini] {
            model.setStickySize(size);settle()
            let actual=sticky.contentRect(forFrameRect:sticky.frame).size
            if size == .standard {
                precondition(actual.width>=320 && actual.width<=440 && actual.height>=320,"standard preserves its original flexible bounds")
            } else {
                precondition(abs(actual.width-size.contentSize.width)<1 && abs(actual.height-size.contentSize.height)<1,"new small presets must resize the real SwiftUI window: \(actual)")
            }
            if size == .mini {
                precondition(!sticky.styleMask.contains(.titled) && !sticky.isOpaque,"mini must have no title bar or opaque rectangular backing")
                precondition(sticky.frame.size == NSSize(width:96,height:96),"mini outer window must be only the ring size")
            } else {
                precondition(!sticky.styleMask.contains(.titled) && !sticky.isOpaque,"all sticky sizes must remain borderless glass cards")
                func dragHandle(in view:NSView)->NSView? {
                    if view.identifier?.rawValue=="sticky-drag-handle" {return view}
                    for child in view.subviews {if let handle=dragHandle(in:child) {return handle}}
                    return nil
                }
                guard let drag=dragHandle(in:sticky.contentView!) as? StickyDragHandle.DragView else {preconditionFailure("missing card drag surface")}
                precondition(drag.bounds.size==sticky.contentView!.bounds.size,"the whole card interior must be draggable")
                let center=NSPoint(x:drag.bounds.midX,y:drag.bounds.midY)
                precondition(drag.hitTest(drag.convert(center,to:drag.superview)) === drag,"body area must accept a drag")
                precondition(!drag.excludedRect.isEmpty,"controls must have an explicit protected area")
                let control=NSPoint(x:drag.excludedRect.midX,y:drag.excludedRect.midY)
                precondition(drag.hitTest(drag.convert(control,to:drag.superview))==nil,"buttons must receive clicks instead of starting a drag")
                precondition(sticky.styleMask.contains(.resizable)==(size == .standard),"standard resize behavior must remain available")
            }
        }
        for diameter in [40.0,57,80,160] {
            model.setMiniDiameter(diameter);settle()
            precondition(sticky.frame.size==NSSize(width:diameter,height:diameter),"custom diameter must change the whole borderless window")
        }
        model.setMiniDiameter(96);settle()
        func ringInput(in view:NSView)->MiniRingInteractionView? {
            if let input=view as? MiniRingInteractionView {return input}
            for child in view.subviews {if let input=ringInput(in:child) {return input}}
            return nil
        }
        for diameter in [40.0,64,96,160] {
            model.setMiniDiameter(diameter);settle()
            guard let input=ringInput(in:sticky.contentView!) else {preconditionFailure("missing ring input")}
            let root=sticky.contentView!
            precondition(input.bounds.size==NSSize(width:diameter,height:diameter),"the native hit surface must track custom ring sizes")
            let half=diameter/2
            for point in [NSPoint(x:half,y:2),NSPoint(x:2,y:half),NSPoint(x:diameter-2,y:half),NSPoint(x:half,y:diameter-2)] {
                precondition(root.hitTest(point) === input,"custom-size rim must remain draggable")
            }
        }
        model.setMiniDiameter(96);settle()
        for center in RingCenterContent.allCases {
            model.saveDesktopSettings(["ringCenter":center.rawValue,"outerRingColor":"#FF8822","innerRingColor":"#4488FF","glassTransparency":0.95]);settle()
            guard let input=ringInput(in:sticky.contentView!) else {preconditionFailure("missing styled native ring")}
            precondition(input.center==center && input.transparency==0.95,"appearance choices must reach the native mini ring")
            let outer=input.outerTint.usingColorSpace(.sRGB)!,inner=input.innerTint.usingColorSpace(.sRGB)!
            precondition(abs(outer.redComponent-1)<0.01 && abs(inner.blueComponent-1)<0.01,"custom colors must reach native drawing")
        }
        model.saveDesktopSettings(["ringCenter":"credit","outerRingColor":NSNull(),"innerRingColor":NSNull(),"glassTransparency":0.85]);settle()
        for action in [MiniRingClickAction.compact,.standard] {
            model.setMiniClickAction(action);model.setStickySize(.mini);settle()
            guard let input=ringInput(in:sticky.contentView!) else {preconditionFailure("the ring must expose its native input surface")}
            let root=sticky.contentView!
            precondition(input.bounds.size==root.bounds.size,"the native input surface must cover the whole ring")
            for point in [NSPoint(x:48,y:4),NSPoint(x:4,y:48),NSPoint(x:92,y:48),NSPoint(x:48,y:92)] {
                precondition(root.hitTest(point) === input,"every visible ring edge must target the native drag surface: \(point)")
            }
            let number=sticky.windowNumber
            let ringFrame=sticky.frame
            let savedPreferences=model.desktopPreferences
            let down=NSEvent.mouseEvent(with:.leftMouseDown,location:NSPoint(x:30,y:30),modifierFlags:[],timestamp:0,windowNumber:number,context:nil,eventNumber:0,clickCount:1,pressure:1)!
            let up=NSEvent.mouseEvent(with:.leftMouseUp,location:NSPoint(x:30,y:30),modifierFlags:[],timestamp:0,windowNumber:number,context:nil,eventNumber:1,clickCount:1,pressure:0)!
            input.mouseDown(with:down);input.mouseUp(with:up);settle()
            precondition(model.desktopPreferences.stickySize == .mini && sticky.frame.size==NSSize(width:96,height:96),"temporary expansion must leave the ring and saved mode unchanged")
            precondition(model.stickyExpansion?.panel?.isVisible==true && model.stickyExpansion?.mode==action.target)
            precondition(model.stickyExpansion?.panel?.frame.size==action.target?.contentSize,"the chosen style must size the separate floating panel")
            precondition(model.desktopPreferences==savedPreferences && sticky.frame==ringFrame,"opening details must not persist a mode or move the ring")
            _=input.accessibilityPerformPress();settle()
            precondition(model.stickyExpansion?.panel==nil && sticky.isVisible,"a second ring click must only dismiss details")
            _=input.accessibilityPerformPress();settle()
            input.eventScreenLocation={_ in NSPoint(x:ringFrame.minX+50,y:ringFrame.minY+40)}
            input.mouseDown(with:down)
            input.mouseDragged(with:NSEvent.mouseEvent(with:.leftMouseDragged,location:NSPoint(x:50,y:40),modifierFlags:[],timestamp:0,windowNumber:number,context:nil,eventNumber:2,clickCount:1,pressure:1)!)
            input.mouseUp(with:up);settle()
            precondition(model.stickyExpansion?.panel==nil && model.desktopPreferences.stickySize==savedPreferences.stickySize && model.desktopPreferences.miniDiameter==savedPreferences.miniDiameter && model.desktopPreferences.miniClickAction==savedPreferences.miniClickAction,"dragging must preserve saved mode/size/action while recording its new position")
            sticky.setFrame(ringFrame,display:true)
        }
        model.setMiniClickAction(.none)
        model.setStickySize(.standard);settle()
        sticky.setContentSize(NSSize(width:410,height:470));settle()
        precondition(sticky.contentRect(forFrameRect:sticky.frame).width==410 && sticky.contentRect(forFrameRect:sticky.frame).height>=320,"standard must retain its original adjustable width and content-driven height")
        let selected=model.windows.selected
        model.saveDesktopSettings(["sidebarEnabled":true,"sidebarAutoHide":false])
        settle()
        let sidebar=model.sidebar!
        precondition(sidebar.handlePanel?.isVisible==true)
        precondition(sidebar.handlePanel?.level == .floating && sidebar.handlePanel?.isOpaque==false)
        sidebar.toggleDetails();settle()
        precondition(sidebar.detailPanel?.isVisible==true && sidebar.interaction.expanded)
        precondition(model.windows.selected==selected,"sidebar must not switch dashboard/sticky mode")
        // Route real secondary mouse events at the NSPanel boundary, where
        // SwiftUI controls/material hit testing cannot swallow them.
        let handle=sidebar.handlePanel!,detail=sidebar.detailPanel!
        func mouse(_ type:NSEvent.EventType,_ panel:NSWindow,_ flags:NSEvent.ModifierFlags=[])->NSEvent {
            NSEvent.mouseEvent(with:type,location:NSPoint(x:8,y:8),modifierFlags:flags,timestamp:0,windowNumber:panel.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
        }
        var presentations=0
        for panel in [handle,detail] {
            let nativePresenter=panel.presentContextMenu
            panel.presentContextMenu={menu,_,_ in
                presentations+=1
                precondition(menu.items.contains{$0.identifier?.rawValue=="sidebar.settings"},"both panels need the same settings menu")
                NotificationCenter.default.post(name:NSWindow.didResignKeyNotification,object:detail)
                precondition(sidebar.interaction.expanded && detail.isVisible,"opening a context menu must not dismiss the details")
            }
            panel.sendEvent(mouse(.rightMouseDown,panel))
            panel.sendEvent(mouse(.leftMouseDown,panel,.control))
            precondition(panel.contextMenu(for:mouse(.leftMouseDown,panel))==nil,"ordinary click must keep its current behavior")
            panel.presentContextMenu=nativePresenter
        }
        precondition(presentations==4,"secondary clicks and Control-clicks must both reach the native presenter")
        let choices=sidebar.makeContextMenu().items.first{$0.identifier?.rawValue=="sidebar.center"}!.submenu!
        let percentage=choices.items.first{$0.identifier?.rawValue=="sidebar.center.percentage"}!
        precondition(NSApp.sendAction(percentage.action!,to:percentage.target,from:percentage))
        settle()
        precondition(model.desktopPreferences.ringCenter == .percentage,"context-menu choice must save the actual preference")
        model.saveDesktopSettings(["ringCenter":"credit","sidebarAutoHide":true]);settle()
        sidebar.dismiss();sidebar.hover(false,surface:"handle")
        let nativePresenter=handle.presentContextMenu
        handle.presentContextMenu={_,_,_ in
            settle(1.4)
            precondition(!sidebar.interaction.tucked,"auto-hide must remain suspended during menu tracking")
        }
        handle.sendEvent(mouse(.rightMouseDown,handle))
        handle.presentContextMenu=nativePresenter
        model.saveDesktopSettings(["sidebarAutoHide":false]);settle()
        sidebar.toggleDetails();settle()
        precondition(sidebar.detailPanel!.styleMask.contains(.resizable),"expanded sidebar must support native resizing")
        sidebar.detailPanel!.setContentSize(NSSize(width:520,height:460))
        NotificationCenter.default.post(name:NSWindow.didEndLiveResizeNotification,object:sidebar.detailPanel!)
        settle()
        precondition(model.desktopPreferences.sidebarDetailWidth==520 && model.desktopPreferences.sidebarDetailHeight==460,"user-resized width and height must persist")
        sidebar.dismiss();sidebar.toggleDetails();settle()
        precondition(sidebar.detailPanel!.frame.size==NSSize(width:520,height:460),"reopening must restore both dimensions")
        let resizeFrame=detail.frame
        let screenLocation=sidebar.eventScreenLocation
        // Feed window events at an inside edge; the captured screen point must
        // work even when live cursor polling is unavailable or has advanced.
        let resizeDown=NSEvent.mouseEvent(with:.leftMouseDown,location:NSPoint(x:4,y:4),modifierFlags:[],timestamp:0,windowNumber:detail.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
        precondition(sidebar.handleResizePointer(resizeDown))
        sidebar.eventScreenLocation={_ in NSPoint(x:resizeFrame.minX+54,y:resizeFrame.minY+44)}
        precondition(sidebar.handleResizePointer(mouse(.leftMouseDragged,detail)))
        sidebar.hover(false,surface:"detail")
        precondition(detail.frame.size==NSSize(width:470,height:420),"corner drag must independently resize width and height without hover repositioning")
        precondition(detail.frame.maxX==resizeFrame.maxX && detail.frame.maxY==resizeFrame.maxY,"resize must preserve the opposite corner")
        precondition(sidebar.handleResizePointer(mouse(.leftMouseUp,detail)));settle()
        sidebar.eventScreenLocation=screenLocation
        precondition(model.desktopPreferences.sidebarDetailWidth==470 && model.desktopPreferences.sidebarDetailHeight==420,"direct edge resize must persist both dimensions")
        model.saveDesktopSettings(["sidebarDetailWidth":NSNull(),"sidebarDetailHeight":NSNull()]);settle()
        precondition(sidebar.detailPanel!.frame.width==376,"adaptive sizing must be recoverable")
        let fullHeight=sidebar.detailPanel!.frame.height
        model.saveDesktopSettings(["sidebarBadge":"remaining","sidebarShowQuota":false,"sidebarTaskLimit":1]);settle()
        precondition(model.desktopPreferences.sidebarBadge == .remaining)
        precondition(sidebar.detailPanel!.frame.height<fullHeight,"one-task-only content must shrink the real panel")
        precondition(!model.desktopPreferences.sidebarContent.showsTabs,"quota tab must disappear when its content is hidden")
        model.saveDesktopSettings(["sidebarShowTasks":false]);settle()
        precondition(sidebar.detailPanel!.isVisible && sidebar.detailPanel!.frame.height>=200,"empty selection must keep a reachable settings action")
        model.saveDesktopSettings(["sidebarShowQuota":true,"sidebarShowTasks":true,"sidebarTaskLimit":3]);settle()
        sidebar.dismiss();settle()
        precondition(sidebar.detailPanel?.isVisible==false && sidebar.handlePanel?.isVisible==true)
        model.saveDesktopSettings(["sidebarAutoHide":true]);sidebar.hover(false,surface:"handle");settle(1.4)
        precondition(sidebar.interaction.tucked && sidebar.handlePanel!.frame.width==12)
        sidebar.hover(true,surface:"handle");settle()
        precondition(!sidebar.interaction.tucked && sidebar.handlePanel!.frame.width==48)
        sidebar.toggleDetails();sidebar.hover(false,surface:"handle");settle(1.4)
        precondition(sidebar.interaction.expanded && !sidebar.interaction.tucked)
        model.saveDesktopSettings(["sidebarSide":"left"]);settle()
        precondition(sidebar.handlePanel!.frame.minX < sidebar.detailPanel!.frame.minX)
        sidebar.drag(by:-100,ended:true);settle()
        precondition(model.desktopPreferences.sidebarPosition>0.5,"dragging up must persist a higher anchor")
        // Multi-display selector and native free drag must use actual screen coordinates.
        let display=sidebar.displays.last!
        sidebar.selectDisplay(display.id);settle()
        precondition(model.desktopPreferences.sidebarScreenID==display.id && display.frame.contains(sidebar.handlePanel!.frame))
        precondition(sidebar.makeContextMenu().items.first{$0.identifier?.rawValue=="sidebar.displays"}!.submenu!.items.count==sidebar.displays.count)
        model.saveDesktopSettings(["sidebarAutoHide":false]);settle()
        sidebar.dismiss();model.setStickySize(.compact);settle()
        var pointer=NSPoint.zero
        sidebar.eventScreenLocation={_ in pointer}
        func dragHandle(to destination:NSPoint) {
            let panel=sidebar.handlePanel!,frame=sidebar.handlePanel!.frame
            pointer=NSPoint(x:frame.midX,y:frame.midY)
            let start=pointer
            panel.sendEvent(mouse(.leftMouseDown,panel))
            pointer=destination
            panel.sendEvent(mouse(.leftMouseDragged,panel))
            precondition(abs(panel.frame.minX-(frame.minX+pointer.x-start.x))<1,"horizontal drag must move the native panel freely")
            panel.sendEvent(mouse(.leftMouseUp,panel));settle()
        }
        dragHandle(to:NSPoint(x:display.frame.minX+8,y:display.frame.midY))
        precondition(model.desktopPreferences.sidebarSide == .left && model.desktopPreferences.sidebarScreenID==display.id)
        let interior=NSPoint(x:display.frame.midX,y:display.frame.midY)
        dragHandle(to:interior)
        precondition(!model.desktopPreferences.sidebarEnabled && sidebar.handlePanel==nil && sticky.isVisible,"interior drop must leave only the sticky surface")
        precondition(model.desktopPreferences.stickySize == .compact && abs(sticky.frame.midX-interior.x)<2,"detach preserves chosen size and drop position")
        func findCardDrag(_ view:NSView)->StickyDragHandle.DragView? {
            if let drag=view as? StickyDragHandle.DragView {return drag}
            for child in view.subviews {if let drag=findCardDrag(child) {return drag}}
            return nil
        }
        guard let bodyDrag=findCardDrag(sticky.contentView!) else {preconditionFailure("missing native card drag surface")}
        sticky.setFrameOrigin(NSPoint(x:display.frame.maxX-sticky.frame.width-4,y:display.frame.midY));settle()
        precondition(!model.desktopPreferences.sidebarEnabled,"programmatic placement must not dock")
        sticky.setFrameOrigin(NSPoint(x:interior.x-sticky.frame.width/2,y:interior.y-sticky.frame.height/2));settle()
        bodyDrag.eventScreenLocation={_ in pointer}
        bodyDrag.mouseDown(with:mouse(.leftMouseDown,sticky))
        pointer=NSPoint(x:display.frame.maxX-sticky.frame.width+20,y:display.frame.midY)
        bodyDrag.mouseDragged(with:mouse(.leftMouseDragged,sticky))
        bodyDrag.mouseUp(with:mouse(.leftMouseUp,sticky));settle()
        precondition(model.desktopPreferences.sidebarEnabled && sidebar.handlePanel?.isVisible==true && !sticky.isVisible,"native compact drag release must convert back to sidebar")
        precondition(model.desktopPreferences.sidebarSide == .right)
        model.setStickySize(.mini);settle();sidebar.finishDrag(at:interior);settle()
        guard let ring=ringInput(in:sticky.contentView!) else {preconditionFailure("missing mini after detach")}
        ring.eventScreenLocation={_ in pointer}
        ring.mouseDown(with:mouse(.leftMouseDown,sticky))
        pointer=NSPoint(x:display.frame.minX+8,y:display.frame.midY)
        ring.mouseDragged(with:mouse(.leftMouseDragged,sticky))
        ring.mouseUp(with:mouse(.leftMouseUp,sticky));settle()
        precondition(model.desktopPreferences.sidebarEnabled && !sticky.isVisible && model.desktopPreferences.sidebarSide == .left,"mini drag release must also dock")
        sidebar.place(.leftTop,on:display.id);settle()
        precondition(model.desktopPreferences.positionPreset == .leftTop && model.desktopPreferences.sidebarSide == .left)
        sidebar.placeCustomSticky(on:display.id,x:0.4,y:0.6);settle()
        precondition(!model.desktopPreferences.sidebarEnabled && sticky.isVisible && model.desktopPreferences.positionPreset == .custom)
        precondition(abs(model.desktopPreferences.stickyPositionX-0.4)<0.001 && abs(model.desktopPreferences.stickyPositionY-0.6)<0.001)
        for preset in [GlassPreset.crystal,.soft,.contrast] {
            model.saveDesktopSettings(preset.configuration);settle()
            guard let ring=ringInput(in:sticky.contentView!) else {preconditionFailure("missing ring in preset test")}
            precondition(ring.material==model.desktopPreferences.glassMaterial && ring.transparency==model.desktopPreferences.glassTransparency,"native mini must receive both material and opacity presets")
        }
        model.saveDesktopSettings(["sidebarEnabled":false]);settle()
        precondition(sidebar.handlePanel==nil && sidebar.detailPanel==nil && !sidebar.interaction.expanded)
        sticky.orderOut(nil)
        let destination=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
        for scheme in [ColorScheme.light,.dark] {
            let name=scheme == .dark ? "dark":"light"
            try render(AccountUsageHistory(snapshot:DesktopFixture.snapshot).frame(width:680),scheme:scheme,to:destination.appendingPathComponent("daily-usage-\(name).png"))
            for center in RingCenterContent.allCases {
                try render(QuotaRing(remaining:62,stale:false,size:96,credits:PulseCredits(balance:128.5,unlimited:false),resetCredits:2).environment(\.ringCenterContent,center),scheme:scheme,to:destination.appendingPathComponent("ring-center-\(center.rawValue)-\(name).png"))
            }
            for size in StickySize.allCases {
                try render(StickyCardContent(snapshot:DesktopFixture.snapshot,size:size,controls:AnyView(HStack(spacing:7){Image(systemName:"rectangle.compress.vertical");Image(systemName:"pin.fill");Image(systemName:"arrow.up.left.and.arrow.down.right")}.font(.system(size:10)))).frame(width:size.contentSize.width,height:size.contentSize.height),scheme:scheme,to:destination.appendingPathComponent("sticky-\(size.rawValue)-\(name).png"))
            }
            let content=SidebarContent()
            try render(SidebarDetailContent(snapshot:DesktopFixture.snapshot,style:.glass,content:content).frame(width:376,height:content.preferredHeight(quotaCount:2,taskCount:3)),scheme:scheme,to:destination.appendingPathComponent("sidebar-\(name).png"))
            let taskOnly=SidebarContent(["sidebarShowQuota":false,"sidebarTaskLimit":1])
            try render(SidebarDetailContent(snapshot:DesktopFixture.snapshot,style:.solid,content:taskOnly).frame(width:376,height:taskOnly.preferredHeight(quotaCount:2,taskCount:3)),scheme:scheme,to:destination.appendingPathComponent("sidebar-task-only-\(name).png"))
            try render(SidebarHandle(snapshot:DesktopFixture.snapshot,tucked:false,expanded:false,side:.right,badge:.remaining,action:{}).frame(width:48,height:48),scheme:scheme,to:destination.appendingPathComponent("sidebar-number-\(name).png"))
            try render(StickyCardContent(snapshot:.empty,size:.mini,running:false),scheme:scheme,to:destination.appendingPathComponent("empty-mini-\(name).png"))
            for diameter in [40.0,64] {
                try render(StickyCardContent(snapshot:DesktopFixture.snapshot,size:.mini,miniDiameter:diameter),scheme:scheme,to:destination.appendingPathComponent("ring-\(Int(diameter))-\(name).png"))
            }
        }
        print("PASS: real hosted sticky resizing, independent native panels, timed auto-hide/reveal, held-open state, drag persistence, cleanup; synthetic light/dark previews rendered")
    }
    @MainActor static func render<V:View>(_ view:V,scheme:ColorScheme,to url:URL) throws {
        let hosted=NSHostingView(rootView:view.environment(\.colorScheme,scheme).environment(\.locale,Locale(identifier:"zh_CN")))
        let window=NSWindow(contentRect:NSRect(origin:.zero,size:hosted.fittingSize),styleMask:.borderless,backing:.buffered,defer:false)
        window.appearance=NSAppearance(named:scheme == .dark ? .darkAqua:.aqua)
        window.contentView=hosted;window.orderFront(nil)
        RunLoop.main.run(until:Date().addingTimeInterval(0.1))
        hosted.layoutSubtreeIfNeeded()
        guard let bitmap=hosted.bitmapImageRepForCachingDisplay(in:hosted.bounds) else {throw NSError(domain:"DesktopPreview",code:1)}
        hosted.cacheDisplay(in:hosted.bounds,to:bitmap)
        guard let data=bitmap.representation(using:.png,properties:[:]) else {throw NSError(domain:"DesktopPreview",code:2)}
        try data.write(to:url)
        window.orderOut(nil)
    }
}

@available(macOS 15.0,*) private struct SidebarStartupCheckApp:App {
    @StateObject private var model=DesktopFixture.model()
    var body:some Scene {
        startupWindow.defaultLaunchBehavior(.presented)
    }
    private var startupWindow:some Scene {
        // A distinct scene avoids restoring a hidden interactive preview window.
        Window("Sidebar Startup Check",id:"sidebar-startup-check") {
            Text("Checking saved sidebar startup").padding(24)
                .onAppear {
                    model.sidebar?.start()
                    DispatchQueue.main.async {
                        precondition(model.desktopPreferences.sidebarEnabled && model.sidebar?.handlePanel?.isVisible==true,"a saved enabled sidebar must be restored after SwiftUI initialization")
                        if let flag=CommandLine.arguments.firstIndex(of:"--startup-report"),CommandLine.arguments.indices.contains(flag+1) {
                            let data=try! JSONSerialization.data(withJSONObject:["sidebarEnabled":model.desktopPreferences.sidebarEnabled,"handleVisible":model.sidebar?.handlePanel?.isVisible==true])
                            try! data.write(to:URL(fileURLWithPath:CommandLine.arguments[flag+1]),options:.atomic)
                        }
                        print("PASS: cold SwiftUI launch with sidebar already enabled")
                        fflush(stdout)
                        NSApp.terminate(nil)
                    }
                }
        }
    }
}

private struct DesktopPreviewApp:App {
    @StateObject private var model=DesktopFixture.model()
    var body:some Scene {
        Window("Codex Pulse · Desktop Preview",id:"preview") {
            DesktopPreviewHome(model:model)
        }.defaultSize(width:680,height:720)
        Window("Codex Pulse 便签预览",id:"sticky") {
            StickyDashboard(model:model).background(PreviewFrameRecorder().allowsHitTesting(false))
        }.defaultSize(width:344,height:344).windowResizability(.contentSize)
        Window("Codex Pulse 用量预览",id:"usage-preview") {
            ScrollView {VStack(spacing:20) {QuotaResetCard(model:model);AccountUsageHistory(snapshot:DesktopFixture.snapshot)}.padding(20)}
                .preferredColorScheme(model.appearance.preferredScheme)
                .frame(minWidth:600,minHeight:700)
        }
        Window("Codex Pulse 设置预览",id:"settings") {
            PulseSettings(model:model).preferredColorScheme(model.appearance.preferredScheme)
        }.windowResizability(.contentSize)
    }
}

private struct PreviewFrameRecorder:NSViewRepresentable {
    func makeNSView(context:Context)->Recorder {Recorder()}
    func updateNSView(_ view:Recorder,context:Context) {}
    final class Recorder:NSView {
        private var observers:[NSObjectProtocol]=[]
        private var mouseMonitor:Any?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach{NotificationCenter.default.removeObserver($0)};observers=[]
            if let mouseMonitor {NSEvent.removeMonitor(mouseMonitor)};mouseMonitor=nil
            guard let window else{return}
            if CommandLine.arguments.contains("--drag-repro") {
                mouseMonitor=NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.leftMouseDragged,.leftMouseUp]){[weak window] event in
                    MainActor.assumeIsolated {
                        if let window,event.window === window {
                            let hit=window.contentView?.hitTest(event.locationInWindow)
                            let text="INPUT \(event.type.rawValue) local=\(event.locationInWindow) cg=\(String(describing:event.cgEvent?.location)) hit=\(String(describing:hit.map{type(of:$0)})) active=\(NSApp.isActive) key=\(window.canBecomeKey) ignores=\(window.ignoresMouseEvents)\n"
                            FileHandle.standardError.write(Data(text.utf8))
                        }
                    }
                    return event
                }
            }
            for event in [NSWindow.didMoveNotification,NSWindow.didResizeNotification] {
                observers.append(NotificationCenter.default.addObserver(forName:event,object:window,queue:.main){[weak self] _ in
                    MainActor.assumeIsolated {self?.record()}
                })
            }
            record()
        }
        private func record() {
            guard let window else{return}
            let frame=window.frame
            let message="PREVIEW_STICKY_FRAME \(frame.minX) \(frame.minY) \(frame.width) \(frame.height)\n"
            FileHandle.standardError.write(Data(message.utf8))
        }
        deinit {observers.forEach{NotificationCenter.default.removeObserver($0)};if let mouseMonitor {NSEvent.removeMonitor(mouseMonitor)}}
    }
}

private struct DesktopPreviewHome:View {
    @ObservedObject var model:PulseModel
    @Environment(\.openWindow) private var openWindow
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                Text("桌面模式预览").font(.title.bold())
                Text("演示数据 · 独立临时设置 · 不启动后台监控或键盘联动").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("打开真实便签窗口"){model.presentWindow("sticky",using:{openWindow(id:$0)})}
                    Button("查看每日／每周用量"){openWindow(id:"usage-preview")}
                    Button("切换深浅色"){model.setAppearance(model.appearance == .dark ? .light:.dark)}
                }
                DesktopSurfaceSettings(model:model)
            }.padding(28)
        }.preferredColorScheme(model.appearance.preferredScheme)
            .background(WindowModeRegistration(mode:.dashboard,coordinator:model.windows).allowsHitTesting(false).accessibilityHidden(true))
            .onAppear {
                model.statusBar?.openWindow={id in model.presentWindow(id,using:{openWindow(id:$0)})}
                model.sidebar?.start()
                if CommandLine.arguments.contains("--resize-repro") {
                    // Keep this isolated test panel visible while the UI driver
                    // switches focus between observations. Production still dismisses.
                    DispatchQueue.main.async {model.sidebar?.trackMenu(true);model.sidebar?.toggleDetails()}
                }
                if CommandLine.arguments.contains("--drag-repro") {
                    NSApp.setActivationPolicy(.accessory)
                    DispatchQueue.main.async {model.presentWindow("sticky",using:{openWindow(id:$0)})}
                }
            }
            .task {
                while !Task.isCancelled {
                    model.snapshot=DesktopFixture.snapshot
                    do {try await Task.sleep(for:.seconds(10))}catch{return}
                }
            }
    }
}
