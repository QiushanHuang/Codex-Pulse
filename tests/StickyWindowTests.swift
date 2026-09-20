import AppKit
import SwiftUI

@main struct StickyWindowTests {
 @MainActor static func main() throws {
  _=NSApplication.shared
  let sticky=NSWindow(contentRect:NSRect(x:0,y:0,width:360,height:560),styleMask:[.titled,.closable],backing:.buffered,defer:false)
  let dashboard=NSWindow(contentRect:NSRect(x:0,y:0,width:1024,height:700),styleMask:.titled,backing:.buffered,defer:false)
  let access=StickyWindowAccessor.AccessView()
  access.pinned=true;sticky.contentView=access
  precondition(sticky.level == .floating,"pin must change the actual sticky window level")
  precondition(dashboard.level == .normal,"other windows must remain normal")
  access.pinned=false;access.apply()
  precondition(sticky.level == .normal,"unpin restores normal level")
  access.pinned=true;access.apply();access.restore()
  precondition(sticky.level == .normal,"detaching the bridge must restore its original level")
  let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
  defer {try? FileManager.default.removeItem(at:folder)}
  let store=PulseConfigurationStore(directory:folder)
  _=try store.migrate(legacySignature:nil)
  _=try store.update{$0["lighting"]=true;$0["windowSettings"]=["otherPreference":"keep"]}
  _=try store.saveStickyPinned(true)
  let saved=try store.read()
  precondition((saved["windowSettings"] as? [String:Any])?["stickyPinned"] as? Bool == true)
  precondition((saved["windowSettings"] as? [String:Any])?["otherPreference"] as? String == "keep")
  precondition(saved["lighting"] as? Bool == true)
  _=try store.saveStickyPinned(false)
  let reopened=try PulseConfigurationStore(directory:folder).read()
  precondition((reopened["windowSettings"] as? [String:Any])?["stickyPinned"] as? Bool == false)
  let malformed=Data(#"{"schemaVersion":2,"windowSettings":"damaged"}"#.utf8)
  try malformed.write(to:store.file)
  var rejected=false
  do {_=try store.saveStickyPinned(true)}catch{rejected=true}
  precondition(rejected,"malformed window preferences must not be overwritten")
  let retained=try Data(contentsOf:store.file);precondition(retained==malformed)
  print("PASS: real window pin/unpin, window isolation, bridge cleanup, pin persistence and unrelated settings")
 }
}
