import Cocoa

// MARK: - Models

struct VolumeStorageInfo {
    let name: String
    let available: Int64
    let total: Int64

    var used: Int64 { max(0, total - available) }
    var usageFraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(used) / Double(total)))
    }
    var usagePercent: Int { Int((usageFraction * 100).rounded()) }

    func formatGB(_ bytes: Int64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
    }
}

enum DisplayMode: Int, CaseIterable {
    case free
    case usedPercent
    case fraction

    var label: String {
        switch self {
        case .free: return "剩余空间"
        case .usedPercent: return "已用百分比"
        case .fraction: return "剩余 / 总计"
        }
    }

    func statusText(for info: VolumeStorageInfo) -> String {
        switch self {
        case .free:
            return String(format: "%.1fG", Double(info.available) / 1_000_000_000)
        case .usedPercent:
            return "\(info.usagePercent)%"
        case .fraction:
            let free = Double(info.available) / 1_000_000_000
            let total = Double(info.total) / 1_000_000_000
            return String(format: "%.0f/%.0fG", free, total)
        }
    }
}

// MARK: - Menu Header View

final class StorageMenuHeaderView: NSView {
    private let nameLabel = NSTextField(labelWithString: "")
    private let percentLabel = NSTextField(labelWithString: "")
    private let progressTrack = NSView()
    private let progressFill = NSView()
    private let statLabels: [NSTextField]
    private let statValues: [NSTextField]
    private var usageFraction: Double = 0

    private let statTitles = ["可用", "已用", "总计"]

