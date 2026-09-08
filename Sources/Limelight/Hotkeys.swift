import AppKit
import Carbon.HIToolbox

/// Carbon hot keys - the only public way to get a global shortcut
/// without an Input Monitoring prompt.
final class HotkeyManager {
    static let shared = HotkeyManager()
    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef?] = []
    private var nextID: UInt32 = 1
    private var installed = false

    static let cmdOpt = UInt32(cmdKey | optionKey)
    static let keyD = UInt32(kVK_ANSI_D)
    static let keyP = UInt32(kVK_ANSI_P)

    private func install() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            HotkeyManager.shared.fire(id.id)
            return noErr
        }, 1, &spec, nil, nil)
    }

    @discardableResult
    func register(key: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> Bool {
        install()
        let id = nextID
        nextID += 1
        handlers[id] = handler
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x4C494D45), id: id)   // 'LIME'
        let err = RegisterEventHotKey(key, modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
        if err == noErr { refs.append(ref); return true }
        Log.d("hotkey registration failed (\(err)) — probably taken by another app")
        handlers[id] = nil
        return false
    }

    fileprivate func fire(_ id: UInt32) { handlers[id]?() }
}
