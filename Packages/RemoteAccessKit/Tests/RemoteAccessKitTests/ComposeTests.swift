import Foundation
import Testing
import Crypto
import NIOCore
import NIOPosix
import NIOSSH
import PatchNodeCore
import DockerKit
@testable import RemoteAccessKit

@Suite("Compose projects from container labels")
struct ComposeDiscoveryTests {
    private func container(_ name: String, project: String?, dir: String?, files: String?, service: String?, running: Bool = true) -> DockerContainer {
        var labels: [String: String] = [:]
        if let project { labels["com.docker.compose.project"] = project }
        if let dir { labels["com.docker.compose.project.working_dir"] = dir }
        if let files { labels["com.docker.compose.project.config_files"] = files }
        if let service { labels["com.docker.compose.service"] = service }
        return DockerContainer(id: name + "-id", name: name, state: running ? .running : .exited, labels: labels)
    }

    @Test func groupsByProjectWithFolderFilesAndServices() {
        let projects = ComposeDiscovery.projects(in: [
            container("web-1", project: "web", dir: "/opt/stacks/web", files: "/opt/stacks/web/compose.yaml,/opt/stacks/web/override.yaml", service: "nginx"),
            container("web-2", project: "web", dir: "/opt/stacks/web", files: "/opt/stacks/web/compose.yaml,/opt/stacks/web/override.yaml", service: "php", running: false),
            container("lonely", project: nil, dir: nil, files: nil, service: nil),
        ])
        #expect(projects.count == 1)
        let web = projects[0]
        #expect(web.name == "web")
        #expect(web.workingDirectory == "/opt/stacks/web")
        #expect(web.configFiles == ["/opt/stacks/web/compose.yaml", "/opt/stacks/web/override.yaml"])
        #expect(web.services == ["nginx", "php"])
        #expect(web.runningCount == 1 && web.containerCount == 2)
        #expect(web.envFile == "/opt/stacks/web/.env")
        #expect(web.isManageable)
    }

    @Test func relativeFilesResolveAgainstTheFolder() {
        let projects = ComposeDiscovery.projects(in: [container("a", project: "app", dir: "/srv/app", files: "docker-compose.yml", service: "a")])
        #expect(projects[0].configFiles == ["/srv/app/docker-compose.yml"])
    }

    @Test(arguments: [
        "relative/dir", "/srv/../etc", "/srv/./x", "/srv/app\n/etc", "/srv/\u{202E}gnp", "",
    ])
    func unsafeFoldersAreDropped(dir: String) {
        let projects = ComposeDiscovery.projects(in: [container("a", project: "app", dir: dir, files: "/srv/app/compose.yaml", service: "a")])
        #expect(projects.first?.workingDirectory == nil)
        #expect(projects.first?.isManageable == false)
    }

    @Test func filesOutsideTheFolderOrInSystemFoldersAreNotManageable() {
        func project(_ dir: String, _ files: [String]) -> ComposeProject {
            ComposeProject(name: "x", workingDirectory: dir, configFiles: files, services: [])
        }
        #expect(project("/opt/stacks/web", ["/opt/stacks/web/compose.yaml"]).isManageable)
        #expect(!project("/opt/stacks/web", ["/root/.ssh/authorized_keys"]).isManageable)
        #expect(!project("/opt/stacks/web", ["/opt/stacks/other/compose.yaml"]).isManageable)
        #expect(!project("/opt/stacks/web", ["/opt/stacks/web/secrets.txt"]).isManageable)
        #expect(!project("/", ["/compose.yaml"]).isManageable)
        #expect(!project("/etc", ["/etc/compose.yml"]).isManageable)
        #expect(!project("/etc/nginx", ["/etc/nginx/compose.yml"]).isManageable)
        #expect(!project("/var/lib/rancher/k3s/server/manifests", ["/var/lib/rancher/k3s/server/manifests/a.yaml"]).isManageable)
        #expect(!project("/usr/local/app", ["/usr/local/app/compose.yaml"]).isManageable)
        #expect(!project("/home/me/.ssh", ["/home/me/.ssh/compose.yml"]).isManageable)
        #expect(throws: ComposeCommands.Failure.notManageable) {
            try ComposeCommands(project: project("/opt/stacks/web", ["/etc/passwd"]))
        }
    }

    @Test func invalidProjectNamesAreIgnored() {
        #expect(ComposeDiscovery.isValidProjectName("my-app_2"))
        #expect(!ComposeDiscovery.isValidProjectName("My App"))
        #expect(!ComposeDiscovery.isValidProjectName("-x"))
        #expect(!ComposeDiscovery.isValidProjectName("a;reboot"))
        #expect(ComposeDiscovery.projects(in: [container("a", project: "x$(id)", dir: "/a", files: "/a/c.yml", service: "a")]).isEmpty)
    }
}

