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
    let displayItems: [TrackDisplayItem]
    @Binding var selectedTracks: Set<TrackDisplayItem.ID>
    @Binding var sortOrder: [KeyPathComparator<TrackDisplayItem>]
    @Binding var visibleColumns: Set<TrackColumn>
    @Binding var columnWidths: [TrackColumn: CGFloat]
    @Binding var isTextFieldFocused: Bool
    @FocusState var isTableFocused: Bool
    @ObservedObject var audioService: AudioService
    @ObservedObject var metadataManager: TrackMetadataManager
    @ObservedObject var waveformServiceHolder: WaveformServiceHolder
    @ObservedObject var collectionService: CollectionService
    @ObservedObject var trackGroupService: TrackGroupService
    let onDoubleClick: (Track) -> Void
    let onKeyPressA: () -> Void
    let onKeyPressSpace: () -> Void
    let onKeyPressBackspace: () -> Void
    let onColumnWidthChange: () -> Void
    let onGroupToggle: (String) -> Void
    let onGoToCurrentTrack: () -> Void
    
    var body: some View {
        Table(displayItems, selection: $selectedTracks, sortOrder: $sortOrder) {
            // Drag handle column - always visible and first
            // Use a small settings icon in the header to represent the columns menu
            TableColumn("⚙︎") { (displayItem: TrackDisplayItem) in
                dragHandle(for: displayItem)
            }
            .width(24)
            
            // Waveform column - always visible and second
            TableColumn("Waveform", value: \.track.waveformPointCount) { displayItem in
                WaveformColumn(
                    track: displayItem.track,
                    audioService: audioService,
                    waveformServiceHolder: waveformServiceHolder,
                    collectionService: collectionService
                )
                .id("waveform-\(displayItem.track.id ?? -1)-\(displayItem.track.waveformPointCount)")
                .help(tooltipForDisplayItem(displayItem))
                .background(backgroundForDisplayItem(displayItem))
            }
            .width(min: 120, ideal: columnWidths[.waveformData] ?? 160, max:200)
            
            TableColumn("Title", value: \.track.title) { displayItem in
                titleCell(for: displayItem)
            }
            .width(min: 150, ideal: columnWidths[.title] ?? 250)
            
            // Note: Conditional columns removed for macOS 13 compatibility
            // All columns are now always visible
            TableColumn("Artist", value: \.track.artist) { displayItem in
                EditableTrackCell(
                    text: displayItem.track.artist,
                    track: displayItem.track,
                    property: "artist",
                    isSelected: selectedTracks.contains(displayItem.id),
                    metadataManager: metadataManager
                )
                    .padding(.vertical, 2)
                    .background(backgroundForDisplayItem(displayItem))
                    .cornerRadius(4)
            }
            .width(min: 100, ideal: columnWidths[.artist] ?? 150)
            
            TableColumn("Album", value: \.track.album) { displayItem in
                EditableTrackCell(
                    text: displayItem.track.album,
                    track: displayItem.track,
                    property: "album",
                    isSelected: selectedTracks.contains(displayItem.id),
                    metadataManager: metadataManager
                )
                    .padding(.vertical, 2)
                    .background(backgroundForDisplayItem(displayItem))
                    .cornerRadius(4)
            }
            .width(min: 100, ideal: columnWidths[.album] ?? 120)
            
            TableColumn("Duration", value: \.track.formattedDuration) { displayItem in
                Text(displayItem.track.formattedDuration)
                    .padding(.vertical, 2)
                    .background(backgroundForDisplayItem(displayItem))
                    .cornerRadius(4)
            }
            .width(min: 5, ideal: 10, max:80)
            
            TableColumn("Rating", value: \.track.rating) { displayItem in
                ratingCell(for: displayItem)
                    .padding(.vertical, 2)
                    .background(backgroundForDisplayItem(displayItem))
                    .cornerRadius(4)
            }
            .width(min: 60, ideal: columnWidths[.rating] ?? 70, max: 100)
            
            TableColumn("Date Added", value: \.track.dateAddedSortValue) { displayItem in
                Text(displayItem.track.formattedDateAdded)
                    .padding(.vertical, 2)
                    .background(backgroundForDisplayItem(displayItem))
                    .cornerRadius(4)
            }
            .width(min: 120, ideal: columnWidths[.dateAdded] ?? 140)
            
            TableColumn("Composer", value: \.track.composerText) { displayItem in
                EditableTrackCell(
                    text: displayItem.track.composerText,
                    track: displayItem.track,
                    property: "composer",
                    isSelected: selectedTracks.contains(displayItem.id),
                    metadataManager: metadataManager
                )
                    .padding(.vertical, 2)
                    .background(backgroundForDisplayItem(displayItem))
                    .cornerRadius(4)
            }
            .width(min: 100, ideal: columnWidths[.composer] ?? 150)
            
            TableColumn("Tags", value: \.track.generalTags.count) { displayItem in
                if let trackId = displayItem.track.id {
                    InteractiveTagsView_New(
                        trackId: trackId,
                        metadataManager: metadataManager,
                        isTextFieldFocused: $isTextFieldFocused
                    )
                    .padding(.vertical, 2)
                    .background(backgroundForDisplayItem(displayItem))
                    .cornerRadius(4)
                }
            }
            .width(min: 120, ideal: columnWidths[.generalTags] ?? 200, max:600)
        }
        .tableStyle(.bordered)
        .focusable()
        .focused($isTableFocused)
        .background(TableWidthObserver(columnWidths: $columnWidths, onWidthChange: onColumnWidthChange))
        .onTapGesture(count: 2) {
            if let selectedTrack = selectedTracks.first,
               let displayItem = displayItems.first(where: { $0.id == selectedTrack }) {
                onDoubleClick(displayItem.track)
            }
        }
        .background(KeyboardEventHandler(
            isTextFieldFocused: isTextFieldFocused,
            isTableFocused: isTableFocused,
            hasSelection: !selectedTracks.isEmpty,
            onCommandA: onKeyPressA,
            onSpace: onKeyPressSpace,
            onBackspace: onKeyPressBackspace,
            onCommandL: onGoToCurrentTrack
        ))
        .onDeleteCommand {
            if !isTextFieldFocused && isTableFocused && !selectedTracks.isEmpty {
                onKeyPressBackspace()
            }
        }
        .onAppear {
            // Set focus to the table when it appears to ensure it can receive keyboard events
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTableFocused = true
            }
        }
    }
    
    @ViewBuilder
    private func titleCell(for displayItem: TrackDisplayItem) -> some View {
        HStack(spacing: 8) {
            // Enhanced chevron indicator for container tracks
            if case .container(let groupedTrack) = displayItem {
                Button(action: {
                    onGroupToggle(groupedTrack.group.id)
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.1))
                            .frame(width: 18, height: 18)
                        
                        Image(systemName: groupedTrack.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .help("Click to \(groupedTrack.isExpanded ? "collapse" : "expand") group (\(groupedTrack.trackCount) tracks)")
            } else if case .groupMember(let track, let groupId) = displayItem {
                // Enhanced indentation for group members with visual connection line
                HStack(spacing: 0) {
                    // Connection line from parent group
                    Rectangle()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 1, height: 20)
                        .padding(.leading, 8)
                    
                    // Horizontal connector
                    Rectangle()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 8, height: 1)
                    
                    // Main track indicator or member bullet
                    let isMainTrack = getGroupById(groupId)?.mainTrackId == track.id
                    Circle()
                        .fill(isMainTrack ? Color.yellow : Color.secondary.opacity(0.6))
                        .frame(width: 4, height: 4)
                        .padding(.trailing, 4)
                }
                .frame(width: 24)
            } else {
                // Individual tracks get no indentation but maintain alignment
                Spacer()
                    .frame(width: 0)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    // Title with enhanced styling based on item type
                    HStack(spacing: 4) {
                        // Group icon for container tracks
                        if displayItem.isContainer {
                            Image(systemName: "rectangle.3.group")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                        }
                        
                        EditableTrackCell(
                            text: displayItem.track.title,
                            track: displayItem.track,
                            property: "title",
                            isSelected: selectedTracks.contains(displayItem.id),
                            fontWeight: displayItem.isContainer ? .semibold : 
                                       displayItem.isMember ? .regular : .medium,
                            metadataManager: metadataManager
                        )
                            .foregroundColor(displayItem.isContainer ? .accentColor : .primary)
                    }
                    
                    // Enhanced track count display for container tracks
                    if case .container(let groupedTrack) = displayItem {
                        HStack(spacing: 2) {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 8))
                                .foregroundColor(.accentColor)
                            Text("\(groupedTrack.trackCount)")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.accentColor)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.accentColor.opacity(0.3), lineWidth: 0.5)
                        )
                        .cornerRadius(8)
                    }
                    
                    // Show main track indicator for group members
                    if case .groupMember(let track, let groupId) = displayItem,
                       let group = getGroupById(groupId),
                       track.id == group.mainTrackId {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundColor(.yellow)
                            Text("MAIN")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.yellow)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(Color.yellow.opacity(0.2))
                                .cornerRadius(3)
                        }
                        .help("Main track in group")
                    }
                    
                    Spacer()
                }
                
                // Artist info (only show if not empty and not "Unknown")
                if !displayItem.track.artist.isEmpty && displayItem.track.artist != "Unknown" {
                    Text(displayItem.track.artist)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .background(backgroundForDisplayItem(displayItem))
        .cornerRadius(4)
    }
    
    @ViewBuilder
    private func ratingCell(for displayItem: TrackDisplayItem) -> some View {
        if let trackId = displayItem.track.id {
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
    private func dragHandle(for displayItem: TrackDisplayItem) -> some View {
        let tooltipText = tooltipForDisplayItem(displayItem)
        
        if #available(macOS 13.0, *) {
            Image(systemName: dragIconForDisplayItem(displayItem))
                .foregroundColor(.secondary)
                .font(.caption)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
                .help(tooltipText)
                .draggable(dragPayload(for: displayItem.track)) {
                    dragPreview(for: displayItem.track)
                }
                .onHover { hovering in
                    // When the preview is about to show and hover starts during drag, mark drag kind
                    if hovering {
                        Task { @MainActor in
                            DragStateManager.shared.beginTrackDrag()
                        }
                    }
                }
                .contextMenu {
                    // Column visibility controls when right-clicking the drag handle
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
                        .disabled(column == .title || column == .waveformData)
                    }
                    Divider()
                    Button("Show All Columns") {
                        visibleColumns = Set(TrackColumn.allCases)
                    }
                    Button("Show Default Columns") {
                        visibleColumns = [.waveformData, .title, .artist, .album, .duration, .rating, .generalTags, .type, .dateAdded]
                    }
                }
        } else {
            Image(systemName: dragIconForDisplayItem(displayItem))
                .foregroundColor(.secondary)
                .font(.caption)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
                .help(tooltipText)
                .onDrag { dragItem(for: displayItem.track) }
                .onHover { hovering in
                    if hovering {
                        Task { @MainActor in
                            DragStateManager.shared.beginTrackDrag()
                        }
                    }
                }
                .contextMenu {
                    // Column visibility controls when right-clicking the drag handle
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
                        .disabled(column == .title || column == .waveformData)
                    }
                    Divider()
                    Button("Show All Columns") {
                        visibleColumns = Set(TrackColumn.allCases)
                    }
                    Button("Show Default Columns") {
                        visibleColumns = [.waveformData, .title, .artist, .album, .duration, .rating, .generalTags, .type, .dateAdded]
                    }
                }
        }
    }
    
    // Helper method to get appropriate drag icon for display item type
    private func dragIconForDisplayItem(_ displayItem: TrackDisplayItem) -> String {
        switch displayItem {
        case .container:
            return "rectangle.3.group"
        case .groupMember:
            return "line.3.horizontal"
        case .individual:
            return "line.3.horizontal"
        }
    }
    
    // Helper method to generate tooltip text for display items
    private func tooltipForDisplayItem(_ displayItem: TrackDisplayItem) -> String {
        switch displayItem {
        case .container(let groupedTrack):
            return "Track Group: \(groupedTrack.title) (\(groupedTrack.trackCount) tracks)"
        case .groupMember(let track, let groupId):
            if let group = getGroupById(groupId), track.id == group.mainTrackId {
                return "Main track in group: \(track.title)"
            } else {
                return "Group member: \(track.title)"
            }
        case .individual(let track):
            return "Individual track: \(track.title)"
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

    @available(macOS 13.0, *)
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
        // Find the display item for this track
        guard let trackDisplayItem = displayItems.first(where: { $0.track.id == track.id }) else {
            return [track]
        }
        
        // Check if this display item is selected
        if selectedTracks.contains(trackDisplayItem.id) && !selectedTracks.isEmpty {
            // Return all selected tracks, handling containers properly
            return getTracksFromSelectedDisplayItems()
        } else {
            // Single track drag - handle container tracks
            return getTracksFromDisplayItem(trackDisplayItem)
        }
    }
    
    /// Gets all tracks from selected display items, handling containers properly
    private func getTracksFromSelectedDisplayItems() -> [Track] {
        var tracks: [Track] = []
        var processedGroupIds: Set<String> = []
        
        for selectedId in selectedTracks {
            guard let displayItem = displayItems.first(where: { $0.id == selectedId }) else { continue }
            
            switch displayItem {
            case .individual(let track):
                tracks.append(track)
                
            case .container(let groupedTrack):
                // For container tracks, add the main track (represents the group)
                tracks.append(groupedTrack.mainTrack)
                processedGroupIds.insert(groupedTrack.group.id)
                
            case .groupMember(let track, let groupId):
                // Only add group members if their container isn't already selected
                if !processedGroupIds.contains(groupId) {
                    tracks.append(track)
                }
            }
        }
        
        return tracks
    }
    
    /// Gets tracks from a single display item, handling containers properly
    private func getTracksFromDisplayItem(_ displayItem: TrackDisplayItem) -> [Track] {
        switch displayItem {
        case .individual(let track):
            return [track]
            
        case .container(let groupedTrack):
            // For container tracks, return the main track (represents the group)
            return [groupedTrack.mainTrack]
            
        case .groupMember(let track, _):
            // For group members, return the individual track
            return [track]
        }
    }
    
    @ViewBuilder
    private func backgroundForDisplayItem(_ displayItem: TrackDisplayItem) -> some View {
        switch displayItem {
        case .container:
            // Distinct background for container tracks with subtle accent color
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
                )
        case .groupMember(let track, let groupId):
            // Enhanced background for group members with indentation effect
            let isMainTrack = getGroupById(groupId)?.mainTrackId == track.id
            RoundedRectangle(cornerRadius: 4)
                .fill(isMainTrack ? 
                      Color.yellow.opacity(0.15) : 
                      Color.secondary.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isMainTrack ? 
                               Color.yellow.opacity(0.3) : 
                               Color.secondary.opacity(0.2), lineWidth: 0.5)
                )
        case .individual:
            Color.clear
        }
    }
    
    // Helper method to get group by ID from trackGroupService
    private func getGroupById(_ groupId: String) -> TrackGroup? {
        return trackGroupService.groups.first { $0.id == groupId }
    }

    @available(macOS 13.0, *)
    private func dragPayload(for track: Track) -> DraggedTracks {
        let tracks = tracksForDrag(from: track)
        let paths = tracks.map { $0.path }
        
        // Log drag payload for debugging
        print("🎵 [TrackListView] Creating drag payload:")
        print("   - Source track: \(track.title)")
        print("   - Tracks to drag: \(tracks.count)")
        for (index, dragTrack) in tracks.enumerated() {
            print("   - [\(index)] \(dragTrack.title) (\(dragTrack.path))")
        }
        // Mark drag kind globally for hover targets
        Task { @MainActor in
            DragStateManager.shared.beginTrackDrag()
        }
        
        return DraggedTracks(paths: paths)
    }

    @available(macOS 13.0, *)
    @ViewBuilder
    private func dragPreview(for track: Track) -> some View {
        let tracks = tracksForDrag(from: track)
        let dragInfo = getDragPreviewInfo(for: track, tracks: tracks)
        
        HStack(spacing: 8) {
            Image(systemName: dragInfo.icon)
                .font(.title2)
                .foregroundColor(dragInfo.iconColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(dragInfo.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .fixedSize()
                
                if let subtitle = dragInfo.subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .padding(8)
        .background(.regularMaterial)
        .cornerRadius(8)
        .shadow(radius: 2)
        .frame(minWidth: 160, minHeight: 60)
    }
    
    /// Gets preview information for drag operation
    private func getDragPreviewInfo(for track: Track, tracks: [Track]) -> (icon: String, iconColor: Color, title: String, subtitle: String?) {
        // Find the display item for this track to determine context
        guard let trackDisplayItem = displayItems.first(where: { $0.track.id == track.id }) else {
            return ("music.note", .primary, track.displayTitle, nil)
        }
        
        // Handle multiple selection
        if selectedTracks.count > 1 {
            let containerCount = selectedTracks.compactMap { selectedId in
                displayItems.first(where: { $0.id == selectedId })
            }.filter { item in
                if case .container = item { return true }
                return false
            }.count
            
            let individualCount = tracks.count - containerCount
            
            if containerCount > 0 && individualCount > 0 {
                return ("rectangle.3.group", .accentColor, "\(selectedTracks.count) items", "\(containerCount) groups, \(individualCount) tracks")
            } else if containerCount > 0 {
                return ("rectangle.3.group", .accentColor, "\(containerCount) track groups", nil)
            } else {
                return ("music.note.list", .primary, "\(tracks.count) tracks", nil)
            }
        }
        
        // Handle single item drag
        switch trackDisplayItem {
        case .container(let groupedTrack):
            return ("rectangle.3.group", .accentColor, groupedTrack.title, "\(groupedTrack.trackCount) tracks in group")
            
        case .groupMember(let track, let groupId):
            if let group = getGroupById(groupId), track.id == group.mainTrackId {
                return ("star.fill", .yellow, track.displayTitle, "Main track in group")
            } else {
                return ("music.note", .secondary, track.displayTitle, "Group member")
            }
            
        case .individual(let track):
            return ("music.note", .primary, track.displayTitle, nil)
        }
    }



    private func dragItem(for track: Track) -> NSItemProvider {
        let tracksToExport = tracksForDrag(from: track)
        let paths = tracksToExport.map { $0.path }
        let payload = paths.joined(separator: "\n")
        
        print("🔍 [TrackListView] Creating legacy drag item:")
        print("   - Source track: \(track.title)")
        print("   - Selected display items: \(selectedTracks.count)")
        print("   - Tracks to export: \(tracksToExport.count)")
        for (index, exportTrack) in tracksToExport.enumerated() {
            print("   - [\(index)] \(exportTrack.title)")
        }
        print("   - Payload length: \(payload.count) characters")
        // Mark drag kind globally for hover targets (legacy path)
        Task { @MainActor in
            DragStateManager.shared.beginTrackDrag()
        }
        
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
    @StateObject private var trackGroupService: TrackGroupService
    @StateObject private var trackDisplayService: TrackDisplayService
    @State private var sortOrder = [KeyPathComparator(\TrackDisplayItem.track.title)]
    @State private var selectedDisplayItems = Set<TrackDisplayItem.ID>()
    @State private var displayItems: [TrackDisplayItem] = []
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
    @State private var showDeleteConfirmation = false
    @State private var tracksToDelete: [Track] = []
    @FocusState private var isTextFieldFocused: Bool
    @State private var preservedSelection: Set<Track.ID> = []
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
        let groupService = TrackGroupService()
        self._trackGroupService = StateObject(wrappedValue: groupService)
        self._trackDisplayService = StateObject(wrappedValue: TrackDisplayService(trackGroupService: groupService))
    }
    

    
    var filteredTracks: [Track] {
        let baseTracks = tracksFilter ?? metadataManager.getAllTracks()
        let filteredTracks = searchService.filterTracks(baseTracks)
        return filteredTracks
    }
    
    var filteredDisplayItems: [TrackDisplayItem] {
        let tracks = filteredTracks
        let displayItems = trackDisplayService.convertTracksToDisplayItems(tracks)
        let searchFilteredItems = searchService.filterDisplayItems(displayItems)
        let sortedItems = sortGroupAware(searchFilteredItems, using: sortOrder)
        return trackDisplayService.filterCollapsedGroups(sortedItems)
    }
    
    private func updateDisplayItems() {
        displayItems = filteredDisplayItems
    }
    
    /// Group-aware sorting that keeps group members together
    private func sortGroupAware(_ items: [TrackDisplayItem], using sortOrder: [KeyPathComparator<TrackDisplayItem>]) -> [TrackDisplayItem] {
        // Group items by their group association
        var groupedItems: [String?: [TrackDisplayItem]] = [:]
        
        for item in items {
            let groupKey = item.associatedGroupId
            if groupedItems[groupKey] == nil {
                groupedItems[groupKey] = []
            }
            groupedItems[groupKey]?.append(item)
        }
        
        // Sort each group internally and collect results
        var sortedItems: [TrackDisplayItem] = []
        
        // First, sort the group keys to maintain consistent ordering
        let sortedGroupKeys = groupedItems.keys.sorted { key1, key2 in
            // Individual tracks (nil key) are sorted by their track properties
            // Groups are sorted by their container track properties
            guard let key1 = key1, let key2 = key2 else {
                // Handle individual tracks vs groups
                if key1 == nil && key2 == nil {
                    return false // Both individual, maintain original order
                } else if key1 == nil {
                    // Individual track vs group - compare individual track with group's main track
                    let individualItems = groupedItems[nil] ?? []
                    let groupItems = groupedItems[key2] ?? []
                    if let individualItem = individualItems.first,
                       let containerItem = groupItems.first(where: { $0.isContainer }) {
                        return sortOrder.isEmpty ? false : individualItem.track.title < containerItem.track.title
                    }
                    return false
                } else {
                    // Group vs individual track
                    let groupItems = groupedItems[key1] ?? []
                    let individualItems = groupedItems[nil] ?? []
                    if let containerItem = groupItems.first(where: { $0.isContainer }),
                       let individualItem = individualItems.first {
                        return sortOrder.isEmpty ? false : containerItem.track.title < individualItem.track.title
                    }
                    return true
                }
            }
            
            // Both are groups - compare their container tracks
            let group1Items = groupedItems[key1] ?? []
            let group2Items = groupedItems[key2] ?? []
            
            guard let container1 = group1Items.first(where: { $0.isContainer }),
                  let container2 = group2Items.first(where: { $0.isContainer }) else {
                return key1 < key2 // Fallback to string comparison
            }
            
            // Use the first sort comparator to compare containers
            if let firstComparator = sortOrder.first {
                let result = firstComparator.compare(container1, container2)
                return result == .orderedAscending
            }
            
            return container1.track.title < container2.track.title
        }
        
        // Process each group in sorted order
        for groupKey in sortedGroupKeys {
            guard let groupItems = groupedItems[groupKey] else { continue }
            
            if groupKey == nil {
                // Individual tracks - sort normally
                let sorted = groupItems.sorted(using: sortOrder)
                sortedItems.append(contentsOf: sorted)
            } else {
                // Group items - maintain group structure
                // Container first, then sorted group members
                let container = groupItems.first { $0.isContainer }
                let members = groupItems.filter { $0.isMember }
                
                if let container = container {
                    sortedItems.append(container)
                }
                
                // Sort group members by their track properties, but keep main track first
                let sortedMembers = members.sorted { member1, member2 in
                    // Check if either is the main track
                    if let groupId = groupKey,
                       let group = trackGroupService.groups.first(where: { $0.id == groupId }) {
                        if member1.track.id == group.mainTrackId { return true }
                        if member2.track.id == group.mainTrackId { return false }
                    }
                    
                    // Sort by track title for non-main tracks
                    return member1.track.title < member2.track.title
                }
                
                sortedItems.append(contentsOf: sortedMembers)
            }
        }
        
        return sortedItems
    }
    
    private func handleGroupToggle(_ groupId: String) {
        displayItems = trackDisplayService.toggleGroupExpansion(groupId: groupId, currentDisplayItems: displayItems)
    }
    
    private func scrollToCurrentTrack() {
        guard let currentTrack = audioService.currentTrack else { return }
        
        // Find the display item for the current track
        if let displayItem = displayItems.first(where: { $0.track.id == currentTrack.id }) {
            // Select the current track - this will make it visible in most cases
            selectedDisplayItems = [displayItem.id]
            print("🎯 [TrackListView] Selected current track: \(currentTrack.title)")
        } else {
            print("🎯 [TrackListView] Current track not found in display items: \(currentTrack.title)")
        }
    }
    
    var body: some View {
        let _ = print("🎨 [TrackListView] Body view rendering - columnWidths: \(columnWidths.map { "\($0.key.displayName): \($0.value)" })")
        
        VStack {
            TrackTable(
                displayItems: displayItems,
                selectedTracks: $selectedDisplayItems,
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
                trackGroupService: trackGroupService,
                onDoubleClick: { track in
                    print("Double-clicked track: \(track.title)")
                    print("Track path: \(track.path)")
                    print("Is URL: \(track.isUrl)")
                    print("Duration: \(track.duration) ms")
                    Task {
                        _ = await audioService.loadTrack(track)
                        audioService.play()
                    }
                },
                onKeyPressA: {
                    selectedDisplayItems = Set(displayItems.map { $0.id })
                },
                onKeyPressSpace: {
                    // Same track - toggle play/pause
                    audioService.togglePlayPause()
                },
                onKeyPressBackspace: {
                    let selectedTracksList = displayItems.filter { selectedDisplayItems.contains($0.id) }.map { $0.track }
                    if !selectedTracksList.isEmpty {
                        tracksToDelete = selectedTracksList
                        showDeleteConfirmation = true
                    }
                },
                onColumnWidthChange: saveColumnWidths,
                onGroupToggle: handleGroupToggle,
                onGoToCurrentTrack: {
                    scrollToCurrentTrack()
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("GoToCurrentTrack"))) { _ in
            scrollToCurrentTrack()
        }
        .background(
            TableSelectionHandler(
                selectedDisplayItems: $selectedDisplayItems,
                displayItems: displayItems
            )
        )
        .contextMenu {
            if !selectedDisplayItems.isEmpty {
                trackContextMenu()
            } else {
                columnContextMenu()
            }
        }
        .alert("Rating Update Error", isPresented: $showingRatingError) {
            Button("OK") { }
        } message: {
            Text(ratingErrorMessage)
        }
        .sheet(isPresented: $showTagEditor) {
            let selectedTrackIds = getSelectedTrackIdsForMetadataEditing()
            
            TagEditorView(
                metadataManager: metadataManager,
                collectionService: collectionService,
                trackIds: selectedTrackIds
            )
        }
        .sheet(isPresented: $showMetadataEditor) {
            let selectedTrackIds = getSelectedTrackIdsForMetadataEditing()
            
            MetadataEditorView(
                metadataManager: metadataManager,
                collectionService: collectionService,
                trackIds: selectedTrackIds
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
        .onChange(of: visibleColumns) { _ in
            saveVisibleColumns()
        }
        .onChange(of: filteredTracks) { _ in
            // Update display items when tracks change
            updateDisplayItems()
            
            // Preserve selection for display items that still exist
            let newDisplayItemIds: Set<String> = Set(displayItems.map { $0.id })
            let validSelections = selectedDisplayItems.filter { displayItemId in
                return newDisplayItemIds.contains(displayItemId)
            }
            selectedDisplayItems = validSelections
        }
        .onChange(of: searchService.searchText) { _ in
            // Update display items when search changes
            updateDisplayItems()
            
            // Clear selection when search changes to avoid confusion
            selectedDisplayItems.removeAll()
        }
        .onChange(of: sortOrder) { _ in
            // Update display items when sort order changes
            updateDisplayItems()
        }
        .onAppear {
            // Initialize display items on first load
            updateDisplayItems()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("GoToCurrentTrack"))) { _ in
            // Handle menu action for Go to Current Track - find current track and select it
            guard let currentTrack = audioService.currentTrack else { return }
            
            if let displayItem = displayItems.first(where: { $0.track.id == currentTrack.id }) {
                selectedDisplayItems = [displayItem.id]
            }
        }
    }
    
    // MARK: - Auto-play functionality
    
    /// Gets the next track for auto-play based on the current playing track
    /// Uses display items to respect group structure and visibility
    private func getNextTrackForAutoPlay() -> Track? {
        guard let currentTrack = audioService.currentTrack else { return nil }
        
        // Find current track in display items
        let playableTracks = displayItems.map { $0.track }
        guard let currentIndex = playableTracks.firstIndex(where: { $0.id == currentTrack.id }) else {
            return nil
        }
        
        let nextIndex = currentIndex + 1
        guard nextIndex < playableTracks.count else {
            // Reached end of list, could loop back to beginning if desired
            // For now, return nil to stop playback
            return nil
        }
        
        let nextTrack = playableTracks[nextIndex]
        print("🔍 [TrackListView] Auto-play: Current track '\(currentTrack.title)' at index \(currentIndex), next track '\(nextTrack.title)' at index \(nextIndex)")
        return nextTrack
    }
    
    /// Gets the previous track for auto-play based on the current playing track
    /// Uses display items to respect group structure and visibility
    private func getPreviousTrackForAutoPlay() -> Track? {
        guard let currentTrack = audioService.currentTrack else { return nil }
        
        // Find current track in display items
        let playableTracks = displayItems.map { $0.track }
        guard let currentIndex = playableTracks.firstIndex(where: { $0.id == currentTrack.id }) else {
            return nil
        }
        
        let previousIndex = currentIndex - 1
        guard previousIndex >= 0 else {
            // Reached beginning of list, could loop back to end if desired
            // For now, return nil to stop playback
            return nil
        }
        
        let previousTrack = playableTracks[previousIndex]
        print("🔍 [TrackListView] Auto-play: Current track '\(currentTrack.title)' at index \(currentIndex), previous track '\(previousTrack.title)' at index \(previousIndex)")
        return previousTrack
    }
    
    // MARK: - Track Grouping Actions
    
    private func createGroupFromSelection(_ selectedItems: [TrackDisplayItem]) async {
        let trackIds = selectedItems.compactMap { $0.track.id }
        guard trackIds.count >= 2 else { 
            print("❌ Cannot create group: Need at least 2 tracks, got \(trackIds.count)")
            return 
        }
        
        // Validate that none of the selected tracks are already in groups
        let alreadyGroupedTracks = selectedItems.filter { item in
            guard let trackId = item.track.id else { return false }
            return trackGroupService.getGroupForTrack(trackId: trackId) != nil
        }
        
        if !alreadyGroupedTracks.isEmpty {
            let trackTitles = alreadyGroupedTracks.map { $0.track.title }.joined(separator: ", ")
            await MainActor.run {
                ratingErrorMessage = "Cannot group tracks that are already in groups: \(trackTitles)"
                showingRatingError = true
            }
            return
        }
        
        // Use first selected track as main track (automatic main track selection)
        let mainTrackId = trackIds.first!
        
        // Generate auto-generated group name based on main track
        let mainTrack = selectedItems.first { $0.track.id == mainTrackId }?.track
        let autoGeneratedName = generateGroupName(for: mainTrack)
        
        Task {
            do {
                let group = try await trackGroupService.createGroup(
                    trackIds: trackIds,
                    name: autoGeneratedName,
                    mainTrackId: mainTrackId
                )
                
                print("✅ Created group '\(group.displayName)' with \(group.trackCount) tracks")
                
                // Update display items to reflect the new group
                await MainActor.run {
                    updateDisplayItems()
                    selectedDisplayItems.removeAll()
                }
            } catch {
                print("❌ Failed to create group: \(error)")
                await MainActor.run {
                    ratingErrorMessage = "Failed to create group: \(error.localizedDescription)"
                    showingRatingError = true
                }
            }
        }
    }
    
    /// Generates an auto-generated group name based on the main track
    private func generateGroupName(for track: Track?) -> String {
        guard let track = track else {
            return "Track Group"
        }
        
        // Use track title as base, with fallback patterns
        let baseTitle = track.title.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if baseTitle.isEmpty {
            return "Track Group"
        }
        
        // Remove common version indicators to create a cleaner group name
        let cleanTitle = baseTitle
            .replacingOccurrences(of: #"\s*\([^)]*remix[^)]*\)"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s*\([^)]*version[^)]*\)"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s*\([^)]*edit[^)]*\)"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s*\([^)]*live[^)]*\)"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s*-\s*(remix|version|edit|live).*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let finalTitle = cleanTitle.isEmpty ? baseTitle : cleanTitle
        
        // Check if a group with this name already exists and add a number suffix if needed
        return ensureUniqueGroupName(finalTitle)
    }
    
    /// Ensures the group name is unique by adding a number suffix if needed
    private func ensureUniqueGroupName(_ baseName: String) -> String {
        let existingNames = Set(trackGroupService.groups.map { $0.name })
        
        if !existingNames.contains(baseName) {
            return baseName
        }
        
        // Find the next available number suffix
        var counter = 2
        while existingNames.contains("\(baseName) \(counter)") {
            counter += 1
        }
        
        return "\(baseName) \(counter)"
    }
    
    private func addTracksToExistingGroup(individualTracks: [TrackDisplayItem], containerTrack: TrackDisplayItem) {
        guard case .container(let groupedTrack) = containerTrack else { return }
        let trackIds = individualTracks.compactMap { $0.track.id }
        guard !trackIds.isEmpty else { return }
        
        Task {
            do {
                try await trackGroupService.addTracksToGroup(groupId: groupedTrack.group.id, trackIds: trackIds)
                print("✅ Added \(trackIds.count) tracks to group '\(groupedTrack.group.displayName)'")
                
                // Update display items to reflect the added tracks
                await MainActor.run {
                    updateDisplayItems()
                    selectedDisplayItems.removeAll()
                }
            } catch {
                print("❌ Failed to add tracks to group: \(error)")
                await MainActor.run {
                    ratingErrorMessage = "Failed to add tracks to group: \(error.localizedDescription)"
                    showingRatingError = true
                }
            }
        }
    }
    
    private func ungroupTracks(_ containerItem: TrackDisplayItem) {
        guard case .container(let groupedTrack) = containerItem else { return }
        
        Task {
            do {
                try await trackGroupService.deleteGroup(groupId: groupedTrack.group.id)
                print("✅ Ungrouped tracks from group '\(groupedTrack.group.displayName)'")
                
                // Update display items to reflect the ungrouped tracks
                await MainActor.run {
                    updateDisplayItems()
                    selectedDisplayItems.removeAll()
                }
            } catch {
                print("❌ Failed to ungroup tracks: \(error)")
                await MainActor.run {
                    ratingErrorMessage = "Failed to ungroup tracks: \(error.localizedDescription)"
                    showingRatingError = true
                }
            }
        }
    }
    
    private func setAsMainTrack(_ memberItem: TrackDisplayItem) {
        guard case .groupMember(let track, let groupId) = memberItem,
              let trackId = track.id else { return }
        
        Task {
            do {
                try await trackGroupService.setMainTrack(groupId: groupId, trackId: trackId)
                print("✅ Set track '\(track.title)' as main track for group")
                
                // Update display items to reflect the new main track
                await MainActor.run {
                    updateDisplayItems()
                }
            } catch {
                print("❌ Failed to set main track: \(error)")
                await MainActor.run {
                    ratingErrorMessage = "Failed to set main track: \(error.localizedDescription)"
                    showingRatingError = true
                }
            }
        }
    }
    
    private func removeTrackFromGroup(_ memberItem: TrackDisplayItem) {
        guard case .groupMember(let track, let groupId) = memberItem,
              let trackId = track.id else { return }
        
        Task {
            do {
                try await trackGroupService.removeTrackFromGroup(groupId: groupId, trackId: trackId)
                print("✅ Removed track '\(track.title)' from group")
                
                // Update display items to reflect the removed track
                await MainActor.run {
                    updateDisplayItems()
                    selectedDisplayItems.removeAll()
                }
            } catch {
                print("❌ Failed to remove track from group: \(error)")
                await MainActor.run {
                    ratingErrorMessage = "Failed to remove track from group: \(error.localizedDescription)"
                    showingRatingError = true
                }
            }
        }
    }

    
    // MARK: - Helper Functions
    
    /// Gets track IDs for metadata editing, handling container tracks properly
    /// For container tracks, returns the main track ID instead of the container
    private func getSelectedTrackIdsForMetadataEditing() -> [Int] {
        let selectedItems = displayItems.filter { selectedDisplayItems.contains($0.id) }
        var trackIds: [Int] = []
        var processedGroupIds: Set<String> = []
        
        for item in selectedItems {
            switch item {
            case .individual(let track):
                if let trackId = track.id {
                    trackIds.append(trackId)
                }
                
            case .container(let groupedTrack):
                // For container tracks, edit the main track
                if let mainTrackId = groupedTrack.mainTrack.id {
                    trackIds.append(mainTrackId)
                    processedGroupIds.insert(groupedTrack.group.id)
                }
                
            case .groupMember(let track, let groupId):
                // Only include group members if their container isn't already selected
                if !processedGroupIds.contains(groupId), let trackId = track.id {
                    trackIds.append(trackId)
                }
            }
        }
        
        return trackIds
    }
    
    private func deleteSelectedTracks() {
        guard !tracksToDelete.isEmpty else { return }
        
        let tracksToDeleteCount = tracksToDelete.count
        
        Task {
            do {
                // Delete tracks from database and move files to trash
                for track in tracksToDelete {
                    if let trackId = track.id {
                        try collectionService.deleteTrackAndMoveToTrash(trackId)
                        print("✅ Successfully deleted track and moved to trash: \(track.title)")
                    }
                }
                
                // Reload tracks to reflect changes
                try await collectionService.loadAllTracks()
                
                // Clear selection and tracks to delete
                await MainActor.run {
                    selectedDisplayItems.removeAll()
                    tracksToDelete.removeAll()
                }
                
                print("✅ Successfully deleted \(tracksToDeleteCount) tracks")
                
            } catch {
                print("❌ Failed to delete tracks: \(error)")
                await MainActor.run {
                    ratingErrorMessage = "Failed to delete tracks: \(error.localizedDescription)"
                    showingRatingError = true
                }
            }
        }
    }
    
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
    
    // MARK: - Context Menus
    
    @ViewBuilder
    private func trackContextMenu() -> some View {
        // Track actions only
        if !selectedDisplayItems.isEmpty {
            Button("Play") {
                if let selectedTrack = selectedDisplayItems.first,
                   let displayItem = displayItems.first(where: { $0.id == selectedTrack }) {
                    let track = displayItem.track
                    print("Context menu play track: \(track.title)")
                    print("Track path: \(track.path)")
                    print("Is URL: \(track.isUrl)")
                    print("Duration: \(track.duration) ms")
                    Task {
                        _ = await audioService.loadTrack(track)
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
            
            Divider()
            
            // Track grouping options
            trackGroupingContextMenu()
            
            Divider()
            
            Button("Move to Trash", role: .destructive) {
                let selectedTracksList = displayItems.filter { selectedDisplayItems.contains($0.id) }.map { $0.track }
                if !selectedTracksList.isEmpty {
                    tracksToDelete = selectedTracksList
                    showDeleteConfirmation = true
                }
            }
            
            // Only show "Refresh Data" for local files
            if let selectedTrack = selectedDisplayItems.first,
               let displayItem = displayItems.first(where: { $0.id == selectedTrack }),
               !displayItem.track.isUrl {
                let track = displayItem.track
                Button("Refresh Data…") {
                    refreshTrackData(track: track)
                }
            }
            
            // Only show "Reveal in Finder" for local files
            if let selectedTrack = selectedDisplayItems.first,
               let displayItem = displayItems.first(where: { $0.id == selectedTrack }),
               !displayItem.track.isUrl {
                let track = displayItem.track
                Button("Reveal in Finder") {
                    revealInFinder(track: track)
                }
            }
        }
    }
    
    @ViewBuilder
    private func trackGroupingContextMenu() -> some View {
        let selectedItems = displayItems.filter { selectedDisplayItems.contains($0.id) }
        
        // Analyze selection to determine available options
        let individualTracks = selectedItems.filter { $0.isIndividual }
        let containerTracks = selectedItems.filter { $0.isContainer }
        let groupMembers = selectedItems.filter { $0.isMember }
        
        // "Group Tracks" - show when multiple individual tracks are selected
        if individualTracks.count >= 2 && containerTracks.isEmpty && groupMembers.isEmpty {
            Button("Group Tracks") {
                Task {
                    await createGroupFromSelection(selectedItems)
                }
            }
        }
        
        // "Ungroup Tracks" - show when a single container track is selected
        if selectedItems.count == 1, let containerItem = selectedItems.first, containerItem.isContainer {
            Button("Ungroup Tracks") {
                ungroupTracks(containerItem)
            }
        }
        
        // "Set as Main Track" - show when a single group member is selected
        if selectedItems.count == 1, let memberItem = selectedItems.first, memberItem.isMember {
            Button("Set as Main Track") {
                setAsMainTrack(memberItem)
            }
        }
        
        // "Add to Group" - show when selection includes individual tracks and one container
        if individualTracks.count >= 1 && containerTracks.count == 1 && groupMembers.isEmpty {
            Button("Add to Group") {
                addTracksToExistingGroup(individualTracks: individualTracks, containerTrack: containerTracks.first!)
            }
        }
        
        // "Remove from Group" - show when a single group member is selected (but not main track)
        if selectedItems.count == 1, let memberItem = selectedItems.first, memberItem.isMember {
            if let groupId = memberItem.groupId,
               let group = trackGroupService.groups.first(where: { $0.id == groupId }),
               memberItem.track.id != group.mainTrackId {
                Button("Remove from Group") {
                    removeTrackFromGroup(memberItem)
                }
            }
        }
    }
    
    @ViewBuilder
    private func columnContextMenu() -> some View {
        // Column visibility only
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
        print("🔧 [TrackListView] Loading preferences...")
        guard !hasLoadedPreferences else { 
            print("🔧 [TrackListView] Preferences already loaded, skipping")
            return 
        }
        hasLoadedPreferences = true
        
        // Visible columns
        if let stored = UserDefaults.standard.stringArray(forKey: visibleColumnsDefaultsKey) {
            let set = Set(stored.compactMap { TrackColumn(rawValue: $0) })
            if !set.isEmpty {
                visibleColumns = set
                print("🔧 [TrackListView] Loaded visible columns: \(set.map { $0.displayName })")
            } else {
                print("🔧 [TrackListView] No valid visible columns found in stored data: \(stored)")
            }
        } else {
            print("🔧 [TrackListView] No stored visible columns found, using defaults")
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
            print("🔧 [TrackListView] Loaded column widths: \(result.map { "\($0.key.displayName): \($0.value)" })")
        } else {
            print("🔧 [TrackListView] No stored column widths found")
        }
        
        print("🔧 [TrackListView] Preferences loading completed")
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


}

// MARK: - Table Width Observer
private struct TableWidthObserver: NSViewRepresentable {
    @Binding var columnWidths: [TrackColumn: CGFloat]
    let onWidthChange: () -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        
        // Set up the observer with multiple attempts to find the table view
        DispatchQueue.main.async {
            self.setupObserverWithRetries(context: context, view: view)
        }
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // Also try to set up observer here as a fallback
        if let tableView = findTableView(in: nsView) {
            context.coordinator.setupObserver(for: tableView)
        }
    }
    
    private func setupObserverWithRetries(context: Context, view: NSView, attempt: Int = 0) {
        print("🔍 [TrackListView] Attempting to find NSTableView (attempt \(attempt + 1))")
        
        // Try to find the table view in the entire window hierarchy
        if let window = view.window,
           let contentView = window.contentView,
           let tableView = findTableView(in: contentView) {
            print("🔍 [TrackListView] Found NSTableView in window content view")
            context.coordinator.setupObserver(for: tableView)
            return
        }
        
        // If not found and we haven't exceeded max attempts, try again
        if attempt < 10 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.setupObserverWithRetries(context: context, view: view, attempt: attempt + 1)
            }
        } else {
            print("❌ [TrackListView] Failed to find NSTableView after 10 attempts")
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
            print("🔍 [TrackListView] Setting up column width observer for NSTableView")
            self.tableView = tableView
            
            // Start a timer to periodically check column widths - reduced frequency for better performance
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.checkColumnWidths()
            }
        }
        
        private func checkColumnWidths() {
            guard let tableView = tableView else { return }
            
            var updated = false
            
            for column in tableView.tableColumns {
                let title = column.title
                let width = column.width
                
                // Map column title to TrackColumn
                let trackColumn: TrackColumn? = {
                    switch title {
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
                        print("📏 [TrackListView] Column width changed: \(trackColumn.displayName) from \(currentWidth) to \(width)")
                        columnWidths[trackColumn] = width
                        updated = true
                    }
                } else {
                    print("🔍 [TrackListView] Unknown column title: '\(title)' (identifier: \(column.identifier.rawValue))")
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


#Preview {
    let collectionService = CollectionService()
    TrackListView(
        collectionService: collectionService,
        audioService: AudioService(),
        searchService: SearchService()
    )
}


// MARK: - Table Selection Handler
struct TableSelectionHandler: NSViewRepresentable {
    @Binding var selectedDisplayItems: Set<TrackDisplayItem.ID>
    let displayItems: [TrackDisplayItem]
    
    func makeNSView(context: Context) -> NSView {
        let view = TableSelectionView(selectedDisplayItems: _selectedDisplayItems)
        view.displayItems = displayItems
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? TableSelectionView {
            view.displayItems = displayItems
        }
    }
}

class TableSelectionView: NSView {
    var selectedDisplayItems: Binding<Set<TrackDisplayItem.ID>>
    var displayItems: [TrackDisplayItem] = []
    
    init(selectedDisplayItems: Binding<Set<TrackDisplayItem.ID>>) {
        self.selectedDisplayItems = selectedDisplayItems
        super.init(frame: .zero)
        self.wantsLayer = true
    }
    
    private var monitor: Any?
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        
        if window != nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                return self?.handleMouseDown(event) ?? event
            }
        }
    }
    
    deinit {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    private func handleMouseDown(_ event: NSEvent) -> NSEvent? {
        guard let window = self.window, window == event.window else { return event }
        
        // Check if we are in an editing state (text field/view is first responder)
        // This handles the case where user is editing a tag and clicks another row
        let firstResponder = window.firstResponder
        let isEditing = firstResponder is NSTextView || firstResponder is NSTextField
        
        if isEditing {
            if let tableView = findTableView(in: window.contentView) {
                // Convert point to table view coordinates
                let locationInTable = tableView.convert(event.locationInWindow, from: nil)
                
                // Check if the click is within the table view
                if tableView.bounds.contains(locationInTable) {
                    // Get the row at the clicked location
                    let row = tableView.row(at: locationInTable)
                    
                    if row >= 0 && row < displayItems.count {
                        // If we clicked a row while editing, we want to:
                        // 1. Make table first responder (ends editing)
                        // 2. Select the row immediately
                        
                        window.makeFirstResponder(tableView)
                        
                        // Only handle simple clicks (no modifiers) manually to ensure immediate selection
                        // Let the table handle complex selections (shift/cmd click) naturally
                        let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                        if modifierFlags.isEmpty {
                            let displayItem = displayItems[row]
                            
                            // Update SwiftUI binding
                            DispatchQueue.main.async {
                                self.selectedDisplayItems.wrappedValue = [displayItem.id]
                            }
                            
                            // Update visual selection
                            let indexSet = IndexSet(integer: row)
                            tableView.selectRowIndexes(indexSet, byExtendingSelection: false)
                            
                            // Consume the event since we handled it
                            return nil
                        }
                    }
                }
            }
        }
        
        return event
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        return super.hitTest(point)
    }
    
    override func rightMouseDown(with event: NSEvent) {
        // Find the NSTableView in the view hierarchy
        if let tableView = findTableView(in: self.window?.contentView) {
            // Convert the event location to the table view's coordinate space
            let locationInTableView = tableView.convert(event.locationInWindow, from: nil)
            let row = tableView.row(at: locationInTableView)
            
            if row >= 0 && row < displayItems.count {
                let displayItem = displayItems[row]
                let displayItemId = displayItem.id
                
                // If the clicked row is already part of the selection, preserve the selection
                // and just show the context menu for the current selection
                if selectedDisplayItems.wrappedValue.contains(displayItemId) {
                    self.nextResponder?.rightMouseDown(with: event)
                    return
                }
                
                // Select the clicked row immediately and synchronously
                selectedDisplayItems.wrappedValue = [displayItemId]
                
                // Update the table view selection
                let indexSet = IndexSet(integer: row)
                tableView.selectRowIndexes(indexSet, byExtendingSelection: false)
                
                // Use a small delay to ensure the selection is processed before showing context menu
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    // Forward the event to the next responder to show context menu
                    self.nextResponder?.rightMouseDown(with: event)
                }
                return
            }
        }
        
        // If no valid row was found, forward immediately
        self.nextResponder?.rightMouseDown(with: event)
    }
    
    private func findTableView(in view: NSView?) -> NSTableView? {
        guard let view = view else { return nil }
        
        // Look for the actual SwiftUI Table's NSTableView, not the List's
        if let tableView = view as? NSTableView {
            let className = String(describing: type(of: tableView))
            
            // Skip ListCoreOutlineView (SwiftUI List) and look for Table's NSTableView
            if className.contains("ListCore") {
                // Continue searching for the actual Table
            } else {
                return tableView
            }
        }
        
        for subview in view.subviews {
            if let tableView = findTableView(in: subview) {
                return tableView
            }
        }
        return nil
    }
}

// macOS 13-compatible keyboard event handler
struct KeyboardEventHandler: NSViewRepresentable {
    let isTextFieldFocused: Bool
    let isTableFocused: Bool
    let hasSelection: Bool
    let onCommandA: () -> Void
    let onSpace: () -> Void
    let onBackspace: () -> Void
    let onCommandL: () -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = KeyEventView()
        view.coordinator = context.coordinator
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let keyView = nsView as? KeyEventView {
            keyView.coordinator = context.coordinator
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(
            isTextFieldFocused: isTextFieldFocused,
            isTableFocused: isTableFocused,
            hasSelection: hasSelection,
            onCommandA: onCommandA,
            onSpace: onSpace,
            onBackspace: onBackspace,
            onCommandL: onCommandL
        )
    }
    
    class KeyEventView: NSView {
        var coordinator: Coordinator?
        
        override var acceptsFirstResponder: Bool { true }
        
        override func keyDown(with event: NSEvent) {
            guard let coordinator = coordinator else {
                super.keyDown(with: event)
                return
            }
            
            let modifiers = event.modifierFlags
            let key = event.charactersIgnoringModifiers ?? ""
            
            if modifiers.contains(.command) && key == "a" {
                coordinator.onCommandA()
            } else if key == " " && !coordinator.isTextFieldFocused && coordinator.isTableFocused {
                coordinator.onSpace()
            } else if event.keyCode == 51 && !coordinator.isTextFieldFocused && coordinator.isTableFocused && coordinator.hasSelection {
                // 51 is backspace/delete
                coordinator.onBackspace()
            } else if modifiers.contains(.command) && key == "l" {
                coordinator.onCommandL()
            } else {
                super.keyDown(with: event)
            }
        }
    }
    
    class Coordinator {
        let isTextFieldFocused: Bool
        let isTableFocused: Bool
        let hasSelection: Bool
        let onCommandA: () -> Void
        let onSpace: () -> Void
        let onBackspace: () -> Void
        let onCommandL: () -> Void
        
        init(isTextFieldFocused: Bool, isTableFocused: Bool, hasSelection: Bool, onCommandA: @escaping () -> Void, onSpace: @escaping () -> Void, onBackspace: @escaping () -> Void, onCommandL: @escaping () -> Void) {
            self.isTextFieldFocused = isTextFieldFocused
            self.isTableFocused = isTableFocused
            self.hasSelection = hasSelection
            self.onCommandA = onCommandA
            self.onSpace = onSpace
            self.onBackspace = onBackspace
            self.onCommandL = onCommandL
        }
    }
}

// MARK: - Editable Track Cell
private struct EditableTrackCell: View {
    let text: String
    let track: Track
    let property: String
    let isSelected: Bool
    var fontWeight: Font.Weight? = nil // Add optional font weight
    @ObservedObject var metadataManager: TrackMetadataManager
    
    @State private var isEditing = false
    @State private var editedText: String?
    @FocusState private var isFocused: Bool
    
    @State private var clickCount = 0
    @State private var workItem: DispatchWorkItem?
    @State private var lastSelectionTime: Date = .distantPast
    
    var body: some View {
        ZStack(alignment: .leading) {
            if isEditing {
                TextField("", text: Binding(
                    get: { editedText ?? text },
                    set: { editedText = $0 }
                ))
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit {
                        commitEdit()
                    }
                    .onChange(of: isFocused) { focused in
                        if !focused {
                            commitEdit()
                        }
                    }
                    .onAppear {
                        // Only set if nil to preserve ongoing edits if any (though isEditing controls visibility)
                        if editedText == nil {
                            editedText = text
                        }
                        isFocused = true
                    }
            } else {
                Text(editedText ?? text)
                    .fontWeight(fontWeight) // Apply font weight here on the Text view
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .gesture(isSelected ? TapGesture().onEnded {
                        handleClick()
                    } : nil)
            }
        }
        .onChange(of: isSelected) { selected in
            if selected {
                lastSelectionTime = Date()
            } else {
                workItem?.cancel()
                clickCount = 0
                if isEditing {
                    commitEdit()
                }
            }
        }
        // Ensure we stay in sync with parent updates
        .onChange(of: text) { newText in
            editedText = newText
        }
        .onAppear {
            if isSelected {
                lastSelectionTime = Date()
            }
            // Sync initial state if needed
            if editedText == nil {
                editedText = text
            }
        }
    }
    
    private func handleClick() {
        if !isSelected { return }
        
        let now = Date()
        if now.timeIntervalSince(lastSelectionTime) < 0.5 {
            return
        }
        
        clickCount += 1
        
        if clickCount == 1 {
            let task = DispatchWorkItem {
                if clickCount == 1 {
                    startEditing()
                }
                clickCount = 0
            }
            workItem = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
        } else {
            workItem?.cancel()
            clickCount = 0
        }
    }
    
    private func startEditing() {
        editedText = text
        isEditing = true
    }
    
    private func commitEdit() {
        guard isEditing else { return }
        isEditing = false
        
        let currentVal = editedText ?? text
        if currentVal != text {
            Task { @MainActor in
                // Using optional try since we're in a UI callback
                try? await metadataManager.updateTrackMetadata(trackId: track.id!, updates: [property: currentVal])
            }
        }
    }
}
