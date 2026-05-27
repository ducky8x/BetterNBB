import AppKit
import Vision
import ScreenCaptureKit

// MARK: - Config

struct RegionConfig: Codable {
    var x, y, width, height: Double
    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    init(_ r: CGRect) { x = r.origin.x; y = r.origin.y; width = r.width; height = r.height }
}

struct AppConfig: Codable {
    var regions: [String: RegionConfig] = [:]
    var overlayFrame: RegionConfig?
    var sourceWindowHint: String = "NBB"

    static let saveURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NinjaOCR")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }()

    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: saveURL),
              let cfg  = try? JSONDecoder().decode(AppConfig.self, from: data)
        else { return AppConfig() }
        return cfg
    }

    func save() {
        try? JSONEncoder().encode(self).write(to: AppConfig.saveURL)
    }
}

// MARK: - Screen Capture

private func virtualDesktopFrame() -> CGRect {
    NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
}

func captureRegion(_ rect: CGRect) async -> CGImage? {
    let captureRect = CGRect(
        x: rect.origin.x,
        y: rect.origin.y,
        width: max(1, rect.width),
        height: max(1, rect.height)
    )
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let center = CGPoint(x: captureRect.midX, y: captureRect.midY)
        guard let display = content.displays.first(where: { $0.frame.contains(center) }) ?? content.displays.first
        else { return nil }

        // sourceRect is relative to the chosen display, in the same global orientation.
        let sourceRect = CGRect(
            x: captureRect.origin.x - display.frame.origin.x,
            y: captureRect.origin.y - display.frame.origin.y,
            width: captureRect.width,
            height: captureRect.height
        )
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect  = sourceRect
        config.width       = max(1, Int(captureRect.width))
        config.height      = max(1, Int(captureRect.height))
        config.scalesToFit = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    } catch {
        print("⚠️  Capture failed: \(error)")
        return nil
    }
}

func findWindow(titleContains hint: String) async -> SCWindow? {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let match = content.windows.filter { win in
            let title = (win.title ?? "").lowercased()
            let app = (win.owningApplication?.applicationName ?? "").lowercased()
            let h = hint.lowercased()
            return !h.isEmpty && (title.contains(h) || app.contains(h))
        }
        // Prefer largest matching window.
        return match.max(by: { ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height) })
    } catch {
        print("⚠️  Window discovery failed: \(error)")
        return nil
    }
}

func captureWindowImage(_ window: SCWindow) async -> CGImage? {
    do {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = max(1, Int(window.frame.width))
        config.height = max(1, Int(window.frame.height))
        config.scalesToFit = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    } catch {
        print("⚠️  Window capture failed: \(error)")
        return nil
    }
}

func cropWindowImage(_ image: CGImage, windowFrame: CGRect, globalRect: CGRect) -> CGImage? {
    let relX = globalRect.origin.x - windowFrame.origin.x
    let relYFromTop = globalRect.origin.y - windowFrame.origin.y
    let cropRect = CGRect(
        x: relX,
        y: relYFromTop,
        width: globalRect.width,
        height: globalRect.height
    ).integral
    let bounded = cropRect.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard bounded.width > 1, bounded.height > 1 else { return nil }
    return image.cropping(to: bounded)
}

// MARK: - OCR

func recognizeText(in image: CGImage) -> String {
    let req = VNRecognizeTextRequest()
    req.recognitionLevel       = .accurate
    req.usesLanguageCorrection = false
    req.recognitionLanguages   = ["en-US"]
    try? VNImageRequestHandler(cgImage: image).perform([req])
    return req.results?
        .compactMap { $0.topCandidates(1).first?.string }
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        ?? ""
}

// MARK: - Layout constants

let topCols: [(header: String, key: String)] = [
    ("Location", "loc"), ("%", "pct"), ("Dist.", "dist"), ("Nether", "nether"), ("Angle", "angle")
]
let topRows = 2

let botCols: [(header: String, key: String)] = [
    ("x", "x"), ("z", "z"), ("Angle", "angle"), ("Error", "error")
]
let botRows = 3

func cellKey(section: String, row: Int, col: String) -> String { "\(section)_r\(row)_\(col)" }

// MARK: - Generic Drag Picker
// Used for both cell regions and overlay placement.

protocol DragPickerDelegate: AnyObject {
    func dragPicker(_ picker: DragPicker, didSelect rect: CGRect, tag: String)
}

