import SwiftUI

struct RenameFolderSheet: View {
    @Binding var folderName: String
    @FocusState private var isTextFieldFocused: Bool
    let onCancel: () -> Void
    let onRename: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Rename Folder")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Enter a new name for the folder")
                .font(.body)
                .foregroundColor(.secondary)
            
            TextField("Folder name", text: $folderName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .focused($isTextFieldFocused)
                .onSubmit {
                    if !folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onRename()
                    }
                }
            
            HStack(spacing: 12) {
                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
                
                Button("Rename") {
                    onRename()
                }
                .buttonStyle(.borderedProminent)
                .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 300)
        .onAppear {
            // Automatically focus the text field when the sheet appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
    }
}