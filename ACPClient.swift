import Foundation
import Darwin

struct ACPFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// ACP v1 over newline-delimited JSON-RPC. All state and callbacks live on the main queue.
/// GLoop offers no filesystem or terminal capabilities, and rejects agent tool permissions.
final class ACPClient {
    typealias Reply = (Result<[String:Any],Error>) -> Void
    var onText: ((String) -> Void)?
    var onStatus: ((String) -> Void)?
    var onDisconnect: ((String) -> Void)?
    private(set) var connected = false
    private(set) var supportsAudio = false
    private(set) var agentName = "Agent"
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var errors: FileHandle?
    private var workspace: URL?
    private var generation = UUID()
    private var cancelling = false
    private var nextID = 0
    private var pending: [Int:(Reply,DispatchWorkItem)] = [:]
    private var session: String?
    private var receivedText = 0
    private var frame = Data()
    private let writer = DispatchQueue(label: "GLoop.ACP.write")
    var requestTimeout: Double = 120

    func connect(executable: String, arguments: [String], completion: @escaping Reply) {
        disconnect()
        guard executable.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: executable), arguments.count <= 64,
              arguments.allSatisfy({ !$0.contains("\0") && $0.utf8.count <= 4096 }) else {
            completion(.failure(ACPFailure(message: "Choose an executable ACP agent and valid arguments."))); return
        }
        signal(SIGPIPE,SIG_IGN)
        let token = UUID(); generation = token
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("GLoop-ACP-"+UUID().uuidString)
        do { try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true,attributes: [.posixPermissions:0o700]) }
        catch { completion(.failure(error)); return }
        workspace = folder
        let task = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        task.executableURL = URL(fileURLWithPath: executable); task.arguments = arguments; task.currentDirectoryURL = folder
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:"+(environment["PATH"] ?? "/usr/bin:/bin")
        task.environment = environment
        task.standardInput = stdin; task.standardOutput = stdout; task.standardError = stderr
        process = task; input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading; errors = stderr.fileHandleForReading
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                if data.isEmpty { self.fail("The agent closed its connection. Reconnect to try again.") }
                else { self.receive(data) }
            }
        }
        // Drain stderr without storing diagnostics that may contain credentials or private paths.
        stderr.fileHandleForReading.readabilityHandler = { handle in if handle.availableData.isEmpty { handle.readabilityHandler = nil } }
        task.terminationHandler = { [weak self] task in DispatchQueue.main.async {
            guard let self, self.generation == token else { return }
            self.fail("The agent exited (status \(task.terminationStatus)). Check its ACP arguments and sign-in, then reconnect.")
        } }
        do { try task.run() }
        catch { fail("Could not launch the agent: \(error.localizedDescription)"); completion(.failure(error)); return }
        request("initialize",params: ["protocolVersion":1,"clientCapabilities":[:],"clientInfo":["name":"gloop","title":"GLoop","version":"3.4.0"]],timeout: 20) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure: completion(result)
            case .success(let value):
                guard (value["protocolVersion"] as? Int) == 1 else {
                    self.fail("This agent does not support ACP v1."); completion(.failure(ACPFailure(message:"This agent does not support ACP v1."))); return
                }
                self.connected = true
                let capabilities = value["agentCapabilities"] as? [String:Any]
                self.supportsAudio = (capabilities?["promptCapabilities"] as? [String:Any])?["audio"] as? Bool == true
                self.agentName = String(((value["agentInfo"] as? [String:Any])?["title"] as? String ?? (value["agentInfo"] as? [String:Any])?["name"] as? String ?? "Agent").prefix(80))
                completion(result)
            }
        }
    }

    func ask(prompt: String, audio: Data?, completion: @escaping Reply) {
        guard connected, pending.isEmpty, let workspace else { completion(.failure(ACPFailure(message:"Connect an agent before asking."))); return }
        guard audio == nil || supportsAudio else { completion(.failure(ACPFailure(message:"This agent does not accept audio. Turn off Share loop audio, or connect an audio-capable agent."))); return }
        receivedText = 0; session = nil
        // A new session per request prevents context leaking between clips or changed selections.
        request("session/new",params:["cwd":workspace.path,"mcpServers":[]]) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure: completion(result)
            case .success(let value):
                guard let id = value["sessionId"] as? String, !id.isEmpty else { completion(.failure(ACPFailure(message:"The agent did not return a session ID."))); return }
                self.session = id
                var blocks: [[String:Any]] = [["type":"text","text":prompt]]
                if let audio { blocks.append(["type":"audio","mimeType":"audio/wav","data":audio.base64EncodedString()]) }
                self.request("session/prompt",params:["sessionId":id,"prompt":blocks],completion: completion)
            }
        }
    }

    func disconnect() { close(reason: "Disconnected.",notify: false) }
    func cancel() {
        cancelling = true
        if let session { send(["jsonrpc":"2.0","method":"session/cancel","params":["sessionId":session]]) }
        // Give the notification a brief chance to reach the peer, then close even if it ignores it.
        let token = generation
        connected = false
        let callbacks = pending.values.map { $0 }; pending.removeAll()
        for (callback,timer) in callbacks { timer.cancel(); callback(.failure(ACPFailure(message:"Stopped."))) }
        onDisconnect?("Stopped. Reconnect to ask again.")
        DispatchQueue.main.asyncAfter(deadline:.now()+0.25) { [weak self] in
            guard self?.generation == token else { return }
            self?.close(reason:"Stopped.",notify:false)
        }
    }
    private func request(_ method: String,params: [String:Any],timeout: Double? = nil,completion: @escaping Reply) {
        nextID += 1; let id = nextID
        let timer = DispatchWorkItem { [weak self] in self?.fail("The agent timed out. Reconnect to try again.") }
        pending[id] = (completion,timer)
        DispatchQueue.main.asyncAfter(deadline: .now()+(timeout ?? requestTimeout),execute: timer)
        send(["jsonrpc":"2.0","id":id,"method":method,"params":params])
    }
    private func send(_ message: [String:Any]) {
        guard let input, let bytes = try? JSONSerialization.data(withJSONObject: message), bytes.count <= 12_000_000 else { fail("The agent message is too large or the connection is closed."); return }
        var data = bytes; data.append(10)
        let token = generation
        writer.async { [weak self] in
            do { try input.write(contentsOf: data) }
            catch { DispatchQueue.main.async { if self?.generation == token { self?.fail("Could not write to the agent. Reconnect to try again.") } } }
        }
    }
    private func receive(_ data: Data) {
        frame.append(data)
        while let newline = frame.firstIndex(of: 10) {
            guard newline <= 1_048_576 else { fail("The agent sent an oversized message."); return }
            let line = Data(frame[..<newline]); frame.removeSubrange(...newline)
            if line.isEmpty { continue }
            guard let message = try? JSONSerialization.jsonObject(with: line) as? [String:Any], message["jsonrpc"] as? String == "2.0" else { fail("The agent sent invalid ACP data. Check that it is running in ACP mode."); return }
            handle(message)
            if process == nil { return }
        }
        if frame.count > 1_048_576 { fail("The agent sent an oversized message.") }
    }
    private func handle(_ message: [String:Any]) {
        if let method = message["method"] as? String {
            let params = message["params"] as? [String:Any] ?? [:]
            if let id = message["id"] {
                if method == "session/request_permission" {
                    let options = params["options"] as? [[String:Any]] ?? []
                    let rejection = options.first { $0["kind"] as? String == "reject_once" }
                    let outcome: [String:Any] = rejection?["optionId"].map { ["outcome":"selected","optionId":$0] } ?? ["outcome":"cancelled"]
                    send(["jsonrpc":"2.0","id":id,"result":["outcome":outcome]])
                    onStatus?("Agent tool access was declined. Trim suggestions use only the shared context.")
                } else { send(["jsonrpc":"2.0","id":id,"error":["code":-32601,"message":"GLoop does not provide filesystem, terminal, or other tool access."]]) }
                return
            }
            guard method == "session/update", params["sessionId"] as? String == session,
                  let update = params["update"] as? [String:Any], update["sessionUpdate"] as? String == "agent_message_chunk",
                  let content = update["content"] as? [String:Any], content["type"] as? String == "text", let text = content["text"] as? String else { return }
            receivedText += text.utf8.count
            guard receivedText <= 65_536 else { fail("The agent reply was too long. Ask for one short trim suggestion."); return }
            onText?(text)
        } else if let id = message["id"] as? Int, let (completion,timer) = pending.removeValue(forKey:id) {
            timer.cancel()
            if let error = message["error"] as? [String:Any] {
                if (error["code"] as? Int) == -32000 { completion(.failure(ACPFailure(message:"Sign in to this agent using its own app or CLI, then reconnect."))) }
                else { completion(.failure(ACPFailure(message:String((error["message"] as? String ?? "Agent request failed.").prefix(500))))) }
            } else if let result = message["result"] as? [String:Any] { completion(.success(result)) }
            else { completion(.failure(ACPFailure(message:"The agent returned an invalid response."))) }
        }
    }
    private func fail(_ reason: String) { close(reason: cancelling ? "Stopped." : reason,notify: !cancelling) }
    private func close(reason: String,notify: Bool) {
        generation = UUID(); cancelling = false; connected = false; supportsAudio = false; session = nil; frame = Data()
        let old = process; process = nil
        output?.readabilityHandler = nil; errors?.readabilityHandler = nil
        try? input?.close(); input = nil; try? output?.close(); output = nil; try? errors?.close(); errors = nil
        old?.terminationHandler = nil
        if let old, old.isRunning {
            old.terminate()
            DispatchQueue.global().asyncAfter(deadline:.now()+2) { if old.isRunning { kill(old.processIdentifier,SIGKILL) } }
        }
        let callbacks = pending.values.map { $0 }; pending.removeAll()
        for (callback,timer) in callbacks { timer.cancel(); callback(.failure(ACPFailure(message:reason))) }
        // Only the private empty workspace created by this client is removed; source clips never enter it.
        if let workspace { try? FileManager.default.removeItem(at:workspace) }; workspace = nil
        if notify { onDisconnect?(reason) }
    }
}
