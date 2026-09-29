import AppKit
import SwiftUI

// A borderless SwiftUI window does not reliably forward a drag through its
// context-menu gesture. Own both mouse gestures on a transparent native surface.
struct MiniRingInteraction:NSViewRepresentable {
    @Environment(\.ringOuterColor) private var outerColor
    @Environment(\.ringInnerColor) private var innerColor
    @Environment(\.glassTransparency) private var transparency
    @Environment(\.glassMaterial) private var material
    let summary:String
    var remaining:Double?=nil
    var credits:PulseCredits?=nil
    var fresh=true
    var center:RingCenterContent = .credit
    var resetCredits:Int?=nil
    var onClick:((NSView)->Void)?=nil
    var onDragBegin:(()->Void)?=nil
    var onDragEnd:((NSWindow)->Void)?=nil
    var clickDescription:String?=nil
    let makeMenu:()->NSMenu
    func makeNSView(context:Context)->MiniRingInteractionView {let view=MiniRingInteractionView();update(view);return view}
    func updateNSView(_ view:MiniRingInteractionView,context:Context) {update(view)}
    private func update(_ view:MiniRingInteractionView) {
        view.makeMenu=makeMenu
        view.outerTint=NSColor(outerColor);view.innerTint=NSColor(innerColor);view.transparency=transparency;view.material=material
        view.remaining=remaining
        view.center=center
        view.resetCreditText=fresh ? resetCredits.map{String($0)} ?? "—":"—"
        view.creditText=credits?.display(fresh:fresh,compact:true) ?? "—"
        view.onClick=onClick
        view.onDragBegin=onDragBegin
        view.onDragEnd=onDragEnd
        view.setAccessibilityElement(true);view.setAccessibilityRole(.button)
        view.setAccessibilityLabel("额度圆环");view.setAccessibilityValue(summary+"，Credit 余额 "+(credits?.display(fresh:fresh) ?? "未提供")+"，可用重置次数 "+view.resetCreditText+" 次")
        let clickHint=clickDescription.map{$0+"；"} ?? ""
        view.setAccessibilityHelp(clickHint+"拖动移动；右键调整圆环大小和其他设置")
        view.toolTip=summary+" · 剩余 credit "+(credits?.display(fresh:fresh) ?? "未提供")+" · 内环不表示余额百分比"+" · "+clickHint+"拖动移动，右键调整大小"
    }
}

