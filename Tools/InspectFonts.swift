import Foundation
import CoreText

let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Packages/UI/Sources/UI/Resources")
for file in try FileManager.default.contentsOfDirectory(at: resources, includingPropertiesForKeys: nil) where file.pathExtension == "ttf" {
    if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(file as CFURL) as? [CTFontDescriptor] {
        for descriptor in descriptors {
            let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String ?? "Unknown"
            print(file.lastPathComponent + ": " + name)
        }
    }
}
