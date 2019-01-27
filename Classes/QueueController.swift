//
//  QueueController.swift
//  Subler
//
//  Created by Damiano Galassi on 26/01/2019.
//

import Cocoa
import MP42Foundation

class QueueController : NSWindowController, NSWindowDelegate, NSPopoverDelegate, ItemViewDelegate, NSTableViewDataSource, NSTableViewDelegate, ExpandedTableViewDelegate, NSToolbarItemValidation, NSMenuItemValidation {

    static let shared = QueueController()

    private let queue: Queue
    private let prefs = QueuePreferences()
    private var popover: NSPopover?
    private var itemPopover: NSPopover?
    private var windowController: OptionsViewController?

    private let tablePasteboardType = NSPasteboard.PasteboardType("SublerBatchTableViewDataType")
    private lazy var docImg: NSImage = {
        // Load a generic movie icon to display in the table view
        let img = NSWorkspace.shared.icon(forFileType: "mov")
        img.size = NSSize(width: 16, height: 16)
        return img
    }()

    @IBOutlet var table: ExpandedTableView!
    @IBOutlet var startItem: NSToolbarItem!
    @IBOutlet var statusLabel: NSTextField!
    @IBOutlet var progressBar: NSProgressIndicator!

    override var windowNibName: NSNib.Name? {
        return "Queue"
    }

    private init() {
        popover = nil
        itemPopover = nil
        windowController = nil
        QueuePreferences.registerUserDefaults()
        if let url = prefs.queueURL {
            queue = Queue(url: url)
        } else {
            fatalError("Invalid queue url")
        }
        super.init(window: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func windowDidLoad() {
        super.windowDidLoad()

        if #available(OSX 10.12, *) {
            window?.tabbingMode = .disallowed
        }

        table.registerForDraggedTypes([NSPasteboard.PasteboardType.backwardsCompatibleFileURL, tablePasteboardType])
        progressBar.isHidden = true

        let main = OperationQueue.main
        let nc = NotificationCenter.default

        nc.addObserver(forName: Queue.Working, object: queue, queue: main) {(note) in
            guard let info = note.userInfo,
                let status = info["ProgressString"] as? String,
                let progress = info["Progress"] as? Double,
                let index = info["ItemIndex"] as? Int
                else { return }

            self.statusLabel.stringValue = status
            self.progressBar.isIndeterminate = false
            self.progressBar.doubleValue = progress

            if index != NSNotFound {
                self.updateUI(indexes: IndexSet(integer: index))
            }
        }

        nc.addObserver(forName: Queue.Completed, object: queue, queue: main) { (note) in
            self.progressBar.isHidden = true
            self.progressBar.stopAnimation(self)
            self.progressBar.doubleValue = 0
            self.progressBar.isIndeterminate = true

            self.startItem.image = NSImage(named: "playBackTemplate")
            self.statusLabel.stringValue = NSLocalizedString("Done", comment: "Queue -> Done")

            self.updateUI()

            if self.prefs.showDoneNotification, let info = note.userInfo {
                let notification = NSUserNotification()
                notification.title = NSLocalizedString("Queue Done", comment: "")

                if let failedCount = info["FailedCount"] as? UInt,
                    let completedCount = info["CompletedCount"] as? UInt {
                    notification.informativeText = "Completed: \(completedCount); Failed: \(failedCount)"
                }
                else if let completedCount = info["CompletedCount"] as? UInt {
                    notification.informativeText = "Completed: \(completedCount)"
                }
                notification.soundName = NSUserNotificationDefaultSoundName
                NSUserNotificationCenter.default.deliver(notification)
            }
        }

        // Update the UI the first time
        updateUI()
    }

    //MARK: User Interface Validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let action = menuItem.action

        if action == #selector(removeSelectedItems(_:)) {
            if let row = table?.selectedRow, row != -1 {
                let item = queue.item(at: row)
                if item.status != .working {
                    return true
                }
            } else if let row = table?.clickedRow, row != -1 {
                let item = queue.item(at: row)
                if item.status != .working {
                    return true
                }
            }
        }

