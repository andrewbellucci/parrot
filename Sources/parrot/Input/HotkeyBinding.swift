import ArgumentParser
import CoreGraphics
import Foundation

enum HotkeyBinding: String, CaseIterable, ExpressibleByArgument {
    case fn
    case leftOption = "left-option"
    case rightOption = "right-option"
    case leftControl = "left-control"
    case rightControl = "right-control"
    case leftCommand = "left-command"
    case rightCommand = "right-command"
    case leftShift = "left-shift"
    case rightShift = "right-shift"

    var eventFlags: CGEventFlags {
        switch self {
        case .fn: .maskSecondaryFn
        case .leftOption, .rightOption: .maskAlternate
        case .leftControl, .rightControl: .maskControl
        case .leftCommand, .rightCommand: .maskCommand
        case .leftShift, .rightShift: .maskShift
        }
    }

    // macOS virtual key codes for modifier keys.
    var keyCode: CGKeyCode {
        switch self {
        case .fn: 63
        case .leftOption: 58
        case .rightOption: 61
        case .leftControl: 59
        case .rightControl: 62
        case .leftCommand: 55
        case .rightCommand: 54
        case .leftShift: 56
        case .rightShift: 60
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
        guard FileManager.default.fileExists(atPath: url.path) else { return .fn }
        let contents = try String(contentsOf: url, encoding: .utf8)
        guard let value = Self.hotkeyValue(in: contents) else { return .fn }
        guard let binding = HotkeyBinding(rawValue: value) else {
            throw ValidationError(
                "invalid hotkey '\(value)' in \(url.path); expected one of: \(Self.supportedValues)"
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
        let replacement = "hotkey = \"\(binding.rawValue)\""

        if let index = lines.firstIndex(where: Self.isHotkeyLine) {
            lines[index] = replacement
        } else {
            if !lines.isEmpty, lines.last != "" { lines.append("") }
            lines.append(replacement)
        }

        var updated = lines.joined(separator: "\n")
        if !updated.hasSuffix("\n") { updated.append("\n") }
        try updated.write(to: url, atomically: true, encoding: .utf8)
    }

    private static var supportedValues: String {
        HotkeyBinding.allCases.map(\.rawValue).joined(separator: ", ")
    }

    private static func isHotkeyLine(_ line: String) -> Bool {
        let parts = line.split(separator: "=", maxSplits: 1)
        return parts.first?.trimmingCharacters(in: .whitespaces) == "hotkey"
    }

    private static func hotkeyValue(in contents: String) -> String? {
        guard let line = contents.components(separatedBy: .newlines).first(where: isHotkeyLine),
              let equals = line.firstIndex(of: "=")
        else { return nil }

        let value = line[line.index(after: equals)...]
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
            .trimmingCharacters(in: .whitespaces)
        guard value.count >= 2, value.first == "\"", value.last == "\"" else { return nil }
        return String(value.dropFirst().dropLast())
    }
}
