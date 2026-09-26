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
  let top=sticky.frame.maxY
  access.circular=true;access.contentSize=NSSize(width:96,height:96);access.apply()
  precondition(sticky.contentRect(forFrameRect:sticky.frame).size == NSSize(width:96,height:96),"mini preset must resize the actual window")
  precondition(!sticky.styleMask.contains(.titled) && !sticky.isOpaque && sticky.isMovableByWindowBackground)
  precondition(abs(sticky.frame.maxY-top)<1,"preset changes should keep the top edge anchored")
  access.circular=false;access.contentSize=NSSize(width:344,height:344);access.apply()
  precondition(sticky.styleMask.contains(.titled),"switching modes must restore original chrome")
  precondition(sticky.contentRect(forFrameRect:sticky.frame).width==344,"standard size can be restored")
  access.pinned=false;access.apply()
  precondition(sticky.level == .normal,"unpin restores normal level")
  access.pinned=true;access.apply();access.restore()
  precondition(sticky.level == .normal,"detaching the bridge must restore its original level")
  let dragWindow=NSWindow(contentRect:NSRect(x:300,y:300,width:96,height:96),styleMask:.borderless,backing:.buffered,defer:false)
  let surface=MiniRingInteractionView();dragWindow.contentView=surface
  // Real window-server hit routing needs painted content on the input surface,
  // rather than a transparent native overlay over a non-interactive SwiftUI ring.
  surface.remaining=62
  let pixels=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:96,pixelsHigh:96,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:pixels)
  NSGraphicsContext.current!.cgContext.clear(surface.bounds)
  surface.draw(surface.bounds)
  NSGraphicsContext.restoreGraphicsState()
  precondition(pixels.colorAt(x:48,y:48)!.alphaComponent>0.9,"the interactive native surface must paint the visible ring")
  precondition(pixels.colorAt(x:1,y:1)!.alphaComponent<0.1,"corners outside the ring must remain transparent")
  var pointer=NSPoint.zero;surface.eventScreenLocation={_ in pointer}
  for point in [NSPoint(x:48,y:2),NSPoint(x:2,y:48),NSPoint(x:94,y:48),NSPoint(x:48,y:94)] {
   precondition(surface.hitTest(point) === surface,"the whole visible ring, including its rim, must be interactive")
  }
  precondition(surface.hitTest(NSPoint(x:2,y:2))==nil,"transparent corners outside the circle must not capture clicks")
  var clicks=0;surface.onClick={_ in clicks+=1}
  func event(_ type:NSEvent.EventType,_ x:CGFloat,_ y:CGFloat)->NSEvent {
   NSEvent.mouseEvent(with:type,location:NSPoint(x:x,y:y),modifierFlags:[],timestamp:0,windowNumber:dragWindow.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
  }
  let origin=dragWindow.frame.origin
  precondition(surface.acceptsFirstMouse(for:nil),"a floating inactive ring must accept the first drag")
  surface.mouseDown(with:event(.leftMouseDown,40,40))
  pointer=NSPoint(x:origin.x+100,y:origin.y+70)
  surface.mouseDragged(with:event(.leftMouseDragged,100,70))
  precondition(dragWindow.frame.origin==NSPoint(x:origin.x+60,y:origin.y+30),"mouse movement must move the actual borderless window")
  pointer=NSPoint(x:origin.x+130,y:origin.y+60)
  surface.mouseDragged(with:event(.leftMouseDragged,100,70))
  precondition(dragWindow.frame.origin==NSPoint(x:origin.x+90,y:origin.y+20),"drag coordinates must remain stable after the window has already moved")
  surface.mouseUp(with:event(.leftMouseUp,70,30))
  surface.mouseDragged(with:event(.leftMouseDragged,120,120))
  precondition(dragWindow.frame.origin==NSPoint(x:origin.x+90,y:origin.y+20),"releasing the mouse must end the drag")
  precondition(dashboard.level == .normal,"dragging the ring must not affect other windows")
  precondition(clicks==0,"drag release must not activate the click action")
  surface.mouseDown(with:event(.leftMouseDown,30,30))
  surface.mouseUp(with:event(.leftMouseUp,30,30))
  precondition(clicks==1,"a plain left click must activate its configured action")
  let beforeJitter=dragWindow.frame.origin
  surface.mouseDown(with:event(.leftMouseDown,40,40))
  pointer=NSPoint(x:beforeJitter.x+41,y:beforeJitter.y+41)
  surface.mouseDragged(with:event(.leftMouseDragged,41,41))
  surface.mouseUp(with:event(.leftMouseUp,41,41))
  precondition(clicks==2 && dragWindow.frame.origin==beforeJitter,"tiny click jitter must not move the ring or prevent clicking")
  surface.mouseDown(with:event(.leftMouseDown,30,30))
  pointer=NSPoint(x:beforeJitter.x+80,y:beforeJitter.y+50)
  surface.mouseDragged(with:event(.leftMouseDragged,80,50))
  pointer=NSPoint(x:beforeJitter.x+30,y:beforeJitter.y+30)
  surface.mouseDragged(with:event(.leftMouseDragged,-20,10))
  surface.mouseUp(with:event(.leftMouseUp,30,30))
  precondition(clicks==2,"dragging back to the start must still count as a drag")
  surface.mouseDown(with:event(.leftMouseDown,20,20))
  surface.mouseUp(with:event(.leftMouseUp,120,20))
  precondition(clicks==2,"releasing outside the ring must not activate")
  precondition(surface.accessibilityPerformPress() && clicks==3,"Accessibility press must match a configured left click")
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
