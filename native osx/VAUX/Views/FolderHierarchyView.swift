import SwiftUI
import AppKit

struct FolderHierarchyView: View {
    @ObservedObject var collectionService: CollectionService
    @ObservedObject var audioService: AudioService
    @ObservedObject var folderManager: FolderHierarchyManager
    @ObservedObject var searchService: SearchService
    @ObservedObject var playlistService: PlaylistService
    /// Opens the chosen playlist as the main content (same as selecting it in the sidebar).
    var onNavigateToPlaylist: ((Playlist) -> Void)?
    @EnvironmentObject var waveformServiceHolder: WaveformServiceHolder
    @StateObject private var metadataManager: TrackMetadataManager

    @State private var sortOrder = [KeyPathComparator(\FolderHierarchyTableRow.titleSort)]
    @State private var selectedRowIds = Set<String>()
    @State private var visibleColumns: Set<TrackColumn> = [.waveformData, .title, .artist, .album, .duration, .rating, .generalTags, .type, .dateAdded]
    @State private var columnWidths: [TrackColumn: CGFloat] = [:]
    @State private var showTagEditor = false
    @State private var showMetadataEditor = false
    @State private var showDeleteConfirmation = false
    @State private var tracksToDelete: [Track] = []
    @State private var hasLoadedPreferences = false
    @FocusState private var isTextFieldFocused: Bool

    private let visibleColumnsDefaultsKey = "FolderHierarchyView.visibleColumns"
    private let columnWidthsDefaultsKey = "FolderHierarchyView.columnWidths"

    init(
        collectionService: CollectionService,
        audioService: AudioService,
        folderManager: FolderHierarchyManager,
        searchService: SearchService,
        playlistService: PlaylistService,
        onNavigateToPlaylist: ((Playlist) -> Void)? = nil
    ) {
        self.collectionService = collectionService
        self.audioService = audioService
        self.folderManager = folderManager
        self.searchService = searchService
        self.playlistService = playlistService
        self.onNavigateToPlaylist = onNavigateToPlaylist
        self._metadataManager = StateObject(wrappedValue: TrackMetadataManager(collectionService: collectionService))
    }

    private var sortedRoots: [FolderNode] {
        FolderHierarchySorter.sortedTree(folderManager.rootFolders, sortOrder: sortOrder)
    }

    private var flatRows: [FolderHierarchyTableRow] {
        FolderHierarchyFlatten.visibleRows(
            sortedRoots: sortedRoots,
            folderManager: folderManager,
            searchService: searchService
        )
    }

