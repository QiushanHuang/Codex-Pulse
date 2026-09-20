import Foundation
@main struct InputMonitorStateTests {
 static func main(){
 precondition(InputMonitorState.status(requested:true,preflight:false,tapActive:true)=="普通按键交互已开启")
 let healthy=InputMonitorState.assess(requested:true,preflight:false,tapActive:true,continuity:"changed")
 precondition(healthy.code == "verified" && !healthy.needsPermission, "Live OS listener overrides stale preflight and changed signature")
 let changed=InputMonitorState.assess(requested:true,preflight:false,tapActive:false,continuity:"changed")
 precondition(changed.code == "signature_changed_denied" && changed.needsPermission)
 let failed=InputMonitorState.assess(requested:true,preflight:true,tapActive:false,continuity:"changed")
 precondition(failed.code == "listener_failed" && !failed.needsPermission, "A creation failure with granted preflight must not prescribe TCC repair")
 precondition(InputMonitorState.assess(requested:false,preflight:false,tapActive:false,continuity:"changed").code == "disabled")
 precondition(InputMonitorState.assess(requested:true,preflight:false,tapActive:false,continuity:"unknown").code == "permission_required")
 precondition(InputMonitorState.assess(requested:true,preflight:false,tapActive:false,continuity:"matches").needsPermission, "A matching signature is not a permission grant")
 print("PASS: 6 authorization states and existing live-tap authority")
 }
}
