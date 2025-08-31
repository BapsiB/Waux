import SwiftUI

struct SearchBarView: View {
    @ObservedObject var searchService: SearchService
    @State private var isSearchFocused: Bool = false
    @State private var showSearchOptions: Bool = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Search icon
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 12))
            
            // Search text field
            TextField("Search tracks...", text: $searchService.searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 200)
                .onTapGesture {
                    isSearchFocused = true
                }
                .onSubmit {
                    isSearchFocused = false
                }
            
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
            
            // Clear search button (only show when there's text)
            if !searchService.searchText.isEmpty {
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
