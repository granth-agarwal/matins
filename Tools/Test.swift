import Foundation

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
let plugin = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
process.arguments = ["test"]
if FileManager.default.fileExists(atPath: plugin) {
    process.arguments! += ["-Xswiftc", "-plugin-path", "-Xswiftc", plugin]
}
process.currentDirectoryURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
try process.run()
process.waitUntilExit()
exit(process.terminationStatus)
