import SwiftUI

struct InteractiveTagsView: View {
    let track: Track
    let onUpdate: ([String]) -> Void
    @State private var tags: [String] = []
    @State private var input: String = ""
    @FocusState private var focused: Bool
    
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
                                    print("[TagsUI] remove tag \(tag) from track id=\(track.id ?? -1)")
                                    tags.removeAll { $0 == tag }
                                    onUpdate(tags)
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
        }
        .onAppear {
            tags = track.generalTags
        }
        .onChange(of: track.generalTags) { newValue in
            // Sync from parent
            tags = newValue
        }
    }
    
    private func addCurrentInput() {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        print("[TagsUI] add tag \(name) to track id=\(track.id ?? -1)")
        if !tags.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            tags.append(name)
            onUpdate(tags)
        }
        input = ""
        focused = true
    }
}

#Preview {
    InteractiveTagsView(
        track: Track(
            title: "Sample Track",
            artist: "Sample Artist",
            album: "Sample Album",
            path: "/path/to/track.mp3",
            isUrl: false,
            duration: 180000,
            generalTags: ["rock", "live"]
        ),
        onUpdate: { tags in
            print("Updated tags: \(tags)")
        }
    )
}


