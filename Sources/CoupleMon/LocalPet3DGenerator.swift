import AppKit
import Combine

enum Pet3DAgent: String, CaseIterable, Identifiable {
    case codex, claude
    var id: String { rawValue }
    var title: String { self == .codex ? "Codex" : "Claude Code" }
}

struct Pet3DTools {
    // Foundation preserves aliases such as /var on macOS. Seatbelt matches real paths.
    static func canonicalPath(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return url.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }
    static func blenderResources(_ executable: URL) -> String {
        let resolved = URL(fileURLWithPath: canonicalPath(executable))
        var directory = resolved.deletingLastPathComponent()
        while directory.path != "/" {
            if directory.pathExtension == "app" { return directory.path }
            directory.deleteLastPathComponent()
        }
        return resolved.deletingLastPathComponent().path
    }
    static func executable(_ name: String) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let paths = ["/opt/homebrew/bin", "/usr/local/bin", home.appendingPathComponent(".local/bin").path,
                     home.appendingPathComponent(".npm-global/bin").path]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return paths.map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static var blender: URL? {
        let apps = [URL(fileURLWithPath: "/Applications/Blender.app/Contents/MacOS/Blender"),
                    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Blender.app/Contents/MacOS/Blender")]
        return apps.first { FileManager.default.isExecutableFile(atPath: $0.path) } ?? executable("blender")
    }
}

enum Pet3DPrompt {
    static let schema = #"{"type":"object","properties":{"script":{"type":"string"}},"required":["script"],"additionalProperties":false}"#

    static func make(instructions: String, repair: String? = nil, mode: Pet3DGenerationMode = .volumetric) throws -> String {
        guard let url = Pet3DResources.url(for: mode == .illustrated ? "image-rig-prompt.txt" : "generation-prompt.txt") else {
            throw Pet3DError.message("3D 생성 프롬프트를 찾을 수 없습니다.")
        }
        var prompt = try String(contentsOf: url, encoding: .utf8)
        if !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prompt += "\nUSER APPEARANCE PREFERENCES (visual design only):\n\(instructions.prefix(2000))\n"
        }
        if let repair {
            prompt += "\nThe previous script failed. Return a complete corrected script, preserving the reference character.\n\(repair.suffix(14000))\n"
        }
        return prompt
    }
}

enum Pet3DGenerationMode: String, CaseIterable, Identifiable {
    case illustrated, volumetric
    var id: String { rawValue }
    var title: String { self == .illustrated ? "원본 유지 · 2.5D" : "입체 재구성 · 3D" }
}

