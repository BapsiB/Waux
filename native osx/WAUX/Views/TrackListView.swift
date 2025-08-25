import SwiftUI

enum TrackColumn: String, CaseIterable, Hashable {
    case id
    case title
    case artist
    case album
    case albumArtist
    case composer
    case genre
    case year
    case trackNumber
    case discNumber
    case bpm
    case path
    case isUrl
    case duration
    case timeMarkers
    case waveformData
    case rating
    case comment
    case generalTags
    case type
    
    var displayName: String {
        switch self {
        case .id: return "ID"
        case .title: return "Title"
        case .artist: return "Artist"
        case .album: return "Album"
        case .albumArtist: return "Album Artist"
        case .composer: return "Composer"
        case .genre: return "Genre"
        case .year: return "Year"
        case .trackNumber: return "Track #"
        case .discNumber: return "Disc #"
        case .bpm: return "BPM"
        case .path: return "Path"
        case .isUrl: return "URL?"
        case .duration: return "Duration"
        case .timeMarkers: return "Markers"
        case .waveformData: return "Waveform"
        case .rating: return "Rating"
        case .comment: return "Comment"
        case .generalTags: return "Tags"
        case .type: return "Type"
        }
    }
}

// MARK: - Track Table Component

struct TrackTable: View {
    let filteredTracks: [Track]
    @Binding var selectedTracks: Set<Track.ID>
    @Binding var sortOrder: [KeyPathComparator<Track>]
    @Binding var visibleColumns: Set<TrackColumn>
    @Binding var columnWidths: [TrackColumn: CGFloat]
    @Binding var isTextFieldFocused: Bool
    @ObservedObject var audioService: AudioService
    @ObservedObject var metadataManager: TrackMetadataManager
    @ObservedObject var waveformServiceHolder: WaveformServiceHolder
    @ObservedObject var collectionService: CollectionService
    let onDoubleClick: (Track) -> Void
    let contextMenu: () -> AnyView
    let onKeyPressA: () -> Void
    let onKeyPressSpace: () -> Void
    
