import SwiftUI
import UniformTypeIdentifiers

struct FolderHierarchyView: View {
    @ObservedObject var collectionService: CollectionService
    @ObservedObject var audioService: AudioService
    @ObservedObject var folderManager: FolderHierarchyManager
    @Binding var searchText: String
    @StateObject private var waveformServiceHolder = WaveformServiceHolder()
    @StateObject private var metadataManager: TrackMetadataManager
    @State private var selectedTracks = Set<Track.ID>()
    @State private var showTagEditor = false
    @State private var showMetadataEditor = false
    @FocusState private var isTextFieldFocused: Bool
    
    init(collectionService: CollectionService, audioService: AudioService, folderManager: FolderHierarchyManager, searchText: Binding<String>) {
        self.collectionService = collectionService
        self.audioService = audioService
        self.folderManager = folderManager
        self._searchText = searchText
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
                            searchText: $searchText,
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
            folderManager.buildHierarchy(from: collectionService.tracks)
        }
        .onChange(of: collectionService.tracks) { _, _ in
            // Rebuild hierarchy when tracks change
            folderManager.buildHierarchy(from: collectionService.tracks)
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
            }
            
            if !folderManager.selectedFolders.isEmpty {
                Button("Add Selected Folders to Playlist") {
                    // TODO: Implement add to playlist functionality
                }
                Divider()
            }
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
    @Binding var searchText: String
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
            
            // Tracks in this folder
            if folderManager.isExpanded(folder.path) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(folder.tracks) { track in
                        if searchText.isEmpty || trackMatchesSearch(track) {
                            FolderTrackRowView(
                                track: track,
                                audioService: audioService,
                                metadataManager: metadataManager,
                                waveformServiceHolder: waveformServiceHolder,
                                collectionService: collectionService,
                                selectedTracks: $selectedTracks,
                                isTextFieldFocused: $isTextFieldFocused,
                                onDoubleClick: onDoubleClick
                            )
                            .padding(.leading, 20)
                        }
                    }
                }
            }
        }
    }
    
    private func trackMatchesSearch(_ track: Track) -> Bool {
        return track.title.localizedCaseInsensitiveContains(searchText) ||
               track.artist.localizedCaseInsensitiveContains(searchText) ||
               track.album.localizedCaseInsensitiveContains(searchText)
    }
}

struct FolderHeaderView: View {
    let folder: FolderNode
    @ObservedObject var folderManager: FolderHierarchyManager
    let isExpanded: Bool
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            // Expand/collapse button
            if folder.hasChildren {
                Button(action: {
                    folderManager.toggleExpansion(for: folder.path)
                }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                // Spacer for alignment when no children
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 16, height: 16)
            }
            
            // Folder icon
            Image(systemName: "folder")
                .foregroundColor(.blue)
                .font(.system(size: 14))
            
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
            Button(action: {
                folderManager.toggleSelection(for: folder.path)
            }) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .font(.system(size: 12))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.blue.opacity(0.2) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture {
            folderManager.toggleSelection(for: folder.path)
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
    @Binding var isTextFieldFocused: Bool
    let onDoubleClick: (Track) -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
                .font(.caption)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
                .onDrag { dragItem(for: track) }
            
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
            
            // Duration
            Text(track.formattedDuration)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .trailing)
            
            // Selection checkbox
            if let trackId = track.id {
                Button(action: {
                    if selectedTracks.contains(trackId) {
                        selectedTracks.remove(trackId)
                    } else {
                        selectedTracks.insert(trackId)
                    }
                }) {
                    Image(systemName: selectedTracks.contains(trackId) ? "checkmark.square.fill" : "square")
                        .foregroundColor(selectedTracks.contains(trackId) ? .blue : .secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(selectedTracks.contains(track.id) ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture {
            if let trackId = track.id {
                if selectedTracks.contains(trackId) {
                    selectedTracks.remove(trackId)
                } else {
                    selectedTracks.insert(trackId)
                }
            }
        }
        .onTapGesture(count: 2) {
            onDoubleClick(track)
        }
    }
    
    // MARK: - Drag support
    
    private func dragItem(for track: Track) -> NSItemProvider {
        let payload = track.path as NSString
        return NSItemProvider(item: payload, typeIdentifier: UTType.plainText.identifier)
    }
}

#Preview {
    let collectionService = CollectionService()
    let folderManager = FolderHierarchyManager()
    FolderHierarchyView(
        collectionService: collectionService,
        audioService: AudioService(),
        folderManager: folderManager,
        searchText: .constant("")
    )
}
