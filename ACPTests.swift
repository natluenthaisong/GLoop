import Foundation
import AVFoundation

/// A deterministic offline ACP peer for protocol/UI tests; never connects to a model or network.
func runACPFixture() {
    var promptID: Any?, rejectedPermission = false, rejectedFS = false
    func send(_ message: [String:Any]) {
        var bytes = try! JSONSerialization.data(withJSONObject:message); bytes.append(10)
        // Split every message, including UTF-8, to exercise framing across pipe reads.
        let cut = min(7,bytes.count)
        FileHandle.standardOutput.write(bytes.prefix(cut)); FileHandle.standardOutput.write(bytes.dropFirst(cut))
    }
    func respond(_ id:Any,_ result:[String:Any]) { send(["jsonrpc":"2.0","id":id,"result":result]) }
    while let line = readLine() {
        guard let message = try? JSONSerialization.jsonObject(with:Data(line.utf8)) as? [String:Any] else { exit(2) }
        let params = message["params"] as? [String:Any] ?? [:]
        switch message["method"] as? String {
        case "initialize":
            precondition((params["clientCapabilities"] as? [String:Any])?.isEmpty == true)
            respond(message["id"]!,["protocolVersion":ProcessInfo.processInfo.arguments.contains("--fixture-version") ? 2 : 1,"agentInfo":["name":"Offline test agent"],"agentCapabilities":["promptCapabilities":["audio":true]]])
        case "session/new":
            precondition((params["mcpServers"] as? [Any])?.isEmpty == true)
            respond(message["id"]!,["sessionId":"fixture-session"])
        case "session/prompt":
            let blocks = params["prompt"] as! [[String:Any]]
            precondition(blocks[0]["type"] as? String == "text")
            precondition(!(blocks[0]["text"] as! String).contains("/Users/"))
            if ProcessInfo.processInfo.arguments.contains("--fixture-invalid") { FileHandle.standardOutput.write(Data("not ACP\n".utf8)); continue }
            if ProcessInfo.processInfo.arguments.contains("--fixture-slow") { continue }
            if ProcessInfo.processInfo.arguments.contains("--fixture-large") { FileHandle.standardOutput.write(Data(repeating:65,count:1_048_577)); continue }
            promptID = message["id"]
            send(["jsonrpc":"2.0","id":"permission","method":"session/request_permission","params":["sessionId":"fixture-session","toolCall":["toolCallId":"t","title":"Test permission refusal"],"options":[["optionId":"yes","kind":"allow_once","name":"Allow"],["optionId":"no","kind":"reject_once","name":"Reject"]]]])
            send(["jsonrpc":"2.0","id":"fs","method":"fs/read_text_file","params":["sessionId":"fixture-session","path":"/not-a-real-file"]])
        case "session/cancel": exit(0)
        default:
            if message["id"] as? String == "permission" {
                let outcome = (message["result"] as? [String:Any])?["outcome"] as? [String:Any]
                precondition(outcome?["optionId"] as? String == "no"); rejectedPermission = true
            }
            if message["id"] as? String == "fs" { precondition((message["error"] as? [String:Any])?["code"] as? Int == -32601); rejectedFS = true }
            if rejectedPermission && rejectedFS, let id = promptID {
                let text = "Offline test suggestion for E♭.\n```gloop\n{\"start\":0.5,\"end\":1.5,\"reason\":\"Synthetic fixture range\"}\n```"
                for chunk in [String(text.prefix(37)),String(text.dropFirst(37))] { send(["jsonrpc":"2.0","method":"session/update","params":["sessionId":"fixture-session","update":["sessionUpdate":"agent_message_chunk","content":["type":"text","text":chunk]]]]) }
                respond(id,["stopReason":"end_turn"]); promptID = nil; rejectedPermission = false; rejectedFS = false
            }
        }
    }
}

