import Foundation
import PatchNodeCore

public enum ComposeAction: String, Sendable, Hashable, CaseIterable {
    case up
    case stop
    case restart
    /// `pull` then `up -d`.
    case update
}

/// Every command run over SSH for a compose project. Paths and the project
/// name only reach the shell through `ShellQuoting`; output in plain text
/// (`--ansi never --progress plain`).
public struct ComposeCommands: Sendable {
    public enum Failure: Error, Equatable { case notManageable, unsafePath }

    public let project: ComposeProject
    private let directory: String

    public init(project: ComposeProject) throws {
        guard project.isManageable, let directory = project.workingDirectory,
              ComposeDiscovery.isValidProjectName(project.name),
              ComposeDiscovery.isSafeAbsolutePath(directory),
              project.configFiles.allSatisfy(ComposeDiscovery.isSafeAbsolutePath)
        else { throw Failure.notManageable }
        self.project = project
        self.directory = directory
    }

    /// Every command runs under `/bin/sh -c`, whatever the user's login shell
    /// (csh would run the write after a failed `if`, zsh stops on an
    /// unmatched glob): the checks below mean what they say.
    static func sh(_ script: String) throws -> String {
        "/bin/sh -c " + (try ShellQuoting.quote(script))
    }

    /// `docker compose` for this project, with `replacing` a config file by
    /// another (a staged copy, for validation).
    func compose(replacing original: String? = nil, with staged: String? = nil) throws -> String {
        var arguments = ["docker", "compose", "--ansi", "never", "--project-directory", directory, "-p", project.name]
        for file in project.configFiles {
            arguments += ["-f", file == original ? (staged ?? file) : file]
        }
        return try ShellQuoting.command(arguments)
    }

    /// A login shell in the project's folder (interactive, with a PTY).
    public func terminalHere() throws -> String {
        try Self.sh("cd -- \(try ShellQuoting.quote(directory)) && exec \"${SHELL:-/bin/sh}\" -l")
    }

    /// Validation before any action: `config --quiet` (non-zero exit = invalid).
    public func validate(replacing original: String? = nil, with staged: String? = nil) throws -> String {
        try Self.sh(try compose(replacing: original, with: staged) + " config --quiet")
    }

    public func run(_ action: ComposeAction) throws -> String {
        let compose = try compose()
        let script = switch action {
        case .up: compose + " up -d --progress plain"
        case .stop: compose + " stop"
        case .restart: compose + " restart"
        case .update: compose + " pull --progress plain && " + compose + " up -d --progress plain"
        }
        return try Self.sh(script)
    }

    // MARK: - Files

    /// A file of this project only: one of its compose files or its `.env`.
    public func isEditable(_ path: String) -> Bool {
        project.configFiles.contains(path) || path == project.envFile
    }

    /// On the server, right before touching `path`: its folder, with every
    /// symbolic link resolved (`cd -P`, `pwd -P`), must be the folder the path
    /// names, and the file itself must not be a link (exit 4 otherwise). A
    /// project folder that is a link to `/etc` is refused here.
    static func realPathCheck(_ path: String) throws -> String {
        let folder = (path as NSString).deletingLastPathComponent
        let quotedFolder = try ShellQuoting.quote(folder)
        let quotedFile = try ShellQuoting.quote(path)
        return "real=$(cd -P -- \(quotedFolder) 2>/dev/null && pwd -P) || exit 4; "
            + "if [ \"$real\" != \(quotedFolder) ] || [ -L \(quotedFile) ]; then echo 'symbolic link in the path: not edited' >&2; exit 4; fi"
    }

    /// Prints the file, or nothing with exit status 3 if it doesn't exist; a
    /// path through a symbolic link is refused (exit 4): PatchNode only edits
    /// real files in the real project folder.
    public func read(_ path: String) throws -> String {
        guard isEditable(path) else { throw Failure.unsafePath }
        let quoted = try ShellQuoting.quote(path)
        return try Self.sh(try Self.realPathCheck(path) + "; if [ -f \(quoted) ]; then cat -- \(quoted); else exit 3; fi")
    }

