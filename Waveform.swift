import AppKit
import AVFoundation
import Accelerate

/// A bounded peak envelope, reduced across channels without cancelling opposite phases.
struct WaveformEnvelope {
    let peaks: [Float]
    let duration: Double
    let binDuration: Double
    init(_ pcm: AVAudioPCMBuffer) {
        let frames = Int(pcm.frameLength)
        duration = Double(frames)/pcm.format.sampleRate
        let stride = max(1,(frames+16383)/16384)
        binDuration = Double(stride)/pcm.format.sampleRate
        guard frames > 0, let channels = pcm.floatChannelData else { peaks = []; return }
        var values = [Float](); values.reserveCapacity((frames+stride-1)/stride)
        for start in Swift.stride(from: 0,to: frames,by: stride) {
            let count = min(stride,frames-start)
            var peak: Float = 0
            for c in 0..<Int(pcm.format.channelCount) {
                var value: Float = 0
                vDSP_maxmgv(channels[c]+start,1,&value,vDSP_Length(count))
                if value.isFinite { peak = max(peak,value) }
            }
            values.append(peak)
        }
        peaks = values
    }
}

struct WaveformScale {
    var duration: Double = 0
    var lower: Double = 0
    var upper: Double = 0
    var span: Double { max(0.000001,upper-lower) }
    func time(at fraction: Double) -> Double { lower+min(1,max(0,fraction.isFinite ? fraction : 0))*span }
    func fraction(at time: Double) -> Double { (time-lower)/span }
    mutating func fit() { lower = 0; upper = max(0,duration) }
    mutating func zoom(a: Double,b: Double) {
        let padding = max(0.08,(b-a)*0.2)
        lower = max(0,a-padding); upper = min(duration,b+padding)
    }
    static func selection(_ from: Double,_ to: Double,duration: Double) -> (Double,Double)? {
        guard from.isFinite, to.isFinite, duration.isFinite, duration >= 0.16 else { return nil }
        let a = max(0,min(duration,min(from,to))), b = max(0,min(duration,max(from,to)))
        return b-a >= 0.16 ? (a,b) : nil
    }
}