    var body: some View {
        Table(filteredTracks, selection: $selectedTracks, sortOrder: $sortOrder) {
            // Waveform column - always visible and first
            TableColumn("Waveform", value: \Track.waveformPointCount) { track in
                WaveformColumn(
                    track: track,
                    audioService: audioService,
                    waveformServiceHolder: waveformServiceHolder,
                    collectionService: collectionService
                )
                .id("waveform-\(track.id ?? -1)-\(track.waveformPointCount)")
            }
            .width(min: 120, ideal: columnWidths[.waveformData] ?? 160)
            
            TableColumn("Title", value: \.title) { track in
                titleCell(for: track)
            }
            .width(min: 150, ideal: columnWidths[.title] ?? 250)
            
            if visibleColumns.contains(.artist) {
                TableColumn("Artist", value: \.artist) { track in
                    Text(track.artist)
                }
                .width(min: 100, ideal: columnWidths[.artist] ?? 150)
            }
            
            if visibleColumns.contains(.album) {
                TableColumn("Album", value: \.album) { track in
                    Text(track.album)
                }
                .width(min: 100, ideal: columnWidths[.album] ?? 150)
            }
            
            if visibleColumns.contains(.duration) {
                TableColumn("Duration", value: \.duration) { track in
                    Text(track.formattedDuration)
                        .monospacedDigit()
                }
                .width(min: 50, ideal: columnWidths[.duration] ?? 70)
            }
            
            if visibleColumns.contains(.rating) {
                TableColumn("Rating", value: \.rating) { track in
                    ratingCell(for: track)
                }
                .width(min: 80, ideal: columnWidths[.rating] ?? 100)
            }
            
            if visibleColumns.contains(.type) {
                TableColumn("Type", value: \.sourceType.rawValue) { track in
                    typeCell(for: track)
                }
                .width(min: 60, ideal: columnWidths[.type] ?? 80)
            }
            
            if visibleColumns.contains(.albumArtist) {
                TableColumn("Album Artist", value: \Track.albumArtistText) { track in
                    Text(track.albumArtistText)
                        .foregroundColor(track.albumArtist?.isEmpty == false ? .primary : .secondary)
                }
                .width(min: 100, ideal: columnWidths[.albumArtist] ?? 150)
            }
            
            if visibleColumns.contains(.composer) {
                TableColumn("Composer", value: \Track.composerText) { track in
                    Text(track.composerText)
                        .foregroundColor(track.composer?.isEmpty == false ? .primary : .secondary)
                }
                .width(min: 100, ideal: columnWidths[.composer] ?? 150)
            }
            
            if visibleColumns.contains(.generalTags) {
                TableColumn("Tags", value: \Track.generalTagsText) { track in
                    if let trackId = track.id {
                        InteractiveTagsView_New(
                            trackId: trackId,
                            metadataManager: metadataManager,
                            isTextFieldFocused: $isTextFieldFocused
                        )
                    }
                }
                .width(min: 120, ideal: columnWidths[.generalTags] ?? 220, max: 320)
            }
        }
        .tableStyle(.bordered)
        .background(TableWidthObserver(columnWidths: $columnWidths, onWidthChange: {}))
        .onTapGesture(count: 2) {
            if let selectedTrack = selectedTracks.first,
               let track = filteredTracks.first(where: { $0.id == selectedTrack }) {
                onDoubleClick(track)
            }
        }
        .contextMenu {
            contextMenu()
        }
        .onKeyPress("a", phases: .down) { press in
            if press.modifiers.contains(.command) {
                onKeyPressA()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.space, phases: .down) { press in
            if !isTextFieldFocused && !selectedTracks.isEmpty {
                onKeyPressSpace()
                return .handled
            }
            return .ignored
        }
    }
    
    @ViewBuilder
    private func titleCell(for track: Track) -> some View {
        VStack(alignment: .leading) {
            Text(track.title)
                .fontWeight(.medium)
            if !track.artist.isEmpty && track.artist != "Unknown" {
                Text(track.artist)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private func ratingCell(for track: Track) -> some View {
        if let trackId = track.id {
            InteractiveStarRating_New(
                trackId: trackId,
                metadataManager: metadataManager
            )
        }
    }
    
    @ViewBuilder
    private func typeCell(for track: Track) -> some View {
        HStack {
            Image(systemName: iconName(for: track.sourceType))
                .foregroundColor(color(for: track.sourceType))
            Text(track.sourceType.rawValue.capitalized)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func iconName(for sourceType: TrackSource) -> String {
        switch sourceType {
        case .local:
            return "music.note"
        case .youtube:
            return "play.rectangle"
        case .url:
            return "link"
        }
    }
    
    private func color(for sourceType: TrackSource) -> Color {
        switch sourceType {
        case .local:
            return .blue
        case .youtube:
            return .red
        case .url:
            return .green
        }
    }
}

struct TrackListView: View {
    @ObservedObject var collectionService: CollectionService
    @ObservedObject var audioService: AudioService
    let tracksFilter: [Track]? // If provided, only show these tracks; otherwise show all tracks
    @StateObject private var waveformServiceHolder = WaveformServiceHolder()
    @StateObject private var metadataManager: TrackMetadataManager
    @State private var sortOrder = [KeyPathComparator(\Track.title)]
    @State private var searchText = ""
    @State private var selectedTracks = Set<Track.ID>()
    @State private var showingRatingError = false
    @State private var ratingErrorMessage = ""
    @State private var visibleColumns: Set<TrackColumn> = [.waveformData, .title, .artist, .album, .duration, .rating, .generalTags, .type]
    @State private var showTagEditor = false
    @State private var columnWidths: [TrackColumn: CGFloat] = [:]
    @State private var hasLoadedPreferences = false
    @State private var showDatabaseRepair = false
    @State private var corruptedTracks: [(id: Int, title: String, issues: [String])] = []
    @State private var isScanningDatabase = false
    @State private var showFileChangesSheet = false
    @State private var fileChangesData: FileChangesData? = nil
    @FocusState private var isTextFieldFocused: Bool
    private let visibleColumnsDefaultsKey = "TrackListView.visibleColumns"
    private let columnWidthsDefaultsKey = "TrackListView.columnWidths"
    
    init(collectionService: CollectionService, audioService: AudioService, tracksFilter: [Track]? = nil) {
        self.collectionService = collectionService
        self.audioService = audioService
        self.tracksFilter = tracksFilter
        self._metadataManager = StateObject(wrappedValue: TrackMetadataManager(collectionService: collectionService))
    }
    

    
    var filteredTracks: [Track] {
        let baseTracks = tracksFilter ?? collectionService.tracks
        
        if searchText.isEmpty {
            return baseTracks.sorted(using: sortOrder)
        } else {
            return baseTracks.filter { track in
                track.title.localizedCaseInsensitiveContains(searchText) ||
                track.artist.localizedCaseInsensitiveContains(searchText) ||
                track.album.localizedCaseInsensitiveContains(searchText)
            }.sorted(using: sortOrder)
        }
    }
    
    var body: some View {
        VStack {
            searchBar
            
            TrackTable(
                filteredTracks: filteredTracks,
                selectedTracks: $selectedTracks,
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
                onDoubleClick: { track in
                    print("Double-clicked track: \(track.title)")
                    print("Track path: \(track.path)")
                    print("Is URL: \(track.isUrl)")
                    print("Duration: \(track.duration) ms")
                    Task {
                        await audioService.loadTrack(track)
                        audioService.play()
                    }
                },
                contextMenu: {
                    AnyView(columnContextMenu)
                },
                onKeyPressA: {
                    selectedTracks = Set(filteredTracks.compactMap { $0.id })
                },
                onKeyPressSpace: {
                    if let selectedTrack = selectedTracks.first,
                       let track = filteredTracks.first(where: { $0.id == selectedTrack }) {
                        Task {
                            await audioService.loadTrack(track)
                            audioService.play()
                        }
                    }
                }
            )
        }
        .alert("Rating Update Error", isPresented: $showingRatingError) {
            Button("OK") { }
        } message: {
            Text(ratingErrorMessage)
        }
        .sheet(isPresented: $showTagEditor) {
            let selectedTrackIds = filteredTracks
                .filter { selectedTracks.contains($0.id) }
                .compactMap { $0.id }
            
            TagEditorView_New(
                metadataManager: metadataManager,
                collectionService: collectionService,
                trackIds: selectedTrackIds
            )
        }
        .sheet(isPresented: $showDatabaseRepair) {
            DatabaseRepairView(
                collectionService: collectionService,
                corruptedTracks: $corruptedTracks,
                isScanning: $isScanningDatabase
            )
        }
        .sheet(item: $fileChangesData) { data in
            FileChangesSheet(
                newFiles: data.newFiles,
                deletedTracks: data.deletedTracks,
                movedUpdates: data.movedUpdates,
                onCancel: { fileChangesData = nil },
                onApply: { adds, deletes, moves in
                    Task {
                        do {
                            print("🔍 [TrackListView] Applying filesystem changes - adds: \(adds.count), deletes: \(deletes.count), moves: \(moves.count)")
                            try await collectionService.applyFilesystemChanges(
                                newFiles: adds,
                                deletedTrackIds: deletes,
                                movedUpdates: moves
                            )
                            print("🔍 [TrackListView] Successfully applied filesystem changes")
                            await MainActor.run {
                                fileChangesData = nil
                            }
                        } catch {
                            print("❌ [TrackListView] Failed to apply filesystem changes: \(error)")
                            await MainActor.run {
                                // Show error alert to user
                                ratingErrorMessage = "Failed to apply filesystem changes: \(error.localizedDescription)"
                                showingRatingError = true
                            }
                        }
                    }
                }
            )
            .frame(minWidth: 640, minHeight: 420)
        }
        .onAppear(perform: loadPreferences)
        .task {
            await scanForFileChanges()
        }
        .onChange(of: visibleColumns) { _, _ in
            saveVisibleColumns()
        }
    }
    
    // MARK: - Context Menu
    
    @ViewBuilder
    private var columnContextMenu: some View {
        // Track actions
        if !selectedTracks.isEmpty {
            Button("Play") {
                if let selectedTrack = selectedTracks.first,
                   let track = filteredTracks.first(where: { $0.id == selectedTrack }) {
                    print("Context menu play track: \(track.title)")
                    print("Track path: \(track.path)")
                    print("Is URL: \(track.isUrl)")
                    print("Duration: \(track.duration) ms")
                    Task {
                        await audioService.loadTrack(track)
                        audioService.play()
                    }
                }
            }
            Button("Edit Tags…") {
                showTagEditor = true
            }
            Divider()
        }
        
        // Column visibility
        ForEach(TrackColumn.allCases, id: \.self) { column in
            Button {
                if visibleColumns.contains(column) {
                    // Always keep title and waveform columns visible
                    if column != .title && column != .waveformData && visibleColumns.count > 2 {
                        visibleColumns.remove(column)
                    }
                } else {
                    visibleColumns.insert(column)
                }
            } label: {
                HStack {
                    Text(column.displayName)
                    Spacer()
                    if visibleColumns.contains(column) {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .disabled(column == .title || column == .waveformData) // Title and waveform columns are always visible
        }
        Divider()
        Button("Show All Columns") {
            visibleColumns = Set(TrackColumn.allCases)
        }
        Button("Show Default Columns") {
            visibleColumns = [.waveformData, .title, .artist, .album, .duration, .rating, .generalTags, .type]
        }
    }
    
    @ViewBuilder
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search tracks...", text: $searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            Spacer()
            
            Text("\(filteredTracks.count) tracks")
                .foregroundColor(.secondary)
            
            if !selectedTracks.isEmpty {
                Text("\(selectedTracks.count) selected")
                    .foregroundColor(.blue)
                    .fontWeight(.medium)
            }
            
            Button("🔧 Database Repair") {
                showDatabaseRepair = true
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundColor(.orange)
        }
        .padding(.horizontal)
        .padding(.top)
    }
    
    // MARK: - Cell Views
    
    @ViewBuilder
    private func titleCell(for track: Track) -> some View {
        VStack(alignment: .leading) {
            Text(track.title)
                .fontWeight(.medium)
            if !track.artist.isEmpty && track.artist != "Unknown" {
                Text(track.artist)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private func ratingCell(for track: Track) -> some View {
        if let trackId = track.id {
            InteractiveStarRating_New(
                trackId: trackId,
                metadataManager: metadataManager
            )
        }
    }
    
    @ViewBuilder
    private func typeCell(for track: Track) -> some View {
        HStack {
            Image(systemName: iconName(for: track.sourceType))
                .foregroundColor(color(for: track.sourceType))
            Text(track.sourceType.rawValue.capitalized)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Helper Methods
    
    private func iconName(for sourceType: TrackSource) -> String {
        switch sourceType {
        case .local:
            return "music.note"
        case .youtube:
            return "play.rectangle"
        case .url:
            return "link"
        }
    }
    
    private func color(for sourceType: TrackSource) -> Color {
        switch sourceType {
        case .local:
            return .blue
        case .youtube:
            return .red
        case .url:
            return .green
        }
    }
    
    // MARK: - Column Width Persistence
    
    private func loadPreferences() {
        guard !hasLoadedPreferences else { return }
        hasLoadedPreferences = true
        // Visible columns
        if let stored = UserDefaults.standard.stringArray(forKey: visibleColumnsDefaultsKey) {
            let set = Set(stored.compactMap { TrackColumn(rawValue: $0) })
            if !set.isEmpty {
                visibleColumns = set
            }
        }
        // Column widths
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
        let arr = visibleColumns.map { $0.rawValue }
        UserDefaults.standard.set(arr, forKey: visibleColumnsDefaultsKey)
    }
    
    private func saveColumnWidths() {
        var dict: [String: Double] = [:]
        for (col, width) in columnWidths {
            dict[col.rawValue] = Double(width)
        }
        UserDefaults.standard.set(dict, forKey: columnWidthsDefaultsKey)
    }

    private func scanForFileChanges() async {
        do {
            print("🔍 [TrackListView] Starting scan...")
            let changes = try await collectionService.scanFilesystemChanges()
            print("🔍 [TrackListView] Scan completed - new: \(changes.newFiles.count), deleted: \(changes.deletedTracks.count), moved: \(changes.movedUpdates.count)")
            
            if !changes.newFiles.isEmpty || !changes.deletedTracks.isEmpty || !changes.movedUpdates.isEmpty {
                print("🔍 [TrackListView] Changes detected, showing sheet...")
                print("🔍 [TrackListView] New files: \(changes.newFiles.count), Deleted: \(changes.deletedTracks.count), Moved: \(changes.movedUpdates.count)")
                
                await MainActor.run {
                    fileChangesData = FileChangesData(
                        newFiles: changes.newFiles,
                        deletedTracks: changes.deletedTracks,
                        movedUpdates: changes.movedUpdates
                    )
                }
            } else {
                print("🔍 [TrackListView] No changes detected")
            }
        } catch {
            print("🔍 [TrackListView] Scan failed: \(error)")
        }
    }
    

}

// MARK: - Table Width Observer
private struct TableWidthObserver: NSViewRepresentable {
    @Binding var columnWidths: [TrackColumn: CGFloat]
    let onWidthChange: () -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // Find the NSTableView in the view hierarchy
        if let tableView = findTableView(in: nsView) {
            context.coordinator.setupObserver(for: tableView)
        }
    }
    
    private func findTableView(in view: NSView) -> NSTableView? {
        if let tableView = view as? NSTableView {
            return tableView
        }
        for subview in view.subviews {
            if let tableView = findTableView(in: subview) {
                return tableView
            }
        }
        return nil
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(columnWidths: $columnWidths, onWidthChange: onWidthChange)
    }
    
    class Coordinator: NSObject {
        @Binding var columnWidths: [TrackColumn: CGFloat]
        let onWidthChange: () -> Void
        private var tableView: NSTableView?
        private var timer: Timer?
        
        init(columnWidths: Binding<[TrackColumn: CGFloat]>, onWidthChange: @escaping () -> Void) {
            self._columnWidths = columnWidths
            self.onWidthChange = onWidthChange
        }
        
        func setupObserver(for tableView: NSTableView) {
            self.tableView = tableView
            
            // Start a timer to periodically check column widths
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.checkColumnWidths()
            }
        }
        
        private func checkColumnWidths() {
            guard let tableView = tableView else { return }
            
            var updated = false
            let columnIdentifiers = ["Waveform", "Title", "Artist", "Album", "Duration", "Rating", "Type", "Album Artist", "Composer", "Tags"]
            
            for (index, identifier) in columnIdentifiers.enumerated() {
                guard index < tableView.tableColumns.count else { break }
                let column = tableView.tableColumns[index]
                let width = column.width
                
                // Map identifier to TrackColumn
                let trackColumn: TrackColumn? = {
                    switch identifier {
                    case "Title": return .title
                    case "Artist": return .artist
                    case "Album": return .album
                    case "Duration": return .duration
                    case "Rating": return .rating
                    case "Type": return .type
                    case "Album Artist": return .albumArtist
                    case "Composer": return .composer
                    case "Waveform": return .waveformData
                    case "Tags": return .generalTags
                    default: return nil
                    }
                }()
                
                if let trackColumn = trackColumn {
                    let currentWidth = columnWidths[trackColumn] ?? 0
                    if abs(currentWidth - width) > 1.0 { // Threshold to avoid noise
                        columnWidths[trackColumn] = width
                        updated = true
                    }
                }
            }
            
            if updated {
                onWidthChange()
            }
        }
        
        deinit {
            timer?.invalidate()
        }
    }
}

// MARK: - File Changes Sheet
private struct FileChangesSheet: View {
    let newFiles: [String]
    let deletedTracks: [Track]
    let movedUpdates: [CollectionService.MovedFileUpdate]
    var onCancel: () -> Void
    var onApply: (_ adds: [String], _ deletes: [Int], _ moves: [CollectionService.MovedFileUpdate]) -> Void

    @State private var newFilesSelection: Set<String> = []
    @State private var deletedSelection: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filesystem Changes Detected")
                .font(.title2)
                .bold()
            Text("Select which changes to apply to the library.")
                .foregroundColor(.secondary)
            
            // Debug info
            Text("DEBUG: newFiles.count = \(newFiles.count), deletedTracks.count = \(deletedTracks.count)")
                .font(.caption)
                .foregroundColor(.red)
            Text("DEBUG: newFilesSelection.count = \(newFilesSelection.count), deletedSelection.count = \(deletedSelection.count)")
                .font(.caption)
                .foregroundColor(.blue)
            Text("DEBUG: Button disabled = \(newFilesSelection.isEmpty && deletedSelection.isEmpty && movedUpdates.isEmpty)")
                .font(.caption)
                .foregroundColor(.green)

            HStack(spacing: 16) {
                // New files
                VStack(alignment: .leading) {
                    HStack {
                        Text("New Files (") + Text("\(newFiles.count)").bold() + Text(")")
                        Spacer()
                        Button(newFilesSelection.count == newFiles.count ? "Deselect All" : "Select All") {
                            if newFilesSelection.count == newFiles.count { newFilesSelection.removeAll() }
                            else { newFilesSelection = Set(newFiles) }
                        }
                        .buttonStyle(.borderless)
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(newFiles, id: \.self) { path in
                                Toggle(isOn: Binding(
                                    get: { newFilesSelection.contains(path) },
                                    set: { checked in
                                        if checked { newFilesSelection.insert(path) } else { newFilesSelection.remove(path) }
                                    }
                                )) {
                                    Text(URL(fileURLWithPath: path).lastPathComponent)
                                        .help(path)
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(minHeight: 140)
                }

                // Deleted files
                VStack(alignment: .leading) {
                    HStack {
                        Text("Missing Files (") + Text("\(deletedTracks.count)").bold() + Text(")")
                        Spacer()
                        Button(deletedSelection.count == deletedTracks.count ? "Deselect All" : "Select All") {
                            let allIds = deletedTracks.compactMap { $0.id }
                            if deletedSelection.count == allIds.count { deletedSelection.removeAll() }
                            else { deletedSelection = Set(allIds) }
                        }
                        .buttonStyle(.borderless)
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(deletedTracks, id: \.id) { track in
                                if let id = track.id {
                                    Toggle(isOn: Binding(
                                        get: { deletedSelection.contains(id) },
                                        set: { checked in
                                            if checked { deletedSelection.insert(id) } else { deletedSelection.remove(id) }
                                        }
                                    )) {
                                        HStack {
                                            Image(systemName: "exclamationmark.triangle").foregroundColor(.orange)
                                            Text(track.displayTitle)
                                            Spacer()
                                            Text(URL(fileURLWithPath: track.path).lastPathComponent)
                                                .foregroundColor(.secondary)
                                        }
                                        .help(track.path)
                                    }
                                    .toggleStyle(.checkbox)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(minHeight: 140)
                }
            }

            if !movedUpdates.isEmpty {
                VStack(alignment: .leading) {
                    Text("Moved Files (") + Text("\(movedUpdates.count)").bold() + Text(") - will update paths")
                    List(movedUpdates) { upd in
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.right.arrow.left").foregroundColor(.blue)
                            Text(upd.trackTitle)
                            Spacer()
                            Text(URL(fileURLWithPath: upd.oldPath).lastPathComponent)
                            Image(systemName: "arrow.right")
                            Text(URL(fileURLWithPath: upd.newPath).lastPathComponent)
                        }
                        .help("\(upd.oldPath) -> \(upd.newPath)")
                    }
                    .frame(minHeight: 100)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Apply Changes") {
                    print("🔍 [FileChangesSheet] Apply button clicked - newFilesSelection: \(newFilesSelection.count), deletedSelection: \(deletedSelection.count), movedUpdates: \(movedUpdates.count)")
                    onApply(Array(newFilesSelection), Array(deletedSelection), movedUpdates)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newFilesSelection.isEmpty && deletedSelection.isEmpty && movedUpdates.isEmpty)
            }
        }
        .padding()
        .onAppear {
            print("🔍 [FileChangesSheet] onAppear - newFiles.count = \(newFiles.count), deletedTracks.count = \(deletedTracks.count)")
            newFilesSelection = Set(newFiles)
            deletedSelection = Set(deletedTracks.compactMap { $0.id })
            print("🔍 [FileChangesSheet] Set newFilesSelection.count = \(newFilesSelection.count), deletedSelection.count = \(deletedSelection.count)")
        }
    }
}

#Preview {
    let collectionService = CollectionService()
    return TrackListView(
        collectionService: collectionService,
        audioService: AudioService()
    )
}

// MARK: - File Changes Data
struct FileChangesData: Identifiable {
    let id = UUID()
    let newFiles: [String]
    let deletedTracks: [Track]
    let movedUpdates: [CollectionService.MovedFileUpdate]
}