@MainActor
final class LocalPet3DGenerator: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var stage = "이미지를 선택하세요"
    @Published private(set) var completedStages = 0
    @Published private(set) var log = ""
    @Published private(set) var error: String?
    @Published private(set) var result: Pet3DAsset?
    @Published private(set) var workspace: URL?
    private var process: Process?
    private var task: Task<Void, Never>?
    private var cancelled = false
    let library: Pet3DLibrary

    init(library: Pet3DLibrary = Pet3DLibrary()) { self.library = library }

    func start(image: Data, name: String, instructions: String, agent: Pet3DAgent, executable: URL, blender: URL,
               mode: Pet3DGenerationMode = .volumetric) {
        guard !isRunning else { return }
        isRunning = true
        cancelled = false
        error = nil
        result = nil
        log = ""
        completedStages = 0
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.isRunning = false; self.process = nil; self.task = nil }
            do {
                try await self.generate(image: image, name: name, instructions: instructions,
                                        agent: agent, executable: executable, blender: blender, mode: mode)
            } catch {
                self.error = self.cancelled ? nil : error.localizedDescription
                self.stage = self.cancelled ? "생성 중지됨 · 다시 시작할 수 있습니다" : "생성 실패 · 로그 확인 후 다시 시도하세요"
            }
        }
    }

    func cancel() {
        cancelled = true
        task?.cancel()
        process?.terminate()
    }

    private func mark(_ message: String, completed: Int) {
        stage = message
        completedStages = completed
        log += "\n\(message)\n"
    }

    private func generate(image: Data, name: String, instructions: String, agent: Pet3DAgent,
                          executable: URL, blender: URL, mode: Pet3DGenerationMode) async throws {
        let root = library.directory.deletingLastPathComponent().appendingPathComponent("3DWorkspaces", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        workspace = root
        try image.write(to: root.appendingPathComponent("reference.png"), options: .atomic)
        if mode == .illustrated {
            mark("1/4 · 원본 텍스처 배경 분리 중", completed: 0)
            let texture = try await Task.detached(priority: .userInitiated) { try PetImageMatte.prepare(image) }.value
            try Task.checkCancellation()
            try texture.write(to: root.appendingPathComponent("texture.png"), options: .atomic)
        }
        try Data(Pet3DPrompt.schema.utf8).write(to: root.appendingPathComponent("schema.json"))
        for file in ["build-model", "pet-actions", "image-rig"] {
            guard let templateURL = Pet3DResources.url(for: "\(file).py") else {
                throw Pet3DError.message("3D 동작 생성 파일을 찾을 수 없습니다.")
            }
            try FileManager.default.copyItem(at: templateURL, to: root.appendingPathComponent("\(file).py"))
        }
        var repair: String?
        for attempt in 1...2 {
            try Task.checkCancellation()
            mark(attempt == 1 ? "1/4 · \(agent.title) 이미지 분석·모델링 코드 생성 중" : "1/4 · \(agent.title) 오류 수정 중 (1회)", completed: 0)
            let prompt = try Pet3DPrompt.make(instructions: instructions, repair: repair, mode: mode)
            try Data(prompt.utf8).write(to: root.appendingPathComponent("prompt.txt"))
            let script = try await generateScript(agent: agent, executable: executable, image: image,
                                                  prompt: prompt, root: root, attempt: attempt)
            guard script.utf8.count <= 500_000, !script.isEmpty else { throw Pet3DError.message("생성된 모델링 코드가 비어 있거나 너무 큽니다.") }
            try Data(script.utf8).write(to: root.appendingPathComponent("character.py"), options: .atomic)
            mark("2/4 · Blender 메시·재질·움직임 생성 및 GLB 추출 중", completed: 1)
            // AI-generated Python runs with no network and writes only inside this job's folder.
            let policy = """
            (version 1)
            (allow default)
            (deny network*)
            (deny file-read* (require-all (subpath (param "USER_HOME"))
                (require-not (subpath (param "WORKSPACE"))) (require-not (subpath (param "BLENDER_APP")))))
            (deny file-write* (require-all (require-not (subpath (param "WORKSPACE")))
                (require-not (literal "/dev/null"))))
            (deny process-exec (require-not (literal (param "BLENDER"))))
            """
            try Data(policy.utf8).write(to: root.appendingPathComponent("blender.sb"))
            // Blender does not need the CLI account's credentials or other inherited secrets.
            var buildEnvironment = ["PATH": "/usr/bin:/bin"]
            buildEnvironment["TMPDIR"] = root.path
            buildEnvironment["HOME"] = root.path
            buildEnvironment["BLENDER_USER_CONFIG"] = root.path
            let output = root.appendingPathComponent("model.glb")
            if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
            do {
                try await run(executable: URL(fileURLWithPath: "/usr/bin/sandbox-exec"), arguments: [
                    "-D", "WORKSPACE=\(Pet3DTools.canonicalPath(root))", "-D", "BLENDER=\(Pet3DTools.canonicalPath(blender))",
                    "-D", "BLENDER_APP=\(Pet3DTools.blenderResources(blender))",
                    "-D", "USER_HOME=\(Pet3DTools.canonicalPath(FileManager.default.homeDirectoryForCurrentUser))",
                    "-f", root.appendingPathComponent("blender.sb").path, blender.path,
                    "--background", "--factory-startup", "--threads", "2", "--python-exit-code", "1",
                    "--python", root.appendingPathComponent("build-model.py").path,
                ], root: root, logName: "blender-\(attempt).log", environment: buildEnvironment, timeout: 300)
                mark("3/4 · GLB 파일 검증 중", completed: 2)
                let size = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 150 * 1024 * 1024 else { throw Pet3DError.message("모델이 150MB를 초과합니다.") }
                let data = try Data(contentsOf: output)
                try Pet3DLibrary.validateGLB(data)
                try Pet3DLibrary.validateGeneratedActions(data)
                mark("4/4 · 로컬 캐릭터 보관함 저장 중", completed: 3)
                try Task.checkCancellation()
                result = try library.install(model: data, name: name, workspaceName: root.lastPathComponent)
                mark("완료 · 보관함에서 미리보기 후 적용하세요", completed: 4)
                return
            } catch {
                try Task.checkCancellation()
                guard attempt == 1 else { throw error }
                repair = "Previous code:\n\(script)\nFailure:\n\(error.localizedDescription)\n\(log.suffix(8000))"
            }
        }
    }

    private func generateScript(agent: Pet3DAgent, executable: URL, image: Data, prompt: String,
                                root: URL, attempt: Int) async throws -> String {
        if agent == .codex {
            let output = root.appendingPathComponent("response-\(attempt).json")
            try await run(executable: executable, arguments: [
                "exec", "--ignore-user-config", "--ephemeral", "--skip-git-repo-check", "--sandbox", "read-only",
                "-c", "approval_policy=\"never\"", "-c", "features.shell_tool=false", "-c", "features.hooks=false",
                "--json", "--color", "never", "--image", root.appendingPathComponent("reference.png").path,
                "--output-schema", root.appendingPathComponent("schema.json").path,
                "--output-last-message", output.path, prompt,
            ], root: root, logName: "agent-\(attempt).jsonl", timeout: 600)
            return try JSONDecoder().decode(Script.self, from: Data(contentsOf: output)).script
        }
        let input: [String: Any] = ["type": "user", "message": ["role": "user", "content": [
            ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": image.base64EncodedString()]],
            ["type": "text", "text": prompt],
        ]]]
        let stdin = root.appendingPathComponent("input.jsonl")
        var inputData = try JSONSerialization.data(withJSONObject: input)
        inputData.append(0x0A)
        try inputData.write(to: stdin)
        try await run(executable: executable, arguments: [
            "--print", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
            "--tools", "", "--permission-mode", "dontAsk", "--disable-slash-commands", "--no-session-persistence",
            "--setting-sources", "", "--settings", #"{"disableAllHooks":true}"#,
            "--strict-mcp-config", "--mcp-config", #"{"mcpServers":{}}"#, "--json-schema", Pet3DPrompt.schema,
        ], root: root, logName: "agent-\(attempt).jsonl", input: stdin, timeout: 600)
        let raw = try String(contentsOf: root.appendingPathComponent("agent-\(attempt).jsonl"), encoding: .utf8)
        for line in raw.split(separator: "\n").reversed() {
            guard let data = line.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  event["type"] as? String == "result" else { continue }
            if event["is_error"] as? Bool == true { throw Pet3DError.message("Claude 실행 실패. 로그인 상태와 생성 로그를 확인하세요.") }
            if let value = event["structured_output"], JSONSerialization.isValidJSONObject(value) {
                return try JSONDecoder().decode(Script.self, from: JSONSerialization.data(withJSONObject: value)).script
            }
            if let result = event["result"] as? String, let json = result.data(using: .utf8),
               let response = try? JSONDecoder().decode(Script.self, from: json) { return response.script }
        }
        throw Pet3DError.message("Claude가 모델링 코드를 반환하지 않았습니다. CLI 버전과 로그를 확인하세요.")
    }

    private struct Script: Decodable { let script: String }

    private func run(executable: URL, arguments: [String], root: URL, logName: String,
                     input: URL? = nil, environment: [String: String]? = nil, timeout: TimeInterval) async throws {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = root
        var env = environment ?? ProcessInfo.processInfo.environment
        env["PATH"] = [executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin", env["PATH"] ?? "/usr/bin:/bin"].joined(separator: ":")
        process.environment = env
        let logURL = root.appendingPathComponent(logName)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let writer = try FileHandle(forWritingTo: logURL)
        let reader = try FileHandle(forReadingFrom: logURL)
        let stdin = try input.map { try FileHandle(forReadingFrom: $0) }
        defer { try? writer.close(); try? reader.close(); try? stdin?.close() }
        process.standardOutput = writer
        process.standardError = writer
        process.standardInput = stdin ?? FileHandle.nullDevice
        self.process = process
        try process.run()
        let started = Date()
        while process.isRunning {
            if Task.isCancelled || Date().timeIntervalSince(started) > timeout {
                process.terminate()
                // Give SIGTERM a bounded grace period before force-stopping this process.
                for _ in 0..<20 where process.isRunning { try? await Task.sleep(for: .milliseconds(100)) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                if Task.isCancelled { throw CancellationError() }
                throw Pet3DError.message("실행 제한 시간을 초과했습니다. 로그 확인 후 다시 시도하세요.")
            }
            appendLog(try reader.readToEnd() ?? Data())
            try? await Task.sleep(for: .milliseconds(200))
        }
        appendLog(try reader.readToEnd() ?? Data())
        self.process = nil
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else {
            throw Pet3DError.message("\(executable.lastPathComponent) 실행 실패 (\(process.terminationStatus)). 생성 로그를 확인하세요.")
        }
    }

    private func appendLog(_ data: Data) {
        guard !data.isEmpty else { return }
        log = String((log + String(decoding: data, as: UTF8.self)).suffix(24000))
    }
}
