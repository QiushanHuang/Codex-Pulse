import AppKit
import SwiftUI

@MainActor enum DesktopFixture {
    static var now:Double {Date().timeIntervalSince1970}
    static var snapshot:PulseSnapshot {
        PulseSnapshot(generatedAt:now,quotaAt:now,windows:[
            QuotaWindow(id:"short",bucket:"codex",name:"Codex",label:"5 小时",used:24,remaining:76,reset:now+8400,burnRate:6.2,hoursLeft:12.3,history:(0..<12).map{QuotaPoint(at:now-Double(11-$0)*300,remaining:88-Double($0))}),
            QuotaWindow(id:"weekly",bucket:"codex",name:"Codex",label:"每周",used:38,remaining:62,reset:now+264000,burnRate:2.1,hoursLeft:29.5,history:(0..<12).map{QuotaPoint(at:now-Double(11-$0)*300,remaining:68-Double($0)*0.55)})
        ],tasks:[
            PulseTask(id:"12345678-1234-1234-1234-123456789001",title:"完善桌面状态面板",status:"active",at:now-20),
            PulseTask(id:"12345678-1234-1234-1234-123456789002",title:"检查新版本的界面与快捷操作",status:"active",at:now-60),
            PulseTask(id:"12345678-1234-1234-1234-123456789003",title:"整理本周工作记录",status:"completed",at:now-600)
        ],events:[],quotaError:nil,taskError:nil,resetCredits:nil,keyboard:KeyboardState(status:"off",message:"演示数据"))
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
            } else {precondition(sticky.styleMask.contains(.titled),"normal window chrome must return for other modes")}
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
            precondition(model.stickyExpansion?.panel==nil && model.desktopPreferences==savedPreferences,"dragging must dismiss the temporary panel without altering the saved mode")
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
        model.saveDesktopSettings(["sidebarEnabled":false]);settle()
        precondition(sidebar.handlePanel==nil && sidebar.detailPanel==nil && !sidebar.interaction.expanded)
        sticky.orderOut(nil)
        let destination=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
        for scheme in [ColorScheme.light,.dark] {
            let name=scheme == .dark ? "dark":"light"
            for size in StickySize.allCases {
                try render(StickyCardContent(snapshot:DesktopFixture.snapshot,size:size,controls:AnyView(HStack(spacing:7){Image(systemName:"rectangle.compress.vertical");Image(systemName:"pin.fill");Image(systemName:"arrow.up.left.and.arrow.down.right")}.font(.system(size:10)))).frame(width:size.contentSize.width,height:size.contentSize.height),scheme:scheme,to:destination.appendingPathComponent("sticky-\(size.rawValue)-\(name).png"))
            }
            let content=SidebarContent()
            try render(SidebarDetailContent(snapshot:DesktopFixture.snapshot,style:.solid,content:content).frame(width:376,height:content.preferredHeight(quotaCount:2,taskCount:3)),scheme:scheme,to:destination.appendingPathComponent("sidebar-\(name).png"))
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
                    Button("切换深浅色"){model.setAppearance(model.appearance == .dark ? .light:.dark)}
                }
                DesktopSurfaceSettings(model:model)
            }.padding(28)
        }.preferredColorScheme(model.appearance.preferredScheme)
            .background(WindowModeRegistration(mode:.dashboard,coordinator:model.windows).allowsHitTesting(false).accessibilityHidden(true))
            .onAppear {
                model.statusBar?.openWindow={id in model.presentWindow(id,using:{openWindow(id:$0)})}
                model.sidebar?.start()
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
