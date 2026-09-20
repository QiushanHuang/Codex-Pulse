import Foundation
@main struct StickyPresentationTests {
 static func window(rate:Double?=12,hours:Double?=4.2,reset:Double?=320)->QuotaWindow {
  QuotaWindow(id:"weekly",bucket:"codex",name:"Codex",label:"每周",used:50,remaining:50,reset:reset,burnRate:rate,hoursLeft:hours,history:[])
 }
 static func main() {
  let fresh=StickyQuotaMetrics(quota:window(),fresh:true,now:100)
  precondition(fresh.rate==12 && fresh.hoursLeft==4.2 && fresh.secondsToReset==220,"fresh rate, exhaustion and reset are retained")
  let stale=StickyQuotaMetrics(quota:window(),fresh:false,now:100)
  precondition(stale.rate==nil && stale.hoursLeft==nil,"stale estimates must not appear current")
  let zero=StickyQuotaMetrics(quota:window(rate:0),fresh:true,now:100)
  precondition(zero.rate==0 && zero.hoursLeft==nil,"zero rate is valid but cannot predict exhaustion")
  for rate:Double? in [nil,-1,.nan,.infinity] {
   let value=StickyQuotaMetrics(quota:window(rate:rate),fresh:true,now:100)
   precondition(value.rate==nil && value.hoursLeft==nil)
  }
  for hours:Double? in [nil,-1,.nan,.infinity] {
   precondition(StickyQuotaMetrics(quota:window(hours:hours),fresh:true,now:100).hoursLeft==nil)
  }
  precondition(StickyQuotaMetrics(quota:window(hours:0),fresh:true,now:100).hoursLeft==0)
  precondition(StickyQuotaMetrics(quota:window(reset:99),fresh:true,now:100).secondsToReset==nil)
  precondition(StickyQuotaMetrics(quota:nil,fresh:true,now:100).rate==nil)
  precondition(StickyQuotaMetrics(quota:window(reset:.greatestFiniteMagnitude),fresh:true,now:100).secondsToReset==nil)
  print("PASS: sticky speed/exhaustion values, stale/missing/zero/invalid estimates and expired reset")
 }
}