final class WaveformView: NSView {
    var onBegin: (() -> Void)?
    var onPreview: ((Double,Double) -> Void)?
    var onSelect: ((Double,Double) -> Void)?
    var onSeek: ((Double) -> Void)?
    var onCancel: (() -> Void)?
    var scale = WaveformScale()
    var loopA = 0.0, loopB = 0.0
    var repeating = true
    var message = "Open a video to see its waveform."
    private var envelope: WaveformEnvelope?
    private var cachedPath: NSBezierPath?
    private var cachedWidth: CGFloat = 0
    private var head = 0.0
    private var lastHeadX: CGFloat = -1
    private enum Drag: Equatable { case start, end, selection }
    private var drag: Drag?
    private var downPoint = NSPoint.zero
    private var downTime = 0.0
    private var original = (0.0,0.0)
    private var moved = false
    var isInteracting: Bool { drag != nil }
    var available: Bool { envelope != nil && scale.duration >= 0.16 }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true); setAccessibilityRole(.image); setAccessibilityLabel("Audio waveform and loop markers")
        toolTip = "Drag across the waveform to select a loop. Drag A or B to adjust it. Click inside the loop to seek. Escape cancels a drag. You can also edit the A/B time fields."
        setAccessibilityHelp(toolTip)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func accessibilityValue() -> Any? {
        available ? "Loop A \(stamp(loopA,precise: true)), B \(stamp(loopB,precise: true)). Playback \(stamp(head,precise: true))." : message
    }
    func clear(_ text: String) {
        drag = nil; envelope = nil; scale = WaveformScale(); loopA = 0; loopB = 0
        head = 0; cachedPath = nil; message = text; needsDisplay = true
    }
    func install(_ value: WaveformEnvelope) {
        envelope = value; scale.duration = value.duration; scale.fit(); cachedPath = nil
        message = value.peaks.isEmpty ? "No audio waveform available." : ""; needsDisplay = true
    }
    func update(a: Double,b: Double,repeating: Bool) {
        guard !isInteracting else { return }
        if loopA != a || loopB != b || self.repeating != repeating {
            loopA = a; loopB = b; self.repeating = repeating; needsDisplay = true
        }
    }
    func setPlayhead(_ time: Double) {
        head = time
        let x = xAt(time)
        // Do not repaint a static or subpixel-moving waveform at the player's 67 Hz timer rate.
        if abs(x-lastHeadX) >= 1 { lastHeadX = x; needsDisplay = true }
    }
    func aiSummary() -> [Double] {
        guard let envelope, !envelope.peaks.isEmpty else { return [] }
        let n = envelope.peaks.count, count = min(512,n)
        return (0..<count).map { i in
            let lo = i*n/count, hi = max(lo+1,(i+1)*n/count)
            return Double(((envelope.peaks[lo..<hi].max() ?? 0)*10000).rounded())/10000
        }
    }
    func fit() { scale.fit(); cachedPath = nil; needsDisplay = true }
    func zoomToLoop() { guard available else { return }; scale.zoom(a: loopA,b: loopB); cachedPath = nil; needsDisplay = true }
    private var plot: NSRect { NSRect(x: 12,y: 22,width: max(1,bounds.width-24),height: max(1,bounds.height-44)) }
    private func xAt(_ time: Double) -> CGFloat { plot.minX+CGFloat(scale.fraction(at: time))*plot.width }
    private func timeAt(_ point: NSPoint) -> Double { scale.time(at: Double((point.x-plot.minX)/plot.width)) }
    override func layout() { super.layout(); if cachedWidth != bounds.width { cachedPath = nil; needsDisplay = true } }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    private func text(_ string: String,at point: NSPoint,color: NSColor = GLoopTheme.muted,size: CGFloat = 10) {
        (string as NSString).draw(at: point,withAttributes: [.font:NSFont.monospacedDigitSystemFont(ofSize: size,weight: .medium),.foregroundColor:color])
    }
    private func path() -> NSBezierPath {
        if let cachedPath { return cachedPath }
        let result = NSBezierPath(); result.lineWidth = 1.25
        guard let envelope, !envelope.peaks.isEmpty else { return result }
        let n = envelope.peaks.count, width = plot.width, columns = max(1,Int(width/2))
        let maximum = max(0.001,envelope.peaks.max() ?? 0)
        for i in 0..<columns {
            let t0 = scale.time(at: Double(i)/Double(columns)), t1 = scale.time(at: Double(i+1)/Double(columns))
            let lo = min(n-1,max(0,Int(t0/envelope.binDuration)))
            let hi = min(n,max(lo+1,Int(ceil(t1/envelope.binDuration))))
            let value = envelope.peaks[lo..<hi].max() ?? 0
            guard value > 0 else { continue }
            let height = max(0.5,CGFloat(value/maximum)*plot.height/2)
            let x = plot.minX+(CGFloat(i)+0.5)*width/CGFloat(columns)
            result.move(to: NSPoint(x: x,y: plot.midY-height)); result.line(to: NSPoint(x: x,y: plot.midY+height))
        }
        cachedPath = result; cachedWidth = bounds.width
        return result
    }
    override func draw(_ dirtyRect: NSRect) {
        GLoopTheme.surface.setFill(); bounds.fill()
        guard available else {
            let size = (message as NSString).size(withAttributes: [.font:NSFont.systemFont(ofSize: 12)])
            (message as NSString).draw(at: NSPoint(x: max(12,(bounds.width-size.width)/2),y: (bounds.height-size.height)/2),withAttributes: [.font:NSFont.systemFont(ofSize: 12),.foregroundColor:GLoopTheme.muted]); return
        }
        let left = max(plot.minX,min(plot.maxX,xAt(loopA))), right = max(plot.minX,min(plot.maxX,xAt(loopB)))
        let selected = NSRect(x: left,y: plot.minY,width: max(0,right-left),height: plot.height)
        GLoopTheme.accent.withAlphaComponent(repeating ? 0.13 : 0.06).setFill(); selected.fill()
        GLoopTheme.border.setStroke(); let center = NSBezierPath(); center.move(to: NSPoint(x: plot.minX,y: plot.midY)); center.line(to: NSPoint(x: plot.maxX,y: plot.midY)); center.stroke()
        GLoopTheme.muted.withAlphaComponent(0.7).setStroke(); path().stroke()
        NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect: selected).addClip(); GLoopTheme.accent.setStroke(); path().stroke(); NSGraphicsContext.restoreGraphicsState()
        if head >= scale.lower && head <= scale.upper {
            let line = NSBezierPath(); line.lineWidth = 1.5; line.move(to: NSPoint(x: xAt(head),y: plot.minY)); line.line(to: NSPoint(x: xAt(head),y: plot.maxY)); GLoopTheme.text.setStroke(); line.stroke()
        }
        for (name,time) in [("A",loopA),("B",loopB)] where time >= scale.lower && time <= scale.upper {
            let x = xAt(time), marker = NSBezierPath(); marker.lineWidth = 2
            marker.move(to: NSPoint(x: x,y: 17)); marker.line(to: NSPoint(x: x,y: plot.maxY+2)); GLoopTheme.accent.setStroke(); marker.stroke()
            let badge = NSRect(x: x-8,y: 1,width: 16,height: 16)
            GLoopTheme.accent.setFill(); NSBezierPath(roundedRect: badge,xRadius: 2,yRadius: 2).fill()
            text(name,at: NSPoint(x: x-3.5,y: 2),color: GLoopTheme.canvas,size: 11)
        }
        text(stamp(scale.lower,precise: true),at: NSPoint(x: plot.minX,y: bounds.height-17))
        let end = stamp(scale.upper,precise: true)
        let endWidth = (end as NSString).size(withAttributes: [.font:NSFont.monospacedDigitSystemFont(ofSize: 10,weight: .medium)]).width
        text(end,at: NSPoint(x: plot.maxX-endWidth,y: bounds.height-17))
        if window?.firstResponder === self { GLoopTheme.border.setStroke(); NSBezierPath(rect: bounds.insetBy(dx: 0.5,dy: 0.5)).stroke() }
    }
    override func mouseDown(with event: NSEvent) {
        guard available else { return }
        window?.makeFirstResponder(self)
        downPoint = convert(event.locationInWindow,from: nil); downTime = timeAt(downPoint)
        original = (loopA,loopB); moved = false
        let da = abs(downPoint.x-xAt(loopA)), db = abs(downPoint.x-xAt(loopB))
        if min(da,db) <= 10 { drag = da <= db ? .start : .end } else { drag = .selection }
        onBegin?(); needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let drag else { return }
        let point = convert(event.locationInWindow,from: nil), time = timeAt(point)
        guard moved || abs(point.x-downPoint.x) >= 3 else { return }
        moved = true
        switch drag {
        case .start: loopA = max(0,min(loopB-0.16,time))
        case .end: loopB = min(scale.duration,max(loopA+0.16,time))
        case .selection:
            guard let selection = WaveformScale.selection(downTime,time,duration: scale.duration) else { return }
            loopA = selection.0; loopB = selection.1
        }
        onPreview?(loopA,loopB); needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard let drag else { return }
        self.drag = nil
        if moved && (loopA != original.0 || loopB != original.1) { onSelect?(loopA,loopB) }
        else if !moved && drag == .selection { onSeek?(downTime) }
        else { onCancel?() }
        needsDisplay = true
    }
    func cancelDrag() {
        guard drag != nil else { return }
        drag = nil; loopA = original.0; loopB = original.1; onCancel?(); needsDisplay = true
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancelDrag() } else { super.keyDown(with: event) }
    }
    override func resignFirstResponder() -> Bool { cancelDrag(); needsDisplay = true; return super.resignFirstResponder() }
}

