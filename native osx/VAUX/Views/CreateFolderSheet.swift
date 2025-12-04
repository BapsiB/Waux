import SwiftUI

struct CreateFolderSheet: View {
    @Binding var newFolderName: String
    @FocusState private var isTextFieldFocused: Bool
    let parentFolder: PlaylistFolder?
    let onCancel: () -> Void
    let onCreate: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Create New Folder")
                .font(.title2)
                .fontWeight(.semibold)
            
            if let parentFolder = parentFolder {
                Text("Creating folder in: \(parentFolder.name)")
                    .font(.body)
                    .foregroundColor(.secondary)
            } else {
                Text("Enter a name for your new folder")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            TextField("Folder name", text: $newFolderName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .focused($isTextFieldFocused)
                .onSubmit {
                    if !newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onCreate()
                    }
                }
            
            HStack(spacing: 12) {
                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
                
                Button("Create") {
                    onCreate()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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