    /// Our backups only: `<file>.bak-YYYYMMDD-HHMMSS`, which sort by date.
    static func backupGlob(_ quotedFile: String) -> String {
        quotedFile + ".bak-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]"
    }

    public static func stagedPath(for path: String) -> String { path + ".PatchNode-new" }

    /// Writes stdin to a new staged copy, readable by its owner only. Created
    /// exclusively (`set -C`, O_EXCL): a link planted at that name is removed
    /// first and can never be written through.
    public func stage(_ path: String) throws -> String {
        guard isEditable(path) else { throw Failure.unsafePath }
        let staged = try ShellQuoting.quote(Self.stagedPath(for: path))
        return try Self.sh(try Self.realPathCheck(path) + "; umask 077 && rm -f -- \(staged) && set -C && cat > \(staged)")
    }

    /// Validates the project with the staged copy in place of `path` (a `.env`
    /// is read by compose from the folder: it is checked in its final place,
    /// see `commit`).
    public func validateStaged(_ path: String) throws -> String {
        guard project.configFiles.contains(path) else { throw Failure.unsafePath }
        return try validate(replacing: path, with: Self.stagedPath(for: path))
    }

    /// Backs the old file up (`.bak-<stamp>`, created exclusively, owner-only:
    /// a `.env` backup holds secrets), writes the new content into the file
    /// (same inode, owner and mode; a symbolic link is refused), removes the
    /// staged copy, keeps the 5 newest backups. Backups are found by a strict
    /// glob, never by parsing `ls`: no other file can be deleted.
    public func commit(_ path: String, stamp: String) throws -> String {
        guard isEditable(path), stamp.count == 15, stamp.allSatisfy({ $0.isNumber || $0 == "-" }) else { throw Failure.unsafePath }
        let file = try ShellQuoting.quote(path)
        let staged = try ShellQuoting.quote(Self.stagedPath(for: path))
        let backup = try ShellQuoting.quote(path + ".bak-" + stamp)
        let script = [
            "set -e",
            "umask 077",
            try Self.realPathCheck(path),
            "if [ -L \(staged) ]; then echo 'symbolic link: not edited' >&2; exit 4; fi",
            "if [ -f \(file) ]; then (set -C; cat -- \(file) > \(backup)); fi",
            "cat -- \(staged) > \(file)",
            "rm -f -- \(staged)",
            "set -- \(Self.backupGlob(file))",
            "if [ -e \"$1\" ]; then extra=$(($# - 5)); for old in \"$@\"; do if [ \"$extra\" -gt 0 ]; then rm -f -- \"$old\"; extra=$((extra - 1)); fi; done; fi",
        ].joined(separator: "; ")
        return try Self.sh(script)
    }

    /// Puts back the backup `commit` just made with `stamp` (after a `.env`
    /// that fails validation) — that exact file, never the "newest" one: a
    /// file planted with a later date can't be restored.
    public func restoreBackup(_ path: String, stamp: String) throws -> String {
        guard isEditable(path), stamp.count == 15, stamp.allSatisfy({ $0.isNumber || $0 == "-" }) else { throw Failure.unsafePath }
        let file = try ShellQuoting.quote(path)
        let backup = try ShellQuoting.quote(path + ".bak-" + stamp)
        return try Self.sh(try Self.realPathCheck(path) + "; if [ -f \(backup) ] && [ ! -L \(backup) ]; then cat -- \(backup) > \(file); else exit 4; fi")
    }

    /// A `.env` created by this save and refused by validation goes away.
    public func removeEnvFile() throws -> String {
        guard let env = project.envFile else { throw Failure.unsafePath }
        return try Self.sh(try Self.realPathCheck(env) + "; rm -f -- \(try ShellQuoting.quote(env))")
    }

    public func discardStaged(_ path: String) throws -> String {
        guard isEditable(path) else { throw Failure.unsafePath }
        return try Self.sh(try Self.realPathCheck(path) + "; rm -f -- \(try ShellQuoting.quote(Self.stagedPath(for: path)))")
    }

    /// `20261011-143207`, local time.
    public static func stamp(_ date: Date = .now, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d%02d%02d-%02d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }
}