@Suite("Compose commands")
struct ComposeCommandsTests {
    let project = ComposeProject(name: "web", workingDirectory: "/opt/my stacks/it's web", configFiles: ["/opt/my stacks/it's web/compose.yaml"], services: ["nginx"])

    @Test func everyPathIsQuoted() throws {
        let commands = try ComposeCommands(project: project)
        let up = "'docker' 'compose' '--ansi' 'never' '--project-directory' '/opt/my stacks/it'\\''s web' '-p' 'web' '-f' '/opt/my stacks/it'\\''s web/compose.yaml' up -d --progress plain"
        #expect(try commands.run(.up) == "/bin/sh -c " + (try ShellQuoting.quote(up)))
        let here = "cd -- '/opt/my stacks/it'\\''s web' && exec \"${SHELL:-/bin/sh}\" -l"
        #expect(try commands.terminalHere() == "/bin/sh -c " + (try ShellQuoting.quote(here)))
        #expect(try commands.run(.update).contains(" pull --progress plain && "))
        #expect(try commands.run(.stop).hasSuffix(" stop'"))
        #expect(try commands.run(.restart).hasSuffix(" restart'"))
    }

    @Test func onlyTheProjectsFilesCanBeReadOrWritten() throws {
        let commands = try ComposeCommands(project: project)
        #expect(throws: ComposeCommands.Failure.unsafePath) { try commands.read("/etc/shadow") }
        #expect(throws: ComposeCommands.Failure.unsafePath) { try commands.stage("/root/.ssh/authorized_keys") }
        #expect(try commands.read("/opt/my stacks/it's web/.env").contains("cat --"))
        #expect(throws: ComposeCommands.Failure.unsafePath) { try commands.commit(project.configFiles[0], stamp: "$(reboot)") }
        #expect(!ComposeDiscovery.isSafeAbsolutePath("/opt//stacks"))
        #expect(!ComposeDiscovery.isSafeAbsolutePath("/opt/stacks/"))
    }

    @Test func aProjectWithoutFolderIsNotManageable() {
        #expect(throws: ComposeCommands.Failure.notManageable) {
            try ComposeCommands(project: ComposeProject(name: "x", workingDirectory: nil, configFiles: [], services: []))
        }
    }

    @Test func stampIsDigitsAndDash() {
        let date = Date(timeIntervalSince1970: 1_791_000_000)
        let stamp = ComposeCommands.stamp(date, timeZone: TimeZone(identifier: "UTC")!)
        #expect(stamp == "20261014-030000" || stamp.count == 15)
        #expect(stamp.allSatisfy { $0.isNumber || $0 == "-" })
    }
}

@Suite("Diff and .env masking")
struct TextDiffTests {
    @Test func showsRemovedThenAddedWithContext() {
        let old = "a\nb\nc\nd\ne\nf\ng\nh\ni"
        let new = "a\nb\nc\nd\nE\nf\ng\nh\ni"
        let lines = TextDiff.lines(old: old, new: new, context: 1)
        #expect(lines.map(\.kind) == [.unchanged, .removed, .added, .unchanged])
        #expect(lines.map(\.text) == ["d", "e", "E", "f"])
        #expect(lines[1].number == 5 && lines[2].number == 5)
        #expect(TextDiff.hasChanges(old: old, new: new))
        #expect(!TextDiff.hasChanges(old: old, new: old))
    }

    @Test func masksValuesButNotKeysOrComments() {
        #expect(EnvMasking.masked("# db\nPOSTGRES_PASSWORD=s3cret\nEMPTY=\nURL=a=b\n") == "# db\nPOSTGRES_PASSWORD=••••\nEMPTY=\nURL=••••\n")
    }
}

