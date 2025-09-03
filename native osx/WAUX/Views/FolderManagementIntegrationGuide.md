# Folder Management UI Components Integration Guide

This guide explains how to integrate the folder management UI components into the existing PlaylistSidebar.

## Components Created

### 1. CreateFolderSheet
- **Purpose**: Modal sheet for creating new folders
- **Usage**: Similar to CreatePlaylistSheet
- **Features**: 
  - Text field with validation
  - Support for parent folder context
  - Auto-focus on text field
  - Cancel/Create buttons

### 2. RenameFolderSheet
- **Purpose**: Modal sheet for renaming existing folders
- **Usage**: Similar to RenamePlaylistSheet
- **Features**:
  - Pre-populated with current folder name
  - Text field validation
  - Auto-focus on text field
  - Cancel/Rename buttons

### 3. DeleteFolderConfirmationSheet
- **Purpose**: Confirmation dialog for folder deletion
- **Features**:
  - Shows folder contents count
  - Explains what happens to contents (moved to parent level)
  - Warning icon for visual emphasis
  - Cancel/Delete buttons

### 4. FolderContextMenu
- **Purpose**: Reusable context menu for folder operations
- **Features**:
  - Create Subfolder option
  - Rename option
  - Delete option (destructive style)

### 5. FolderRowView
- **Purpose**: Display component for individual folders
- **Features**:
  - Hierarchical indentation based on depth
  - Expand/collapse chevron for folders with children
  - Folder icon and name
  - Content count display (playlists and subfolders)
  - Integrated context menu

### 6. FolderManagementView
- **Purpose**: Centralized state management for folder operations
- **Features**:
  - Manages all folder-related sheets
  - Handles error states and alerts
  - Provides public methods for triggering operations
  - Uses improved error handling

### 7. FolderErrorHandler
- **Purpose**: Utility for user-friendly error messages
- **Features**:
  - Converts PlaylistError cases to readable messages
  - Provides context-appropriate error descriptions

## Integration Steps

### Step 1: Add FolderManagementView to PlaylistSidebar

```swift
struct PlaylistSidebar: View {
    // ... existing properties
    @StateObject private var folderManagement = FolderManagementView()
    
    var body: some View {
        VStack {
            // ... existing content
        }
        .background(
            FolderManagementView(playlistService: playlistService)
        )
    }
}
```

### Step 2: Update the + Button to Show Dropdown Menu

Replace the simple + button with a dropdown menu:

```swift
Menu {
    Button("Create Playlist") {
        // Existing playlist creation logic
    }
    
    Button("Create Folder") {
        folderManagement.createFolder()
    }
} label: {
    Image(systemName: "plus.circle.fill")
        .font(.system(size: 16, weight: .medium))
        .foregroundColor(AppStyle.mainColor)
}
```

### Step 3: Add Hierarchical Display Logic

Replace the simple playlist list with hierarchical rendering:

```swift
List {
    // Root folders first
    ForEach(rootFolders, id: \.id) { folder in
        FolderRowView(
            folder: folder,
            depth: 0,
            isExpanded: playlistService.folderExpandedStates[folder.id] ?? true,
            playlistCount: getPlaylistCount(in: folder),
            subfolderCount: getSubfolderCount(in: folder),
            onToggleExpansion: { toggleFolderExpansion(folder) },
            onRename: { folderManagement.renameFolder(folder) },
            onDelete: { folderManagement.deleteFolder(folder) },
            onCreateSubfolder: { folderManagement.createFolder(parentFolder: folder) }
        )
        
        // Show contents if expanded
        if playlistService.folderExpandedStates[folder.id] ?? true {
            // Render subfolders and playlists recursively
        }
    }
    
    // Root-level playlists
    ForEach(rootPlaylists, id: \.id) { playlist in
        // Existing playlist row rendering
    }
}
```

### Step 4: Add Helper Methods

Add these helper methods to PlaylistSidebar:

```swift
private var rootFolders: [PlaylistFolder] {
    playlistService.folders.filter { $0.parentFolderId == nil }
}

private var rootPlaylists: [Playlist] {
    playlistService.playlists.filter { $0.folderId == nil }
}

private func getPlaylistCount(in folder: PlaylistFolder) -> Int {
    playlistService.playlists.filter { $0.folderId == folder.id }.count
}

private func getSubfolderCount(in folder: PlaylistFolder) -> Int {
    playlistService.folders.filter { $0.parentFolderId == folder.id }.count
}

private func toggleFolderExpansion(_ folder: PlaylistFolder) {
    let currentState = playlistService.folderExpandedStates[folder.id] ?? true
    playlistService.folderExpandedStates[folder.id] = !currentState
}
```

## Error Handling

The components include comprehensive error handling:

- **Invalid Names**: Empty or whitespace-only names are rejected
- **Folder Not Found**: Handles cases where folders are deleted externally
- **Circular References**: Prevents moving folders into their own descendants
- **Max Depth Exceeded**: Prevents creating folders beyond 10 levels deep
- **Database Errors**: Provides user-friendly messages for database failures

## Requirements Satisfied

This implementation satisfies all requirements from the task:

- ✅ **1.1**: Create folder UI with proper validation
- ✅ **1.2**: Rename folder functionality with error handling
- ✅ **1.4**: Error handling and user feedback for all operations
- ✅ **5.1**: Context menu with rename and delete options
- ✅ **5.2**: Rename dialog implementation
- ✅ **5.3**: Delete confirmation with proper messaging
- ✅ **5.4**: Comprehensive error handling for folder operations

## Next Steps

After integrating these components:

1. Test folder creation, renaming, and deletion
2. Verify error handling works correctly
3. Test with various folder hierarchies
4. Ensure proper integration with existing playlist functionality
5. Add drag-and-drop support (Task 7)
6. Update PlaylistSidebar with hierarchical display (Task 6)