final class DragPicker: NSWindowController {
    weak var delegate: DragPickerDelegate?
    let tag: String
    private let instruction: String
    private var startPoint: NSPoint = .zero
    private var selectionView: NSView?
    private let desktopFrame: CGRect

    init(tag: String, instruction: String) {
        self.tag         = tag
        self.instruction = instruction
        self.desktopFrame = virtualDesktopFrame()
        let win = NSWindow(contentRect: desktopFrame, styleMask: .borderless,
                           backing: .buffered, defer: false)
        win.level           = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        win.backgroundColor = NSColor.black.withAlphaComponent(0.35)
        win.isOpaque        = false
        super.init(window: win)

        let lbl = NSTextField(labelWithString: "\(instruction)   •   ESC to cancel")
        lbl.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        lbl.textColor = .white; lbl.backgroundColor = .clear; lbl.sizeToFit()
        lbl.setFrameOrigin(NSPoint(x: (desktopFrame.width - lbl.frame.width) / 2, y: desktopFrame.height - 60))
        win.contentView?.addSubview(lbl)
        win.makeKeyAndOrderFront(nil)
        NSCursor.crosshair.set()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        startPoint = event.locationInWindow
        let box = NSView(frame: NSRect(origin: startPoint, size: .zero))
        box.wantsLayer = true
        box.layer?.borderColor  = NSColor.systemBlue.cgColor
        box.layer?.borderWidth  = 2
        box.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.15).cgColor
        window?.contentView?.addSubview(box); selectionView = box
    }

    override func mouseDragged(with event: NSEvent) {
        guard let box = selectionView else { return }
        let cur = event.locationInWindow
        box.frame = NSRect(x: min(startPoint.x, cur.x), y: min(startPoint.y, cur.y),
                           width: abs(cur.x - startPoint.x), height: abs(cur.y - startPoint.y))
    }

    override func mouseUp(with event: NSEvent) {
        guard let box = selectionView, let win = window else { close(); return }
        // Convert from window-local coords to global top-left coords across all displays.
        let globalX = win.frame.origin.x + box.frame.origin.x
        let globalBottomY = win.frame.origin.y + box.frame.origin.y
        let picked = CGRect(x: globalX,
                            y: desktopFrame.maxY - globalBottomY - box.frame.height,
                            width: box.frame.width, height: box.frame.height)
        NSCursor.arrow.set(); close()
        if picked.width > 4 && picked.height > 4 {
            delegate?.dragPicker(self, didSelect: picked, tag: tag)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { NSCursor.arrow.set(); close() }
    }
}

// MARK: - Setup Cell

final class SetupCell: NSView {
    let key: String
    private let pickButton = NSButton()

    var onPick: ((String) -> Void)?

    init(key: String, header: String) {
        self.key = key
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor

        let hdr = NSTextField(labelWithString: header)
        hdr.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        hdr.textColor = NSColor(white: 0.55, alpha: 1)
        hdr.alignment = .center
        hdr.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hdr)

        pickButton.title = "select"
        pickButton.font  = NSFont.systemFont(ofSize: 9)
        pickButton.bezelStyle = .inline
        pickButton.target = self
        pickButton.action = #selector(pickTapped)
        pickButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pickButton)

        NSLayoutConstraint.activate([
            hdr.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            hdr.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            hdr.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            pickButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            pickButton.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 6),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
    @objc private func pickTapped() { onPick?(key) }

    func markConfigured(_ yes: Bool) {
        layer?.backgroundColor = yes
            ? NSColor(white: 0.16, alpha: 1).cgColor
            : NSColor(red: 0.22, green: 0.08, blue: 0.08, alpha: 1).cgColor
        pickButton.title = yes ? "✓ redo" : "select"
    }
}

// MARK: - Overlay Table Window

final class OverlayTableWindow: NSWindowController {

    private var labels: [String: NSTextField] = [:]
    private var currentValues: [String: String] = [:]
    private var valueKeys: [String] = []
    private var baseValueFontSize: CGFloat = 14
    private var valueFontSize: CGFloat = 14
    private var valueFontWeight: NSFont.Weight = .regular
    private let minValueFontSize: CGFloat = 6

    // Default frame — overridden by saved config or position picker
    private var targetFrame: NSRect = {
        let s = NSScreen.main?.frame ?? .zero
        let w: CGFloat = 480; let h: CGFloat = 160
        return NSRect(x: s.midX - w/2, y: s.minY + 60, width: w, height: h)
    }()

