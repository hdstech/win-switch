import AppKit
import Carbon

/// Carbon hotkey events are delivered through the classic Carbon event model,
/// which still works on modern macOS and requires no special permissions.
private func carbonHotKeyHandler(_ nextHandler: EventHandlerCallRef?,
                                 _ event: EventRef?,
                                 _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    GetEventParameter(event,
                      EventParamName(kEventParamDirectObject),
                      EventParamType(typeEventHotKeyID),
                      nil,
                      MemoryLayout<EventHotKeyID>.size,
                      nil,
                      &hotKeyID)
    let id = Int(hotKeyID.id)
    DispatchQueue.main.async { SwitcherController.shared.onHotKey(id: id) }
    return noErr
}

final class HotkeyManager {
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var handlerRef: EventHandlerRef?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), carbonHotKeyHandler, 1, &spec, nil, &handlerRef)

        // id 1: ⌥⇥ (next), id 2: ⇧⌥⇥ (previous)
        register(keyCode: UInt32(kVK_Tab), modifiers: UInt32(optionKey), id: 1)
        register(keyCode: UInt32(kVK_Tab), modifiers: UInt32(optionKey | shiftKey), id: 2)
    }

    private func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = 0x5753_5754 // 'WSWT'
        hotKeyID.id = id
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status != noErr {
            NSLog("WinSwitch: failed to register hotkey \(id): \(status)")
        }
        hotKeyRefs.append(ref)
    }
}
