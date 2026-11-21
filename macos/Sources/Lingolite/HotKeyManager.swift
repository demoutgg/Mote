// 全局快捷键注册中心：单事件处理器按 ID 分发，支持多个组合键。
import Carbon.HIToolbox

final class HotKeyCenter {
    private var actions: [UInt32: () -> Void] = [:]
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?

    @discardableResult
    func register(
        keyCode: UInt32,
        modifiers: UInt32,
        id: UInt32,
        action: @escaping () -> Void
    ) -> Bool {
        if eventHandlerRef == nil {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            let userData = Unmanaged.passUnretained(self).toOpaque()
            let callback: EventHandlerUPP = { _, event, userData in
                guard let event, let userData else { return noErr }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return noErr }

                let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
                center.perform(id: hotKeyID.id)
                return noErr
            }

            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                callback,
                1,
                &eventType,
                userData,
                &eventHandlerRef
            )
            guard status == noErr else {
                eventHandlerRef = nil
                return false
            }
        }

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4C4E4754), id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return false }

        actions[id] = action
        hotKeyRefs.append(ref)
        return true
    }

    private func perform(id: UInt32) {
        guard let action = actions[id] else { return }
        DispatchQueue.main.async(execute: action)
    }

    deinit {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }
}