    init() {
        let win = NSWindow(contentRect: .zero, styleMask: .borderless,
                           backing: .buffered, defer: false)
        win.level              = .floating
        win.isOpaque           = false
        win.backgroundColor    = .clear
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.hasShadow          = false
        super.init(window: win)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Call before start to position the overlay.
    func setFrame(_ rect: CGRect) {
        // rect is in top-left coords; convert to bottom-left for NSWindow
        guard let screen = NSScreen.main else { return }
        let winY = screen.frame.height - rect.origin.y - rect.height
        targetFrame = NSRect(x: rect.origin.x, y: winY, width: rect.width, height: rect.height)
        rebuildLayout()
    }

    func rebuildLayout() {
        guard let win = window else { return }
        win.setFrame(targetFrame, display: false)
        win.contentView?.subviews.forEach { $0.removeFromSuperview() }
        labels.removeAll()
        valueKeys.removeAll()

        let W = targetFrame.width
        let H = targetFrame.height
        let cv = win.contentView!

        // Proportions: top table ~55%, gap ~8%, bottom table ~37%
        let topH   = H * 0.55
        let botH   = H * 0.37
        let gap    = H - topH - botH
        let hdrH   = topH * 0.22
        let tRowH  = (topH - hdrH) / CGFloat(topRows)
        let bHdrH  = botH * 0.28
        let bRowH  = (botH - bHdrH) / CGFloat(botRows)
        let topColW = W / CGFloat(topCols.count)
        let botColW = W / CGFloat(botCols.count)
        let fontSize = max(10, min(tRowH * 0.55, 22))
        baseValueFontSize = fontSize
        valueFontSize = fontSize
        let hdrSize  = max(8, fontSize * 0.65)

        // -- Top section --
        let topBaseY = botH + gap

        for (ci, col) in topCols.enumerated() {
            let lbl = makeLabel(col.header, size: hdrSize, weight: .semibold,
                                color: NSColor(white: 0.7, alpha: 1))
            lbl.frame = NSRect(x: CGFloat(ci) * topColW, y: topBaseY + CGFloat(topRows) * tRowH,
                               width: topColW, height: hdrH)
            cv.addSubview(lbl)
        }
        for ri in 0..<topRows {
            for (ci, col) in topCols.enumerated() {
                let key = cellKey(section: "top", row: ri, col: col.key)
                let lbl = makeLabel("--", size: fontSize, weight: .regular, color: .white)
                lbl.frame = NSRect(x: CGFloat(ci) * topColW,
                                   y: topBaseY + CGFloat(topRows - 1 - ri) * tRowH,
                                   width: topColW, height: tRowH)
                cv.addSubview(lbl)
                labels[key] = lbl
                valueKeys.append(key)
                lbl.stringValue = currentValues[key].flatMap { $0.isEmpty ? nil : $0 } ?? "--"
            }
        }

        // Divider
        let div = NSBox()
        div.boxType = .separator
        div.frame = NSRect(x: 0, y: botH + gap * 0.5, width: W, height: 1)
        cv.addSubview(div)

        // -- Bottom section --
        for (ci, col) in botCols.enumerated() {
            let lbl = makeLabel(col.header, size: hdrSize, weight: .semibold,
                                color: NSColor(white: 0.7, alpha: 1))
            lbl.frame = NSRect(x: CGFloat(ci) * botColW, y: CGFloat(botRows) * bRowH,
                               width: botColW, height: bHdrH)
            cv.addSubview(lbl)
        }
        for ri in 0..<botRows {
            for (ci, col) in botCols.enumerated() {
                let key = cellKey(section: "bot", row: ri, col: col.key)
                let lbl = makeLabel("--", size: fontSize, weight: .regular, color: .white)
                lbl.frame = NSRect(x: CGFloat(ci) * botColW,
                                   y: CGFloat(botRows - 1 - ri) * bRowH,
                                   width: botColW, height: bRowH)
                cv.addSubview(lbl)
                labels[key] = lbl
                valueKeys.append(key)
                lbl.stringValue = currentValues[key].flatMap { $0.isEmpty ? nil : $0 } ?? "--"
            }
        }

        updateAllValueFonts()
        recolorAllValues()
        win.makeKeyAndOrderFront(nil)
    }

    private func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight,
                            color: NSColor) -> NSTextField {
        let lbl = NSTextField(labelWithString: text)
        lbl.font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        lbl.textColor = color; lbl.alignment = .center
        lbl.drawsBackground = false; lbl.isBezeled = false
        lbl.lineBreakMode = .byClipping
        lbl.maximumNumberOfLines = 1
        lbl.cell?.wraps = false
        lbl.cell?.truncatesLastVisibleLine = false
        return lbl
    }

