import Foundation
import Testing
import UI
import Store

struct UITests {
    @Test func paletteSelectionAndContrast() {
        #expect(BriefPalette.index(dayOfYear: 7, previous: 0) == 1)
        #expect(BriefPalette.index(dayOfYear: 7, previous: 0, pinned: 3) == 3)
        for palette in BriefPalette.defaults {
            #expect(BriefPalette.contrast(palette.accent, palette.ground) >= 3)
            #expect(BriefPalette.contrast(palette.accent, "0E0E0E") >= 4.5)
            #expect(BriefPalette.contrast("F2EFEA", "0E0E0E") >= 4.5)
            #expect(BriefPalette.contrast("A8A39B", "1A1A1A") >= 4.5)
            #expect(BriefPalette.contrast("8F8A83", "1A1A1A") >= 4.5)
        }
    }
    @Test func checkboxStateSurvivesReopen() throws {
        let (root, store) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        try store.setTask(id: "source:key", title: "Review", checked: true)
        let reopened = try BriefStore(url: root.appendingPathComponent("test.sqlite"))
        #expect(try reopened.taskStates()["source:key"] == true)
        try reopened.setTask(id: "source:key", title: "Review", checked: false)
        #expect(try store.taskStates()["source:key"] == false)
    }
}
