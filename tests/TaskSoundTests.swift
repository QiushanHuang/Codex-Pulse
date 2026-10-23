import Foundation
import AppKit
@main struct TaskSoundTests {
    static func main() throws {
        var policy=TaskSoundPolicy()
        precondition(!policy.consume(enabled:false,at:100))
        precondition(policy.consume(enabled:true,at:100.1),"disabled events must not consume the sound budget")
        precondition(!policy.consume(enabled:true,at:100.2),"a burst must not overlap sounds")
        precondition(policy.consume(enabled:true,at:101.2),"a later reminder can sound again")
        precondition(!policy.consume(enabled:true,at:.nan))
        precondition(NotificationPreferences().dictionary["soundSelections"] != nil,
                     "each event needs a persistent sound selection")
        var preferences=NotificationPreferences(["soundEnabled":true])
        let defaults=ReminderEvent.allCases.map {preferences.sound(for:$0)}
        precondition(Set(defaults).count==ReminderEvent.allCases.count,"defaults must distinguish every event")
        for sound in ReminderSound.allCases {
            if let path=sound.path {precondition(NSSound(contentsOfFile:path,byReference:true) != nil,"unreadable system sound: \(path)")}
            preferences.soundSelections["waiting_input"]=sound.rawValue
            precondition(NotificationPreferences(preferences.dictionary)==preferences)
            let decoded=try JSONDecoder().decode(NotificationPreferences.self,from:JSONEncoder().encode(preferences))
            precondition(decoded==preferences)
        }
        let old=try JSONDecoder().decode(NotificationPreferences.self,from:Data("{\"soundEnabled\":true,\"cardsEnabled\":false}".utf8))
        precondition(old.soundEnabled && !old.cardsEnabled && old.sound(for:.failed) == .basso,"old settings must migrate")
        let invalid=NotificationPreferences(["soundSelections":["failed":"../../unknown","completed":"silent"]])
        precondition(invalid.sound(for:.failed) == .basso && invalid.sound(for:.completed) == .silent)
        let done=TaskAlert(id:"d",taskID:"t",kind:"completed",at:10,title:"Done")
        let question=TaskAlert(id:"q",taskID:"t",kind:"waiting_input",at:10,title:"Question")
        let failed=TaskAlert(id:"f",taskID:"t",kind:"failed",at:10,title:"Failed")
        preferences=NotificationPreferences(["soundEnabled":true])
        precondition(preferences.soundCandidate(in:[done,question]) == .ping)
        precondition(preferences.soundCandidate(in:[failed,question,done]) == .basso)
        preferences.soundSelections["failed"]="silent"
        precondition(preferences.soundCandidate(in:[failed,question]) == .ping,"silent events must not mask audible ones")
        preferences.delivery = .off
        precondition(preferences.soundCandidate(in:[question]) == nil)
        preferences.delivery = .cards;preferences.soundEnabled=false
        precondition(preferences.soundCandidate(in:[question]) == nil)
        var resetPolicy=TaskAlertPolicy()
        let reset=TaskAlert(id:"reset",taskID:"",kind:"reset",at:100,title:"Quota reset")
        precondition(resetPolicy.consume([reset],now:101).isEmpty,"do not replay resets on startup")
        let fresh=TaskAlert(id:"fresh",taskID:"",kind:"reset",at:102,title:"Quota reset")
        precondition(resetPolicy.consume([fresh],now:103)==[fresh])
        precondition(resetPolicy.consume([fresh],now:104).isEmpty)
        print("PASS: per-event defaults, 14 decodable sounds, migration, persistence, mute, priority and reset deduplication")
    }
}