    func updateValue(key: String, value: String) {
        DispatchQueue.main.async {
            guard let lbl = self.labels[key] else { return }
            self.currentValues[key] = value
            lbl.stringValue = value.isEmpty ? "--" : value
            self.updateAllValueFonts()
            self.recolorAllValues()
        }
    }

    private func updateAllValueFonts() {
        guard !valueKeys.isEmpty else { return }
        // Recompute from the max/base size each time so fonts can grow back.
        var fittedSize = baseValueFontSize

        while fittedSize > minValueFontSize {
            let font = NSFont.monospacedDigitSystemFont(ofSize: fittedSize, weight: valueFontWeight)
            let allFit = valueKeys.allSatisfy { key in
                guard let lbl = labels[key] else { return true }
                let text = lbl.stringValue.isEmpty ? "--" : lbl.stringValue
                let measured = (text as NSString).boundingRect(
                    with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: font]
                ).integral.size
                // Use conservative bounds to avoid right-edge clipping.
                return measured.width <= lbl.frame.width * 0.86 && measured.height <= lbl.frame.height * 0.86
            }
            if allFit { break }
            fittedSize -= 0.5
        }

        valueFontSize = max(minValueFontSize, fittedSize)
        let font = NSFont.monospacedDigitSystemFont(ofSize: valueFontSize, weight: valueFontWeight)
        for key in valueKeys {
            labels[key]?.font = font
        }
    }

    private func recolorAllValues() {
        for key in valueKeys {
            guard let lbl = labels[key] else { continue }
            if key.hasSuffix("_pct") {
                let raw = currentValues[key] ?? lbl.stringValue
                let v = Double(raw.replacingOccurrences(of: "%", with: "")) ?? 0
                lbl.textColor = v > 50 ? .systemGreen : v > 10 ? .systemOrange : .systemRed
            } else {
                lbl.textColor = .white
            }
        }
    }

    func hide() { window?.orderOut(nil) }
    func show() { window?.makeKeyAndOrderFront(nil) }
}

// MARK: - Overlay Position Preview
// Semi-transparent preview shown while dragging to place the overlay.

final class OverlayPreviewWindow: NSWindowController {
    init(frame: NSRect) {
        let win = NSWindow(contentRect: frame, styleMask: .borderless,
                           backing: .buffered, defer: false)
        win.level           = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) - 1)
        win.isOpaque        = false
        win.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.18)
        win.ignoresMouseEvents = true
        super.init(window: win)

        // Border
        let border = NSView(frame: NSRect(origin: .zero, size: frame.size))
        border.wantsLayer = true
        border.layer?.borderColor = NSColor.systemBlue.cgColor
        border.layer?.borderWidth = 2
        win.contentView?.addSubview(border)

        // Label
        let lbl = NSTextField(labelWithString: "Overlay will appear here")
        lbl.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        lbl.textColor = .white; lbl.alignment = .center
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.backgroundColor = .clear
        win.contentView?.addSubview(lbl)
        NSLayoutConstraint.activate([
            lbl.centerXAnchor.constraint(equalTo: win.contentView!.centerXAnchor),
            lbl.centerYAnchor.constraint(equalTo: win.contentView!.centerYAnchor),
        ])
        win.makeKeyAndOrderFront(nil)
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Control Window

final class ControlWindow: NSWindowController, DragPickerDelegate {
    private var config    = AppConfig.load()
    private var picker:   DragPicker?
    private var preview:  OverlayPreviewWindow?
    private var allCells: [SetupCell] = []
    private var isRunning = false

    private let startStopBtn    = NSButton()
    private let statusLbl       = NSTextField(labelWithString: "Set regions then press Start")
    private let overlayBtn      = NSButton()
    private let sourceHintField = NSTextField(string: "")
    private var overlayFrameLbl = NSTextField(labelWithString: "Not set")

    var onStart: (([String: CGRect], String) -> Void)?
    var onStop:  (() -> Void)?
    var onOverlayFrameChanged: ((CGRect) -> Void)?

