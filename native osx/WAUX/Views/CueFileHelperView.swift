//
//  CueFileHelperView.swift
//  WAUX
//
//  Created by AI Assistant on 03/10/2025.
//

import SwiftUI
import UniformTypeIdentifiers

enum ParsingLayer: Int, CaseIterable {
    case layer1 = 1
    case layer2 = 2
    case layer3 = 3
    case layer4 = 4
    
    var title: String {
        switch self {
        case .layer1: return "Layer 1: Raw Parse"
        case .layer2: return "Layer 2: Fades Merged"
        case .layer3: return "Layer 3: Channels Merged"
        case .layer4: return "Layer 4: Final"
        }
    }
    
    var description: String {
        switch self {
        case .layer1: return "Each line parsed into CueEvent"
        case .layer2: return "Fades aggregated with clips"
        case .layer3: return "Events merged across channels"
        case .layer4: return "Final aggregation by catalog ID"
        }
    }
}

enum SortField: String, CaseIterable {
    case track = "track"
    case eventID = "eventID"
    case catalogID = "catalogID"
    case title = "title"
    case startTime = "startTime"
    case endTime = "endTime"
    case duration = "duration"
    case state = "state"
    case composer = "composer"
    
    var displayName: String {
        switch self {
        case .track: return "Track"
        case .eventID: return "Event"
        case .catalogID: return "Catalog ID"
        case .title: return "Title"
        case .startTime: return "Start Time"
        case .endTime: return "End Time"
        case .duration: return "Duration"
        case .state: return "State"
        case .composer: return "Composer"
        }
    }
}

struct CueFileHelperView: View {
    @State private var parsingResult: CueParsingResult?
    @State private var selectedLayer: ParsingLayer = .layer4
    @State private var isFileLoaded = false
    @State private var isDragging = false
    @State private var searchDirectory: URL?
    @State private var processingProgress: (current: Int, total: Int)?
    @State private var originalFileURL: URL?
    @State private var showingDirectoryPicker = false
    @State private var selectedEventForInfo: CueEvent?
    @State private var filterText: String = ""
    @State private var sortField: SortField = .catalogID
    @State private var sortAscending: Bool = true
    @State private var sortOrder: [KeyPathComparator<CueEvent>] = []
    
    private let parsingService = CueFileParsingService()
    private let composerService = ComposerFetchingService()
    
