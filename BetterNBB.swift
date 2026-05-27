import AppKit
import Vision
import ScreenCaptureKit

<<<<<<< Updated upstream
// MARK: - Screen Capture (ScreenCaptureKit)

func captureRegion(_ rect: CGRect) async -> CGImage? {
    guard let screen = NSScreen.main else { return nil }

    // Convert from top-left origin (AppKit) to bottom-left (Quartz)
    let flipped = CGRect(
        x: rect.origin.x,
        y: screen.frame.height - rect.origin.y - rect.height,
        width: rect.width,
        height: rect.height
    )

    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            print("⚠️  No display found")
            return nil
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect   = flipped
        config.width        = max(1, Int(rect.width))
        config.height       = max(1, Int(rect.height))
        config.scalesToFit  = false

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    } catch {
        print("⚠️  Capture failed: \(error)\n    → Grant Screen Recording in System Settings › Privacy & Security")
=======
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
>>>>>>> Stashed changes
        return nil
    }
}

// MARK: - OCR

func recognizeNumber(in image: CGImage) -> String {
<<<<<<< Updated upstream
    let request = VNRecognizeTextRequest()
    request.recognitionLevel        = .accurate
    request.usesLanguageCorrection  = false
    request.recognitionLanguages    = ["en-US"]

    try? VNImageRequestHandler(cgImage: image).perform([request])

    let raw = request.results?
        .compactMap { $0.topCandidates(1).first?.string }
        .joined(separator: " ") ?? ""

    return raw
        .components(separatedBy: .whitespaces)
        .first { !$0.isEmpty && $0.allSatisfy { "0123456789.-".contains($0) } }
        ?? ""
}

// MARK: - Overlay Window

final class OverlayWindow: NSWindowController {
    private let label = NSTextField(labelWithString: "--")

    init() {
        let frame = NSRect(x: 0, y: 0, width: 480, height: 110)
        let win   = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        win.level            = .floating
        win.isOpaque         = false
        win.backgroundColor  = .clear
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.hasShadow        = false
        super.init(window: win)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment      = .center
        label.font           = NSFont(name: "Avenir-Heavy", size: 64) ?? .boldSystemFont(ofSize: 64)
        label.textColor      = .systemGreen
        label.backgroundColor = .clear
        win.contentView?.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: win.contentView!.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: win.contentView!.trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: win.contentView!.centerYAnchor),
        ])

        centerOnScreen()
        win.makeKeyAndOrderFront(nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func centerOnScreen() {
        guard let screen = NSScreen.main, let win = window else { return }
        win.setFrameOrigin(NSPoint(
            x: screen.frame.midX - win.frame.width  / 2,
            y: screen.frame.midY - win.frame.height / 2
        ))
    }

    func update(text: String, font: NSFont, color: NSColor) {
        DispatchQueue.main.async {
            self.label.stringValue = text.isEmpty ? "--" : text
            self.label.font        = font
            self.label.textColor   = color
        }
    }
}

// MARK: - Region Picker (drag a rectangle on screen)

protocol RegionPickerDelegate: AnyObject {
    func regionPicker(_ picker: RegionPicker, didSelect rect: CGRect)
}

final class RegionPicker: NSWindowController, NSWindowDelegate {
    weak var delegate: RegionPickerDelegate?
    private var startPoint: NSPoint = .zero
    private var selectionView: NSView?

    init() {
        let screen = NSScreen.main?.frame ?? .zero
        let win    = NSWindow(contentRect: screen, styleMask: .borderless, backing: .buffered, defer: false)
        win.level           = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        win.backgroundColor = NSColor.black.withAlphaComponent(0.35)
        win.isOpaque        = false
        win.ignoresMouseEvents = false
        super.init(window: win)
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
        win.contentView?.addTrackingArea(NSTrackingArea(
            rect: win.contentView!.bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited],
            owner: win.contentView, userInfo: nil
        ))
=======
    let req = VNRecognizeTextRequest()
    req.recognitionLevel       = .accurate
    req.usesLanguageCorrection = false
    req.recognitionLanguages   = ["en-US"]
    try? VNImageRequestHandler(cgImage: image).perform([req])
    let raw = req.results?
        .compactMap { $0.topCandidates(1).first?.string }
        .joined(separator: " ") ?? ""
    return raw.components(separatedBy: .whitespaces)
        .first { !$0.isEmpty && $0.allSatisfy { "0123456789.-".contains($0) } } ?? ""
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

