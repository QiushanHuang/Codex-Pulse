import Foundation
@main struct TaskNotificationTests {
    static func main() throws {
        var policy=TaskAlertPolicy()
        let first=TaskAlert(id:"one",taskID:"t",kind:"completed",at:100,title:"Done")
        precondition(policy.consume([first],now:101).isEmpty,"startup must baseline history")
        let next=TaskAlert(id:"two",taskID:"t",kind:"waiting_input",at:102,title:"Question")
        precondition(policy.consume([first,next],now:103)==[next])
        precondition(policy.consume([next],now:104).isEmpty,"same event must not repeat")
        let stale=TaskAlert(id:"old",taskID:"t",kind:"completed",at:1,title:"Old")
        precondition(policy.consume([stale],now:500).isEmpty)
        let data=try JSONEncoder().encode(NotificationPreferences(["systemEnabled":false]))
        let decoded=try JSONDecoder().decode(NotificationPreferences.self,from:data)
        precondition(decoded.cardsEnabled)
        precondition(decoded.delivery == .cards,"existing single-channel preferences must keep that choice")
        var preferences=NotificationPreferences(["soundEnabled":true])
        for mode in NotificationDelivery.allCases {
            preferences.delivery=mode
            precondition(preferences.delivery==mode)
            let restored=NotificationPreferences(preferences.dictionary)
            precondition(restored==preferences,"the chosen mode must survive saving and relaunch")
            precondition(restored.soundForReminders==(mode != .off),"turning reminders off must silence their cue")
            if mode == .cards {precondition(!restored.systemEnabled && restored.cardsEnabled)}
            if mode == .system {precondition(restored.systemEnabled && !restored.cardsEnabled)}
        }
        precondition(next.heading=="需要你回答")
        let preview=TaskAlert(id:"preview",taskID:"",kind:"waiting_input",at:102,title:"Preview")
        precondition(!preview.resolved(taskStatus:nil),"a preview must survive the live snapshot refresh")
        precondition(next.resolved(taskStatus:"active"),"resolved requests should disappear")
        precondition(!next.resolved(taskStatus:"waiting_input"),"pending requests should stay visible")
        var starting=TaskAlertPolicy()
        precondition(starting.consume([next],now:104)==[next],"a currently pending request should appear on startup")
        print("PASS: notification deduplication, startup baseline, preferences, preview survival and request resolution")
    }
}
