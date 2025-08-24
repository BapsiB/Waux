import Foundation

class PreferenceService: ObservableObject {
    static let shared = PreferenceService()
    
    private let userDefaults = UserDefaults.standard
    
    // MARK: - Keys
    private let lastFolderPathKey = "lastFolderPath"
    private let lastFolderBookmarkKey = "lastFolderBookmark"
    
    // MARK: - Published Properties
    @Published var lastFolderPath: String? {
        didSet {
            if let path = lastFolderPath {
                userDefaults.set(path, forKey: lastFolderPathKey)
            } else {
                userDefaults.removeObject(forKey: lastFolderPathKey)
            }
        }
    }
    
    @Published var lastFolderBookmark: Data? {
        didSet {
            if let bookmark = lastFolderBookmark {
                userDefaults.set(bookmark, forKey: lastFolderBookmarkKey)
            } else {
                userDefaults.removeObject(forKey: lastFolderBookmarkKey)
            }
        }
    }
    
    // MARK: - Initialization
    private init() {
        loadPreferences()
    }
    
    // MARK: - Public Methods
    func saveLastFolder(_ url: URL) {
        lastFolderPath = url.path
        
        // Create a security-scoped bookmark for the folder
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            lastFolderBookmark = bookmark
        } catch {
            print("Failed to create bookmark for folder: \(error)")
            lastFolderBookmark = nil
        }
    }
    
    func getLastFolderURL() -> URL? {
        guard let path = lastFolderPath else { return nil }
        return URL(fileURLWithPath: path)
    }
    
    func getLastFolderBookmarkURL() -> URL? {
        guard let bookmarkData = lastFolderBookmark else { return nil }
        
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            if isStale {
                // Bookmark is stale, try to create a new one
                if let path = lastFolderPath {
                    let newURL = URL(fileURLWithPath: path)
                    saveLastFolder(newURL)
                }
            }
            
            return url
        } catch {
            print("Failed to resolve bookmark: \(error)")
            return nil
        }
    }
    
    func clearLastFolder() {
        lastFolderPath = nil
        lastFolderBookmark = nil
    }
    
    // MARK: - Private Methods
    private func loadPreferences() {
        lastFolderPath = userDefaults.string(forKey: lastFolderPathKey)
        lastFolderBookmark = userDefaults.data(forKey: lastFolderBookmarkKey)
    }
}