    var body: some View {
        FolderHierarchyTable(
            rows: flatRows,
            selectedRowIds: $selectedRowIds,
            sortOrder: $sortOrder,
            visibleColumns: $visibleColumns,
            columnWidths: $columnWidths,
            isTextFieldFocused: Binding(
                get: { isTextFieldFocused },
                set: { isTextFieldFocused = $0 }
            ),
            audioService: audioService,
            metadataManager: metadataManager,
            waveformServiceHolder: waveformServiceHolder,
            collectionService: collectionService,
            folderManager: folderManager,
            onDoubleClickTrack: { track in
                Task {
                    _ = await audioService.loadTrack(track)
                    audioService.play()
                }
            },
            onColumnWidthChange: saveColumnWidths,
            onKeyPressBackspace: {
                let tracks = selectedTracksFromRows()
                if !tracks.isEmpty {
                    tracksToDelete = tracks
                    showDeleteConfirmation = true
                }
            }
        )
        .background(
            FolderHierarchyTableSelectionHandler(
                selectedRowIds: $selectedRowIds,
                rows: flatRows,
                onKeyPressA: {
                    selectedRowIds = Set(flatRows.map(\.id))
                },
                onKeyPressSpace: {
                    audioService.togglePlayPause()
                },
                onKeyPressBackspace: {
                    let tracks = selectedTracksFromRows()
                    if !tracks.isEmpty {
                        tracksToDelete = tracks
                        showDeleteConfirmation = true
                    }
                },
                onExpandSelectedFolder: {
                    expandSelectedFolder()
                },
                onCollapseSelectedFolder: {
                    collapseSelectedFolder()
                },
                onGoToCurrentTrack: {
                    scrollToCurrentTrack()
                }
            )
        )
        .onAppear {
            let rootPath = collectionService.getRootFolders().first
            folderManager.buildHierarchy(from: collectionService.tracks, rootPath: rootPath)
        }
        .onChange(of: collectionService.tracks) { _ in
            let rootPath = collectionService.getRootFolders().first
            folderManager.buildHierarchy(from: collectionService.tracks, rootPath: rootPath)
            pruneSelection()
        }
        .onChange(of: selectedRowIds) { newIds in
            syncLegacySelection(from: newIds)
        }
        .onChange(of: searchService.searchText) { _ in
            pruneSelection()
        }
        .onAppear(perform: loadPreferences)
        .onChange(of: visibleColumns) { _ in
            saveVisibleColumns()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("GoToCurrentTrack"))) { _ in
            scrollToCurrentTrack()
        }
        .contextMenu {
            contextMenuContent()
        }
        .sheet(isPresented: $showTagEditor) {
            TagEditorView(
                metadataManager: metadataManager,
                collectionService: collectionService,
                trackIds: selectedTrackIdsForEditing()
            )
        }
        .sheet(isPresented: $showMetadataEditor) {
            MetadataEditorView(
                metadataManager: metadataManager,
                collectionService: collectionService,
                trackIds: selectedTrackIdsForEditing()
            )
        }
        .alert("Delete Tracks", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                tracksToDelete = []
            }
            Button("Delete", role: .destructive) {
                deleteSelectedTracks()
            }
        } message: {
            let count = tracksToDelete.count
            if count == 1 {
                Text("Delete '\(tracksToDelete.first?.title ?? "this track")'? The file will be moved to trash.")
            } else {
                Text("Delete \(count) tracks? The files will be moved to trash.")
            }
        }
    }

    private func scrollToCurrentTrack() {
        guard let current = audioService.currentTrack, let tid = current.id else { return }
        let rid = "track:\(tid)"
        if flatRows.contains(where: { $0.id == rid }) {
            selectedRowIds = [rid]
        }
    }

    private func expandSelectedFolder() -> Bool {
        guard selectedRowIds.count == 1, let selectedRowId = selectedRowIds.first else { return false }
        guard let selectedRow = flatRows.first(where: { $0.id == selectedRowId }) else { return false }
        guard case .folder(let folder) = selectedRow.kind, folder.hasChildren else { return false }
        guard !folderManager.isExpanded(folder.path) else { return false }
        folderManager.toggleExpansion(for: folder.path)
        return true
    }

    private func collapseSelectedFolder() -> Bool {
        guard selectedRowIds.count == 1, let selectedRowId = selectedRowIds.first else { return false }
        guard let selectedRow = flatRows.first(where: { $0.id == selectedRowId }) else { return false }
        guard case .folder(let folder) = selectedRow.kind, folder.hasChildren else { return false }
        guard folderManager.isExpanded(folder.path) else { return false }
        folderManager.toggleExpansion(for: folder.path)
        return true
    }

    private func pruneSelection() {
        let valid = Set(flatRows.map(\.id))
        selectedRowIds = selectedRowIds.intersection(valid)
    }

    private func syncLegacySelection(from ids: Set<String>) {
        var folders = Set<String>()
        for id in ids {
            if id.hasPrefix("folder:") {
                folders.insert(String(id.dropFirst(7)))
            }
        }
        folderManager.selectedFolders = folders
        // Keep published selectedTracks-compatible state via folderManager only for folders;
        // track selection is row-id based; context menus use selectedTrackIdsForEditing
    }

    private func selectedTracksFromRows() -> [Track] {
        let idSet = selectedRowIds
        return flatRows.compactMap { row in
            guard idSet.contains(row.id), case .track(let t) = row.kind else { return nil }
            return t
        }
    }

    private func selectedTrackIdsForEditing() -> [Int] {
        selectedTracksFromRows().compactMap(\.id)
    }

    @ViewBuilder
    private func contextMenuContent() -> some View {
        let trackList = selectedTracksFromRows()
        let folderOnlyIds = selectedRowIds.filter { $0.hasPrefix("folder:") }

        if !trackList.isEmpty {
            Button("Play") {
                if let t = trackList.first {
                    Task {
                        _ = await audioService.loadTrack(t)
                        audioService.play()
                    }
                }
            }
            Button("Edit Tags…") { showTagEditor = true }
            Button("Edit Metadata…") { showMetadataEditor = true }
            if let onNavigateToPlaylist {
                let paths = trackList.map(\.path)
                let playlistsWithSelection = playlistService.playlistsContainingAllTracks(absoluteTrackPaths: paths)
                Menu("Open in Playlist") {
                    if playlistsWithSelection.isEmpty {
                        Button("No playlists") {}
                            .disabled(true)
                    } else {
                        ForEach(playlistsWithSelection, id: \.id) { playlist in
                            Button(playlist.name) {
                                onNavigateToPlaylist(playlist)
                            }
                        }
                    }
                }
            }
            Divider()
            Button("Move to Trash", role: .destructive) {
                tracksToDelete = trackList
                showDeleteConfirmation = true
            }
            Divider()
            Button("Reveal in Finder") {
                revealTracksInFinder(trackList)
            }
        }

        if !folderOnlyIds.isEmpty {
            if !trackList.isEmpty { Divider() }
            Button("Add Selected Folders to Playlist") {
                // TODO: playlist from folders
            }
            Button("Reveal in Finder") {
                for id in folderOnlyIds {
                    let path = String(id.dropFirst(7))
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                }
            }
        }
    }

    private func revealTracksInFinder(_ tracks: [Track]) {
        let parents = Set(tracks.map { URL(fileURLWithPath: $0.path).deletingLastPathComponent().path })
        for directory in parents {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: directory)
        }
    }

    private func deleteSelectedTracks() {
        guard !tracksToDelete.isEmpty else { return }
        let count = tracksToDelete.count
        Task {
            do {
                let deletedIds = tracksToDelete.compactMap(\.id)
                for track in tracksToDelete {
                    if let trackId = track.id {
                        try collectionService.deleteTrackAndMoveToTrash(trackId)
                    }
                }
                await collectionService.removeTracksFromMemory(trackIds: deletedIds)
                await MainActor.run {
                    tracksToDelete = []
                    selectedRowIds.removeAll()
                }
                print("✅ Deleted \(count) tracks from folder view")
            } catch {
                print("❌ Delete failed: \(error)")
            }
        }
    }

    private func loadPreferences() {
        guard !hasLoadedPreferences else { return }
        hasLoadedPreferences = true
        if let stored = UserDefaults.standard.stringArray(forKey: visibleColumnsDefaultsKey) {
            let set = Set(stored.compactMap { TrackColumn(rawValue: $0) })
            if !set.isEmpty { visibleColumns = set }
        }
        if let dict = UserDefaults.standard.dictionary(forKey: columnWidthsDefaultsKey) as? [String: Double] {
            var result: [TrackColumn: CGFloat] = [:]
            for (key, value) in dict {
                if let col = TrackColumn(rawValue: key) {
                    result[col] = CGFloat(value)
                }
            }
            columnWidths = result
        }
    }

    private func saveVisibleColumns() {
        UserDefaults.standard.set(visibleColumns.map(\.rawValue), forKey: visibleColumnsDefaultsKey)
    }

    private func saveColumnWidths() {
        var dict: [String: Double] = [:]
        for (col, width) in columnWidths {
            dict[col.rawValue] = Double(width)
        }
        UserDefaults.standard.set(dict, forKey: columnWidthsDefaultsKey)
    }
}

