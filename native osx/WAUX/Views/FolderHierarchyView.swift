import SwiftUI
import UniformTypeIdentifiers

struct FolderHierarchyView: View {
    @ObservedObject var collectionService: CollectionService
    @ObservedObject var audioService: AudioService
    @ObservedObject var folderManager: FolderHierarchyManager
    @ObservedObject var searchService: SearchService
    @StateObject private var waveformServiceHolder = WaveformServiceHolder()
    @StateObject private var metadataManager: TrackMetadataManager
    @State private var selectedTracks = Set<Track.ID>()
    @State private var lastSelectedTrackId: Track.ID? = nil
    @State private var showTagEditor = false
    @State private var showMetadataEditor = false
    @FocusState private var isTextFieldFocused: Bool
    
    init(collectionService: CollectionService, audioService: AudioService, folderManager: FolderHierarchyManager, searchService: SearchService) {
        self.collectionService = collectionService
        self.audioService = audioService
        self.folderManager = folderManager
        self.searchService = searchService
        self._metadataManager = StateObject(wrappedValue: TrackMetadataManager(collectionService: collectionService))
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(folderManager.rootFolders) { folder in
                                            FolderNodeView(
                            folder: folder,
                            folderManager: folderManager,
                            audioService: audioService,
                            metadataManager: metadataManager,
                            waveformServiceHolder: waveformServiceHolder,
                            collectionService: collectionService,
                            selectedTracks: $selectedTracks,
                            lastSelectedTrackId: $lastSelectedTrackId,
                            searchService: searchService,
                            isTextFieldFocused: Binding(
                                get: { isTextFieldFocused },
                                set: { isTextFieldFocused = $0 }
                            ),
                            onDoubleClick: { track in
                                Task {
                                    await audioService.loadTrack(track)
                                    audioService.play()
                                }
                            }
                        )
                }
            }
            .padding(.horizontal, 8)
        }
        .onAppear {
            // Build hierarchy when view appears
            let rootPath = collectionService.getRootFolders().first
            folderManager.buildHierarchy(from: collectionService.tracks, rootPath: rootPath)
        }
        .onChange(of: collectionService.tracks) { _, _ in
            // Rebuild hierarchy when tracks change
            let rootPath = collectionService.getRootFolders().first
            folderManager.buildHierarchy(from: collectionService.tracks, rootPath: rootPath)
        }
        .sheet(isPresented: $showTagEditor) {
            let selectedTrackIds = selectedTracks.compactMap { $0 }
            TagEditorView_New(
                metadataManager: metadataManager,
                collectionService: collectionService,
                trackIds: selectedTrackIds
            )
        }
        .sheet(isPresented: $showMetadataEditor) {
            let selectedTrackIds = selectedTracks.compactMap { $0 }
            MetadataEditorView(
                metadataManager: metadataManager,
                collectionService: collectionService,
                trackIds: selectedTrackIds
            )
        }
        .contextMenu {
            if !selectedTracks.isEmpty {
                Button("Play") {
                    if let selectedTrack = selectedTracks.first,
                       let track = collectionService.tracks.first(where: { $0.id == selectedTrack }) {
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
                Divider()
                Button("Reveal in Finder") {
                    revealSelectedTracksInFinder()
                }
                Divider()
            }
            
            if !folderManager.selectedFolders.isEmpty {
                Button("Add Selected Folders to Playlist") {
                    // TODO: Implement add to playlist functionality
                }
                Button("Reveal in Finder") {
                    revealSelectedFoldersInFinder()
                }
                Divider()
            }
        }
    }
    
    // MARK: - Reveal in Finder Functions
    
    private func revealSelectedTracksInFinder() {
        let selectedTracksList = selectedTracks.compactMap { trackId in
            collectionService.tracks.first { $0.id == trackId }
        }
        
        guard !selectedTracksList.isEmpty else { return }
        
        // Get unique parent directories
        let parentDirectories = Set(selectedTracksList.map { track in
            URL(fileURLWithPath: track.path).deletingLastPathComponent().path
        })
        
        // Reveal each parent directory in Finder
        for directory in parentDirectories {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: directory)
        }
    }
    
    private func revealSelectedFoldersInFinder() {
        let selectedFolderPaths = folderManager.selectedFolders
        
        guard !selectedFolderPaths.isEmpty else { return }
        
        // Reveal each selected folder in Finder
        for folderPath in selectedFolderPaths {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderPath)
        }
    }
}

