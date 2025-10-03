//
//  CueFileHelperView.swift
//  WAUX
//
//  Created by AI Assistant on 03/10/2025.
//

import SwiftUI
import UniformTypeIdentifiers

struct CueFileHelperView: View {
    @State private var events: [CueEvent] = []
    @State private var isFileLoaded = false
    @State private var isDragging = false
    @State private var searchDirectory: URL?
    @State private var processingProgress: (current: Int, total: Int)?
    @State private var originalFileURL: URL?
    @State private var showingDirectoryPicker = false
    @State private var selectedEventForInfo: CueEvent?
    
    private let parsingService = CueFileParsingService()
    private let composerService = ComposerFetchingService()
    
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
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Table View
    
    private var tableView: some View {
        Table(events) {
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
            
            TableColumn("Channel") { event in
                Text("\(event.channel)")
            }
            .width(60)
            
            TableColumn("Event") { event in
                Text("\(event.eventID)")
            }
            .width(60)
            
            TableColumn("Clip Name") { event in
                Text(event.clipName)
            }
            .width(min: 200, ideal: 300)
            
            TableColumn("Start Time") { event in
                Text(event.startTime)
            }
            .width(100)
            
            TableColumn("End Time") { event in
                Text(event.endTime)
            }
            .width(100)
            
            TableColumn("Duration") { event in
                Text(event.duration)
            }
            .width(80)
            
            TableColumn("State") { event in
                Text(event.state)
            }
            .width(80)
            
            TableColumn("Composer") { event in
                Text(event.composer.isEmpty ? "-" : event.composer)
                    .foregroundColor(event.composer.isEmpty ? .secondary : .primary)
            }
            .width(min: 150, ideal: 200)
        }
    }
    
    // MARK: - Bottom Controls
    
    private var bottomControlsView: some View {
        HStack {
            Text("\(events.count) clips")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button("Fetch Composers") {
                fetchComposers()
            }
            .buttonStyle(.borderedProminent)
            .disabled(searchDirectory == nil || processingProgress != nil)
            
            Button("Export to CSV") {
                exportToCSV()
            }
            .buttonStyle(.bordered)
            .disabled(events.isEmpty)
            
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
            
            let parsedEvents = parsingService.aggregateEvents(from: lines)
            
            withAnimation {
                events = parsedEvents
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
        guard let directory = searchDirectory else { return }
        
        processingProgress = (0, events.count)
        
        DispatchQueue.global(qos: .userInitiated).async {
            let updatedEvents = composerService.fetchComposers(for: events, in: directory) { current, total in
                DispatchQueue.main.async {
                    processingProgress = (current, total)
                }
            }
            
            DispatchQueue.main.async {
                events = updatedEvents
                processingProgress = nil
            }
        }
    }
    
    private func exportToCSV() {
        guard let originalURL = originalFileURL else { return }
        
        let fileName = originalURL.deletingPathExtension().lastPathComponent
        let exportURL = originalURL.deletingLastPathComponent().appendingPathComponent("\(fileName).csv")
        
        // Build CSV content
        var csvContent = "Clip Name,Duration,Composer\n"
        
        for event in events {
            let clipName = escapeCSVValue(event.clipName)
            let duration = escapeCSVValue(event.duration)
            let composer = escapeCSVValue(event.composer)
            
            csvContent += "\(clipName),\(duration),\(composer)\n"
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
            events = []
            isFileLoaded = false
            originalFileURL = nil
            processingProgress = nil
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
                        infoRow(label: "Clip Name", value: event.clipName)
                        infoRow(label: "Channel", value: "\(event.channel)")
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
                    
                    // All Names (merged clips/fades)
                    if !event.allNames.isEmpty {
                        infoSection(title: "All Clips & Fades") {
                            Text(event.allNames)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
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