    init() {
        let win = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 580, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        win.title = "NinjaOCR Setup"
        win.backgroundColor = NSColor(white: 0.1, alpha: 1)
        super.init(window: win)
        buildUI(in: win.contentView!)
        applyConfig()
        win.makeKeyAndOrderFront(nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildUI(in root: NSView) {
        let outer = NSStackView()
        outer.orientation = .vertical
        outer.spacing = 14
        outer.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        outer.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(outer)
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            outer.topAnchor.constraint(equalTo: root.topAnchor),
            outer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        outer.addArrangedSubview(sectionGrid(title: "Stronghold", section: "top",
                                             cols: topCols, rows: topRows))
        outer.addArrangedSubview(sectionGrid(title: "Ender Eye Throws", section: "bot",
                                             cols: botCols, rows: botRows))

        // Overlay placement row
        overlayBtn.title = "⊞  Set Overlay Position"
        overlayBtn.bezelStyle = .rounded
        overlayBtn.target = self; overlayBtn.action = #selector(pickOverlay)

        overlayFrameLbl.font = NSFont.systemFont(ofSize: 11)
        overlayFrameLbl.textColor = NSColor(white: 0.5, alpha: 1)
        overlayFrameLbl.isEditable = false; overlayFrameLbl.isBezeled = false
        overlayFrameLbl.backgroundColor = .clear

        if let saved = config.overlayFrame {
            let r = saved.cgRect
            overlayFrameLbl.stringValue = String(format: "%.0f, %.0f  •  %.0f × %.0f",
                                                 r.origin.x, r.origin.y, r.width, r.height)
        }

        let overlayRow = NSStackView(views: [overlayBtn, overlayFrameLbl])
        overlayRow.spacing = 10
        outer.addArrangedSubview(overlayRow)

        // Source window hint
        let srcLbl = NSTextField(labelWithString: "Source window title/app contains:")
        srcLbl.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        srcLbl.textColor = NSColor(white: 0.65, alpha: 1)
        sourceHintField.stringValue = config.sourceWindowHint
        sourceHintField.font = NSFont.systemFont(ofSize: 12)
        sourceHintField.target = self
        sourceHintField.action = #selector(sourceHintChanged)
        let srcRow = NSStackView(views: [srcLbl, sourceHintField])
        srcRow.spacing = 8
        srcRow.alignment = .centerY
        outer.addArrangedSubview(srcRow)

        // Start/stop
        startStopBtn.bezelStyle = .rounded
        startStopBtn.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        startStopBtn.target = self; startStopBtn.action = #selector(toggleRunning)
        updateButtonState()

        statusLbl.font = NSFont.systemFont(ofSize: 11)
        statusLbl.textColor = NSColor(white: 0.5, alpha: 1)
        statusLbl.alignment = .center; statusLbl.isEditable = false
        statusLbl.isBezeled = false; statusLbl.backgroundColor = .clear

        let btnRow = NSStackView(views: [startStopBtn])
        btnRow.distribution = .fillEqually
        outer.addArrangedSubview(btnRow)
        outer.addArrangedSubview(statusLbl)
        startStopBtn.widthAnchor.constraint(equalToConstant: 160).isActive = true
    }

    private func sectionGrid(title: String, section: String,
                              cols: [(header: String, key: String)], rows: Int) -> NSView {
        let wrapper = NSView()
        wrapper.wantsLayer = true
        wrapper.layer?.backgroundColor = NSColor(white: 0.08, alpha: 1).cgColor
        wrapper.layer?.cornerRadius = 6

        let titleLbl = NSTextField(labelWithString: title.uppercased())
        titleLbl.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        titleLbl.textColor = NSColor(white: 0.5, alpha: 1)
        titleLbl.isEditable = false; titleLbl.isBezeled = false
        titleLbl.backgroundColor = .clear
        titleLbl.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(titleLbl)

        let grid = NSGridView()
        grid.rowSpacing = 1; grid.columnSpacing = 1
        grid.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(grid)

        for row in 0..<rows {
            var views: [NSView] = []
            for col in cols {
                let key  = cellKey(section: section, row: row, col: col.key)
                let cell = SetupCell(key: key, header: row == 0 ? col.header : "")
                cell.onPick = { [weak self] k in self?.startPickingCell(key: k) }
                cell.translatesAutoresizingMaskIntoConstraints = false
                cell.widthAnchor.constraint(equalToConstant: 88).isActive = true
                cell.heightAnchor.constraint(equalToConstant: 50).isActive = true
                allCells.append(cell); views.append(cell)
            }
            grid.addRow(with: views)
        }

        NSLayoutConstraint.activate([
            titleLbl.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 8),
            titleLbl.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 10),
            grid.topAnchor.constraint(equalTo: titleLbl.bottomAnchor, constant: 6),
            grid.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 6),
            grid.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -6),
            grid.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -6),
        ])
        return wrapper
    }

    private func applyConfig() {
        for cell in allCells { cell.markConfigured(config.regions[cell.key] != nil) }
    }

    private func startPickingCell(key: String) {
        picker = DragPicker(tag: key, instruction: "Drag over the number for: \(key)")
        picker?.delegate = self
    }

    @objc private func pickOverlay() {
        picker = DragPicker(tag: "__overlay__", instruction: "Drag to set where the overlay table will appear")
        picker?.delegate = self
    }

    func dragPicker(_ picker: DragPicker, didSelect rect: CGRect, tag: String) {
        if tag == "__overlay__" {
            config.overlayFrame = RegionConfig(rect)
            config.save()
            DispatchQueue.main.async {
                self.overlayFrameLbl.stringValue = String(format: "%.0f, %.0f  •  %.0f × %.0f",
                                                         rect.origin.x, rect.origin.y,
                                                         rect.width, rect.height)
                self.onOverlayFrameChanged?(rect)
                // Show a brief preview
                if let screen = NSScreen.main {
                    let winY = screen.frame.height - rect.origin.y - rect.height
                    let winFrame = NSRect(x: rect.origin.x, y: winY, width: rect.width, height: rect.height)
                    self.preview = OverlayPreviewWindow(frame: winFrame)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        self.preview?.close(); self.preview = nil
                    }
                }
            }
        } else {
            config.regions[tag] = RegionConfig(rect); config.save()
            DispatchQueue.main.async {
                self.allCells.first { $0.key == tag }?.markConfigured(true)
            }
        }
    }

    @objc private func toggleRunning() {
        isRunning.toggle(); updateButtonState()
        if isRunning {
            let rects = config.regions.mapValues { $0.cgRect }
            let hint = sourceHintField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            config.sourceWindowHint = hint.isEmpty ? "NBB" : hint
            config.save()
            onStart?(rects, config.sourceWindowHint)
            let total = (topRows * topCols.count) + (botRows * botCols.count)
            statusLbl.stringValue = "Running — \(rects.count)/\(total) regions active (source: \(config.sourceWindowHint))"
        } else {
            onStop?()
            statusLbl.stringValue = "Stopped"
        }
    }

    @objc private func sourceHintChanged() {
        config.sourceWindowHint = sourceHintField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if config.sourceWindowHint.isEmpty { config.sourceWindowHint = "NBB" }
        config.save()
    }

    private func updateButtonState() {
        startStopBtn.title = isRunning ? "■  Stop" : "▶  Start"
        startStopBtn.contentTintColor = isRunning ? .systemRed : .systemGreen
    }

    var savedOverlayFrame: CGRect? { config.overlayFrame?.cgRect }
}

