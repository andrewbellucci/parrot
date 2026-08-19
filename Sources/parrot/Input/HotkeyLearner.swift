import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct HotkeyCapture {
    private var pending: (keyCode: CGKeyCode, kind: HotkeyBinding.EventKind)?

    mutating func consume(
        type: CGEventType,
        keyCode: CGKeyCode,
        isRepeat: Bool,
        displayName: String
    ) -> HotkeyBinding? {
        if let pending {
            let completed = pending.keyCode == keyCode
                && ((pending.kind == .key && type == .keyUp)
                    || (pending.kind == .modifier && type == .flagsChanged))
            guard completed else { return nil }
            return HotkeyBinding(
                keyCode: keyCode,
                eventKind: pending.kind,
                displayName: displayName
            )
        }

        if type == .keyDown, !isRepeat {
            pending = (keyCode, .key)
        } else if type == .flagsChanged {
            pending = (keyCode, .modifier)
        }
        return nil
    }
}

final class HotkeyLearner {
    enum LearnerError: LocalizedError {
        case accessibilityDenied
        case tapCreateFailed
        case captureFailed

        var errorDescription: String? {
            switch self {
            case .accessibilityDenied:
                "Accessibility permission is required to learn a global hotkey"
            case .tapCreateFailed:
                "could not create the hotkey-learning event tap"
            case .captureFailed:
                "hotkey capture ended before a complete press and release"
            }
        }
    }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isArmed = false
    private var capture = HotkeyCapture()
    private var result: HotkeyBinding?

    func learn() throws -> HotkeyBinding {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        guard AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary) else {
            throw LearnerError.accessibilityDenied
        }

        let eventMask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: hotkeyLearnerCallback,
            userInfo: userInfo
        ) else {
            throw LearnerError.tapCreateFailed
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("release all keys… (^C to cancel)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            self?.isArmed = true
            print("press and release the push-to-talk key")
        }
        CFRunLoopRun()
        stop()

        guard let result else { throw LearnerError.captureFailed }
        return result
    }

    private func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        guard isArmed else { return false }
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        result = capture.consume(
            type: type,
            keyCode: keyCode,
            isRepeat: isRepeat,
            displayName: Self.displayName(for: event, keyCode: keyCode)
        )
        if result != nil {
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        return type == .keyDown || type == .keyUp || type == .flagsChanged
    }

    private static func displayName(for event: CGEvent, keyCode: CGKeyCode) -> String {
        guard let nsEvent = NSEvent(cgEvent: event),
              let characters = nsEvent.charactersIgnoringModifiers,
              !characters.isEmpty,
              characters.unicodeScalars.allSatisfy({ 32 ... 126 ~= $0.value })
        else { return "Key \(keyCode)" }
        return characters.uppercased()
    }
}

private func hotkeyLearnerCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let learner = Unmanaged<HotkeyLearner>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        return Unmanaged.passUnretained(event)
    }
    return learner.handle(type: type, event: event)
        ? nil
        : Unmanaged.passUnretained(event)
}
