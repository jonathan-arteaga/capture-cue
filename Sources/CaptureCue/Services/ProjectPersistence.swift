import Foundation

struct ProjectPersistence {
    private let fileManager: FileManager
    private let appSupportDirectory: URL

    init(fileManager: FileManager = .default, appSupportDirectory: URL? = nil) {
        self.fileManager = fileManager
        if let appSupportDirectory {
            self.appSupportDirectory = appSupportDirectory
        } else {
            let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.appSupportDirectory = baseDirectory.appending(path: "CaptureCue", directoryHint: .isDirectory)
        }
    }

    var projectsFileURL: URL {
        appSupportDirectory.appending(path: "projects.json")
    }

    func loadProjects() throws -> [StudioProject] {
        guard fileManager.fileExists(atPath: projectsFileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: projectsFileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([StudioProject].self, from: data)
    }

    func saveProjects(_ projects: [StudioProject]) throws {
        try fileManager.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(projects)
        try data.write(to: projectsFileURL, options: [.atomic])
    }
}