struct FolderNodeView: View {
    let folder: FolderNode
    @ObservedObject var folderManager: FolderHierarchyManager
    @ObservedObject var audioService: AudioService
    @ObservedObject var metadataManager: TrackMetadataManager
    @ObservedObject var waveformServiceHolder: WaveformServiceHolder
    @ObservedObject var collectionService: CollectionService
    @Binding var selectedTracks: Set<Track.ID>
    @Binding var lastSelectedTrackId: Track.ID?
    @ObservedObject var searchService: SearchService
    @Binding var isTextFieldFocused: Bool
    let onDoubleClick: (Track) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Folder header
            FolderHeaderView(
                folder: folder,
                folderManager: folderManager,
                isExpanded: folderManager.isExpanded(folder.path),
                isSelected: folderManager.isSelected(folder.path)
            )
            
            // Child folders and tracks when expanded
            if folderManager.isExpanded(folder.path) {
                VStack(alignment: .leading, spacing: 0) {
                    // Render child folders first
                    ForEach(folder.children) { childFolder in
                        FolderNodeView(
                            folder: childFolder,
                            folderManager: folderManager,
                            audioService: audioService,
                            metadataManager: metadataManager,
                            waveformServiceHolder: waveformServiceHolder,
                            collectionService: collectionService,
                            selectedTracks: $selectedTracks,
                            lastSelectedTrackId: $lastSelectedTrackId,
                            searchService: searchService,
                            isTextFieldFocused: $isTextFieldFocused,
                            onDoubleClick: onDoubleClick
                        )
                    }
                    
                    // Then render tracks in this folder
                    ForEach(folder.tracks) { track in
                        if searchService.searchText.isEmpty || trackMatchesSearch(track) {
                            FolderTrackRowView(
                                track: track,
                                audioService: audioService,
                                metadataManager: metadataManager,
                                waveformServiceHolder: waveformServiceHolder,
                                collectionService: collectionService,
                                selectedTracks: $selectedTracks,
                                lastSelectedTrackId: $lastSelectedTrackId,
                                isTextFieldFocused: $isTextFieldFocused,
                                onDoubleClick: onDoubleClick,
                                allTracks: folder.tracks
                            )
                            .padding(.leading, CGFloat((folder.level + 1) * 20)) // Indent tracks one level deeper than their parent folder
                        }
                    }
                }
            }
        }
    }
    
    private func trackMatchesSearch(_ track: Track) -> Bool {
        return searchService.trackMatchesSearch(track)
    }
}

struct FolderHeaderView: View {
    let folder: FolderNode
    @ObservedObject var folderManager: FolderHierarchyManager
    let isExpanded: Bool
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            // Expand/collapse button with larger clickable area
            if folder.hasChildren {
                Button(action: {
                    folderManager.toggleExpansion(for: folder.path)
                }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 16, height: 16)
                        .padding(.horizontal, 12) // Add 12px horizontal padding for wider clickable area
                        .padding(.vertical, 2) // Add 2px vertical padding for minimal height increase
                        // .background(Color.red.opacity(0.3)) // Debug color to show clickable area
                        .contentShape(Rectangle()) // Ensure the entire padded area is clickable
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                // Spacer for alignment when no children
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 36, height: 36) // Match the size of the button with padding
            }
            
            // Folder icon
            Image(systemName: "folder")
                .foregroundColor(AppStyle.secondaryColor.opacity(0.8))
                .font(.system(size: 14))
                .padding(.leading, -10) // Move 10px to the left
            
            // Folder name
            Text(folder.displayName)
                .font(.system(size: 14))
                .foregroundColor(isSelected ? .white : .primary)
            
            // Track count
            if !folder.tracks.isEmpty {
                Text("(\(folder.tracks.count))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Selection checkbox
            // Button(action: {
            //     folderManager.toggleSelection(for: folder.path)
            // }) {
            //     Image(systemName: isSelected ? "checkmark.square.fill" : "square")
            //         .foregroundColor(isSelected ? AppStyle.secondaryColor.opacity(0.2) : .secondary)
            //         .font(.system(size: 12))
            // }
            // .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .padding(.leading, CGFloat(folder.level * 20)) // Add visual indentation based on folder depth
        .background(isSelected ? AppStyle.secondaryColor.opacity(0.1) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture {
            folderManager.toggleSelection(for: folder.path)
        }
        .onDrag {
            let paths = folder.allTracks.map { $0.path }
            let payload = paths.joined(separator: "\n")
            
            print("🔍 [FolderHierarchyView] Creating folder drag item:")
            print("   - Folder: \(folder.displayName)")
            print("   - Tracks in folder: \(folder.allTracks.count)")
            print("   - Paths: \(paths)")
            print("   - Payload type: \(type(of: payload))")
            print("   - Payload length: \(payload.count)")
            print("   - Payload content: '\(payload)'")
            
            return NSItemProvider(object: payload as NSString)
        }
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
            }
        }
    }
}