    private var currentEvents: [CueEvent] {
        guard let result = parsingResult else { return [] }
        let events: [CueEvent]
        switch selectedLayer {
        case .layer1: events = result.layer1
        case .layer2: events = result.layer2
        case .layer3: events = result.layer3
        case .layer4: events = result.layer4
        }
        
        // Apply filter if present
        let filteredEvents = filterText.isEmpty ? events : events.filter { event in
            let searchText = filterText.lowercased()
            return event.catalogID.lowercased().contains(searchText) ||
                   event.title.lowercased().contains(searchText)
        }
        
        // Apply sorting using sortOrder if available, otherwise use default sorting
        if !sortOrder.isEmpty {
            return filteredEvents.sorted(using: sortOrder)
        } else {
            // Default sorting by catalogID
            return filteredEvents.sorted { first, second in
                first.catalogID.compare(second.catalogID) == .orderedAscending
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if isFileLoaded {
                // Header with controls
                headerView
                
                // Table view
                tableView
                
                // Bottom controls
                bottomControlsView
            } else {
                // Drop zone
                dropZoneView
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            handleDrop(providers: providers)
        }
        .sheet(item: $selectedEventForInfo) { event in
            CueEventDetailView(event: event)
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Cue File Helper")
                    .font(.headline)
                
                Spacer()
                
                if let progress = processingProgress {
                    ProgressView(value: Double(progress.current), total: Double(progress.total)) {
                        Text("Fetching composers: \(progress.current) / \(progress.total)")
                            .font(.caption)
                    }
                    .frame(width: 200)
                }
                
                Button("Select Audio Directory") {
                    selectDirectory()
                }
                .buttonStyle(.bordered)
                
                if searchDirectory != nil {
                    Text("✓")
                        .foregroundColor(.green)
                        .help("Audio directory selected")
                }
            }
            .padding()
            
            Divider()
            
            // Layer selector and filter
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Text("Debug View:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $selectedLayer) {
                        ForEach(ParsingLayer.allCases, id: \.self) { layer in
                            Text(layer.title).tag(layer)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 500)
                }
                
                // Filter controls
                HStack(spacing: 12) {
                    // Filter field
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        
                        TextField("Filter by catalog ID or title...", text: $filterText)
                            .textFieldStyle(.plain)
                        
                        if !filterText.isEmpty {
                            Button(action: {
                                filterText = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Clear filter")
                        }
                    }
                    .padding(6)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(6)
                    
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Table View
    
    private var tableView: some View {
        Table(currentEvents, sortOrder: $sortOrder) {
            TableColumn("") { event in
                Button(action: {
                    selectedEventForInfo = event
                }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("Show detailed information")
            }
            .width(30)
            
            TableColumn("Track", value: \.channel) { event in
                Text("\(event.channel)")
            }
            .width(60)
            
            TableColumn("Event", value: \.eventID) { event in
                Text("\(event.eventID)")
            }
            .width(60)
            
            TableColumn("Catalog ID", value: \.catalogID) { event in
                Text(event.catalogID)
            }
            .width(min: 150, ideal: 200)
            
            TableColumn("Title", value: \.title) { event in
                Text(event.title)
            }
            .width(min: 150, ideal: 250)
            
            TableColumn("Start Time", value: \.startTime) { event in
                Text(event.startTime)
            }
            .width(100)
            
            TableColumn("End Time", value: \.endTime) { event in
                Text(event.endTime)
            }
            .width(100)
            
            TableColumn("Duration", value: \.duration) { event in
                Text(event.duration)
            }
            .width(80)
            
            TableColumn("State", value: \.state) { event in
                Text(event.state)
            }
            .width(80)
            
            TableColumn("Composer", value: \.composer) { event in
                Text(event.composer.isEmpty ? "-" : event.composer)
                    .foregroundColor(event.composer.isEmpty ? .secondary : .primary)
            }
            .width(min: 150, ideal: 200)
        }
        .onChange(of: sortOrder) { newSortOrder in
            if let newSort = newSortOrder.first {
                // Map KeyPathComparator to our SortField
                switch newSort.keyPath {
                case \.channel:
                    sortField = .track
                case \.eventID:
                    sortField = .eventID
                case \.catalogID:
                    sortField = .catalogID
                case \.title:
                    sortField = .title
                case \.startTime:
                    sortField = .startTime
                case \.endTime:
                    sortField = .endTime
                case \.duration:
                    sortField = .duration
                case \.state:
                    sortField = .state
                case \.composer:
                    sortField = .composer
                default:
                    break
                }
                sortAscending = newSort.order == .forward
            }
        }
    }
    
    // MARK: - Bottom Controls
    
    private var totalEventsCount: Int {
        guard let result = parsingResult else { return 0 }
        switch selectedLayer {
        case .layer1: return result.layer1.count
        case .layer2: return result.layer2.count
        case .layer3: return result.layer3.count
        case .layer4: return result.layer4.count
        }
    }
    
    private var bottomControlsView: some View {
        HStack {
            HStack(spacing: 4) {
                Text("\(currentEvents.count)")
                    .font(.caption)
                    .foregroundColor(.primary)
                
                if !filterText.isEmpty {
                    Text("/ \(totalEventsCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("filtered")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("events")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text("in \(selectedLayer.title)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Fetch Composers") {
                fetchComposers()
            }
            .buttonStyle(.borderedProminent)
            .disabled(searchDirectory == nil || processingProgress != nil || selectedLayer != .layer4)
            .help(selectedLayer != .layer4 ? "Composer fetching only works on Layer 4" : "Fetch composer metadata from audio files")
            
            Button("Export to CSV") {
                exportToCSV()
            }
            .buttonStyle(.bordered)
            .disabled(currentEvents.isEmpty)
            
            Button("Clear") {
                clearData()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Drop Zone View
    
    private var dropZoneView: some View {
        ZStack {
            Color(NSColor.controlBackgroundColor)
            
            VStack(spacing: 20) {
                Image(systemName: "doc.text")
                    .font(.system(size: 64))
                    .foregroundColor(isDragging ? .accentColor : .secondary)
                
                Text("Drag a cue file here to parse it")
                    .font(.title2)
                    .foregroundColor(.secondary)
                
                Text("Supports .txt files exported from DAWs")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .scaleEffect(isDragging ? 1.1 : 1.0)
            .animation(.spring(response: 0.3), value: isDragging)
        }
    }
    
    // MARK: - Functions
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (urlData, error) in
            DispatchQueue.main.async {
                guard let urlData = urlData as? Data,
                      let url = URL(dataRepresentation: urlData, relativeTo: nil),
                      url.pathExtension.lowercased() == "txt" else {
                    return
                }
                
                parseFile(at: url)
            }
        }
        
        return true
    }
    
    private func parseFile(at url: URL) {
        originalFileURL = url
        
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            
            let result = parsingService.parseWithAllLayers(from: lines)
            
            withAnimation {
                parsingResult = result
                selectedLayer = .layer4  // Start with final layer
                isFileLoaded = true
            }
        } catch {
            print("Error reading file: \(error)")
        }
    }
    
    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select directory containing audio files"
        
        if let lastDirectory = searchDirectory {
            panel.directoryURL = lastDirectory
        }
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                searchDirectory = url
            }
        }
    }
    
    private func fetchComposers() {
        guard let directory = searchDirectory, var result = parsingResult else { return }
        
        processingProgress = (0, result.layer4.count)
        
        DispatchQueue.global(qos: .userInitiated).async {
            let updatedEvents = composerService.fetchComposers(for: result.layer4, in: directory) { current, total in
                DispatchQueue.main.async {
                    processingProgress = (current, total)
                }
            }
            
            DispatchQueue.main.async {
                // Update layer 4 with composer information
                parsingResult = CueParsingResult(
                    layer1: result.layer1,
                    layer2: result.layer2,
                    layer3: result.layer3,
                    layer4: updatedEvents
                )
                processingProgress = nil
            }
        }
    }
    
    private func exportToCSV() {
        guard let originalURL = originalFileURL else { return }
        
        let fileName = originalURL.deletingPathExtension().lastPathComponent
        let layerSuffix = selectedLayer == .layer4 ? "" : "_\(selectedLayer.title.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: ":", with: ""))"
        let exportURL = originalURL.deletingLastPathComponent().appendingPathComponent("\(fileName)\(layerSuffix).csv")
        
        // Build CSV content
        var csvContent = "Track,Event,Catalog ID,Title,Unique Titles,Start Time,End Time,Duration,State,Composer\n"
        
        for event in currentEvents {
            let channel = "\(event.channel)"
            let eventID = "\(event.eventID)"
            let catalogID = escapeCSVValue(event.catalogID)
            let title = escapeCSVValue(event.title)
            let uniqueTitles = escapeCSVValue(event.uniqueTitles.sorted().joined(separator: "; "))
            let startTime = escapeCSVValue(event.startTime)
            let endTime = escapeCSVValue(event.endTime)
            let duration = escapeCSVValue(event.duration)
            let state = escapeCSVValue(event.state)
            let composer = escapeCSVValue(event.composer)
            
            csvContent += "\(channel),\(eventID),\(catalogID),\(title),\(uniqueTitles),\(startTime),\(endTime),\(duration),\(state),\(composer)\n"
        }
        
        do {
            try csvContent.write(to: exportURL, atomically: true, encoding: .utf8)
            
            // Reveal in Finder
            NSWorkspace.shared.selectFile(exportURL.path, inFileViewerRootedAtPath: "")
        } catch {
            print("Error exporting CSV: \(error)")
        }
    }
    
    private func escapeCSVValue(_ value: String) -> String {
        var escaped = value
        
        let needsQuotes = escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n")
        
        if needsQuotes {
            escaped = escaped.replacingOccurrences(of: "\"", with: "\"\"")
            escaped = "\"\(escaped)\""
        }
        
        return escaped
    }
    
    
    private func clearData() {
        withAnimation {
            parsingResult = nil
            isFileLoaded = false
            originalFileURL = nil
            processingProgress = nil
            selectedLayer = .layer4
            filterText = ""
            sortField = .catalogID
            sortAscending = true
            sortOrder = []
        }
    }
}

// MARK: - Detail View

struct CueEventDetailView: View {
    let event: CueEvent
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Cue Event Details")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Basic Information
                    infoSection(title: "Basic Information") {
                        infoRow(label: "Catalog ID", value: event.catalogID)
                        infoRow(label: "Title", value: event.title.isEmpty ? "-" : event.title)
                        infoRow(label: "Original Name", value: event.originalClipName)
                        infoRow(label: "Track", value: "\(event.channel)")
                        infoRow(label: "Event ID", value: "\(event.eventID)")
                        infoRow(label: "State", value: event.state.isEmpty ? "-" : event.state)
                    }
                    
                    // Timing Information
                    infoSection(title: "Timing Information") {
                        infoRow(label: "Start Time", value: event.startTime)
                        infoRow(label: "End Time", value: event.endTime)
                        infoRow(label: "Duration", value: event.duration)
                    }
                    
                    // Composer
                    infoSection(title: "Metadata") {
                        infoRow(label: "Composer", value: event.composer.isEmpty ? "-" : event.composer)
                    }
                    
                    // Unique Titles (merged clips)
                    if !event.uniqueTitles.isEmpty {
                        infoSection(title: "Unique Titles (Merged Clips)") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(event.uniqueTitles).sorted(), id: \.self) { title in
                                    Text("• \(title)")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.primary)
                                        .textSelection(.enabled)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 600, height: 500)
    }
    
    @ViewBuilder
    private func infoSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
    
    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .fontWeight(.medium)
                .frame(width: 120, alignment: .leading)
            
            Text(value)
                .foregroundColor(.primary)
                .textSelection(.enabled)
            
            Spacer()
        }
    }
}

#Preview {
    CueFileHelperView()
        .frame(width: 900, height: 600)
}
