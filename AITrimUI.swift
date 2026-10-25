import AppKit
import UniformTypeIdentifiers

final class AITrimWindow: NSWindowController, NSWindowDelegate {
    weak var app: PlayerApp?
    let client = ACPClient()
    let exporter = TrimExporter()
    let executable = NSTextField(string: "")
    let arguments = NSTextField(string: "[]")
    let connection = NSTextField(wrappingLabelWithString: "Choose an installed ACP agent, then connect. Sign in through the agent’s own app or CLI first.")
    let clipLabel = NSTextField(wrappingLabelWithString: "")
    let sharing = NSButton(checkboxWithTitle:"Share loop audio (up to 60 seconds)",target:nil,action:nil)
    let request = NSTextField(string: "")
    let reply = NSTextView()
    let resultLabel = NSTextField(wrappingLabelWithString:"No suggestion yet.")
    let notice = NSTextField(wrappingLabelWithString:"")
    var connectButton = NSButton(), chooseButton = NSButton(), askButton = NSButton(), stopButton = NSButton()
    var useButton = NSButton(), undoButton = NSButton(), exportButton = NSButton()
    var busy = false, connecting = false, exporting = false
    var token = UUID()
    var replyText = ""
    var proposed: (TrimContext,TrimProposal)?
    var undoRange: (UUID,Double,Double?,Bool,TrimProposal)?
    init(app: PlayerApp) {
        self.app = app
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:700,height:720),styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false)
        super.init(window:window)
        window.title = "AI Trim"; window.minSize = NSSize(width:620,height:690); window.isReleasedWhenClosed = false; window.delegate = self
        let root = StudioSurface(GLoopTheme.canvas); window.contentView = root
        executable.placeholderString = "Path to an installed ACP agent"; executable.setAccessibilityLabel("ACP agent executable")
        arguments.placeholderString = "[\"--acp\"]"; arguments.setAccessibilityLabel("ACP arguments as a JSON array")
        arguments.toolTip = "A JSON list of arguments, for example [\"--acp\"]. GLoop launches the executable directly, without a shell. Do not enter API keys here."
        if !app.uiTest { executable.stringValue = UserDefaults.standard.string(forKey:"acpExecutable") ?? ""; arguments.stringValue = UserDefaults.standard.string(forKey:"acpArguments") ?? "[]" }
        if app.uiTest && ProcessInfo.processInfo.arguments.contains("--acp-ui-test") { executable.stringValue = Bundle.main.executablePath ?? ""; arguments.stringValue = "[\"--acp-test-agent\"]" }
        chooseButton = button("Choose…",#selector(chooseAgent)); connectButton = button("Connect",#selector(connectAgent))
        askButton = button("Ask",#selector(ask)); stopButton = button("Stop",#selector(stop))
        useButton = button("Use loop",#selector(useLoop)); undoButton = button("Undo loop change",#selector(undoLoop))
        exportButton = button("Export current loop…",#selector(exportLoop))
        request.placeholderString = "e.g. Remove silence at the beginning and end"; request.setAccessibilityLabel("Trim request")
        request.target = self; request.action = #selector(ask)
        sharing.target = self; sharing.action = #selector(sharingChanged)
        sharing.toolTip = "Sends the current A/B range at its original speed and pitch. Audio is off by default and requires an audio-capable agent."
        let privacy = NSTextField(wrappingLabelWithString:"Ask sends your request, loop times, BPM and waveform summary. Optional audio goes to the connected agent, which may use a cloud provider. Video, file paths, library and practice history are not sent.")
        let trust = NSTextField(wrappingLabelWithString:"Only connect an agent you trust: it runs with your Mac account’s permissions. GLoop does not grant file or terminal access through ACP.")
        for field in [privacy,trust,connection,notice] { field.font = .systemFont(ofSize:12); field.textColor = GLoopTheme.muted }
        clipLabel.font = .systemFont(ofSize:14,weight:.semibold)
        resultLabel.font = .monospacedDigitSystemFont(ofSize:13,weight:.medium)
        reply.isEditable = false; reply.isSelectable = true; reply.isRichText = false; reply.font = .systemFont(ofSize:13)
        reply.backgroundColor = .textBackgroundColor; reply.textColor = .textColor; reply.textContainerInset = NSSize(width:10,height:10)
        reply.isHorizontallyResizable = false; reply.autoresizingMask = [.width]; reply.textContainer?.widthTracksTextView = true
        reply.setAccessibilityLabel("Agent response")
        let scroll = NSScrollView(); scroll.documentView = reply; scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:140).isActive = true
        let settings = app.col([app.row([executable,chooseButton,connectButton],spacing:8),app.row([app.muted("Arguments (JSON)"),arguments],spacing:8),connection,trust],spacing:8)
        let send = app.row([request,askButton,stopButton],spacing:8)
        request.setContentHuggingPriority(.init(1),for:.horizontal); executable.setContentHuggingPriority(.init(1),for:.horizontal); arguments.setContentHuggingPriority(.init(1),for:.horizontal)
        let actions = app.row([useButton,undoButton,app.flexible(),exportButton],spacing:8)
        let stack = app.col([settings,NSBox.separator(),clipLabel,privacy,sharing,send,scroll,resultLabel,actions,notice],spacing:12)
        stack.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(stack)
        for view in stack.arrangedSubviews { view.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo:root.topAnchor,constant:20),stack.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-20),stack.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:20),stack.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-20)])
        client.onText = { [weak self] text in guard let self, self.busy else { return }; self.replyText += text; self.reply.string = self.visibleReply; self.reply.scrollToEndOfDocument(nil) }
        client.onStatus = { [weak self] text in self?.notice.stringValue = text }
        client.onDisconnect = { [weak self] text in
            guard let self else { return }; self.token = UUID(); self.busy = false; self.connecting = false; self.connection.stringValue = text; self.refresh()
        }
        refresh(); window.center()
    }
    required init?(coder:NSCoder) { fatalError() }
    private func button(_ title:String,_ action:Selector)->NSButton { let b = NSButton(title:title,target:self,action:action); b.bezelStyle = .rounded; return b }
    func refresh() {
        guard let app else { return }
        if let clip = app.selected { clipLabel.stringValue = "\(clip.title)\nCurrent loop: \(stamp(app.prefs.a,precise:true))–\(stamp(app.prefs.b ?? app.duration,precise:true))" }
        else { clipLabel.stringValue = "Open a video in GLoop to ask for a trim." }
        let idle = !busy && !connecting
        executable.isEnabled = !client.connected && idle; arguments.isEnabled = executable.isEnabled; chooseButton.isEnabled = executable.isEnabled
        connectButton.title = client.connected ? "Disconnect" : "Connect"; connectButton.isEnabled = idle
        askButton.isEnabled = client.connected && idle && app.selected != nil && app.smooth.ready
        request.isEnabled = idle; stopButton.isEnabled = busy || connecting || exporting
        sharing.isEnabled = client.connected && client.supportsAudio && idle && app.smooth.ready
        useButton.isEnabled = idle && proposed?.0.clipID == app.audioRequest
        undoButton.isEnabled = idle && undoRange?.0 == app.audioRequest
        exportButton.isEnabled = !exporting && app.selected != nil && app.duration > 0
    }
    private var visibleReply: String {
        let prose = (replyText.components(separatedBy:"```").first ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
        return prose.hasPrefix("{") ? "" : prose
    }
    @objc func chooseAgent() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false; panel.message = "Choose the installed ACP executable."
        panel.beginSheetModal(for:window!) { [weak self] response in if response == .OK, let url = panel.url { self?.executable.stringValue = url.path } }
    }
    @objc func connectAgent() {
        sharing.state = .off
        if client.connected { token = UUID(); client.disconnect(); proposed = nil; connection.stringValue = "Disconnected."; refresh(); return }
        guard let data = arguments.stringValue.data(using:.utf8), let args = try? JSONDecoder().decode([String].self,from:data) else { connection.stringValue = "Arguments must be a JSON list, for example [\"--acp\"]."; return }
        connecting = true; connection.stringValue = "Connecting…"; refresh()
        client.connect(executable:executable.stringValue.trimmingCharacters(in:.whitespacesAndNewlines),arguments:args) { [weak self] result in
            guard let self else { return }; self.connecting = false
            switch result {
            case .success:
                self.connection.stringValue = "Connected to \(self.client.agentName). \(self.client.supportsAudio ? "Audio sharing is available." : "Text and waveform summary only; this agent does not accept audio.")"
                if self.app?.uiTest != true { UserDefaults.standard.set(self.executable.stringValue,forKey:"acpExecutable"); UserDefaults.standard.set(self.arguments.stringValue,forKey:"acpArguments") }
            case .failure(let error): self.connection.stringValue = error.localizedDescription
            }
            self.refresh()
        }
    }
    @objc func sharingChanged() { notice.stringValue = sharing.state == .on ? "The next request will include the current loop’s original audio." : "Audio will not be attached." }
    @objc func ask() {
        guard let app, !busy, !connecting, client.connected, let pcm = app.smooth.buffer, app.selected != nil else { return }
        let question = request.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !question.isEmpty, question.utf8.count <= 8192 else { notice.stringValue = "Enter a request of up to 8,192 bytes."; return }
        let context = TrimContext(clipID:app.audioRequest,duration:app.duration,a:app.prefs.a,b:app.prefs.b ?? app.duration,bpm:app.prefs.bpm,peaks:app.waveform.aiSummary())
        let audio = sharing.state == .on
        guard !audio || (client.supportsAudio && context.b-context.a <= 60) else { notice.stringValue = "For audio sharing, select a loop up to 60 seconds and connect an audio-capable agent."; return }
        token = UUID(); let current = token
        busy = true; proposed = nil; replyText = ""; reply.string = ""; resultLabel.stringValue = "Waiting for a suggestion…"; notice.stringValue = audio ? "Preparing loop audio…" : "Sending timing and waveform summary…"; refresh()
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            let prepared = Result { (try context.prompt(question,audio:audio),try audio ? TrimAudio.wav(pcm,a:context.a,b:context.b) : nil) }
            DispatchQueue.main.async {
                guard let self, self.token == current, self.app?.audioRequest == context.clipID else { return }
                switch prepared {
                case .failure(let error): self.finish(.failure(error),context:context)
                case .success(let (prompt,data)):
                    self.notice.stringValue = "Asking \(self.client.agentName)…"
                    self.client.ask(prompt:prompt,audio:data) { [weak self] result in
                        guard let self, self.token == current, self.app?.audioRequest == context.clipID else { return }
                        self.finish(result,context:context)
                    }
                }
            }
        }
    }
    private func finish(_ result:Result<[String:Any],Error>,context:TrimContext) {
        busy = false
        switch result {
        case .failure(let error): resultLabel.stringValue = "No loop changed."; notice.stringValue = error.localizedDescription
        case .success(let result):
            guard result["stopReason"] as? String == "end_turn" else { resultLabel.stringValue = "No loop changed."; notice.stringValue = "The agent did not finish its reply. Try a shorter request."; refresh(); return }
            do {
                let proposal = try TrimProposal.parse(replyText,duration:context.duration)
                reply.string = visibleReply.isEmpty ? proposal.reason : visibleReply + (visibleReply.contains(proposal.reason) ? "" : "\n\n"+proposal.reason)
                proposed = (context,proposal); resultLabel.stringValue = "Suggested loop: \(stamp(proposal.start,precise:true))–\(stamp(proposal.end,precise:true))"
                notice.stringValue = "Use loop applies these markers. Listen in GLoop before exporting."
            } catch { resultLabel.stringValue = "No loop changed."; notice.stringValue = error.localizedDescription }
        }
        refresh()
    }
    @objc func stop() { token = UUID(); busy = false; connecting = false; proposed = nil; client.cancel(); if exporting { exporter.cancel() }; resultLabel.stringValue = "No loop changed."; notice.stringValue = "Stopped. Reconnect to ask again."; refresh() }
    func clipDidChange() {
        token = UUID(); if busy || connecting { client.cancel() }; busy = false; connecting = false; proposed = nil; undoRange = nil; sharing.state = .off
        replyText = ""; reply.string = ""; resultLabel.stringValue = "No suggestion yet."; notice.stringValue = ""; refresh()
    }
    @objc func useLoop() {
        guard let app, let (context,proposal) = proposed, context.clipID == app.audioRequest else { notice.stringValue = "This suggestion belongs to another clip. Ask again."; return }
        do { try proposal.validate(duration:app.duration) } catch { notice.stringValue = error.localizedDescription; return }
        undoRange = (app.audioRequest,app.prefs.a,app.prefs.b,app.prefs.looping,proposal)
        app.prefs.a = proposal.start; app.prefs.b = proposal.end; app.prefs.looping = true; app.markersChanged()
        proposed = nil; notice.stringValue = "Loop applied. Press Play in GLoop to listen; the source video is unchanged."; refresh()
    }
    @objc func undoLoop() {
        guard let app, let old = undoRange, old.0 == app.audioRequest else { return }
        guard app.prefs.a == old.4.start && app.prefs.b == old.4.end else { undoRange = nil; notice.stringValue = "The loop was edited after applying this suggestion. Your newer markers were kept."; refresh(); return }
        app.prefs.a = old.1; app.prefs.b = old.2; app.prefs.looping = old.3; app.markersChanged(); undoRange = nil
        notice.stringValue = "Previous loop restored."; refresh()
    }
    @objc func exportLoop() {
        guard let app, let clip = app.selected, !exporting else { return }
        let a = app.prefs.a,b = app.prefs.b ?? app.duration
        let panel = NSSavePanel(); panel.allowedContentTypes = [.mpeg4Movie]; panel.nameFieldStringValue = URL(fileURLWithPath:clip.path).deletingPathExtension().lastPathComponent+" - trim.mp4"
        panel.message = "Export \(stamp(a,precise:true))–\(stamp(b,precise:true)) at original speed and pitch. Choose a new filename; the source is kept."
        panel.beginSheetModal(for:window!) { [weak self] response in
            guard let self, response == .OK, let destination = panel.url else { return }
            self.exporting = true; self.notice.stringValue = "Exporting a new MP4…"; self.refresh()
            self.exporter.export(source:URL(fileURLWithPath:clip.path),destination:destination,a:a,b:b) { [weak self] result in
                guard let self else { return }; self.exporting = false
                switch result { case .success: self.notice.stringValue = "Saved \(destination.lastPathComponent). Open it in GLoop to practice."; case .failure(let error): self.notice.stringValue = error.localizedDescription }; self.refresh()
            }
        }
    }
    func shutdown() { token = UUID(); client.disconnect(); exporter.cancel() }
    func windowWillClose(_ notification:Notification) { shutdown(); busy = false; connecting = false; proposed = nil; connection.stringValue = "Disconnected." }
}

extension PlayerApp {
    @objc func showAITrim() {
        if aiTrimWindow == nil { aiTrimWindow = AITrimWindow(app:self) }
        aiTrimWindow?.window?.appearance = window.appearance; aiTrimWindow?.refresh(); aiTrimWindow?.showWindow(nil)
    }
}
