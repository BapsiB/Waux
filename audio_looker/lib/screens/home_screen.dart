// lib/screens/home_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:audio_looker/blocs/collection/collection_bloc.dart';
import 'package:audio_looker/blocs/audio_player/audio_player_bloc.dart'; // Import Bloc
import 'package:audio_looker/services/collection_service.dart';
import 'package:audio_looker/widgets/audio_player_widget.dart';
import 'package:audio_looker/widgets/playlist_drawer.dart';
import 'package:path_provider/path_provider.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as pathLib;
import 'package:audio_looker/widgets/folder_tree_view.dart';
import 'package:audio_looker/widgets/track_table_widget.dart';
import 'package:audio_looker/models/playlist.dart';
import 'package:audio_looker/blocs/playlist/playlist_bloc.dart';

// Define view mode enum
enum ViewMode { list, tree }

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
  bool _isPlayerMinimized = true;
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
  final double _fullPlayerHeight = 490;
  final double _minimizedPlayerHeight = 100;

  // --- Grid/Table State ---
  String _sortColumnName = 'title';
  DataGridSortDirection _sortDirectionSf = DataGridSortDirection.ascending;
  final Set<int> _selectedTrackIds = {};
  int? _anchorTrackId;
  bool _isPlaylistPanelVisible = true;

  String? _currentlySelectedPlaylistId;
  Playlist? _currentlySelectedPlaylist;

  // *** ADDED: State variable to track the currently loaded audio path ***
  String? _currentlyLoadedPath;

  @override
  void initState() {
    super.initState();
    context.read<CollectionBloc>().add(LoadCollection());
    _searchController.addListener(_onSearchChanged);
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _playerHeightAnimation = Tween<double>(
      begin: _fullPlayerHeight,
      end: _minimizedPlayerHeight,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    )..addListener(() => setState(() {}));

    _animationController.value = 1.0;

    // *** ADDED: Listen to AudioPlayerBloc to get the loaded path ***
    // (Alternatively, integrate this logic into the BlocListener below if preferred)
    // Note: Using a separate listener can sometimes be clearer for specific state updates.
    // Consider if combining with the existing BlocListener is better for your structure.
    context.read<AudioPlayerBloc>().stream.listen((playerState) {
      if (!mounted) return; // Ensure widget is still mounted

      String? newPath;
      if (playerState is AudioPlayerLoaded) {
        newPath = playerState.currentSource;
      } else if (playerState is! AudioPlayerLoading) {
        // Reset path if player is stopped, errored, or in initial state
        newPath = null;
      }

      // Update state only if the path actually changes
      if (_currentlyLoadedPath != newPath) {
        setState(() {
          _currentlyLoadedPath = newPath;
          print(
            "HomeScreen: Updated currentlyLoadedPath: $_currentlyLoadedPath",
          );
          // No need to explicitly trigger tree expansion here,
          // passing the updated path to FolderTreeView will handle it via didUpdateWidget.
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _urlController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // --- UI Event Handlers ---
  void _onSearchChanged() {
    context.read<CollectionBloc>().add(
      SearchCollection(_searchController.text),
    );
    setState(() {
      _selectedTrackIds.clear();
      // Don't clear the player if searching, let the user decide
      // _selectedTrackForPlayer = null;
      _anchorTrackId = null;
    });
  }

  void _togglePlaylistPanel() {
    setState(() {
      _isPlaylistPanelVisible = !_isPlaylistPanelVisible;
    });
  }

  void _handlePlaylistSelected(String playlistId) {
    final playlistState = context.read<PlaylistBloc>().state;
    setState(() {
      if (_currentlySelectedPlaylistId == playlistId) {
        _currentlySelectedPlaylistId = null;
        _currentlySelectedPlaylist = null;
      } else {
        if (playlistState is PlaylistLoaded) {
          try {
            _currentlySelectedPlaylist = playlistState.playlists.firstWhere(
              (p) => p.id == playlistId,
            );
            _currentlySelectedPlaylistId = playlistId;
          } catch (e) {
            _currentlySelectedPlaylist = null;
            _currentlySelectedPlaylistId = null;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Error: Could not select playlist.'),
              ),
            );
          }
        } else {
          _currentlySelectedPlaylist = null;
          _currentlySelectedPlaylistId = null;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Playlists are still loading...')),
          );
        }
      }
      _selectedTrackIds.clear();
      // Don't clear player when changing playlist view if a track is playing
      // _selectedTrackForPlayer = null;
      _anchorTrackId = null;
      // _updatePlayerSelection(); // Ensure player updates if necessary
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

  void _handlePlayerExpand(Track track) {
    print("Handling Play Preview and Minimize for: ${track.title}");
    final bloc = context.read<AudioPlayerBloc>();
    final currentBlocState = bloc.state;

    bool needsLoad = true;
    if (currentBlocState is AudioPlayerLoaded &&
        currentBlocState.currentSource == track.path) {
      needsLoad = false;
      print("Track already loaded.");
    }

    setState(() {
      _selectedTrackForPlayer = track;
      // Ensure the correct track is selected in the table visually
      _selectedTrackIds.clear();
      if (track.id != null) {
        _selectedTrackIds.add(track.id!);
      }
      _anchorTrackId = track.id; // Update anchor for shift-select consistency

      // --- Ensure player minimizes ---
      _isPlayerMinimized = false;
      // if (!_animationController.isCompleted) {
      _animationController.reverse(from: 0.0); // Go directly to minimized state
      // }
      // -----------------------------

      // *** Update the currently loaded path immediately for tree view ***
      // (The listener above will also catch this, but setting it here ensures
      // it's available if the tree view is built right after this)
      _currentlyLoadedPath = track.path;
    });

    if (needsLoad) {
      bloc.add(LoadAudio(source: track.path, isUrl: track.isUrl));
      Future.delayed(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        final postDelayState = bloc.state;
        if (postDelayState is AudioPlayerLoaded &&
            postDelayState.currentSource == track.path) {
          print("Dispatched PlayAudio after loading.");
        } else {
          print(
            "Skipped PlayAudio: State mismatch after delay or widget unmounted.",
          );
        }
      });
    }
  }

  void _handlePlayPreviewAndMinimize(Track track) {
    print("Handling Play Preview and Minimize for: ${track.title}");
    final bloc = context.read<AudioPlayerBloc>();
    final currentBlocState = bloc.state;

    bool needsLoad = true;
    if (currentBlocState is AudioPlayerLoaded &&
        currentBlocState.currentSource == track.path) {
      needsLoad = false;
      print("Track already loaded.");
    }

    setState(() {
      _selectedTrackForPlayer = track;
      // Ensure the correct track is selected in the table visually
      _selectedTrackIds.clear();
      if (track.id != null) {
        _selectedTrackIds.add(track.id!);
      }
      _anchorTrackId = track.id; // Update anchor for shift-select consistency

      // --- Ensure player minimizes ---
      _isPlayerMinimized = true;
      if (!_animationController.isCompleted) {
        _animationController.forward(
          from: 1.0,
        ); // Go directly to minimized state
      }
      // -----------------------------

      // *** Update the currently loaded path immediately for tree view ***
      // (The listener above will also catch this, but setting it here ensures
      // it's available if the tree view is built right after this)
      _currentlyLoadedPath = track.path;
    });

    if (needsLoad) {
      bloc.add(LoadAudio(source: track.path, isUrl: track.isUrl));
      Future.delayed(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        final postDelayState = bloc.state;
        if (postDelayState is AudioPlayerLoaded &&
            postDelayState.currentSource == track.path) {
          bloc.add(PlayAudio());
          print("Dispatched PlayAudio after loading.");
        } else {
          print(
            "Skipped PlayAudio: State mismatch after delay or widget unmounted.",
          );
        }
      });
    } else {
      bloc.add(PlayAudio());
      print("Dispatched PlayAudio for already loaded track.");
    }
  }

  void _toggleViewMode() {
    setState(() {
      _viewMode = _viewMode == ViewMode.list ? ViewMode.tree : ViewMode.list;
      _selectedTrackIds.clear();
      // Keep player playing if view mode changes
      // _selectedTrackForPlayer = null;
      _anchorTrackId = null;
      // *** When switching TO tree view, the FolderTreeView will rebuild ***
      // and receive the current _currentlyLoadedPath, triggering expansion.
    });
  }

  // --- File/Folder Handling Methods ---
  // ... (keep _processDirectory, _findAudioFilesRecursively, _handleDroppedFiles, _pickAndAddFolder, _pickAndAddAudioFile, _showAddUrlDialog) ...
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
      var entities = await dir.list(followLinks: false).toList();
      List<Directory> subDirs = [];
      for (final entity in entities) {
        try {
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
              subDirs.add(Directory(entity.path));
            }
          }
        } catch (e) {
          debugPrint("Error processing entity ${entity.path}: $e");
        }
      }
      for (final subDir in subDirs) {
        await _findAudioFilesRecursively(subDir, audioFilePaths);
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

  // --- Sorting Logic ---
  List<Track> _getSortedTracks(List<Track> tracks) {
    List<Track> sortedTracks = List.from(tracks);
    sortedTracks.sort((a, b) {
      int comparison = 0;
      switch (_sortColumnName) {
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
      // Secondary sort by title if primary columns are equal
      if (comparison == 0 && _sortColumnName != 'title') {
        comparison = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      }
      return _sortDirectionSf == DataGridSortDirection.ascending
          ? comparison
          : -comparison;
    });
    return sortedTracks;
  }

  void _handleSortChanged(String columnName, DataGridSortDirection direction) {
    setState(() {
      _sortColumnName = columnName;
      _sortDirectionSf = direction;
      // Don't clear selection or player on sort
      // _selectedTrackIds.clear();
      // _selectedTrackForPlayer = null;
      // _anchorTrackId = null;
    });
  }

  // --- Selection Logic ---
  // Gets the tracks currently visible/relevant based on view mode, filtering, sorting
  List<Track> _getCurrentDisplayedTracks() {
    final collectionState = context.read<CollectionBloc>().state;
    List<Track> sourceTracks = [];

    // Get base list of tracks from BLoC state
    if (collectionState is CollectionLoaded) {
      sourceTracks = collectionState.tracks;
    } else if (collectionState is CollectionLoading &&
        collectionState.currentTracks != null) {
      sourceTracks = collectionState.currentTracks!;
    } else if (collectionState is CollectionError &&
        collectionState.tracks != null) {
      sourceTracks =
          collectionState.tracks!; // Use tracks even on error if available
    }

    // --- Filter based on selected playlist ---
    List<Track> filteredTracks;
    if (_currentlySelectedPlaylist != null) {
      final playlistTrackPaths = Set<String>.from(
        _currentlySelectedPlaylist!.trackPaths,
      );
      filteredTracks =
          sourceTracks
              .where((track) => playlistTrackPaths.contains(track.path))
              .toList();
    } else {
      filteredTracks = sourceTracks; // Show all tracks if no playlist selected
    }

    // --- Apply Sorting (only relevant for List/Table view) ---
    if (_viewMode == ViewMode.list) {
      return _getSortedTracks(filteredTracks);
    } else {
      // For Tree View, return filtered but unsorted (tree handles its own structure)
      // Or apply a default sort if needed for consistency when finding next/prev
      // Let's return filtered for now. Finding next/prev in tree view might need different logic.
      return filteredTracks;
    }
  }

  void _handleSelectionChanged(
    int trackId,
    bool isSelected, {
    bool isShiftPressed = false,
    bool isCtrlPressed = false,
  }) {
    setState(() {
      final List<Track> currentDisplayedTracks =
          _getCurrentDisplayedTracks(); // Use helper
      if (isSelected) {
        if (isCtrlPressed) {
          _selectedTrackIds.add(trackId);
          _anchorTrackId = trackId;
        } else if (isShiftPressed && _anchorTrackId != null) {
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
            _selectedTrackIds.clear();
            for (int i = start; i <= end; i++) {
              if (i >= 0 &&
                  i < currentDisplayedTracks.length &&
                  currentDisplayedTracks[i].id != null) {
                _selectedTrackIds.add(currentDisplayedTracks[i].id!);
              }
            }
            _anchorTrackId = trackId; // Update anchor to the last clicked
          } else {
            // Fallback if indices not found (shouldn't happen often)
            _selectedTrackIds.clear();
            _selectedTrackIds.add(trackId);
            _anchorTrackId = trackId;
          }
        } else {
          // Single click without modifiers
          _selectedTrackIds.clear();
          _selectedTrackIds.add(trackId);
          _anchorTrackId = trackId;
        }
      } else {
        // Deselecting
        if (isCtrlPressed) {
          _selectedTrackIds.remove(trackId);
          if (_anchorTrackId == trackId)
            _anchorTrackId = null; // Clear anchor if deselected
        } else {
          // Simple deselection (or deselecting one from a shift-selection)
          // If only this one was selected, or if shift/ctrl not pressed, clear all
          // If it was part of a multi-selection WITHOUT ctrl, this implies a new single selection elsewhere
          // The SfDataGrid handles this by firing removedRows then addedRows, so this logic might be simplified
          _selectedTrackIds.remove(trackId);
          if (_anchorTrackId == trackId) _anchorTrackId = null;
          // SfDataGrid's onSelectionChanged might automatically handle clearing others on single select deselect? Test this.
          // For safety, if !isCtrlPressed and !isShiftPressed on deselect, maybe clear all? But SfDataGrid likely handles it.
        }
      }
      _updatePlayerSelection(); // Update player based on new selection
    });
  }

  // Updates the _selectedTrackForPlayer based on the _selectedTrackIds set
  void _updatePlayerSelection() {
    if (_selectedTrackIds.length == 1) {
      final newSelectedId = _selectedTrackIds.first;
      // Only update if the track actually changes
      if (_selectedTrackForPlayer?.id != newSelectedId) {
        final newSelectedTrack = _getTrackById(newSelectedId);
        if (newSelectedTrack != null) {
          setState(() {
            _selectedTrackForPlayer = newSelectedTrack;
            // *** Keep player minimized/expanded state as is ***
            // *** Do NOT set _isPlayerMinimized here ***
            // _isPlayerMinimized = false; // REMOVE THIS
            // _animationController.reverse(); // REMOVE THIS

            // *** Update currently loaded path for tree view ***
            _currentlyLoadedPath = newSelectedTrack.path;
          });
          // Load audio for the newly selected track (but don't auto-play)
          context.read<AudioPlayerBloc>().add(
            LoadAudio(
              source: newSelectedTrack.path,
              isUrl: newSelectedTrack.isUrl,
            ),
          );
        }
      }
    } else {
      // If selection is cleared or multiple items are selected,
      // do NOT change _selectedTrackForPlayer here. Let the user explicitly clear/change the player.
      // setState(() {
      //   _selectedTrackForPlayer = null;
      //   _currentlyLoadedPath = null; // Clear loaded path if selection is lost
      // });
    }
  }

  // --- Context Menu Logic ---
  // ... (keep _showContextMenu, _getTrackById, _confirmAndDeleteSelected) ...
  void _showContextMenu(BuildContext context, Offset tapPosition, Track track) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    // Ensure the right-clicked track is selected
    if (!_selectedTrackIds.contains(track.id)) {
      setState(() {
        _selectedTrackIds.clear();
        _selectedTrackIds.add(track.id!);
        _anchorTrackId = track.id;
        _updatePlayerSelection(); // Update player if selection changes to single item
      });
    }

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(tapPosition.dx, tapPosition.dy, 0, 0), // Position at tap
        Offset.zero & overlay.size, // Overlay boundaries
      ),
      items: <PopupMenuEntry>[
        PopupMenuItem(
          value: 'play_now',
          enabled:
              _selectedTrackIds.length == 1, // Only enable for single selection
          child: ListTile(
            leading: Icon(Icons.play_arrow),
            title: Text('Play Now'),
          ),
        ),
        PopupMenuItem(
          // Add "Play Next" option maybe?
          value: 'play_next',
          enabled: _selectedTrackIds.length == 1,
          child: ListTile(
            leading: Icon(Icons.playlist_play),
            title: Text('Play Next'), // Placeholder text
          ),
        ),
        PopupMenuItem(
          // Add "Add to Queue" option maybe?
          value: 'add_to_queue',
          // enabled: _selectedTrackIds.isNotEmpty, // Enable for multiple items
          enabled: false, // Disabled for now
          child: ListTile(
            leading: Icon(Icons.queue_music),
            title: Text('Add to Queue (Not Implemented)'),
          ),
        ),
        const PopupMenuDivider(),
        // Add to Playlist Submenu (if playlists exist)
        if (context.read<PlaylistBloc>().state is PlaylistLoaded &&
            (context.read<PlaylistBloc>().state as PlaylistLoaded)
                .playlists
                .isNotEmpty)
          _buildAddToPlaylistSubmenu(context, track),

        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'edit',
          enabled: _selectedTrackIds.length == 1,
          child: ListTile(
            leading: Icon(Icons.edit_note),
            title: Text('Edit Details'), // More descriptive
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
      // Handle context menu selection
      if (value == 'play_now' && _selectedTrackIds.length == 1) {
        final trackToPlay = _getTrackById(_selectedTrackIds.first);
        if (trackToPlay != null) {
          // Use the existing minimize handler
          _handlePlayPreviewAndMinimize(trackToPlay);
        }
      } else if (value == 'edit' && _selectedTrackIds.length == 1) {
        final trackToEdit = _getTrackById(_selectedTrackIds.first);
        if (trackToEdit != null) {
          // TODO: Implement or show the metadata editor dialog/panel
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Edit action triggered (UI not implemented)'),
            ),
          );
        }
      } else if (value == 'delete') {
        _confirmAndDeleteSelected();
      }
      // Handle 'add_to_playlist' if value structure includes playlist ID
      else if (value != null &&
          value is Map &&
          value['action'] == 'add_to_playlist') {
        final String playlistId = value['playlist_id'];
        final addedTrackIds = Set<int>.from(
          _selectedTrackIds,
        ); // Copy selection
        final collectionState = context.read<CollectionBloc>().state;
        final playlistBloc = context.read<PlaylistBloc>();

        if (collectionState is CollectionLoaded) {
          int addedCount = 0;
          for (final trackId in addedTrackIds) {
            try {
              final track = collectionState.tracks.firstWhere(
                (t) => t.id == trackId,
              );
              playlistBloc.add(
                AddTrackToPlaylist(
                  playlistId: playlistId,
                  trackPath: track.path,
                ),
              );
              addedCount++;
            } catch (e) {
              print(
                "Couldn't find track $trackId to add to playlist $playlistId",
              );
            }
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Added $addedCount track(s) to playlist.')),
          );
        }
      }
    });
  }

  // Helper for context menu
  Track? _getTrackById(int id) {
    final state = context.read<CollectionBloc>().state;
    List<Track> sourceList = [];
    if (state is CollectionLoaded) {
      sourceList = state.tracks;
    } else if (state is CollectionLoading && state.currentTracks != null) {
      sourceList = state.currentTracks!;
    } else if (state is CollectionError && state.tracks != null) {
      sourceList = state.tracks!;
    }

    try {
      return sourceList.firstWhere((t) => t.id == id);
    } catch (e) {
      return null; // Not found
    }
  }

  // Helper for context menu -> Add to Playlist submenu
  PopupMenuItem<dynamic> _buildAddToPlaylistSubmenu(
    BuildContext context,
    Track track,
  ) {
    // No longer returns PopupMenuButton, returns a single item to trigger a dialog
    final playlistState = context.read<PlaylistBloc>().state;
    bool playlistsAvailable =
        playlistState is PlaylistLoaded && playlistState.playlists.isNotEmpty;

    return PopupMenuItem(
      // Give it a unique value to identify the action in .then()
      value: 'show_add_to_playlist_dialog',
      enabled: playlistsAvailable, // Only enable if playlists exist
      child: ListTile(
        leading: Icon(Icons.playlist_add),
        title: Text('Add to Playlist...'),
        enabled: playlistsAvailable,
      ),
    );
  }

  // Helper for context menu
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
                Navigator.of(dialogContext).pop(); // Close dialog first
                final collectionBloc = context.read<CollectionBloc>();
                final idsToDelete = List<int>.from(
                  _selectedTrackIds,
                ); // Copy IDs before modifying set

                // Stop player if the deleted track was playing
                if (_selectedTrackForPlayer != null &&
                    idsToDelete.contains(_selectedTrackForPlayer!.id)) {
                  context.read<AudioPlayerBloc>().add(StopAudio());
                  // Clear player selection state *after* stopping
                  // Use addPostFrameCallback to avoid setState during build/layout
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() {
                        _selectedTrackForPlayer = null;
                        _currentlyLoadedPath = null; // Clear loaded path
                      });
                    }
                  });
                }

                // Dispatch delete events
                for (final trackId in idsToDelete) {
                  collectionBloc.add(RemoveTrack(trackId));
                }

                // Clear selection state *after* dispatching deletes
                // Use addPostFrameCallback here too for safety
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() {
                      _selectedTrackIds.clear();
                      _anchorTrackId = null;
                      // _selectedTrackForPlayer is handled above if needed
                    });
                  }
                });
              },
            ),
          ],
        );
      },
    );
  }

  // --- Rating Handler ---
  void _handleRatingChanged(int trackId, int newRating) {
    print("Rating changed in table: Track $trackId -> $newRating stars");
    context.read<CollectionBloc>().add(UpdateTrackRating(trackId, newRating));
    // Optimistically update the track in the local state if it's the currently playing one
    if (_selectedTrackForPlayer?.id == trackId) {
      setState(() {
        _selectedTrackForPlayer = _selectedTrackForPlayer?.copyWith(
          rating: newRating,
        );
      });
    }
  }

  // --- NEW: Play Next Track Logic ---
  void _playNextTrack() {
    if (_selectedTrackForPlayer == null)
      return; // Cannot play next if nothing is playing

    final List<Track> currentList = _getCurrentDisplayedTracks();
    if (currentList.isEmpty) return;

    final currentIndex = currentList.indexWhere(
      (t) => t.id == _selectedTrackForPlayer!.id,
    );

    if (currentIndex != -1 && currentIndex < currentList.length - 1) {
      // Found current track and it's not the last one
      final nextTrack = currentList[currentIndex + 1];
      print("Playing next track: ${nextTrack.title}");

      // Use the existing handler to load, play, and set state correctly
      // This will update _selectedTrackForPlayer and trigger BLoC events
      // Pass the next track to the handler
      _handlePlayPreviewAndMinimize(nextTrack); // Re-use the handler

      // We might need to ensure the player stays minimized if it already was.
      // _handlePlayPreviewAndMinimize already sets _isPlayerMinimized = true,
      // so it should remain minimized.
    } else {
      // Current track not found or it's the last track
      print("No next track available or current track not found in list.");
      // Optional: Stop playback, loop, or do nothing
      // context.read<AudioPlayerBloc>().add(StopAudio()); // Example: Stop at end
    }
  }

  void _playPreviousTrack() {
    if (_selectedTrackForPlayer == null) return; // Nothing is playing

    // Get the audio player bloc and its current state
    final audioPlayerBloc = context.read<AudioPlayerBloc>();
    final playerState = audioPlayerBloc.state;

    // Check if the currently loaded track matches the selected track
    if (playerState is AudioPlayerLoaded &&
        playerState.currentSource == _selectedTrackForPlayer!.path) {
      // Get current position
      final currentPosition = playerState.position;

      // *** Conditional Logic based on position ***
      if (currentPosition.inMilliseconds > 700) {
        // If played past 700ms, seek to beginning of current track
        print("Previous button clicked (>700ms): Seeking current track to 0");
        audioPlayerBloc.add(const SeekAudio(position: Duration.zero));
        // Ensure it plays if it was paused at the end for example
        if (!playerState.isPlaying) {
          audioPlayerBloc.add(PlayAudio());
        }
        return; // Don't proceed to play the actual previous track
      }
      // *** End of Conditional Logic ***
    }

    // --- Default Behavior (Position <= 700ms OR state doesn't match) ---
    // Find the actual previous track in the currently displayed list
    final List<Track> currentList = _getCurrentDisplayedTracks();
    if (currentList.isEmpty) return;

    final currentIndex = currentList.indexWhere(
      (t) => t.id == _selectedTrackForPlayer!.id,
    );

    if (currentIndex > 0) {
      // Found current track and it's not the first one
      final previousTrack = currentList[currentIndex - 1];
      print(
        "Previous button clicked (<=700ms): Playing previous track: ${previousTrack.title}",
      );
      // Use the handler to load/play the previous track and update state
      _handlePlayPreviewAndMinimize(previousTrack);
    } else {
      // Current track is the first one or not found
      print("No previous track available or current track not found.");
      // Optional: Seek to 0 if it's the first track?
      audioPlayerBloc.add(const SeekAudio(position: Duration.zero));
    }
  }

  // --- Build Method ---
  @override
  Widget build(BuildContext context) {
    // *** ADDED: Wrap with BlocListener for AudioPlayerBloc ***
    // This ensures _currentlyLoadedPath is updated even if other parts
    // of the UI trigger audio loading without direct interaction here.
    return BlocListener<AudioPlayerBloc, AudioPlayerState>(
      listener: (context, playerState) {
        if (!mounted) return; // Ensure widget is still mounted

        String? newPath;
        if (playerState is AudioPlayerLoaded) {
          newPath = playerState.currentSource;
        } else if (playerState is! AudioPlayerLoading) {
          // Reset path if player is stopped, errored, or in initial state
          newPath = null;
        }

        // Update state only if the path actually changes
        if (_currentlyLoadedPath != newPath) {
          setState(() {
            _currentlyLoadedPath = newPath;
            print(
              "HomeScreen (Listener): Updated currentlyLoadedPath: $_currentlyLoadedPath",
            );
          });
        }
      },
      child: BlocListener<PlaylistBloc, PlaylistState>(
        listener: (context, playlistState) {
          if (playlistState is PlaylistLoaded &&
              _currentlySelectedPlaylistId != null) {
            bool selectedExists = playlistState.playlists.any(
              (p) => p.id == _currentlySelectedPlaylistId,
            );
            if (!selectedExists) {
              setState(() {
                _currentlySelectedPlaylistId = null;
                _currentlySelectedPlaylist = null;
              });
            } else {
              try {
                final updatedPlaylist = playlistState.playlists.firstWhere(
                  (p) => p.id == _currentlySelectedPlaylistId,
                );
                if (!identical(_currentlySelectedPlaylist, updatedPlaylist) &&
                    _currentlySelectedPlaylist != updatedPlaylist) {
                  setState(() {
                    _currentlySelectedPlaylist = updatedPlaylist;
                  });
                }
              } catch (e) {
                /* ignore */
              }
            }
          }
        },
        child: Scaffold(
          // ... (AppBar setup remains the same) ...
          appBar: AppBar(
            title: const Text('Audio Looker'),
            actions: [
              IconButton(
                icon: Icon(
                  _isPlaylistPanelVisible ? Icons.menu_open : Icons.menu,
                ),
                tooltip: 'Toggle Playlists Panel',
                onPressed: _togglePlaylistPanel,
              ),
              // Add other actions like search icon if needed
              IconButton(
                icon: Icon(
                  _viewMode == ViewMode.list
                      ? Icons.account_tree
                      : Icons.table_rows,
                ),
                onPressed: _toggleViewMode,
                tooltip:
                    _viewMode == ViewMode.list
                        ? 'Switch to folder view'
                        : 'Switch to table view',
              ),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Add...',
                onPressed: () {
                  showMenu(
                    context: context,
                    position: RelativeRect.fromLTRB(
                      MediaQuery.of(context).size.width - 100,
                      kToolbarHeight,
                      MediaQuery.of(context).size.width,
                      0,
                    ), // Position near top right
                    items: <PopupMenuEntry>[
                      PopupMenuItem(
                        value: 'add_file',
                        child: ListTile(
                          leading: Icon(Icons.audio_file),
                          title: Text('Add Audio File(s)'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'add_folder',
                        child: ListTile(
                          leading: Icon(Icons.folder_open),
                          title: Text('Add Folder'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'add_url',
                        child: ListTile(
                          leading: Icon(Icons.link),
                          title: Text('Add Audio from URL'),
                        ),
                      ),
                    ],
                  ).then((value) {
                    if (value == 'add_file')
                      _pickAndAddAudioFile();
                    else if (value == 'add_folder')
                      _pickAndAddFolder();
                    else if (value == 'add_url')
                      _showAddUrlDialog();
                  });
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Row(
            children: [
              // Playlist Panel (AnimatedContainer)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                width: _isPlaylistPanelVisible ? 250.0 : 0.0,
                decoration: BoxDecoration(
                  border: Border(
                    right: BorderSide(
                      color:
                          _isPlaylistPanelVisible
                              ? Theme.of(context).dividerColor
                              : Colors.transparent,
                      width: 1.0,
                    ),
                  ),
                  color: Theme.of(context).canvasColor,
                ),
                clipBehavior: Clip.hardEdge,
                child: Visibility(
                  visible: _isPlaylistPanelVisible,
                  maintainState: false, // Don't keep state when hidden
                  child: PlaylistDrawer(
                    selectedPlaylistId: _currentlySelectedPlaylistId,
                    onPlaylistSelected: _handlePlaylistSelected,
                  ),
                ),
              ),

              // Main Content Area (Expanded)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Search bar and Playlist Header (Paddings, Conditionals)
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
                          // Add clear button?
                          // suffixIcon: _searchController.text.isNotEmpty
                          //     ? IconButton(
                          //         icon: Icon(Icons.clear, size: 18),
                          //         onPressed: () {
                          //           _searchController.clear();
                          //           // _onSearchChanged(); // Trigger search update
                          //         },
                          //       )
                          //     : null,
                        ),
                      ),
                    ),
                    if (_currentlySelectedPlaylist != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 4.0,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12.0,
                            vertical: 8.0,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.secondaryContainer.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  'Playlist: ${_currentlySelectedPlaylist!.name}',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium?.copyWith(
                                    color:
                                        Theme.of(
                                          context,
                                        ).colorScheme.onSecondaryContainer,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.clear),
                                tooltip: 'Show All Tracks',
                                iconSize: 20,
                                visualDensity: VisualDensity.compact,
                                onPressed:
                                    () => _handlePlaylistSelected(
                                      _currentlySelectedPlaylistId!,
                                    ), // Tap again to deselect
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Collection content area (Expanded > DropTarget > Stack > BlocConsumer)
                    Expanded(
                      child: DropTarget(
                        onDragDone:
                            (detail) async =>
                                await _handleDroppedFiles(detail.files),
                        onDragEntered:
                            (detail) => setState(() => _isDragging = true),
                        onDragExited:
                            (detail) => setState(() => _isDragging = false),
                        child: Stack(
                          children: [
                            // Main Content: Table or Tree View
                            BlocConsumer<CollectionBloc, CollectionState>(
                              listener: (context, state) {
                                if (state is CollectionError) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Error: ${state.message}'),
                                      backgroundColor: Colors.redAccent,
                                    ),
                                  );
                                }
                                // Update selection if underlying data changes (e.g., item deleted)
                                if (state is CollectionLoaded) {
                                  final currentTrackIds =
                                      state.tracks.map((t) => t.id).toSet();
                                  bool selectionChanged = false;
                                  _selectedTrackIds.removeWhere((id) {
                                    if (!currentTrackIds.contains(id)) {
                                      selectionChanged = true;
                                      if (_anchorTrackId == id)
                                        _anchorTrackId = null;
                                      return true;
                                    }
                                    return false;
                                  });
                                  if (selectionChanged) {
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          if (mounted) {
                                            setState(() {
                                              _updatePlayerSelection();
                                            });
                                          }
                                        });
                                  }
                                }
                              },
                              builder: (context, state) {
                                // --- Logic to get tracks/folders/loading state ---
                                List<Track> allTracks = [];
                                List<String> rootFolders = [];
                                bool isLoading = false;

                                if (state is CollectionLoading) {
                                  isLoading = true;
                                  allTracks = state.currentTracks ?? [];
                                  rootFolders = state.currentRootFolders ?? [];
                                } else if (state is CollectionLoaded) {
                                  isLoading = false;
                                  allTracks = state.tracks;
                                  rootFolders = state.rootFolders;
                                } else if (state is CollectionError) {
                                  allTracks =
                                      state.tracks ??
                                      []; // Show tracks even on error if available
                                  // You might want to show an error message prominently here too
                                } else if (state is CollectionInitial) {
                                  isLoading = true;
                                }
                                // --------------------------------------------------

                                if (isLoading && allTracks.isEmpty) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }

                                // Get the list relevant for the current view & filter
                                List<Track> displayedTracks =
                                    _getCurrentDisplayedTracks();

                                // --- Empty State Handling ---
                                if (!isLoading && displayedTracks.isEmpty) {
                                  if (_currentlySelectedPlaylist != null) {
                                    return Center(
                                      child: Text(
                                        'Playlist "${_currentlySelectedPlaylist!.name}" is empty.',
                                      ),
                                    );
                                  } else if (_searchController
                                      .text
                                      .isNotEmpty) {
                                    return Center(
                                      child: Text(
                                        'No tracks found for "${_searchController.text}"',
                                      ),
                                    );
                                  } else if (allTracks.isEmpty &&
                                      rootFolders.isEmpty) {
                                    // True empty state
                                    return Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(20.0),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.music_note_outlined,
                                              size: 64,
                                              color: Colors.grey[600],
                                            ),
                                            const SizedBox(height: 16),
                                            Text(
                                              'Collection is Empty',
                                              style:
                                                  Theme.of(
                                                    context,
                                                  ).textTheme.headlineSmall,
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              'Add files/folders using drag & drop or the (+) button.',
                                              style:
                                                  Theme.of(
                                                    context,
                                                  ).textTheme.bodyMedium,
                                              textAlign: TextAlign.center,
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  } else if (_viewMode == ViewMode.tree &&
                                      rootFolders.isEmpty) {
                                    return const Center(
                                      child: Text(
                                        'No root folders added. Add folders via (+) or drag & drop.',
                                      ),
                                    );
                                  } else if (_viewMode == ViewMode.list &&
                                      allTracks.isEmpty &&
                                      rootFolders.isNotEmpty) {
                                    // Case where folders exist but maybe contain no playable files yet
                                    return const Center(
                                      child: Text(
                                        'No audio tracks found in the collection yet.',
                                      ),
                                    );
                                  }
                                  // Fallback empty message if other conditions don't catch it
                                  return const Center(
                                    child: Text('No tracks to display.'),
                                  );
                                }

                                // --- Build View (Column: [Expanded(Table/Tree), Player]) ---
                                return Column(
                                  children: [
                                    Expanded(
                                      child: Opacity(
                                        opacity:
                                            isLoading
                                                ? 0.6
                                                : 1.0, // Dim content while loading in background
                                        child: Container(
                                          color:
                                              _currentlySelectedPlaylistId !=
                                                      null
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .surfaceVariant
                                                      .withOpacity(0.3)
                                                  : null, // Subtle background for playlist view
                                          child:
                                              _viewMode == ViewMode.list
                                                  ? TrackTableWidget(
                                                    tracks:
                                                        displayedTracks, // Pass the correctly filtered/sorted list
                                                    key: ValueKey(
                                                      'track-table-${_currentlySelectedPlaylistId ?? 'all'}-${_sortColumnName}-${_sortDirectionSf}',
                                                    ), // More specific key
                                                    selectedTrackIds:
                                                        _selectedTrackIds,
                                                    audioPlayerBloc:
                                                        context
                                                            .read<
                                                              AudioPlayerBloc
                                                            >(),
                                                    onSelectionChanged:
                                                        _handleSelectionChanged,
                                                    onShowContextMenu:
                                                        _showContextMenu,
                                                    onRatingChanged:
                                                        _handleRatingChanged,
                                                    onSort: _handleSortChanged,
                                                    initialSortColumnName:
                                                        _sortColumnName,
                                                    initialSortDirection:
                                                        _sortDirectionSf,
                                                    onPlayPreviewAndMinimize:
                                                        _handlePlayerExpand,
                                                  )
                                                  : FolderTreeView(
                                                    tracks:
                                                        allTracks, // Tree view usually needs all tracks to build structure
                                                    key: ValueKey(
                                                      'folder-tree-${_currentlyLoadedPath ?? 'none'}',
                                                    ), // Key includes loaded path to trigger rebuild/update
                                                    rootFolders: rootFolders,
                                                    selectedTrack:
                                                        _selectedTrackForPlayer,
                                                    // *** ADDED: Pass the loaded path ***
                                                    currentlyLoadedPath:
                                                        _currentlyLoadedPath,
                                                    onTrackSelected: (track) {
                                                      // Select track in tree view - should update player?
                                                      setState(() {
                                                        _selectedTrackIds
                                                            .clear();
                                                        if (track.id != null) {
                                                          _selectedTrackIds.add(
                                                            track.id!,
                                                          );
                                                          _anchorTrackId =
                                                              track.id;
                                                        } else {
                                                          _anchorTrackId = null;
                                                        }
                                                        _updatePlayerSelection(); // Update player state
                                                      });
                                                    },
                                                    onTrackDeleted: (trackId) {
                                                      // Handle deletion initiated from tree view
                                                      _selectedTrackIds.remove(
                                                        trackId,
                                                      );
                                                      if (_anchorTrackId ==
                                                          trackId)
                                                        _anchorTrackId = null;
                                                      if (_selectedTrackForPlayer
                                                              ?.id ==
                                                          trackId) {
                                                        context
                                                            .read<
                                                              AudioPlayerBloc
                                                            >()
                                                            .add(StopAudio());
                                                        _selectedTrackForPlayer =
                                                            null; // Clear player state too
                                                        _currentlyLoadedPath =
                                                            null; // Clear loaded path
                                                      }
                                                      context
                                                          .read<
                                                            CollectionBloc
                                                          >()
                                                          .add(
                                                            RemoveTrack(
                                                              trackId,
                                                            ),
                                                          );
                                                      setState(
                                                        () {},
                                                      ); // Trigger rebuild after state changes
                                                    },
                                                  ),
                                        ),
                                      ),
                                    ),
                                    // --- Audio Player ---
                                    if (_selectedTrackForPlayer != null)
                                      AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 200,
                                        ),
                                        curve: Curves.easeInOut,
                                        height: _playerHeightAnimation.value,
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).cardColor,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(
                                                0.2,
                                              ),
                                              blurRadius: 8,
                                              offset: const Offset(0, -2),
                                            ),
                                          ],
                                        ),
                                        child: Column(
                                          children: [
                                            // Minimize/Expand Toggle Bar
                                            Container(
                                              height: 36,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .surfaceVariant
                                                  .withOpacity(0.5),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  IconButton(
                                                    icon: Icon(
                                                      _isPlayerMinimized
                                                          ? Icons
                                                              .keyboard_arrow_up
                                                          : Icons
                                                              .keyboard_arrow_down,
                                                    ),
                                                    onPressed:
                                                        _togglePlayerSize,
                                                    tooltip:
                                                        _isPlayerMinimized
                                                            ? 'Expand player'
                                                            : 'Minimize player',
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // Player Content Area (Stack: Full Player, Minimized Controls)
                                            Expanded(
                                              child: Stack(
                                                children: [
                                                  // Full Player
                                                  AnimatedOpacity(
                                                    opacity:
                                                        _isPlayerMinimized
                                                            ? 0.0
                                                            : 1.0,
                                                    duration: const Duration(
                                                      milliseconds: 150,
                                                    ),
                                                    child: IgnorePointer(
                                                      ignoring:
                                                          _isPlayerMinimized,
                                                      child: AudioPlayerWidget(
                                                        key: ValueKey(
                                                          _selectedTrackForPlayer!
                                                              .id,
                                                        ), // Ensure widget rebuilds on track change
                                                        trackId:
                                                            _selectedTrackForPlayer!
                                                                .id!,
                                                        title:
                                                            _selectedTrackForPlayer!
                                                                .title,
                                                        artist:
                                                            _selectedTrackForPlayer!
                                                                .artist,
                                                        audioSource:
                                                            _selectedTrackForPlayer!
                                                                .path,
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
                                                        onRatingChanged: (
                                                          rating,
                                                        ) {
                                                          if (_selectedTrackForPlayer
                                                                  ?.id !=
                                                              null) {
                                                            _handleRatingChanged(
                                                              _selectedTrackForPlayer!
                                                                  .id!,
                                                              rating,
                                                            );
                                                          }
                                                        },
                                                        onNotesChanged: (
                                                          notes,
                                                        ) {
                                                          if (_selectedTrackForPlayer
                                                                  ?.id !=
                                                              null) {
                                                            context
                                                                .read<
                                                                  CollectionBloc
                                                                >()
                                                                .add(
                                                                  UpdateTrackComment(
                                                                    _selectedTrackForPlayer!
                                                                        .id!,
                                                                    notes,
                                                                  ),
                                                                );
                                                            // Optimistically update local state if needed
                                                            // setState(() { _selectedTrackForPlayer = _selectedTrackForPlayer?.copyWith(comment: notes); });
                                                          }
                                                        },
                                                      ),
                                                    ),
                                                  ),
                                                  // Minimized Player Controls
                                                  AnimatedOpacity(
                                                    opacity:
                                                        _isPlayerMinimized
                                                            ? 1.0
                                                            : 0.0,
                                                    duration: const Duration(
                                                      milliseconds: 150,
                                                    ),
                                                    child: IgnorePointer(
                                                      ignoring:
                                                          !_isPlayerMinimized,
                                                      child:
                                                          _buildMinimizedPlayerControls(), // Updated builder
                                                    ),
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
                            ), // End BlocConsumer
                            // Drag overlay
                            if (_isDragging)
                              Container(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withOpacity(0.1),
                                child: Center(/* ... Drag hint ... */),
                              ),
                            // Loading Indicator Overlay
                            BlocBuilder<CollectionBloc, CollectionState>(
                              builder: (context, state) {
                                if (state is CollectionLoading &&
                                    !state.currentTracks.isNullOrEmpty) {
                                  // Show only if loading in background
                                  return Positioned.fill(
                                    child: Container(
                                      color: Colors.black.withOpacity(0.4),
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
              ),
            ],
          ),
        ),
      ), // End Scaffold
    ); // End BlocListener<PlaylistBloc...>
  } // End build method

  // --- UPDATED Minimized Player Controls Builder ---
  Widget _buildMinimizedPlayerControls() {
    if (_selectedTrackForPlayer == null) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        height: _minimizedPlayerHeight,
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceVariant.withOpacity(0.9), // Slightly more opaque
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor, width: 1.0),
          ), // More visible border
        ),
        child: BlocBuilder<AudioPlayerBloc, AudioPlayerState>(
          builder: (context, playerState) {
            bool isPlaying = false;
            bool isCurrentTrackLoaded = false;

            if (playerState is AudioPlayerLoaded &&
                playerState.currentSource == _selectedTrackForPlayer!.path) {
              isPlaying = playerState.isPlaying;
              isCurrentTrackLoaded = true;
            }

            return Row(
              children: [
                // Optional: Album art placeholder
                // Container(
                //   width: 40, height: 40, color: Colors.grey[700],
                //   child: Icon(Icons.music_note, color: Colors.white70),
                // ),
                // const SizedBox(width: 12),

                // Track Info (Expanded)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedTrackForPlayer!.title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 2),
                      Text(
                        _selectedTrackForPlayer!.artist,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[400],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16), // Spacing before controls
                // Previous Button
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  onPressed:
                      _playPreviousTrack, // *** Call previous track handler ***
                  tooltip: 'Previous',
                  iconSize: 28,
                ),
                // Play/Pause Button
                IconButton(
                  icon: Icon(
                    isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    size: 40, // Larger play/pause
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: () {
                    final bloc = context.read<AudioPlayerBloc>();
                    if (isCurrentTrackLoaded) {
                      if (isPlaying) {
                        bloc.add(PauseAudio());
                      } else {
                        // Handle case where track ended and user hits play again
                        if (playerState is AudioPlayerLoaded &&
                            playerState.position >= playerState.duration &&
                            playerState.duration > Duration.zero) {
                          bloc.add(const SeekAudio(position: Duration.zero));
                        }
                        bloc.add(PlayAudio());
                      }
                    } else {
                      // Fallback if track somehow not loaded (should be handled by select/play handlers)
                      bloc.add(
                        LoadAudio(
                          source: _selectedTrackForPlayer!.path,
                          isUrl: _selectedTrackForPlayer!.isUrl,
                        ),
                      );
                      Future.delayed(const Duration(milliseconds: 100), () {
                        if (!mounted) return;
                        final postDelayState = bloc.state;
                        if (postDelayState is AudioPlayerLoaded &&
                            postDelayState.currentSource ==
                                _selectedTrackForPlayer!.path) {
                          bloc.add(PlayAudio());
                        }
                      });
                    }
                  },
                  tooltip: isPlaying ? 'Pause' : 'Play',
                ),
                // Next Button
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  onPressed: _playNextTrack, // *** Call next track handler ***
                  tooltip: 'Next',
                  iconSize: 28,
                ),
                // Optional: Add volume or other controls here if desired
              ],
            );
          },
        ),
      ),
    );
  }
} // End _HomeScreenState

// Helper extension for checking null or empty on List<Track>?
extension TrackListNullOrEmpty on List<Track>? {
  bool get isNullOrEmpty {
    return this == null || this!.isEmpty;
  }
}
