import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
// Import Syncfusion DataGrid (Needed for DataGridSortDirection enum)
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
// Local imports
import 'package:audio_looker/blocs/collection/collection_bloc.dart';
import 'package:audio_looker/blocs/audio_player/audio_player_bloc.dart';
import 'package:audio_looker/services/collection_service.dart';
import 'package:audio_looker/widgets/audio_player_widget.dart';
import 'package:path_provider/path_provider.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as pathLib;
import 'package:audio_looker/widgets/folder_tree_view.dart';
// Import the new TrackTableWidget
import 'package:audio_looker/widgets/track_table_widget.dart';
// Import WaveformPreviewCell if needed elsewhere, otherwise TrackTableWidget handles it
// import 'package:audio_looker/widgets/track_table_row.dart' show WaveformPreviewCell;

// Define view mode enum
enum ViewMode { list, tree } // 'list' now means table view

// --- Sorting State (Managed by HomeScreen, passed to TrackTableWidget) ---
// enum SortColumn { preview, title, artist, album, rating, tags } // Can be removed if defined in track_table_widget.dart
// enum SortDirection { ascending, descending } // Can be removed

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
  Track? _selectedTrackForPlayer;
  bool _isPlayerMinimized = false;
  ViewMode _viewMode = ViewMode.list;
  bool _isDragging = false;
  final List<String> _supportedExtensions = [
    'mp3',
    'wav',
    'ogg',
    'm4a',
    'aac',
    'flac',
  ];
  late AnimationController _animationController;
  late Animation<double> _playerHeightAnimation;

  // --- Grid/Table State (Managed here as source of truth) ---
  String _sortColumnName = 'title'; // Default sort column name
  DataGridSortDirection _sortDirectionSf =
      DataGridSortDirection.ascending; // Use SfDataGrid enum
  final Set<int> _selectedTrackIds = {}; // Canonical list of selected IDs
  int? _anchorTrackId; // Keep for potential advanced selection later

  // Focus node might not be needed here anymore if TrackTableWidget manages its own focus
  // final FocusNode _focusNode = FocusNode();

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
    // WidgetsBinding.instance.addPostFrameCallback((_) => FocusScope.of(context).requestFocus(_focusNode)); // Focus managed by table widget now
  }

  @override
  void dispose() {
    _searchController.dispose();
    _urlController.dispose();
    _animationController.dispose();
    // _focusNode.dispose(); // Dispose if moved to TrackTableWidget
    super.dispose();
  }

  // --- UI Event Handlers ---
  void _onSearchChanged() {
    context.read<CollectionBloc>().add(
      SearchCollection(_searchController.text),
    );
    setState(() {
      _selectedTrackIds.clear();
      _selectedTrackForPlayer = null;
      _anchorTrackId = null;
    });
  }

  void _togglePlayerSize() {
    setState(() {
      _isPlayerMinimized = !_isPlayerMinimized;
      if (_isPlayerMinimized)
        _animationController.forward();
      else
        _animationController.reverse();
    });
  }

  void _toggleViewMode() {
    setState(() {
      _viewMode = _viewMode == ViewMode.list ? ViewMode.tree : ViewMode.list;
      _selectedTrackIds.clear();
      _selectedTrackForPlayer = null;
      _anchorTrackId = null;
    });
  }

  // --- File/Folder Handling Methods (Implementations unchanged) ---
  // Future<void> _processFile(String filePath) async {
  //   context.read<CollectionBloc>().add(AddTracksFromPaths([filePath]));
  // }

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
      // Use list LIFO to process current directory files before recursing
      var entities = await dir.list(followLinks: false).toList();
      List<Directory> subDirs = [];

      for (final entity in entities) {
        try {
          // Use FileSystemEntity.type() for async check
          // var type = await FileSystemEntity.type(entity.path, followLinks: false); // Alternative async check

          // Or use the entity type directly if list() provides typed objects
          // if (entity is File) {
          //   // Direct type check (often works, but use static methods if errors persist)
          //   final extension = pathLib
          //       .extension(entity.path)
          //       .toLowerCase()
          //       .replaceAll('.', '');
          //   if (_supportedExtensions.contains(extension)) {
          //     audioFilePaths.add(entity.path);
          //   }
          // } else if (entity is Directory) {
          //   subDirs.add(entity); // Collect subdirectories
          // }

          // --- USING STATIC METHODS (More Robust) ---
          bool isFile = await FileSystemEntity.isFile(entity.path);
          if (isFile) {
            final extension = pathLib
                .extension(entity.path)
                .toLowerCase()
                .replaceAll('.', '');
            if (_supportedExtensions.contains(extension)) {
              audioFilePaths.add(entity.path);
            }
          } else {
            bool isDir = await FileSystemEntity.isDirectory(entity.path);
            if (isDir) {
              subDirs.add(Directory(entity.path)); // Add as Directory object
            }
          }
          // --- END USING STATIC METHODS ---
        } catch (e) {
          // Log errors for specific file access issues (e.g., permissions)
          debugPrint("Error processing entity ${entity.path}: $e");
        }
      }
      // Recurse into subdirectories *after* processing files in current dir
      for (final subDir in subDirs) {
        await _findAudioFilesRecursively(subDir, audioFilePaths);
      }
    } catch (e) {
      // Log errors for directory listing issues (e.g., permissions)
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
        }
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
      await _processDirectory(folderPath);
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
        await _processDirectory(result);
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
    _urlController.clear();
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

  // --- Sorting Logic (State managed here, sorting done before passing list) ---
  List<Track> _getSortedTracks(List<Track> tracks) {
    List<Track> sortedTracks = List.from(tracks); // Create a copy
    sortedTracks.sort((a, b) {
      int comparison = 0;
      switch (_sortColumnName) {
        // Use the string name from state
        case 'title':
          comparison = a.title.toLowerCase().compareTo(b.title.toLowerCase());
          break;
        case 'artist':
          comparison = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
          break;
        case 'album':
          comparison = a.album.toLowerCase().compareTo(b.album.toLowerCase());
          break;
        case 'rating':
          comparison = a.rating.compareTo(b.rating);
          break;
        case 'tags':
          String aTag =
              a.generalTags.isNotEmpty
                  ? a.generalTags.join(',').toLowerCase()
                  : '\uffff';
          String bTag =
              b.generalTags.isNotEmpty
                  ? b.generalTags.join(',').toLowerCase()
                  : '\uffff';
          comparison = aTag.compareTo(bTag);
          break;
      }
      if (comparison == 0 && _sortColumnName != 'title') {
        comparison = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      }
      return _sortDirectionSf == DataGridSortDirection.ascending
          ? comparison
          : -comparison;
    });
    return sortedTracks;
  }

  // Callback from TrackTableWidget when user clicks a header
  void _handleSortChanged(String columnName, DataGridSortDirection direction) {
    setState(() {
      _sortColumnName = columnName;
      _sortDirectionSf = direction;
      _selectedTrackIds.clear();
      _selectedTrackForPlayer = null;
      _anchorTrackId = null; // Clear selection on sort
    });
    // The list passed to TrackTableWidget will be re-sorted in the next build cycle
  }
  // --- End Sorting Logic ---

  // --- Selection Logic (Handles callbacks from TrackTableWidget) ---
  void _handleSelectionChanged(
    int trackId,
    bool isSelected, {
    bool isShiftPressed = false,
    bool isCtrlPressed = false,
  }) {
    setState(() {
      final List<Track> currentDisplayedTracks =
          _getCurrentDisplayedTracks(); // Get currently sorted list

      if (isSelected) {
        // Row was selected
        if (isCtrlPressed) {
          // Toggle Add
          _selectedTrackIds.add(trackId);
          _anchorTrackId = trackId;
        } else if (isShiftPressed && _anchorTrackId != null) {
          // Range Add
          final anchorIndex = currentDisplayedTracks.indexWhere(
            (t) => t.id == _anchorTrackId,
          );
          final clickedIndex = currentDisplayedTracks.indexWhere(
            (t) => t.id == trackId,
          );
          if (anchorIndex != -1 && clickedIndex != -1) {
            final start =
                anchorIndex < clickedIndex ? anchorIndex : clickedIndex;
            final end = anchorIndex > clickedIndex ? anchorIndex : clickedIndex;
            _selectedTrackIds.clear(); // Shift replaces selection
            for (int i = start; i <= end; i++) {
              if (i >= 0 &&
                  i < currentDisplayedTracks.length &&
                  currentDisplayedTracks[i].id != null) {
                _selectedTrackIds.add(currentDisplayedTracks[i].id!);
              }
            }
          } else {
            // Fallback
            _selectedTrackIds.clear();
            _selectedTrackIds.add(trackId);
            _anchorTrackId = trackId;
          }
        } else {
          // Simple Select
          _selectedTrackIds.clear();
          _selectedTrackIds.add(trackId);
          _anchorTrackId = trackId;
        }
      } else {
        // Row was deselected
        if (isCtrlPressed) {
          // Toggle Remove
          _selectedTrackIds.remove(trackId);
          if (_anchorTrackId == trackId) _anchorTrackId = null;
        } else {
          // Simple Deselect (remove only this one)
          _selectedTrackIds.remove(trackId);
          if (_anchorTrackId == trackId) _anchorTrackId = null;
        }
      }
      _updatePlayerSelection(); // Update player based on final selection
    });
  }

  // Helper to get the currently displayed (and potentially sorted) track list
  List<Track> _getCurrentDisplayedTracks() {
    final state = context.read<CollectionBloc>().state;
    List<Track> tracks = [];
    if (state is CollectionLoaded) {
      tracks = state.tracks;
    } else if (state is CollectionLoading && state.currentTracks != null) {
      tracks = state.currentTracks!;
    }
    // Apply sorting if in list mode
    return _viewMode == ViewMode.list ? _getSortedTracks(tracks) : tracks;
  }

  void _updatePlayerSelection() {
    if (_selectedTrackIds.length == 1) {
      _selectedTrackForPlayer = _getTrackById(_selectedTrackIds.first);
      // Optionally force player to expand when a new single track is selected
      if (_isPlayerMinimized && _selectedTrackForPlayer != null)
        _togglePlayerSize();
    } else {
      _selectedTrackForPlayer = null;
    }
  }
  // --- End Selection Logic ---

  // --- Context Menu Logic (Triggered by TrackTableWidget callback) ---
  void _showContextMenu(BuildContext context, Offset tapPosition, Track track) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    // Selection state is managed by _handleSelectionChanged via callbacks
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
      if (value == 'play' && _selectedTrackIds.length == 1) {
        final trackToPlay = _getTrackById(_selectedTrackIds.first);
        if (trackToPlay != null) _playPreview(trackToPlay);
      } else if (value == 'edit' && _selectedTrackIds.length == 1) {
        // TODO: Implement edit
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Edit action (not implemented)')),
        );
      } else if (value == 'delete') {
        _confirmAndDeleteSelected();
      }
    });
  }

  Track? _getTrackById(int id) {
    // Helper to find track in the *current* BLoC state (unsorted)
    final state = context.read<CollectionBloc>().state;
    List<Track> sourceList = [];
    if (state is CollectionLoaded) {
      sourceList = state.tracks;
    } else if (state is CollectionLoading && state.currentTracks != null) {
      sourceList = state.currentTracks!;
    }
    try {
      return sourceList.firstWhere((t) => t.id == id);
    } catch (e) {
      return null;
    }
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
                final idsToDelete = List<int>.from(_selectedTrackIds);
                for (final trackId in idsToDelete) {
                  collectionBloc.add(RemoveTrack(trackId));
                }
                // Clear selection state after dispatching delete actions
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

  // --- Play Preview Logic (Triggered by TrackTableWidget callback) ---
  void _playPreview(Track track) {
    print("Play preview requested for: ${track.title}");
    // Ensure player state reflects this track
    if (_selectedTrackForPlayer?.id != track.id ||
        _selectedTrackIds.length != 1) {
      setState(() {
        _selectedTrackIds.clear();
        _selectedTrackIds.add(track.id!);
        _anchorTrackId = track.id;
        _selectedTrackForPlayer = track; // Directly set player track
      });
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
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search collection...',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
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
                      /* ... Error listener ... */
                    },
                    builder: (context, state) {
                      List<Track> tracks = [];
                      List<String> rootFolders = [];
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
                      } else if (state is CollectionError) {
                        tracks =
                            state.tracks ?? []; /* Error handled by listener */
                      } else if (state is CollectionInitial) {
                        isLoading = true;
                        isInitialLoad = true;
                      }

                      if (isInitialLoad)
                        return const Center(child: CircularProgressIndicator());
                      // Use helper to get potentially sorted list
                      List<Track> displayedTracks =
                          _getCurrentDisplayedTracks();

                      if (!isLoading && displayedTracks.isEmpty) {
                        // Show empty state (could be due to search)
                        final searchQuery = _searchController.text;
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
                                  searchQuery.isNotEmpty
                                      ? 'No tracks found for "$searchQuery"'
                                      : 'Collection is empty',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  searchQuery.isEmpty
                                      ? 'Add files/folders using the buttons above or drag & drop.'
                                      : '',
                                  style: Theme.of(context).textTheme.bodySmall,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      // Build the appropriate view
                      return Column(
                        children: [
                          Expanded(
                            child: Opacity(
                              opacity: isLoading ? 0.6 : 1.0,
                              child:
                                  _viewMode == ViewMode.list
                                      // --- Instantiate TrackTableWidget ---
                                      ? TrackTableWidget(
                                        // Pass the potentially sorted list
                                        tracks: displayedTracks,
                                        selectedTrackIds: _selectedTrackIds,
                                        onSelectionChanged:
                                            _handleSelectionChanged,
                                        onShowContextMenu: _showContextMenu,
                                        onPlayPreview: _playPreview,
                                        onSort: _handleSortChanged,
                                        initialSortColumnName: _sortColumnName,
                                        initialSortDirection: _sortDirectionSf,
                                      )
                                      : FolderTreeView(
                                        // Pass unsorted list to FolderTreeView
                                        tracks: tracks,
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
