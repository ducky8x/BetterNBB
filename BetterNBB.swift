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

func captureRegion(_ rect: CGRect) async -> CGImage? {
    guard let screen = NSScreen.main else { return nil }
    let flipped = CGRect(
        x: rect.origin.x,
        y: screen.frame.height - rect.origin.y - rect.height,
        width: max(1, rect.width),
        height: max(1, rect.height)
    )
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { return nil }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect  = flipped
        config.width       = max(1, Int(rect.width))
        config.height      = max(1, Int(rect.height))
        config.scalesToFit = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    } catch {
        print("⚠️  Capture failed: \(error)")
        return nil
    }
}

// MARK: - OCR

func recognizeNumber(in image: CGImage) -> String {
    let req = VNRecognizeTextRequest()
    req.recognitionLevel       = .accurate
    req.usesLanguageCorrection = false
    req.recognitionLanguages   = ["en-US"]
    try? VNImageRequestHandler(cgImage: image).perform([req])
    let raw = req.results?
        .compactMap { $0.topCandidates(1).first?.string }
        .joined(separator: " ") ?? ""
    return raw.components(separatedBy: .whitespaces)
        .first { !$0.isEmpty && $0.allSatisfy { "0123456789.-+%(),".contains($0) } } ?? ""
}

// MARK: - Layout constants

// Top table: Location | % | Dist. | Nether | Angle  (2 data rows)
let topCols: [(header: String, key: String)] = [
    ("Location", "loc"), ("%", "pct"), ("Dist.", "dist"), ("Nether", "nether"), ("Angle", "angle")
]
let topRows = 2

// Bottom table: x | z | Angle | Error  (3 data rows)
let botCols: [(header: String, key: String)] = [
    ("x", "x"), ("z", "z"), ("Angle", "angle"), ("Error", "error")
]
let botRows = 3

func cellKey(section: String, row: Int, col: String) -> String {
    "\(section)_r\(row)_\(col)"
}

// MARK: - Region Picker

protocol RegionPickerDelegate: AnyObject {
    func regionPicker(_ picker: RegionPicker, didSelect rect: CGRect, forKey key: String)
}

final class RegionPicker: NSWindowController {
    weak var delegate: RegionPickerDelegate?
    let key: String
    private var startPoint: NSPoint = .zero
    private var selectionView: NSView?

    init(key: String) {
        self.key = key
        let screen = NSScreen.main?.frame ?? .zero
        let win = NSWindow(contentRect: screen, styleMask: .borderless, backing: .buffered, defer: false)
        win.level           = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        win.backgroundColor = NSColor.black.withAlphaComponent(0.4)
        win.isOpaque        = false
        super.init(window: win)

        let lbl = NSTextField(labelWithString: "Drag to select: \(key)   •   ESC to cancel")
        lbl.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        lbl.textColor = .white; lbl.backgroundColor = .clear; lbl.sizeToFit()
        lbl.setFrameOrigin(NSPoint(x: (screen.width - lbl.frame.width) / 2, y: screen.height - 60))
        win.contentView?.addSubview(lbl)
        win.makeKeyAndOrderFront(nil)
        NSCursor.crosshair.set()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        startPoint = event.locationInWindow
        let box = NSView(frame: NSRect(origin: startPoint, size: .zero))
        box.wantsLayer = true
        box.layer?.borderColor = NSColor.systemBlue.cgColor
        box.layer?.borderWidth = 2
        box.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.2).cgColor
        window?.contentView?.addSubview(box); selectionView = box
    }

    override func mouseDragged(with event: NSEvent) {
        guard let box = selectionView else { return }
        let cur = event.locationInWindow
        box.frame = NSRect(x: min(startPoint.x, cur.x), y: min(startPoint.y, cur.y),
                           width: abs(cur.x - startPoint.x), height: abs(cur.y - startPoint.y))
    }

    override func mouseUp(with event: NSEvent) {
        guard let box = selectionView, let screen = NSScreen.main else { close(); return }
        let picked = CGRect(x: box.frame.origin.x,
                            y: screen.frame.height - box.frame.origin.y - box.frame.height,
                            width: box.frame.width, height: box.frame.height)
        NSCursor.arrow.set(); close()
        if picked.width > 4 && picked.height > 4 {
            delegate?.regionPicker(self, didSelect: picked, forKey: key)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { NSCursor.arrow.set(); close() }
    }
}