struct FolderTrackRowView: View {
    let track: Track
    @ObservedObject var audioService: AudioService
    @ObservedObject var metadataManager: TrackMetadataManager
    @ObservedObject var waveformServiceHolder: WaveformServiceHolder
    @ObservedObject var collectionService: CollectionService
    @Binding var selectedTracks: Set<Track.ID>
    @Binding var lastSelectedTrackId: Track.ID?
    @Binding var isTextFieldFocused: Bool
    let onDoubleClick: (Track) -> Void
    let allTracks: [Track]
    
    var body: some View {
        HStack(spacing: 8) {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
                .font(.caption)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
                .onDrag { dragItem(for: track) }
            
            // Waveform and play button
            WaveformColumn(
                track: track,
                audioService: audioService,
                waveformServiceHolder: waveformServiceHolder,
                collectionService: collectionService
            )
            .frame(width: 200, height: 36)
            
            // Track info
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 13))
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                if !track.artist.isEmpty && track.artist != "Unknown" {
                    Text(track.artist)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Selection checkbox
            if let trackId = track.id {
                // Button(action: {
                //     handleSelection(trackId: trackId, modifierFlags: [])
                // }) {
                    // Image(systemName: selectedTracks.contains(trackId) ? "checkmark.square.fill" : "square")
                    //     .foregroundColor(selectedTracks.contains(trackId) ? AppStyle.secondaryColor.opacity(0.2) : .secondary)
                    //     .font(.system(size: 12))
                // }
                // .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(selectedTracks.contains(track.id) ? AppStyle.secondaryColor.opacity(0.1) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture {
            print("🔍 [FolderHierarchyView] ANY tap gesture detected for track: \(track.title)")
            if let trackId = track.id {
                // Check for modifier keys using NSEvent
                var modifierFlags: EventModifiers = []
                
                if NSEvent.modifierFlags.contains(.command) {
                    print("🔍 [FolderHierarchyView] Command key detected")
                    modifierFlags.insert(.command)
                }
                if NSEvent.modifierFlags.contains(.shift) {
                    print("🔍 [FolderHierarchyView] Shift key detected")
                    modifierFlags.insert(.shift)
                }
                
                print("🔍 [FolderHierarchyView] Detected modifier flags: \(modifierFlags)")
                handleSelection(trackId: trackId, modifierFlags: modifierFlags)
            }
        }
        .onTapGesture(count: 2) {
            onDoubleClick(track)
        }
        .contextMenu {
            Button("Play") {
                Task {
                    await audioService.loadTrack(track)
                    audioService.play()
                }
            }
            Button("Reveal in Finder") {
                let trackURL = URL(fileURLWithPath: track.path)
                let parentDirectory = trackURL.deletingLastPathComponent().path
                NSWorkspace.shared.selectFile(track.path, inFileViewerRootedAtPath: parentDirectory)
            }
        }
    }
    
    // MARK: - Selection Logic
    
