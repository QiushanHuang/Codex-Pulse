import AppKit
@main struct ApplicationLifecycleTests {
 @MainActor static func main() {
  let app=NSApplication.shared
  let delegate=PulseApplicationDelegate()
  precondition(PulseApplicationDelegate.activationPolicy(showInDock:false) == .accessory)
  precondition(PulseApplicationDelegate.activationPolicy(showInDock:true) == .regular)
  var reopened=0
  delegate.reopen={reopened += 1}
  precondition(!delegate.applicationShouldTerminateAfterLastWindowClosed(app))
  precondition(!delegate.applicationShouldHandleReopen(app,hasVisibleWindows:false))
  precondition(reopened==1,"Dock click must reopen a closed window")
  _=delegate.applicationShouldHandleReopen(app,hasVisibleWindows:true)
  precondition(reopened==2,"Dock click must restore the selected view even with settings visible")
  let menu=delegate.applicationDockMenu(app)!
  precondition(menu.items.contains{$0.action == #selector(NSApplication.hide(_:)) && $0.target === app},"Dock menu must use native application hiding")
  print("PASS: Dock reopen, native hide action and background lifetime")
 }
}
