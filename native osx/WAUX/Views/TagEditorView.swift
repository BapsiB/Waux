import SwiftUI

struct TagEditorView: View {
    @ObservedObject var metadataManager: TrackMetadataManager
    @ObservedObject var collectionService: CollectionService
    private let trackIds: [Int]
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText: String = ""
    @FocusState private var searchFocused: Bool
    
    @State private var suggestionSuffix: String? = nil
    @State private var suggestedFullTag: String? = nil
    
    @State private var colorPickerTag: TagDefinition? = nil
    @State private var colorSelection: Color = .gray
    
    @State private var errorMessage: String? = nil
    
    // Computed properties for current tag state
    private var tracks: [Track] {
        metadataManager.getTracks(ids: trackIds)
    }
    
    private var commonTags: Set<String> {
        guard !tracks.isEmpty else { return [] }
        let tagSets = tracks.map { Set($0.generalTags) }
        return tagSets.reduce(tagSets.first ?? []) { $0.intersection($1) }
    }
    
    private var partialTags: Set<String> {
        guard tracks.count > 1 else { return [] }
        let allTags = Set(tracks.flatMap { $0.generalTags })
        return allTags.subtracting(commonTags).filter { tag in
            tracks.contains { $0.generalTags.contains(tag) }
        }
    }
    
    private var singleTrackTags: Set<String> {
        guard tracks.count == 1, let track = tracks.first else { return [] }
        return Set(track.generalTags)
    }
    
    init(metadataManager: TrackMetadataManager, collectionService: CollectionService, trackIds: [Int]) {
        self.metadataManager = metadataManager
        self.collectionService = collectionService
        self.trackIds = trackIds
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tracks.count > 1 ? "Edit Multiple Tracks Tags" : "Edit Track Tags")
                .font(.title3)
                .fontWeight(.semibold)
            
            searchRow
            
            if tracks.count > 1 {
                sectionAssignedAll
                sectionAssignedSome
            } else {
                sectionAssignedSingle
            }
            
            Divider().padding(.vertical, 4)
            
            Text("Available Tags:")
                .font(.headline)
            availableTagsList
            
            HStack {
                if metadataManager.isUpdating {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Saving...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 520, height: 560)
        .onAppear { 
            searchFocused = true 
            updateSuggestion()
        }
        .onChange(of: searchText) { _ in updateSuggestion() }
        .sheet(item: $colorPickerTag) { tag in
            VStack(alignment: .leading, spacing: 12) {
                Text("Select Color for \(tag.name)")
                    .font(.headline)
                ColorPicker("Color", selection: $colorSelection, supportsOpacity: false)
                    .labelsHidden()
                HStack {
                    Spacer()
                    Button("Cancel") { colorPickerTag = nil }
                    Button("Set Color") {
                        do {
                            try collectionService.updateGlobalTagColor(name: tag.name, color: colorSelection)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                        colorPickerTag = nil
                    }
                }
            }
            .padding(16)
            .frame(width: 320)
        }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }
    
    private var searchRow: some View {
        HStack(alignment: .top) {
            ZStack(alignment: .leading) {
                TextField("Search or create tag...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .focused($searchFocused)
                    .onSubmit { createOrToggleTag() }
                if let suggestionSuffix, !searchText.isEmpty, searchFocused {
                    HStack { Spacer() }.overlay(alignment: .leading) {
                        HStack(spacing: 0) {
                            Text(searchText)
                                .foregroundColor(.clear)
                            Text(suggestionSuffix)
                                .foregroundColor(.secondary)
                        }
                        .allowsHitTesting(false)
                    }
                }
            }
            Button {
                createOrToggleTag()
            } label: {
                Image(systemName: "plus.circle")
            }
            .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Add/Create Tag")
        }
    }
    
    private var sectionAssignedAll: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tags Assigned in All Tracks:")
                .font(.headline)
            tagContainer(for: commonTags)
                .frame(maxHeight: 110)
        }
    }
    