func runACPTests() throws {
    func awaitResult<T>(_ work: (@escaping (Result<T,Error>)->Void)->Void) throws -> T {
        var result: Result<T,Error>?
        work { result = $0 }
        let deadline = Date().addingTimeInterval(15)
        while result == nil && Date() < deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.01)) }
        guard let result else { throw ACPFailure(message:"ACP test timed out") }; return try result.get()
    }
    func expectFailure(_ work: () throws -> Void) { do { try work(); preconditionFailure("Expected failure") } catch {} }
    let valid = "Explanation\n```gloop\n{\"start\":1,\"end\":3,\"reason\":\"phrase\"}\n```"
    let parsed = try TrimProposal.parse(valid,duration:4); precondition(parsed.start == 1)
    for text in ["No suggestion", "{\"start\":-1,\"end\":3,\"reason\":\"bad\"}","{\"start\":1,\"end\":8,\"reason\":\"bad\"}","{\"start\":1,\"end\":1.01,\"reason\":\"bad\"}",valid+"\n"+valid] {
        expectFailure { _ = try TrimProposal.parse(text,duration:4) }
    }
    let pcm = AVAudioPCMBuffer(pcmFormat:AVAudioFormat(standardFormatWithSampleRate:48000,channels:2)!,frameCapacity:96000)!
    pcm.frameLength = 96000
    for c in 0..<2 { for i in 0..<96000 { pcm.floatChannelData![c][i] = Float(sin(Double(i)*2*Double.pi*440/48000))*0.5 } }
    let wav = try TrimAudio.wav(pcm,a:0.5,b:1.5)
    precondition(wav.count == 96044 && String(data:wav.prefix(4),encoding:.utf8) == "RIFF")
    expectFailure { _ = try TrimAudio.wav(pcm,a:-1,b:1) }
    expectFailure { _ = try TrimAudio.wav(pcm,a:1,b:3) }
    let context = TrimContext(clipID:UUID(),duration:2,a:0.5,b:1.5,bpm:120,peaks:[0,0.5,0.2])
    let prompt = try context.prompt("Trim to one second",audio:false)
    precondition(prompt.contains("No audio or video is attached") && !prompt.contains("/Users/"))
    let binary = URL(fileURLWithPath:CommandLine.arguments[0]).standardizedFileURL.path
    let client = ACPClient(); var output = ""
    client.onText = { output += $0 }
    _ = try awaitResult { client.connect(executable:binary,arguments:["--acp-test-agent"],completion:$0) }
    precondition(client.connected && client.supportsAudio)
    let response = try awaitResult { client.ask(prompt:prompt,audio:nil,completion:$0) }
    precondition(response["stopReason"] as? String == "end_turn")
    let suggested = try TrimProposal.parse(output,duration:2); precondition(suggested.start == 0.5)
    output = ""
    _ = try awaitResult { client.ask(prompt:try! context.prompt("Trim audio",audio:true),audio:wav,completion:$0) }
    precondition(output.contains("E♭")); client.disconnect()
    for mode in ["--fixture-invalid","--fixture-large","--fixture-slow","--fixture-version"] {
        expectFailure {
            _ = try awaitResult { client.connect(executable:binary,arguments:["--acp-test-agent",mode],completion:$0) }
            client.requestTimeout = 0.15
            _ = try awaitResult { client.ask(prompt:prompt,audio:nil,completion:$0) }
        }
        client.disconnect()
    }
    _ = try awaitResult { client.connect(executable:binary,arguments:["--acp-test-agent","--fixture-slow"],completion:$0) }
    var cancelled = false
    client.ask(prompt:prompt,audio:nil) { result in if case .failure = result { cancelled = true } }
    var stopStatus: [String] = []; client.onDisconnect = { stopStatus.append($0) }
    client.cancel(); precondition(cancelled && !client.connected)
    RunLoop.current.run(until:Date().addingTimeInterval(0.4))
    precondition(stopStatus == ["Stopped. Reconnect to ask again."],"Normal cancellation must not become an agent error")
    print("PASS ACP: stdio framing, initialize/session/prompt, streamed text, audio, tool refusal, malformed/oversized replies, timeout, version mismatch, cancellation and proposal validation")
    if let i = CommandLine.arguments.firstIndex(of:"--export-test-file"), i+1 < CommandLine.arguments.count {
        let source = URL(fileURLWithPath:CommandLine.arguments[i+1]), original = try Data(contentsOf:source)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("GLoop-export-test-"+UUID().uuidString+".mp4")
        defer { try? FileManager.default.removeItem(at:destination) }
        let exporter = TrimExporter()
        _ = try awaitResult { exporter.export(source:source,destination:destination,a:0.5,b:1.5,completion:$0) }
        let duration = try NativeAudio.duration(destination)
        let afterSource = try Data(contentsOf:source); precondition(abs(duration-1) < 0.05 && afterSource == original)
        let copy = try Data(contentsOf:destination)
        expectFailure { _ = try awaitResult { exporter.export(source:source,destination:destination,a:0.7,b:1.2,completion:$0) } }
        let afterCopy = try Data(contentsOf:destination); precondition(afterCopy == copy)
        print("PASS trim export: one-second MP4, original retained, existing destination protected")
    }
}
