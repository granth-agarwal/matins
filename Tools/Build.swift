import Foundation

@discardableResult
func run(_ executable: String, _ arguments: [String], capture: Bool = false) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    if capture { process.standardOutput = pipe }
    try process.run()
    let data = capture ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "MorningBriefBuild", code: Int(process.terminationStatus))
    }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

let manager = FileManager.default
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
manager.changeCurrentDirectoryPath(root.path)
try run("/usr/bin/swift", ["build", "-c", "release", "--arch", "arm64"])
let bin = URL(fileURLWithPath: try run(
    "/usr/bin/swift", ["build", "-c", "release", "--arch", "arm64", "--show-bin-path"], capture: true
))
let app = root.appendingPathComponent("build/Morning Brief.app")
let contents = app.appendingPathComponent("Contents")
let macOS = contents.appendingPathComponent("MacOS")
let resources = contents.appendingPathComponent("Resources")
try manager.createDirectory(at: macOS, withIntermediateDirectories: true)
try manager.createDirectory(at: resources, withIntermediateDirectories: true)
func copy(_ source: URL, _ destination: URL) throws {
    if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
    try manager.copyItem(at: source, to: destination)
}
try copy(bin.appendingPathComponent("MorningBrief"), macOS.appendingPathComponent("MorningBrief"))
try copy(root.appendingPathComponent("App/Info.plist"), contents.appendingPathComponent("Info.plist"))
for resource in try manager.contentsOfDirectory(at: bin, includingPropertiesForKeys: nil)
where resource.pathExtension == "bundle" {
    try copy(resource, resources.appendingPathComponent(resource.lastPathComponent))
}
try run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", app.path])
print("Built \(app.path)")