    private var sectionAssignedSome: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tags Assigned in Some Tracks:")
                .font(.headline)
            tagContainer(for: partialTags)
                .frame(maxHeight: 110)
        }
    }
    
    private var sectionAssignedSingle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Assigned Tags:")
                .font(.headline)
            tagContainer(for: singleTrackTags)
                .frame(maxHeight: 110)
        }
    }
    
    private var availableTagsList: some View {
        let allTags = collectionService.globalTags
        let filtered = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? allTags
            : allTags.filter { $0.name.lowercased().contains(searchText.lowercased()) }
        return ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(filtered, id: \.id) { tag in
                    tagChip(tag: tag, isInAvailableSection: true)
                }
            }
            .padding(.trailing, 6)
        }
    }
    
    private func tagContainer(for tagNames: some Sequence<String>) -> some View {
        let tags = tagNames.compactMap { name in
            collectionService.globalTags.first(where: { $0.name == name }) ?? TagDefinition(name: name)
        }
        return Group {
            if tags.isEmpty {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.textBackgroundColor))
                        .opacity(0.3)
                    Text("None")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    FlowLayout(spacing: 6) {
                        ForEach(tags, id: \.id) { tag in
                            tagChip(tag: tag, isInAvailableSection: false)
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(.textBackgroundColor)).opacity(0.3))
                .padding(.vertical, 2)
                .padding(.horizontal, 2)
            }
        }
    }
    
    @ViewBuilder
    private func tagChip(tag: TagDefinition, isInAvailableSection: Bool) -> some View {
        let isSelected: Bool = {
            if tracks.count > 1 {
                return commonTags.contains(tag.name)
            } else {
                return singleTrackTags.contains(tag.name)
            }
        }()
        let bg = (tag.color ?? Color.gray.opacity(0.6)).opacity(isSelected ? 1.0 : 0.8)
        let textColor: Color = {
            let nsColor = NSColor(bg)
            guard let rgbColor = nsColor.usingColorSpace(.sRGB) else {
                return .black // fallback color
            }
            let brightness = (rgbColor.redComponent * 0.299 + rgbColor.greenComponent * 0.587 + rgbColor.blueComponent * 0.114)
            return brightness < 0.5 ? .white : .black
        }()
        Menu {
            Button("Set Color") {
                colorSelection = tag.color ?? .gray
                colorPickerTag = tag
            }
            Divider()
            Button(role: .destructive) { try? collectionService.removeGlobalTag(tag.name) } label: {
                Label("Delete Tag Definition \"\(tag.name)\"", systemImage: "trash")
            }
        } label: {
            HStack(spacing: 6) {
                if isSelected && isInAvailableSection {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 12))
                        .foregroundColor(textColor)
                }
                Text(tag.name)
                    .font(.system(size: 12))
                    .foregroundColor(textColor)
                if !isInAvailableSection {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 12))
                        .foregroundColor(textColor.opacity(0.9))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 14).fill(bg))
        }
        .simultaneousGesture(TapGesture().onEnded {
            toggleAssignment(for: tag.name, currentlySelected: isSelected)
        })
    }
    
    private func updateSuggestion() {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        suggestionSuffix = nil
        suggestedFullTag = nil
        guard !term.isEmpty else { return }
        let existing = collectionService.globalTags
        if let firstMatch = existing.first(where: { $0.name.lowercased().hasPrefix(term) && $0.name.lowercased() != term }) {
            suggestedFullTag = firstMatch.name
            suggestionSuffix = String(firstMatch.name.dropFirst(searchText.count))
        }
    }
    
    private func createOrToggleTag() {
        let name = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        
        let existing = collectionService.globalTags.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
        
        do {
            if let existingName = existing?.name {
                let isInAll = tracks.count > 1 ? commonTags.contains(existingName) : singleTrackTags.contains(existingName)
                if isInAll {
                    metadataManager.removeTag(from: trackIds, tag: existingName)
                } else {
                    metadataManager.addTag(to: trackIds, tag: existingName)
                }
            } else {
                try collectionService.addGlobalTag(name)
                metadataManager.addTag(to: trackIds, tag: name)
            }
            
            searchText = ""
            suggestedFullTag = nil
            suggestionSuffix = nil
            searchFocused = true
            
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func toggleAssignment(for tagName: String, currentlySelected: Bool) {
        if currentlySelected {
            metadataManager.removeTag(from: trackIds, tag: tagName)
        } else {
            metadataManager.addTag(to: trackIds, tag: tagName)
        }
    }
}

// Simple flow layout for chips
struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    let content: () -> Content
    
    init(spacing: CGFloat = 6, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }
    
    var body: some View {
        GeometryReader { geometry in
            self.generateContent(in: geometry)
        }
    }
    
    private func generateContent(in geometry: GeometryProxy) -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero
        
        return ZStack(alignment: .topLeading) {
            content()
                .alignmentGuide(.leading, computeValue: { d in
                    if abs(width - d.width) > geometry.size.width {
                        width = 0
                        height -= d.height
                    }
                    let result = width
                    if d.width == geometry.size.width {
                        width = 0
                    } else {
                        width -= d.width + spacing
                    }
                    return result
                })
                .alignmentGuide(.top, computeValue: { d in
                    let result = height
                    if d.width == geometry.size.width {
                        height = 0
                    }
                    return result
                })
        }
    }
}

