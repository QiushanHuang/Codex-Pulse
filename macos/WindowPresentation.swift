import AppKit
import SwiftUI

enum PulseWindowMode:String {case dashboard,sticky}

@MainActor final class PulseWindowCoordinator {
    private weak var dashboard:NSWindow?
    private weak var sticky:NSWindow?
    private(set) var selected:PulseWindowMode?
    private var presenting=false
    private var waitingForWindow=false
    private var pendingCreations:Set<PulseWindowMode>=[]
    private var cancelledCreations:[PulseWindowMode:Bool]=[:]
    private var initialFocus:Set<PulseWindowMode>=[.dashboard,.sticky]
    private let show:@MainActor (NSWindow)->Void
    private let hide:@MainActor (NSWindow)->Void
    init(show:@escaping @MainActor (NSWindow)->Void = {$0.deminiaturize(nil);$0.makeKeyAndOrderFront(nil)},hide:@escaping @MainActor (NSWindow)->Void = {$0.orderOut(nil)}) {
        self.show=show;self.hide=hide
    }
    private func window(_ mode:PulseWindowMode)->NSWindow? {mode == .dashboard ? dashboard:sticky}
    private func opposite(_ mode:PulseWindowMode)->NSWindow? {mode == .dashboard ? sticky:dashboard}
    func register(_ mode:PulseWindowMode,window:NSWindow) {
        guard self.window(mode) !== window else{return}
        if mode == .dashboard {dashboard=window} else {sticky=window}
        initialFocus.insert(mode)
        if pendingCreations.contains(mode),let selected,selected != mode {
            cancelledCreations[mode]=window.isExcludedFromWindowsMenu
            window.isExcludedFromWindowsMenu=true
            hide(window)
        } else if window.isKeyWindow {becameKey(mode,window:window)}
        DispatchQueue.main.async {[weak self,weak window] in
            guard let self,let window,self.window(mode) === window else{return}
            if self.cancelledCreations[mode] != nil {self.hide(window)}
            else if self.selected == mode && self.waitingForWindow {self.finish(mode,window:window)}
            else if let selected=self.selected,selected != mode,!window.isKeyWindow {self.hide(window)}
        }
    }
    func unregister(_ mode:PulseWindowMode,window:NSWindow) {
        guard self.window(mode) === window else{return}
        pendingCreations.remove(mode)
        if let original=cancelledCreations.removeValue(forKey:mode){window.isExcludedFromWindowsMenu=original}
        if mode == .dashboard {dashboard=nil} else {sticky=nil}
    }
    func present(_ mode:PulseWindowMode,open:(String)->Void) {
        selected=mode
        let otherMode:PulseWindowMode = mode == .sticky ? .dashboard:.sticky
        if pendingCreations.contains(otherMode),let other=window(otherMode),cancelledCreations[otherMode] == nil {
            cancelledCreations[otherMode]=other.isExcludedFromWindowsMenu
            other.isExcludedFromWindowsMenu=true
        }
        if let other=opposite(mode){hide(other)}
        if let target=window(mode){finish(mode,window:target)}
        else {waitingForWindow=true;if pendingCreations.insert(mode).inserted {open(mode.rawValue)}}
    }
    private func finish(_ mode:PulseWindowMode,window:NSWindow) {
        if let original=cancelledCreations.removeValue(forKey:mode){window.isExcludedFromWindowsMenu=original}
        pendingCreations.remove(mode)
        waitingForWindow=false;presenting=true
        if let other=opposite(mode){hide(other)}
        show(window);presenting=false
        initialFocus.remove(mode);clearInitialFocus(mode,window:window)
    }
    func becameKey(_ mode:PulseWindowMode,window:NSWindow) {
        guard !presenting,self.window(mode) === window else{return}
        guard cancelledCreations[mode] == nil else {hide(window);return}
        pendingCreations.remove(mode)
        let changing=selected != mode
        selected=mode;waitingForWindow=false
        if let other=opposite(mode){hide(other)}
        if changing || initialFocus.contains(mode) {initialFocus.remove(mode);clearInitialFocus(mode,window:window)}
    }
    private func clearInitialFocus(_ mode:PulseWindowMode,window:NSWindow) {
        // Opening either view should not auto-focus its first button.
        // Subsequent Tab navigation keeps the native visible focus indication.
        window.makeFirstResponder(nil)
        DispatchQueue.main.async {[weak self,weak window] in
            guard let self,let window,self.selected == mode,self.window(mode) === window else{return}
            window.makeFirstResponder(nil)
        }
    }
}

struct WindowModeRegistration:NSViewRepresentable {
    let mode:PulseWindowMode
    let coordinator:PulseWindowCoordinator
    func makeNSView(context:Context)->RegistrationView {let view=RegistrationView();view.mode=mode;view.coordinator=coordinator;return view}
    func updateNSView(_ view:RegistrationView,context:Context){view.mode=mode;view.coordinator=coordinator;view.attach()}
    static func dismantleNSView(_ view:RegistrationView,coordinator:()){view.detach()}
    final class RegistrationView:NSView {
        var mode:PulseWindowMode = .dashboard
        weak var coordinator:PulseWindowCoordinator?
        private weak var observed:NSWindow?
        private var token:NSObjectProtocol?
        override func viewDidMoveToWindow(){super.viewDidMoveToWindow();attach()}
        func attach(){
            guard observed !== window else{return}
            detach();guard let window else{return};observed=window
            coordinator?.register(mode,window:window)
            token=NotificationCenter.default.addObserver(forName:NSWindow.didBecomeKeyNotification,object:window,queue:.main){[weak self,weak window] _ in
                MainActor.assumeIsolated {guard let self,let window else{return};self.coordinator?.becameKey(self.mode,window:window)}
            }
        }
        func detach(){if let token{NotificationCenter.default.removeObserver(token)};token=nil;if let observed{coordinator?.unregister(mode,window:observed)};observed=nil}
        deinit{if let token{NotificationCenter.default.removeObserver(token)}}
    }
}