final class MiniRingInteractionView:NSView {
    var outerTint=NSColor(pulseMint) {didSet{needsDisplay=true;ink.needsDisplay=true}}
    var innerTint=NSColor(pulseCredit) {didSet{needsDisplay=true;ink.needsDisplay=true}}
    var material:GlassMaterial = .clear {didSet{if material != oldValue {configureGlass()}}}
    var transparency=0.98 {didSet{needsDisplay=true;ink.needsDisplay=true}}
    var remaining:Double? {didSet{needsDisplay=true;ink.needsDisplay=true}}
    var center:RingCenterContent = .credit {didSet{needsDisplay=true;ink.needsDisplay=true}}
    var resetCreditText="—" {didSet{needsDisplay=true;ink.needsDisplay=true}}
    var creditText="—" {didSet{needsDisplay=true;ink.needsDisplay=true}}
    var makeMenu:()->NSMenu={NSMenu()}
    var onClick:((NSView)->Void)?
    var onDragBegin:(()->Void)?
    var onDragEnd:((NSWindow)->Void)?
    var eventScreenLocation:(NSEvent)->NSPoint?={event in
        guard let point=event.cgEvent?.location,let mainScreen=NSScreen.screens.first else{return nil}
        return NSPoint(x:point.x,y:mainScreen.frame.maxY-point.y)
    }
    private var anchor:NSPoint?
    private var origin:NSPoint?
    private var didDrag=false
    private let dragThreshold:CGFloat=3
    private var glassView:NSView?
    private let ink=RingInkView()
    private var accessibilityObserver:NSObjectProtocol?
    override init(frame:NSRect) {
        super.init(frame:frame)
        ink.owner=self
        configureGlass()
        accessibilityObserver=NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,object:nil,queue:.main) {[weak self] _ in
            MainActor.assumeIsolated {self?.configureGlass()}
        }
    }
    required init?(coder:NSCoder) {fatalError("init(coder:) has not been implemented")}
    deinit {if let accessibilityObserver {NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)}}
    private func configureGlass() {
        glassView?.removeFromSuperview();glassView=nil;ink.removeFromSuperview()
        if #available(macOS 26.0,*),!NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            let glass=NSGlassEffectView(frame:bounds)
            glass.style = material == .clear ? .clear:.regular;glass.cornerRadius=bounds.width/2
            glass.autoresizingMask=[.width,.height]
            ink.frame=bounds;ink.autoresizingMask=[.width,.height]
            glass.contentView=ink
            addSubview(glass);glassView=glass
        }
        needsDisplay=true
    }
    override func layout() {
        super.layout()
        if #available(macOS 26.0,*),let glass=glassView as? NSGlassEffectView {glass.cornerRadius=min(bounds.width,bounds.height)/2}
    }
    override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance();needsDisplay=true;ink.needsDisplay=true}
    override func draw(_ dirtyRect:NSRect) {if glassView == nil {paintRing(background:true)}}
    func paintRing(background:Bool) {
        let dark=effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
        let top=dark ? NSColor(srgbRed:46/255,green:58/255,blue:65/255,alpha:1):NSColor(srgbRed:0.95,green:0.97,blue:0.97,alpha:1)
        let bottom=dark ? NSColor(srgbRed:22/255,green:32/255,blue:37/255,alpha:1):NSColor(srgbRed:0.89,green:0.93,blue:0.94,alpha:1)
        if background {NSGradient(starting:top,ending:bottom)?.draw(in:NSBezierPath(ovalIn:bounds),angle:-90)}
        else {
            NSColor.windowBackgroundColor.withAlphaComponent(1-transparency).setFill()
            NSBezierPath(ovalIn:bounds).fill()
        }
        let diameter=min(bounds.width,bounds.height)
        let width=max(2.5,diameter/16),padding=max(2.5,diameter*5/96)
        let track=NSBezierPath(ovalIn:bounds.insetBy(dx:padding+width/2,dy:padding+width/2))
        track.lineWidth=width
        if remaining==nil {track.setLineDash([3,4],count:2,phase:0)}
        NSColor.labelColor.withAlphaComponent(0.10).setStroke();track.stroke()
        if let remaining,remaining.isFinite,remaining>0 {
            let accent=remaining<=10 ? NSColor.systemRed:outerTint
            let arc=NSBezierPath();arc.lineWidth=width;arc.lineCapStyle = .round
            arc.appendArc(withCenter:NSPoint(x:bounds.midX,y:bounds.midY),radius:diameter/2-padding-width/2,startAngle:90,endAngle:90-min(100,remaining)*3.6,clockwise:true)
            accent.setStroke();arc.stroke()
        }
        let purple=innerTint
        let inner=NSBezierPath(ovalIn:bounds.insetBy(dx:padding+width+diameter*0.075,dy:padding+width+diameter*0.075))
        inner.lineWidth=max(1.3,width*0.55);inner.setLineDash([2,3],count:2,phase:0)
        (creditText == "—" ? NSColor.secondaryLabelColor:purple).withAlphaComponent(0.55).setStroke();inner.stroke()
        let rim=NSBezierPath(ovalIn:bounds.insetBy(dx:0.7,dy:0.7));rim.lineWidth=0.8
        NSColor.white.withAlphaComponent(dark ? 0.2:0.5).setStroke();rim.stroke()
        func label(_ string:String,at y:CGFloat,size:CGFloat,color:NSColor) {
            var font=NSFont.systemFont(ofSize:size,weight:.semibold)
            var text=NSAttributedString(string:string,attributes:[.font:font,.foregroundColor:color])
            if text.size().width>diameter*0.5 {
                font=NSFont.systemFont(ofSize:size*diameter*0.5/text.size().width,weight:.semibold)
                text=NSAttributedString(string:string,attributes:[.font:font,.foregroundColor:color])
            }
            text.draw(at:NSPoint(x:bounds.midX-text.size().width/2,y:y-text.size().height/2))
        }
        let percent=remaining.map{String(format:"%.0f",$0)} ?? "—"
        let mainText=center == .credit ? creditText:center == .percentage ? percent:resetCreditText
        let mint=outerTint
        let color=center == .percentage ? mint:purple
        label(mainText,at:bounds.midY+(diameter>=60 ? diameter*0.12:0),size:diameter*(center == .credit ? 0.20:0.27),color:mainText == "—" ? .secondaryLabelColor:color)
        if diameter>=60 {label(center == .credit ? "credit":center == .percentage ? "% 剩余":"次重置",at:bounds.midY-diameter*0.04,size:max(8,diameter*0.095),color:color)}
        if diameter>=52 {label(center == .percentage ? creditText+" cr":percent+"%",at:bounds.midY-diameter*0.19,size:max(8,diameter*0.11),color:center == .credit ? mint:purple)}


    }
    override func hitTest(_ point:NSPoint)->NSView? {
        guard super.hitTest(point) != nil else{return nil}
        return containsRingPoint(convert(point,from:superview)) ? self:nil
    }
    private func containsRingPoint(_ local:NSPoint)->Bool {
        guard bounds.width>0,bounds.height>0 else{return false}
        let x=(local.x-bounds.midX)/(bounds.width/2)
        let y=(local.y-bounds.midY)/(bounds.height/2)
        return x*x+y*y<=1
    }
    override var mouseDownCanMoveWindow:Bool {false}
    override func acceptsFirstMouse(for event:NSEvent?)->Bool {true}
    override func mouseDown(with event:NSEvent) {
        if event.modifierFlags.contains(.control) {showMenu(event);return}
        guard let window else{return}
        anchor=window.convertPoint(toScreen:event.locationInWindow)
        origin=window.frame.origin
        didDrag=false
    }
    override func mouseDragged(with event:NSEvent) {
        guard let window,let anchor,let origin else{return}
        // Use the event's captured screen position: queued local coordinates can
        // belong to an earlier window frame, and the live cursor can differ for
        // remote or accessibility input.
        let point=eventScreenLocation(event) ?? window.convertPoint(toScreen:event.locationInWindow)
        guard didDrag || hypot(point.x-anchor.x,point.y-anchor.y)>=dragThreshold else{return}
        if !didDrag {onDragBegin?()}
        didDrag=true
        window.setFrameOrigin(NSPoint(x:origin.x+point.x-anchor.x,y:origin.y+point.y-anchor.y))
    }
    override func mouseUp(with event:NSEvent) {
        var shouldClick=false
        if let window,let anchor,origin != nil {
            let point=window.convertPoint(toScreen:event.locationInWindow)
            shouldClick = !didDrag && hypot(point.x-anchor.x,point.y-anchor.y)<dragThreshold && containsRingPoint(convert(event.locationInWindow,from:nil))
            if didDrag && !window.frameAutosaveName.isEmpty {window.saveFrame(usingName:window.frameAutosaveName)}
        }
        let endedDrag=didDrag,draggedWindow=window
        anchor=nil;origin=nil;didDrag=false
        if endedDrag,let draggedWindow {onDragEnd?(draggedWindow)}
        else if shouldClick {onClick?(self)}
    }
    override func rightMouseDown(with event:NSEvent) {showMenu(event)}
    override func viewDidMoveToWindow() {super.viewDidMoveToWindow();if window==nil {anchor=nil;origin=nil;didDrag=false}}
    override func accessibilityPerformPress()->Bool {if let onClick {onClick(self)} else {showAccessibleMenu()};return true}
    override func accessibilityPerformShowMenu()->Bool {showAccessibleMenu();return true}
    private func showMenu(_ event:NSEvent) {
        anchor=nil;origin=nil;didDrag=false
        presentMenu(at:convert(event.locationInWindow,from:nil))
    }
    private func showAccessibleMenu() {presentMenu(at:NSPoint(x:0,y:bounds.maxY))}
    private func presentMenu(at point:NSPoint) {
        let menu=makeMenu()
        // Return from the mouse/Accessibility action before entering menu tracking.
        DispatchQueue.main.async {[weak self] in
            guard let self,self.window != nil else{return}
            menu.popUp(positioning:nil,at:point,in:self)
        }
    }
}

