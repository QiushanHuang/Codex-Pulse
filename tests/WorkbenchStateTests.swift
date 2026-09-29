import Foundation

@main
struct WorkbenchStateTests {
    static func main() throws {
        let active = PulseTask(id: "01a0ba58-2270-79f1-ad38-c0d641f6533f", title: "Fix Window Layout", status: "active", at: 10)
        let ended = PulseTask(id: "b", title: "Review fonts", status: "completed", at: 50)
        let failed = PulseTask(id: "c", title: "Fix keyboard", status: "failed", at: 30)
        let interrupted = PulseTask(id: "d", title: "Run checks", status: "interrupted", at: 20)
        let unknown = PulseTask(id: "e", title: "Archived? No", status: "unknown", at: 15)
        let tasks = [ended, unknown, interrupted, active, failed]
        precondition(WorkbenchTasks.filtered(tasks, query: "  fix  ").map(\.id) == [active.id, failed.id], "Search must trim whitespace and ignore case")
        precondition(WorkbenchTasks.filtered(tasks, query: "01A0").map(\.id) == [active.id], "Search includes stable task ID")
        precondition(WorkbenchTasks.filtered(tasks, filter: .attention).map(\.id) == [failed.id, interrupted.id, unknown.id], "Attention includes failure, interruption and unknown")
        precondition(WorkbenchTasks.filtered(tasks, filter: .completed).map(\.id) == [ended.id], "Completed means turn ended")
        precondition(WorkbenchTasks.filtered(tasks, query: "font", filter: .active).isEmpty, "Query and filter intersect")
        precondition(WorkbenchTasks.filtered(tasks).map(\.id) == [active.id, failed.id, interrupted.id, unknown.id, ended.id], "Sort by state group then actual recent activity")
        precondition(WorkbenchTasks.taskURL(for: active)?.absoluteString == "codex://threads/01a0ba58-2270-79f1-ad38-c0d641f6533f")
        for invalid in ["", "not-an-id", "../settings", "codex://threads/abc", "01a0ba58-2270-79f1-ad38-c0d641f6533f?x=1"] {
            let task = PulseTask(id: invalid, title: "Invalid", status: "active", at: 0)
            precondition(WorkbenchTasks.taskURL(for: task) == nil, "Reject malformed or injected task links")
        }
        let heavy=PulseTask(id:"heavy",title:"Large run",status:"completed",at:1,tokensUsed:9_000_000)
        let light=PulseTask(id:"light",title:"Small run",status:"active",at:99,tokensUsed:10)
        let zero=PulseTask(id:"zero",title:"Zero run",status:"completed",at:2,tokensUsed:0)
        let missing=PulseTask(id:"missing",title:"Missing run",status:"active",at:200)
        let invalid=PulseTask(id:"invalid",title:"Bad value",status:"failed",at:100,tokensUsed:-1)
        let usageTasks=[missing,light,heavy,zero,invalid]
        precondition(WorkbenchTasks.filtered(usageTasks,sort:.tokensDescending).map(\.id)==["heavy","light","zero","missing","invalid"],"token order must override active-state priority; missing stays last")
        precondition(WorkbenchTasks.filtered(usageTasks,sort:.tokensAscending).map(\.id)==["zero","light","heavy","missing","invalid"],"a confirmed zero is not unknown")
        precondition(WorkbenchTasks.filtered(usageTasks,query:"run",filter:.completed,sort:.tokensDescending).map(\.id)==["heavy","zero"],"sorting preserves query and status intersection")
        let tie=PulseTask(id:"tie",title:"Tie",status:"failed",at:150,tokensUsed:10)
        precondition(WorkbenchTasks.filtered([light,tie],sort:.tokensDescending).map(\.id)==["tie","light"],"equal totals use recency, independent of status")
        let chart=TaskTokenComparison(tasks:usageTasks)
        precondition(chart.knownCount==3 && chart.missingCount==2 && chart.maximum==9_000_000)
        precondition(chart.fraction(for:heavy)==1 && chart.fraction(for:zero)==0 && chart.fraction(for:missing)==nil)
        precondition(abs(chart.fraction(for:light)! - 10.0/9_000_000)<1e-12,"bar lengths share a zero baseline and one maximum")
        precondition(TaskTokenComparison(tasks:[zero]).fraction(for:zero)==0,"all-zero charts must not divide by zero")
        precondition(TaskTokenComparison(tasks:[]).maximum==nil)
        let json = #"{"at":100,"status":"ready","message":"Ready","devices":[{"id":"runtime-1","key":"ghub:serial-1","name":"Logitech G913","model":"G913","provider":"ghub","connection":"LIGHTSPEED","state":"ACTIVE","support":"verified","reason":"Verified mapping","selectable":true,"layoutId":"g913-full","capabilities":["quota","keypad"]}],"selectedKey":"ghub:serial-1","activeKey":null}"#
        let inventory = try JSONDecoder().decode(DeviceInventory.self, from: Data(json.utf8))
        precondition(inventory.devices[0].isVerified && inventory.devices[0].selectable)
        precondition(inventory.selectedKey == "ghub:serial-1" && inventory.activeKey == nil, "Selection must not imply hardware activation")
        precondition(!inventory.isStale(now: 120) && inventory.isStale(now: 131))
        precondition(DeviceInventory.empty.isStale(now: 5), "Missing discovery is never fresh")
        precondition(inventory.isStale(now: 90), "Future discovery timestamps must not appear fresh")
        precondition(PulseAppearance.system.preferredScheme == nil)
        precondition(PulseAppearance.light.preferredScheme == .light && PulseAppearance.dark.preferredScheme == .dark)
        print("PASS: workbench filtering, ordering, link validation, inventory freshness and appearance")
    }
}