        // Instruction label
        let lbl = NSTextField(labelWithString: "Drag to select region for: \(key)   •   ESC to cancel")
        lbl.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        lbl.textColor = .white
        lbl.backgroundColor = .clear
        lbl.sizeToFit()
        lbl.setFrameOrigin(NSPoint(x: (screen.width - lbl.frame.width) / 2, y: screen.height - 60))
        win.contentView?.addSubview(lbl)

        win.makeKeyAndOrderFront(nil)
>>>>>>> Stashed changes
        NSCursor.crosshair.set()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        startPoint = event.locationInWindow
        let box = NSView(frame: NSRect(origin: startPoint, size: .zero))
        box.wantsLayer = true
        box.layer?.borderColor = NSColor.systemBlue.cgColor
        box.layer?.borderWidth = 2
<<<<<<< Updated upstream
        box.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.15).cgColor
=======
        box.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.2).cgColor
>>>>>>> Stashed changes
        window?.contentView?.addSubview(box)
        selectionView = box
    }

    override func mouseDragged(with event: NSEvent) {
        guard let box = selectionView else { return }
<<<<<<< Updated upstream
        let current = event.locationInWindow
        let origin  = NSPoint(x: min(startPoint.x, current.x), y: min(startPoint.y, current.y))
        let size    = NSSize(width: abs(current.x - startPoint.x), height: abs(current.y - startPoint.y))
        box.frame   = NSRect(origin: origin, size: size)
=======
        let cur = event.locationInWindow
        box.frame = NSRect(
            x: min(startPoint.x, cur.x), y: min(startPoint.y, cur.y),
            width: abs(cur.x - startPoint.x), height: abs(cur.y - startPoint.y)
        )
>>>>>>> Stashed changes
    }

    override func mouseUp(with event: NSEvent) {
        guard let box = selectionView, let screen = NSScreen.main else { close(); return }
<<<<<<< Updated upstream

        // box.frame is in window (bottom-left) coords — convert to top-left for our fields
        let picked = CGRect(
            x: box.frame.origin.x,
            y: screen.frame.height - box.frame.origin.y - box.frame.height,
            width: box.frame.width,
            height: box.frame.height
        )

        NSCursor.arrow.set()
        close()

        if picked.width > 4 && picked.height > 4 {
            delegate?.regionPicker(self, didSelect: picked)
        }
    }
=======
        let picked = CGRect(
            x: box.frame.origin.x,
            y: screen.frame.height - box.frame.origin.y - box.frame.height,
            width: box.frame.width, height: box.frame.height
        )
        NSCursor.arrow.set()
        close()
        if picked.width > 4 && picked.height > 4 {
            delegate?.regionPicker(self, didSelect: picked, forKey: key)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { NSCursor.arrow.set(); close() } // ESC
    }
}

// MARK: - NinjaBrain-style Table Cell

final class NBCell: NSView {
    let key: String
    private let valueLabel  = NSTextField(labelWithString: "--")
    private let pickButton  = NSButton()
    private var isConfigured = false

    var onPick: ((String) -> Void)?

    init(key: String, header: String) {
        self.key = key
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor

        // Header
        let hdr = NSTextField(labelWithString: header)
        hdr.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        hdr.textColor = NSColor(white: 0.6, alpha: 1)
        hdr.alignment = .center
        hdr.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hdr)