// MARK: - Setup Cell (used in the control window only)

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

// Displays a compact NBB-style table at the bottom of the screen.
// No background — just text on a fully transparent window.

final class OverlayTableWindow: NSWindowController {

    // key → label
    private var labels: [String: NSTextField] = [:]
    // We build the layout once on first update
    private var didLayout = false

    // ordered keys so we can lay them out
    private let topKeys: [[String]] = (0..<topRows).map { r in
        topCols.map { cellKey(section: "top", row: r, col: $0.key) }
    }
    private let botKeys: [[String]] = (0..<botRows).map { r in
        botCols.map { cellKey(section: "bot", row: r, col: $0.key) }
    }

    private let colW: CGFloat  = 90
    private let rowH: CGFloat  = 28
    private let hdrH: CGFloat  = 20
    private let secGap: CGFloat = 14
    private let fontSize: CGFloat = 14

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
        buildLayout()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildLayout() {
        guard let screen = NSScreen.main, let cv = window?.contentView else { return }

        let topTableW = CGFloat(topCols.count) * colW
        let botTableW = CGFloat(botCols.count) * colW
        let winW      = max(topTableW, botTableW)

        let topTableH = hdrH + CGFloat(topRows) * rowH
        let botTableH = hdrH + CGFloat(botRows) * rowH
        let winH      = topTableH + secGap + botTableH + 12

        let winX = screen.frame.midX - winW / 2
        let winY = screen.frame.minY + 60
        window?.setFrame(NSRect(x: winX, y: winY, width: winW, height: winH), display: false)
        window?.contentView?.setFrameSize(NSSize(width: winW, height: winH))

        // ---- Top section ----
        let topY = botTableH + secGap  // bottom of top section in window coords

        // Headers
        for (ci, col) in topCols.enumerated() {
            let lbl = makeLabel(col.header, size: 10, weight: .semibold, color: NSColor(white: 0.6, alpha: 1))
            lbl.frame = NSRect(x: CGFloat(ci) * colW, y: topY + CGFloat(topRows) * rowH, width: colW, height: hdrH)
            cv.addSubview(lbl)
        }
        // Data rows
        for (ri, rowKeys) in topKeys.enumerated() {
            for (ci, key) in rowKeys.enumerated() {
                let lbl = makeLabel("--", size: fontSize, weight: .regular, color: .white)
                lbl.frame = NSRect(x: CGFloat(ci) * colW,
                                   y: topY + CGFloat(topRows - 1 - ri) * rowH,
                                   width: colW, height: rowH)
                cv.addSubview(lbl)
                labels[key] = lbl
            }
        }

        // Divider line between sections
        let div = NSBox()
        div.boxType = .separator
        div.frame = NSRect(x: 0, y: botTableH + secGap / 2 - 1, width: winW, height: 1)
        cv.addSubview(div)

        // ---- Bottom section ----
        // Headers
        for (ci, col) in botCols.enumerated() {
            let lbl = makeLabel(col.header, size: 10, weight: .semibold, color: NSColor(white: 0.6, alpha: 1))
            lbl.frame = NSRect(x: CGFloat(ci) * colW, y: CGFloat(botRows) * rowH, width: colW, height: hdrH)
            cv.addSubview(lbl)
        }
        // Data rows
        for (ri, rowKeys) in botKeys.enumerated() {
            for (ci, key) in rowKeys.enumerated() {
                let lbl = makeLabel("--", size: fontSize, weight: .regular, color: .white)
                lbl.frame = NSRect(x: CGFloat(ci) * colW,
                                   y: CGFloat(botRows - 1 - ri) * rowH,
                                   width: colW, height: rowH)
                cv.addSubview(lbl)
                labels[key] = lbl
            }
        }

        window?.makeKeyAndOrderFront(nil)
    }

    private func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let lbl = NSTextField(labelWithString: text)
        lbl.font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        lbl.textColor   = color
        lbl.alignment   = .center
        lbl.drawsBackground = false
        lbl.isBezeled   = false
        return lbl
    }

    func updateValue(key: String, value: String) {
        DispatchQueue.main.async {
            guard let lbl = self.labels[key] else { return }
            lbl.stringValue = value.isEmpty ? "--" : value

            // Colour % column green/orange/red
            if key.hasSuffix("_pct") {
                let v = Double(value.replacingOccurrences(of: "%", with: "")) ?? 0
                lbl.textColor = v > 50 ? .systemGreen : v > 10 ? .systemOrange : .systemRed
            } else {
                lbl.textColor = .white
            }
        }
    }
}