    private func handleSelection(trackId: Track.ID, modifierFlags: EventModifiers) {
        print("🔍 [FolderHierarchyView] handleSelection called:")
        print("   - Track ID: \(trackId)")
        print("   - Modifier flags: \(modifierFlags)")
        print("   - Contains command: \(modifierFlags.contains(.command))")
        print("   - Contains shift: \(modifierFlags.contains(.shift))")
        print("   - Current selection count: \(selectedTracks.count)")
        print("   - Last selected track: \(lastSelectedTrackId != nil ? String(describing: lastSelectedTrackId!) : "none")")
        
        if modifierFlags.contains(.command) {
            print("🔍 [FolderHierarchyView] Processing command+click selection")
            // Command+click: Add/remove from selection
            if selectedTracks.contains(trackId) {
                selectedTracks.remove(trackId)
                print("🔍 [FolderHierarchyView] Removed track from selection")
            } else {
                selectedTracks.insert(trackId)
                print("🔍 [FolderHierarchyView] Added track to selection")
            }
            lastSelectedTrackId = trackId
        } else if modifierFlags.contains(.shift) {
            print("🔍 [FolderHierarchyView] Processing shift+click selection")
            // Shift+click: Select range
            if let lastSelected = lastSelectedTrackId {
                print("🔍 [FolderHierarchyView] Selecting range from \(lastSelected) to \(trackId)")
                selectRange(from: lastSelected, to: trackId)
            } else {
                print("🔍 [FolderHierarchyView] No previous selection, just selecting this track")
                // If no previous selection, just select this track
                selectedTracks.insert(trackId)
                lastSelectedTrackId = trackId
            }
        } else {
            print("🔍 [FolderHierarchyView] Processing simple click selection")
            // Simple click: Select only this track
            selectedTracks.removeAll()
            selectedTracks.insert(trackId)
            lastSelectedTrackId = trackId
            print("🔍 [FolderHierarchyView] Cleared selection and selected only this track")
        }
        
        print("🔍 [FolderHierarchyView] Final selection count: \(selectedTracks.count)")
    }
    
    private func selectRange(from startId: Track.ID, to endId: Track.ID) {
        print("🔍 [FolderHierarchyView] selectRange called:")
        print("   - Start ID: \(startId)")
        print("   - End ID: \(endId)")
        
        guard let startIndex = allTracks.firstIndex(where: { $0.id == startId }),
              let endIndex = allTracks.firstIndex(where: { $0.id == endId }) else {
            print("🔍 [FolderHierarchyView] ERROR: Could not find track indices")
            return
        }
        
        let rangeStart = min(startIndex, endIndex)
        let rangeEnd = max(startIndex, endIndex)
        
        print("🔍 [FolderHierarchyView] Range indices: \(rangeStart) to \(rangeEnd)")
        print("🔍 [FolderHierarchyView] Total tracks in folder: \(allTracks.count)")
        
        // Add all tracks in the range to selection
        var addedCount = 0
        for index in rangeStart...rangeEnd {
            if let trackId = allTracks[index].id {
                selectedTracks.insert(trackId)
                addedCount += 1
            }
        }
        
        print("🔍 [FolderHierarchyView] Added \(addedCount) tracks to selection")
        lastSelectedTrackId = endId
    }
    
    // MARK: - Drag support
    
    private func dragItem(for track: Track) -> NSItemProvider {
        // Determine which tracks to include in the drag: selected ones if the dragged
        // track is selected, otherwise just the single row's track.
        let draggedIds = selectedTracks
        let tracksToExport: [Track]
        if let tid = track.id, draggedIds.contains(tid), !draggedIds.isEmpty {
            let selectedIdSet = draggedIds
            tracksToExport = allTracks.filter { idTrack in
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
        
        print("🔍 [FolderHierarchyView] Creating drag item:")
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

#Preview {
    let collectionService = CollectionService()
    let folderManager = FolderHierarchyManager()
    FolderHierarchyView(
        collectionService: collectionService,
        audioService: AudioService(),
        folderManager: folderManager,
        searchService: SearchService()
    )
}