        // Value
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .regular)
        valueLabel.textColor = .white
        valueLabel.alignment = .center
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)

        // Pick button
        pickButton.title = "select"
        pickButton.font = NSFont.systemFont(ofSize: 9)
        pickButton.bezelStyle = .inline
        pickButton.isBordered = true
        pickButton.target = self
        pickButton.action = #selector(pickTapped)
        pickButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pickButton)

        NSLayoutConstraint.activate([
            hdr.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            hdr.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            hdr.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),

            valueLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 4),

            pickButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            pickButton.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func pickTapped() { onPick?(key) }

    func setValue(_ s: String, color: NSColor = .white) {
        valueLabel.stringValue = s.isEmpty ? "--" : s
        valueLabel.textColor   = color
    }

    func markConfigured(_ yes: Bool) {
        isConfigured = yes
        layer?.backgroundColor = yes
            ? NSColor(white: 0.14, alpha: 1).cgColor
            : NSColor(red: 0.25, green: 0.1, blue: 0.1, alpha: 1).cgColor
        pickButton.title = yes ? "✓ reselect" : "select"
    }
}

// MARK: - Table Section

struct ColumnDef { let header: String; let key: String }

final class NBTableSection: NSView {
    let title: String
    private(set) var cells: [NBCell] = []
    var onPick: ((String) -> Void)?

    init(title: String, rows: Int, cols: [ColumnDef]) {
        self.title = title
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.1, alpha: 1).cgColor
        layer?.cornerRadius = 4

