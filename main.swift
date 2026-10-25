import AppKit
import AVFoundation
import UniformTypeIdentifiers

final class VideoHost: NSView {
    var onFile: ((URL) -> Void)?
    var playerLayer: AVPlayerLayer? { didSet { wantsLayer = true; if let playerLayer { layer?.addSublayer(playerLayer) }; needsLayout = true } }
    override func layout() { super.layout(); playerLayer?.frame = bounds }
    override init(frame: NSRect) { super.init(frame: frame); clipsToBounds = true; registerForDraggedTypes([.fileURL]) }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) { NSColor.black.setFill(); bounds.fill() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], let url = urls.first else { return false }
        onFile?(url); return true
    }
}

final class PlayerApp: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    var window: NSWindow!
    let appearanceMenu = NSMenu(title: "Appearance")
    var alignmentControls: NSStackView!
    let alignmentToggle = NSButton()
    let libraryCount = NSTextField(labelWithString: "")
    let emptyLibrary = NSTextField(labelWithString: "No matching sections.\nTry another search or song.")
    let player = NativeVideo()
    var clips: [Clip] = []
    var visible: [Clip] = []
    var selected: Clip?
    var saved = SavedState()
    var prefs = ClipSettings()
    var counter = LoopCounter()
    let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/GLoop", isDirectory: true)
    var stateURL: URL { support.appendingPathComponent("State.json") }
    let table = NSTableView()
    let song = NSPopUpButton()
    let search = NSSearchField()
    let video = VideoHost(frame: .zero)
    let titleLabel = NSTextField(labelWithString: "Open a video")
    let subtitle = NSTextField(labelWithString: "")
    let waveform = WaveformView(frame: .zero)
    let zoomWaveButton = NSButton(title: "Zoom to loop",target: nil,action: nil)
    let fitWaveButton = NSButton(title: "Fit clip",target: nil,action: nil)
    var waveWasPlaying = false
    let timeline = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let elapsed = NSTextField(labelWithString: "0:00")
    let total = NSTextField(labelWithString: "0:00")
    let play = NSButton(title: "Play", target: nil, action: nil)
    let speed = NSSlider(value: 75, minValue: 25, maxValue: 125, target: nil, action: nil)
    let speedLabel = NSTextField(labelWithString: "75%")
    let autoIncrease = NSButton(checkboxWithTitle: "Auto speed", target: nil, action: nil)
    let speedStep = NSPopUpButton()
    let pitchDown = NSButton(title: "−",target: nil,action: nil)
    let pitchUp = NSButton(title: "+",target: nil,action: nil)
    let pitchReset = NSButton(title: "Reset",target: nil,action: nil)
    let pitchLabel = NSTextField(labelWithString: "Original")
    let pitchNote = NSTextField(labelWithString: "")
    let metronome = PracticeMetronome()
    let smooth = GaplessAudio()
    let audioQueue = DispatchQueue(label: "local.gloop.decode",qos: .userInitiated)
    var audioRequest = UUID()
    var audioBusy = false
    var smoothAccounted = 0
    var videoSyncAt = 0.0
    var isPlaying: Bool { smooth.ready ? smooth.isPlaying : player.isPlaying }
    var playbackVolume: Int32 { smoke || uiTest || smooth.ready || audioBusy ? 0 : saved.volume }
    let metroCheck = NSButton(checkboxWithTitle: "Metronome", target: nil, action: nil)
    let clickVolume = NSSlider(value: 30,minValue: 0,maxValue: 100,target: nil,action: nil)
    let beatField = NSTextField(string: "0:00.000")
    let metroStatus = NSTextField(labelWithString: "Set BPM above to enable clicks")
    var metroSeekTarget: Double?
    let loopCheck = NSButton(checkboxWithTitle: "Loop phrase", target: nil, action: nil)
    let aField = NSTextField(string: "0:00.000")
    let bField = NSTextField(string: "0:00.000")
    let repeatMenu = NSPopUpButton()
    let progress = NSTextField(labelWithString: "0 / 30 plays")
    let status = NSTextField(labelWithString: "Select a clip.")
    let volume = NSSlider(value: 55, minValue: 0, maxValue: 100, target: nil, action: nil)
    let detectBPMButton = NSButton(title: "Detect BPM", target: nil, action: nil)
    let bpmField = NSTextField(string: "")
    let effectiveBPM = NSTextField(labelWithString: "Now — BPM")
    let bpmNote = NSTextField(labelWithString: "")
    var bpmRequest = UUID()
    var bpmBusy = false
    let bpmQueue = DispatchQueue(label: "local.gloop.tempo", qos: .userInitiated)
    var timer: Timer?
    var keys: Any?
    var duration = 0.0
    var pendingPause = false
    var pendingStart = 0.0
    var loadingAt = 0.0
    var seekingUntil = 0.0
    var lastRaw = -1.0
    var rawAt = 0.0
    let uiTest = ProcessInfo.processInfo.arguments.contains("--ui-test")
    var now: Double { ProcessInfo.processInfo.systemUptime }
    let smokeRampOne = ProcessInfo.processInfo.arguments.contains("--smoke-ramp1")
    let smokeRamp = ProcessInfo.processInfo.arguments.contains("--smoke-ramp")
    var smokeRates: [Float] = []
    var smokePitches: [Int] = []
    let smokePitch = ProcessInfo.processInfo.arguments.contains("--smoke-pitch") ? -1 : 0
    var smoke = ProcessInfo.processInfo.arguments.contains("--smoke-test") || ProcessInfo.processInfo.arguments.contains("--smoke-ramp") || ProcessInfo.processInfo.arguments.contains("--smoke-ramp1")
    var smokeStarted = false
    var smokeRate: Float = 0
    var smokeVout: UInt32 = 0
    var pendingFiles: [URL] = []
    var downloadJob: VideoDownload?
    var downloadSheet: NSAlert?
    var downloadRequest = UUID()
    var startupNotice: String?
    var persistenceBlocked = false
    var practiceInspector: NSView?
    var importRequest = UUID()
    var pendingSave: DispatchWorkItem?
    let stats = PracticeStats()
    var statsStore: PracticeStatsStore!
    var statsWindow: PracticeStatsWindow?
    var aiTrimWindow: AITrimWindow?
    var statsUIAt = 0.0, statsSavedAt = 0.0, statsFirstLength = 0.0
    var statsStartingCount = 0
    let cleanButton = NSButton(title: "Played cleanly",target: nil,action: nil)
    let undoCleanButton = NSButton(title: "Undo",target: nil,action: nil)

    func applicationDidFinishLaunching(_ note: Notification) {
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let legacyState = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Riff Practice/State.json")
        let loadState = FileManager.default.fileExists(atPath: stateURL.path) ? stateURL : legacyState
        if !uiTest && !smoke && FileManager.default.fileExists(atPath: loadState.path) {
            do { saved = try StateStore.load(loadState) }
            catch {
                let backup = loadState.deletingPathExtension().appendingPathExtension("backup.json")
                let preserved = support.appendingPathComponent("Unreadable-" + UUID().uuidString + ".json")
                do { try FileManager.default.copyItem(at: loadState, to: preserved) }
                catch { persistenceBlocked = true }
                if let restored = try? StateStore.load(backup) { saved = restored; startupNotice = "Settings were restored from the last readable backup. The unreadable file was preserved." }
                else { startupNotice = "Your settings could not be read. The original file was preserved; import your videos to start again." }
                if persistenceBlocked { startupNotice = "Settings could not be read or backed up. Saving is disabled to protect the original file. Check the GLoop folder in Application Support." }
            }
        }
        if let url = Bundle.main.url(forResource: "Library", withExtension: "json"), let data = try? Data(contentsOf: url), let lib = try? JSONDecoder().decode([Clip].self, from: data) { clips = lib }
        if smoke, let i = ProcessInfo.processInfo.arguments.firstIndex(of: "--smoke-file"), i+1 < ProcessInfo.processInfo.arguments.count {
            let path = ProcessInfo.processInfo.arguments[i+1]
            guard FileManager.default.fileExists(atPath: path) else { fputs("Smoke test file not found.\n",stderr); exit(1) }
            clips = [Clip(title: "Test clip",song: "Tests",path: path,duration: 0)]
        }
        if uiTest, let i = ProcessInfo.processInfo.arguments.firstIndex(of: "--ui-test-file"), i+1 < ProcessInfo.processInfo.arguments.count {
            clips = [Clip(title: "Loop timing fixture",song: "Local UI test",path: ProcessInfo.processInfo.arguments[i+1],duration: 4)]
        }
        if !smoke { clips += saved.imports.filter { imported in !clips.contains { $0.path == imported.path } } }
        clips.removeAll { saved.hiddenPaths?.contains($0.path) == true }
        if smoke && clips.isEmpty { fputs("Provide --smoke-file /absolute/path/to/video with at least two seconds of audio.\n",stderr); exit(1) }
        setupStats(); setupEngine(); buildUI(); setupMenus()
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in self?.key(event) ?? event }
        timer = Timer.scheduledTimer(timeInterval: 0.015, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer!, forMode: .common)
        let remembered = smoke ? clips.first : clips.first(where: { $0.path == saved.lastPath })
        window.makeKeyAndOrderFront(nil); window.contentView?.layoutSubtreeIfNeeded()
        filter()
        if let clip = remembered ?? clips.first { load(clip) }
        window.makeKeyAndOrderFront(nil); window.makeFirstResponder(video); NSApp.activate(ignoringOtherApps: true)
        if let url = pendingFiles.first { pendingFiles.removeAll(); importVideo(url) }
        else if let startupNotice { status.stringValue = startupNotice }
    }
    func setupEngine() { player.setVolume(smoke ? 0 : saved.volume) }
    func label(_ text: String, _ size: CGFloat = 13, _ weight: NSFont.Weight = .regular) -> NSTextField {
        let l = NSTextField(labelWithString: text); l.font = .systemFont(ofSize: size, weight: weight); l.textColor = GLoopTheme.text; return l
    }
    func button(_ text: String, _ action: Selector, symbol: String? = nil) -> NSButton {
        let b = NSButton(title: text, target: self, action: action); b.bezelStyle = .rounded; b.controlSize = .regular
        if let symbol { b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: text); b.imagePosition = .imageLeading }
        return b
    }
    func row(_ views: [NSView], spacing: CGFloat = 10) -> NSStackView {
        let s = NSStackView(views: views); s.orientation = .horizontal; s.alignment = .centerY; s.spacing = spacing; return s
    }
    func col(_ views: [NSView], spacing: CGFloat = 12) -> NSStackView {
        let s = NSStackView(views: views); s.orientation = .vertical; s.alignment = .leading; s.spacing = spacing; return s
    }
    func width(_ v: NSView, _ w: CGFloat) { v.widthAnchor.constraint(equalToConstant: w).isActive = true }
    func flexible() -> NSView { let v = NSView(); v.setContentHuggingPriority(.init(1), for: .horizontal); return v }
    func buildUI() {
        window = NSWindow(contentRect: NSRect(x: 80,y: 80,width: 1440,height: 860),styleMask: [.titled,.closable,.miniaturizable,.resizable],backing: .buffered,defer: false)
        window.title = "GLoop"; window.minSize = NSSize(width: 1180,height: 720); window.delegate = self
        window.titlebarAppearsTransparent = true
        let root = StudioSurface(GLoopTheme.canvas); window.contentView = root
        let sidebar = StudioSurface(GLoopTheme.sidebar), main = NSView(), inspector = StudioSurface(GLoopTheme.sidebar)
        for v in [sidebar,main,inspector] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
        NSLayoutConstraint.activate([sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),sidebar.topAnchor.constraint(equalTo: root.topAnchor),sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),sidebar.widthAnchor.constraint(equalToConstant: 236),main.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),main.topAnchor.constraint(equalTo: root.topAnchor),main.bottomAnchor.constraint(equalTo: root.bottomAnchor),main.trailingAnchor.constraint(equalTo: inspector.leadingAnchor),inspector.trailingAnchor.constraint(equalTo: root.trailingAnchor),inspector.topAnchor.constraint(equalTo: root.topAnchor),inspector.bottomAnchor.constraint(equalTo: root.bottomAnchor),inspector.widthAnchor.constraint(equalToConstant: 320)])
        libraryCount.font = .systemFont(ofSize: 12); libraryCount.textColor = GLoopTheme.muted
        song.addItem(withTitle: "All songs"); for name in Array(Set(clips.map(\.song))).sorted() { song.addItem(withTitle: name) }
        song.target = self; song.action = #selector(filterChanged); song.setAccessibilityLabel("Filter by song")
        search.placeholderString = "Find a section"; search.delegate = self; search.setAccessibilityLabel("Search practice sections")
        let header = col([row([label("Library",14,.semibold),flexible(),libraryCount]),song,search],spacing: 12)
        header.translatesAutoresizingMaskIntoConstraints = false; sidebar.addSubview(header)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip")); column.width = 208; table.addTableColumn(column)
        table.headerView = nil; table.rowHeight = 64; table.intercellSpacing = NSSize(width: 0,height: 2); table.style = .plain; table.backgroundColor = .clear; table.delegate = self; table.dataSource = self; table.allowsEmptySelection = true
        table.setAccessibilityLabel("Practice sections")
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.drawsBackground = false; scroll.translatesAutoresizingMaskIntoConstraints = false; sidebar.addSubview(scroll)
        emptyLibrary.font = .systemFont(ofSize: 13); emptyLibrary.textColor = GLoopTheme.muted; emptyLibrary.maximumNumberOfLines = 4; emptyLibrary.lineBreakMode = .byWordWrapping; emptyLibrary.cell?.wraps = true; emptyLibrary.alignment = .center; emptyLibrary.translatesAutoresizingMaskIntoConstraints = false; sidebar.addSubview(emptyLibrary); emptyLibrary.isHidden = true
        let open = button("Open video…",#selector(openFile),symbol: "plus"); open.translatesAutoresizingMaskIntoConstraints = false; sidebar.addSubview(open)
        NSLayoutConstraint.activate([header.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor,constant: 16),header.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor,constant: -16),header.topAnchor.constraint(equalTo: sidebar.topAnchor,constant: 20),song.widthAnchor.constraint(equalTo: header.widthAnchor),search.widthAnchor.constraint(equalTo: header.widthAnchor),scroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor,constant: 8),scroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor,constant: -8),scroll.topAnchor.constraint(equalTo: header.bottomAnchor,constant: 16),scroll.bottomAnchor.constraint(equalTo: open.topAnchor,constant: -16),open.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor,constant: 16),open.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor,constant: -16),open.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor,constant: -20),open.heightAnchor.constraint(equalToConstant: 36),emptyLibrary.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor,constant: 24),emptyLibrary.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor,constant: -24),emptyLibrary.topAnchor.constraint(equalTo: scroll.topAnchor,constant: 36)])
        titleLabel.font = .systemFont(ofSize: 18,weight: .semibold); titleLabel.textColor = GLoopTheme.text; titleLabel.maximumNumberOfLines = 2; titleLabel.lineBreakMode = .byTruncatingTail
        subtitle.font = .systemFont(ofSize: 13); subtitle.textColor = GLoopTheme.muted
        let heading = col([subtitle,titleLabel],spacing: 8)
        video.translatesAutoresizingMaskIntoConstraints = false; video.onFile = { [weak self] url in self?.importVideo(url) }
        let aspect = video.heightAnchor.constraint(equalTo: video.widthAnchor,multiplier: 9/16); aspect.priority = .init(750); aspect.isActive = true
        video.heightAnchor.constraint(greaterThanOrEqualToConstant: 230).isActive = true
        video.playerLayer = player.layer
        timeline.target = self; timeline.action = #selector(scrub); timeline.isContinuous = true; timeline.setAccessibilityLabel("Playback position")
        for l in [elapsed,total] { l.font = .monospacedDigitSystemFont(ofSize: 12,weight: .medium); l.textColor = GLoopTheme.muted; width(l,46) }
        timeline.setContentHuggingPriority(.init(1),for: .horizontal)
        let scrubber = row([elapsed,timeline,total])
        setupWaveform()
        zoomWaveButton.target = self; zoomWaveButton.action = #selector(zoomWaveform); zoomWaveButton.bezelStyle = .rounded; zoomWaveButton.toolTip = "Enlarge the selected loop for more precise marker placement"
        fitWaveButton.target = self; fitWaveButton.action = #selector(fitWaveform); fitWaveButton.bezelStyle = .rounded; fitWaveButton.toolTip = "Show the full waveform without changing your loop"
        let info = row([muted("Drag to select · drag A/B"),flexible(),zoomWaveButton,fitWaveButton,button("Full screen",#selector(fullscreen),symbol: "arrow.up.left.and.arrow.down.right")])
        let viewing = col([heading,video,waveform,scrubber,info],spacing: 12)
        viewing.translatesAutoresizingMaskIntoConstraints = false; main.addSubview(viewing)
        for v in [heading,video,waveform,scrubber,info] { v.widthAnchor.constraint(equalTo: viewing.widthAnchor).isActive = true }
        titleLabel.widthAnchor.constraint(equalTo: heading.widthAnchor).isActive = true
        play.target = self; play.action = #selector(togglePlay); play.bezelStyle = .rounded; play.controlSize = .large; play.toolTip = "Play or pause (Space)"; width(play,100); play.heightAnchor.constraint(equalToConstant: 36).isActive = true
        let leftSpace = flexible(), rightSpace = flexible()
        let controls = row([leftSpace,button("Previous",#selector(previous),symbol: "backward.end.fill"),button("−5s",#selector(backFive)),play,button("+5s",#selector(forwardFive)),button("Next",#selector(next),symbol: "forward.end.fill"),rightSpace],spacing: 10)
        leftSpace.widthAnchor.constraint(equalTo: rightSpace.widthAnchor).isActive = true
        volume.target = self; volume.action = #selector(volumeChanged); volume.doubleValue = Double(saved.volume); volume.setAccessibilityLabel("Video volume percent"); width(volume,100)
        let footer = row([muted("Space: play/pause   [ / ]: speed"),flexible(),muted("Volume"),volume],spacing: 8)
        status.font = .systemFont(ofSize: 12); status.textColor = GLoopTheme.muted; status.maximumNumberOfLines = 2; status.lineBreakMode = .byTruncatingTail
        cleanButton.target = self; cleanButton.action = #selector(markPlayedCleanly); cleanButton.bezelStyle = .rounded
        undoCleanButton.target = self; undoCleanButton.action = #selector(undoPlayedCleanly); undoCleanButton.bezelStyle = .rounded; undoCleanButton.toolTip = "Undo your most recent clean mark"
        let practiceRow = row([cleanButton,undoCleanButton,flexible(),button("Ask AI…",#selector(showAITrim)),button("Practice stats…",#selector(showPracticeStats))])
        let transport = col([controls,practiceRow,footer,status],spacing: 12); transport.translatesAutoresizingMaskIntoConstraints = false; main.addSubview(transport)
        for v in [controls,practiceRow,footer,status] { v.widthAnchor.constraint(equalTo: transport.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([viewing.leadingAnchor.constraint(equalTo: main.leadingAnchor,constant: 24),viewing.trailingAnchor.constraint(equalTo: main.trailingAnchor,constant: -24),viewing.topAnchor.constraint(equalTo: main.topAnchor,constant: 24),viewing.bottomAnchor.constraint(lessThanOrEqualTo: transport.topAnchor,constant: -16),transport.leadingAnchor.constraint(equalTo: main.leadingAnchor,constant: 24),transport.trailingAnchor.constraint(equalTo: main.trailingAnchor,constant: -24),transport.bottomAnchor.constraint(equalTo: main.bottomAnchor,constant: -24)])
        let practice = makeInspector(); practiceInspector = practice; practice.translatesAutoresizingMaskIntoConstraints = false; inspector.addSubview(practice)
        NSLayoutConstraint.activate([practice.leadingAnchor.constraint(equalTo: inspector.leadingAnchor),practice.trailingAnchor.constraint(equalTo: inspector.trailingAnchor),practice.topAnchor.constraint(equalTo: inspector.topAnchor),practice.bottomAnchor.constraint(equalTo: inspector.bottomAnchor)])
        applyAppearance(); updateControls(); refreshStatsUI(); window.center()
        if uiTest && ProcessInfo.processInfo.arguments.contains("--ui-test-small") { window.setContentSize(NSSize(width: 1180,height: 692)) }
    }
    func setupMenus() {
        let menu = NSMenu(); let appMenu = NSMenu(); let appItem = NSMenuItem(); appItem.submenu = appMenu; menu.addItem(appItem)
        appMenu.addItem(withTitle: "About GLoop",action: #selector(about),keyEquivalent: "").target = self
        appMenu.addItem(.separator()); appMenu.addItem(withTitle: "Quit GLoop",action: #selector(NSApplication.terminate(_:)),keyEquivalent: "q")
        let file = NSMenu(); let fi = NSMenuItem(title: "File",action: nil,keyEquivalent: ""); fi.submenu = file; menu.addItem(fi)
        file.addItem(withTitle: "Open Video…",action: #selector(openFile),keyEquivalent: "o").target = self
        file.addItem(withTitle: "Open Practice File…",action: #selector(openPracticeFile),keyEquivalent: "").target = self
        file.addItem(withTitle: "Convert Video to MP4…",action: #selector(convertFile),keyEquivalent: "").target = self
        file.addItem(withTitle: "Close Window",action: #selector(NSWindow.performClose(_:)),keyEquivalent: "w")
        file.addItem(.separator())
        file.addItem(withTitle: "Show Video in Finder",action: #selector(revealVideo),keyEquivalent: "").target = self
        file.addItem(withTitle: "Remove from Library",action: #selector(removeFromLibrary),keyEquivalent: "").target = self
        let edit = NSMenu(); let ei = NSMenuItem(title: "Edit",action: nil,keyEquivalent: ""); ei.submenu = edit; menu.addItem(ei)
        for (title,sel,key) in [("Cut","cut:","x"),("Copy","copy:","c"),("Paste","paste:","v"),("Select All","selectAll:","a")] { edit.addItem(withTitle: title,action: Selector(sel),keyEquivalent: key) }
        let view = NSMenu(); let vi = NSMenuItem(title: "View",action: nil,keyEquivalent: ""); vi.submenu = view; menu.addItem(vi)
        view.addItem(withTitle: "AI Trim…",action: #selector(showAITrim),keyEquivalent: "").target = self
        view.addItem(withTitle: "Practice Stats",action: #selector(showPracticeStats),keyEquivalent: "j").target = self
        view.addItem(withTitle: "Full Screen",action: #selector(fullscreen),keyEquivalent: "f").target = self
        let themeItem = NSMenuItem(title: "Appearance",action: nil,keyEquivalent: ""); themeItem.submenu = appearanceMenu; view.addItem(themeItem)
        for (index,name) in ["Follow System","Dark","Light"].enumerated() {
            let item = NSMenuItem(title: name,action: #selector(selectAppearance(_:)),keyEquivalent: ""); item.tag = index; item.target = self; appearanceMenu.addItem(item)
        }
        applyAppearance()
        let help = NSMenu(); let hi = NSMenuItem(title: "Help", action: nil, keyEquivalent: ""); hi.submenu = help; menu.addItem(hi)
        help.addItem(withTitle: "GLoop Quick Start", action: #selector(quickStart), keyEquivalent: "?").target = self
        NSApp.mainMenu = menu
    }
    func numberOfRows(in tableView: NSTableView) -> Int { visible.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let c = visible[row]; let cell = NSTableCellView()
        let name = label(c.title,13,.medium); name.toolTip = c.title; name.maximumNumberOfLines = 2; name.lineBreakMode = .byWordWrapping; name.cell?.wraps = true; name.cell?.usesSingleLineMode = false
        let detail = label(c.song + (c.duration > 0 ? " · " + stamp(c.duration) : ""),12); detail.textColor = GLoopTheme.muted
        let stack = col([name,detail],spacing: 3); stack.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor,constant: 8),stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor,constant: -8),stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),name.widthAnchor.constraint(equalTo: stack.widthAnchor)])
        cell.textField = name; return cell
    }
    func tableView(_ tableView: NSTableView,rowViewForRow row: Int) -> NSTableRowView? { GLoopRow() }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard table.selectedRow >= 0,table.selectedRow < visible.count else { return }
        let c = visible[table.selectedRow]; if selected?.path != c.path { load(c) }
    }
    @objc func filterChanged() { filter() }
    func controlTextDidChange(_ obj: Notification) { if obj.object as? NSSearchField === search { filter() } }
    func filter() {
        let q = search.stringValue.lowercased(); let name = song.titleOfSelectedItem ?? "All songs"
        visible = clips.filter { (name == "All songs" || $0.song == name) && (q.isEmpty || ($0.title+" "+$0.song).lowercased().contains(q)) }
        libraryCount.stringValue = "\(visible.count) \(visible.count == 1 ? "clip" : "clips")"
        emptyLibrary.stringValue = clips.isEmpty ? "Open a video to begin.\nMP4 and MOV work without extra software." : "No matching sections.\nTry another search or song."
        emptyLibrary.isHidden = !visible.isEmpty
        let prior = selected?.path; table.reloadData()
        if let i = visible.firstIndex(where: { $0.path == prior }) { table.selectRowIndexes(IndexSet(integer: i),byExtendingSelection: false) }
    }
    func load(_ clip: Clip) {
        importRequest = UUID()
        guard FileManager.default.fileExists(atPath: clip.path) else { status.stringValue = "File moved or missing. Use Open video to locate it."; return }
        if !["mp4", "mov", "m4v"].contains(URL(fileURLWithPath: clip.path).pathExtension.lowercased()) { offerConversion(URL(fileURLWithPath: clip.path)); return }
        sampleStats(); persistStats(); stats.select(clip)
        waveform.clear("Loading waveform…"); waveWasPlaying = false
        save(); smooth.clear(); audioRequest = UUID(); audioBusy = true; metronome.reset(); metroSeekTarget = nil; player.stop()
        bpmRequest = UUID(); bpmBusy = false
        selected = clip; prefs = (saved.settings[clip.path] ?? ClipSettings()).normalized(duration: clip.duration); counter.reset(); duration = clip.duration; prepareStats(at: prefs.a); refreshStatsUI()
        aiTrimWindow?.clipDidChange()
        player.open(URL(fileURLWithPath: clip.path))
        titleLabel.stringValue = clip.title; subtitle.stringValue = clip.song
        updateControls(); pendingPause = true; pendingStart = max(0,prefs.a); loadingAt = now; seekingUntil = now+0.3; lastRaw = -1
        player.setVolume(0); player.setRate(Float(prefs.speed)); player.play()
        status.stringValue = "Loading audio…"; saved.lastPath = clip.path; save()
        let request = audioRequest, settings = prefs
        audioQueue.async { [weak self] in
            let result = Result {
                let pcm = try GaplessAudio.decode(clip.path)
                let duration = Double(pcm.frameLength) / pcm.format.sampleRate
                let valid = settings.normalized(duration: duration)
                // Allocate/copy the initial phrase on the decoder queue, not the UI thread.
                return (GaplessAudio.prepare(pcm,a: valid.a,b: valid.b ?? duration),WaveformEnvelope(pcm))
            }
            DispatchQueue.main.async {
                guard let self, self.audioRequest == request else { return }
                self.audioBusy = false
                switch result {
                case .success(let (prepared,envelope)):
                    self.waveform.install(envelope)
                    let pcm = prepared.source
                    self.duration = Double(pcm.frameLength) / pcm.format.sampleRate
                    self.prefs = self.prefs.normalized(duration: self.duration)
                    self.smooth.install(prepared)
                    self.configureSmooth(at: self.prefs.a,playing: false)
                    self.updateControls()
                    self.status.stringValue = "Ready"
                    self.player.setVolume(0)
                case .failure(let error):
                    self.status.stringValue = error.localizedDescription
                    self.player.setVolume(self.playbackVolume)
                    self.updatePitchControls()
                    self.waveform.clear("Waveform unavailable for this video."); self.updateWaveform()
                }
            }
        }
        if let i = visible.firstIndex(of: clip), table.selectedRow != i { table.selectRowIndexes(IndexSet(integer: i),byExtendingSelection: false); table.scrollRowToVisible(i) }
    }
    func updateControls() {
        func enabled(_ view: NSView) {
            if let control = view as? NSControl { control.isEnabled = selected != nil }
            for child in view.subviews { enabled(child) }
        }
        if let practiceInspector { enabled(practiceInspector) }
        speed.doubleValue = prefs.speed*100; speedLabel.stringValue = String(format: "%.0f%%",prefs.speed*100)
        aField.stringValue = stamp(prefs.a,precise: true); bField.stringValue = stamp(prefs.b ?? duration,precise: true)
        loopCheck.state = prefs.looping ? .on : .off
        autoIncrease.state = prefs.autoIncrease == true ? .on : .off
        speedStep.selectItem(at: prefs.increasePoints == 1 ? 0 : 1)
        metroCheck.state = prefs.metronomeEnabled == true ? .on : .off
        clickVolume.doubleValue = (prefs.clickVolume ?? 0.3)*100
        beatField.stringValue = stamp(prefs.beatAnchor ?? prefs.a,precise: true)
        repeatMenu.selectItem(at: [0,5,10,30,50].firstIndex(of: prefs.target) ?? 3)
        total.stringValue = stamp(duration); timeline.maxValue = max(1,duration)
        updateProgress(); updateBPMControls(); updatePitchControls(); updateWaveform(); aiTrimWindow?.refresh()
    }
    func updateProgress() { progress.stringValue = prefs.looping ? (prefs.target == 0 ? "\(counter.completed) plays" : "\(counter.completed) / \(prefs.target) plays") : "Single play" }
    func position() -> Double {
        if smooth.ready { return smooth.position }
        let raw = max(0,player.time)
        if raw != lastRaw { lastRaw = raw; rawAt = now }
        let running = player.isPlaying
        return min(max(duration,raw), raw + (running && now > seekingUntil ? min(0.28,now-rawAt)*prefs.speed : 0))
    }
    @objc func tick() {
        guard selected != nil else { return }
        defer { waveform.setPlayhead(position()) }
        sampleStats()
        let s = player.state
        let len = smooth.ready ? smooth.duration : player.duration
        if len > 0 && abs(duration-len) > 0.005 { duration = len; timeline.maxValue = len; total.stringValue = stamp(len); if prefs.b == nil { bField.stringValue = stamp(len,precise: true) }; if !smooth.ready && stats.b <= stats.a { prepareStats(at: prefs.a) } }
        if s == .failed { smooth.pause(); metronome.stop(); status.stringValue = "macOS cannot play this video. Use File → Convert Video to MP4, or open a supported MP4/MOV."; pendingPause = false; return }
        if pendingPause && s == .playing && player.hasVideo > 0 {
            player.setRate(Float(prefs.speed)); player.pause(true)
            if pendingStart > 0 { player.seek(pendingStart) }
            pendingPause = false; player.setVolume(playbackVolume); status.stringValue = "Ready"
        }
        if smoke && !smokeStarted && !pendingPause && smooth.ready { smokeStarted = true; prefs.pitchSemitones = smokePitch; prefs.a = 0.4; prefs.b = 1.2; prefs.speed = (smokeRamp || smokeRampOne) ? 0.9 : 0.75; prefs.autoIncrease = smokeRamp || smokeRampOne; prefs.speedStep = smokeRampOne ? 1 : 5; prefs.bpm = 120; prefs.metronomeEnabled = smokeRampOne; prefs.beatAnchor = nil; prefs.looping = true; prefs.target = 5; counter.reset(); updateControls(); seek(0.4); player.setRate(Float(prefs.speed)); player.pause(false); smokeRate = player.rate; smokeRates = [smokeRate]; smokeVout = player.hasVideo; configureSmooth(at: 0.4,playing: true); smokePitches = [smooth.pitchSemitones] }
        if pendingPause && now-loadingAt > 12 { status.stringValue = "Waiting for video. Allow Downloads access if macOS asks." }
        if smooth.ready && !pendingPause {
            tickSmooth()
            if smoke && now-loadingAt > 30 && !counter.finished { finishSmoke(failed: true) }
            return
        }
        let t = position(); elapsed.stringValue = stamp(t); if !timeline.cell!.isHighlighted { timeline.doubleValue = t }
        let end = min(duration,prefs.b ?? duration)
        if !pendingPause && !counter.finished && now > seekingUntil && end > prefs.a+0.1 && (s == .ended || (s == .playing && t >= end-0.012)) {
            stats.boundary(speed: prefs.speed); refreshStatsUI()
            let again = counter.boundary(looping: prefs.looping,target: prefs.target); updateProgress()
            if again {
                if s == .ended { player.stop(); player.play(); player.setRate(Float(prefs.speed)) }
                if prefs.autoIncrease == true { setSpeed(prefs.nextLoopSpeed,automatic: true) }
                if smoke { smokeRates.append(player.rate) }
                seek(prefs.a); status.stringValue = "Repeating " + stamp(prefs.a) + "–" + stamp(end) + " · " + String(format:"%.0f%% speed",prefs.speed*100)
            } else {
                metronome.stop(); player.pause(true); play.title = "Replay"; status.stringValue = prefs.looping ? "Finished: \(counter.completed) plays" : "Finished"
                if smoke { finishSmoke() }
            }
        }
        if !counter.finished { play.title = player.isPlaying ? "Pause" : "Play" }
        syncMetronome()
        if smoke && now-loadingAt > 20 && !counter.finished { finishSmoke(failed: true) }
    }
    func configureSmooth(at time: Double,playing: Bool) {
        guard smooth.ready else { return }
        let end = min(smooth.duration,prefs.b ?? smooth.duration)
        let remaining = prefs.looping ? (prefs.target == 0 ? 0 : max(1,prefs.target-counter.completed)) : 1
        sampleStats()
        smooth.configure(a: prefs.a,b: end,position: time,plays: remaining)
        prepareStats(at: smooth.position)
        smoothAccounted = 0; smooth.rate = prefs.speed; smooth.pitchSemitones = prefs.pitchShift; smooth.volume = smoke || uiTest ? 0 : Float(saved.volume)/100
        if playing { do { try smooth.play() } catch { status.stringValue = error.localizedDescription } }
        sampleStats()
    }
    func syncVideo(force: Bool = false) {
        guard smooth.isPlaying else { return }
        let raw = max(0,player.time)
        let state = player.state
        if force || state == .ended || (now-videoSyncAt > 1 && abs(raw-smooth.position) > 0.25) {
            if state == .ended || state == .stopped { player.stop(); player.play() }
            player.pause(false)
            player.setRate(Float(prefs.speed))
            player.seek(smooth.position)
            videoSyncAt = now
        }
    }
    func tickSmooth() {
        while smoothAccounted < smooth.completed && !counter.finished {
            smoothAccounted += 1
            stats.boundary(speed: prefs.speed); refreshStatsUI()
            let again = counter.boundary(looping: prefs.looping,target: prefs.target)
            updateProgress(); metronome.reset()
            if again {
                if prefs.autoIncrease == true { setSpeed(prefs.nextLoopSpeed,automatic: true) }
                if smoke { smokeRates.append(Float(smooth.rate)); smokePitches.append(smooth.pitchSemitones) }
                syncVideo(force: true)
                status.stringValue = "Playing"
            } else {
                smooth.pause(); metronome.stop(); player.pause(true)
                play.title = "Replay"; status.stringValue = "Finished: \(counter.completed) plays"
                if smoke { finishSmoke() }
            }
        }
        elapsed.stringValue = stamp(smooth.position)
        if !timeline.cell!.isHighlighted { timeline.doubleValue = smooth.position }
        if !counter.finished { play.title = smooth.isPlaying ? "Pause" : "Play" }
        syncVideo(); syncMetronome()
    }
    func seek(_ t: Double) {
        sampleStats(); if !smooth.ready { prepareStats(at: t) }
        let value = min(max(0,t),max(0,duration-0.025)); if smooth.ready { configureSmooth(at: value,playing: smooth.isPlaying) }; metronome.reset(); metroSeekTarget = value; player.seek(value); lastRaw = -1; rawAt = now; seekingUntil = now+0.22; timeline.doubleValue = value
    }
    @objc func togglePlay() {
        sampleStats(); defer { stats.resetClock(); sampleStats(); persistStats(); refreshStatsUI() }
        guard selected != nil else { openFile(); return }
        if audioBusy { status.stringValue = "Loading audio…"; return }
        if smooth.ready {
            if smooth.isPlaying { smooth.pause(); player.pause(true); metronome.stop(); status.stringValue = "Paused" }
            else {
                if counter.finished { counter.reset(); configureSmooth(at: prefs.a,playing: false) }
                pendingPause = false
                do { try smooth.play(); syncVideo(force: true); status.stringValue = "Playing" }
                catch { status.stringValue = "Audio could not start: " + error.localizedDescription }
            }
            updateProgress(); return
        }
        metronome.reset(); pendingPause = false; player.setVolume(playbackVolume)
        if counter.finished || [.ended,.stopped,.failed].contains(player.state) {
            counter.reset(); player.stop(); player.play(); player.setRate(Float(prefs.speed)); seek(prefs.a)
        } else if player.isPlaying { player.pause(true); status.stringValue = "Paused" }
        else { if position() < prefs.a || position() >= (prefs.b ?? duration)-0.025 { seek(prefs.a) }; player.pause(false) }
        rawAt = now; lastRaw = -1; updateProgress()
    }
    @objc func scrub() { counter.reset(); seek(timeline.doubleValue); updateProgress() }
    @objc func setA() { let a = position(); guard a < (prefs.b ?? duration)-0.15 else { status.stringValue = "Set A at least 0.15 seconds before B."; return }; prefs.a = a; markersChanged() }
    @objc func setB() { let b = position(); guard b > prefs.a+0.15 else { status.stringValue = "Set B at least 0.15 seconds after A."; return }; prefs.b = b; prefs.looping = true; markersChanged() }
    @objc func markersEdited() {
        guard let a = parseStamp(aField.stringValue),let b = parseStamp(bField.stringValue),a >= 0,b > a+0.15,b <= duration+0.02 else { status.stringValue = "Use m:ss.mmm. B must be after A and inside the video."; updateControls(); return }
        prefs.a = a; prefs.b = min(b,duration); prefs.looping = true; markersChanged()
    }
    func markersChanged() { aiTrimWindow?.refresh(); metronome.reset(); counter.reset(); seek(prefs.a); updateControls(); save(); status.stringValue = "Loop saved: " + stamp(prefs.a,precise: true) + "–" + stamp(prefs.b ?? duration,precise: true) }
    @objc func clearMarkers() { prefs.a = 0; prefs.b = nil; markersChanged() }
    @objc func loopChanged() { prefs.looping = loopCheck.state == .on; counter.reset(); if smooth.ready { configureSmooth(at: position(),playing: smooth.isPlaying) } else { prepareStats(at: position()) }; updateProgress(); updateWaveform(); save() }
    @objc func autoIncreaseChanged() {
        prefs.autoIncrease = autoIncrease.state == .on; save()
        status.stringValue = prefs.autoIncrease == true ? "Auto speed: +\(prefs.increasePoints)% per loop, up to 100%." : "Auto speed off"
    }
    @objc func speedStepChanged() { prefs.speedStep = speedStep.indexOfSelectedItem == 0 ? 1 : 5; save(); status.stringValue = "+\(prefs.increasePoints)% per loop, up to 100%." }
    @objc func repeatChanged() { prefs.target = [0,5,10,30,50][max(0,repeatMenu.indexOfSelectedItem)]; counter.reset(); if smooth.ready { configureSmooth(at: position(),playing: smooth.isPlaying) } else { prepareStats(at: position()) }; updateProgress(); save() }
    func setSpeed(_ rate: Double, automatic: Bool = false) { sampleStats(); stats.speedChanged(min(1.25,max(0.25,rate)),automatic: automatic); metronome.reset(); prefs.speed = min(1.25,max(0.25,rate)); smooth.rate = prefs.speed; player.setRate(Float(prefs.speed)); speed.doubleValue = prefs.speed*100; speedLabel.stringValue = String(format:"%.0f%%",prefs.speed*100); rawAt = now; lastRaw = -1; updateBPMControls(); save() }
    func syncMetronome() {
        let active = prefs.metronomeEnabled == true && !pendingPause && !counter.finished && isPlaying
        if let target = metroSeekTarget, active, !smooth.ready {
            let raw = player.time
            if abs(raw-target) > 0.25 && now < seekingUntil+0.1 { metronome.stop(); return }
            metroSeekTarget = nil
        }
        metronome.sync(position: position(),bpm: prefs.bpm,rate: prefs.speed,anchor: prefs.beatAnchor ?? prefs.a,active: active,volume: smoke ? 0 : (prefs.clickVolume ?? 0.3))
        if let error = metronome.failure { metroStatus.stringValue = "Audio unavailable"; status.stringValue = error }
    }
    @objc func metroChanged() {
        prefs.metronomeEnabled = metroCheck.state == .on; metronome.failure = nil; metronome.reset(); save(); updateBPMControls()
        if prefs.metronomeEnabled == true && prefs.bpm == nil { status.stringValue = "Enter or detect BPM first." }
    }
    @objc func clickVolumeChanged() { prefs.clickVolume = clickVolume.doubleValue/100; save() }
    @objc func alignBeat() { prefs.beatAnchor = position(); beatAlignmentChanged() }
    @objc func beatAtA() { prefs.beatAnchor = nil; beatAlignmentChanged() }
    @objc func beatEdited() {
        guard let value = parseStamp(beatField.stringValue), value <= duration else { status.stringValue = "Enter a beat time inside this clip (m:ss.mmm)."; return }
        prefs.beatAnchor = value; window.makeFirstResponder(video); beatAlignmentChanged()
    }
    func beatAlignmentChanged() {
        metronome.reset(); beatField.stringValue = stamp(prefs.beatAnchor ?? prefs.a,precise: true); save()
        status.stringValue = "Beat at " + stamp(prefs.beatAnchor ?? prefs.a,precise: true)
    }
    func updateBPMControls() {
        metroStatus.stringValue = prefs.bpm == nil ? "Detect or enter BPM first" : (prefs.metronomeEnabled == true ? String(format:"%.1f BPM",prefs.bpm!*prefs.speed) : "Off")
        detectBPMButton.isEnabled = selected != nil && !bpmBusy
        detectBPMButton.title = bpmBusy ? "Analyzing…" : "Detect BPM"
        if let bpm = prefs.bpm {
            if window.firstResponder !== bpmField.currentEditor() { bpmField.stringValue = String(format:"%.1f",bpm) }
            effectiveBPM.stringValue = String(format:"Now %.1f BPM",bpm*prefs.speed)
        } else { bpmField.stringValue = ""; effectiveBPM.stringValue = "Now — BPM" }
        bpmNote.stringValue = bpmBusy ? "Analyzing…" : (prefs.bpmNote ?? ""); bpmNote.isHidden = bpmNote.stringValue.isEmpty
    }
    @objc func detectBPM() {
        guard let clip = selected, !bpmBusy else { return }
        let request = UUID(); bpmRequest = request; bpmBusy = true; updateBPMControls()
        bpmQueue.async { [weak self] in
            let result = Result { try BPMDetector.detect(path: clip.path) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.bpmRequest == request, self.selected?.path == clip.path else { return }
                self.bpmBusy = false
                switch result {
                case .success(let estimate):
                    self.prefs.bpm = estimate.bpm; self.prefs.bpmNote = estimate.description; self.save(); self.updateBPMControls()
                case .failure(let error):
                    self.updateBPMControls(); self.bpmNote.stringValue = "Enter BPM manually."; self.status.stringValue = error.localizedDescription
                }
            }
        }
    }
    @objc func bpmEdited() {
        let text = bpmField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { bpmRequest = UUID(); bpmBusy = false; prefs.bpm = nil; prefs.bpmNote = nil; save(); updateBPMControls(); return }
        guard let value = Double(text), value.isFinite, (20...400).contains(value) else { status.stringValue = "Enter an original tempo between 20 and 400 BPM."; return }
        storeManualBPM(value)
    }
    func storeManualBPM(_ value: Double) {
        window.makeFirstResponder(video)
        bpmRequest = UUID(); bpmBusy = false; prefs.bpm = value; prefs.bpmNote = "Manually set · saved for this clip"; save(); updateBPMControls()
    }
    @objc func halfBPM() { if let bpm = prefs.bpm, bpm/2 >= 20 { storeManualBPM(bpm/2) } }
    @objc func doubleBPM() { if let bpm = prefs.bpm, bpm*2 <= 400 { storeManualBPM(bpm*2) } }
    @objc func speedChanged() { setSpeed((speed.doubleValue/5).rounded()*0.05) }
    @objc func slower() { setSpeed(prefs.speed-0.05) }
    @objc func faster() { setSpeed(prefs.speed+0.05) }
    @objc func halfSpeed() { setSpeed(0.5) }
    @objc func threeQuarter() { setSpeed(0.75) }
    @objc func normalSpeed() { setSpeed(1) }
    @objc func volumeChanged() { saved.volume = Int32(volume.intValue); smooth.volume = smoke || uiTest ? 0 : Float(saved.volume)/100; player.setVolume(playbackVolume); save() }
    @objc func backFive() { counter.reset(); seek(position()-5); updateProgress() }
    @objc func forwardFive() { counter.reset(); seek(position()+5); updateProgress() }
    @objc func previous() { navigate(-1) }
    @objc func next() { navigate(1) }
    func navigate(_ step: Int) { guard !visible.isEmpty else { return }; let i = visible.firstIndex(where: { $0.path == selected?.path }) ?? 0; load(visible[(i+step+visible.count)%visible.count]) }
    @objc func fullscreen() { window.toggleFullScreen(nil) }
    @objc func openFile() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.movie]; p.allowsOtherFileTypes = true; p.canChooseDirectories = false
        p.beginSheetModal(for: window) { [weak self] answer in
            p.orderOut(nil)
            if answer == .OK, let url = p.url { DispatchQueue.main.async { self?.importVideo(url) } }
        }
    }
    @objc func openPracticeFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "gloop") ?? .json]
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] answer in
            panel.orderOut(nil)
            if answer == .OK, let url = panel.url { DispatchQueue.main.async { self?.importVideo(url) } }
        }
    }
    @objc func convertFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.movie]; panel.allowsOtherFileTypes = true; panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] answer in
            panel.orderOut(nil)
            if answer == .OK, let url = panel.url { DispatchQueue.main.async { self?.offerConversion(url) } }
        }
    }
    func offerConversion(_ url: URL, handoff: PracticeHandoff? = nil) {
        guard downloadJob == nil else { status.stringValue = "Finish the current import first."; return }
        let alert = NSAlert(); alert.messageText = "Convert to MP4?"
        alert.informativeText = "Create an H.264/AAC copy of \(url.lastPathComponent) in Movies/GLoop. The original file stays unchanged. This optional conversion needs FFmpeg."
        alert.addButton(withTitle: "Convert"); alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] answer in
            guard answer == .alertFirstButtonReturn, let self else { return }
            let job = VideoDownload(), token = UUID(); self.downloadJob = job; self.downloadRequest = token
            let sheet = NSAlert(); sheet.messageText = "Converting video"; sheet.informativeText = "Creating an MP4 copy…"; sheet.addButton(withTitle: "Cancel")
            self.downloadSheet = sheet
            sheet.beginSheetModal(for: self.window) { [weak self] response in
                if response == .alertFirstButtonReturn, let self, self.downloadRequest == token { job.cancel(); self.downloadRequest = UUID(); self.downloadJob = nil; self.downloadSheet = nil; self.status.stringValue = "Conversion cancelled." }
            }
            let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/GLoop", isDirectory: true)
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let result = Result { try job.convert(url, root: root) }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.downloadRequest == token else { return }
                    self.window.endSheet(sheet.window, returnCode: .OK); self.downloadJob = nil; self.downloadSheet = nil
                    switch result {
                    case .success(let output):
                        if let handoff { self.importPracticeVideo(output, request: handoff) }
                        else { self.saved.settings[output.path] = self.saved.settings[url.path]; self.importVideo(output) }
                    case .failure(let error): self.showImportError(error)
                    }
                }
            }
        }
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if window == nil { pendingFiles = [url] } else { importVideo(url) }
    }
    func showImportError(_ error: Error) {
        let alert = NSAlert(); alert.messageText = "Could not import file"; alert.informativeText = error.localizedDescription
        alert.beginSheetModal(for: window)
    }
    func openHandoff(_ url: URL) {
        guard downloadJob == nil, window.attachedSheet == nil else { status.stringValue = "Finish the current import first."; return }
        do {
            let request = try PracticeHandoff.read(url)
            let alert = NSAlert(); alert.messageText = request.title.isEmpty ? "Import YouTube practice" : request.title
            let range = request.b.map { "\(stamp(request.a, precise: true)) – \(stamp($0, precise: true))" } ?? "From \(stamp(request.a, precise: true))"
            alert.informativeText = "\(request.canonicalURL)\n\n\(range) · \(Int(request.speed))% speed\n\nDownload the full video to Movies/GLoop, or choose the original video if you already have it."
            alert.addButton(withTitle: "Download"); alert.addButton(withTitle: "Choose video…"); alert.addButton(withTitle: "Cancel")
            alert.beginSheetModal(for: window) { [weak self] answer in
                guard let self else { return }
                if answer == .alertFirstButtonReturn { self.downloadVideo(request) }
                else if answer == .alertSecondButtonReturn {
                    let panel = NSOpenPanel(); panel.allowedContentTypes = [.movie]; panel.allowsOtherFileTypes = true; panel.canChooseDirectories = false
                    panel.directoryURL = url.deletingLastPathComponent()
                    panel.beginSheetModal(for: self.window) { [weak self] result in
                        panel.orderOut(nil)
                        if result == .OK, let media = panel.url { DispatchQueue.main.async { self?.importPracticeVideo(media, request: request) } }
                    }
                }
            }
        } catch { showImportError(error) }
    }
    func downloadVideo(_ request: PracticeHandoff) {
        let job = VideoDownload(), token = UUID(); downloadJob = job; downloadRequest = token
        let sheet = NSAlert(); sheet.messageText = "Downloading video"; sheet.informativeText = "Starting…"; sheet.addButton(withTitle: "Cancel")
        let spinner = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 320, height: 16)); spinner.isIndeterminate = true; spinner.style = .bar; spinner.startAnimation(nil); sheet.accessoryView = spinner
        downloadSheet = sheet
        sheet.beginSheetModal(for: window) { [weak self] answer in
            if answer == .alertFirstButtonReturn, let self, self.downloadRequest == token {
                job.cancel(); self.downloadRequest = UUID(); self.downloadJob = nil; self.downloadSheet = nil
                self.status.stringValue = "Download cancelled."
            }
        }
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/GLoop", isDirectory: true)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try job.run(request, root: root) { text in
                DispatchQueue.main.async { if self?.downloadRequest == token { self?.downloadSheet?.informativeText = text } }
            } }
            DispatchQueue.main.async {
                guard let self, self.downloadRequest == token else { return }
                self.window.endSheet(sheet.window, returnCode: .OK); self.downloadJob = nil; self.downloadSheet = nil
                switch result {
                case .success(let media): self.importPracticeVideo(media, request: request)
                case .failure(let error): self.showImportError(error)
                }
            }
        }
    }
    func importPracticeVideo(_ url: URL, request: PracticeHandoff) {
        if !["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased()) { offerConversion(url, handoff: request); return }
        status.stringValue = "Reading video…"
        let token = UUID(); downloadRequest = token
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { () -> (Double, ClipSettings) in
                let duration = try VideoDownload.duration(url)
                return (duration, try request.settings(duration: duration))
            }
            DispatchQueue.main.async {
                guard let self, self.downloadRequest == token else { return }
                switch result {
                case .failure(let error): self.showImportError(error)
                case .success(let (length, settings)):
                    self.save()
                    let clip = self.clips.first(where: { $0.path == url.path }) ?? Clip(title: request.title.isEmpty ? url.deletingPathExtension().lastPathComponent : request.title, song: "YouTube", path: url.path, duration: length)
                    if !self.clips.contains(where: { $0.path == url.path }) { self.clips.append(clip); self.saved.imports.append(clip) }
                    if self.selected?.path == clip.path { self.prefs = settings }
                    self.saved.settings[clip.path] = settings
                    self.saved.hiddenPaths?.removeAll { $0 == clip.path }
                    if self.song.item(withTitle: clip.song) == nil { self.song.addItem(withTitle: clip.song) }
                    self.song.selectItem(withTitle: "All songs"); self.search.stringValue = ""; self.filter(); self.load(clip)
                }
            }
        }
    }
    func importVideo(_ url: URL) {
        guard downloadJob == nil else { status.stringValue = "Finish the current import first."; return }
        guard url.isFileURL else { return }
        if url.pathExtension.lowercased() == "gloop" { openHandoff(url); return }
        guard !url.hasDirectoryPath else { return }
        guard FileManager.default.isReadableFile(atPath: url.path) else { status.stringValue = "This file could not be read. Check its location and permissions."; return }
        if !["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased()) { offerConversion(url); return }
        saved.hiddenPaths?.removeAll { $0 == url.path }
        if let c = clips.first(where: { $0.path == url.path }) { load(c); return }
        let token = UUID(); importRequest = token; status.stringValue = "Reading video…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try NativeAudio.duration(url) }
            DispatchQueue.main.async {
                guard let self, self.importRequest == token else { return }
                switch result {
                case .failure(let error): self.showImportError(error)
                case .success(let length):
                    let c = Clip(title: url.deletingPathExtension().lastPathComponent, song: "Imported videos", path: url.path, duration: length)
                    self.clips.append(c); self.saved.imports.append(c)
                    if self.song.item(withTitle: c.song) == nil { self.song.addItem(withTitle: c.song) }
                    self.song.selectItem(withTitle: "All songs"); self.search.stringValue = ""; self.filter(); self.load(c)
                }
            }
        }
    }
    func key(_ e: NSEvent) -> NSEvent? {
        guard e.window === window else { return e }
        if e.modifierFlags.contains(.command) || e.modifierFlags.contains(.control) { return e }
        if window.firstResponder is NSTextView || waveform.isInteracting { return e }
        switch e.keyCode {
        case 49: togglePlay()
        case 123: seek(position()-(e.modifierFlags.contains(.shift) ? 5 : 1))
        case 124: seek(position()+(e.modifierFlags.contains(.shift) ? 5 : 1))
        default:
            switch e.charactersIgnoringModifiers?.lowercased() {
            case "a": setA()
            case "b": setB()
            case "[": slower()
            case "]": faster()
            case "0": normalSpeed()
            case "l": loopCheck.state = loopCheck.state == .on ? .off : .on; loopChanged()
            case "n": next()
            case "p": previous()
            default: return e
            }
        }
        return nil
    }
    func save() {
        guard !smoke && !uiTest && !persistenceBlocked else { return }
        if let selected { saved.settings[selected.path] = prefs }
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.persistState() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }
    func persistState() {
        guard !smoke && !uiTest && !persistenceBlocked else { return }
        do { try StateStore.save(saved, to: stateURL) }
        catch { status.stringValue = "Could not save settings. Check free space and access to Application Support/GLoop." }
    }
    @objc func revealVideo() { if let selected { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: selected.path)]) } }
    @objc func removeFromLibrary() {
        guard let selected else { return }
        sampleStats(); persistStats(); stats.select(nil); refreshStatsUI()
        waveform.clear("Open a video to see its waveform."); waveWasPlaying = false
        save(); smooth.clear(); player.stop(); player.av.replaceCurrentItem(with: nil); metronome.reset()
        audioRequest = UUID(); bpmRequest = UUID(); importRequest = UUID(); audioBusy = false; bpmBusy = false
        clips.removeAll { $0.path == selected.path }; saved.imports.removeAll { $0.path == selected.path }
        if saved.hiddenPaths == nil { saved.hiddenPaths = [] }; saved.hiddenPaths!.append(selected.path)
        self.selected = nil; aiTrimWindow?.clipDidChange(); refreshStatsUI(); saved.lastPath = nil; duration = 0; prefs = ClipSettings(); counter.reset()
        titleLabel.stringValue = "Choose a video"; subtitle.stringValue = ""; filter(); updateControls(); save()
        status.stringValue = "Removed from library. The video file is unchanged."
    }
    @objc func quickStart() {
        let alert = NSAlert(); alert.messageText = "Practice a phrase"
        alert.informativeText = "1. Open an MP4 or MOV video.\n2. Set A and B around the phrase.\n3. Choose a speed and press Space.\n4. Turn on Auto speed to add 1% or 5% each loop.\n\nA / B: set markers · [ / ]: change speed\n\nBPM detection and the metronome work offline. YouTube downloads and other-format conversion need optional tools. No account or activation is required."
        alert.beginSheetModal(for: window)
    }
    @objc func about() { let a = NSAlert(); a.messageText = "GLoop"; let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "3.0"; a.informativeText = "Guitar practice player\nVersion \(version)\n\nVideo and audio: Apple AVFoundation\nOpen source · MIT license\nNo account or activation"; a.runModal() }
    func finishSmoke(failed: Bool = false) {
        let expected: [Float] = smokeRampOne ? [0.9,0.91,0.92,0.93,0.94] : smokeRamp ? [0.9,0.95,1,1,1] : [0.75,0.75,0.75,0.75,0.75]
        let ratesOK = smokeRates.count == expected.count && zip(smokeRates,expected).allSatisfy { abs($0 - $1) < 0.001 }
        let statsLoops = stats.data.sessions.flatMap(\.loops)
        let statsOK = statsLoops.count == 5 && zip(statsLoops,expected).allSatisfy { abs($0.lowSpeed-Double($1)) < 0.001 && abs($0.highSpeed-Double($1)) < 0.001 }
        let pitchOK = smokePitches.count == 5 && smokePitches.allSatisfy { $0 == smokePitch }
        let report: [String:Any] = ["pitchOK":pitchOK,"pitchSemitones":smokePitches,"statsLoops":statsLoops.count,"statsSeconds":stats.data.sessions.reduce(0) { $0+$1.seconds },"statsOK":statsOK,"success": !failed && statsOK && ratesOK && pitchOK && (!smokeRampOne || (metronome.scheduledCount > 0 && !metronome.isPlaying && metronome.failure == nil && abs(metronome.lastInterval - 60/(120*0.94)) < 0.001)) && smooth.ready && smooth.completed == 5 && counter.completed == 5 && counter.finished && smokeVout > 0,"metronomeClicksScheduled":metronome.scheduledCount,"lastClickInterval":metronome.lastInterval,"metronomeStopped":!metronome.isPlaying,"rates":smokeRates,"completed": counter.completed,"finished": counter.finished,"rate":smokeRate,"smoothAudio": smooth.ready,"audioCompleted": smooth.completed,"videoOutputs": smokeVout,"duration":duration]
        if let data = try? JSONSerialization.data(withJSONObject: report,options: .prettyPrinted) { try? data.write(to: support.appendingPathComponent(smokeRampOne ? "smoke-ramp1.json" : smokeRamp ? "smoke-ramp.json" : "smoke-test.json")) }
        NSApp.terminate(nil)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { aiTrimWindow?.shutdown(); sampleStats(); persistStats(wait: true); downloadJob?.cancel(); save(); pendingSave?.cancel(); persistState(); audioRequest = UUID(); smooth.shutdown(); metronome.shutdown(); timer?.invalidate(); if let keys { NSEvent.removeMonitor(keys) }; player.shutdown() }
}
extension NSBox { static func separator() -> NSBox { let box = NSBox(); box.boxType = .separator; return box } }

