//
//  SettingsView.swift
//  Refiner
//

import SwiftUI
import Carbon.HIToolbox

struct SettingsView: View {
    var onShortcutChanged: () -> Void

    @State private var isRecording = false
    @State private var keyCode: UInt32
    @State private var modifiers: UInt32
    @State private var monitor: Any?

    init(onShortcutChanged: @escaping () -> Void) {
        self.onShortcutChanged = onShortcutChanged
        let kc = UserDefaults.standard.object(forKey: HotKeyDefaults.keyCodeKey) as? UInt32 ?? HotKeyDefaults.defaultKeyCode
        let mods = UserDefaults.standard.object(forKey: HotKeyDefaults.modifiersKey) as? UInt32 ?? HotKeyDefaults.defaultModifiers
        _keyCode = State(initialValue: kc)
        _modifiers = State(initialValue: mods)
    }

    @AppStorage("autoFixJSON") private var autoFixJSON = false

    var body: some View {
        Form {
            HStack {
                Text("Global Shortcut")
                Spacer()
                Button(action: { startRecording() }) {
                    Text(isRecording ? "Press shortcut…" : shortcutDisplayString)
                        .frame(minWidth: 120)
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Fix JSON", isOn: $autoFixJSON)
                Text("Automatically repair common JSON errors like trailing commas, single quotes, unquoted keys, and comments.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            #if DEBUG
            Section {
                Button("Reset Onboarding") {
                    UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
                }
            }
            #endif
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 180)
        .onDisappear { stopRecording() }
    }

    // MARK: - Recording

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let carbonMods = carbonModifiers(from: event.modifierFlags)
            if event.keyCode == 53 { // Escape
                stopRecording()
                return nil
            }
            guard carbonMods != 0 else {
                // Require at least one modifier
                return nil
            }
            keyCode = UInt32(event.keyCode)
            modifiers = carbonMods
            UserDefaults.standard.set(keyCode, forKey: HotKeyDefaults.keyCodeKey)
            UserDefaults.standard.set(modifiers, forKey: HotKeyDefaults.modifiersKey)
            stopRecording()
            onShortcutChanged()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    // MARK: - Display

    private var shortcutDisplayString: String {
        var parts = ""
        if modifiers & UInt32(controlKey) != 0 { parts += "\u{2303}" }
        if modifiers & UInt32(optionKey) != 0  { parts += "\u{2325}" }
        if modifiers & UInt32(shiftKey) != 0   { parts += "\u{21E7}" }
        if modifiers & UInt32(cmdKey) != 0     { parts += "\u{2318}" }
        parts += keyCodeString(keyCode)
        return parts
    }

    // MARK: - Helpers

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.option)  { mods |= UInt32(optionKey) }
        if flags.contains(.shift)   { mods |= UInt32(shiftKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        return mods
    }

    private func keyCodeString(_ code: UInt32) -> String {
        let map: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_Space): "Space", UInt32(kVK_Return): "Return",
            UInt32(kVK_Tab): "Tab", UInt32(kVK_Delete): "Delete",
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
            UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
            UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
            UInt32(kVK_ANSI_Minus): "-", UInt32(kVK_ANSI_Equal): "=",
            UInt32(kVK_ANSI_LeftBracket): "[", UInt32(kVK_ANSI_RightBracket): "]",
            UInt32(kVK_ANSI_Semicolon): ";", UInt32(kVK_ANSI_Quote): "'",
            UInt32(kVK_ANSI_Comma): ",", UInt32(kVK_ANSI_Period): ".",
            UInt32(kVK_ANSI_Slash): "/", UInt32(kVK_ANSI_Backslash): "\\",
            UInt32(kVK_ANSI_Grave): "`",
        ]
        return map[code] ?? "?"
    }
}
