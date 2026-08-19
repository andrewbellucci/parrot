import CoreGraphics
import Foundation
import Testing
@testable import parrot

struct HotkeyConfigStoreTests {
    @Test func captureLearnsRegularKeyPair() {
        var capture = HotkeyCapture()

        #expect(capture.consume(
            type: .keyDown,
            keyCode: 105,
            isRepeat: false,
            displayName: "Key 105"
        ) == nil)
        #expect(capture.consume(
            type: .keyUp,
            keyCode: 105,
            isRepeat: false,
            displayName: "Key 105"
        ) == HotkeyBinding(keyCode: 105, eventKind: .key, displayName: "Key 105"))
    }

    @Test func captureLearnsModifierEdgePair() {
        var capture = HotkeyCapture()

        #expect(capture.consume(
            type: .flagsChanged,
            keyCode: 56,
            isRepeat: false,
            displayName: "Key 56"
        ) == nil)
        #expect(capture.consume(
            type: .flagsChanged,
            keyCode: 56,
            isRepeat: false,
            displayName: "Key 56"
        ) == HotkeyBinding(keyCode: 56, eventKind: .modifier, displayName: "Key 56"))
    }

    @Test func regularKeyUsesKeyDownAndKeyUp() {
        let binding = HotkeyBinding(keyCode: 105, eventKind: .key, displayName: "Key 105")

        #expect(binding.nextPressedState(
            type: .keyDown,
            keyCode: 105,
            isRepeat: false,
            currentlyPressed: false
        ) == true)
        #expect(binding.nextPressedState(
            type: .keyDown,
            keyCode: 105,
            isRepeat: true,
            currentlyPressed: true
        ) == nil)
        #expect(binding.nextPressedState(
            type: .keyUp,
            keyCode: 105,
            isRepeat: false,
            currentlyPressed: true
        ) == false)
    }

    @Test func modifierUsesAlternatingFlagEdges() {
        let binding = HotkeyBinding(keyCode: 56, eventKind: .modifier, displayName: "Key 56")

        #expect(binding.nextPressedState(
            type: .flagsChanged,
            keyCode: 56,
            isRepeat: false,
            currentlyPressed: false
        ) == true)
        #expect(binding.nextPressedState(
            type: .flagsChanged,
            keyCode: 56,
            isRepeat: false,
            currentlyPressed: true
        ) == false)
        #expect(binding.nextPressedState(
            type: .flagsChanged,
            keyCode: 60,
            isRepeat: false,
            currentlyPressed: false
        ) == nil)
    }

    @Test func missingConfigDefaultsToFn() throws {
        let url = temporaryConfigURL()
        #expect(try HotkeyConfigStore(url: url).load() == .defaultBinding)
    }

    @Test func savesAndLoadsLearnedBinding() throws {
        let url = temporaryConfigURL()
        let store = HotkeyConfigStore(url: url)
        let binding = HotkeyBinding(keyCode: 105, eventKind: .key, displayName: "Key 105")

        try store.save(binding)

        #expect(try store.load() == binding)
        #expect(try String(contentsOf: url) == """
        hotkey_keycode = 105
        hotkey_event = "key"
        hotkey_name = "Key 105"

        """)
    }

    @Test func loadsLegacyNamedBinding() throws {
        let url = temporaryConfigURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "hotkey = \"caps-lock\"\n".write(to: url, atomically: true, encoding: .utf8)

        let binding = try HotkeyConfigStore(url: url).load()

        #expect(binding.keyCode == 57)
        #expect(binding.eventKind == .modifier)
        #expect(binding.displayName == "Caps Lock")
    }

    @Test func preservesOtherSettingsAndReplacesLegacyBinding() throws {
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
        try store.save(HotkeyBinding(keyCode: 105, eventKind: .key, displayName: "F13"))
        let result = try String(contentsOf: url)

        #expect(result.contains("model = \"example\""))
        #expect(result.contains("overlay = true"))
        #expect(result.contains("hotkey_keycode = 105"))
        #expect(!result.contains("hotkey = \"fn\""))
    }

    private func temporaryConfigURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("config.toml")
    }
}
