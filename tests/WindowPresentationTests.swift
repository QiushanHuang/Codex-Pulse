import AppKit
import SwiftUI
@main struct WindowPresentationTests {
 @MainActor static func main() {
  _=NSApplication.shared
  let main=NSWindow(),sticky=NSWindow(),settings=NSWindow()
  var shown:[NSWindow]=[],hidden:[NSWindow]=[],opened:[String]=[]
  let coordinator=PulseWindowCoordinator(show:{shown.append($0)},hide:{hidden.append($0)})
  coordinator.register(.dashboard,window:main)
  coordinator.present(.sticky){opened.append($0)}
  precondition(opened==["sticky"] && hidden.last === main)
  coordinator.register(.sticky,window:sticky)
  RunLoop.main.run(until:Date().addingTimeInterval(0.02))
  precondition(shown.last === sticky && coordinator.selected == .sticky)
  coordinator.present(.dashboard){opened.append($0)}
  precondition(hidden.last === sticky && shown.last === main)
  coordinator.present(.sticky){opened.append($0)}
  coordinator.present(.sticky){opened.append($0)}
  precondition(opened==["sticky"],"reuse known windows")
  precondition(!hidden.contains{$0 === settings},"settings is outside the mode pair")
  let focus=FocusView();sticky.contentView=focus;sticky.makeFirstResponder(focus)
  precondition(sticky.firstResponder === focus)
  coordinator.present(.sticky){_ in}
  RunLoop.main.run(until:Date().addingTimeInterval(0.02))
  precondition(sticky.firstResponder !== focus,"opening clears toolbar autofocus")
  sticky.makeFirstResponder(focus)
  coordinator.becameKey(.sticky,window:sticky)
  precondition(sticky.firstResponder === focus,"normal focus return preserves keyboard focus")
  coordinator.becameKey(.dashboard,window:main)
  precondition(hidden.last === sticky && coordinator.selected == .dashboard)
  let mainFocus=FocusView();main.contentView=mainFocus;main.makeFirstResponder(mainFocus)
  coordinator.present(.dashboard){_ in}
  RunLoop.main.run(until:Date().addingTimeInterval(0.02))
  precondition(main.firstResponder !== mainFocus,"dashboard opening clears automatic button focus")
  main.makeFirstResponder(mainFocus)
  coordinator.becameKey(.dashboard,window:main)
  precondition(main.firstResponder === mainFocus,"dashboard focus return preserves deliberate keyboard focus")
  let lateMain=NSWindow(),lateSticky=KeyWindow()
  var lateHidden:[NSWindow]=[]
  let delayed=PulseWindowCoordinator(show:{_ in},hide:{lateHidden.append($0)})
  delayed.register(.dashboard,window:lateMain)
  delayed.present(.sticky){_ in}
  delayed.present(.dashboard){_ in}
  delayed.register(.sticky,window:lateSticky)
  delayed.becameKey(.sticky,window:lateSticky)
  precondition(delayed.selected == .dashboard,"late creation must not reverse newer request")
  precondition(lateHidden.last === lateSticky)
  delayed.present(.sticky){_ in}
  precondition(delayed.selected == .sticky && !lateSticky.isExcludedFromWindowsMenu)
  delayed.becameKey(.dashboard,window:lateMain)
  delayed.becameKey(.sticky,window:lateSticky)
  precondition(delayed.selected == .sticky,"native activation works after explicit reopening")
  let registeredMain=NSWindow(),registeredSticky=NSWindow()
  let registered=PulseWindowCoordinator(show:{_ in},hide:{_ in})
  registered.register(.dashboard,window:registeredMain)
  registered.present(.sticky){_ in}
  registered.register(.sticky,window:registeredSticky)
  registered.present(.dashboard){_ in}
  registered.becameKey(.sticky,window:registeredSticky)
  precondition(registered.selected == .dashboard,"late key event after registration must not reverse selection")
  registered.unregister(.sticky,window:registeredSticky)
  var reopened=false
  registered.present(.sticky){_ in reopened=true}
  precondition(reopened,"detached pending window can be reopened")
  print("PASS: exclusive mode switch, target creation/reuse, settings isolation, initial focus clearing and later keyboard focus")
 }
 final class KeyWindow:NSWindow {override var isKeyWindow:Bool {true}}
 final class FocusView:NSView {override var acceptsFirstResponder:Bool {true}}
}