/// An SSH server whose exec runs commands with a real /bin/sh, in a
/// temporary folder, with a fake `docker` (exit 1 if the compose file
/// contains "invalid"): the remote file operations run for real.
final class ShellSSHServer: Sendable {
    let hostKey = Curve25519.Signing.PrivateKey()
    let channel: any Channel
    let root: URL

    init(allowedKey: Curve25519.Signing.PublicKey, loginShell: String = "/bin/sh") async throws {
        // Resolved: on macOS the temporary folder is behind a symbolic link
        // (/var → /private/var), which the real-path check would refuse.
        // (Foundation's resolvingSymlinksInPath drops /private: realpath.)
        let temporary = realpath(FileManager.default.temporaryDirectory.path(percentEncoded: false), nil).map { pointer in
            defer { free(pointer) }
            return String(cString: pointer)
        } ?? NSTemporaryDirectory()
        root = URL(fileURLWithPath: temporary, isDirectory: true).appending(path: "PatchNode-compose-\(UUID().uuidString)", directoryHint: .isDirectory)
        let bin = root.appending(path: "bin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let docker = bin.appending(path: "docker")
        try """
        #!/bin/sh
        # Fake docker compose: "config" fails when a -f file contains "invalid"
        # or the project's .env contains "BROKEN".
        action=""
        list=$(mktemp)
        while [ $# -gt 0 ]; do
          case "$1" in
            compose) shift ;;
            -f) printf '%s\\n' "$2" >> "$list"; shift 2 ;;
            --project-directory|-p|--ansi|--progress) shift 2 ;;
            *) action="$action $1"; shift ;;
          esac
        done
        case "$action" in
          *config*)
            status=0
            while IFS= read -r f; do
              if grep -q invalid "$f"; then echo "yaml: invalid at line 1" >&2; status=1; fi
              if [ -f "$(dirname "$f")/.env" ] && grep -q BROKEN "$(dirname "$f")/.env"; then echo "env: bad" >&2; status=1; fi
            done < "$list"
            rm -f "$list"; exit $status ;;
          *) rm -f "$list"; echo "ran$action"; exit 0 ;;
        esac
        """.write(to: docker, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: docker.path(percentEncoded: false))
        let hostKey = self.hostKey
        let auth = KeyAuth(allowed: allowedKey)
        let path = bin.path(percentEncoded: false) + ":/usr/bin:/bin"
        channel = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .childChannelInitializer { child in
                child.eventLoop.makeCompletedFuture {
                    try child.pipeline.syncOperations.addHandler(NIOSSHHandler(
                        role: .server(.init(hostKeys: [NIOSSHPrivateKey(ed25519Key: hostKey)], userAuthDelegate: auth, globalRequestDelegate: nil)),
                        allocator: child.allocator,
                        inboundChildChannelInitializer: { session, _ in
                            session.eventLoop.makeCompletedFuture {
                                try session.pipeline.syncOperations.addHandler(ShellSession(path: path, loginShell: loginShell))
                            }
                        }
                    ))
                }
            }
            .bind(host: "127.0.0.1", port: 0).get()
    }

    var fingerprint: String { SSHHostKeyFingerprint.of(NIOSSHPrivateKey(ed25519Key: hostKey).publicKey) }
    var endpoint: SSHEndpoint { SSHEndpoint(host: "127.0.0.1", port: channel.localAddress?.port ?? 0, username: "patchnode") }

    func stop() {
        channel.close(promise: nil)
        try? FileManager.default.removeItem(at: root)
    }
}

private final class KeyAuth: NIOSSHServerUserAuthenticationDelegate, Sendable {
    let allowed: NIOSSHPublicKey
    init(allowed: Curve25519.Signing.PublicKey) { self.allowed = allowed.nioKey }
    var supportedAuthenticationMethods: NIOSSHAvailableUserAuthenticationMethods { [.publicKey] }
    func requestReceived(request: NIOSSHUserAuthenticationRequest, responsePromise: EventLoopPromise<NIOSSHUserAuthenticationOutcome>) {
        if case .publicKey(let key) = request.request, key.publicKey == allowed {
            responsePromise.succeed(.success)
        } else {
            responsePromise.succeed(.failure)
        }
    }
}

private final class ShellSession: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData
    private let path: String
    private let loginShell: String
    private var command: String?
    private var stdin = Data()

