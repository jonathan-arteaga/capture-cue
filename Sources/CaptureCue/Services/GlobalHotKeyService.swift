import Carbon.HIToolbox
import Foundation

@MainActor
final class GlobalHotKeyService {
    private static let signature = OSType(0x5453_4854)

    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var actionByID: [UInt32: GlobalShortcutAction] = [:]
    private var handler: ((GlobalShortcutAction) -> Void)?

    func register(
        shortcuts: [GlobalShortcut],
        handler: @escaping (GlobalShortcutAction) -> Void
    ) -> [GlobalShortcutRegistration] {
        self.handler = handler
        installEventHandlerIfNeeded()
        unregisterAll()

        return shortcuts.map { shortcut in
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(
                signature: Self.signature,
                id: shortcut.action.rawValue
            )
            let status = RegisterEventHotKey(
                shortcut.keyCode,
                shortcut.modifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )

            if status == noErr, let hotKeyRef {
                hotKeyRefs.append(hotKeyRef)
                actionByID[shortcut.action.rawValue] = shortcut.action
            }

            return GlobalShortcutRegistration(shortcut: shortcut, status: status)
        }
    }

    func unregisterAll() {
        hotKeyRefs.forEach { UnregisterEventHotKey($0) }
        hotKeyRefs = []
        actionByID = [:]
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            Self.handleHotKeyEvent,
            1,
            &eventType,
            userData,
            &eventHandler
        )
    }

    private func handleHotKey(id: UInt32) {
        guard let action = actionByID[id] else { return }
        handler?(action)
    }

    private static let handleHotKeyEvent: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }

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

        guard status == noErr else { return status }

        let service = Unmanaged<GlobalHotKeyService>
            .fromOpaque(userData)
            .takeUnretainedValue()

        Task { @MainActor in
            service.handleHotKey(id: hotKeyID.id)
        }

        return noErr
    }
}
