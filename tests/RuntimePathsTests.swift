import Foundation

@main struct RuntimePathsTests {
    static func main() throws {
        let resources = URL(fileURLWithPath: "/tmp/移动的应用/Codex Pulse.app/Contents/Resources")
        let bundled = PulseRuntimePaths.resolve("runtime/python/bin/python3", resources: resources)
        precondition(bundled.path == resources.appendingPathComponent("runtime/python/bin/python3").path,
                     "Bundled runtime must follow the app after moving it, including spaces and Unicode")
        let external = PulseRuntimePaths.resolve("/opt/homebrew/bin/python3", resources: resources)
        precondition(external.path == "/opt/homebrew/bin/python3", "Source builds retain absolute runtimes")
        print("PASS: relocated bundled runtimes and external source runtimes")
    }
}