// MARK: - Coordinator

final class AppCoordinator {
    private let controls = ControlWindow()
    private let overlay  = OverlayTableWindow()
    private var timer:   Timer?
    private var regions: [String: CGRect] = [:]
    private var sourceWindowHint: String = "NBB"

    init() {
        // Apply saved overlay position immediately
        if let saved = controls.savedOverlayFrame {
            overlay.setFrame(saved)
        } else {
            overlay.rebuildLayout()
        }

        controls.onOverlayFrameChanged = { [weak self] rect in
            self?.overlay.setFrame(rect)
        }
        controls.onStart = { [weak self] rects, hint in
            self?.regions = rects
            self?.sourceWindowHint = hint
            self?.overlay.show()
            self?.startPolling()
        }
        controls.onStop = { [weak self] in
            self?.stopPolling()
            self?.overlay.hide()
        }
    }

    private func startPolling() {
        stopPolling()
        timer = .scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func stopPolling() { timer?.invalidate(); timer = nil }

    private func tick() {
        let snapshot = regions
        let hint = sourceWindowHint
        Task {
            if let window = await findWindow(titleContains: hint),
               let windowImage = await captureWindowImage(window) {
                for (key, rect) in snapshot {
                    let image = cropWindowImage(windowImage, windowFrame: window.frame, globalRect: rect)
                    let value = image.map(recognizeText(in:)) ?? ""
                    await self.overlay.updateValue(key: key, value: value)
                }
                return
            }

            // Fallback: visible display capture if source window is missing/minimized.
            for (key, rect) in snapshot {
                guard let image = await captureRegion(rect) else { continue }
                let value = recognizeText(in: image)
                await self.overlay.updateValue(key: key, value: value)
            }
        }
    }
}

// MARK: - Entry Point

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    func applicationDidFinishLaunching(_ n: Notification) { coordinator = AppCoordinator() }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

let app      = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
