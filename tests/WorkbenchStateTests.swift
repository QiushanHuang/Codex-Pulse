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