// MARK: - Table selection (tag editing / row click)

private struct FolderHierarchyTableSelectionHandler: NSViewRepresentable {
    @Binding var selectedRowIds: Set<String>
    let rows: [FolderHierarchyTableRow]
    let onKeyPressA: () -> Void
    let onKeyPressSpace: () -> Void
    let onKeyPressBackspace: () -> Void
    let onExpandSelectedFolder: () -> Bool
    let onCollapseSelectedFolder: () -> Bool
    let onGoToCurrentTrack: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = FolderHierarchySelectionView(selectedRowIds: $selectedRowIds)
        view.rows = rows
        view.onKeyPressA = onKeyPressA
        view.onKeyPressSpace = onKeyPressSpace
        view.onKeyPressBackspace = onKeyPressBackspace
        view.onExpandSelectedFolder = onExpandSelectedFolder
        view.onCollapseSelectedFolder = onCollapseSelectedFolder
        view.onGoToCurrentTrack = onGoToCurrentTrack
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let v = nsView as? FolderHierarchySelectionView {
            v.rows = rows
            v.onKeyPressA = onKeyPressA
            v.onKeyPressSpace = onKeyPressSpace
            v.onKeyPressBackspace = onKeyPressBackspace
            v.onExpandSelectedFolder = onExpandSelectedFolder
            v.onCollapseSelectedFolder = onCollapseSelectedFolder
            v.onGoToCurrentTrack = onGoToCurrentTrack
            v.hasSelection = !selectedRowIds.isEmpty
            DispatchQueue.main.async {
                v.applyAllowsTypeSelect()
            }
        }
    }
}

