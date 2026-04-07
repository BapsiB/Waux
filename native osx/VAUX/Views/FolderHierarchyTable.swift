import SwiftUI
import UniformTypeIdentifiers
import AppKit

private let folderHierarchyIndentPerDepth: CGFloat = 16
private let folderHierarchyWaveformMinInner: CGFloat = 48
/// Second click on the same folder row within this window toggles expand/collapse (after first click selected the row).
private let folderOpenSecondTapInterval: TimeInterval = 0.35

struct FolderHierarchyTable: View {
    let rows: [FolderHierarchyTableRow]
    @Binding var selectedRowIds: Set<String>
    /// Tracks last single tap on a folder row for select-then-open-within-interval.
    @State private var folderSequentialTap: (rowId: String, at: Date)?
    @Binding var sortOrder: [KeyPathComparator<FolderHierarchyTableRow>]
    @Binding var visibleColumns: Set<TrackColumn>
    @Binding var columnWidths: [TrackColumn: CGFloat]
    @Binding var isTextFieldFocused: Bool
    @FocusState var isTableFocused: Bool
    @ObservedObject var audioService: AudioService
    @ObservedObject var metadataManager: TrackMetadataManager
    @ObservedObject var waveformServiceHolder: WaveformServiceHolder
    @ObservedObject var collectionService: CollectionService
    @ObservedObject var folderManager: FolderHierarchyManager
    let onDoubleClickTrack: (Track) -> Void
    let onColumnWidthChange: () -> Void
    let onKeyPressA: () -> Void
    let onKeyPressSpace: () -> Void
    let onKeyPressBackspace: () -> Void
    let onGoToCurrentTrack: () -> Void

    var body: some View {
        Table(rows, selection: $selectedRowIds, sortOrder: $sortOrder) {
            TableColumn("⚙︎") { (row: FolderHierarchyTableRow) in
                dragHandle(for: row)
            }
            .width(24)

            TableColumn("Waveform", value: \.waveformPointCount) { row in
                waveformCell(for: row)
            }
            .width(min: 120, ideal: columnWidths[.waveformData] ?? 160, max: 200)

            TableColumn("Title", value: \.titleSort) { row in
                titleCell(for: row)
            }
            .width(min: 150, ideal: columnWidths[.title] ?? 250)

            TableColumn("Artist", value: \.artistSort) { row in
                artistCell(for: row)
            }
            .width(min: 100, ideal: columnWidths[.artist] ?? 150)

            TableColumn("Album", value: \.albumSort) { row in
                albumCell(for: row)
            }
            .width(min: 100, ideal: columnWidths[.album] ?? 120)

            TableColumn("Duration", value: \.formattedDurationSort) { row in
                durationCell(for: row)
            }
            .width(min: 5, ideal: 10, max: 80)

            TableColumn("Rating", value: \.ratingSort) { row in
                ratingCell(for: row)
            }
            .width(min: 60, ideal: columnWidths[.rating] ?? 70, max: 100)

            TableColumn("Date Added", value: \.dateAddedSortValue) { row in
                dateAddedCell(for: row)
            }
            .width(min: 120, ideal: columnWidths[.dateAdded] ?? 140)

            TableColumn("Composer", value: \.composerSort) { row in
                composerCell(for: row)
            }
            .width(min: 100, ideal: columnWidths[.composer] ?? 150)

            TableColumn("Tags", value: \.generalTagsCount) { row in
                tagsCell(for: row)
            }
            .width(min: 120, ideal: columnWidths[.generalTags] ?? 200, max: 600)
        }
        .tableStyle(.bordered)
        .focusable()
        .focused($isTableFocused)
        .background(TableWidthObserver(columnWidths: $columnWidths, onWidthChange: onColumnWidthChange))
        .background(KeyboardEventHandler(
            isTextFieldFocused: isTextFieldFocused,
            isTableFocused: isTableFocused,
            hasSelection: !selectedRowIds.isEmpty,
            onCommandA: onKeyPressA,
            onSpace: onKeyPressSpace,
            onBackspace: onKeyPressBackspace,
            onCommandL: onGoToCurrentTrack
        ))
        .onDeleteCommand {
            if !isTextFieldFocused && isTableFocused && !selectedRowIds.isEmpty {
                onKeyPressBackspace()
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTableFocused = true
            }
        }
    }

