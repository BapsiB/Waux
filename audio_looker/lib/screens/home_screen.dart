import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart'; // Needed for LogicalKeyboardKey and HardwareKeyboard
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import 'package:data_table_2/data_table_2.dart'; // Import data_table_2
import 'package:audio_looker/blocs/collection/collection_bloc.dart';
import 'package:audio_looker/blocs/audio_player/audio_player_bloc.dart';
import 'package:audio_looker/services/collection_service.dart';
import 'package:audio_looker/widgets/audio_player_widget.dart';
import 'package:path_provider/path_provider.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as pathLib;
import 'package:audio_looker/widgets/folder_tree_view.dart';
// We still need WaveformPreviewCell from track_table_row.dart
// Assuming track_table_row.dart now only exports WaveformPreviewCell or is refactored
import 'package:audio_looker/widgets/track_table_row.dart'
    show WaveformPreviewCell;

// Define view mode enum
enum ViewMode { list, tree } // 'list' now means table view

// --- Sorting State ---
// Keep the enum, mapping will happen to column index
enum SortColumn { preview, title, artist, album, rating, tags }

enum SortDirection { ascending, descending }

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  // --- State Variables ---
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  Track? _selectedTrackForPlayer; // Track currently loaded in the player
  bool _isPlayerMinimized =
      false; // State of the player widget (full/minimized)
  ViewMode _viewMode = ViewMode.list; // Current view mode (table or tree)
  bool _isDragging = false; // Flag for drag-and-drop overlay
  final List<String> _supportedExtensions = [
    // Supported audio file types
    'mp3', 'wav', 'ogg', 'm4a', 'aac', 'flac',
  ];
  late AnimationController
  _animationController; // For player minimize/expand animation
  late Animation<double> _playerHeightAnimation;

  // --- Table State ---
  SortColumn _sortColumn = SortColumn.title; // Default sort column
  SortDirection _sortDirection =
      SortDirection.ascending; // Default sort direction
  final Set<int> _selectedTrackIds =
      {}; // Store IDs of selected tracks in the table
  int? _anchorTrackId; // Track ID where shift-selection range starts

  final FocusNode _focusNode =
      FocusNode(); // To capture keyboard events for the table

  // Map SortColumn enum to DataTable2 column index for sorting state
  // IMPORTANT: This mapping MUST match the order of DataColumn2 definitions
  final Map<SortColumn, int> _sortColumnToIndex = {
    SortColumn.preview: 0,
    SortColumn.title: 1,
    SortColumn.artist: 2,
    SortColumn.album: 3,
    SortColumn.rating: 4,
    SortColumn.tags: 5,
  };

  // --- Lifecycle Methods ---
  @override
  void initState() {
    super.initState();
    // Load initial collection data
    context.read<CollectionBloc>().add(LoadCollection());
    // Listen for search text changes
    _searchController.addListener(_onSearchChanged);
    // Setup animation controller for player height
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _playerHeightAnimation = Tween<double>(begin: 490, end: 100).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    )..addListener(() => setState(() {})); // Rebuild on animation change
    // Request focus after the first frame to enable keyboard interactions
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => FocusScope.of(context).requestFocus(_focusNode),
    );
  }

  @override
  void dispose() {
    // Dispose controllers and focus node to prevent memory leaks
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _urlController.dispose();
    _animationController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // --- UI Event Handlers ---
  void _onSearchChanged() {
    // Dispatch search event to CollectionBloc
    context.read<CollectionBloc>().add(
      SearchCollection(_searchController.text),
    );
    // Clear selection when search query changes
    setState(() {
      _selectedTrackIds.clear();
      _selectedTrackForPlayer = null;
      _anchorTrackId = null;
    });
  }

  void _togglePlayerSize() {
    // Animate player minimize/expand
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
    // Switch between table and tree view
    setState(() {
      _viewMode = _viewMode == ViewMode.list ? ViewMode.tree : ViewMode.list;
      // Clear selection when switching views
      _selectedTrackIds.clear();
      _selectedTrackForPlayer = null;
      _anchorTrackId = null;
    });
  }

  // --- File/Folder Handling Methods ---
  // (Implementations assumed correct from previous steps)
  Future<void> _processFile(String filePath) async {
    context.read<CollectionBloc>().add(AddTracksFromPaths([filePath]));
    debugPrint("Processing single file: $filePath");
  }

  Future<void> _processDirectory(String dirPath) async {
    debugPrint("Processing directory: $dirPath");
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Directory not found: $dirPath")),
        );
        return;
      }
      List<String> audioFilePaths = [];
      await _findAudioFilesRecursively(dir, audioFilePaths);
      if (audioFilePaths.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("No supported audio files found in folder."),
          ),
        );
        return;
      }
      context.read<CollectionBloc>().add(AddTracksFromPaths(audioFilePaths));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Adding ${audioFilePaths.length} files from $dirPath...",
          ),
        ),
      );
    } catch (e, stackTrace) {
      debugPrint("Error processing folder: $e\n$stackTrace");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error processing folder: $e")));
    }
  }

  Future<void> _findAudioFilesRecursively(
    Directory dir,
    List<String> audioFilePaths,
  ) async {
    try {
      await for (final entity in dir.list(
        recursive: false,
        followLinks: false,
      )) {
        // Avoid infinite loops with links, don't recurse automatically
        try {
          if (entity is File) {
            final extension = pathLib
                .extension(entity.path)
                .toLowerCase()
                .replaceAll('.', '');
            if (_supportedExtensions.contains(extension)) {
              audioFilePaths.add(entity.path);
              // debugPrint("Found file: ${entity.path}");
            }
          } else if (entity is Directory) {
            // Manually recurse into subdirectories
            await _findAudioFilesRecursively(entity, audioFilePaths);
          }
        } catch (e) {
          debugPrint(
            "Error processing entity ${entity.path}: $e",
          ); // Log errors for specific files/folders
        }
      }
    } catch (e) {
      debugPrint("Error listing directory ${dir.path}: $e");
    }
  }

  Future<void> _handleDroppedFiles(List<DropItem> items) async {
    debugPrint("Items dropped: ${items.length}");
    if (items.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Processing dropped items...")),
    );
    List<String> filesToAdd = [];
    List<String> foldersToProcess = [];
    for (final item in items) {
      final path = item.path;
      try {
        debugPrint("Processing dropped path: $path");
        if (path.startsWith("web:")) {
          filesToAdd.add(path);
          continue;
        } // Handle web URLs if necessary

        // Use FileSystemEntity.typeSync for potentially faster checks on desktop
        // Note: typeSync can throw if path doesn't exist or permissions are insufficient
        var type = await FileSystemEntity.type(path, followLinks: false);

        if (type == FileSystemEntityType.directory) {
          context.read<CollectionBloc>().add(AddRootFolder(path));
          foldersToProcess.add(path);
        } else if (type == FileSystemEntityType.file) {
          final extension = pathLib
              .extension(item.path)
              .toLowerCase()
              .replaceFirst('.', '');
          if (_supportedExtensions.contains(extension)) {
            filesToAdd.add(path);
          } else {
            debugPrint("Skipping unsupported file type: $path");
          }
        } else {
          debugPrint(
            "Skipping unsupported or inaccessible path: $path (Type: $type)",
          );
        }
      } catch (e, stackTrace) {
        debugPrint(
          "Error checking dropped path type for $path: $e\n$stackTrace",
        );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error processing item: $path")));
      }
    }
    if (filesToAdd.isNotEmpty) {
      context.read<CollectionBloc>().add(AddTracksFromPaths(filesToAdd));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Adding ${filesToAdd.length} dropped files...")),
      );
    }
    for (final folderPath in foldersToProcess) {
      await _processDirectory(
        folderPath,
      ); // Process folders after adding them as root
      // Notification for adding root folder is now inside _processDirectory/pickFolder
    }
  }

  Future<void> _pickAndAddFolder() async {
    try {
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Folder to Add',
      );
      if (result != null) {
        context.read<CollectionBloc>().add(AddRootFolder(result));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Added '${pathLib.basename(result)}' as root folder.",
            ),
          ),
        );
        await _processDirectory(result); // Scan the added folder
      }
    } catch (e) {
      debugPrint("Error picking folder: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error selecting folder: $e")));
    }
  }

  Future<void> _pickAndAddAudioFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: true,
        allowedExtensions: _supportedExtensions,
        dialogTitle: 'Select Audio Files',
      );
      if (result != null && result.files.isNotEmpty) {
        List<String> filePathsToAdd = [];
        for (final file in result.files) {
          if (file.path != null) {
            filePathsToAdd.add(file.path!);
          } else if (file.bytes != null) {
            // Handle files picked without a direct path (e.g., web)
            final tempDir = await getTemporaryDirectory();
            final tempFile = File('${tempDir.path}/${file.name}');
            await tempFile.writeAsBytes(file.bytes!);
            filePathsToAdd.add(tempFile.path);
            debugPrint(
              "Handled file from bytes: ${file.name} -> ${tempFile.path}",
            );
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
      debugPrint("Error picking file(s): $e\n$stackTrace");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error selecting file(s): $e")));
    }
  }

  void _showAddUrlDialog() {
    _urlController.clear(); // Clear previous entry
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Add Audio from URL'),
            content: TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                hintText: 'Enter audio URL (e.g., http://.../track.mp3)',
              ),
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  if (_urlController.text.isNotEmpty &&
                      Uri.tryParse(_urlController.text)?.hasAbsolutePath ==
                          true) {
                    context.read<CollectionBloc>().add(
                      AddTrackFromUrl(_urlController.text.trim()),
                    );
                    Navigator.of(context).pop();
                  } else {
                    // Optional: Show validation error
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Please enter a valid URL."),
                      ),
                    );
                  }
                },
                child: const Text('Add'),
              ),
            ],
          ),
    );
  }
  // --- End File/Folder Handling ---

  // --- Sorting Logic ---
  void _onSort(SortColumn column) {
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
      _selectedTrackIds.clear();
      _selectedTrackForPlayer = null;
      _anchorTrackId = null; // Clear selection on sort
    });
  }

  List<Track> _sortTracks(List<Track> tracks) {
    // Create a copy to avoid modifying the original list from the BLoC state
    List<Track> sortedTracks = List.from(tracks);
    sortedTracks.sort((a, b) {
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
        case SortColumn.tags:
          String aTag =
              a.generalTags.isNotEmpty
                  ? a.generalTags.join(',').toLowerCase()
                  : '\uffff'; // Sort by joined tags
          String bTag =
              b.generalTags.isNotEmpty
                  ? b.generalTags.join(',').toLowerCase()
                  : '\uffff';
          comparison = aTag.compareTo(bTag);
          break;
        case SortColumn.preview:
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
    return sortedTracks;
  }
  // --- End Sorting Logic ---

  // --- Selection Logic ---
  void _handleSelectChanged(
    bool? selected,
    int trackId,
    List<Track> currentSortedTracks,
  ) {
    final keyState = HardwareKeyboard.instance;
    final bool isShiftPressed = keyState.isShiftPressed;
    final bool isCtrlPressed =
        keyState.isControlPressed || keyState.isMetaPressed;

    setState(() {
      if (selected == true) {
        if (isCtrlPressed) {
          // Ctrl/Cmd + Click: Toggle single item
          if (_selectedTrackIds.contains(trackId)) {
            _selectedTrackIds.remove(trackId);
            if (_anchorTrackId == trackId) _anchorTrackId = null;
          } else {
            _selectedTrackIds.add(trackId);
            _anchorTrackId = trackId; // Set new anchor on add
          }
        } else if (isShiftPressed && _anchorTrackId != null) {
          // Shift + Click: Select range
          final anchorIndex = currentSortedTracks.indexWhere(
            (t) => t.id == _anchorTrackId,
          );
          final clickedIndex = currentSortedTracks.indexWhere(
            (t) => t.id == trackId,
          );
          if (anchorIndex != -1 && clickedIndex != -1) {
            final start =
                anchorIndex < clickedIndex ? anchorIndex : clickedIndex;
            final end = anchorIndex > clickedIndex ? anchorIndex : clickedIndex;
            // Keep existing selection if Ctrl/Cmd is also held? (Standard behavior varies)
            // For simplicity, Shift overrides Ctrl here and replaces selection.
            _selectedTrackIds.clear();
            for (int i = start; i <= end; i++) {
              if (i >= 0 &&
                  i < currentSortedTracks.length &&
                  currentSortedTracks[i].id != null) {
                _selectedTrackIds.add(currentSortedTracks[i].id!);
              }
            }
          } else {
            // Fallback if anchor/clicked index invalid
            _selectedTrackIds.clear();
            _selectedTrackIds.add(trackId);
            _anchorTrackId = trackId;
          }
        } else {
          // Simple Click: Select only this item
          _selectedTrackIds.clear();
          _selectedTrackIds.add(trackId);
          _anchorTrackId = trackId;
        }
      } else {
        // Deselected (selected == false)
        if (isCtrlPressed) {
          // Ctrl/Cmd + Click: Deselect single item
          _selectedTrackIds.remove(trackId);
          if (_anchorTrackId == trackId) _anchorTrackId = null;
        } else {
          // Simple Deselect (without Ctrl): Typically selects only the clicked item if it wasn't selected,
          // or clears selection if the clicked item *was* the only selected one.
          // But DataTable2 calls onSelectChanged with false only when an already selected item is clicked again (without Ctrl).
          // In this case, we just remove it. If other items were selected, they remain (unless Ctrl was held).
          _selectedTrackIds.remove(trackId);
          if (_anchorTrackId == trackId) _anchorTrackId = null;
          // If the intent was to clear all others on simple deselect, add:
          // if (!isCtrlPressed) { _selectedTrackIds.clear(); _anchorTrackId = null; }
        }
      }

      // Update player state based on new selection
      _updatePlayerSelection();
    });
    FocusScope.of(context).requestFocus(_focusNode);
  }

  // Helper to update the player based on current selection
  void _updatePlayerSelection() {
    if (_selectedTrackIds.length == 1) {
      final selectedId = _selectedTrackIds.first;
      _selectedTrackForPlayer = _getTrackById(selectedId);
      if (_isPlayerMinimized && _selectedTrackForPlayer != null)
        _togglePlayerSize();
    } else {
      _selectedTrackForPlayer = null;
    }
  }
  // --- End Selection Logic ---

  // --- Context Menu Logic ---
  void _showContextMenu(BuildContext context, Offset tapPosition, Track track) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    // If the right-clicked item is NOT part of the current selection,
    // clear the previous selection and select only the clicked item.
    if (!_selectedTrackIds.contains(track.id)) {
      setState(() {
        _selectedTrackIds.clear();
        _selectedTrackIds.add(track.id!);
        _anchorTrackId = track.id;
        _updatePlayerSelection(); // Update player based on this new single selection
      });
    }
    // Now _selectedTrackIds reflects the item(s) the context menu should act upon.

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(tapPosition.dx, tapPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry>[
        PopupMenuItem(
          value: 'play',
          enabled: _selectedTrackIds.length == 1,
          child: ListTile(leading: Icon(Icons.play_arrow), title: Text('Play')),
        ),
        PopupMenuItem(
          value: 'edit',
          enabled: _selectedTrackIds.length == 1,
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
      // Handle actions based on the state of _selectedTrackIds when the menu was shown
      if (value == 'play' && _selectedTrackIds.length == 1) {
        final trackToPlay = _getTrackById(_selectedTrackIds.first);
        if (trackToPlay != null) _playPreview(trackToPlay);
      } else if (value == 'edit' && _selectedTrackIds.length == 1) {
        // TODO: Implement edit for _selectedTrackIds.first
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Edit action (not implemented)')),
        );
      } else if (value == 'delete') {
        _confirmAndDeleteSelected(); // Acts on _selectedTrackIds
      }
    });
  }

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

  void _confirmAndDeleteSelected() {
    if (_selectedTrackIds.isEmpty) return;
    final count = _selectedTrackIds.length;
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Confirm Delete'),
          content: Text(
            'Are you sure you want to remove $count item(s) from your collection? This cannot be undone.',
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
                final idsToDelete = List<int>.from(
                  _selectedTrackIds,
                ); // Copy before clearing state
                for (final trackId in idsToDelete) {
                  collectionBloc.add(RemoveTrack(trackId));
                }
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
    // Ensure track is selected
    if (!_selectedTrackIds.contains(track.id)) {
      final state = context.read<CollectionBloc>().state;
      List<Track> currentTracks = [];
      if (state is CollectionLoaded) {
        currentTracks =
            _viewMode == ViewMode.list
                ? _sortTracks(List.from(state.tracks))
                : state.tracks;
      }
      // Simulate single select
      _handleSelectChanged(true, track.id!, currentTracks);
    } else {
      // If already selected, ensure player is updated (especially if multiple were selected before)
      if (_selectedTrackIds.length != 1) {
        setState(() {
          _selectedTrackIds.clear();
          _selectedTrackIds.add(track.id!);
          _anchorTrackId = track.id;
          _updatePlayerSelection();
        });
      }
    }
    // Load and play
    context.read<AudioPlayerBloc>().add(
      LoadAudio(source: track.path, isUrl: track.isUrl),
    );
    Future.delayed(
      const Duration(milliseconds: 100),
      () => context.read<AudioPlayerBloc>().add(PlayAudio()),
    );
    if (_isPlayerMinimized) _togglePlayerSize();
  }
  // --- End Play Preview Logic ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          // TODO: Add button for column visibility later
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(
              16.0,
              16.0,
              16.0,
              8.0,
            ), // Reduced bottom padding
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search collection...',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ), // Slightly less rounded
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ), // Compact padding
                isDense: true,
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
                      // Optional: Show feedback on state changes like errors
                      if (state is CollectionError) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error: ${state.message}'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
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
                        tracks =
                            state.tracks ?? []; /* Error shown by listener */
                      } else if (state is CollectionInitial) {
                        isLoading = true;
                        isInitialLoad = true;
                      }

                      // Show initial loading indicator
                      if (isInitialLoad)
                        return const Center(child: CircularProgressIndicator());

                      // Show empty state message (only if not loading and tracks are truly empty)
                      if (!isLoading && tracks.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.music_off_outlined,
                                  size: 64,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  searchQuery != null && searchQuery.isNotEmpty
                                      ? 'No tracks found for "$searchQuery"'
                                      : 'Collection is empty',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Add files/folders using the buttons above or drag & drop.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      // Sort tracks only if in table view
                      List<Track> displayedTracks =
                          (_viewMode == ViewMode.list)
                              ? _sortTracks(
                                tracks,
                              ) // Sort the actual list from state
                              : tracks; // Use original order for tree view

                      // Build the appropriate view
                      return Column(
                        children: [
                          Expanded(
                            child: Opacity(
                              opacity:
                                  isLoading
                                      ? 0.6
                                      : 1.0, // Dim content slightly if loading in background
                              child:
                                  _viewMode == ViewMode.list
                                      ? _buildDataTable2(
                                        displayedTracks,
                                      ) // Use DataTable2 builder
                                      : FolderTreeView(
                                        tracks:
                                            displayedTracks, // Pass original/unsorted tracks to tree
                                        rootFolders: rootFolders,
                                        selectedTrack: _selectedTrackForPlayer,
                                        onTrackSelected: (track) {
                                          setState(() {
                                            _selectedTrackForPlayer = track;
                                            _selectedTrackIds.clear();
                                            if (track.id != null)
                                              _selectedTrackIds.add(track.id!);
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
                                              _selectedTrackIds.remove(trackId);
                                              if (_selectedTrackForPlayer?.id ==
                                                  trackId)
                                                _selectedTrackForPlayer = null;
                                              if (_anchorTrackId == trackId)
                                                _anchorTrackId = null;
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
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 8,
                                    offset: const Offset(0, -2),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  Container(
                                    // Toggle button bar
                                    height: 36,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceVariant
                                        .withOpacity(0.5), // Use theme color
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
                                            ), // Ensure player rebuilds on track change
                                            trackId:
                                                _selectedTrackForPlayer!.id!,
                                            title:
                                                _selectedTrackForPlayer!.title,
                                            artist:
                                                _selectedTrackForPlayer!.artist,
                                            audioSource:
                                                _selectedTrackForPlayer!.path,
                                            isUrl:
                                                _selectedTrackForPlayer!.isUrl,
                                            rating:
                                                _selectedTrackForPlayer!.rating,
                                            notes:
                                                _selectedTrackForPlayer!
                                                    .comment,
                                            generalTags:
                                                _selectedTrackForPlayer!
                                                    .generalTags,
                                            onRatingChanged: (rating) {
                                              if (_selectedTrackForPlayer?.id !=
                                                  null)
                                                context
                                                    .read<CollectionBloc>()
                                                    .add(
                                                      UpdateTrackRating(
                                                        _selectedTrackForPlayer!
                                                            .id!,
                                                        rating,
                                                      ),
                                                    );
                                            },
                                            onNotesChanged: (notes) {
                                              if (_selectedTrackForPlayer?.id !=
                                                  null)
                                                context
                                                    .read<CollectionBloc>()
                                                    .add(
                                                      UpdateTrackComment(
                                                        _selectedTrackForPlayer!
                                                            .id!,
                                                        notes,
                                                      ),
                                                    );
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
                                          child:
                                              _buildMinimizedPlayer(), // Build minimized view
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
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withOpacity(0.1),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 30,
                            vertical: 20,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.file_download_outlined,
                                size: 48,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'Drop Audio Files or Folders Here',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  // Loading Indicator Overlay
                  BlocBuilder<CollectionBloc, CollectionState>(
                    builder: (context, state) {
                      if (state is CollectionLoading) {
                        return Positioned.fill(
                          child: Container(
                            color: Colors.black.withOpacity(
                              0.4,
                            ), // Darker overlay
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
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Build Table View using DataTable2 ---
  Widget _buildDataTable2(List<Track> tracks) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return DataTable2(
      // --- Basic Styling & Behavior ---
      columnSpacing: 12,
      horizontalMargin: 12,
      minWidth: 900, // Increased minWidth slightly for tags column
      dataRowHeight: 48,
      headingRowHeight: 40,
      border: TableBorder(
        horizontalInside: BorderSide(
          color: Theme.of(context).dividerColor.withOpacity(0.5),
          width: 0.5,
        ),
      ), // Subtle border
      dividerThickness: 0, // Use border instead of divider
      headingCheckboxTheme: CheckboxThemeData(
        // Style header checkbox if shown (not used here)
        checkColor: MaterialStateProperty.all(colorScheme.onPrimary),
        fillColor: MaterialStateProperty.all(colorScheme.primary),
      ),
      datarowCheckboxTheme: CheckboxThemeData(
        // Style row checkboxes if shown (not used here)
        checkColor: MaterialStateProperty.all(colorScheme.onPrimary),
        fillColor: MaterialStateProperty.all(colorScheme.primary),
      ),
      headingTextStyle: textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.bold,
      ), // Style header text
      dataTextStyle: textTheme.bodyMedium, // Style cell text
      showBottomBorder: true, // Add border below header
      // --- Sorting ---
      sortColumnIndex: _sortColumnToIndex[_sortColumn],
      sortAscending: _sortDirection == SortDirection.ascending,

      // --- Columns Definition ---
      columns: [
        DataColumn2(
          label: Text('Preview'),
          tooltip: 'Waveform preview and play',
          fixedWidth: 150,
        ),
        DataColumn2(
          label: Text('Title'),
          size: ColumnSize.L,
          onSort: (i, asc) => _onSort(SortColumn.title),
        ),
        DataColumn2(
          label: Text('Artist'),
          size: ColumnSize.M,
          onSort: (i, asc) => _onSort(SortColumn.artist),
        ),
        DataColumn2(
          label: Text('Album'),
          size: ColumnSize.M,
          onSort: (i, asc) => _onSort(SortColumn.album),
        ),
        DataColumn2(
          label: Text('Rating'),
          fixedWidth: 100,
          numeric: true,
          onSort: (i, asc) => _onSort(SortColumn.rating),
        ),
        DataColumn2(
          label: Text('Tags'),
          size: ColumnSize.M,
          onSort: (i, asc) => _onSort(SortColumn.tags),
        ),
      ],

      // --- Rows Definition ---
      rows: List<DataRow2>.generate(tracks.length, (index) {
        final track = tracks[index];
        // Ensure track ID is not null before proceeding
        if (track.id == null) {
          debugPrint("Error: Track at index $index has null ID, skipping row.");
          // Return an empty row or handle appropriately
          // For now, let's return an empty row to avoid crashing the list generation
          return DataRow2(
            cells: List.generate(6, (_) => DataCell(SizedBox.shrink())),
          );
        }
        final isSelected = _selectedTrackIds.contains(track.id!);

        return DataRow2(
          key: ValueKey(track.id!),
          selected: isSelected,
          onSelectChanged:
              (selected) => _handleSelectChanged(
                selected,
                track.id!,
                tracks,
              ), // Pass sorted list
          onSecondaryTapDown:
              (details) =>
                  _showContextMenu(context, details.globalPosition, track),
          // Apply subtle background color change on selection using MaterialStateProperty
          color: MaterialStateProperty.resolveWith<Color?>((
            Set<MaterialState> states,
          ) {
            if (states.contains(MaterialState.selected)) {
              return colorScheme.primary.withOpacity(
                0.08,
              ); // Subtle primary color tint
            }
            // Optional: Add hover effect
            // if (states.contains(MaterialState.hovered)) {
            //    return Theme.of(context).hoverColor;
            // }
            return null; // Use default (transparent)
          }),
          cells: [
            // Preview Cell
            DataCell(
              SizedBox(
                height: 30,
                child: WaveformPreviewCell(
                  track: track,
                  isSelected: isSelected,
                  onPlayPreview: () => _playPreview(track),
                ),
              ),
            ),
            // Title Cell
            DataCell(
              Text(
                track.title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ), // Bold selected title
            // Artist Cell
            DataCell(Text(track.artist, overflow: TextOverflow.ellipsis)),
            // Album Cell
            DataCell(Text(track.album, overflow: TextOverflow.ellipsis)),
            // Rating Cell
            DataCell(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < track.rating ? Icons.star : Icons.star_border,
                    size: 14,
                    color:
                        i < track.rating
                            ? Colors.amber.shade600
                            : Colors.grey.shade500,
                  ),
                ),
              ),
            ),
            // Tags Cell
            DataCell(
              track.generalTags.isEmpty
                  ? const SizedBox.shrink()
                  : Padding(
                    // Add padding to prevent chips touching cell border
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Wrap(
                      spacing: 4.0,
                      runSpacing: 4.0,
                      children:
                          track.generalTags
                              .map(
                                (tag) => Chip(
                                  label: Text(tag),
                                  labelStyle: TextStyle(
                                    fontSize: 10,
                                    color: colorScheme.onSecondaryContainer,
                                  ), // Use theme color
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 0,
                                  ),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  backgroundColor: colorScheme
                                      .secondaryContainer
                                      .withOpacity(0.6), // Use theme color
                                  side: BorderSide.none,
                                  visualDensity:
                                      VisualDensity
                                          .compact, // Make chips smaller
                                ),
                              )
                              .toList(),
                    ),
                  ),
              showEditIcon: false,
            ),
          ],
        );
      }),
      // Widget to show when the table is empty after filtering/loading
      empty: Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Text(
            _searchController.text.isNotEmpty
                ? 'No tracks found matching "${_searchController.text}".'
                : 'No tracks in collection.', // Should be covered by the main empty state, but good fallback
            style: textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  // Minimized player view
  Widget _buildMinimizedPlayer() {
    if (_selectedTrackForPlayer == null) return const SizedBox.shrink();
    // Provide a basic layout for the minimized player
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      height: double.infinity, // Take full height of its container
      child: Row(
        children: [
          // Album art placeholder or actual image later
          Container(
            width: 40,
            height: 40,
            color: Colors.grey[700],
            child: Icon(Icons.music_note, color: Colors.white70),
          ),
          const SizedBox(width: 12),
          // Track Info
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedTrackForPlayer!.title,
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _selectedTrackForPlayer!.artist,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Basic Controls (Example)
          BlocBuilder<AudioPlayerBloc, AudioPlayerState>(
            builder: (context, playerState) {
              bool isPlaying = false;
              if (playerState is AudioPlayerLoaded && playerState.isPlaying) {
                isPlaying = true;
              }
              return Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.skip_previous),
                    onPressed: () {
                      /* TODO */
                    },
                    tooltip: 'Previous',
                  ),
                  IconButton(
                    icon: Icon(
                      isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                    ),
                    onPressed: () {
                      if (isPlaying) {
                        context.read<AudioPlayerBloc>().add(PauseAudio());
                      } else {
                        context.read<AudioPlayerBloc>().add(PlayAudio());
                      }
                    },
                    tooltip: isPlaying ? 'Pause' : 'Play',
                  ),
                  IconButton(
                    icon: Icon(Icons.skip_next),
                    onPressed: () {
                      /* TODO */
                    },
                    tooltip: 'Next',
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