if ProcessInfo.processInfo.arguments.contains("--acp-test-agent") { runACPFixture(); exit(0) }
if ProcessInfo.processInfo.arguments.contains("--acp-test") { try runACPTests(); exit(0) }
if ProcessInfo.processInfo.arguments.contains("--stats-test") { try practiceStatsTests(); exit(0) }
if ProcessInfo.processInfo.arguments.contains("--waveform-test") { try waveformTests(); exit(0) }
if ProcessInfo.processInfo.arguments.contains("--pitch-test") { try GaplessAudio.pitchTest(); exit(0) }
if ProcessInfo.processInfo.arguments.contains("--gapless-test") { try GaplessAudio.selfTest(); exit(0) }
if ProcessInfo.processInfo.arguments.contains("--handoff-test") { try PracticeHandoff.selfTest(); exit(0) }
if ProcessInfo.processInfo.arguments.contains("--state-test") { try StateStore.selfTest(); exit(0) }
if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--media-test"), index + 1 < ProcessInfo.processInfo.arguments.count {
    try ReleaseTests.media(URL(fileURLWithPath: ProcessInfo.processInfo.arguments[index + 1])); exit(0)
}
if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--conversion-test"), index + 2 < ProcessInfo.processInfo.arguments.count {
    let output = try VideoDownload().convert(URL(fileURLWithPath: ProcessInfo.processInfo.arguments[index + 1]), root: URL(fileURLWithPath: ProcessInfo.processInfo.arguments[index + 2]))
    try ReleaseTests.media(output); print("Converted: \(output.path)"); exit(0)
}
if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--handoff-download"), index + 2 < ProcessInfo.processInfo.arguments.count {
    do {
        let request = try PracticeHandoff.read(URL(fileURLWithPath: ProcessInfo.processInfo.arguments[index + 1]))
        let media = try VideoDownload().run(request, root: URL(fileURLWithPath: ProcessInfo.processInfo.arguments[index + 2], isDirectory: true)) { print($0) }
        let settings = try request.settings(duration: VideoDownload.duration(media))
        print("Downloaded: \(media.path)"); print("Practice: \(stamp(settings.a, precise: true))–\(stamp(settings.b ?? 0, precise: true)), \(Int(settings.speed * 100))%, +\(request.increment)%")
        exit(0)
    } catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
}
if ProcessInfo.processInfo.arguments.contains("--metronome-test") { try PracticeMetronome.selfTest(); exit(0) }
if ProcessInfo.processInfo.arguments.contains("--bpm-test") { try BPMDetector.selfTest(); exit(0) }
if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--detect-bpm"), index+1 < ProcessInfo.processInfo.arguments.count {
    do { let r = try BPMDetector.detect(path: ProcessInfo.processInfo.arguments[index+1]); print("BPM: \(r.bpm), strength: \(r.strength), seconds: \(r.seconds)"); exit(0) }
    catch { print(error.localizedDescription); exit(1) }
}
if ProcessInfo.processInfo.arguments.contains("--self-test") { runCoreTests(); exit(0) }
let application = NSApplication.shared
application.setActivationPolicy(.regular)
let delegate = PlayerApp()
application.delegate = delegate
application.run()
