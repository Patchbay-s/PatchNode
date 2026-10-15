import Foundation
import DockerKit
import PatchNodeCore

/// A Docker Compose project as its containers describe it: the Engine API
/// has no compose file, but compose labels every container with its project,
/// folder, files and service.
public struct ComposeProject: Sendable, Hashable, Identifiable {
    public static let workingDirectoryLabel = "com.docker.compose.project.working_dir"
    public static let configFilesLabel = "com.docker.compose.project.config_files"

    public let name: String
    /// Absolute folder of the project (where `docker compose` ran).
    public let workingDirectory: String?
    /// Absolute paths, the first is the main file.
    public let configFiles: [String]
    public let services: [String]
    public let runningCount: Int
    public let containerCount: Int

    public var id: String { name }

    /// The `.env` compose reads by default, next to the project.
    public var envFile: String? {
        workingDirectory.map { ($0.hasSuffix("/") ? $0 : $0 + "/") + ".env" }
    }

    /// Everything needed to work on it over SSH: a folder that isn't a
    /// system one, and compose files inside it (labels can come from an
    /// image: a file elsewhere, `/root/.ssh/…`, is never offered).
    public var isManageable: Bool {
        guard let workingDirectory, ComposeDiscovery.isProjectFolder(workingDirectory) else { return false }
        return !configFiles.isEmpty && configFiles.allSatisfy { ComposeDiscovery.isComposeFile($0, in: workingDirectory) }
    }

    public init(
        name: String, workingDirectory: String?, configFiles: [String], services: [String],
        runningCount: Int = 0, containerCount: Int = 0
    ) {
        self.name = name
        self.workingDirectory = workingDirectory
        self.configFiles = configFiles
        self.services = services
        self.runningCount = runningCount
        self.containerCount = containerCount
    }
}

public enum ComposeDiscovery {
    /// One project per `com.docker.compose.project`, with the folder and files
    /// most of its containers report. Paths that aren't plain absolute paths
    /// (labels can also come from an image) are dropped.
    public static func projects(in containers: [DockerContainer]) -> [ComposeProject] {
        let grouped = Dictionary(grouping: containers.filter { $0.composeProject != nil }) { $0.composeProject! }
        return grouped.compactMap { name, members -> ComposeProject? in
            guard isValidProjectName(name) else { return nil }
            let directory = mostCommon(members.compactMap { $0.labels[ComposeProject.workingDirectoryLabel] }.filter(isSafeAbsolutePath))
            let files = mostCommon(members.compactMap { $0.labels[ComposeProject.configFilesLabel] })
                .map { configFiles($0, relativeTo: directory) } ?? []
            let services = Set(members.compactMap(\.composeService)).filter { !$0.isEmpty }.sorted()
            return ComposeProject(
                name: name, workingDirectory: directory, configFiles: files, services: services,
                runningCount: members.count { $0.isRunning }, containerCount: members.count
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Compose's own rule: lowercase letters, digits, `-`, `_`, starting with a
    /// letter or digit.
    public static func isValidProjectName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first, name.count <= 128 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_")
        return CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789").contains(first)
            && name.unicodeScalars.allSatisfy(allowed.contains)
    }

    /// Folders that never hold a compose project.
    static let systemFolders: Set<String> = ["/", "/etc", "/usr", "/bin", "/sbin", "/boot", "/proc", "/sys", "/dev", "/lib", "/lib64", "/var", "/root/.ssh"]

    public static func isProjectFolder(_ path: String) -> Bool {
        let normalized = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        let systemPrefixes = ["/etc/", "/proc/", "/sys/", "/usr/", "/boot/", "/lib/", "/lib64/", "/bin/", "/sbin/", "/dev/", "/var/lib/"]
        return isSafeAbsolutePath(normalized) && !systemFolders.contains(normalized)
            && !systemPrefixes.contains(where: normalized.hasPrefix)
            && !normalized.split(separator: "/").contains(".ssh")
    }

    /// A `.yml`/`.yaml` file inside the project's folder.
    public static func isComposeFile(_ path: String, in folder: String) -> Bool {
        let prefix = folder.hasSuffix("/") ? folder : folder + "/"
        let lowered = path.lowercased()
        return isSafeAbsolutePath(path) && path.hasPrefix(prefix) && (lowered.hasSuffix(".yml") || lowered.hasSuffix(".yaml"))
    }

    /// Absolute and canonical (no `.`/`..` component, no `//`, no trailing
    /// `/`), no control character, reasonable length. Symbolic links along
    /// the path are checked on the server before any read or write
    /// (`ComposeCommands`).
    public static func isSafeAbsolutePath(_ path: String) -> Bool {
        guard path.hasPrefix("/"), path.count <= 1024, !path.contains("//"), path == "/" || !path.hasSuffix("/"),
              !path.unicodeScalars.contains(where: ShellQuoting.isControl)
        else { return false }
        return !path.split(separator: "/").contains { $0 == ".." || $0 == "." }
    }

    /// `a.yml,b.yml` (absolute since compose 2; relative ones resolved
    /// against the folder).
    static func configFiles(_ label: String, relativeTo directory: String?) -> [String] {
        label.split(separator: ",").compactMap { part -> String? in
            let path = part.trimmingCharacters(in: .whitespaces)
            if path.hasPrefix("/") { return isSafeAbsolutePath(path) ? path : nil }
            guard let directory, !path.isEmpty else { return nil }
            let joined = (directory.hasSuffix("/") ? directory : directory + "/") + path
            return isSafeAbsolutePath(joined) ? joined : nil
        }
    }

    private static func mostCommon(_ values: [String]) -> String? {
        Dictionary(grouping: values, by: { $0 }).max { $0.value.count < $1.value.count }?.key
    }
}
