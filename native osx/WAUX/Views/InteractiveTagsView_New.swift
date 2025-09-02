import SwiftUI
import AppKit

struct InteractiveTagsView_New: View {
    let trackId: Int
    @ObservedObject var metadataManager: TrackMetadataManager
    @Binding var isTextFieldFocused: Bool
    @State private var input: String = ""
    @FocusState private var focused: Bool
    
    private var track: Track? {
        metadataManager.getTrack(id: trackId)
    }
    
    private var tags: [String] {
        track?.generalTags ?? []
    }
    
    // Get global tags from the metadata manager's collection service
    private var globalTags: [String] {
        metadataManager.collectionServiceAccess.globalTags.map { $0.name }
    }
    
    // Get the best suggestion for inline completion
    private var suggestion: String? {
        let inputLower = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !inputLower.isEmpty else { return nil }
        
        // First priority: exact matches
        let exactMatches = globalTags.filter { $0.lowercased() == inputLower }
        if !exactMatches.isEmpty {
            return exactMatches.first
        }
        
        // Second priority: starts with input
        let startsWith = globalTags.filter { $0.lowercased().hasPrefix(inputLower) && $0.lowercased() != inputLower }
        if !startsWith.isEmpty {
            return startsWith.first
        }
        
        // Third priority: contains input
        let contains = globalTags.filter { 
            $0.lowercased().contains(inputLower) && 
            !$0.lowercased().hasPrefix(inputLower) && 
            $0.lowercased() != inputLower 
        }
        if !contains.isEmpty {
            return contains.first
        }
        
        return nil
    }
    
    // Get the completion part (what would be added)
    private var completionPart: String? {
        guard let suggestion = suggestion else { return nil }
        let inputLower = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if suggestion.lowercased().hasPrefix(inputLower) && suggestion.lowercased() != inputLower {
            return String(suggestion.dropFirst(inputLower.count))
        }
        return nil
    }
    
    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag)
                                .font(.caption)
                                .padding(.vertical, 2)
                                .padding(.horizontal, 6)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.15)))
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .onTapGesture {
                                    metadataManager.removeTag(from: [trackId], tag: tag)
                                }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            ZStack(alignment: .leading) {
                // Custom NSTextField that can intercept Tab key
                CustomTagTextField(
                    text: $input,
                    placeholder: "+ tag",
                    onTab: {
                        if let suggestion = suggestion {
                            input = suggestion
                        }
                    },
                    onSubmit: addCurrentInput
                )
                .frame(width: 80)
                .focused($focused)
                .onChange(of: focused) { _, newValue in
                    isTextFieldFocused = newValue
                }
                
                // Overlay showing the completion suggestion
                if let completion = completionPart, !completion.isEmpty {
                    HStack(spacing: 0) {
                        // Invisible spacer to align with the input text
                        Text(input)
                            .font(.caption)
                            .foregroundColor(.clear)
                            .allowsHitTesting(false)
                        
                        // The completion part in grey
                        Text(completion)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .allowsHitTesting(false)
                    }
                    .allowsHitTesting(false)
                }
            }
        }
    }
    
    private func addCurrentInput() {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        
        if !tags.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            metadataManager.addTag(to: [trackId], tag: name)
        }
        input = ""
        focused = true
    }
}

// Custom NSTextField that can intercept Tab key
struct CustomTagTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onTab: () -> Void
    let onSubmit: () -> Void
    
    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        textField.isBordered = false
        textField.backgroundColor = NSColor.clear
        textField.focusRingType = .none
        textField.delegate = context.coordinator
        return textField
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        nsView.stringValue = text
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: CustomTagTextField
        
        init(_ parent: CustomTagTextField) {
            self.parent = parent
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }
        
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                parent.onTab()
                return true // Prevent default Tab behavior
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}
