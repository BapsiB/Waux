import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'; // Needed for RawKeyboardListener
import 'package:flutter/services.dart'; // Needed for LogicalKeyboardKey and HardwareKeyboard
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audio_looker/blocs/collection/collection_bloc.dart';
import 'package:audio_looker/blocs/audio_player/audio_player_bloc.dart';
import 'package:audio_looker/services/collection_service.dart';
import 'package:audio_looker/widgets/audio_player_widget.dart';
import 'package:path_provider/path_provider.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as pathLib;
import 'package:audio_looker/widgets/folder_tree_view.dart';
import 'package:audio_looker/widgets/track_table_row.dart'; // Import the new row widget

// Define view mode enum
enum ViewMode { list, tree } // 'list' now means table view

// --- Sorting State ---
enum SortColumn { preview, title, artist, album, rating, tags }

enum SortDirection { ascending, descending }

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  Track? _selectedTrackForPlayer; // Renamed for clarity
  bool _isPlayerMinimized = false;

  // View mode state
  ViewMode _viewMode = ViewMode.list; // Default to table view

  // Drag and drop state
  bool _isDragging = false;
  final List<String> _supportedExtensions = [
    'mp3',
    'wav',
    'ogg',
    'm4a',
    'aac',
    'flac',
  ];

  // Animation controller for the player
  late AnimationController _animationController;
  late Animation<double> _playerHeightAnimation;

  // --- Table State ---
  SortColumn _sortColumn = SortColumn.title; // Default sort
  SortDirection _sortDirection = SortDirection.ascending;
  final Set<int> _selectedTrackIds = {}; // Store IDs of selected tracks
  int? _anchorTrackId; // For shift-click selection

  // Focus node for keyboard events
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    context.read<CollectionBloc>().add(LoadCollection());
    _searchController.addListener(_onSearchChanged);
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _playerHeightAnimation = Tween<double>(begin: 490, end: 100).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    )..addListener(() => setState(() {}));

    // Request focus for keyboard events
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_focusNode);
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _urlController.dispose();
    _animationController.dispose();
    _focusNode.dispose(); // Dispose focus node
    super.dispose();
  }

  void _onSearchChanged() {
    context.read<CollectionBloc>().add(
      SearchCollection(_searchController.text),
    );
    // Clear selection on search
    setState(() {
      _selectedTrackIds.clear();
      _selectedTrackForPlayer = null;
      _anchorTrackId = null;
    });
  }

  void _togglePlayerSize() {
    setState(() {
      _isPlayerMinimized = !_isPlayerMinimized;
      if (_isPlayerMinimized) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  void _toggleViewMode() {
    setState(() {
      _viewMode = _viewMode == ViewMode.list ? ViewMode.tree : ViewMode.list;
      // Clear selection when switching views
      _selectedTrackIds.clear();
      _selectedTrackForPlayer = null;
      _anchorTrackId = null;
    });
  }

  // --- File/Folder Handling (Assumed to be correct from previous steps) ---
  Future<void> _processFile(String filePath) async {
    context.read<CollectionBloc>().add(AddTracksFromPaths([filePath]));
  }

  Future<void> _processDirectory(String dirPath) async {
    debugPrint("Processing directory: $dirPath");
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        /* ... error handling ... */
        return;
      }
      List<String> audioFilePaths = [];
      await _findAudioFilesRecursively(dir, audioFilePaths);
      if (audioFilePaths.isEmpty) {
        /* ... error handling ... */
        return;
      }
      context.read<CollectionBloc>().add(AddTracksFromPaths(audioFilePaths));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Adding ${audioFilePaths.length} files...")),
      );
    } catch (e, stackTrace) {
      /* ... error handling ... */
    }
  }

  Future<void> _findAudioFilesRecursively(
    Directory dir,
    List<String> audioFilePaths,
  ) async {
    try {
      await for (final entity in dir.list()) {
        if (entity is File) {
          final extension = pathLib
              .extension(entity.path)
              .toLowerCase()
              .replaceAll('.', '');
          if (_supportedExtensions.contains(extension))
            audioFilePaths.add(entity.path);
        } else if (entity is Directory) {
          await _findAudioFilesRecursively(entity, audioFilePaths);
        }
      }
    } catch (e) {
      debugPrint("Error listing directory: $e");
    }
  }

  Future<void> _handleDroppedFiles(List<DropItem> items) async {
    debugPrint("Paths dropped: ${items.length} items");
    if (items.isEmpty) {
      /* ... */
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Processing dropped items...")),
    );
    List<String> filesToAdd = [];
    List<String> foldersToProcess = [];
    for (final item in items) {
      final path = item.path;
      try {
        if (path.startsWith("web:")) {
          filesToAdd.add(path);
          continue;
        }
        if (await FileSystemEntity.isDirectory(path)) {
          context.read<CollectionBloc>().add(AddRootFolder(path));
          foldersToProcess.add(path);
        } else if (await FileSystemEntity.isFile(path)) {
          final extension = pathLib
              .extension(item.path)
              .toLowerCase()
              .replaceFirst('.', '');
          if (_supportedExtensions.contains(extension)) filesToAdd.add(path);
        }
      } catch (e, stackTrace) {
        /* ... error handling ... */
      }
    }
    if (filesToAdd.isNotEmpty) {
      context.read<CollectionBloc>().add(AddTracksFromPaths(filesToAdd));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Added ${filesToAdd.length} files")),
      );
    }
    for (final folderPath in foldersToProcess) {
      await _processDirectory(folderPath);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Added '$folderPath' as root")));
    }
  }

  Future<void> _pickAndAddFolder() async {
    try {
      final result = await FilePicker.platform.getDirectoryPath();
      if (result != null) {
        context.read<CollectionBloc>().add(AddRootFolder(result));
        await _processDirectory(result);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Added '$result' as root")));
      }
    } catch (e) {
      /* ... error handling ... */
    }
  }

  Future<void> _pickAndAddAudioFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: true,
        allowedExtensions: _supportedExtensions,
      );
      if (result != null && result.files.isNotEmpty) {
        List<String> filePathsToAdd = [];
        for (final file in result.files) {
          if (file.path != null) {
            filePathsToAdd.add(file.path!);
          } else if (file.bytes != null) {
            final tempDir = await getTemporaryDirectory();
            final tempFile = File('${tempDir.path}/${file.name}');
            await tempFile.writeAsBytes(file.bytes!);
            filePathsToAdd.add(tempFile.path);
          }
        }
        if (filePathsToAdd.isNotEmpty) {
          context.read<CollectionBloc>().add(
            AddTracksFromPaths(filePathsToAdd),
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Adding ${filePathsToAdd.length} files...")),
          );
        }
      }
    } catch (e, stackTrace) {
      /* ... error handling ... */
    }
  }

  void _showAddUrlDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(/* ... URL Dialog ... */),
    );
  }
  // --- End File/Folder Handling ---

  // --- Sorting Logic ---
  void _onSort(SortColumn column) {
    // Allow sorting only for non-preview columns
    if (column == SortColumn.preview) return;

    setState(() {
      if (_sortColumn == column) {
        _sortDirection =
            _sortDirection == SortDirection.ascending
                ? SortDirection.descending
                : SortDirection.ascending;
      } else {
        _sortColumn = column;
        _sortDirection = SortDirection.ascending;
      }
    });
  }

  List<Track> _sortTracks(List<Track> tracks) {
    tracks.sort((a, b) {
      int comparison = 0;
      switch (_sortColumn) {
        case SortColumn.title:
          comparison = a.title.toLowerCase().compareTo(b.title.toLowerCase());
          break;
        case SortColumn.artist:
          comparison = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
          break;
        case SortColumn.album:
          comparison = a.album.toLowerCase().compareTo(b.album.toLowerCase());
          break;
        case SortColumn.rating:
          comparison = a.rating.compareTo(b.rating);
          break;
        case SortColumn.preview: // No standard sort for preview
          break;
        default:
          break;
      }
      // Apply secondary sort by title if primary comparison is equal
      if (comparison == 0 && _sortColumn != SortColumn.title) {
        comparison = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      }

      return _sortDirection == SortDirection.ascending
          ? comparison
          : -comparison;
    });
    return tracks;
  }
  // --- End Sorting Logic ---

  // --- Selection Logic ---
  void _handleRowTap(
    int trackId,
    List<Track> currentSortedTracks, {
    bool isShiftPressed = false,
    bool isCtrlPressed = false,
  }) {
    setState(() {
      if (isCtrlPressed) {
        // Toggle selection for the clicked row
        if (_selectedTrackIds.contains(trackId)) {
          _selectedTrackIds.remove(trackId);
          // If the deselected track was the anchor, clear the anchor
          if (_anchorTrackId == trackId) _anchorTrackId = null;
        } else {
          _selectedTrackIds.add(trackId);
          _anchorTrackId = trackId; // Set anchor on add
        }
      } else if (isShiftPressed && _anchorTrackId != null) {
        // Select range from anchor to clicked row
        final anchorIndex = currentSortedTracks.indexWhere(
          (t) => t.id == _anchorTrackId,
        );
        final clickedIndex = currentSortedTracks.indexWhere(
          (t) => t.id == trackId,
        );

        if (anchorIndex != -1 && clickedIndex != -1) {
          final startIndex =
              anchorIndex < clickedIndex ? anchorIndex : clickedIndex;
          final endIndex =
              anchorIndex > clickedIndex ? anchorIndex : clickedIndex;

          _selectedTrackIds
              .clear(); // Clear previous selection for range select
          for (int i = startIndex; i <= endIndex; i++) {
            // Ensure index is within bounds before accessing
            if (i >= 0 &&
                i < currentSortedTracks.length &&
                currentSortedTracks[i].id != null) {
              _selectedTrackIds.add(currentSortedTracks[i].id!);
            }
          }
        } else {
          // Fallback to single selection if indices are invalid
          _selectedTrackIds.clear();
          _selectedTrackIds.add(trackId);
          _anchorTrackId = trackId;
        }
      } else {
        // Single selection
        _selectedTrackIds.clear();
        _selectedTrackIds.add(trackId);
        _anchorTrackId = trackId; // Update anchor on single select
      }

      // Update the player only if exactly one track is selected
      if (_selectedTrackIds.length == 1) {
        final selectedId = _selectedTrackIds.first;
        final collectionState = context.read<CollectionBloc>().state;
        if (collectionState is CollectionLoaded) {
          try {
            _selectedTrackForPlayer = collectionState.tracks.firstWhere(
              (t) => t.id == selectedId,
            );
            if (_isPlayerMinimized) _togglePlayerSize();
          } catch (e) {
            _selectedTrackForPlayer = null;
          }
        } else {
          _selectedTrackForPlayer = null;
        }
      } else {
        // Clear player track if multiple or none selected
        _selectedTrackForPlayer = null;
      }
    });
    // Keep focus on the list for keyboard navigation
    FocusScope.of(context).requestFocus(_focusNode);
  }
  // --- End Selection Logic ---

  // --- Context Menu Logic ---
  void _showContextMenu(BuildContext context, Offset tapPosition, Track track) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final bool isTrackSelected = _selectedTrackIds.contains(track.id);

    // Ensure the tapped track is selected before showing the menu for single items
    if (!_selectedTrackIds.contains(track.id)) {
      setState(() {
        _selectedTrackIds.clear();
        _selectedTrackIds.add(track.id!);
        _anchorTrackId = track.id;
        // Update player if needed
        if (_selectedTrackIds.length == 1) {
          final collectionState = context.read<CollectionBloc>().state;
          if (collectionState is CollectionLoaded) {
            try {
              _selectedTrackForPlayer = collectionState.tracks.firstWhere(
                (t) => t.id == track.id,
              );
            } catch (e) {
              _selectedTrackForPlayer = null;
            }
          } else {
            _selectedTrackForPlayer = null;
          }
        } else {
          _selectedTrackForPlayer = null;
        }
      });
    }

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(tapPosition.dx, tapPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry>[
        PopupMenuItem(
          value: 'play',
          enabled:
              _selectedTrackIds.length ==
              1, // Only enable play for single selection
          child: ListTile(leading: Icon(Icons.play_arrow), title: Text('Play')),
        ),
        PopupMenuItem(
          value: 'edit',
          enabled:
              _selectedTrackIds.length ==
              1, // Only enable edit for single selection
          child: ListTile(
            leading: Icon(Icons.edit),
            title: Text('Edit Metadata'),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_outline, color: Colors.red),
            title: Text(
              _selectedTrackIds.length > 1
                  ? 'Delete ${_selectedTrackIds.length} Items'
                  : 'Delete from Collection',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ),
      ],
    ).then((value) {
      // Handle selected menu item
      if (value == 'play' && _selectedTrackIds.length == 1) {
        final trackToPlay = _getTrackById(_selectedTrackIds.first);
        if (trackToPlay != null) {
          _playPreview(trackToPlay); // Use existing play logic
        }
      } else if (value == 'edit' && _selectedTrackIds.length == 1) {
        // TODO: Implement metadata editing popup/screen for _selectedTrackIds.first
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Edit metadata action (not implemented yet)'),
          ),
        );
      } else if (value == 'delete') {
        _confirmAndDeleteSelected();
      }
    });
  }

  // Helper to get track by ID from current state
  Track? _getTrackById(int id) {
    final state = context.read<CollectionBloc>().state;
    if (state is CollectionLoaded) {
      try {
        return state.tracks.firstWhere((t) => t.id == id);
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  // Helper to confirm and delete selected tracks
  void _confirmAndDeleteSelected() {
    if (_selectedTrackIds.isEmpty) return;

    final count = _selectedTrackIds.length;
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Confirm Delete'),
          content: Text(
            'Are you sure you want to remove $count item(s) from your collection?',
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              child: Text('Delete', style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                final collectionBloc = context.read<CollectionBloc>();
                // Dispatch delete events for all selected tracks
                final idsToDelete = List<int>.from(
                  _selectedTrackIds,
                ); // Copy IDs before clearing
                for (final trackId in idsToDelete) {
                  collectionBloc.add(RemoveTrack(trackId));
                }
                // Clear selection state
                setState(() {
                  _selectedTrackIds.clear();
                  _selectedTrackForPlayer = null;
                  _anchorTrackId = null;
                });
              },
            ),
          ],
        );
      },
    );
  }
  // --- End Context Menu Logic ---

  // --- Play Preview Logic ---
  void _playPreview(Track track) {
    print("Play preview/action for: ${track.title}");
    // Select the track if not already selected (might be triggered from context menu)
    if (!_selectedTrackIds.contains(track.id)) {
      // Need the current track list to handle selection properly
      final state = context.read<CollectionBloc>().state;
      List<Track> currentTracks = [];
      if (state is CollectionLoaded) {
        currentTracks =
            _viewMode == ViewMode.list
                ? _sortTracks(List.from(state.tracks))
                : state.tracks;
      }
      _handleRowTap(track.id!, currentTracks);
    }
    // Load and play the track in the main player
    context.read<AudioPlayerBloc>().add(
      LoadAudio(source: track.path, isUrl: track.isUrl),
    );
    Future.delayed(const Duration(milliseconds: 100), () {
      context.read<AudioPlayerBloc>().add(PlayAudio());
    });
    if (_isPlayerMinimized) _togglePlayerSize();
  }
  // --- End Play Preview Logic ---

  @override
  Widget build(BuildContext context) {
    // Use RawKeyboardListener to capture key events for selection
    return RawKeyboardListener(
      focusNode: _focusNode,
      onKey: (RawKeyEvent event) {
        // This listener might be too high level. Key handling for selection
        // is better managed closer to the list/tap detection.
        // We now get the state directly in _buildTableView.
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Audio Looker'),
          actions: [
            IconButton(
              icon: Icon(
                _viewMode == ViewMode.list ? Icons.folder : Icons.table_rows,
              ),
              onPressed: _toggleViewMode,
              tooltip:
                  _viewMode == ViewMode.list
                      ? 'Switch to folder view'
                      : 'Switch to table view',
            ),
            IconButton(
              icon: const Icon(Icons.link),
              onPressed: _showAddUrlDialog,
              tooltip: 'Add from URL',
            ),
            IconButton(
              icon: const Icon(Icons.folder),
              onPressed: _pickAndAddFolder,
              tooltip: 'Add folder',
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _pickAndAddAudioFile,
              tooltip: 'Add audio file(s)',
            ),
          ],
        ),
        body: Column(
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search your collection...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),

            // Collection content area
            Expanded(
              child: DropTarget(
                onDragDone:
                    (detail) async => await _handleDroppedFiles(detail.files),
                onDragEntered: (detail) => setState(() => _isDragging = true),
                onDragExited: (detail) => setState(() => _isDragging = false),
                child: Stack(
                  children: [
                    // --- Main Content: Either Table or Tree View ---
                    BlocConsumer<CollectionBloc, CollectionState>(
                      listener: (context, state) {
                        /* ... */
                      },
                      builder: (context, state) {
                        List<Track> tracks = [];
                        List<String> rootFolders = [];
                        String? searchQuery;
                        bool isLoading = false;
                        bool isInitialLoad = false;

                        // Determine state and extract data
                        if (state is CollectionLoading) {
                          isLoading = true;
                          tracks = state.currentTracks ?? [];
                        } else if (state is CollectionLoaded) {
                          isLoading = false;
                          tracks = state.tracks;
                          rootFolders = state.rootFolders;
                          searchQuery = state.searchQuery;
                        } else if (state is CollectionError) {
                          tracks = state.tracks ?? [];
                          return Center(child: Text('Error: ${state.message}'));
                        } else if (state is CollectionInitial) {
                          isLoading = true;
                          isInitialLoad = true;
                        }

                        if (isInitialLoad)
                          return const Center(
                            child: CircularProgressIndicator(
                              color: Colors.brown,
                            ),
                          );
                        if (!isLoading && tracks.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.music_note,
                                  size: 64,
                                  color: Colors.grey,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  searchQuery != null
                                      ? 'No tracks found for "$searchQuery"'
                                      : 'Your collection is empty',
                                  style: const TextStyle(fontSize: 16),
                                ),
                                const SizedBox(height: 24),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.add),
                                      label: const Text('Add Files'),
                                      onPressed: _pickAndAddAudioFile,
                                    ),
                                    const SizedBox(width: 12),
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.folder),
                                      label: const Text('Add Folder'),
                                      onPressed: _pickAndAddFolder,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Or drag and drop files and folders here',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          );
                        }

                        // Sort tracks for table view
                        List<Track> displayedTracks =
                            (_viewMode == ViewMode.list)
                                ? _sortTracks(List.from(tracks)) // Sort a copy
                                : tracks; // Use original order for tree view

                        // Build the appropriate view
                        return Column(
                          children: [
                            Expanded(
                              child: Opacity(
                                opacity: isLoading ? 0.6 : 1.0,
                                child:
                                    _viewMode == ViewMode.list
                                        ? _buildTableView(
                                          displayedTracks,
                                        ) // Pass sorted tracks
                                        : FolderTreeView(
                                          tracks:
                                              displayedTracks, // Pass original/unsorted tracks
                                          rootFolders: rootFolders,
                                          selectedTrack:
                                              _selectedTrackForPlayer,
                                          onTrackSelected: (track) {
                                            setState(() {
                                              _selectedTrackForPlayer = track;
                                              _selectedTrackIds
                                                  .clear(); // Clear table selection
                                              if (track.id != null)
                                                _selectedTrackIds.add(
                                                  track.id!,
                                                );
                                              _anchorTrackId = track.id;
                                              if (_isPlayerMinimized)
                                                _togglePlayerSize();
                                            });
                                          },
                                          onTrackDeleted: (trackId) {
                                            context.read<CollectionBloc>().add(
                                              RemoveTrack(trackId),
                                            );
                                            setState(() {
                                              if (_selectedTrackIds.contains(
                                                trackId,
                                              )) {
                                                _selectedTrackIds.remove(
                                                  trackId,
                                                );
                                                if (_selectedTrackForPlayer
                                                        ?.id ==
                                                    trackId) {
                                                  _selectedTrackForPlayer =
                                                      null;
                                                }
                                                // Reset anchor if it was the deleted item
                                                if (_anchorTrackId == trackId) {
                                                  _anchorTrackId = null;
                                                }
                                              }
                                            });
                                          },
                                        ),
                              ),
                            ),
                            // Audio player
                            if (_selectedTrackForPlayer != null)
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                height: _playerHeightAnimation.value,
                                child: Column(
                                  children: [
                                    Container(
                                      // Toggle button bar
                                      height: 36,
                                      color: Theme.of(
                                        context,
                                      ).primaryColor.withOpacity(0.1),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          IconButton(
                                            icon: Icon(
                                              _isPlayerMinimized
                                                  ? Icons.keyboard_arrow_up
                                                  : Icons.keyboard_arrow_down,
                                            ),
                                            onPressed: _togglePlayerSize,
                                            tooltip:
                                                _isPlayerMinimized
                                                    ? 'Expand player'
                                                    : 'Minimize player',
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: Stack(
                                        children: [
                                          // Full Player
                                          AnimatedOpacity(
                                            opacity:
                                                _isPlayerMinimized ? 0.0 : 1.0,
                                            duration: const Duration(
                                              milliseconds: 200,
                                            ),
                                            child: AudioPlayerWidget(
                                              key: ValueKey(
                                                _selectedTrackForPlayer!.id,
                                              ),
                                              trackId:
                                                  _selectedTrackForPlayer!.id!,
                                              title:
                                                  _selectedTrackForPlayer!
                                                      .title,
                                              artist:
                                                  _selectedTrackForPlayer!
                                                      .artist,
                                              audioSource:
                                                  _selectedTrackForPlayer!.path,
                                              isUrl:
                                                  _selectedTrackForPlayer!
                                                      .isUrl,
                                              rating:
                                                  _selectedTrackForPlayer!
                                                      .rating,
                                              notes:
                                                  _selectedTrackForPlayer!
                                                      .comment,
                                              generalTags:
                                                  _selectedTrackForPlayer!
                                                      .generalTags,
                                              onRatingChanged: (rating) {
                                                if (_selectedTrackForPlayer
                                                        ?.id !=
                                                    null) {
                                                  context
                                                      .read<CollectionBloc>()
                                                      .add(
                                                        UpdateTrackRating(
                                                          _selectedTrackForPlayer!
                                                              .id!,
                                                          rating,
                                                        ),
                                                      );
                                                }
                                              },
                                              onNotesChanged: (notes) {
                                                if (_selectedTrackForPlayer
                                                        ?.id !=
                                                    null) {
                                                  context
                                                      .read<CollectionBloc>()
                                                      .add(
                                                        UpdateTrackComment(
                                                          _selectedTrackForPlayer!
                                                              .id!,
                                                          notes,
                                                        ),
                                                      );
                                                }
                                              },
                                            ),
                                          ),
                                          // Minimized Player
                                          AnimatedOpacity(
                                            opacity:
                                                _isPlayerMinimized ? 1.0 : 0.0,
                                            duration: const Duration(
                                              milliseconds: 200,
                                            ),
                                            child: _buildMinimizedPlayer(),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    // Drag overlay
                    if (_isDragging)
                      Container(
                        color: Theme.of(context).primaryColor.withOpacity(0.3),
                        child: Center(
                          child: Container(/* ... Drag text/icon ... */),
                        ),
                      ),
                    // Loading Indicator Overlay
                    BlocBuilder<CollectionBloc, CollectionState>(
                      builder: (context, state) {
                        if (state is CollectionLoading)
                          return Positioned.fill(
                            child: Container(
                              color: Colors.black.withOpacity(0.3),
                              child: const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(
                                      color: Colors.white,
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'Processing audio...',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        return const SizedBox.shrink();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Build Table View ---
  Widget _buildTableView(List<Track> tracks) {
    // Get current keyboard state directly here for accurate state during build/tap
    final keyState = HardwareKeyboard.instance; // Use HardwareKeyboard.instance
    final bool isShiftPressed = keyState.isShiftPressed;
    final bool isCtrlPressed =
        keyState.isControlPressed || keyState.isMetaPressed;

    return Column(
      children: [
        _buildTableHeader(),
        Expanded(
          child: ListView.builder(
            itemCount: tracks.length,
            itemBuilder: (context, index) {
              final track = tracks[index];
              // Ensure track.id is not null before using it
              if (track.id == null) {
                print("Warning: Track at index $index has null ID.");
                return const SizedBox.shrink(); // Skip rendering if ID is null
              }
              final isSelected = _selectedTrackIds.contains(track.id!);

              return GestureDetector(
                onSecondaryTapDown:
                    (details) => _showContextMenu(
                      context,
                      details.globalPosition,
                      track,
                    ),
                // Use onTap directly on GestureDetector
                onTap:
                    () => _handleRowTap(
                      track.id!,
                      tracks, // Pass the currently displayed (sorted) list
                      isShiftPressed: isShiftPressed,
                      isCtrlPressed: isCtrlPressed,
                    ),
                child: TrackTableRow(
                  key: ValueKey(track.id), // Add key for efficient updates
                  track: track,
                  isSelected: isSelected,
                  // Remove onTap from TrackTableRow if GestureDetector handles it
                  onTap:
                      () => _handleRowTap(
                        track.id!,
                        tracks,
                        isShiftPressed: isShiftPressed,
                        isCtrlPressed: isCtrlPressed,
                      ),
                  onSecondaryTap:
                      () {}, // Keep for potential fallback, but GestureDetector is primary
                  onPlayPreview: () => _playPreview(track),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // --- Build Table Header ---
  Widget _buildTableHeader() {
    const headerPadding = EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0);
    final headerStyle = Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold);

    Widget buildHeaderCell(
      String title,
      SortColumn column, {
      double? width,
      int flex = 1,
    }) {
      bool isSorting = _sortColumn == column;
      return InkWell(
        onTap: () => _onSort(column), // Click to sort
        child: Container(
          width: width,
          padding: headerPadding,
          decoration: BoxDecoration(
            // Add subtle bottom border to header cells
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 1.0,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: headerStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Show sort icon only for the active sort column
              if (isSorting && column != SortColumn.preview)
                Icon(
                  _sortDirection == SortDirection.ascending
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
                  size: 16,
                ),
            ],
          ),
        ),
      );
    }

    return Container(
      // Removed border here, applied to cells instead
      color: Theme.of(
        context,
      ).splashColor.withOpacity(0.5), // Subtle background for header row
      child: Row(
        children: [
          // Fixed width columns
          buildHeaderCell('Preview', SortColumn.preview, width: 150),

          // Flexible columns - Adjusted flex values
          Expanded(
            flex: 4,
            child: buildHeaderCell('Title', SortColumn.title),
          ), // Increased Title flex
          Expanded(
            flex: 3,
            child: buildHeaderCell('Artist', SortColumn.artist),
          ), // Increased Artist flex
          Expanded(
            flex: 3,
            child: buildHeaderCell('Album', SortColumn.album),
          ), // Increased Album flex
          buildHeaderCell('Rating', SortColumn.rating, width: 100),
          Expanded(
            flex: 3,
            child: buildHeaderCell('Tags', SortColumn.tags),
          ), // Increased Tags flex
        ],
      ),
    );
  }

  // Minimized player view
  Widget _buildMinimizedPlayer() {
    if (_selectedTrackForPlayer == null) return const SizedBox.shrink();
    // Simplified - actual layout needed
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              _selectedTrackForPlayer!.title,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Add basic controls if needed
        ],
      ),
    );
  }
}
