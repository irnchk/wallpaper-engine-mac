import AppKit
import ImageIO
import WallpaperEngineCore

@MainActor
final class LibraryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    var projects: [WallpaperProject] = [] {
        didSet {
            tableView.reloadData()
            updateButtons()
        }
    }

    var onImportRequested: (() -> Void)?
    var onApplyRequested: ((WallpaperProject) -> Void)?
    var onSetLightRequested: ((WallpaperProject) -> Void)?
    var onSetDarkRequested: ((WallpaperProject) -> Void)?
    var onRevealRequested: ((WallpaperProject) -> Void)?

    private let tableView = NSTableView()
    private let thumbnailCache = ThumbnailCache(maxPixelSize: 96)
    private let applyButton = NSButton(title: "Apply", target: nil, action: nil)
    private let setLightButton = NSButton(title: "Set Light/Day", target: nil, action: nil)
    private let setDarkButton = NSButton(title: "Set Dark/Night", target: nil, action: nil)
    private let revealButton = NSButton(title: "Reveal", target: nil, action: nil)

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Wallpaper Library"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        projects.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < projects.count else {
            return nil
        }

        let project = projects[row]
        let identifier = tableColumn?.identifier.rawValue ?? "cell"
        let text: String

        switch identifier {
        case "preview":
            return previewCell(for: project)
        case "title":
            text = project.title
        case "type":
            text = project.type.rawValue.capitalized
        case "status":
            text = project.supportStatus.label
        default:
            text = ""
        }

        let field = NSTextField(labelWithString: text)
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        return field
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtons()
    }

    private func buildContent() {
        guard let contentView = window?.contentView else {
            return
        }

        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.headerView = NSTableHeaderView()
        tableView.rowHeight = 58

        let previewColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("preview"))
        previewColumn.title = ""
        previewColumn.width = 86
        previewColumn.minWidth = 86
        previewColumn.maxWidth = 86
        tableView.addTableColumn(previewColumn)

        let titleColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        titleColumn.title = "Title"
        titleColumn.width = 270
        tableView.addTableColumn(titleColumn)

        let typeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("type"))
        typeColumn.title = "Type"
        typeColumn.width = 90
        tableView.addTableColumn(typeColumn)

        let statusColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("status"))
        statusColumn.title = "Status"
        statusColumn.width = 330
        tableView.addTableColumn(statusColumn)

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let importButton = NSButton(title: "Import", target: self, action: #selector(importClicked))
        applyButton.target = self
        applyButton.action = #selector(applyClicked)
        setLightButton.target = self
        setLightButton.action = #selector(setLightClicked)
        setDarkButton.target = self
        setDarkButton.action = #selector(setDarkClicked)
        revealButton.target = self
        revealButton.action = #selector(revealClicked)

        let controls = NSStackView(views: [importButton, applyButton, setLightButton, setDarkButton, revealButton])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 8
        controls.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(scrollView)
        contentView.addSubview(controls)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            scrollView.bottomAnchor.constraint(equalTo: controls.topAnchor, constant: -12),

            controls.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            controls.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])

        updateButtons()
    }

    private func previewCell(for project: WallpaperProject) -> NSView {
        let identifier = NSUserInterfaceItemIdentifier("previewCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? PreviewCellView
            ?? PreviewCellView(identifier: identifier)
        cell.configure(image: thumbnailCache.image(for: project.previewURL))
        return cell
    }

    @objc
    private func importClicked() {
        onImportRequested?()
    }

    @objc
    private func applyClicked() {
        guard let project = selectedProject else {
            return
        }
        onApplyRequested?(project)
    }

    @objc
    private func setLightClicked() {
        guard let project = selectedProject else {
            return
        }
        onSetLightRequested?(project)
    }

    @objc
    private func setDarkClicked() {
        guard let project = selectedProject else {
            return
        }
        onSetDarkRequested?(project)
    }

    @objc
    private func revealClicked() {
        guard let project = selectedProject else {
            return
        }
        onRevealRequested?(project)
    }

    private var selectedProject: WallpaperProject? {
        let row = tableView.selectedRow
        guard row >= 0, row < projects.count else {
            return nil
        }
        return projects[row]
    }

    private func updateButtons() {
        let project = selectedProject
        applyButton.isEnabled = project?.isPlayableNow == true
        setLightButton.isEnabled = project?.isPlayableNow == true
        setDarkButton.isEnabled = project?.isPlayableNow == true
        revealButton.isEnabled = project != nil
    }
}

private final class PreviewCellView: NSTableCellView {
    private let thumbnailView = NSImageView()

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        thumbnailView.layer?.cornerRadius = 4
        thumbnailView.layer?.masksToBounds = true
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(thumbnailView)
        NSLayoutConstraint.activate([
            thumbnailView.widthAnchor.constraint(equalToConstant: 72),
            thumbnailView.heightAnchor.constraint(equalToConstant: 42),
            thumbnailView.centerXAnchor.constraint(equalTo: centerXAnchor),
            thumbnailView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(image: NSImage?) {
        thumbnailView.image = image
    }
}

private final class ThumbnailCache {
    private let cache = NSCache<NSURL, NSImage>()
    private let maxPixelSize: Int

    init(maxPixelSize: Int) {
        self.maxPixelSize = maxPixelSize
        cache.countLimit = 200
    }

    func image(for url: URL?) -> NSImage? {
        guard let url else {
            return nil
        }

        let key = url.standardizedFileURL as NSURL
        if let cachedImage = cache.object(forKey: key) {
            return cachedImage
        }

        guard let image = loadThumbnail(url: url) else {
            return nil
        }

        cache.setObject(image, forKey: key)
        return image
    }

    private func loadThumbnail(url: URL) -> NSImage? {
        let sourceOptions = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }

        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }
}
