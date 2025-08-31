import SwiftUI

struct SearchBarView: View {
    @ObservedObject var searchService: SearchService
    @State private var isSearchFocused: Bool = false
    @State private var showSearchOptions: Bool = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Search text field with magnifier/clear button inside
            HStack(spacing: 4) {
                TextField("Search tracks...", text: $searchService.searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .onTapGesture {
                        isSearchFocused = true
                    }
                    .onSubmit {
                        isSearchFocused = false
                    }
                
                // Show magnifier when no text, clear button when there's text
                if searchService.searchText.isEmpty {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                } else {
                    Button(action: {
                        searchService.clearSearch()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(.separatorColor), lineWidth: 0.5)
            )
            .frame(width: 200)
            
            // Search options button
            Button(action: {
                showSearchOptions.toggle()
            }) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
            }
            .buttonStyle(PlainButtonStyle())
            .help("Search options")
        }
        .popover(isPresented: $showSearchOptions) {
            SearchOptionsView(searchService: searchService)
        }
    }
}

struct SearchOptionsView: View {
    @ObservedObject var searchService: SearchService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Search Options")
                .font(.headline)
                .padding(.bottom, 4)
            
            VStack(alignment: .leading, spacing: 8) {
                SearchOptionRow(title: "Title", isEnabled: $searchService.searchInTitle)
                SearchOptionRow(title: "Artist", isEnabled: $searchService.searchInArtist)
                SearchOptionRow(title: "Album", isEnabled: $searchService.searchInAlbum)
                SearchOptionRow(title: "Album Artist", isEnabled: $searchService.searchInAlbumArtist)
                SearchOptionRow(title: "Composer", isEnabled: $searchService.searchInComposer)
                SearchOptionRow(title: "Genre", isEnabled: $searchService.searchInGenre)
                SearchOptionRow(title: "Tags", isEnabled: $searchService.searchInTags)
                SearchOptionRow(title: "Comment", isEnabled: $searchService.searchInComment)
            }
            
            Divider()
            
            HStack {
                Button("Select All") {
                    searchService.selectAllSearchOptions()
                }
                .buttonStyle(.bordered)
                
                Button("Clear All") {
                    searchService.clearAllSearchOptions()
                }
                .buttonStyle(.bordered)
                
                Spacer()
            }
        }
        .padding()
        .frame(width: 250)
    }
}

struct SearchOptionRow: View {
    let title: String
    @Binding var isEnabled: Bool
    
    var body: some View {
        HStack {
            Toggle(title, isOn: $isEnabled)
                .toggleStyle(.checkbox)
            Spacer()
        }
    }
}

#Preview {
    SearchBarView(searchService: SearchService())
        .padding()
}