        if action == #selector(showInFinder(_:)) {
            if let row = table?.clickedRow, row != -1 {
                let item = queue.item(at: row)
                if item.status == .completed {
                    return true
                }
            }
        }

        if action == #selector(edit(_:)) {
            if let row = table?.clickedRow, row != -1 {
                let item = queue.item(at: row)
                if item.status == .completed || item.status == .ready {
                    return true
                }
            }
        }

        if action == #selector(removeCompletedItems(_:)) {
            return true
        }

        return false
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        return true
    }

    //MARK: Queue

    func saveToDisk() throws {
        prefs.saveUserDefaults()
        try queue.saveToDisk()
    }

    internal func edit(item: SBQueueItem) {
        let originalStatus = item.status
        item.status = SBQueueItemStatus.working

        updateUI()

        DispatchQueue.global().async {
            if originalStatus != SBQueueItemStatus.completed {
                do {
                    try item.prepare()
                } catch {
                    self.presentError(error)
                }
            }

            DispatchQueue.main.async {
                do {
                    var doc: Document?
                    if originalStatus == SBQueueItemStatus.completed {
                        try doc = Document(contentsOf: item.destURL, ofType: "")
                    } else if let mp4 = item.mp4File {
                        doc = Document(mp4: mp4)
                    }

                    if let doc = doc {
                        NSDocumentController.shared.addDocument(doc)
                        doc.makeWindowControllers()
                        doc.showWindows()

                        self.itemPopover?.close()

                        item.status = originalStatus
                        let index = self.queue.index(of: item)
                        self.remove(at: index)
                        self.updateUI()
                    }
                } catch {
                    self.presentError(error)
                }
            }
        }
    }

    //MARK: Items creation

    /// Creates a new SBQueueItem from an NSURL,
    /// and adds the current actions to it.
    private func createItem(url: URL) -> SBQueueItem {
        let item = SBQueueItem(url: url)

        if prefs.clearExistingMetadata {
            item.addAction(QueueClearExistingMetadataAction())
        }
        if prefs.searchMetadata {
            item.addAction(QueueMetadataAction(movieLanguage: prefs.movieProviderLanguage,tvShowLanguage: prefs.tvShowProviderLanguage, movieProvider: prefs.movieProvider, tvShowProvider: prefs.tvShowProvider, preferredArtwork: prefs.providerArtwork))
        }
        if prefs.setOutputFilename {
            item.addAction(QueueSetOutputFilenameAction())
        }
        if prefs.subtitles {
            item.addAction(QueueSubtitlesAction())
        }
        if prefs.organize {
            item.addAction(QueueOrganizeGroupsAction())
        }
        if prefs.fixFallbacks {
            item.addAction(QueueFixFallbacksAction())
        }
        if prefs.clearTrackName {
            item.addAction(QueueClearTrackNameAction())
        }
        if prefs.fixTrackLanguage {
            item.addAction(QueueSetLanguageAction(language: prefs.fixTrackLanguageValue))
        }
        if prefs.applyColorSpace {
            item.addAction(QueueColorSpaceAction(tag: QueueColorSpaceActionTag(rawValue: UInt16(prefs.applyColorSpaceValue))!))
        }
        if let set = prefs.metadataSet {
            item.addAction(QueueSetAction(preset: set))
        }
        if prefs.optimize {
            item.addAction(QueueOptimizeAction())
        }
        if prefs.sendToiTunes {
            item.addAction(QueueSendToiTunesAction())
        }

        let value = try? url.resourceValues(forKeys: [URLResourceKey.typeIdentifierKey])

        if let destination = prefs.destination {
            item.destURL = destination.appendingPathComponent(url.lastPathComponent).deletingPathExtension().appendingPathExtension(prefs.fileType)
        } else if let type = value?.typeIdentifier,  UTTypeConformsTo(type as CFString, "public.mpeg-4" as CFString) {
            item.destURL = url
        } else {
            item.destURL = url.deletingPathExtension().appendingPathExtension(prefs.fileType)
        }

        return item
    }

    //MARK: Queue management

    var status: Queue.Status {
        get {
            return queue.status
        }
    }

    var count: Int {
        get {
            return queue.count
        }
    }

    func items(at indexes: IndexSet) -> [SBQueueItem] {
        return queue.items(at: indexes)
    }

    /// Adds a SBQueueItem to the queue
    func add(_ item: SBQueueItem) {
        insert(items: [item], at: IndexSet(integer: IndexSet.Element(queue.count)))
    }

    func add(_ item: SBQueueItem, applyPreset: Bool) {
        //WHY APPLY PRESET?
        if prefs.optimize {
            item.addAction(QueueOptimizeAction())
        }
        add(item)
    }

    private func add(_ items: [SBQueueItem], at index: Int) {
        let indexes = IndexSet(integersIn: index ..< (index + items.count))
        insert(items: items, at: indexes)
    }

    /// Adds an array of SBQueueItem to the queue.
    /// Implements the undo manager.
    func insert(items: [SBQueueItem], at indexes: IndexSet) {
        guard let firstIndex = indexes.first else { fatalError() }

        table.beginUpdates()

        // Forward
        var currentIndex = firstIndex
        var currentObjectIndex = 0

        while currentIndex != NSNotFound {
            queue.insert(items[currentObjectIndex], at: currentIndex)
            currentIndex = indexes.integerGreaterThan(currentIndex) ?? NSNotFound
            currentObjectIndex += 1
        }

        table.insertRows(at: indexes, withAnimation: .slideDown)
        table.endUpdates()
        updateState()

        guard let undo = window?.undoManager else { return }

        undo.registerUndo(withTarget: self) { (target) in
            self.remove(at: indexes)
        }

        if undo.isUndoing == false {
            undo.setActionName(NSLocalizedString("Add Queue Item", comment: "Queue -> redo add item."))
        }

        if undo.isUndoing || undo.isRedoing {
            if prefs.autoStart {
                start(self)
            }
        }
    }

    private func remove(at index: Int) {
        remove(at: IndexSet(integer: IndexSet.Element(index)))
    }

    func remove(at indexes: IndexSet) {
        if indexes.isEmpty {
            return
        }

        table.beginUpdates()

        let removedItems = queue.items(at: indexes)

        if queue.count > indexes.last! {
            queue.remove(at: indexes)
        }

        table.removeRows(at: indexes, withAnimation: .slideUp)
        table.selectRowIndexes(IndexSet(integer: indexes.first!), byExtendingSelection: false)

        table.endUpdates()
        updateState()

        guard let undo = window?.undoManager else { return }

        undo.registerUndo(withTarget: self) { (target) in
            self.insert(items: removedItems, at: indexes)
        }

        if undo.isUndoing == false {
            undo.setActionName(NSLocalizedString("Remove Queue Item", comment: "Queue -> redo add item."))
        }
    }

    private func move(items: [SBQueueItem], at index: Int) {
        var currentIndex = index
        var source: [Int] = Array()
        var dest: [Int] = Array()

        table.beginUpdates()

        for item in items.reversed() {
            let sourceIndex = queue.index(of: item)
            queue.remove(at: IndexSet(integer: IndexSet.Element(sourceIndex)))

            if sourceIndex < currentIndex {
                currentIndex -= 1
            }

            queue.insert(item, at: currentIndex)

            source.append(currentIndex)
            dest.append(sourceIndex)

            table.moveRow(at: Int(sourceIndex), to: Int(currentIndex))
        }

        table.endUpdates()

        guard let undo = window?.undoManager else { return }

        undo.registerUndo(withTarget: self) { (target) in
            self.move(at: source, to: dest)
        }

        if undo.isUndoing == false {
            undo.setActionName(NSLocalizedString("Move Queue Item", comment: "Queue -> move add item."))
        }
    }

    private func move(at source: [Int], to dest: [Int]) {
        var newSource: [Int] = Array()
        var newDest: [Int] = Array()

        table.beginUpdates()

        for (sourceIndex, destIndex) in zip(source, dest).reversed() {
            newSource.append(destIndex)
            newDest.append(sourceIndex)

            if let item = queue.items(at: IndexSet(integer: IndexSet.Element(sourceIndex))).first {
                queue.remove(at: IndexSet(integer: IndexSet.Element(sourceIndex)))
                queue.insert(item, at: destIndex)

                table.moveRow(at: sourceIndex, to: destIndex)
            }
        }

        table.endUpdates()

        guard let undo = window?.undoManager else { return }

        undo.registerUndo(withTarget: self) { (target) in
            self.move(at: newSource, to: newDest)
        }

        if undo.isUndoing == false {
            undo.setActionName(NSLocalizedString("Move Queue Item", comment: "Queue -> move add item."))
        }
    }

    //MARK: Popover delegate

    /// Creates a popover with the queue options.
    private func createOptionsPopover() {
        if popover == nil {
            let p = NSPopover()
            p.contentViewController = OptionsViewController(options: prefs)
            p.animates = true
            p.behavior = NSPopover.Behavior.semitransient
            p.delegate = self

            popover = p
        }
    }

    /// Creates a popover with a SBQueueItem
    private func createItemPopover(_ item: SBQueueItem) {
        let p = NSPopover()

        let view = ItemViewController(item: item, delegate: self)
        p.contentViewController = view
        p.animates = true
        p.behavior = NSPopover.Behavior.semitransient
        p.delegate = self

        itemPopover = p
    }

    func popoverShouldDetach(_ popover: NSPopover) -> Bool {
        return popover == self.popover
    }

    func popoverDidClose(_ notification: Notification) {
        guard let closedPopover = notification.object as? NSPopover
            else { return }

        if popover == closedPopover {
            popover = nil
        }
        if itemPopover == closedPopover {
            itemPopover = nil
        }
    }

    func windowWillClose(_ notification: Notification) {
        windowController = nil
    }

    //MARK: UI

    /// Updates the count on the app dock icon.
    private func updateDockTile() {
        let count = queue.readyCount + ((queue.status == .working) ? 1 : 0)

        if count > 0 {
            NSApp.dockTile.badgeLabel = "\(count)"
        } else {
            NSApp.dockTile.badgeLabel = nil
        }
    }

    private func updateUI(indexes: IndexSet) {
        table.reloadData(forRowIndexes: indexes, columnIndexes: IndexSet(integer: 0))
        updateState()
    }

    private func updateUI() {
        table.reloadData()
        updateState()
    }

    private func updateState() {
        if queue.status != .working {
            if queue.count == 1 {
                statusLabel.stringValue = NSLocalizedString("1 item in queue", comment: "")
            } else {
                statusLabel.stringValue = String.localizedStringWithFormat(NSLocalizedString("%lu items in queue.", comment: ""), queue.count)
            }
        }
        updateDockTile()
    }

    @IBAction func start(_ sender: Any?) {
        if queue.status == .working {
            return
        }

        startItem.image = NSImage(named: "stopTemplate")
        statusLabel.stringValue = NSLocalizedString("Working.", comment: "Queue -> Working")
        progressBar.isHidden = false
        progressBar.startAnimation(self)

        window?.undoManager?.removeAllActions(withTarget: self)

        queue.start()
    }

    @IBAction func stop(_ sender: Any?) {
        queue.stop()
    }

    @IBAction func toggleStartStop(_ sender: Any?) {
        if queue.status == .working {
            stop(self)
        } else {
            start(self)
        }
    }

    @IBAction func toggleOptions(_ sender: Any?) {
        createOptionsPopover()

        if let p = popover, p.isShown == false {
            if let target = ((sender as? NSView) != nil) ? sender as? NSView : window?.contentView {
                p.show(relativeTo: target.bounds, of: target, preferredEdge: .maxY)
            }
        } else {
            popover?.close()
            popover = nil
        }
    }

    @IBAction func toggleItemsOptions(_ sender: Any?) {
        guard let sender = sender as? NSView else { return }
        let index = table.row(for: sender)
        let item = queue.item(at: index)

        if let p = itemPopover, p.isShown, let controller = p.contentViewController as? ItemViewController, controller.item == item {
            p.close()
            itemPopover = nil
        } else {
            createItemPopover(item)
            itemPopover?.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxX)
        }
    }

    //MARK: Open

    private func itemsFrom(url: URL) -> [SBQueueItem] {
        var items: [SBQueueItem] = Array()
        let supportedFileFormats = MP42FileImporter.supportedFileFormats()

        let value = try? url.resourceValues(forKeys: [URLResourceKey.isDirectoryKey])

        if let isDirectory = value?.isDirectory, isDirectory == true,
            let directoryEnumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [URLResourceKey.nameKey, URLResourceKey.isDirectoryKey], options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles], errorHandler: nil) {

            for fileURL in directoryEnumerator {

                if let value = try? url.resourceValues(forKeys: [URLResourceKey.isDirectoryKey]), let isDirectory = value.isDirectory, isDirectory == false, let fileURL = fileURL as? URL, supportedFileFormats.contains(fileURL.pathExtension.lowercased()) {

                    items.append(createItem(url: fileURL))

                }
            }
        } else if supportedFileFormats.contains(url.pathExtension.lowercased()) {
            items.append(createItem(url: url))
        }

        return items
    }

    func addItemsFrom(urls: [URL], at index: Int) {
        var items: [SBQueueItem] = Array()

        for url in urls {
            let itemsFromURL = itemsFrom(url: url)

            for item in itemsFromURL {
                items.append(item)
            }
        }
        add(items, at: index)
    }

    @IBAction func open(_ sender: Any?) {
        guard let windowForSheet = window else { return }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedFileTypes = MP42FileImporter.supportedFileFormats()

        panel.beginSheetModal(for: windowForSheet) { (response) in
            if response == NSApplication.ModalResponse.OK {
                self.addItemsFrom(urls: panel.urls, at: Int(self.queue.count))
            }
        }
    }

    //MARK: Table View

    func numberOfRows(in tableView: NSTableView) -> Int {
        return Int(queue.count)
    }

    private let nameColumn = NSUserInterfaceItemIdentifier(rawValue: "nameColumn")

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = queue.item(at: row)

        if tableColumn?.identifier == nameColumn {
            let cell = tableView.makeView(withIdentifier: nameColumn, owner: self) as? NSTableCellView
            cell?.textField?.stringValue = item.fileURL.lastPathComponent

            switch item.status {
            case .editing:
                cell?.imageView?.image = NSImage(named: "EncodeWorking")
            case .working:
                cell?.imageView?.image = NSImage(named: "EncodeWorking")
            case .completed:
                cell?.imageView?.image = NSImage(named: "EncodeComplete")
            case .failed:
                cell?.imageView?.image = NSImage(named: "EncodeCanceled")
            case .cancelled:
                cell?.imageView?.image = NSImage(named: "EncodeCanceled")
            case .ready,
                 .unknown:
                cell?.imageView?.image = docImg
            @unknown default:
                cell?.imageView?.image = docImg
            }

            return cell
        }

        return nil
    }

    func deleteSelection(in tableView: NSTableView) {
        var rowIndexes = tableView.selectedRowIndexes
        let clickedRow = tableView.clickedRow

        if clickedRow != -1 && rowIndexes.contains(clickedRow) == false {
            rowIndexes.removeAll()
            rowIndexes.insert(clickedRow)
        }

        let items = queue.items(at: rowIndexes)

        for item in items where item.status == .working {
            rowIndexes.remove(IndexSet.Element(queue.index(of: item)))
        }

        if rowIndexes.isEmpty == false {
            remove(at: rowIndexes)
        }
    }

    @IBAction func edit(_ sender: Any?) {
        let clickedRow = table.clickedRow
        if clickedRow > -1 {
            let item = queue.item(at: clickedRow)
            edit(item: item)
        }
    }

    @IBAction func showInFinder(_ sender: Any?) {
        let clickedRow = table.clickedRow
        if clickedRow > -1 {
            let item = queue.item(at: clickedRow)
            NSWorkspace.shared.activateFileViewerSelecting([item.destURL])
        }
    }

    @IBAction func removeSelectedItems(_ sender: Any?) {
        deleteSelection(in: table)
    }

    @IBAction func removeCompletedItems(_ sender: Any?) {
        let indexes = queue.indexesOfItems(with: .completed)

        if indexes.isEmpty == false {
            table.removeRows(at: indexes, withAnimation: .slideUp)
            queue.remove(at: indexes)
            updateState()
        }
    }

    //MARK: Drag & Drop

    func tableView(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to pboard: NSPasteboard) -> Bool {
        let data = NSKeyedArchiver.archivedData(withRootObject: rowIndexes)
        pboard.declareTypes([tablePasteboardType], owner: self)
        pboard.setData(data, forType: tablePasteboardType)
        return true
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        if info.draggingSource == nil {
            tableView.setDropRow(row, dropOperation: .above)
            return .copy
        } else if let source = info.draggingSource as? NSTableView, tableView == source && dropOperation == .above {
            return .every
        } else {
            return []
        }
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        let pboard = info.draggingPasteboard

        if let source = info.draggingSource as? NSTableView, source == tableView,
            let rowData = pboard.data(forType: tablePasteboardType),
            let rowIndexes = NSKeyedUnarchiver.unarchiveObject(with: rowData) as? IndexSet {

            let items = queue.items(at: rowIndexes)
            move(items: items, at: row)
            return true

        } else {

            if pboard.types?.contains(NSPasteboard.PasteboardType.backwardsCompatibleFileURL) ?? false {

                if let items = pboard.readObjects(forClasses: [NSURL.classForCoder()], options: [:]) as? [URL] {
                    addItemsFrom(urls: items, at: row)
                }

                return true
            }
        }

        return false
    }
}