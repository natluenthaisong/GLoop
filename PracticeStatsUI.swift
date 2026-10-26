import AppKit

func practiceDuration(_ seconds: Double) -> String {
    let value = max(0,Int(seconds))
    return value >= 3600 ? "\(value/3600)h \((value%3600)/60)m" : "\(value/60)m \(value%60)s"
}
func practiceSpeed(_ low: Double, _ high: Double? = nil) -> String {
    let a = Int((low*100).rounded()), b = Int(((high ?? low)*100).rounded())
    return a == b ? "\(a)%" : "\(a)–\(b)%"
}

final class PracticeStatsWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    let recorder: PracticeStats
    let summary = NSTextField(labelWithString: "")
    let today = NSTextField(labelWithString: "")
    let message = NSTextField(wrappingLabelWithString: "")
    let empty = NSTextField(wrappingLabelWithString: "")
    let scope = NSPopUpButton()
    let tabs = NSSegmentedControl(labels: ["Sessions","Speed history","Completed loops"],trackingMode: .selectOne,target: nil,action: nil)
    let table = NSTableView()
    var rows: [[String]] = []
    var selectedPath: String?
    var storageNotice: String?
    let dateFormat: DateFormatter = { let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short; return f }()
    init(recorder: PracticeStats) {
        self.recorder = recorder
        let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 900,height: 550),styleMask: [.titled,.closable,.miniaturizable,.resizable],backing: .buffered,defer: false)
        super.init(window: window)
        window.title = "Practice Stats"; window.minSize = NSSize(width: 760,height: 440); window.isReleasedWhenClosed = false
        let root = StudioSurface(GLoopTheme.canvas); window.contentView = root
        scope.addItems(withTitles: ["All clips","Current clip"]); scope.target = self; scope.action = #selector(rebuild); scope.setAccessibilityLabel("Practice stats scope")
        tabs.selectedSegment = 0; tabs.target = self; tabs.action = #selector(rebuild); tabs.setAccessibilityLabel("Practice history type")
        summary.font = .monospacedDigitSystemFont(ofSize: 18,weight: .semibold)
        today.font = .systemFont(ofSize: 13); today.textColor = GLoopTheme.muted
        message.font = .systemFont(ofSize: 12); message.textColor = GLoopTheme.muted
        empty.font = .systemFont(ofSize: 14); empty.textColor = GLoopTheme.muted; empty.alignment = .center
        table.headerView = NSTableHeaderView(); table.rowHeight = 30; table.style = .plain
        table.delegate = self; table.dataSource = self; table.usesAlternatingRowBackgroundColors = true
        table.setAccessibilityLabel("Practice history")
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        for v in [scope,tabs,summary,today,scroll,message,empty] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
        NSLayoutConstraint.activate([
            scope.topAnchor.constraint(equalTo: root.topAnchor,constant: 20),scope.trailingAnchor.constraint(equalTo: root.trailingAnchor,constant: -20),
            summary.topAnchor.constraint(equalTo: root.topAnchor,constant: 22),summary.leadingAnchor.constraint(equalTo: root.leadingAnchor,constant: 20),summary.trailingAnchor.constraint(lessThanOrEqualTo: scope.leadingAnchor,constant: -16),
            today.topAnchor.constraint(equalTo: summary.bottomAnchor,constant: 10),today.leadingAnchor.constraint(equalTo: summary.leadingAnchor),
            tabs.topAnchor.constraint(equalTo: today.bottomAnchor,constant: 24),tabs.leadingAnchor.constraint(equalTo: summary.leadingAnchor),
            scroll.topAnchor.constraint(equalTo: tabs.bottomAnchor,constant: 14),scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor,constant: 20),scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor,constant: -20),scroll.bottomAnchor.constraint(equalTo: message.topAnchor,constant: -16),
            message.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),message.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),message.bottomAnchor.constraint(equalTo: root.bottomAnchor,constant: -20),
            empty.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),empty.widthAnchor.constraint(lessThanOrEqualTo: scroll.widthAnchor,constant: -40)
        ])
        window.center(); rebuild()
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc func rebuild() {
        for c in table.tableColumns { table.removeTableColumn(c) }
        let headings: [(String,CGFloat)]
        switch tabs.selectedSegment {
        case 1: headings = [("Started",145),("Section",250),("A–B",145),("Speed",75),("Time",100)]
        case 2: headings = [("Finished",145),("Section",250),("A–B",145),("Speed",85),("Clean",75)]
        default: headings = [("Started",145),("Section",250),("Time",100),("Loops",70),("Clean",70)]
        }
        for (i,h) in headings.enumerated() {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(String(i))); c.title = h.0; c.width = h.1; c.minWidth = 55; table.addTableColumn(c)
        }
        refresh()
    }
    func refresh() {
        let sessions = recorder.data.sessions.filter { scope.indexOfSelectedItem == 0 || $0.clip.path == selectedPath }
        let seconds = sessions.reduce(0) { $0+$1.seconds }, loops = sessions.flatMap(\.loops)
        summary.stringValue = "\(practiceDuration(seconds))   ·   \(loops.count) loops   ·   \(loops.filter(\.clean).count) clean"
        let start = Calendar.current.startOfDay(for: Date())
        let todaySeconds = sessions.flatMap(\.speeds).filter { $0.date >= start }.reduce(0) { $0+$1.seconds }
        today.stringValue = "Today: \(practiceDuration(todaySeconds))   ·   Total above includes all recorded practice"
        var result: [[String]] = []
        for s in sessions.reversed() {
            let name = s.clip.song + " · " + s.clip.title
            switch tabs.selectedSegment {
            case 1:
                for p in s.speeds.reversed() { result.append([dateFormat.string(from: p.date),name,stamp(p.a,precise: true)+"–"+stamp(p.b,precise: true),practiceSpeed(p.speed),practiceDuration(p.seconds)]); if result.count >= 300 { break } }
            case 2:
                for p in s.loops.reversed() { result.append([dateFormat.string(from: p.date),name,stamp(p.a,precise: true)+"–"+stamp(p.b,precise: true),practiceSpeed(p.lowSpeed,p.highSpeed),p.clean ? "Yes" : "—"]); if result.count >= 300 { break } }
            default: result.append([dateFormat.string(from: s.started),name,practiceDuration(s.seconds),String(s.loops.count),String(s.loops.filter(\.clean).count)])
            }
            if result.count >= 300 { break }
        }
        rows = result; table.reloadData(); empty.isHidden = !rows.isEmpty
        empty.stringValue = tabs.selectedSegment == 2 ? "Complete an A–B loop to see it here.\nUse Played cleanly to mark your last completed loop." : "No practice recorded yet.\nPlay a section to start tracking."
        message.stringValue = storageNotice ?? "Saved only on this Mac. Clean marks are your own assessment. History shows the latest 300 entries; totals include all entries."
    }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn, let i = Int(column.identifier.rawValue), rows.indices.contains(row), rows[row].indices.contains(i) else { return nil }
        let cell = NSTextField(labelWithString: rows[row][i]); cell.font = .systemFont(ofSize: 12); cell.lineBreakMode = .byTruncatingTail; cell.toolTip = rows[row][i]; return cell
    }
}

