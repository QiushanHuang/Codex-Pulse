import AppKit
import SwiftUI

// A borderless SwiftUI window does not reliably forward a drag through its
// context-menu gesture. Own both mouse gestures on a transparent native surface.
struct MiniRingInteraction:NSViewRepresentable {
    let summary:String
    var remaining:Double?=nil
    var onClick:((NSView)->Void)?=nil
    var onDragBegin:(()->Void)?=nil
    var clickDescription:String?=nil
    let makeMenu:()->NSMenu
    func makeNSView(context:Context)->MiniRingInteractionView {let view=MiniRingInteractionView();update(view);return view}
    func updateNSView(_ view:MiniRingInteractionView,context:Context) {update(view)}
    private func update(_ view:MiniRingInteractionView) {
        view.makeMenu=makeMenu
        view.remaining=remaining
        view.onClick=onClick
        view.onDragBegin=onDragBegin
        view.setAccessibilityElement(true);view.setAccessibilityRole(.button)
        view.setAccessibilityLabel("额度圆环");view.setAccessibilityValue(summary)
        let clickHint=clickDescription.map{$0+"；"} ?? ""
        view.setAccessibilityHelp(clickHint+"拖动移动；右键调整圆环大小和其他设置")
        view.toolTip=summary+" · "+clickHint+"拖动移动，右键调整大小"
    }
}

final class MiniRingInteractionView:NSView {
    var remaining:Double? {didSet{needsDisplay=true}}
    var makeMenu:()->NSMenu={NSMenu()}
    var onClick:((NSView)->Void)?
    var onDragBegin:(()->Void)?
    var eventScreenLocation:(NSEvent)->NSPoint?={event in
        guard let point=event.cgEvent?.location,let mainScreen=NSScreen.screens.first else{return nil}
        return NSPoint(x:point.x,y:mainScreen.frame.maxY-point.y)
    }
    private var anchor:NSPoint?
    private var origin:NSPoint?
    private var didDrag=false
    private let dragThreshold:CGFloat=3
    override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance();needsDisplay=true}
    override func draw(_ dirtyRect:NSRect) {
        let dark=effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
        let top=dark ? NSColor(srgbRed:46/255,green:58/255,blue:65/255,alpha:1):NSColor(srgbRed:0.95,green:0.97,blue:0.97,alpha:1)
        let bottom=dark ? NSColor(srgbRed:22/255,green:32/255,blue:37/255,alpha:1):NSColor(srgbRed:0.89,green:0.93,blue:0.94,alpha:1)
        NSGradient(starting:top,ending:bottom)?.draw(in:NSBezierPath(ovalIn:bounds),angle:-90)
        let diameter=min(bounds.width,bounds.height)
        let width=max(2.5,diameter/16),padding=max(2.5,diameter*5/96)
        let track=NSBezierPath(ovalIn:bounds.insetBy(dx:padding+width/2,dy:padding+width/2))
        track.lineWidth=width
        if remaining==nil {track.setLineDash([3,4],count:2,phase:0)}
        NSColor.labelColor.withAlphaComponent(0.10).setStroke();track.stroke()
        if let remaining,remaining.isFinite,remaining>0 {
            let accent=remaining<=10 ? NSColor.systemRed:(dark ? NSColor(srgbRed:0.31,green:0.94,blue:0.73,alpha:1):NSColor(srgbRed:0.015,green:0.43,blue:0.32,alpha:1))
            let arc=NSBezierPath();arc.lineWidth=width;arc.lineCapStyle = .round
            arc.appendArc(withCenter:NSPoint(x:bounds.midX,y:bounds.midY),radius:diameter/2-padding-width/2,startAngle:90,endAngle:90-min(100,remaining)*3.6,clockwise:true)
            accent.setStroke();arc.stroke()
        }
        let font=NSFont.systemFont(ofSize:diameter/3,weight:.semibold)
        let rounded=font.fontDescriptor.withDesign(.rounded).flatMap{NSFont(descriptor:$0,size:diameter/3)} ?? font
        let text=NSAttributedString(string:remaining.map{String(format:"%.0f",$0)} ?? "—",attributes:[.font:rounded,.foregroundColor:remaining==nil ? NSColor.secondaryLabelColor:NSColor.labelColor])
        let size=text.size()
        text.draw(at:NSPoint(x:bounds.midX-size.width/2,y:bounds.midY-size.height/2))
    }
    override func hitTest(_ point:NSPoint)->NSView? {
        guard let hit=super.hitTest(point) else{return nil}
        return containsRingPoint(convert(point,from:superview)) ? hit:nil
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
        anchor=nil;origin=nil;didDrag=false
        if shouldClick {onClick?(self)}
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
            apply()
        }
        func apply() {
            guard !changingChrome,let window else{return}
            if controlled == nil {
                controlled=window;originalLevel=window.level;originalHides=window.hidesOnDeactivate
                originalMinimum=window.contentMinSize;originalMaximum=window.contentMaxSize
                originalChrome=Chrome(window)
            }
            let top=window.frame.maxY
            if circular != appliedCircular {
                changingChrome=true
                if circular {
                    window.styleMask = .borderless;window.isOpaque=false;window.backgroundColor = .clear
                    window.hasShadow=false;window.isMovableByWindowBackground=true
                } else {originalChrome?.restore(window)}
                appliedCircular=circular;appliedSize=nil
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
            if appliedCircular,let controlled {originalChrome?.restore(controlled)}
            controlled?.level=originalLevel;controlled?.hidesOnDeactivate=originalHides
            if appliedSize != nil {controlled?.contentMinSize=originalMinimum;controlled?.contentMaxSize=originalMaximum}
            controlled=nil;appliedSize=nil;appliedCircular=false;originalChrome=nil
        }
    }
}
