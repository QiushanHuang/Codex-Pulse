import Foundation

@main struct UsagePresentationTests {
    static func main() throws {
        let old = Data(#"{"id":"t","title":"Old","status":"active","at":0}"#.utf8)
        let task = try JSONDecoder().decode(PulseTask.self, from: old)
        precondition(task.tokensUsed == nil && task.tokenLabel.contains("—"))
        let known = PulseTask(id:"t", title:"Test", status:"active", at:0, tokensUsed:1234567)
        precondition(known.tokenLabel.contains("1.23M"))
        precondition(PulseCredits(balance:0, unlimited:false).display(fresh:true) == "0")
        precondition(PulseCredits(balance:123.45, unlimited:false).display(fresh:true) == "123.45")
        precondition(PulseCredits(balance:nil, unlimited:true).display(fresh:true) == "∞")
        precondition(PulseCredits(balance:123, unlimited:false).display(fresh:false) == "—")
        precondition(PulseCredits(balance:Double.nan, unlimited:false).display(fresh:true) == "—")
        precondition(PulseCredits(balance:-1, unlimited:false).display(fresh:true)=="-1")
        let key=String(repeating:"a",count:64),request="12345678-1234-1234-1234-123456789abc"
        let unknown=QuotaResetResult(requestID:request,accountKey:key,state:"unknown",outcome:nil,message:"Pending",at:1)
        precondition(QuotaResetPolicy.canStart(accountKey:key,fresh:true,count:2,busy:false,result:nil))
        precondition(!QuotaResetPolicy.canStart(accountKey:key,fresh:false,count:2,busy:false,result:nil))
        precondition(!QuotaResetPolicy.canStart(accountKey:nil,fresh:true,count:2,busy:false,result:nil))
        precondition(!QuotaResetPolicy.canStart(accountKey:key,fresh:true,count:2,busy:true,result:unknown))
        precondition(QuotaResetPolicy.canStart(accountKey:key,fresh:false,count:0,busy:false,result:unknown),"an uncertain attempt reuses its key even if the count dropped")
        precondition(!QuotaResetPolicy.canStart(accountKey:String(repeating:"b",count:64),fresh:false,count:0,busy:false,result:unknown))
        print("PASS: legacy snapshots, token formatting, zero/unlimited/unknown/stale credit")
    }
}
