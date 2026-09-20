import AppKit
import SwiftUI

// Attached only to the sticky scene. Never changes the level of NSApp.keyWindow.
struct StickyWindowAccessor:NSViewRepresentable {
    let pinned:Bool
    func makeNSView(context:Context)->AccessView {
        let view=AccessView();view.pinned=pinned;return view
    }
    func updateNSView(_ view:AccessView,context:Context) {view.pinned=pinned;view.apply()}
    static func dismantleNSView(_ view:AccessView,coordinator:()) {view.restore()}
    final class AccessView:NSView {
        var pinned=false
        private weak var controlled:NSWindow?
        private var originalLevel:NSWindow.Level = .normal
        private var originalHides=false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if controlled !== window {
                restore()
                controlled=window
                originalLevel=window?.level ?? .normal
                originalHides=window?.hidesOnDeactivate ?? false
            }
            apply()
        }
        func apply() {
            guard let window else{return}
            if controlled == nil {
                controlled=window;originalLevel=window.level;originalHides=window.hidesOnDeactivate
            }
            let level:NSWindow.Level=pinned ? .floating:.normal
            if window.level != level {window.level=level}
            if window.hidesOnDeactivate {window.hidesOnDeactivate=false}
        }
        func restore(){controlled?.level=originalLevel;controlled?.hidesOnDeactivate=originalHides;controlled=nil}
    }
}
