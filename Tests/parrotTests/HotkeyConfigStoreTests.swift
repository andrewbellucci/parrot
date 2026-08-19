import Foundation
import Testing
@testable import parrot

struct HotkeyConfigStoreTests {
    @Test func capsLockUsesPhysicalEdgesAndIsSuppressed() {
        #expect(HotkeyBinding.capsLock.keyCode == 57)
        #expect(HotkeyBinding.capsLock.eventFlags == .maskAlphaShift)
        #expect(HotkeyBinding.capsLock.suppressesSystemEvent)
        #expect(
            HotkeyBinding.capsLock.nextPressedState(
                currentlyPressed: false,
                eventFlags: .maskAlphaShift
            )
        )
        #expect(
            !HotkeyBinding.capsLock.nextPressedState(
                currentlyPressed: true,
                eventFlags: .maskAlphaShift
            )
        )
    }

    @Test func missingConfigDefaultsToFn() throws {
        let url = temporaryConfigURL()
        #expect(try HotkeyConfigStore(url: url).load() == .fn)
    }

    @Test func savesAndLoadsBinding() throws {
        let url = temporaryConfigURL()
        let store = HotkeyConfigStore(url: url)

        try store.save(.rightOption)

        #expect(try store.load() == .rightOption)
        #expect(try String(contentsOf: url) == "hotkey = \"right-option\"\n")
    }

    @Test func preservesOtherSettingsWhenUpdating() throws {
        let url = temporaryConfigURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "model = \"example\"\nhotkey = \"fn\"\noverlay = true\n".write(
            to: url,
            atomically: true,
            encoding: .utf8
        )

        let store = HotkeyConfigStore(url: url)
        try store.save(.leftControl)
        let result = try String(contentsOf: url)

        #expect(result.contains("model = \"example\""))
        #expect(result.contains("hotkey = \"left-control\""))
        #expect(result.contains("overlay = true"))
    }

    private func temporaryConfigURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("config.toml")
    }
}