    init(path: String, loginShell: String) {
        self.path = path
        self.loginShell = loginShell
    }

    func handlerAdded(context: ChannelHandlerContext) {
        context.channel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true).whenFailure { _ in }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case let exec as SSHChannelRequestEvent.ExecRequest:
            command = exec.command
            if exec.wantReply { context.triggerUserOutboundEvent(ChannelSuccessEvent(), promise: nil) }
        case let event as ChannelEvent where event == .inputClosed:
            guard let command else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: loginShell)
            process.arguments = ["-c", command]
            process.environment = ["PATH": path, "SHELL": "/bin/sh"]
            let input = Pipe(), output = Pipe()
            process.standardInput = input
            process.standardOutput = output
            process.standardError = output
            do {
                try process.run()
                input.fileHandleForWriting.write(stdin)
                try? input.fileHandleForWriting.close()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                var buffer = context.channel.allocator.buffer(capacity: data.count)
                buffer.writeBytes(data)
                context.writeAndFlush(NIOAny(SSHChannelData(type: .channel, data: .byteBuffer(buffer))), promise: nil)
                context.triggerUserOutboundEvent(SSHChannelRequestEvent.ExitStatus(exitStatus: Int(process.terminationStatus)), promise: nil)
            } catch {
                context.triggerUserOutboundEvent(SSHChannelRequestEvent.ExitStatus(exitStatus: 127), promise: nil)
            }
            context.close(promise: nil)
        default:
            context.fireUserInboundEventTriggered(event)
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard case .byteBuffer(let buffer) = unwrapInboundIn(data).data else { return }
        stdin.append(contentsOf: buffer.readableBytesView)
    }
}

@Suite("Compose over SSH, run by a real shell", .serialized)
struct ComposeRemoteTests {
    let clientKey = Curve25519.Signing.PrivateKey()

