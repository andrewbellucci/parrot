import CoreGraphics
import Foundation

enum HotkeyConfigError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        if case .invalid(let message) = self { return message }
        return nil
    }
}

struct HotkeyBinding: Equatable {
    enum EventKind: String {
        case key
        case modifier
    }

    let keyCode: CGKeyCode
    let eventKind: EventKind
    let displayName: String

    static let defaultBinding = HotkeyBinding(
        keyCode: 63,
        eventKind: .modifier,
        displayName: "Fn"
    )

    var isFn: Bool { keyCode == 63 && eventKind == .modifier }

    func matches(type: CGEventType, keyCode candidate: CGKeyCode) -> Bool {
        guard candidate == keyCode else { return false }
        switch eventKind {
        case .key:
            return type == .keyDown || type == .keyUp
        case .modifier:
            return type == .flagsChanged
        }
    }

    func nextPressedState(
        type: CGEventType,
        keyCode candidate: CGKeyCode,
        isRepeat: Bool,
        currentlyPressed: Bool
    ) -> Bool? {
        guard matches(type: type, keyCode: candidate) else { return nil }
        switch eventKind {
        case .key:
            if type == .keyDown, !isRepeat { return true }
            if type == .keyUp { return false }
            return nil
        case .modifier:
            // Modifier and status keys arrive as one flagsChanged event for
            // each physical edge. Toggling state avoids aggregate flag bugs
            // when the matching modifier on the other side is also held.
            return !currentlyPressed
        }
    }
}

struct HotkeyConfigStore {
    let url: URL

    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/parrot/config.toml")
    }

    func load() throws -> HotkeyBinding {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .defaultBinding
        }
        let contents = try String(contentsOf: url, encoding: .utf8)

        if let keyCodeValue = Self.value(for: "hotkey_keycode", in: contents) {
            guard let keyCode = UInt16(keyCodeValue),
                  let kindValue = Self.quotedValue(for: "hotkey_event", in: contents),
                  let kind = HotkeyBinding.EventKind(rawValue: kindValue)
            else {
                throw HotkeyConfigError.invalid(
                    "invalid learned hotkey in \(url.path); run `parrot hotkey learn`"
                )
            }
            let name = Self.quotedValue(for: "hotkey_name", in: contents) ?? "Key \(keyCode)"
            return HotkeyBinding(keyCode: keyCode, eventKind: kind, displayName: name)
        }

        guard let legacyName = Self.quotedValue(for: "hotkey", in: contents) else {
            return .defaultBinding
        }
        guard let binding = Self.legacyBindings[legacyName] else {
            throw HotkeyConfigError.invalid(
                "unknown legacy hotkey '\(legacyName)' in \(url.path); run `parrot hotkey learn`"
            )
        }
        return binding
    }

    func save(_ binding: HotkeyBinding) throws {
        let manager = FileManager.default
        try manager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let existing = manager.fileExists(atPath: url.path)
            ? try String(contentsOf: url, encoding: .utf8)
            : ""
        var lines = existing.isEmpty
            ? []
            : existing.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let managedKeys = ["hotkey", "hotkey_keycode", "hotkey_event", "hotkey_name"]
        lines.removeAll { line in managedKeys.contains { Self.isLine(line, for: $0) } }
        while lines.last == "" { lines.removeLast() }
        if !lines.isEmpty { lines.append("") }
        lines.append("hotkey_keycode = \(binding.keyCode)")
        lines.append("hotkey_event = \"\(binding.eventKind.rawValue)\"")
        lines.append("hotkey_name = \"\(Self.escape(binding.displayName))\"")

        try (lines.joined(separator: "\n") + "\n").write(
            to: url,
            atomically: true,
            encoding: .utf8
        )
    }

    private static let legacyBindings: [String: HotkeyBinding] = [
        "fn": .defaultBinding,
        "caps-lock": HotkeyBinding(keyCode: 57, eventKind: .modifier, displayName: "Caps Lock"),
        "left-option": HotkeyBinding(keyCode: 58, eventKind: .modifier, displayName: "Left Option"),
        "right-option": HotkeyBinding(keyCode: 61, eventKind: .modifier, displayName: "Right Option"),
        "left-control": HotkeyBinding(keyCode: 59, eventKind: .modifier, displayName: "Left Control"),
        "right-control": HotkeyBinding(keyCode: 62, eventKind: .modifier, displayName: "Right Control"),
        "left-command": HotkeyBinding(keyCode: 55, eventKind: .modifier, displayName: "Left Command"),
        "right-command": HotkeyBinding(keyCode: 54, eventKind: .modifier, displayName: "Right Command"),
        "left-shift": HotkeyBinding(keyCode: 56, eventKind: .modifier, displayName: "Left Shift"),
        "right-shift": HotkeyBinding(keyCode: 60, eventKind: .modifier, displayName: "Right Shift"),
    ]

    private static func isLine(_ line: String, for key: String) -> Bool {
        let parts = line.split(separator: "=", maxSplits: 1)
        return parts.first?.trimmingCharacters(in: .whitespaces) == key
    }

    private static func value(for key: String, in contents: String) -> String? {
        guard let line = contents.components(separatedBy: .newlines)
            .first(where: { isLine($0, for: key) }),
              let equals = line.firstIndex(of: "=")
        else { return nil }
        return line[line.index(after: equals)...]
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
            .trimmingCharacters(in: .whitespaces)
    }

    private static func quotedValue(for key: String, in contents: String) -> String? {
        guard let value = value(for: key, in: contents),
              value.count >= 2,
              value.first == "\"",
              value.last == "\""
        else { return nil }
        return String(value.dropFirst().dropLast())
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