private final class RingInkView:NSView {
    weak var owner:MiniRingInteractionView?
    override func draw(_ dirtyRect:NSRect) {owner?.paintRing(background:false)}
    override func hitTest(_ point:NSPoint)->NSView? {nil}
}

@MainActor final class MiniRingMenuAction:NSObject {
    private let action:()->Void
    init(_ action:@escaping ()->Void) {self.action=action}
    @objc func run(_ sender:Any?){action()}
    static func item(_ title:String,selected:Bool=false,action:@escaping ()->Void)->NSMenuItem {
        let target=MiniRingMenuAction(action)
        let item=NSMenuItem(title:title,action:#selector(run(_:)),keyEquivalent:"")
        item.target=target;item.representedObject=target;item.state=selected ? .on:.off
        return item
    }
}

final class MiniRingSizeMenuView:NSView {
    private let label=NSTextField(labelWithString:"")
    private let slider=NSSlider()
    private let change:(Double)->Void
    init(diameter:Double,change:@escaping (Double)->Void) {
        self.change=change
        super.init(frame:NSRect(x:0,y:0,width:230,height:62))
        label.frame=NSRect(x:14,y:35,width:202,height:17)
        label.font = .systemFont(ofSize:12);label.stringValue="圆环大小：\(Int(diameter)) 点"
        slider.frame=NSRect(x:14,y:9,width:202,height:22)
        slider.minValue=40;slider.maxValue=160;slider.doubleValue=diameter
        slider.isContinuous=true;slider.controlSize = .small
        slider.target=self;slider.action=#selector(resize(_:));slider.setAccessibilityLabel("圆环直径")
        addSubview(label);addSubview(slider)
    }
    required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
    @objc private func resize(_ sender:NSSlider) {
        let value=sender.doubleValue.rounded();sender.doubleValue=value
        label.stringValue="圆环大小：\(Int(value)) 点";change(value)
    }
}

// Attached only to the sticky scene. Never changes the level of NSApp.keyWindow.
struct StickyWindowAccessor:NSViewRepresentable {
    let pinned:Bool
    var contentSize:NSSize?=nil
    var resizable=false
    var circular=false
    func makeNSView(context:Context)->AccessView {
        let view=AccessView();view.pinned=pinned;view.contentSize=contentSize;view.resizable=resizable;view.circular=circular;return view
    }
    func updateNSView(_ view:AccessView,context:Context) {view.pinned=pinned;view.contentSize=contentSize;view.resizable=resizable;view.circular=circular;view.apply()}
    static func dismantleNSView(_ view:AccessView,coordinator:()) {view.restore()}
    final class AccessView:NSView {
        var pinned=false
        var contentSize:NSSize?
        var resizable=false
        var circular=false
        private var appliedCircular=false
        private var appliedChrome=false
        private var changingChrome=false
        private var originalChrome:Chrome?
        private struct Chrome {
            let style:NSWindow.StyleMask
            let opaque:Bool
            let color:NSColor
            let shadow:Bool
            let movable:Bool
            init(_ window:NSWindow) {
                style=window.styleMask;opaque=window.isOpaque;color=window.backgroundColor
                shadow=window.hasShadow;movable=window.isMovableByWindowBackground
            }
            func restore(_ window:NSWindow) {
                window.styleMask=style;window.isOpaque=opaque;window.backgroundColor=color
                window.hasShadow=shadow;window.isMovableByWindowBackground=movable
            }
        }
        private var appliedSize:NSSize?
        private var appliedResizable=false
        private var originalMinimum=NSSize.zero
        private var originalMaximum=NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        private weak var controlled:NSWindow?
        private var originalLevel:NSWindow.Level = .normal
        private var originalHides=false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Changing a titled window to borderless temporarily reparents its
            // content view. Keep the original chrome through that native cycle.
            guard !changingChrome else{return}
            if controlled !== window {
                restore()
                controlled=window
                originalLevel=window?.level ?? .normal
                originalHides=window?.hidesOnDeactivate ?? false
                originalMinimum=window?.contentMinSize ?? .zero
                originalMaximum=window?.contentMaxSize ?? originalMaximum
                originalChrome=window.map{Chrome($0)}
            }
            // Finish AppKit's attachment transaction before replacing its frame
            // view; changing style synchronously can detach the incoming content.
            DispatchQueue.main.async {[weak self] in self?.apply()}
        }
        func apply() {
            guard !changingChrome,let window else{return}
            if controlled == nil {
                controlled=window;originalLevel=window.level;originalHides=window.hidesOnDeactivate
                originalMinimum=window.contentMinSize;originalMaximum=window.contentMaxSize
                originalChrome=Chrome(window)
            }
            let top=window.frame.maxY
            let desiredStyle:NSWindow.StyleMask=resizable ? [.borderless,.resizable]:.borderless
            if !appliedChrome || circular != appliedCircular || window.styleMask != desiredStyle {
                changingChrome=true
                window.styleMask=desiredStyle
                window.isOpaque=false;window.backgroundColor = .clear
                window.hasShadow = !circular;window.isMovableByWindowBackground=true
                appliedCircular=circular;appliedChrome=true;appliedSize=nil
                changingChrome=false
            }
            let level:NSWindow.Level=pinned ? .floating:.normal
            if window.level != level {window.level=level}
            if window.hidesOnDeactivate {window.hidesOnDeactivate=false}
            if let contentSize,contentSize != appliedSize || resizable != appliedResizable {
                appliedSize=contentSize;appliedResizable=resizable
                // SwiftUI's previous content constraints can otherwise block shrinking.
                window.contentMinSize=resizable ? NSSize(width:320,height:320):contentSize
                window.contentMaxSize=resizable ? NSSize(width:440,height:CGFloat.greatestFiniteMagnitude):contentSize
                var frame=window.frameRect(forContentRect:NSRect(origin:.zero,size:contentSize))
                frame.origin=NSPoint(x:window.frame.minX,y:top-frame.height)
                if let screen=window.screen?.visibleFrame {
                    frame.origin.x=max(screen.minX,min(frame.minX,screen.maxX-frame.width))
                    frame.origin.y=max(screen.minY,min(frame.minY,screen.maxY-frame.height))
                }
                window.setFrame(frame,display:true)
            }
        }
        func restore(){
            guard !changingChrome else{return}
            changingChrome=true
            defer {changingChrome=false}
            if appliedChrome,let controlled {originalChrome?.restore(controlled)}
            controlled?.level=originalLevel;controlled?.hidesOnDeactivate=originalHides
            if appliedSize != nil {controlled?.contentMinSize=originalMinimum;controlled?.contentMaxSize=originalMaximum}
            controlled=nil;appliedSize=nil;appliedCircular=false;appliedChrome=false;originalChrome=nil
        }
    }
}

