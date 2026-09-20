import Foundation
import JavaScriptCore
@main struct AmbientJavaScriptTests {
 static func main() throws {
 let js=JSContext()!
 let source=try String(contentsOfFile:CommandLine.arguments[1],encoding:.utf8)
 js.evaluateScript(source.replacingOccurrences(of:"export ",with:""))
 precondition(js.exception==nil,"Engine must execute in native JavaScriptCore")
 js.evaluateScript("function check(id,t,opts){return render(presets.find(p=>p.id===id),t,opts)}")
 let f=js.objectForKeyedSubscript("check")!
 let a=f.call(withArguments:["g-lane",0.2,["events":[]]])!.toDictionary()!
 let b=f.call(withArguments:["g-lane",0.2,["events":[["id":"G3","at":0]]]])!.toDictionary()!
 precondition((a["G3"] as! [NSNumber]) != (b["G3"] as! [NSNumber]))
 precondition((a["4"] as! [NSNumber]) != (b["4"] as! [NSNumber]))
 precondition(b["58"]==nil,"Functional keys must remain outside design rendering")
 print("PASS: JavaScriptCore engine, native input bridge, G3/main response, functional exclusion")
 }
}