    /// Chevron only: toggle expand/collapse when the folder has children; selection matches `handleFolderRowTap` (⌘ / ⇧).
    private func handleFolderDisclosureTap(row: FolderHierarchyTableRow, folder: FolderNode) {
        let rowId = row.id
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if flags.contains(.command) {
            if selectedRowIds.contains(rowId) {
                selectedRowIds.remove(rowId)
            } else {
                selectedRowIds.insert(rowId)
            }
            folderSequentialTap = nil
            if folder.hasChildren {
                folderManager.toggleExpansion(for: folder.path)
            }
            return
        }

        if flags.contains(.shift) {
            selectedRowIds = [rowId]
            folderSequentialTap = nil
            if folder.hasChildren {
                folderManager.toggleExpansion(for: folder.path)
            }
            return
        }

        selectedRowIds = [rowId]
        folderSequentialTap = nil
        if folder.hasChildren {
            folderManager.toggleExpansion(for: folder.path)
        }
    }

    /// Single click anywhere on a folder row: select (respecting ⌘ for multi-select). A second click on the same row within `folderOpenSecondTapInterval` toggles expansion.
    private func handleFolderRowTap(row: FolderHierarchyTableRow, folder: FolderNode) {
        let rowId = row.id
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if flags.contains(.command) {
            if selectedRowIds.contains(rowId) {
                selectedRowIds.remove(rowId)
            } else {
                selectedRowIds.insert(rowId)
            }
            folderSequentialTap = nil
            return
        }

        if flags.contains(.shift) {
            selectedRowIds = [rowId]
            folderSequentialTap = nil
            return
        }

        let now = Date()
        if let prev = folderSequentialTap,
           prev.rowId == rowId,
           now.timeIntervalSince(prev.at) < folderOpenSecondTapInterval {
            if folder.hasChildren {
                folderManager.toggleExpansion(for: folder.path)
            }
            folderSequentialTap = nil
            return
        }

        selectedRowIds = [rowId]
        folderSequentialTap = (rowId, now)
    }

    // MARK: - Cells