extension PlayerApp {
    func setupStats() {
        statsStore = PracticeStatsStore(url: uiTest || smoke || measuring ? nil : support.appendingPathComponent("PracticeStats.json"))
        stats.data = statsStore.load()
        statsStore.onError = { [weak self] message in
            self?.statsStore.notice = message; self?.stats.changed = true
            self?.status.stringValue = message; self?.refreshStatsUI()
        }
    }
    func sampleStats() {
        guard selected != nil else { return }
        let running = isPlaying && !pendingPause && !audioBusy && !counter.finished && (smooth.ready || now > seekingUntil)
        let media: Double
        if smooth.ready {
            let length = max(0,(prefs.b ?? duration)-prefs.a)
            let cap = prefs.target > 0 && prefs.looping ? statsFirstLength + Double(max(0,prefs.target-statsStartingCount-1))*length : (prefs.looping ? Double.greatestFiniteMagnitude : statsFirstLength)
            media = min(smooth.consumed,cap)
        } else { media = player.time }
        stats.sample(wall: now,media: media,running: running,speed: prefs.speed)
        if now-statsUIAt >= 1 { statsUIAt = now; refreshStatsUI() }
        if now-statsSavedAt >= 10 { persistStats() }
    }
    func prepareStats(at position: Double) {
        stats.prepare(a: prefs.a,b: min(duration,prefs.b ?? duration),position: position,speed: prefs.speed)
        statsFirstLength = max(0,min(duration,prefs.b ?? duration)-position); statsStartingCount = counter.completed
    }
    func persistStats(wait: Bool = false) {
        statsSavedAt = now
        if stats.changed { statsStore.save(stats.data,wait: wait); stats.changed = false }
        else if wait { statsStore.save(stats.data,wait: true) }
    }
    func refreshStatsUI() {
        let last = stats.latestLoop
        cleanButton.isEnabled = last != nil && last?.clean == false
        undoCleanButton.isEnabled = stats.canUndoClean
        cleanButton.title = last?.clean == true ? "Marked clean" : "Played cleanly"
        cleanButton.toolTip = last.map { "Mark your last completed loop at \(practiceSpeed($0.lowSpeed,$0.highSpeed)), \(stamp($0.a,precise: true))–\(stamp($0.b,precise: true))." } ?? "Complete a full A–B loop first. Seeks and partial loops do not count."
        statsWindow?.selectedPath = selected?.path; statsWindow?.storageNotice = statsStore.notice
        if statsWindow?.window?.isVisible == true { statsWindow?.refresh() }
    }
    @objc func markPlayedCleanly() { if stats.markClean(true) { persistStats(); refreshStatsUI() } }
    @objc func undoPlayedCleanly() { if stats.undoCleanMark() { persistStats(); refreshStatsUI() } }
    @objc func showPracticeStats() {
        if statsWindow == nil {
            statsWindow = PracticeStatsWindow(recorder: stats)
            if uiTest && ProcessInfo.processInfo.arguments.contains("--ui-test-small") { statsWindow?.window?.setContentSize(NSSize(width: 760,height: 440)) }
        }
        statsWindow?.window?.appearance = window.appearance
        statsWindow?.showWindow(nil); refreshStatsUI()
    }
}
