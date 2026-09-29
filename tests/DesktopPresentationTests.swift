import Foundation
import CoreGraphics

@main struct DesktopPresentationTests {
 static func main() throws {
  let monitors=[DesktopDisplay(id:"left",name:"Left",frame:CGRect(x:-1600,y:0,width:1600,height:1000)),DesktopDisplay(id:"main",name:"Main",frame:CGRect(x:0,y:0,width:1440,height:900))]
  precondition(DesktopDocking.target(at:CGPoint(x:-1590,y:500),displays:monitors)?.side == .left)
  precondition(DesktopDocking.target(at:CGPoint(x:1430,y:500),displays:monitors)?.screenID == "main")
  precondition(DesktopDocking.target(at:CGPoint(x:-10,y:500),displays:monitors)?.side == .right)
  precondition(DesktopDocking.target(at:CGPoint(x:700,y:500),displays:monitors)==nil,"interior drops detach")
  precondition(DesktopDocking.target(at:CGPoint(x:700,y:1200),displays:monitors)==nil,"screen gaps do not invent a dock")
  precondition(DesktopDocking.target(for:CGRect(x:0,y:200,width:220,height:180),displays:monitors)?.side == .left)
  precondition(DesktopDocking.target(for:CGRect(x:500,y:200,width:220,height:180),displays:monitors)==nil)
  let clear=DesktopPreferences(GlassPreset.crystal.configuration)
  let soft=DesktopPreferences(GlassPreset.soft.configuration)
  precondition(clear.glassMaterial == .clear && clear.glassTransparency>soft.glassTransparency)
  precondition(soft.glassMaterial == .regular)
  let legacy=DesktopPreferences(["glassTransparency":1.0,"outerRingColor":"#AABBCC"])
  precondition(legacy.glassPreset == .custom && legacy.glassTransparency==1 && legacy.outerRingColor=="#AABBCC","migration must retain existing custom appearance")
  let position=DesktopPlacement.point(x:1,y:0,in:monitors[0].frame)
  precondition(monitors[0].frame.contains(position),"custom targets stay inside the selected display")
  precondition(DesktopPositionPreset.leftTop.side == .left && DesktopPositionPreset.rightBottom.position==0.15)
  let panelSize=DesktopPreferences(["sidebarDetailWidth":520.0,"sidebarDetailHeight":640.0])
  precondition(panelSize.sidebarDetailWidth==520 && panelSize.sidebarDetailHeight==640)
  precondition(DesktopPreferences(["sidebarDetailWidth":100.0]).sidebarDetailWidth==300)
  precondition(DesktopPreferences(["sidebarDetailHeight":Double.nan]).sidebarDetailHeight==nil)
  let fitted=SidebarGeometry.detail(in:CGRect(x:-400,y:0,width:320,height:400),handle:CGRect(x:-90,y:150,width:48,height:48),side:.right,preferredHeight:1000,preferredWidth:900)
  precondition(CGRect(x:-400,y:0,width:320,height:400).contains(fitted) && fitted.width==304 && fitted.height==384)
  let resizeDisplay=CGRect(x:-1600,y:-200,width:1600,height:1000)
  let resizeOriginal=CGRect(x:-900,y:100,width:520,height:460)
  precondition(SidebarResizeSession(frame:resizeOriginal,point:CGPoint(x:-700,y:300))==nil,"content controls must not start resizing")
  for x in [resizeOriginal.minX+4,resizeOriginal.midX,resizeOriginal.maxX-4] {
   for y in [resizeOriginal.minY+4,resizeOriginal.midY,resizeOriginal.maxY-4] {
    guard let session=SidebarResizeSession(frame:resizeOriginal,point:CGPoint(x:x,y:y)) else{continue}
    for delta in [-3000.0,3000.0] {
     let result=session.frame(at:CGPoint(x:x+delta,y:y+delta),in:resizeDisplay)
     precondition(resizeDisplay.contains(result) && result.width>=300 && result.height>=200 && result.width<=960 && result.height<=1200,"all edges must respect display and size bounds")
     if session.horizontal==0 {precondition(result.width==resizeOriginal.width)}
     if session.vertical==0 {precondition(result.height==resizeOriginal.height)}
     precondition(session.horizontal<0 ? result.maxX==resizeOriginal.maxX:result.minX==resizeOriginal.minX)
     precondition(session.vertical<0 ? result.maxY==resizeOriginal.maxY:result.minY==resizeOriginal.minY)
    }
   }
  }
  let defaults=DesktopPreferences()
  precondition(defaults.glassTransparency==0.98 && defaults.outerRingColor==nil && defaults.innerRingColor==nil)
  precondition(DesktopPreferences(["glassTransparency":2.0]).glassTransparency==1)
  precondition(DesktopPreferences(["glassTransparency":Double.nan]).glassTransparency==0.98)
  precondition(DesktopPreferences(["outerRingColor":"#ff8822", "innerRingColor":"invalid"]).outerRingColor=="#FF8822")
  precondition(DesktopPreferences(["innerRingColor":"invalid"]).innerRingColor==nil)
  precondition(defaults.stickySize == .standard && !defaults.sidebarEnabled)
  precondition(defaults.sidebarSide == .right && defaults.sidebarAutoHide)
  precondition(defaults.miniDiameter==96)
  precondition(defaults.miniClickAction == .none && defaults.miniClickAction.target==nil)
  precondition(DesktopPreferences(["miniClickAction":"future"]).miniClickAction == .none)
  precondition(MiniRingClickAction.compact.target == .compact && MiniRingClickAction.standard.target == .standard)
  for screen in [CGRect(x:0,y:0,width:1440,height:900),CGRect(x:-1920,y:100,width:1920,height:1080)] {
   for anchor in [CGRect(x:screen.minX,y:screen.minY,width:44,height:44),CGRect(x:screen.maxX-44,y:screen.maxY-44,width:44,height:44)] {
    for size in [StickySize.compact.contentSize,StickySize.standard.contentSize] {
     let frame=StickyExpansionGeometry.frame(anchor:anchor,in:screen,size:size)
     precondition(screen.contains(frame) && !frame.intersects(anchor),"floating details must stay on screen beside the ring")
    }
   }
  }
  for (raw,expected) in [(0.0,40.0),(48,48),(57.6,58),(200,160),(Double.nan,96)] {
   let prefs=DesktopPreferences(["stickySize":"mini","miniDiameter":raw])
   precondition(prefs.miniDiameter==expected && prefs.stickyContentSize==CGSize(width:expected,height:expected))
  }
  precondition(DesktopPreferences(["stickySize":"compact","miniDiameter":40.0]).stickyContentSize==StickySize.compact.contentSize)
  precondition(StickySize.mini.contentSize == CGSize(width:96,height:96),"mini must be a small square ring without a wide card")
  precondition(StickySize.compact.contentSize.width==220,"compact must be narrower than the previous 280-point card")
  precondition(defaults.sidebarBadge == .waveform,"retain the existing logo option by default")
  precondition(defaults.sidebarContent.sections == [.quota,.reset,.tasks],"default details must be simpler")
  let choices:[String:Any]=["sidebarBadge":"remaining","sidebarShowQuota":false,"sidebarShowReset":true,"sidebarShowConsumption":true,"sidebarShowTasks":true,"sidebarTaskLimit":1]
  let chosen=DesktopPreferences(choices)
  precondition(chosen.sidebarBadge == .remaining && !chosen.sidebarContent.shows(.quota))
  precondition(!chosen.sidebarContent.shows(.reset) && !chosen.sidebarContent.shows(.consumption),"hidden quotas must not leak their detail rows")
  precondition(!chosen.sidebarContent.showsTabs && chosen.sidebarContent.shows(.tasks))
  precondition(chosen.sidebarContent.preferredHeight(quotaCount:2,taskCount:8)<defaults.sidebarContent.preferredHeight(quotaCount:2,taskCount:8),"less content should use a shorter panel")
  precondition(SidebarContent(["sidebarTaskLimit":100]).taskLimit==8)
  precondition(SidebarContent(["sidebarTaskLimit":0]).taskLimit==1)
  precondition(DesktopQuotaValue(remaining:70,fresh:true).number=="70")
  precondition(DesktopQuotaValue(remaining:70,fresh:false).number=="—","a bare number must not present expired quota as current")
  for invalid in [Double.nan,.infinity,-Double.infinity] {precondition(DesktopQuotaValue(remaining:invalid,fresh:true).remaining==nil)}
  precondition(DesktopQuotaValue(remaining:-5,fresh:true).number=="0")
  precondition(DesktopQuotaValue(remaining:120,fresh:true).number=="100")
  precondition(DesktopQuotaValue(remaining:nil,fresh:true).number=="—")
  let invalid=DesktopPreferences(["stickySize":"future", "sidebarSide":"future", "sidebarPosition":Double.nan, "sidebarStyle":"future"])
  precondition(invalid == defaults,"unknown values must fall back without breaking existing configurations")
  precondition(DesktopPreferences(["sidebarPosition":2.0]).sidebarPosition==1)
  precondition(DesktopPreferences(["sidebarPosition":-3.0]).sidebarPosition==0)
  precondition(StickySize.mini.contentSize.width < StickySize.compact.contentSize.width)
  precondition(StickySize.compact.contentSize.height < StickySize.standard.contentSize.height)
  for screen in [CGRect(x:0,y:24,width:1440,height:850),CGRect(x:-1920,y:-250,width:1920,height:1080),CGRect(x:0,y:0,width:320,height:400)] {
   for side in SidebarSide.allCases {
    for position in [-1.0,0,0.5,1,2,Double.nan] {
     for tucked in [false,true] {
      let handle=SidebarGeometry.handle(in:screen,side:side,position:position,tucked:tucked)
      precondition(screen.contains(handle),"handle must stay on the usable display")
      let detail=SidebarGeometry.detail(in:screen,handle:handle,side:side)
      precondition(screen.contains(detail),"details must be clamped even near corners")
      if screen.width>600 {precondition(!handle.intersects(detail),"details must not cover the handle")}
     }
    }
   }
   let center=SidebarGeometry.handle(in:screen,side:.left,position:0.5,tucked:false)
   precondition(abs(SidebarGeometry.position(centerY:center.midY,in:screen)-0.5)<0.001)
  }
  var state=SidebarInteraction()
  state.hideIfIdle();precondition(state.tucked)
  state.hover(true);precondition(!state.tucked)
  state.hideIfIdle();precondition(!state.tucked,"hover must prevent auto-hide")
  state.toggleDetails();state.hover(false);state.hideIfIdle()
  precondition(state.expanded && !state.tucked,"an open panel must hold the handle visible")
  state.dismiss();state.hideIfIdle();precondition(state.tucked && !state.expanded)
  state.setAutoHide(false);state.hideIfIdle();precondition(!state.tucked)
  state.toggleDetails();state.toggleDetails();precondition(!state.expanded)
  state.setAutoHide(true);state.hideIfIdle();precondition(state.tucked)
  state.reset();precondition(!state.expanded && !state.tucked && !state.pointerInside)
  let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer {try? FileManager.default.removeItem(at:directory)}
  let store=PulseConfigurationStore(directory:directory)
  _=try store.update{$0["lighting"]=true;$0["windowSettings"]=["future":"keep", "stickyPinned":true]}
  _=try store.saveWindowSettings(["stickySize":"mini", "sidebarEnabled":true, "sidebarSide":"left", "sidebarPosition":0.7, "sidebarStyle":"solid"])
  let reopened=try PulseConfigurationStore(directory:directory).read()
  let values=reopened["windowSettings"] as! [String:Any]
  let preferences=DesktopPreferences(values)
  precondition(preferences.stickySize == .mini && preferences.sidebarEnabled && preferences.sidebarSide == .left)
  precondition(preferences.sidebarPosition == 0.7 && preferences.sidebarStyle == .solid)
  precondition(values["future"] as? String == "keep" && values["stickyPinned"] as? Bool == true && reopened["lighting"] as? Bool == true)
  _=try store.saveWindowSettings(choices)
  _=try store.saveWindowSettings(["miniDiameter":57.0])
  let reread=try PulseConfigurationStore(directory:directory).read()
  let reopenedChoices=DesktopPreferences(reread["windowSettings"] as! [String:Any])
  precondition(reopenedChoices.sidebarBadge == chosen.sidebarBadge && reopenedChoices.sidebarContent == chosen.sidebarContent)
  precondition(reopenedChoices.stickySize == .mini && reopenedChoices.sidebarSide == .left,"new choices must not reset earlier window preferences")
  precondition(reopenedChoices.miniDiameter==57,"custom ring size must survive reopening the configuration")
  for action in MiniRingClickAction.allCases {
   _=try store.saveWindowSettings(["miniClickAction":action.rawValue])
   let roundtrip=try PulseConfigurationStore(directory:directory).read()
   let prefs=DesktopPreferences(roundtrip["windowSettings"] as! [String:Any])
   precondition(prefs.miniClickAction==action && prefs.miniDiameter==57 && prefs.stickySize == .mini,"click action must persist without changing the current mode or diameter")
  }
  for center in RingCenterContent.allCases {
   _=try store.saveWindowSettings(["ringCenter":center.rawValue])
   let config=try store.read()
   precondition(DesktopPreferences(config["windowSettings"] as! [String:Any]).ringCenter==center)
  }
  _=try store.saveWindowSettings(["glassTransparency":0.95,"outerRingColor":"#FF8822","innerRingColor":"#4488FF"])
  let customConfig=try store.read()
  let custom=DesktopPreferences(customConfig["windowSettings"] as! [String:Any])
  precondition(custom.glassTransparency==0.95 && custom.outerRingColor=="#FF8822" && custom.innerRingColor=="#4488FF")
  _=try store.saveWindowSettings(["outerRingColor":NSNull(),"innerRingColor":NSNull(),"glassTransparency":0.85])
  let restored=try store.read()
  precondition(DesktopPreferences(restored["windowSettings"] as! [String:Any]).outerRingColor==nil)
  print("PASS: desktop preference defaults/persistence, small presets, multi-display bounds and sidebar interaction states")
 }
}