// Explicit native dragging inside the card keeps borderless cards
// movable even when SwiftUI's context-menu gesture owns the surrounding content.
struct StickyDragHandle:NSViewRepresentable {
    var excludedRect:CGRect = .zero
    var onDragEnd:((NSWindow)->Void)?=nil
    func makeNSView(context:Context)->DragView {
        let view=DragView();view.identifier=NSUserInterfaceItemIdentifier("sticky-drag-handle")
        view.setAccessibilityElement(true);view.setAccessibilityRole(.group)
        view.setAccessibilityLabel("拖动便签");view.toolTip="在框内按住拖动；右键打开菜单"
        view.excludedRect=excludedRect;view.onDragEnd=onDragEnd
        return view
    }
    func updateNSView(_ view:DragView,context:Context) {view.excludedRect=excludedRect;view.onDragEnd=onDragEnd}
    final class DragView:NSView {
        var excludedRect:CGRect = .zero
        var onDragEnd:((NSWindow)->Void)?
        var eventScreenLocation:(NSEvent)->NSPoint?={event in
            guard let point=event.cgEvent?.location,let main=NSScreen.screens.first else{return nil}
            return NSPoint(x:point.x,y:main.frame.maxY-point.y)
        }
        private var anchor:NSPoint?
        private var origin:NSPoint?
        private var dragging=false
        override var isFlipped:Bool {true}
        override var mouseDownCanMoveWindow:Bool {false}
        override func acceptsFirstMouse(for event:NSEvent?)->Bool {true}
        override func mouseDown(with event:NSEvent) {
            guard let window else{return}
            anchor=window.convertPoint(toScreen:event.locationInWindow);origin=window.frame.origin;dragging=false
        }
        override func mouseDragged(with event:NSEvent) {
            guard let window,let anchor,let origin else{return}
            let point=eventScreenLocation(event) ?? window.convertPoint(toScreen:event.locationInWindow)
            guard dragging || hypot(point.x-anchor.x,point.y-anchor.y)>=3 else{return}
            dragging=true
            window.setFrameOrigin(NSPoint(x:origin.x+point.x-anchor.x,y:origin.y+point.y-anchor.y))
        }
        override func mouseUp(with event:NSEvent) {
            let moved=dragging,draggedWindow=window
            anchor=nil;origin=nil;dragging=false
            if moved,let draggedWindow {
                if !draggedWindow.frameAutosaveName.isEmpty {draggedWindow.saveFrame(usingName:draggedWindow.frameAutosaveName)}
                onDragEnd?(draggedWindow)
            }
        }
        override func viewDidMoveToWindow() {super.viewDidMoveToWindow();if window==nil {anchor=nil;origin=nil;dragging=false}}
        override func hitTest(_ point:NSPoint)->NSView? {
            if let event=NSApp.currentEvent,event.type == .rightMouseDown || event.modifierFlags.contains(.control) {return nil}
            let local=convert(point,from:superview)
            guard NSBezierPath(roundedRect:bounds,xRadius:20,yRadius:20).contains(local),
                  !excludedRect.insetBy(dx:-5,dy:-5).contains(local) else {return nil}
            return super.hitTest(point)
        }
    }
}
