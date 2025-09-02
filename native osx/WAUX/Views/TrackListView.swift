import SwiftUI
import UniformTypeIdentifiers
import CoreTransferable

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
    case dateAdded
    
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
        case .dateAdded: return "Date Added"
        }
    }
}

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
            // Drag handle column - always visible and first
            TableColumn("", value: \.title) { track in
                dragHandle(for: track)
            }
            .width(24)
            
            // Waveform column - always visible and second
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
                TableColumn("Artist", value: \.artist)
                    .width(min: 100, ideal: columnWidths[.artist] ?? 150)
            }
            
            if visibleColumns.contains(.album) {
                TableColumn("Album", value: \.album)
                    .width(min: 100, ideal: columnWidths[.album] ?? 150)
            }
            
            if visibleColumns.contains(.duration) {
                TableColumn("Duration", value: \.formattedDuration)
                    .width(min: 50, ideal: columnWidths[.duration] ?? 70)
            }
            
            if visibleColumns.contains(.rating) {
                TableColumn("Rating", value: \.rating) { track in
                    ratingCell(for: track)
                }
                .width(min: 80, ideal: columnWidths[.rating] ?? 100)
            }
            
//            if visibleColumns.contains(.type) {
//                TableColumn("Type", value: \.sourceType.rawValue) { track in
//                    typeCell(for: track)
//                }
//                .width(min: 60, ideal: columnWidths[.type] ?? 80)
//            }
            
            if visibleColumns.contains(.dateAdded) {
                TableColumn("Date Added", value: \.formattedDateAdded)
                    .width(min: 120, ideal: columnWidths[.dateAdded] ?? 140)
            }
            
            if visibleColumns.contains(.composer) {
                TableColumn("Composer", value: \Track.composerText)
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
    
    @ViewBuilder
    private func dragHandle(for track: Track) -> some View {
        if #available(macOS 13.0, *) {
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
                .font(.caption)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
                .draggable(dragPayload(for: track)) {
                    dragPreview(for: track)
                }
        } else {
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
                .font(.caption)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
                .onDrag { dragItem(for: track) }
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

    // MARK: - Drag support (Transferable + preview on macOS 13+)

    struct DraggedTracks: Transferable {
        let paths: [String]
        static var transferRepresentation: some TransferRepresentation {
            DataRepresentation(contentType: .plainText) { value in
                (value.paths.joined(separator: "\n")).data(using: .utf8) ?? Data()
            } importing: { data in
                let string = String(data: data, encoding: .utf8) ?? ""
                let paths = string.split(separator: "\n").map { String($0) }
                return DraggedTracks(paths: paths)
            }
        }
    }

    private func tracksForDrag(from track: Track) -> [Track] {
        let draggedIds = selectedTracks
        if let tid = track.id, draggedIds.contains(tid), !draggedIds.isEmpty {
            let selectedIdSet = draggedIds
            return filteredTracks.filter { candidate in
                if let cid = candidate.id { return selectedIdSet.contains(cid) }
                return false
            }
        } else {
            return [track]
        }
    }

    private func dragPayload(for track: Track) -> DraggedTracks {
        let paths = tracksForDrag(from: track).map { $0.path }
        return DraggedTracks(paths: paths)
    }

    @ViewBuilder
    private func dragPreview(for track: Track) -> some View {
        let tracks = tracksForDrag(from: track)
        HStack(spacing: 8) {
            Image(systemName: "music.note.list")
                .font(.title2)
            if tracks.count == 1 {
                Text(tracks[0].displayTitle)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .fixedSize()
            } else {
                Text("\(tracks.count) tracks")
                    .font(.caption)
                    .foregroundColor(.primary)
                    .fixedSize()
            }
        }
        .padding(8)
        .background(.regularMaterial)
        .cornerRadius(8)
        .shadow(radius: 2)
        .frame(minWidth: 160, minHeight: 60)
    }



    private func dragItem(for track: Track) -> NSItemProvider {
        // Determine which tracks to include in the drag: selected ones if the dragged
        // track is selected, otherwise just the single row's track.
        let draggedIds = selectedTracks
        let tracksToExport: [Track]
        if let tid = track.id, draggedIds.contains(tid), !draggedIds.isEmpty {
            let selectedIdSet = draggedIds
            tracksToExport = filteredTracks.filter { idTrack in
                if let sid = idTrack.id {
                    return selectedIdSet.contains(sid)
                }
                return false
            }
        } else {
            tracksToExport = [track]
        }

        let paths = tracksToExport.map { $0.path }
        let payload = paths.joined(separator: "\n")
        
        print("🔍 [TrackListView] Creating drag item:")
        print("   - Track: \(track.title)")
        print("   - Selected tracks count: \(draggedIds.count)")
        print("   - Tracks to export: \(tracksToExport.count)")
        print("   - Paths: \(paths)")
        print("   - Payload type: \(type(of: payload))")
        print("   - Payload length: \(payload.count)")
        print("   - Payload content: '\(payload)'")
        
        return NSItemProvider(object: payload as NSString)
    }
}

struct TrackListView: View {
    @ObservedObject var collectionService: CollectionService
    @ObservedObject var audioService: AudioService
    let tracksFilter: [Track]? // If provided, only show these tracks; otherwise show all tracks
    @ObservedObject var searchService: SearchService
    @Binding var isImportingNewFolder: Bool
    let initialLoadComplete: Bool
    @StateObject private var waveformServiceHolder = WaveformServiceHolder()
    @StateObject private var metadataManager: TrackMetadataManager
    @State private var sortOrder = [KeyPathComparator(\Track.title)]
    @State private var selectedTracks = Set<Track.ID>()
    @State private var showingRatingError = false
    @State private var ratingErrorMessage = ""
    @State private var visibleColumns: Set<TrackColumn> = [.waveformData, .title, .artist, .album, .duration, .rating, .generalTags, .type, .dateAdded]
    @State private var showTagEditor = false
    @State private var showMetadataEditor = false
    @State private var columnWidths: [TrackColumn: CGFloat] = [:]
    @State private var hasLoadedPreferences = false
    @State private var showDatabaseRepair = false
    @State private var corruptedTracks: [(id: Int, title: String, issues: [String])] = []
    @State private var isScanningDatabase = false
    @State private var showFileChangesSheet = false
    @State private var fileChangesData: FileChangesData? = nil
    @State private var hasRunInitialScan = false
    @FocusState private var isTextFieldFocused: Bool
    private let visibleColumnsDefaultsKey = "TrackListView.visibleColumns"
    private let columnWidthsDefaultsKey = "TrackListView.columnWidths"
    
    init(collectionService: CollectionService, audioService: AudioService, tracksFilter: [Track]? = nil, searchService: SearchService, isImportingNewFolder: Binding<Bool> = .constant(false), initialLoadComplete: Bool = false) {
        self.collectionService = collectionService
        self.audioService = audioService
        self.tracksFilter = tracksFilter
        self.searchService = searchService
        self._isImportingNewFolder = isImportingNewFolder
        self.initialLoadComplete = initialLoadComplete
        self._metadataManager = StateObject(wrappedValue: TrackMetadataManager(collectionService: collectionService))
    }
    

    
    var filteredTracks: [Track] {
        let baseTracks = tracksFilter ?? collectionService.tracks
        let filteredTracks = searchService.filterTracks(baseTracks)
        return filteredTracks.sorted(using: sortOrder)
    }
    
    var body: some View {
        VStack {
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
                        // Check if this track is already loaded and playing
                        if audioService.currentTrack?.id == track.id {
                            // Same track - toggle play/pause
                            audioService.togglePlayPause()
                        } else {
                            // Different track - load and play
                            Task {
                                await audioService.loadTrack(track)
                                audioService.play()
                            }
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
        .sheet(isPresented: $showMetadataEditor) {
            let selectedTrackIds = filteredTracks
                .filter { selectedTracks.contains($0.id) }
                .compactMap { $0.id }
            
            MetadataEditorView(
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
                onDismiss: {
                    fileChangesData = nil
                },
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
        }
        .onAppear {
            // Set up auto-play callback for AudioService
            audioService.setNextTrackCallback { [self] in
                self.getNextTrackForAutoPlay()
            }
            audioService.setPreviousTrackCallback { [self] in
                self.getPreviousTrackForAutoPlay()
            }
        }
        .onAppear(perform: loadPreferences)
        .task {
            // Only scan for file changes after the initial load is complete and we haven't run it yet
            if initialLoadComplete && !hasRunInitialScan {
                hasRunInitialScan = true
                await scanForFileChanges()
            }
        }
        .onChange(of: visibleColumns) { _, _ in
            saveVisibleColumns()
        }
        .onChange(of: initialLoadComplete) { _, isComplete in
            if isComplete {
                hasRunInitialScan = false
            }
        }
    }
    
    // MARK: - Auto-play functionality
    
    /// Gets the next track for auto-play based on the current playing track
    private func getNextTrackForAutoPlay() -> Track? {
        guard let currentTrack = audioService.currentTrack,
              let currentIndex = filteredTracks.firstIndex(where: { $0.id == currentTrack.id }) else {
            return nil
        }
        
        let nextIndex = currentIndex + 1
        guard nextIndex < filteredTracks.count else {
            // Reached end of list, could loop back to beginning if desired
            // For now, return nil to stop playback
            return nil
        }
        
        let nextTrack = filteredTracks[nextIndex]
        print("🔍 [TrackListView] Auto-play: Current track '\(currentTrack.title)' at index \(currentIndex), next track '\(nextTrack.title)' at index \(nextIndex)")
        return nextTrack
    }
    
    /// Gets the previous track for auto-play based on the current playing track
    private func getPreviousTrackForAutoPlay() -> Track? {
        guard let currentTrack = audioService.currentTrack,
              let currentIndex = filteredTracks.firstIndex(where: { $0.id == currentTrack.id }) else {
            return nil
        }
        
        let previousIndex = currentIndex - 1
        guard previousIndex >= 0 else {
            // Reached beginning of list, could loop back to end if desired
            // For now, return nil to stop playback
            return nil
        }
        
        let previousTrack = filteredTracks[previousIndex]
        print("🔍 [TrackListView] Auto-play: Current track '\(currentTrack.title)' at index \(currentIndex), previous track '\(previousTrack.title)' at index \(previousIndex)")
        return previousTrack
    }
    
    // MARK: - Helper Functions
    
    private func revealInFinder(track: Track) {
        let fileURL = URL(fileURLWithPath: track.path)
        NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: fileURL.deletingLastPathComponent().path)
    }
    
    private func refreshTrackData(track: Track) {
        guard let trackId = track.id else { return }
        
        Task {
            do {
                // Refresh the track data in the database (this will also update the track in memory)
                try await collectionService.refreshTrackData(trackId: trackId)
                print("✅ Successfully refreshed track data for: \(track.title)")
                
                // Trigger waveform analysis for the refreshed track
                await MainActor.run {
                    waveformServiceHolder.ensure(collectionService: collectionService)
                    // Create a track object with cleared waveform data to trigger analysis
                    let refreshedTrack = Track(
                        id: track.id,
                        title: track.title,
                        artist: track.artist,
                        album: track.album,
                        albumArtist: track.albumArtist,
                        composer: track.composer,
                        genre: track.genre,
                        year: track.year,
                        trackNumber: track.trackNumber,
                        discNumber: track.discNumber,
                        bpm: track.bpm,
                        path: track.path,
                        isUrl: track.isUrl,
                        duration: track.duration,
                        timeMarkers: track.timeMarkers,
                        waveformData: nil, // Clear waveform data to trigger analysis
                        rating: track.rating,
                        comment: track.comment,
                        generalTags: track.generalTags,
                        dateAdded: track.dateAdded
                    )
                    waveformServiceHolder.service?.analyzeIfMissing(refreshedTrack)
                    print("🔄 Triggered waveform analysis for refreshed track: \(track.title)")
                }
                
            } catch {
                print("❌ Failed to refresh track data for \(track.title): \(error)")
            }
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
            Button("Edit Metadata…") {
                showMetadataEditor = true
            }
            
            // Only show "Refresh Data" for local files
            if let selectedTrack = selectedTracks.first,
               let track = filteredTracks.first(where: { $0.id == selectedTrack }),
               !track.isUrl {
                Button("Refresh Data…") {
                    refreshTrackData(track: track)
                }
            }
            
            // Only show "Reveal in Finder" for local files
            if let selectedTrack = selectedTracks.first,
               let track = filteredTracks.first(where: { $0.id == selectedTrack }),
               !track.isUrl {
                Button("Reveal in Finder") {
                    revealInFinder(track: track)
                }
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
            visibleColumns = [.waveformData, .title, .artist, .album, .duration, .rating, .generalTags, .type, .dateAdded]
        }
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
        // Skip scan if we're currently importing a new folder
        if isImportingNewFolder {
            print("🔍 [TrackListView] Skipping scan - currently importing new folder")
            return
        }
        

        
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
            let columnIdentifiers = ["", "Waveform", "Title", "Artist", "Album", "Duration", "Rating", "Type", "Date Added", "Album Artist", "Composer", "Tags"]
            
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
                    case "Date Added": return .dateAdded
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
    var onDismiss: () -> Void
    var onApply: (_ adds: [String], _ deletes: [Int], _ moves: [CollectionService.MovedFileUpdate]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                Text("Library Changes Detected")
                    .font(.title2)
                    .bold()
            }
            
            Text("The following changes have been detected in your music library:")
                .foregroundColor(.secondary)
            
            // Summary
            VStack(alignment: .leading, spacing: 8) {
                if !newFiles.isEmpty {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.green)
                        Text("\(newFiles.count) new file\(newFiles.count == 1 ? "" : "s") added to library")
                            .fontWeight(.medium)
                    }
                }
                
                if !deletedTracks.isEmpty {
                    HStack {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                        Text("\(deletedTracks.count) file\(deletedTracks.count == 1 ? "" : "s") removed from library")
                            .fontWeight(.medium)
                    }
                }
                
                if !movedUpdates.isEmpty {
                    HStack {
                        Image(systemName: "arrow.right.arrow.left.circle.fill")
                            .foregroundColor(.blue)
                        Text("\(movedUpdates.count) file\(movedUpdates.count == 1 ? "" : "s") moved/renamed")
                            .fontWeight(.medium)
                    }
                }
            }
            .padding(.vertical, 8)
            
            // Details section
            if !newFiles.isEmpty || !deletedTracks.isEmpty || !movedUpdates.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Details:")
                        .font(.headline)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            // New files
                            if !newFiles.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("New Files:")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.green)
                                    
                                    ForEach(newFiles.prefix(10), id: \.self) { path in
                                        HStack {
                                            Image(systemName: "plus.circle")
                                                .foregroundColor(.green)
                                                .font(.caption)
                                            Text(URL(fileURLWithPath: path).lastPathComponent)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    if newFiles.count > 10 {
                                        Text("... and \(newFiles.count - 10) more")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .italic()
                                    }
                                }
                            }
                            
                            // Deleted files
                            if !deletedTracks.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Removed Files:")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.red)
                                    
                                    ForEach(deletedTracks.prefix(10), id: \.id) { track in
                                        HStack {
                                            Image(systemName: "minus.circle")
                                                .foregroundColor(.red)
                                                .font(.caption)
                                            Text(track.displayTitle)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    if deletedTracks.count > 10 {
                                        Text("... and \(deletedTracks.count - 10) more")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .italic()
                                    }
                                }
                            }
                            
                            // Moved files
                            if !movedUpdates.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Moved Files:")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.blue)
                                    
                                    ForEach(movedUpdates.prefix(10), id: \.id) { upd in
                                        HStack {
                                            Image(systemName: "arrow.right.arrow.left")
                                                .foregroundColor(.blue)
                                                .font(.caption)
                                            Text(upd.trackTitle)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    if movedUpdates.count > 10 {
                                        Text("... and \(movedUpdates.count - 10) more")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .italic()
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 200)
                }
            }
            
            Spacer()
            
            // Action button
            HStack {
                Spacer()
                Button("OK") {
                    // Apply all changes when OK is clicked
                    let deletedIds = deletedTracks.compactMap { $0.id }
                    onApply(newFiles, deletedIds, movedUpdates)
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 300)
    }
}

#Preview {
    let collectionService = CollectionService()
    TrackListView(
        collectionService: collectionService,
        audioService: AudioService(),
        searchService: SearchService()
    )
}

// MARK: - File Changes Data
struct FileChangesData: Identifiable {
    let id = UUID()
    let newFiles: [String]
    let deletedTracks: [Track]
    let movedUpdates: [CollectionService.MovedFileUpdate]
}