private final class FolderHierarchySelectionView: NSView {
    var selectedRowIds: Binding<Set<String>>
    var rows: [FolderHierarchyTableRow] = []
    var onKeyPressA: (() -> Void)?
    var onKeyPressSpace: (() -> Void)?
    var onKeyPressBackspace: (() -> Void)?
    var onExpandSelectedFolder: (() -> Bool)?
    var onCollapseSelectedFolder: (() -> Bool)?
    var onGoToCurrentTrack: (() -> Void)?
    var hasSelection = false

    init(selectedRowIds: Binding<Set<String>>) {
        self.selectedRowIds = selectedRowIds
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var mouseMonitor: Any?
    private var keyMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if window != nil {
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                self?.handleMouseDown(event) ?? event
            }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKeyDown(event) ?? event
            }
            DispatchQueue.main.async { [weak self] in
                self?.applyAllowsTypeSelect()
            }
        }
    }

    deinit {
        if let monitor = mouseMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
    }

    func applyAllowsTypeSelect() {
        guard let tableView = findTableView(in: window?.contentView) else { return }
        tableView.allowsTypeSelect = false
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard let window = self.window, window === event.window else { return event }
        guard let tableView = findTableView(in: window.contentView) else { return event }

        let fr = window.firstResponder
        if fr is NSTextField { return event }
        if let tv = fr as? NSTextView, tv.isEditable { return event }

        let tableHasFocus = fr === tableView || fr === tableView.enclosingScrollView
        guard tableHasFocus else { return event }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers ?? ""

        if modifiers.contains(.command), key == "a" {
            onKeyPressA?()
            return nil
        }
        if key == " " {
            onKeyPressSpace?()
            return nil
        }
        if event.keyCode == 51, hasSelection {
            onKeyPressBackspace?()
            return nil
        }
        if event.keyCode == 124, hasSelection, onExpandSelectedFolder?() == true {
            return nil
        }
        if event.keyCode == 123, hasSelection, onCollapseSelectedFolder?() == true {
            return nil
        }
        if modifiers.contains(.command), key == "l" {
            onGoToCurrentTrack?()
            return nil
        }
        return event
    }

    private func handleMouseDown(_ event: NSEvent) -> NSEvent? {
        guard let window = self.window, window == event.window else { return event }
        let firstResponder = window.firstResponder
        let isEditing = firstResponder is NSTextView || firstResponder is NSTextField
        guard isEditing else { return event }
        guard let tableView = findTableView(in: window.contentView) else { return event }
        let locationInTable = tableView.convert(event.locationInWindow, from: nil)
        guard tableView.bounds.contains(locationInTable) else { return event }
        let row = tableView.row(at: locationInTable)
        guard row >= 0, row < rows.count else { return event }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.isEmpty {
            let rid = rows[row].id
            window.makeFirstResponder(tableView)
            DispatchQueue.main.async {
                self.selectedRowIds.wrappedValue = [rid]
            }
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            return nil
        }
        return event
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let tableView = findTableView(in: window?.contentView) else {
            nextResponder?.rightMouseDown(with: event)
            return
        }
        let locationInTableView = tableView.convert(event.locationInWindow, from: nil)
        let row = tableView.row(at: locationInTableView)
        guard row >= 0, row < rows.count else {
            nextResponder?.rightMouseDown(with: event)
            return
        }
        let rid = rows[row].id
        if selectedRowIds.wrappedValue.contains(rid) {
            nextResponder?.rightMouseDown(with: event)
            return
        }
        selectedRowIds.wrappedValue = [rid]
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            self.nextResponder?.rightMouseDown(with: event)
        }
    }

    private func findTableView(in view: NSView?) -> NSTableView? {
        guard let view = view else { return nil }
        if let tableView = view as? NSTableView {
            let className = String(describing: type(of: tableView))
            if className.contains("ListCore") {
                // continue
            } else {
                return tableView
            }
        }
        for sub in view.subviews {
            if let t = findTableView(in: sub) { return t }
        }
        return nil
    }
}

#Preview {
    let collectionService = CollectionService()
    let folderManager = FolderHierarchyManager()
    FolderHierarchyView(
        collectionService: collectionService,
        audioService: AudioService(),
        folderManager: folderManager,
        searchService: SearchService(),
        playlistService: PlaylistService()
    )
    .environmentObject(WaveformServiceHolder())
}
