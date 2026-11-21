import Carbon.HIToolbox

final class HotKeyManager {
    private let keyCode: UInt32
    private let modifiers: UInt32
    private let action: () -> Void

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.action = action
    }

    @discardableResult
    func register() -> Bool {
        guard hotKeyRef == nil else { return true }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                manager.action()
            }
            return noErr
        }

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )
        guard handlerStatus == noErr else {
            eventHandlerRef = nil
            return false
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4C4E4754), id: 1)
        let hotKeyStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard hotKeyStatus == noErr else {
            RemoveEventHandler(eventHandlerRef)
            eventHandlerRef = nil
            return false
        }
        return true
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }
}