    @ViewBuilder
    private func waveformCell(for row: FolderHierarchyTableRow) -> some View {
        let baseW = columnWidths[.waveformData] ?? 160
        let innerCap = max(folderHierarchyWaveformMinInner, baseW - CGFloat(row.depth) * folderHierarchyIndentPerDepth)

        switch row.kind {
        case .folder(let folder):
            HStack(spacing: 6) {
                Color.clear
                    .frame(width: CGFloat(row.depth) * folderHierarchyIndentPerDepth)
                    .contentShape(Rectangle())
                    .onTapGesture { handleFolderRowTap(row: row, folder: folder) }

                if folder.hasChildren {
                    Image(systemName: folderManager.isExpanded(folder.path) ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                        .help("Show or hide folder contents")
                        .onTapGesture { handleFolderDisclosureTap(row: row, folder: folder) }
                } else {
                    Color.clear
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                        .onTapGesture { handleFolderRowTap(row: row, folder: folder) }
                }

                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .foregroundColor(AppStyle.mainColor)
                        .font(.system(size: 14))
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .help(folder.displayName)
                .onTapGesture { handleFolderRowTap(row: row, folder: folder) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .track(let track):
            HStack(spacing: 4) {
                Color.clear.frame(width: CGFloat(row.depth) * folderHierarchyIndentPerDepth)
                let p = WaveformColumn.playbackParameters(track: track, audioService: audioService)
                WaveformColumn(
                    track: track,
                    playbackProgress: p.progress,
                    isPlayingThisTrack: p.isPlayingThisTrack,
                    highDetailWaveform: p.highDetailWaveform,
                    audioService: audioService,
                    waveformServiceHolder: waveformServiceHolder,
                    collectionService: collectionService
                )
                .id("waveform-\(track.id ?? -1)-\(track.waveformPointCount)")
                .frame(maxWidth: innerCap)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func titleCell(for row: FolderHierarchyTableRow) -> some View {
        switch row.kind {
        case .folder(let folder):
            HStack(spacing: 6) {
                Text(folder.displayName)
                    .font(.system(size: 13))
                    .fontWeight(.medium)
                    .lineLimit(1)
                if !folder.tracks.isEmpty {
                    Text("(\(folder.tracks.count))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 2)
            .background(rowBackground(for: row))
            .contentShape(Rectangle())
            .onTapGesture { handleFolderRowTap(row: row, folder: folder) }

        case .track(let track):
            if let tid = track.id {
                EditableTrackCell(
                    text: track.title,
                    track: track,
                    property: "title",
                    isSelected: selectedRowIds.contains(row.id),
                    metadataManager: metadataManager,
                    onDoubleClick: onDoubleClickTrack
                )
                .padding(.vertical, 2)
                .background(rowBackground(for: row))
            }
        }
    }

    @ViewBuilder
    private func artistCell(for row: FolderHierarchyTableRow) -> some View {
        switch row.kind {
        case .folder(let folder):
            Text("—")
                .foregroundColor(.secondary)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { handleFolderRowTap(row: row, folder: folder) }
        case .track(let track):
            EditableTrackCell(
                text: track.artist,
                track: track,
                property: "artist",
                isSelected: selectedRowIds.contains(row.id),
                metadataManager: metadataManager,
                onDoubleClick: onDoubleClickTrack
            )
            .padding(.vertical, 2)
            .background(rowBackground(for: row))
        }
    }

    @ViewBuilder
    private func albumCell(for row: FolderHierarchyTableRow) -> some View {
        switch row.kind {
        case .folder(let folder):
            Text("—")
                .foregroundColor(.secondary)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { handleFolderRowTap(row: row, folder: folder) }
        case .track(let track):
            EditableTrackCell(
                text: track.album,
                track: track,
                property: "album",
                isSelected: selectedRowIds.contains(row.id),
                metadataManager: metadataManager,
                onDoubleClick: onDoubleClickTrack
            )
            .padding(.vertical, 2)
            .background(rowBackground(for: row))
        }
    }

    @ViewBuilder
    private func durationCell(for row: FolderHierarchyTableRow) -> some View {
        switch row.kind {
        case .folder(let folder):
            Text("")
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { handleFolderRowTap(row: row, folder: folder) }
        case .track(let track):
            Text(track.formattedDuration)
                .padding(.vertical, 2)
                .background(rowBackground(for: row))
        }
    }

    @ViewBuilder
    private func ratingCell(for row: FolderHierarchyTableRow) -> some View {
        switch row.kind {
        case .folder(let folder):
            Text("—")
                .foregroundColor(.secondary)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { handleFolderRowTap(row: row, folder: folder) }
        case .track(let track):
            if let trackId = track.id {
                InteractiveStarRating_New(
                    trackId: trackId,
                    metadataManager: metadataManager
                )
                .padding(.vertical, 2)
                .background(rowBackground(for: row))
            }
        }
    }

    @ViewBuilder
    private func dateAddedCell(for row: FolderHierarchyTableRow) -> some View {
        switch row.kind {
        case .folder(let folder):
            Text("—")
                .foregroundColor(.secondary)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { handleFolderRowTap(row: row, folder: folder) }
        case .track(let track):
            Text(track.formattedDateAdded)
                .padding(.vertical, 2)
                .background(rowBackground(for: row))
        }
    }

    @ViewBuilder
    private func composerCell(for row: FolderHierarchyTableRow) -> some View {
        switch row.kind {
        case .folder(let folder):
            Text("—")
                .foregroundColor(.secondary)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { handleFolderRowTap(row: row, folder: folder) }
        case .track(let track):
            EditableTrackCell(
                text: track.composerText,
                track: track,
                property: "composer",
                isSelected: selectedRowIds.contains(row.id),
                metadataManager: metadataManager,
                onDoubleClick: onDoubleClickTrack
            )
            .padding(.vertical, 2)
            .background(rowBackground(for: row))
        }
    }

    @ViewBuilder
    private func tagsCell(for row: FolderHierarchyTableRow) -> some View {
        switch row.kind {
        case .folder(let folder):
            Text("—")
                .foregroundColor(.secondary)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { handleFolderRowTap(row: row, folder: folder) }
        case .track(let track):
            if let trackId = track.id {
                InteractiveTagsView_New(
                    trackId: trackId,
                    metadataManager: metadataManager,
                    isTextFieldFocused: $isTextFieldFocused
                )
                .padding(.vertical, 2)
                .background(rowBackground(for: row))
            }
        }
    }

    private func rowBackground(for row: FolderHierarchyTableRow) -> Color {
        guard selectedRowIds.contains(row.id) else { return Color.clear }
        return AppStyle.secondaryColor.opacity(0.1)
    }

    // MARK: - Drag handle

    @ViewBuilder
    private func dragHandle(for row: FolderHierarchyTableRow) -> some View {
        switch row.kind {
        case .folder(let folder):
            Image(systemName: "folder")
                .foregroundColor(.secondary)
                .font(.caption)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
                .help(folder.displayName)
                .onDrag {
                    let paths = folder.allTracks.map { $0.path }
                    let payload = paths.joined(separator: "\n")
                    return NSItemProvider(object: payload as NSString)
                }
                .simultaneousGesture(
                    TapGesture().onEnded {
                        handleFolderRowTap(row: row, folder: folder)
                    }
                )
        case .track(let track):
            if #available(macOS 13.0, *) {
                Image(systemName: "line.3.horizontal")
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
                    .help(track.displayTitle)
                    .onDrag({
                        TrackDragItemProvider.make(for: tracksForDrag(from: track))
                    }, preview: {
                        dragPreview(for: track)
                    })
                    .onHover { hovering in
                        if hovering {
                            Task { @MainActor in
                                DragStateManager.shared.beginTrackDrag()
                            }
                        }
                    }
                    .contextMenu {
                        columnVisibilityMenu()
                    }
            } else {
                Image(systemName: "line.3.horizontal")
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
                    .help(track.displayTitle)
                    .onDrag {
                        TrackDragItemProvider.make(for: tracksForDrag(from: track))
                    }
                    .contextMenu {
                        columnVisibilityMenu()
                    }
            }
        }
    }

    @ViewBuilder
    private func columnVisibilityMenu() -> some View {
        ForEach(TrackColumn.allCases, id: \.self) { column in
            Button {
                if visibleColumns.contains(column) {
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

    private func tracksForDrag(from track: Track) -> [Track] {
        let selectedTrackRows = rows.filter { row in
            guard case .track = row.kind else { return false }
            return selectedRowIds.contains(row.id)
        }
        let selectedIds = Set(selectedTrackRows.compactMap { $0.track?.id })
        if let tid = track.id, selectedIds.contains(tid), !selectedIds.isEmpty {
            return rows.compactMap { r in
                guard case .track(let t) = r.kind else { return nil }
                guard let id = t.id, selectedIds.contains(id) else { return nil }
                return t
            }
        }
        return [track]
    }

    @available(macOS 13.0, *)
    @ViewBuilder
    private func dragPreview(for track: Track) -> some View {
        let tracks = tracksForDrag(from: track)
        HStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.title2)
                .foregroundColor(.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(tracks.count > 1 ? "\(tracks.count) tracks" : track.displayTitle)
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
        .padding(8)
        .background(.regularMaterial)
        .cornerRadius(8)
        .shadow(radius: 2)
        .frame(minWidth: 160, minHeight: 60)
    }
}
