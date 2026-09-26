import Foundation
import CoreGraphics

@main struct DesktopPresentationTests {
 static func main() throws {
  let defaults=DesktopPreferences()
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
  print("PASS: desktop preference defaults/persistence, small presets, multi-display bounds and sidebar interaction states")
 }
}