extension PlayerApp {
    func setupWaveform() {
        waveform.heightAnchor.constraint(equalToConstant: 88).isActive = true
        waveform.onBegin = { [weak self] in
            guard let self else { return }
            self.sampleStats(); self.waveWasPlaying = self.isPlaying
            self.pendingPause = false
            self.smooth.pause(); self.player.pause(true); self.metronome.stop(); self.stats.resetClock()
        }
        waveform.onPreview = { [weak self] a,b in self?.aField.stringValue = stamp(a,precise: true); self?.bField.stringValue = stamp(b,precise: true) }
        waveform.onSelect = { [weak self] a,b in
            guard let self else { return }
            self.prefs.a = a; self.prefs.b = b; self.prefs.looping = true
            self.markersChanged(); self.finishWaveformGesture()
        }
        waveform.onSeek = { [weak self] time in
            guard let self else { return }
            self.counter.reset(); self.seek(min(max(self.prefs.a,time),(self.prefs.b ?? self.duration)-0.025)); self.updateProgress()
            self.finishWaveformGesture()
        }
        waveform.onCancel = { [weak self] in self?.updateControls(); self?.finishWaveformGesture() }
    }
    func finishWaveformGesture() {
        let resume = waveWasPlaying; waveWasPlaying = false
        if resume && !isPlaying { togglePlay() }
        else { play.title = counter.finished ? "Replay" : "Play" }
    }
    func updateWaveform() {
        waveform.update(a: prefs.a,b: prefs.b ?? duration,repeating: prefs.looping)
        zoomWaveButton.isEnabled = waveform.available; fitWaveButton.isEnabled = waveform.available
    }
    @objc func zoomWaveform() { waveform.zoomToLoop() }
    @objc func fitWaveform() { waveform.fit() }
}
