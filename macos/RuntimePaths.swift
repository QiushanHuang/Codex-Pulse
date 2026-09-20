import Foundation

/// Resolves the interpreter configuration used by source and release builds.
enum PulseRuntimePaths {
    static func resolve(_ configured: String, resources: URL) -> URL {
        configured.hasPrefix("/") ? URL(fileURLWithPath: configured) : resources.appendingPathComponent(configured)
    }
}