    init(width: CGFloat = 272) {
        statLabels = statTitles.map { title in
            let label = NSTextField(labelWithString: title)
            label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.alignment = .center
            return label
        }
        statValues = (0..<3).map { _ in
            let label = NSTextField(labelWithString: "—")
            label.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            label.textColor = .labelColor
            label.alignment = .center
            return label
        }

        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 118))

        nameLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        nameLabel.textColor = .labelColor

        percentLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        percentLabel.textColor = .secondaryLabelColor
        percentLabel.alignment = .right

        progressTrack.wantsLayer = true
        progressTrack.layer?.cornerRadius = 4
        progressTrack.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor

        progressFill.wantsLayer = true
        progressFill.layer?.cornerRadius = 4

        [nameLabel, percentLabel, progressTrack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        progressFill.translatesAutoresizingMaskIntoConstraints = true
        addSubview(progressFill)
        (statLabels + statValues).forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        let columnWidth = (width - 28) / 3
        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: percentLabel.leadingAnchor, constant: -8),

            percentLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            percentLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            percentLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),

            progressTrack.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 10),
            progressTrack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            progressTrack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            progressTrack.heightAnchor.constraint(equalToConstant: 8),
        ])

        for (index, titleLabel) in statLabels.enumerated() {
            let valueLabel = statValues[index]
            let xOffset = 14 + CGFloat(index) * columnWidth
            NSLayoutConstraint.activate([
                titleLabel.topAnchor.constraint(equalTo: progressTrack.bottomAnchor, constant: 14),
                titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: xOffset),
                titleLabel.widthAnchor.constraint(equalToConstant: columnWidth),

                valueLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
                valueLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
                valueLabel.widthAnchor.constraint(equalTo: titleLabel.widthAnchor),
            ])
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let track = progressTrack.frame
        let fillWidth = max(0, track.width * usageFraction)
        progressFill.frame = NSRect(x: track.minX, y: track.minY, width: fillWidth, height: track.height)
    }

    func update(with info: VolumeStorageInfo) {
        nameLabel.stringValue = info.name
        percentLabel.stringValue = "\(info.usagePercent)%"
        statValues[0].stringValue = info.formatGB(info.available)
        statValues[1].stringValue = info.formatGB(info.used)
        statValues[2].stringValue = info.formatGB(info.total)

        usageFraction = info.usageFraction
        progressFill.layer?.backgroundColor = Self.usageColor(for: info.usageFraction).cgColor
        percentLabel.textColor = Self.usageColor(for: info.usageFraction)
        statValues[0].textColor = Self.availableColor(for: info)
        needsLayout = true
    }

    static func usageColor(for fraction: Double) -> NSColor {
        switch fraction {
        case ..<0.70: return .systemGreen
        case ..<0.85: return .systemOrange
        default: return .systemRed
        }
    }

    static func availableColor(for info: VolumeStorageInfo) -> NSColor {
        let freeFraction = 1 - info.usageFraction
        switch freeFraction {
        case 0.30...: return .systemGreen
        case 0.15..<0.30: return .systemOrange
        default: return .systemRed
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?
    private var menu = NSMenu()
    private let headerView = StorageMenuHeaderView()
    private var headerMenuItem = NSMenuItem()
    private var displayModeMenu = NSMenu()
    private var lastInfo: VolumeStorageInfo?

    private let lowSpaceThresholdGB: Double = 20
    private let refreshInterval: TimeInterval = 60

    private var displayMode: DisplayMode {
        get {
            DisplayMode(rawValue: UserDefaults.standard.integer(forKey: "displayMode")) ?? .free
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "displayMode")
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        buildMenu()
        statusItem.menu = menu
        refreshStorage()

        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refreshStorage()
        }
    }

    private func setupStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = nil
        button.imagePosition = .noImage
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    }

    private func buildMenu() {
        menu.removeAllItems()
        menu.delegate = self

        headerMenuItem = NSMenuItem()
        headerMenuItem.view = headerView
        headerMenuItem.isEnabled = false
        menu.addItem(headerMenuItem)
        menu.addItem(.separator())

        let displayItem = NSMenuItem(title: "显示方式", action: nil, keyEquivalent: "")
        displayModeMenu = NSMenu()
        for mode in DisplayMode.allCases {
            let item = NSMenuItem(title: mode.label, action: #selector(selectDisplayMode(_:)), keyEquivalent: "")
            item.target = self
            item.tag = mode.rawValue
            item.state = (mode == displayMode) ? .on : .off
            displayModeMenu.addItem(item)
        }
        displayItem.submenu = displayModeMenu
        menu.addItem(displayItem)
        menu.addItem(.separator())

        menu.addItem(makeActionItem("打开「存储」设置", action: #selector(openStorageSettings), symbolName: "internaldrive"))
        menu.addItem(makeActionItem("打开「下载」文件夹", action: #selector(openDownloads), symbolName: "arrow.down.circle"))
        menu.addItem(makeActionItem("打开「缓存」文件夹", action: #selector(openCaches), symbolName: "folder"))
        menu.addItem(.separator())

        menu.addItem(makeActionItem("立即刷新", action: #selector(refreshNow), symbolName: "arrow.clockwise", keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(makeActionItem("退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func makeActionItem(
        _ title: String,
        action: Selector,
        symbolName: String? = nil,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        if let symbolName,
           let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            item.image = image.withSymbolConfiguration(config)
        }
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshStorage()
    }

    @objc private func refreshNow() {
        refreshStorage()
    }

    @objc private func selectDisplayMode(_ sender: NSMenuItem) {
        guard let mode = DisplayMode(rawValue: sender.tag) else { return }
        displayMode = mode
        for item in displayModeMenu.items {
            item.state = (item.tag == mode.rawValue) ? .on : .off
        }
        updateStatusBar()
    }

    @objc private func openStorageSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.Storage",
            "x-apple.systempreferences:com.apple.preference.storage",
        ]
        for urlString in urls {
            if let url = URL(string: urlString), NSWorkspace.shared.open(url) { return }
        }
    }

    @objc private func openDownloads() {
        openFolder(relativeToHome: "Downloads")
    }

    @objc private func openCaches() {
        openFolder(relativeToHome: "Library/Caches")
    }

    private let finderAppURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")

    private func openInFinder(_ url: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: finderAppURL, configuration: config)
    }

    private func openFolder(relativeToHome path: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(path)
        openInFinder(url)
    }

    private func volumeInfo(for volumeURL: URL) -> VolumeStorageInfo? {
        let keys: Set<URLResourceKey> = [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeTotalCapacityKey,
            .volumeNameKey,
        ]
        guard let values = try? volumeURL.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity else { return nil }

        let available: Int64
        if let important = values.volumeAvailableCapacityForImportantUsage {
            available = Int64(important)
        } else if let capacity = values.volumeAvailableCapacity {
            available = Int64(capacity)
        } else {
            return nil
        }

        let name = values.volumeName ?? "Macintosh HD"
        return VolumeStorageInfo(name: name, available: available, total: Int64(total))
    }

    private func refreshStorage() {
        let volumeURL = URL(fileURLWithPath: "/")
        lastInfo = volumeInfo(for: volumeURL)
        updateStatusBar()
        if let info = lastInfo {
            headerView.update(with: info)
        }
    }

    private func updateStatusBar() {
        guard let button = statusItem.button else { return }

        guard let info = lastInfo else {
            button.title = ""
            button.attributedTitle = NSAttributedString(string: "??G")
            button.toolTip = "无法读取磁盘信息"
            return
        }

        let text = displayMode.statusText(for: info)
        button.title = ""

        let freeGB = Double(info.available) / 1_000_000_000
        let isLow = freeGB < lowSpaceThresholdGB || info.usageFraction >= 0.90
        let color: NSColor = isLow ? .systemOrange : .labelColor

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: color,
        ]
        button.attributedTitle = NSAttributedString(string: text, attributes: attributes)

        let warning = isLow ? " · 空间偏低" : ""
        button.toolTip = """
        \(info.name)
        可用 \(info.formatGB(info.available)) · 已用 \(info.usagePercent)%\(warning)
        """
    }
}

// MARK: - Entry

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