        // Title bar
        let titleBar = NSView()
        titleBar.wantsLayer = true
        titleBar.layer?.backgroundColor = NSColor(white: 0.08, alpha: 1).cgColor
        titleBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleBar)

        let titleLbl = NSTextField(labelWithString: title.uppercased())
        titleLbl.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        titleLbl.textColor = .white
        titleLbl.translatesAutoresizingMaskIntoConstraints = false
        titleBar.addSubview(titleLbl)

        // Grid
        let grid = NSGridView()
        grid.rowSpacing    = 1
        grid.columnSpacing = 1
        grid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid)

        // Build cells
        for row in 0..<rows {
            var rowViews: [NSView] = []
            for col in cols {
                let cellKey = "\(title.lowercased())_r\(row)_\(col.key)"
                let cell = NBCell(key: cellKey, header: row == 0 ? col.header : "")
                cell.onPick = { [weak self] key in self?.onPick?(key) }
                cell.translatesAutoresizingMaskIntoConstraints = false
                cell.widthAnchor.constraint(equalToConstant: 90).isActive = true
                cell.heightAnchor.constraint(equalToConstant: 60).isActive = true
                cells.append(cell)
                rowViews.append(cell)
            }
            grid.addRow(with: rowViews)
        }

        NSLayoutConstraint.activate([
            titleBar.topAnchor.constraint(equalTo: topAnchor),
            titleBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleBar.heightAnchor.constraint(equalToConstant: 28),
            titleLbl.leadingAnchor.constraint(equalTo: titleBar.leadingAnchor, constant: 10),
            titleLbl.centerYAnchor.constraint(equalTo: titleBar.centerYAnchor),
            grid.topAnchor.constraint(equalTo: titleBar.bottomAnchor, constant: 1),
            grid.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            grid.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
>>>>>>> Stashed changes
}

// MARK: - Control Window

final class ControlWindow: NSWindowController, RegionPickerDelegate {
<<<<<<< Updated upstream
    // Region fields
    private let xField = field("100");  private let yField = field("100")
    private let wField = field("300");  private let hField = field("120")
    // Display fields
    private let fontField  = field("Avenir-Heavy")
    private let sizeField  = field("64")
    private let colorWell  = NSColorWell()

    private var picker: RegionPicker?

    var onStart: ((CGRect, NSFont, NSColor) -> Void)?
=======
    private var config = AppConfig.load()
    private var picker: RegionPicker?
    private var allCells: [NBCell] = []
    private var isRunning = false

    private let topSection = NBTableSection(
        title: "Stronghold",
        rows: 2,
        cols: [
            ColumnDef(header: "Chunk",  key: "chunk"),
            ColumnDef(header: "%",      key: "pct"),
            ColumnDef(header: "Dist.",  key: "dist"),
            ColumnDef(header: "Nether", key: "nether"),
        ]
    )
    private let bottomSection = NBTableSection(
        title: "Eye Throws",
        rows: 3,
        cols: [
            ColumnDef(header: "X",     key: "x"),
            ColumnDef(header: "Z",     key: "z"),
            ColumnDef(header: "Angle", key: "angle"),
            ColumnDef(header: "Error", key: "error"),
        ]
    )

    private let startStopButton = NSButton()
    private let statusLabel     = NSTextField(labelWithString: "Not running")

    var onStart: (([String: CGRect]) -> Void)?
>>>>>>> Stashed changes
    var onStop:  (() -> Void)?

    init() {
        let win = NSWindow(
<<<<<<< Updated upstream
            contentRect: NSRect(x: 200, y: 200, width: 460, height: 320),
=======
            contentRect: NSRect(x: 100, y: 100, width: 380, height: 620),
>>>>>>> Stashed changes
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
<<<<<<< Updated upstream
        win.title = "Number OCR"
        super.init(window: win)
        buildUI(in: win.contentView!)
=======
        win.title = "NinjaOCR"
        win.backgroundColor = NSColor(white: 0.1, alpha: 1)
        super.init(window: win)
        buildUI(in: win.contentView!)
        applyConfig()
>>>>>>> Stashed changes
        win.makeKeyAndOrderFront(nil)
    }

    required init?(coder: NSCoder) { fatalError() }

<<<<<<< Updated upstream
    // MARK: - UI Layout

    private func buildUI(in root: NSView) {
        let stack = vstack(spacing: 16, insets: NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20))
        root.addSubview(stack)
        fill(stack, in: root)

        // Section: Capture Region
        stack.addArrangedSubview(sectionLabel("Capture Region"))
        stack.addArrangedSubview(hrow("X:", xField, "Y:", yField))
        stack.addArrangedSubview(hrow("W:", wField, "H:", hField))

        let pickBtn = button("⌖  Pick Region…", action: #selector(pickRegion))
        stack.addArrangedSubview(pickBtn)

        // Section: Display
        stack.addArrangedSubview(sectionLabel("Display"))
        stack.addArrangedSubview(hrow("Font:", fontField, "Size:", sizeField))

        colorWell.color = .systemGreen
        colorWell.widthAnchor.constraint(equalToConstant: 44).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let colorRow = NSStackView(views: [NSTextField(labelWithString: "Color:"), colorWell, NSView()])
        colorRow.spacing = 8
        stack.addArrangedSubview(colorRow)

        // Buttons
        let startBtn = button("▶  Start", action: #selector(startTapped))
        let stopBtn  = button("■  Stop",  action: #selector(stopTapped))
        let btnRow   = NSStackView(views: [startBtn, stopBtn])
        btnRow.distribution = .fillEqually
        btnRow.spacing = 12
        stack.addArrangedSubview(btnRow)
    }

    // MARK: - Actions

    @objc private func pickRegion() {
        picker = RegionPicker()
        picker?.delegate = self
    }

    func regionPicker(_ picker: RegionPicker, didSelect rect: CGRect) {
        DispatchQueue.main.async {
            self.xField.stringValue = String(Int(rect.origin.x))
            self.yField.stringValue = String(Int(rect.origin.y))
            self.wField.stringValue = String(Int(rect.width))
            self.hField.stringValue = String(Int(rect.height))
        }
    }

    @objc private func startTapped() {
        guard
            let x    = Double(xField.stringValue),
            let y    = Double(yField.stringValue),
            let w    = Double(wField.stringValue),
            let h    = Double(hField.stringValue),
            let size = Double(sizeField.stringValue)
        else {
            let alert = NSAlert()
            alert.messageText = "Invalid input"
            alert.informativeText = "X, Y, W, H and Size must all be numbers."
            alert.runModal()
            return
        }
        let font  = NSFont(name: fontField.stringValue, size: size) ?? .boldSystemFont(ofSize: size)
        let color = colorWell.color
        onStart?(CGRect(x: x, y: y, width: w, height: h), font, color)
    }

    @objc private func stopTapped() { onStop?() }

    // MARK: - Layout helpers

    private func hrow(_ l1: String, _ f1: NSTextField,
                      _ l2: String, _ f2: NSTextField) -> NSStackView {
        let s = NSStackView(views: [NSTextField(labelWithString: l1), f1,
                                    NSTextField(labelWithString: l2), f2])
        s.spacing = 8
        f1.widthAnchor.constraint(equalToConstant: 110).isActive = true
        f2.widthAnchor.constraint(equalToConstant: 110).isActive = true
        return s
    }
}

// MARK: - Layout utilities

private func field(_ s: String) -> NSTextField { NSTextField(string: s) }

private func sectionLabel(_ s: String) -> NSTextField {
    let l = NSTextField(labelWithString: s.uppercased())
    l.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
    l.textColor = .secondaryLabelColor
    return l
}

private func button(_ title: String, action: Selector) -> NSButton {
    let b = NSButton(title: title, target: nil, action: action)
    b.bezelStyle = .rounded
    return b
}

private func vstack(spacing: CGFloat, insets: NSEdgeInsets) -> NSStackView {
    let s = NSStackView()
    s.orientation  = .vertical
    s.alignment    = .leading
    s.spacing      = spacing
    s.edgeInsets   = insets
    s.translatesAutoresizingMaskIntoConstraints = false
    return s
}

private func fill(_ view: NSView, in parent: NSView) {
    NSLayoutConstraint.activate([
        view.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
        view.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
        view.topAnchor.constraint(equalTo: parent.topAnchor),
        view.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
    ])
=======
    private func buildUI(in root: NSView) {
        // Setup pick handlers
        for section in [topSection, bottomSection] {
            section.onPick = { [weak self] key in self?.startPicking(key: key) }
            allCells.append(contentsOf: section.cells)
        }

        // Stack
        let stack = NSStackView(views: [topSection, bottomSection])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Bottom bar
        startStopButton.bezelStyle = .rounded
        startStopButton.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        startStopButton.target = self
        startStopButton.action = #selector(toggleRunning)
        updateButtonState()

        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = NSColor(white: 0.5, alpha: 1)
        statusLabel.alignment = .center

        let bottomBar = NSStackView(views: [startStopButton, statusLabel])
        bottomBar.orientation = .vertical
        bottomBar.spacing = 6
        bottomBar.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(stack)
        root.addSubview(bottomBar)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            stack.centerXAnchor.constraint(equalTo: root.centerXAnchor),

            bottomBar.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 16),
            bottomBar.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            bottomBar.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -16),
            startStopButton.widthAnchor.constraint(equalToConstant: 160),
        ])
    }

    private func applyConfig() {
        for cell in allCells {
            cell.markConfigured(config.regions[cell.key] != nil)
        }
    }

    private func startPicking(key: String) {
        picker = RegionPicker(key: key)
        picker?.delegate = self
    }

    func regionPicker(_ picker: RegionPicker, didSelect rect: CGRect, forKey key: String) {
        config.regions[key] = RegionConfig(rect)
        config.save()
        DispatchQueue.main.async {
            self.allCells.first(where: { $0.key == key })?.markConfigured(true)
        }
    }

    @objc private func toggleRunning() {
        isRunning.toggle()
        updateButtonState()
        if isRunning {
            let rects = config.regions.mapValues { $0.cgRect }
            onStart?(rects)
            statusLabel.stringValue = "Running — \(rects.count) regions"
        } else {
            onStop?()
            statusLabel.stringValue = "Stopped"
        }
    }

    private func updateButtonState() {
        startStopButton.title = isRunning ? "■  Stop" : "▶  Start"
        startStopButton.contentTintColor = isRunning ? .systemRed : .systemGreen
    }

    func updateCell(key: String, value: String) {
        DispatchQueue.main.async {
            guard let cell = self.allCells.first(where: { $0.key == key }) else { return }
            // Color percentage values
            if key.hasSuffix("_pct"), let pct = Double(value.replacingOccurrences(of: "%", with: "")) {
                let color: NSColor = pct > 50 ? .systemGreen : pct > 10 ? .systemOrange : .systemRed
                cell.setValue(value, color: color)
            } else {
                cell.setValue(value)
            }
        }
    }
}

