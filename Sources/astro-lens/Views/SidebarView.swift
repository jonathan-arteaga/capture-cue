import SwiftUI

struct SidebarView: View {
    var store: StudioStore
    var captureService: ScreenCaptureService
    @State private var projectPendingDeletion: StudioProject?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                LogoMark(size: 26)

                Text("astro-lens")
                    .font(.headline)

                Spacer()

                Button {
                    store.createProject()
                } label: {
                    Image(systemName: "plus")
                }
                .help("New project")

                Menu {
                    Button {
                        importVideo()
                    } label: {
                        Label(store.isImporting ? "Importing Video" : "Import Video", systemImage: "square.and.arrow.down")
                    }
                    .disabled(store.isImporting)

                    Divider()

                    Button {
                        store.duplicateSelectedProject()
                    } label: {
                        Label("Duplicate Project", systemImage: "plus.square.on.square")
                    }

                    Button(role: .destructive) {
                        projectPendingDeletion = store.selectedProject
                    } label: {
                        Label("Delete Project", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .help("Project actions")
            }
            .padding(16)

            List(selection: Binding(
                get: { store.selectedProjectID },
                set: { store.selectedProjectID = $0 }
            )) {
                Section("Projects") {
                    ForEach(store.projects) { project in
                        ProjectRow(project: project)
                            .tag(project.id)
                            .contextMenu {
                                Button {
                                    store.selectedProjectID = project.id
                                    store.duplicateSelectedProject()
                                } label: {
                                    Label("Duplicate", systemImage: "plus.square.on.square")
                                }

                                Button(role: .destructive) {
                                    projectPendingDeletion = project
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }

                if store.selectedTab == .studio {
                    Section("Capture") {
                        CaptureStatusRow(captureService: captureService)
                    }
                }
            }
            .listStyle(.sidebar)

            if let importError = store.importError {
                Label(importError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
        .background(.regularMaterial)
        .alert("Delete Project?", isPresented: deleteAlertBinding, presenting: projectPendingDeletion) { project in
            Button("Delete", role: .destructive) {
                store.selectedProjectID = project.id
                store.deleteSelectedProject()
                projectPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                projectPendingDeletion = nil
            }
        } message: { project in
            Text("Delete \"\(project.title)\" from astro-lens? Recording files on disk will not be deleted.")
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { projectPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    projectPendingDeletion = nil
                }
            }
        )
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

private struct ProjectRow: View {
    let project: StudioProject

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(project.title)
                    .lineLimit(1)
                Text(project.duration.formattedDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: "play.rectangle")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}

private struct CaptureStatusRow: View {
    var captureService: ScreenCaptureService

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: captureService.authorization == .ready ? "checkmark.shield" : "exclamationmark.triangle")
                .foregroundStyle(captureService.authorization == .ready ? Color.secondary : Color.yellow)

            VStack(alignment: .leading, spacing: 2) {
                Text(captureService.authorization.title)
                Text("\(captureService.sources.count) sources")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}