// MARK: - Control Window

final class ControlWindow: NSWindowController, RegionPickerDelegate {
    private var config    = AppConfig.load()
    private var picker:   RegionPicker?
    private var allCells: [SetupCell] = []
    private var isRunning = false

    private let startStopBtn = NSButton()
    private let statusLbl    = NSTextField(labelWithString: "Configure regions then press Start")

    var onStart: (([String: CGRect]) -> Void)?
    var onStop:  (() -> Void)?

    init() {
        let win = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 560, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        win.title = "NinjaOCR Setup"
        win.backgroundColor = NSColor(white: 0.1, alpha: 1)
        super.init(window: win)
        buildUI(in: win.contentView!)
        win.makeKeyAndOrderFront(nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildUI(in root: NSView) {
        let outer = NSStackView()
        outer.orientation = .vertical
        outer.spacing = 16
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

        // Bottom controls
        startStopBtn.bezelStyle = .rounded
        startStopBtn.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        startStopBtn.target = self
        startStopBtn.action = #selector(toggleRunning)
        updateButtonState()

        statusLbl.font = NSFont.systemFont(ofSize: 11)
        statusLbl.textColor = NSColor(white: 0.5, alpha: 1)
        statusLbl.alignment = .center

        let btnRow = NSStackView(views: [startStopBtn])
        btnRow.distribution = .fillEqually
        outer.addArrangedSubview(btnRow)
        outer.addArrangedSubview(statusLbl)
        startStopBtn.widthAnchor.constraint(equalToConstant: 160).isActive = true

        applyConfig()
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
        titleLbl.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(titleLbl)

        let grid = NSGridView()
        grid.rowSpacing    = 1
        grid.columnSpacing = 1
        grid.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(grid)

        for row in 0..<rows {
            var views: [NSView] = []
            for col in cols {
                let key  = cellKey(section: section, row: row, col: col.key)
                let cell = SetupCell(key: key, header: row == 0 ? col.header : "")
                cell.onPick = { [weak self] k in self?.startPicking(key: k) }
                cell.translatesAutoresizingMaskIntoConstraints = false
                cell.widthAnchor.constraint(equalToConstant: 95).isActive = true
                cell.heightAnchor.constraint(equalToConstant: 52).isActive = true
                allCells.append(cell)
                views.append(cell)
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

    private func startPicking(key: String) {
        picker = RegionPicker(key: key); picker?.delegate = self
    }

    func regionPicker(_ picker: RegionPicker, didSelect rect: CGRect, forKey key: String) {
        config.regions[key] = RegionConfig(rect); config.save()
        DispatchQueue.main.async {
            self.allCells.first { $0.key == key }?.markConfigured(true)
        }
    }

    @objc private func toggleRunning() {
        isRunning.toggle(); updateButtonState()
        if isRunning {
            let rects = config.regions.mapValues { $0.cgRect }
            onStart?(rects)
            statusLbl.stringValue = "Running — \(rects.count)/\((topRows * topCols.count) + (botRows * botCols.count)) regions active"
        } else {
            onStop?()
            statusLbl.stringValue = "Stopped"
        }
    }

    private func updateButtonState() {
        startStopBtn.title = isRunning ? "■  Stop" : "▶  Start"
        startStopBtn.contentTintColor = isRunning ? .systemRed : .systemGreen
    }
}

// MARK: - Coordinator

final class AppCoordinator {
    private let controls = ControlWindow()
    private let overlay  = OverlayTableWindow()
    private var timer:   Timer?
    private var regions: [String: CGRect] = [:]

    init() {
        controls.onStart = { [weak self] rects in
            self?.regions = rects
            self?.startPolling()
        }
        controls.onStop = { [weak self] in self?.stopPolling() }
    }

    private func startPolling() {
        stopPolling()
        timer = .scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func stopPolling() { timer?.invalidate(); timer = nil }

    private func tick() {
        let snapshot = regions
        Task {
            for (key, rect) in snapshot {
                guard let image = await captureRegion(rect) else { continue }
                let value = recognizeNumber(in: image)
                self.overlay.updateValue(key: key, value: value)
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