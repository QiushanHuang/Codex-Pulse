import Foundation

struct StickyQuotaMetrics {
    let rate:Double?
    let hoursLeft:Double?
    let secondsToReset:Double?
    init(quota:QuotaWindow?,fresh:Bool,now:Double=Date().timeIntervalSince1970) {
        if fresh,let value=quota?.burnRate,value.isFinite,value>=0 {rate=value} else {rate=nil}
        if let rate,rate>0,let value=quota?.hoursLeft,value.isFinite,value>=0 {hoursLeft=value} else {hoursLeft=nil}
        if let reset=quota?.reset,reset.isFinite,now.isFinite,reset>now,(reset-now).isFinite,Int(exactly:floor((reset-now)/3600)) != nil {secondsToReset=reset-now} else {secondsToReset=nil}
    }
}
