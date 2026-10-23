import Foundation
@main struct WidgetTaskStateTests {
    static func main() throws {
        let json=#"{"generatedAt":100,"quotaAt":100,"windows":[],"tasks":[{"id":"q","title":"Question","status":"waiting_input","at":100,"isRunning":true},{"id":"a","title":"Approval","status":"waiting_approval","at":100,"isRunning":false}],"events":[],"keyboard":{"status":"off","message":"off"}}"#
        let snapshot=try JSONDecoder().decode(PulseSnapshot.self,from:Data(json.utf8))
        precondition(snapshot.activeCount==1,"the widget must count a still-running asynchronous question")
        precondition(snapshot.tasks[0].label=="等待回答")
        precondition(snapshot.tasks[1].label=="等待授权")
        print("PASS: widget running count and pending-action labels")
    }
}
