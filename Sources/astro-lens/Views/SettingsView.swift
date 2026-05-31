import SwiftUI

struct SettingsView: View {
    var store: StudioStore
    var captureStore: CaptureStore

    var body: some View {
        Form {
            Section("Studio") {
                TextField("Owner", text: Binding(
                    get: { store.defaultOwner },
                    set: { store.defaultOwner = $0 }
                ))
            }

            Section("Capture") {
                Toggle("Global screenshot shortcuts", isOn: Binding(
                    get: { captureStore.areGlobalShortcutsEnabled },
                    set: { captureStore.setGlobalShortcutsEnabled($0) }
                ))

                Text(captureStore.globalShortcutSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                HStack {
                    Text(captureStore.hasScreenRecordingPermission ? "Screen Recording allowed" : "Screen Recording needed")
                    Spacer()
                    Button("Open Settings") {
                        captureStore.openScreenRecordingSettings()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 300)
        .padding()
    }
}
