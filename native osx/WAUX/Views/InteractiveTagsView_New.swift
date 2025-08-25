import SwiftUI

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
            
            TextField("+ tag", text: $input)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.caption)
                .frame(width: 80)
                .focused($focused)
                .onSubmit { addCurrentInput() }
                .onChange(of: focused) { _, newValue in
                    isTextFieldFocused = newValue
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