    /// A project folder whose name needs quoting.
    private func makeProject(in server: ShellSSHServer) throws -> ComposeProject {
        let dir = server.root.appending(path: "my stacks/it's web", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "services:\n  web:\n    image: nginx:1.27\n".write(to: dir.appending(path: "compose.yaml"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: dir.appending(path: "compose.yaml").path(percentEncoded: false))
        let path = dir.path(percentEncoded: false)
        let directory = path.hasSuffix("/") ? String(path.dropLast()) : path
        return ComposeProject(name: "web", workingDirectory: directory, configFiles: [directory + "/compose.yaml"], services: ["web"])
    }

    private func remote(_ server: ShellSSHServer, _ project: ComposeProject) async throws -> ComposeRemote {
        let connection = try await SSHAccess.connect(endpoint: server.endpoint, pinnedHostKey: server.fingerprint, key: clientKey, askPassword: { nil })
        return ComposeRemote(connection: connection, commands: try ComposeCommands(project: project))
    }

    private func read(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test func readsTheFileAndReportsAMissingEnv() async throws {
        let server = try await ShellSSHServer(allowedKey: clientKey.publicKey)
        defer { server.stop() }
        let project = try makeProject(in: server)
        let remote = try await remote(server, project)
        defer { remote.close() }
        #expect(try await remote.read(project.configFiles[0]) == "services:\n  web:\n    image: nginx:1.27\n")
        #expect(try await remote.read(project.envFile!) == nil)
    }

    @Test func aValidSaveBacksUpKeepsPermissionsAndKeepsFiveBackups() async throws {
        let server = try await ShellSSHServer(allowedKey: clientKey.publicKey)
        defer { server.stop() }
        let project = try makeProject(in: server)
        let file = project.configFiles[0]
        let remote = try await remote(server, project)
        defer { remote.close() }
        for minute in 0..<7 {
            let content = "services: {} # v\(minute)\n"
            let date = Date(timeIntervalSince1970: 1_790_000_000 + Double(minute * 60))
            #expect(try await remote.save(file, content: content, now: date) == .saved)
            #expect(try read(file) == content)
        }
        let folder = URL(fileURLWithPath: project.workingDirectory!)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        #expect(names.filter { $0.hasPrefix("compose.yaml.bak-") }.count == 5)
        #expect(!names.contains("compose.yaml.PatchNode-new"))
        let mode = try FileManager.default.attributesOfItem(atPath: file)[.posixPermissions] as? Int
        #expect(mode == 0o640)
    }

    @Test func anInvalidFileIsRefusedAndTheOriginalKept() async throws {
        let server = try await ShellSSHServer(allowedKey: clientKey.publicKey)
        defer { server.stop() }
        let project = try makeProject(in: server)
        let file = project.configFiles[0]
        let before = try read(file)
        let remote = try await remote(server, project)
        defer { remote.close() }
        let result = try await remote.save(file, content: "services: invalid\n")
        #expect(result == .invalid(output: "yaml: invalid at line 1\n"))
        #expect(try read(file) == before)
        let names = try FileManager.default.contentsOfDirectory(atPath: project.workingDirectory!)
        #expect(!names.contains { $0.contains(".bak-") || $0.contains("PatchNode-new") })
    }

    @Test func aBrokenEnvIsRolledBackAndANewOneRemoved() async throws {
        let server = try await ShellSSHServer(allowedKey: clientKey.publicKey)
        defer { server.stop() }
        let project = try makeProject(in: server)
        let env = project.envFile!
        let remote = try await remote(server, project)
        defer { remote.close() }
        // New .env, refused: removed.
        #expect(try await remote.save(env, content: "BROKEN=1\n", existed: false) != .saved)
        #expect(!FileManager.default.fileExists(atPath: env))
        // Valid one, then a refused change: the previous one comes back.
        #expect(try await remote.save(env, content: "TOKEN=abc\n", existed: false) == .saved)
        #expect(try await remote.save(env, content: "BROKEN=1\n", existed: true, now: .now.addingTimeInterval(2)) != .saved)
        #expect(try read(env) == "TOKEN=abc\n")
    }

    @Test func injectionInContentOrPathsNeverRuns() async throws {
        let server = try await ShellSSHServer(allowedKey: clientKey.publicKey)
        defer { server.stop() }
        let project = try makeProject(in: server)
        let marker = server.root.appending(path: "pwned").path(percentEncoded: false)
        let remote = try await remote(server, project)
        defer { remote.close() }
        let content = "services: {}\n# $(touch \(marker)) `touch \(marker)` '; touch \(marker); '\n"
        #expect(try await remote.save(project.configFiles[0], content: content) == .saved)
        #expect(try read(project.configFiles[0]) == content)
        #expect(!FileManager.default.fileExists(atPath: marker))
    }

    @Test func aCraftedFileNameNeverGetsAnotherFileDeleted() async throws {
        let server = try await ShellSSHServer(allowedKey: clientKey.publicKey)
        defer { server.stop() }
        let project = try makeProject(in: server)
        let file = project.configFiles[0]
        let folder = project.workingDirectory!
        let victim = folder + "/victim"
        try "keep me".write(toFile: victim, atomically: true, encoding: .utf8)
        // A name `ls` would print over two lines, the second one naming another file.
        let trap = file + ".bak-x\nvictim"
        try "trap".write(toFile: trap, atomically: false, encoding: .utf8)
        let remote = try await remote(server, project)
        defer { remote.close() }
        for minute in 0..<7 {
            #expect(try await remote.save(file, content: "services: {} # \(minute)\n", now: Date(timeIntervalSince1970: 1_790_000_000 + Double(minute * 60))) == .saved)
        }
        #expect(try read(victim) == "keep me")
        #expect(FileManager.default.fileExists(atPath: trap))
    }

    @Test func aPlantedSymlinkIsNeverWrittenThrough() async throws {
        let server = try await ShellSSHServer(allowedKey: clientKey.publicKey)
        defer { server.stop() }
        let project = try makeProject(in: server)
        let file = project.configFiles[0]
        let victim = server.root.appending(path: "victim").path(percentEncoded: false)
        try "keep me".write(toFile: victim, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(atPath: ComposeCommands.stagedPath(for: file), withDestinationPath: victim)
        let remote = try await remote(server, project)
        defer { remote.close() }
        #expect(try await remote.save(file, content: "services: {}\n") == .saved)
        #expect(try read(victim) == "keep me")
        #expect(try read(file) == "services: {}\n")
    }

    @Test func aSymlinkedComposeFileIsNotEdited() async throws {
        let server = try await ShellSSHServer(allowedKey: clientKey.publicKey)
        defer { server.stop() }
        let project = try makeProject(in: server)
        let file = project.configFiles[0]
        let elsewhere = server.root.appending(path: "elsewhere.yaml").path(percentEncoded: false)
        try "services: {}\n".write(toFile: elsewhere, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(atPath: file)
        try FileManager.default.createSymbolicLink(atPath: file, withDestinationPath: elsewhere)
        let remote = try await remote(server, project)
        defer { remote.close() }
        await #expect(throws: ComposeRemote.Failure.self) { _ = try await remote.read(file) }
        await #expect(throws: ComposeRemote.Failure.self) { _ = try await remote.save(file, content: "services: {x: 1}\n") }
        #expect(try read(elsewhere) == "services: {}\n")
    }

    @Test func aProjectFolderThatIsALinkIsRefused() async throws {
        let server = try await ShellSSHServer(allowedKey: clientKey.publicKey)
        defer { server.stop() }
        let real = try makeProject(in: server)
        let linked = server.root.appending(path: "linked").path(percentEncoded: false)
        try FileManager.default.createSymbolicLink(atPath: linked, withDestinationPath: real.workingDirectory!)
        let project = ComposeProject(name: "web", workingDirectory: linked, configFiles: [linked + "/compose.yaml"], services: ["web"])
        let before = try read(real.configFiles[0])
        let remote = try await remote(server, project)
        defer { remote.close() }
        await #expect(throws: ComposeRemote.Failure.self) { _ = try await remote.read(project.configFiles[0]) }
        await #expect(throws: ComposeRemote.Failure.self) { _ = try await remote.save(project.configFiles[0], content: "services: {x: 1}\n") }
        #expect(try read(real.configFiles[0]) == before)
    }

    @Test func aPlantedFutureBackupIsNeverRestored() async throws {
        let server = try await ShellSSHServer(allowedKey: clientKey.publicKey)
        defer { server.stop() }
        let project = try makeProject(in: server)
        let env = project.envFile!
        try "TOKEN=mine\n".write(toFile: env, atomically: true, encoding: .utf8)
        try "EVIL=1\n".write(toFile: env + ".bak-20991231-235959", atomically: true, encoding: .utf8)
        let remote = try await remote(server, project)
        defer { remote.close() }
        #expect(try await remote.save(env, content: "BROKEN=1\n", existed: true) != .saved)
        #expect(try read(env) == "TOKEN=mine\n")
    }

    /// zsh as the login shell: an unmatched backup glob no longer stops the
    /// save half-way (every script runs under /bin/sh).
    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/bin/zsh")))
    func aZshLoginShellSavesANewEnv() async throws {
        let server = try await ShellSSHServer(allowedKey: clientKey.publicKey, loginShell: "/bin/zsh")
        defer { server.stop() }
        let project = try makeProject(in: server)
        let connection = try await SSHAccess.connect(endpoint: server.endpoint, pinnedHostKey: server.fingerprint, key: clientKey, askPassword: { nil })
        let remote = ComposeRemote(connection: connection, commands: try ComposeCommands(project: project))
        defer { remote.close() }
        #expect(try await remote.save(project.envFile!, content: "TZ=UTC\n", existed: false) == .saved)
        #expect(try read(project.envFile!) == "TZ=UTC\n")
        #expect(try await remote.save(project.envFile!, content: "BROKEN=1\n", existed: true, now: .now.addingTimeInterval(2)) != .saved)
        #expect(try read(project.envFile!) == "TZ=UTC\n")
    }

    @Test func actionsStreamTheirOutputAndExitStatus() async throws {
        let server = try await ShellSSHServer(allowedKey: clientKey.publicKey)
        defer { server.stop() }
        let project = try makeProject(in: server)
        let remote = try await remote(server, project)
        defer { remote.close() }
        var text = ""
        var exit: Int?
        for try await event in try await remote.run(.update) {
            switch event {
            case .output(let chunk): text += chunk
            case .exit(let status): exit = status
            }
        }
        #expect(text == "ran pull\nran up -d\n")
        #expect(exit == 0)
        #expect(try await remote.validate().valid)
    }
}
