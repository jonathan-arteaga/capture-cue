import AppKit
import SwiftUI

@main
struct astro_lensApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var store = StudioStore()
    @State private var captureService = ScreenCaptureService()
    @State private var captureStore = CaptureStore()
    @State private var presenterService = PresenterCameraService()

    var body: some Scene {
        WindowGroup("astro-lens", id: "studio") {
            ContentView(
                store: store,
                captureService: captureService,
                captureStore: captureStore,
                presenterService: presenterService
            )
                .frame(minWidth: 1180, minHeight: 760)
                .onAppear {
                    captureStore.startGlobalShortcuts()
                    captureService.onRecordingFinished = { recording in
                        store.attachRecording(recording)
                    }
                    captureService.onPresenterRecordingWillStart = {
                        try presenterService.startCompanionRecording()
                    }
                    captureService.onPresenterRecordingWillStop = {
                        presenterService.stopCompanionRecording()
                    }
                    presenterService.refreshCameras()
                }
                .task {
                    await captureService.refreshSources()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandMenu("Capture") {
                Button("Capture Area") {
                    Task { await captureStore.captureArea() }
                }
                .keyboardShortcut("4", modifiers: [.control, .option, .shift])

                Button("Capture Full Screen") {
                    Task { await captureStore.captureFullScreen() }
                }
                .keyboardShortcut("3", modifiers: [.control, .option, .shift])

                Button("Capture Window") {
                    Task { await captureStore.captureWindow() }
                }
                .keyboardShortcut("5", modifiers: [.control, .option, .shift])

                Divider()

                Button("Copy Markup") {
                    captureStore.copySelectedCapture()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(captureStore.selectedCapture == nil)

                Button("Save Markup...") {
                    Task { await captureStore.saveSelectedCapture() }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(captureStore.selectedCapture == nil)
            }

            CommandMenu("Recording") {
                Button("Refresh Capture Sources") {
                    Task {
                        await captureService.refreshSources()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button(captureService.sessionState.isActive ? "Stop Recording" : "Start Recording") {
                    Task {
                        await captureService.toggleRecording()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(captureService.sessionState == .preparing || captureService.sessionState == .stopping)
            }

            CommandMenu("Project") {
                Button("New Demo Project") {
                    store.createProject()
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("Delete Project...") {
                    confirmAndDeleteSelectedProject()
                }
                .keyboardShortcut(.delete, modifiers: [.command])
            }

            CommandMenu("Export") {
                Button(exportCommandTitle) {
                    Task {
                        await store.exportSelectedProject()
                    }
                }
                .keyboardShortcut("e", modifiers: [.command])
                .disabled(!store.exportReadiness.canExport || store.isExporting)

                Button("Reveal Latest Export") {
                    store.revealLatestExport()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(store.exportURL == nil)

                Button("Copy Latest Export Path") {
                    store.copyLatestExportPath()
                }
                .keyboardShortcut("e", modifiers: [.command, .option])
                .disabled(store.exportURL == nil)
            }
        }

        MenuBarExtra("astro-lens", systemImage: "camera.viewfinder") {
            Button("Capture Area") {
                Task { await captureStore.captureArea() }
            }
            .keyboardShortcut("4", modifiers: [.control, .option, .shift])

            Button("Capture Screen") {
                Task { await captureStore.captureFullScreen() }
            }
            .keyboardShortcut("3", modifiers: [.control, .option, .shift])

            Button("Capture Window") {
                Task { await captureStore.captureWindow() }
            }
            .keyboardShortcut("5", modifiers: [.control, .option, .shift])

            Divider()

            Button(captureService.sessionState.isActive ? "Stop Recording" : "Start Recording") {
                Task { await captureService.toggleRecording() }
            }
            .keyboardShortcut("r", modifiers: [.command])

            Divider()

            Button("Copy Latest") {
                captureStore.copySelectedCapture()
            }
            .disabled(captureStore.selectedCapture == nil)

            Button("Save Latest...") {
                Task { await captureStore.saveSelectedCapture() }
            }
            .disabled(captureStore.selectedCapture == nil)

            Divider()

            SettingsLink {
                Label("Settings...", systemImage: "gear")
            }
        }

        Settings {
            SettingsView(store: store, captureStore: captureStore)
        }
    }

    private var exportCommandTitle: String {
        if store.isExporting,
           let exportProgress = store.exportProgress {
            return "Rendering Movie \(exportProgress.percentText)"
        }

        if store.isExporting {
            return "Rendering Movie"
        }

        return "Render \(store.selectedProject.selectedExportFormat.rawValue)"
    }

    private func confirmAndDeleteSelectedProject() {
        let project = store.selectedProject
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete Project?"
        alert.informativeText = "Delete \"\(project.title)\" from astro-lens? Recording files on disk will not be deleted."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            store.deleteSelectedProject()
        }
    }

    private func importVideo() {
        guard let url = VideoImportPicker.chooseVideo() else {
            return
        }

        Task {
            await store.importRecording(from: url)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
