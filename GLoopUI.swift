import AppKit

enum GLoopTheme {
    static func color(_ dark: UInt32, _ light: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua,.aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex>>16)&255)/255, green: CGFloat((hex>>8)&255)/255, blue: CGFloat(hex&255)/255, alpha: 1)
        }
    }
    static let canvas = color(0x202020,0xFAFAFA)
    static let surface = color(0x252525,0xFFFFFF)
    static let sidebar = color(0x272727,0xF0F0F0)
    static let border = color(0x454545,0xD0D0D0)
    static let text = color(0xF0F0F0,0x222222)
    static let muted = color(0xB0B0B0,0x595959)
    static let accent = color(0xA8C8EF,0x245B9A)
    static let onAccent = color(0x17220F,0xFFFFFF)
}
final class StudioSurface: NSView {
    let fill: NSColor
    var radius: CGFloat
    var bordered: Bool
    init(_ fill: NSColor, radius: CGFloat = 0, bordered: Bool = false) {
        self.fill = fill; self.radius = radius; self.bordered = bordered
        super.init(frame: .zero); wantsLayer = true; clipsToBounds = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        fill.setFill(); let shape = NSBezierPath(roundedRect: bounds,xRadius: radius,yRadius: radius); shape.fill()
        if bordered { GLoopTheme.border.setStroke(); let stroke = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5,dy: 0.5),xRadius: radius,yRadius: radius); stroke.lineWidth = 1; stroke.stroke() }
    }
}
extension PlayerApp {
    func section(_ name: String, _ description: String? = nil, _ contents: [NSView]) -> NSView {
        let stack = col([label(name,13,.semibold)] + contents + [NSBox.separator()],spacing: 10)
        for item in stack.arrangedSubviews { item.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return stack
    }
    func muted(_ text: String) -> NSTextField { let view = label(text,12); view.textColor = GLoopTheme.muted; return view }
    func fieldLabel(_ text: String, _ field: NSView) -> NSStackView { col([muted(text),field],spacing: 6) }
    func fillRow(_ items: [NSView]) -> NSStackView { let stack = row(items,spacing: 8); stack.distribution = .fillEqually; return stack }
    func makeInspector() -> NSView {
        speed.target = self; speed.action = #selector(speedChanged); speed.isContinuous = true; speed.setAccessibilityLabel("Playback speed percent")
        speedLabel.font = .monospacedDigitSystemFont(ofSize: 24,weight: .medium); speedLabel.textColor = GLoopTheme.text
        let headline = row([speedLabel,flexible()]); speedLabel.toolTip = "Playback speed; pitch stays unchanged. [ and ] change it by 5%, Shift+[ and Shift+] by 1%."
        let speedSlider = row([button("−",#selector(slower)),speed,button("+",#selector(faster))],spacing: 6)
        speed.setContentHuggingPriority(.init(1),for: .horizontal); speed.numberOfTickMarks = 0
        autoIncrease.target = self; autoIncrease.action = #selector(autoIncreaseChanged); autoIncrease.font = .systemFont(ofSize: 13)
        autoIncrease.toolTip = "Raise speed on every loop, up to 100%."
        speedStep.addItems(withTitles: ["+1% / loop","+5% / loop"]); speedStep.target = self; speedStep.action = #selector(speedStepChanged); speedStep.setAccessibilityLabel("Auto speed increment")
        let tempoCard = section("Speed",nil,[headline,speedSlider,fillRow([button("50%",#selector(halfSpeed)),button("75%",#selector(threeQuarter)),button("100%",#selector(normalSpeed))]),row([autoIncrease,flexible(),speedStep])])
        for (control,action,name) in [(pitchDown,#selector(lowerPitch),"Lower pitch one semitone"),(pitchUp,#selector(raisePitch),"Raise pitch one semitone"),(pitchReset,#selector(resetPitch),"Reset to original pitch")] {
            control.target = self; control.action = action; control.bezelStyle = .rounded; control.setAccessibilityLabel(name)
        }
        width(pitchDown,30); width(pitchUp,30)
        pitchLabel.font = .monospacedDigitSystemFont(ofSize: 14,weight: .medium); pitchLabel.alignment = .center
        pitchLabel.setContentHuggingPriority(.init(1),for: .horizontal); pitchLabel.setAccessibilityLabel("Pitch shift"); pitchLabel.toolTip = "Changes audio pitch only. Video and tablature stay unchanged; playback speed is independent."
        pitchNote.font = .systemFont(ofSize: 12); pitchNote.textColor = GLoopTheme.muted; pitchNote.maximumNumberOfLines = 2; pitchNote.lineBreakMode = .byWordWrapping
        let pitchSection = section("Pitch",nil,[row([pitchDown,pitchLabel,pitchUp,pitchReset],spacing: 8),pitchNote])
        for (field,name) in [(aField,"Loop start A"),(bField,"Loop end B")] { field.font = .monospacedDigitSystemFont(ofSize: 13,weight: .regular); field.alignment = .center; field.target = self; field.action = #selector(markersEdited); field.delegate = self; field.setAccessibilityLabel(name); field.toolTip = "Type m:ss.mmm and press Return. Up and Down arrows nudge by 0.05 s, with Shift by 0.5 s." }
        let start = col([row([label("A",12,.semibold),flexible(),button("Set here",#selector(setA))]),aField],spacing: 8)
        let end = col([row([label("B",12,.semibold),flexible(),button("Set here",#selector(setB))]),bField],spacing: 8)
        aField.widthAnchor.constraint(equalTo: start.widthAnchor).isActive = true; bField.widthAnchor.constraint(equalTo: end.widthAnchor).isActive = true
        loopCheck.title = "Repeat"; loopCheck.target = self; loopCheck.action = #selector(loopChanged)
        repeatMenu.addItems(withTitles: ["Unlimited","5 plays","10 plays","30 plays","50 plays"]); repeatMenu.selectItem(at: 3); repeatMenu.target = self; repeatMenu.action = #selector(repeatChanged); repeatMenu.setAccessibilityLabel("Repeat target")
        progress.font = .monospacedDigitSystemFont(ofSize: 14,weight: .medium); progress.textColor = GLoopTheme.text
        let loopCard = section("Loop",nil,[fillRow([start,end]),row([loopCheck,flexible(),button("Whole clip",#selector(clearMarkers))]),row([muted("Plays"),flexible(),repeatMenu]),progress])
        detectBPMButton.title = "Detect BPM"; detectBPMButton.target = self; detectBPMButton.action = #selector(detectBPM); detectBPMButton.bezelStyle = .rounded
        bpmField.placeholderString = "—"; bpmField.alignment = .center; bpmField.font = .monospacedDigitSystemFont(ofSize: 16,weight: .medium); width(bpmField,74)
        bpmField.target = self; bpmField.action = #selector(bpmEdited); bpmField.delegate = self; bpmField.setAccessibilityLabel("Original BPM"); bpmField.toolTip = "Original tempo at 100% speed. Enter a number and press Return."
        effectiveBPM.font = .monospacedDigitSystemFont(ofSize: 15,weight: .medium); effectiveBPM.textColor = GLoopTheme.text
        bpmNote.font = .systemFont(ofSize: 12); bpmNote.textColor = GLoopTheme.muted; bpmNote.maximumNumberOfLines = 2; bpmNote.lineBreakMode = .byWordWrapping
        let bpmCard = section("Tempo",nil,[row([muted("Original BPM"),flexible(),bpmField]),fillRow([detectBPMButton,button("÷2",#selector(halfBPM)),button("×2",#selector(doubleBPM))]),effectiveBPM,bpmNote])
        metroCheck.title = "On"; metroCheck.target = self; metroCheck.action = #selector(metroChanged)
        clickVolume.target = self; clickVolume.action = #selector(clickVolumeChanged); clickVolume.setAccessibilityLabel("Metronome volume percent")
        beatField.font = .monospacedDigitSystemFont(ofSize: 13,weight: .regular); beatField.target = self; beatField.action = #selector(beatEdited); beatField.delegate = self; beatField.setAccessibilityLabel("Beat anchor time")
        metroStatus.font = .systemFont(ofSize: 12); metroStatus.textColor = GLoopTheme.muted; metroStatus.maximumNumberOfLines = 2; metroStatus.lineBreakMode = .byWordWrapping
        alignmentControls = col([fieldLabel("Beat position (m:ss.mmm)",beatField),fillRow([button("Align here",#selector(alignBeat)),button("Beat at A",#selector(beatAtA))])],spacing: 12)
        for child in alignmentControls.arrangedSubviews { child.widthAnchor.constraint(equalTo: alignmentControls.widthAnchor).isActive = true }
        beatField.widthAnchor.constraint(equalTo: alignmentControls.widthAnchor).isActive = true
        alignmentControls.isHidden = true
        alignmentToggle.title = ""; alignmentToggle.setButtonType(.pushOnPushOff); alignmentToggle.bezelStyle = .disclosure; alignmentToggle.target = self; alignmentToggle.action = #selector(toggleAlignment); alignmentToggle.setAccessibilityLabel("Show beat alignment"); width(alignmentToggle,16)
        let metroCard = section("Metronome",nil,[row([metroCheck,flexible()]),row([muted("Volume"),clickVolume]),metroStatus,row([alignmentToggle,muted("Beat alignment"),flexible()]),alignmentControls])
        let stack = col([tempoCard,pitchSection,loopCard,bpmCard,metroCard],spacing: 16)
        for item in stack.arrangedSubviews { item.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        let document = TopDownView(); stack.translatesAutoresizingMaskIntoConstraints = false; document.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: document.leadingAnchor,constant: 16),stack.trailingAnchor.constraint(equalTo: document.trailingAnchor,constant: -16),stack.topAnchor.constraint(equalTo: document.topAnchor,constant: 24),stack.bottomAnchor.constraint(equalTo: document.bottomAnchor,constant: -24)])
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.documentView = document
        document.translatesAutoresizingMaskIntoConstraints = false
        document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        return scroll
    }
    func updatePitchControls() {
        let shift = prefs.pitchShift
        let available = selected != nil && smooth.ready && !audioBusy
        pitchLabel.stringValue = shift == 0 ? "Original" : "\(shift > 0 ? "+" : "−")\(abs(shift)) \(abs(shift) == 1 ? "semitone" : "semitones")"
        pitchDown.isEnabled = available && shift > -12; pitchUp.isEnabled = available && shift < 12
        pitchReset.isEnabled = available && shift != 0
        if selected == nil { pitchNote.stringValue = "Open a video to change its pitch." }
        else if audioBusy { pitchNote.stringValue = "Loading audio…" }
        else if !smooth.ready { pitchNote.stringValue = "Pitch unavailable; playing original audio." }
        else if shift == -1 { pitchNote.stringValue = "Half step down · E → E♭" }
        else if shift == 1 { pitchNote.stringValue = "Half step up · E♭ → E" }
        else { pitchNote.stringValue = "−1: E → E♭   +1: E♭ → E" }
    }
    func setPitch(_ semitones: Int) {
        guard selected != nil, smooth.ready, !audioBusy else { return }
        prefs.pitchSemitones = min(12,max(-12,semitones))
        smooth.pitchSemitones = prefs.pitchShift
        updatePitchControls(); save()
    }
    @objc func lowerPitch() { setPitch(prefs.pitchShift-1) }
    @objc func raisePitch() { setPitch(prefs.pitchShift+1) }
    @objc func resetPitch() { setPitch(0) }
    @objc func toggleAlignment() {
        alignmentControls.isHidden = alignmentToggle.state != .on
        alignmentToggle.setAccessibilityLabel(alignmentControls.isHidden ? "Show beat alignment" : "Hide beat alignment")
    }
    @objc func selectAppearance(_ item: NSMenuItem) {
        if !uiTest { UserDefaults.standard.set(item.tag,forKey: "appearance") }
        applyAppearance(choice: item.tag)
    }
    func applyAppearance(choice requested: Int? = nil) {
        let choice = requested ?? (UserDefaults.standard.object(forKey: "appearance") as? Int ?? 1)
        window.appearance = choice == 0 ? nil : NSAppearance(named: choice == 1 ? .darkAqua : .aqua)
        statsWindow?.window?.appearance = window.appearance
        aiTrimWindow?.window?.appearance = window.appearance
        window.backgroundColor = GLoopTheme.canvas
        for item in appearanceMenu.items { item.state = item.tag == choice ? .on : .off }
        window.contentView?.needsDisplay = true
    }
}
final class TopDownView: NSView { override var isFlipped: Bool { true } }
final class GLoopRow: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        GLoopTheme.accent.withAlphaComponent(0.13).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4,dy: 3),xRadius: 3,yRadius: 3).fill()
    }
}