// MARK: - Overlay Window

final class OverlayWindow: NSWindowController {
    private var labels: [String: NSTextField] = [:]

    init() {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                           styleMask: .borderless, backing: .buffered, defer: false)
        win.level = .floating
        win.isOpaque = false
        win.backgroundColor = .clear
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: win)
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateLabel(key: String, value: String, at rect: CGRect) {
        DispatchQueue.main.async {
            if self.labels[key] == nil {
                let lbl = NSTextField(labelWithString: "--")
                lbl.font = NSFont.monospacedDigitSystemFont(ofSize: min(rect.height * 0.6, 32), weight: .bold)
                lbl.textColor = .systemGreen
                lbl.alignment = .center
                lbl.backgroundColor = NSColor.black.withAlphaComponent(0.55)
                lbl.drawsBackground = true
                lbl.isBezeled = false
                self.window?.contentView?.addSubview(lbl)
                self.labels[key] = lbl
            }
            let lbl = self.labels[key]!
            lbl.stringValue = value.isEmpty ? "--" : value
            lbl.frame = rect
            if self.window?.frame != NSScreen.main?.frame {
                self.window?.setFrame(NSScreen.main?.frame ?? .zero, display: false)
            }
            self.window?.makeKeyAndOrderFront(nil)
        }
    }
