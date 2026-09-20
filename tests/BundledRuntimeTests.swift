import Foundation

@main struct BundledRuntimeTests {
    static func main() throws {
        let resources = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let infoURL = resources.deletingLastPathComponent().appendingPathComponent("Info.plist")
        let info = try PropertyListSerialization.propertyList(from:Data(contentsOf:infoURL),format:nil) as! [String:Any]
        let probes:[(String,[String])] = [
            ("PulsePython",["-B","-c","import ssl,sqlite3,ctypes,bz2,lzma; from codex_pulse.codex import AppServer; from codex_pulse.monitor import History; print('Packaged Python and backend OK')"]),
            ("PulseNode",["--input-type=module","-e","import('./scripts/ambient-engine.mjs').then(m=>{if(m.presets.length!==48 || typeof WebSocket!=='function')throw Error('runtime missing'); console.log('Packaged JavaScript and WebSocket OK')})"])
        ]
        for (key,args) in probes {
            let configured=info[key] as! String
            precondition(!configured.hasPrefix("/"),"Release runtime must be relative")
            let process=Process()
            process.executableURL=PulseRuntimePaths.resolve(configured,resources:resources)
            process.currentDirectoryURL=resources.appendingPathComponent("backend")
            process.environment=["PATH":"/usr/bin:/bin", "PYTHONDONTWRITEBYTECODE":"1"]
            process.arguments=args
            try process.run(); process.waitUntilExit()
            precondition(process.terminationStatus==0,"Packaged runtime must work without Homebrew or developer environment")
        }
        print("PASS: moved release bundle launches both backends using the app runtime resolver")
    }
}