>>>>>>> Stashed changes
}

// MARK: - Coordinator

final class AppCoordinator {
<<<<<<< Updated upstream
    private let overlay  = OverlayWindow()
    private let controls = ControlWindow()
    private var timer:   Timer?
    private var region   = CGRect(x: 100, y: 100, width: 300, height: 120)
    private var font     = NSFont(name: "Avenir-Heavy", size: 64) ?? NSFont.boldSystemFont(ofSize: 64)
    private var color    = NSColor.systemGreen

    init() {
        controls.onStart = { [weak self] rect, font, color in
            self?.region = rect
            self?.font   = font
            self?.color  = color
=======
    private let controls = ControlWindow()
    private let overlay  = OverlayWindow()
    private var timer:   Timer?
    private var regions: [String: CGRect] = [:]

    init() {
        controls.onStart = { [weak self] rects in
            self?.regions = rects
>>>>>>> Stashed changes
            self?.startPolling()
        }
        controls.onStop = { [weak self] in self?.stopPolling() }
    }

    private func startPolling() {
        stopPolling()
        timer = .scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func stopPolling() { timer?.invalidate(); timer = nil }

    private func tick() {
<<<<<<< Updated upstream
        let (region, font, color) = (self.region, self.font, self.color)
        Task {
            guard let image = await captureRegion(region) else { return }
            let text = recognizeNumber(in: image)
            self.overlay.update(text: text, font: font, color: color)
=======
        let snapshot = regions
        Task {
            for (key, rect) in snapshot {
                guard let image = await captureRegion(rect) else { continue }
                let value = recognizeNumber(in: image)
                self.controls.updateCell(key: key, value: value)
                self.overlay.updateLabel(key: key, value: value, at: rect)
            }
>>>>>>> Stashed changes
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