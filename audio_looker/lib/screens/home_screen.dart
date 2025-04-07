// lib/screens/home_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'; // Keep for potential future use?
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:path_provider/path_provider.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as pathLib;

// Import BLoCs
import 'package:audio_looker/blocs/collection/collection_bloc.dart';
import 'package:audio_looker/blocs/audio_player/audio_player_bloc.dart';
import 'package:audio_looker/blocs/playlist/playlist_bloc.dart';

// Import Services and Models
import 'package:audio_looker/services/collection_service.dart';
import 'package:audio_looker/models/playlist.dart';

// Import Widgets
import 'package:audio_looker/widgets/playlist_drawer.dart';
import 'package:audio_looker/widgets/folder_tree_view.dart';
import 'package:audio_looker/widgets/track_table_widget.dart';
import 'package:audio_looker/widgets/combined_audio_player_widget.dart';

// Import the new screen <<< ADDED
import 'package:audio_looker/screens/collection_manager_screen.dart';

// Define view mode enum
enum ViewMode { list, tree }

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // ... (keep existing state variables: _searchController, _urlController, etc.) ...
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  Track? _selectedTrackForPlayer; // Track currently selected for the player
  ViewMode _viewMode = ViewMode.list;
  bool _isDragging = false;
  final FocusNode _focusNode = FocusNode();
  final List<String> _supportedExtensions = [
    'mp3',
    'wav',
    'ogg',
    'm4a',
    'aac',
    'flac',
  ];
  String _sortColumnName = 'title';
  DataGridSortDirection _sortDirectionSf = DataGridSortDirection.ascending;
  final Set<int> _selectedTrackIds = {}; // IDs selected in the table/tree
  int? _anchorTrackId; // For shift-selection
  bool _isPlaylistPanelVisible = true;
  String? _currentlySelectedPlaylistId;
  Playlist? _currentlySelectedPlaylist;
  bool _isMinimized = true;
  String? _currentlyLoadedPathInPlayer;

  @override
  void initState() {
    super.initState();
    // Initial data loading - Load collection list first, then load default/last collection
    // This logic might move to main.dart or a splash screen later
    context.read<CollectionBloc>().add(LoadCollectionList());
    // TODO: Add logic here or in listener to load a default collection
    // For now, LoadCollection might fail until one is selected/opened via CollectionManagerScreen
    // context.read<CollectionBloc>().add(LoadCollection()); // Might fail initially

    context.read<PlaylistBloc>().add(
      LoadPlaylists(),
    ); // Load playlists for potentially empty initial state

    _searchController.addListener(_onSearchChanged);

    context.read<AudioPlayerBloc>().stream.listen((playerState) {
      if (!mounted) return;
      String? newPath;
      if (playerState is AudioPlayerLoaded) {
        newPath = playerState.currentSource;
      } else if (playerState is! AudioPlayerLoading) {
        newPath = null;
      }
      if (_currentlyLoadedPathInPlayer != newPath) {
        setState(() {
          _currentlyLoadedPathInPlayer = newPath;
        });
      }
    });

    // Listener to reload playlists when active collection changes
    context.read<CollectionBloc>().stream.listen((collectionState) {
      if (collectionState is CollectionLoaded) {
        // Check if the active collection ID has changed compared to the previous state
        // (Requires storing previous state or comparing IDs carefully)
        // For simplicity, we reload playlists whenever CollectionLoaded is emitted
        // This might be slightly inefficient but ensures consistency.
        print(
          "HomeScreen Listener: Collection loaded, reloading playlists for active collection.",
        );
        context.read<PlaylistBloc>().add(LoadPlaylists());
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _searchController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  // ... (keep existing methods: _handlePlayerToggle, _onSearchChanged, etc.) ...
  void _handlePlayerToggle() {
    if (!mounted) return;
    setState(() {
      _isMinimized = !_isMinimized;
    });
  }

  void _onSearchChanged() {
    // Check if a collection is actually loaded before searching
    if (context.read<CollectionBloc>().state is CollectionLoaded) {
      context.read<CollectionBloc>().add(
        SearchCollection(_searchController.text),
      );
      setState(() {
        _selectedTrackIds.clear();
        _anchorTrackId = null;
      });
    } else {
      // Optionally show a message if trying to search without an active collection
      print("Cannot search: No collection loaded.");
    }
  }

  void _togglePlaylistPanel() {
    setState(() {
      _isPlaylistPanelVisible = !_isPlaylistPanelVisible;
    });
  }

  void _handlePlaylistSelected(String playlistId) {
    // ... (existing playlist selection logic) ...
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
      _anchorTrackId = null;
    });
  }

  void _selectAndPlayTrack(Track track) {
    // ... (existing logic) ...
    print("HomeScreen: Selecting and playing track: ${track.title}");
    final bloc = context.read<AudioPlayerBloc>();
    final currentBlocState = bloc.state;
    bool needsLoad = true;
    if (currentBlocState is AudioPlayerLoaded &&
        currentBlocState.currentSource == track.path) {
      needsLoad = false;
    }
    setState(() {
      _selectedTrackForPlayer = track;
      _selectedTrackIds.clear();
      if (track.id != null) _selectedTrackIds.add(track.id!);
      _anchorTrackId = track.id;
    });
    if (needsLoad) {
      bloc.add(LoadAudio(source: track.path, isUrl: track.isUrl));
      Future.delayed(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        final postDelayState = bloc.state;
        if (postDelayState is AudioPlayerLoaded &&
            postDelayState.currentSource == track.path) {
          bloc.add(PlayAudio());
        }
      });
    } else {
      bloc.add(PlayAudio());
    }
  }

  void _selectAndOpenPlayer(Track track) {
    // ... (existing logic) ...
    print("HomeScreen: Selecting and opening player for track: ${track.title}");
    final bloc = context.read<AudioPlayerBloc>();
    final currentBlocState = bloc.state;
    bool needsLoad = true;
    if (currentBlocState is AudioPlayerLoaded &&
        currentBlocState.currentSource == track.path) {
      needsLoad = false;
    }
    setState(() {
      _selectedTrackForPlayer = track;
      _selectedTrackIds.clear();
      if (track.id != null) _selectedTrackIds.add(track.id!);
      _anchorTrackId = track.id;
      _isMinimized = false; // Ensure player opens
    });
    if (needsLoad) {
      bloc.add(LoadAudio(source: track.path, isUrl: track.isUrl));
      // Optional: Auto-play when opening via edit? Maybe not.
      // Future.delayed(...) bloc.add(PlayAudio());
    } else {
      // Optional: Auto-play if already loaded?
      // bloc.add(PlayAudio());
    }
  }

  void _selectTrackForPlayer(Track track) {
    // ... (existing logic) ...
    print("HomeScreen: Selecting track for player: ${track.title}");
    final bloc = context.read<AudioPlayerBloc>();
    final currentBlocState = bloc.state;
    bool needsLoad = true;
    if (currentBlocState is AudioPlayerLoaded &&
        currentBlocState.currentSource == track.path) {
      needsLoad = false;
    }
    setState(() {
      _selectedTrackForPlayer = track;
    });
    if (needsLoad) {
      bloc.add(LoadAudio(source: track.path, isUrl: track.isUrl));
    }
  }

  void _toggleViewMode() {
    setState(() {
      _viewMode = _viewMode == ViewMode.list ? ViewMode.tree : ViewMode.list;
      _selectedTrackIds.clear();
      _anchorTrackId = null;
    });
  }

  Future<void> _processDirectory(String dirPath) async {
    /* ... existing logic ... */
  }
  Future<void> _findAudioFilesRecursively(
    Directory dir,
    List<String> audioFilePaths,
  ) async {
    /* ... existing logic ... */
  }
  Future<void> _handleDroppedFiles(List<DropItem> items) async {
    // --- MODIFIED: Only add root folder if active collection is 'local' ---
    print("Items dropped: ${items.length}");
    if (items.isEmpty) return;

    final collectionBloc = context.read<CollectionBloc>();
    final activeCollection =
        (collectionBloc.state is CollectionLoaded)
            ? (collectionBloc.state as CollectionLoaded)
                .activeCollectionDefinition
            : null;

    if (activeCollection == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Cannot add items: No active collection."),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Processing dropped items...")),
    );
    List<String> filesToAdd = [];
    List<String> foldersToProcess = []; // For adding tracks within folder

    for (final item in items) {
      final path = item.path;
      try {
        print("Processing dropped path: $path");
        if (path.startsWith("web:")) {
          // Handle web drops if necessary
          // filesToAdd.add(path); // Or handle URL adding logic
          continue;
        }
        var type = await FileSystemEntity.type(path, followLinks: false);

        if (type == FileSystemEntityType.directory) {
          // Only add as ROOT folder if the active collection is LOCAL
          if (activeCollection.type == CollectionType.local) {
            collectionBloc.add(AddRootFolder(path));
          }
          // Always process folder to add tracks inside it to the active collection
          foldersToProcess.add(path);
        } else if (type == FileSystemEntityType.file) {
          final extension = pathLib
              .extension(item.path)
              .toLowerCase()
              .replaceFirst('.', '');
          if (_supportedExtensions.contains(extension)) {
            filesToAdd.add(path);
          } else {
            print("Skipping unsupported file type: $path");
          }
        } else {
          print(
            "Skipping unsupported or inaccessible path: $path (Type: $type)",
          );
        }
      } catch (e, stackTrace) {
        print("Error checking dropped path type for $path: $e\n$stackTrace");
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error processing item: $path")));
      }
    }

    // Add individual files to the active collection
    if (filesToAdd.isNotEmpty) {
      collectionBloc.add(AddTracksFromPaths(filesToAdd));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Adding ${filesToAdd.length} dropped files...")),
      );
    }
    // Process tracks within dropped folders for the active collection
    for (final folderPath in foldersToProcess) {
      // This helper needs to just find files and dispatch AddTracksFromPaths
      await _addTracksFromFolder(folderPath);
    }
  }

  // Helper for drag/drop folders
  Future<void> _addTracksFromFolder(String dirPath) async {
    debugPrint("Scanning folder for tracks: $dirPath");
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Directory not found: $dirPath")),
        );
        return;
      }
      List<String> audioFilePaths = [];
      await _findAudioFilesRecursively(
        dir,
        audioFilePaths,
      ); // Use existing recursive search
      if (audioFilePaths.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "No supported audio files found in folder '$dirPath'.",
            ),
          ),
        );
        return;
      }
      // Dispatch AddTracksFromPaths to add found files to the *active* collection
      context.read<CollectionBloc>().add(AddTracksFromPaths(audioFilePaths));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Adding ${audioFilePaths.length} files from '$dirPath'...",
          ),
        ),
      );
    } catch (e, stackTrace) {
      debugPrint("Error processing folder: $e\n$stackTrace");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error processing folder '$dirPath': $e")),
      );
    }
  }

  Future<void> _pickAndAddFolder() async {
    // --- MODIFIED: Only allow for 'local' collections ---
    final collectionBloc = context.read<CollectionBloc>();
    final activeCollection =
        (collectionBloc.state is CollectionLoaded)
            ? (collectionBloc.state as CollectionLoaded)
                .activeCollectionDefinition
            : null;

    if (activeCollection?.type != CollectionType.local) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Adding root folders is only supported for 'Local' collections.",
          ),
        ),
      );
      return;
    }

    try {
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Folder to Add to Local Collection',
      );
      if (result != null) {
        collectionBloc.add(AddRootFolder(result)); // Add as root
        await _addTracksFromFolder(result); // Also add tracks within
      }
    } catch (e) {
      debugPrint("Error picking folder: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error selecting folder: $e")));
    }
  }

  Future<void> _pickAndAddAudioFile() async {
    // --- MODIFIED: Check if collection is active ---
    final collectionBloc = context.read<CollectionBloc>();
    if (collectionBloc.state is! CollectionLoaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a collection first.")),
      );
      return;
    }
    // ... (rest of existing logic for picking files) ...
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
            // Handle files picked from memory (e.g., web)
            final tempDir = await getTemporaryDirectory();
            final tempFile = File('${tempDir.path}/${file.name}');
            await tempFile.writeAsBytes(file.bytes!);
            filePathsToAdd.add(tempFile.path);
          }
        }
        if (filePathsToAdd.isNotEmpty) {
          collectionBloc.add(
            AddTracksFromPaths(filePathsToAdd),
          ); // Add to active collection
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
    // --- MODIFIED: Check if collection is active ---
    if (context.read<CollectionBloc>().state is! CollectionLoaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a collection first.")),
      );
      return;
    }
    // ... (rest of existing dialog logic) ...
    _urlController.clear();
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Add Audio from URL'),
            content: TextField(
              controller: _urlController,
              decoration: const InputDecoration(hintText: 'Enter audio URL...'),
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
                    ); // Add to active collection
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

  List<Track> _getCurrentDisplayedTracks() {
    // ... (existing logic, uses BLoC state) ...
    final collectionState = context.read<CollectionBloc>().state;
    List<Track> sourceTracks = [];

    if (collectionState is CollectionLoaded) {
      sourceTracks = collectionState.tracks;
    } else if (collectionState is CollectionLoading &&
        collectionState.currentTracks != null) {
      sourceTracks = collectionState.currentTracks!;
    } else if (collectionState is CollectionError &&
        collectionState.tracks != null) {
      sourceTracks = collectionState.tracks!;
    }

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
      filteredTracks = sourceTracks;
    }

    if (_viewMode == ViewMode.list) {
      return _getSortedTracks(filteredTracks);
    } else {
      return filteredTracks; // Tree View gets filtered but unsorted
    }
  }

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
        // Add cases for other sortable columns if needed
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
    });
  }

  // --- Selection Logic ---
  // Handles selection changes originating from the TrackTableWidget or FolderTreeView
  void _handleSelectionChanged(
    int trackId,
    bool isSelected, {
    bool isShiftPressed = false,
    bool isCtrlPressed = false,
  }) {
    setState(() {
      final List<Track> currentDisplayedTracks = _getCurrentDisplayedTracks();
      if (isSelected) {
        if (isCtrlPressed) {
          _selectedTrackIds.add(trackId);
          _anchorTrackId = trackId;
        } else if (isShiftPressed && _anchorTrackId != null) {
          // ... (Shift-select logic remains the same) ...
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
            // Keep the anchor where the shift-select *started* for subsequent shifts
            // _anchorTrackId = trackId; // Don't update anchor on shift-select range completion
          } else {
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
          if (_anchorTrackId == trackId) _anchorTrackId = null;
        } else {
          // Simple deselection or deselecting one from a shift-selection
          _selectedTrackIds.remove(trackId);
          if (_anchorTrackId == trackId) _anchorTrackId = null;
          // If deselecting the only selected item without modifier, clear anchor
          if (_selectedTrackIds.isEmpty) _anchorTrackId = null;
        }
      }
      _updatePlayerSelection(); // Update player based on new selection
    });
  }

  // Updates the _selectedTrackForPlayer based on the _selectedTrackIds set
  // This now only sets the state, the CombinedAudioPlayerWidget reacts to it
  void _updatePlayerSelection() {
    Track? newSelectedTrack;
    if (_selectedTrackIds.length == 1) {
      final newSelectedId = _selectedTrackIds.first;
      newSelectedTrack = _getTrackById(newSelectedId);
    }
    // Update the state only if the track actually changes
    if (_selectedTrackForPlayer?.id != newSelectedTrack?.id) {
      setState(() {
        _selectedTrackForPlayer = newSelectedTrack;
      });
      // Load audio for the newly selected track (but don't auto-play)
      if (newSelectedTrack != null) {
        _selectTrackForPlayer(
          newSelectedTrack,
        ); // Use helper to load without playing
      } else {
        // Optional: Stop player if selection is cleared? Or leave it playing?
        // context.read<AudioPlayerBloc>().add(StopAudio());
      }
    }
  }

  // --- Context Menu Logic ---
  void _showContextMenu(BuildContext context, Offset tapPosition, Track track) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    // Ensure the right-clicked track is selected
    if (!_selectedTrackIds.contains(track.id)) {
      setState(() {
        _selectedTrackIds.clear();
        if (track.id != null) _selectedTrackIds.add(track.id!);
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
        // <<< List of PopupMenuEntry
        PopupMenuItem(
          value: 'play_now',
          enabled: _selectedTrackIds.length == 1,
          child: const ListTile(
            leading: Icon(Icons.play_arrow),
            title: Text('Play Now'),
          ),
        ),
        // --- CORRECTED USAGE: Use spread operator (...) ---
        // Add the generated playlist items directly to the list
        ..._buildAddToPlaylistItems(context), // <<< Use spread operator

        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'edit',
          enabled: _selectedTrackIds.length == 1,
          child: const ListTile(
            leading: Icon(Icons.edit_note),
            title: Text('Edit Details'),
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
      // --- MODIFIED: Handle value map directly ---
      if (value != null &&
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
              final trackToAdd = collectionState.tracks.firstWhere(
                (t) => t.id == trackId,
              );
              playlistBloc.add(
                AddTrackToPlaylist(
                  playlistId: playlistId,
                  trackPath: trackToAdd.path,
                ),
              );
              addedCount++;
            } catch (e) {
              print(
                "Couldn't find track $trackId to add to playlist $playlistId",
              );
            }
          }
          if (addedCount > 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Added $addedCount track(s) to playlist.'),
              ),
            );
          }
        }
      }
      // Handle other values ('play_now', 'edit', 'delete')
      else if (value == 'play_now' && _selectedTrackIds.length == 1) {
        final trackToPlay = _getTrackById(_selectedTrackIds.first);
        if (trackToPlay != null) _selectAndPlayTrack(trackToPlay);
      } else if (value == 'edit' && _selectedTrackIds.length == 1) {
        final trackToEdit = _getTrackById(_selectedTrackIds.first);
        if (trackToEdit != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Edit action triggered (UI not implemented)'),
            ),
          );
        }
      } else if (value == 'delete') {
        _confirmAndDeleteSelected();
      }
    });
  }

  // Helper for context menu
  Track? _getTrackById(int id) {
    // ... (implementation remains the same) ...
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
  List<PopupMenuEntry<dynamic>> _buildAddToPlaylistItems(BuildContext context) {
    final playlistState = context.read<PlaylistBloc>().state;
    List<PopupMenuEntry<dynamic>> playlistItems = [];

    if (playlistState is PlaylistLoaded && playlistState.playlists.isNotEmpty) {
      // Add a header/divider for the playlist section
      playlistItems.add(const PopupMenuDivider());
      playlistItems.add(
        const PopupMenuItem<dynamic>(
          enabled: false, // Make it non-interactive
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 8.0,
            ), // Adjust padding
            leading: Icon(Icons.playlist_add, size: 18),
            title: Text(
              'Add to Playlist:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ),
      );

      // Add an item for each playlist
      playlistItems.addAll(
        playlistState.playlists.map((playlist) {
          return PopupMenuItem<dynamic>(
            // Return a map to identify the action and playlist ID
            value: {'action': 'add_to_playlist', 'playlist_id': playlist.id},
            child: Padding(
              // Indent playlist names slightly
              padding: const EdgeInsets.only(left: 24.0),
              child: Text(playlist.name),
            ),
          );
        }).toList(),
      );
    } else {
      // Optionally add a disabled item if no playlists exist
      playlistItems.add(const PopupMenuDivider());
      playlistItems.add(
        const PopupMenuItem<dynamic>(
          enabled: false,
          child: ListTile(
            leading: Icon(Icons.playlist_add, size: 18),
            title: Text('Add to Playlist: (None)'),
          ),
        ),
      );
    }

    return playlistItems; // Return the generated list
  }

  // Helper for context menu
  void _confirmAndDeleteSelected() {
    if (_selectedTrackIds.isEmpty) return;
    final count = _selectedTrackIds.length;
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Delete'),
          content: Text(
            'Are you sure you want to remove $count item(s) from your collection? This cannot be undone.',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.of(dialogContext).pop(); // Close dialog first
                final collectionBloc = context.read<CollectionBloc>();
                final audioPlayerBloc = context.read<AudioPlayerBloc>();
                final idsToDelete = List<int>.from(
                  _selectedTrackIds,
                ); // Copy IDs

                // Stop player if the deleted track was playing
                if (_selectedTrackForPlayer != null &&
                    idsToDelete.contains(_selectedTrackForPlayer!.id)) {
                  audioPlayerBloc.add(StopAudio());
                  // Clear player selection state *after* stopping
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() {
                        _selectedTrackForPlayer = null;
                        _currentlyLoadedPathInPlayer =
                            null; // Clear loaded path
                      });
                    }
                  });
                }

                // Dispatch delete events
                for (final trackId in idsToDelete) {
                  collectionBloc.add(RemoveTrack(trackId));
                }

                // Clear selection state *after* dispatching deletes
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() {
                      _selectedTrackIds.clear();
                      _anchorTrackId = null;
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
    // Optimistically update the track in the local state if it's the currently selected one
    if (_selectedTrackForPlayer?.id == trackId) {
      setState(() {
        _selectedTrackForPlayer = _selectedTrackForPlayer?.copyWith(
          rating: newRating,
        );
      });
    }
  }

  // --- Play Next/Previous Track Logic ---
  // Finds the next track in the current view and updates the player state
  void _playNextTrack() {
    if (_selectedTrackForPlayer == null) return;

    final List<Track> currentList = _getCurrentDisplayedTracks();
    if (currentList.isEmpty) return;

    final currentIndex = currentList.indexWhere(
      (t) => t.id == _selectedTrackForPlayer!.id,
    );

    if (currentIndex != -1 && currentIndex < currentList.length - 1) {
      final nextTrack = currentList[currentIndex + 1];
      print("HomeScreen: Selecting next track: ${nextTrack.title}");
      _selectAndPlayTrack(nextTrack); // Use the helper to select and play
    } else {
      print("HomeScreen: No next track available or current track not found.");
      // Optional: Stop playback or loop?
      // context.read<AudioPlayerBloc>().add(StopAudio());
    }
  }

  // Finds the previous track or seeks to beginning
  void _playPreviousTrack() {
    if (_selectedTrackForPlayer == null) return;

    final audioPlayerBloc = context.read<AudioPlayerBloc>();
    final playerState = audioPlayerBloc.state;

    // Check if the currently loaded track matches the selected track
    if (playerState is AudioPlayerLoaded &&
        playerState.currentSource == _selectedTrackForPlayer!.path) {
      final currentPosition = playerState.position;
      // If played past a threshold (e.g., 3 seconds), seek to beginning of current track
      if (currentPosition.inSeconds >= 3) {
        print("HomeScreen: Previous clicked (>3s): Seeking current track to 0");
        audioPlayerBloc.add(const SeekAudio(position: Duration.zero));
        // Ensure it plays if it was paused
        if (!playerState.isPlaying) audioPlayerBloc.add(PlayAudio());
        return; // Don't proceed to the actual previous track
      }
    }

    // --- Default Behavior (Position < 3s OR state doesn't match) ---
    final List<Track> currentList = _getCurrentDisplayedTracks();
    if (currentList.isEmpty) return;

    final currentIndex = currentList.indexWhere(
      (t) => t.id == _selectedTrackForPlayer!.id,
    );

    if (currentIndex > 0) {
      // Found current track and it's not the first one
      final previousTrack = currentList[currentIndex - 1];
      print(
        "HomeScreen: Previous clicked (<=3s): Playing previous track: ${previousTrack.title}",
      );
      _selectAndPlayTrack(previousTrack); // Use helper to select and play
    } else {
      // Current track is the first one or not found, seek to 0
      print(
        "HomeScreen: No previous track available or current track not found. Seeking to 0.",
      );
      audioPlayerBloc.add(const SeekAudio(position: Duration.zero));
      // Ensure it plays if it was paused
      if (playerState is AudioPlayerLoaded && !playerState.isPlaying) {
        audioPlayerBloc.add(PlayAudio());
      }
    }
  }

  // --- Build Method ---
  @override
  Widget build(BuildContext context) {
    // Listen to PlaylistBloc state changes to update the selected playlist if it gets deleted/renamed
    return BlocListener<PlaylistBloc, PlaylistState>(
      listener: (context, playlistState) {
        if (playlistState is PlaylistLoaded &&
            _currentlySelectedPlaylistId != null) {
          // Check if the currently selected playlist still exists
          bool selectedExists = playlistState.playlists.any(
            (p) => p.id == _currentlySelectedPlaylistId,
          );
          if (!selectedExists) {
            // If deleted, deselect it
            setState(() {
              _currentlySelectedPlaylistId = null;
              _currentlySelectedPlaylist = null;
            });
          } else {
            // If it exists, check if its data (e.g., name) has changed
            try {
              final updatedPlaylist = playlistState.playlists.firstWhere(
                (p) => p.id == _currentlySelectedPlaylistId,
              );
              // Use simple comparison for name change detection
              if (_currentlySelectedPlaylist?.name != updatedPlaylist.name) {
                setState(() {
                  _currentlySelectedPlaylist = updatedPlaylist;
                });
              }
            } catch (e) {
              /* ignore if not found during update */
            }
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          // --- >>> LEADING ICON BUTTON ADDED <<< ---
          leading: IconButton(
            icon: const Icon(Icons.home), // Example icon
            tooltip: 'Manage Collections',
            onPressed: () {
              // Navigate to the new Collection Manager Screen
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CollectionManagerScreen(),
                  // Consider fullscreenDialog for modal appearance
                  // fullscreenDialog: true,
                ),
              );
            },
          ),
          // --- >>> END LEADING ICON BUTTON <<< ---
          title: BlocBuilder<CollectionBloc, CollectionState>(
            builder: (context, state) {
              String title = 'Audio Looker';
              if (state is CollectionLoaded) {
                title =
                    state
                        .activeCollectionDefinition
                        .name; // Show active collection name
              } else if (state is CollectionLoading &&
                  state.activeCollectionDefinition != null) {
                title =
                    "${state.activeCollectionDefinition!.name} (Loading...)";
              } else if (state is CollectionInitial) {
                title = "Select Collection";
              } else if (state is CollectionError) {
                title = "Error Loading Collection";
              }
              return Text(title); // Display active collection name or status
            },
          ),
          actions: [
            // ... (keep existing actions: playlist toggle, view toggle, add menu) ...
            IconButton(
              icon: Icon(
                _isPlaylistPanelVisible ? Icons.menu_open : Icons.menu,
              ),
              tooltip: 'Toggle Playlists Panel',
              onPressed: _togglePlaylistPanel,
            ),
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
                // --- MODIFIED: Check if collection is active before showing menu ---
                if (context.read<CollectionBloc>().state is! CollectionLoaded) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        "Please select or create a collection first.",
                      ),
                    ),
                  );
                  return;
                }
                // --- End Check ---
                showMenu(
                  context: context,
                  position: RelativeRect.fromLTRB(
                    MediaQuery.of(context).size.width - 100,
                    kToolbarHeight,
                    MediaQuery.of(context).size.width,
                    0,
                  ),
                  items: <PopupMenuEntry>[
                    const PopupMenuItem(
                      value: 'add_file',
                      child: ListTile(
                        leading: Icon(Icons.audio_file),
                        title: Text('Add Audio File(s)'),
                      ),
                    ),
                    // --- MODIFIED: Only show Add Folder for Local Collections ---
                    if ((context.read<CollectionBloc>().state
                                as CollectionLoaded)
                            .activeCollectionDefinition
                            .type ==
                        CollectionType.local)
                      const PopupMenuItem(
                        value: 'add_folder',
                        child: ListTile(
                          leading: Icon(Icons.folder_open),
                          title: Text('Add Folder to Collection'),
                        ),
                      ),
                    // --- End Modification ---
                    const PopupMenuItem(
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
        body: Focus(
          // <-- Add Focus widget
          focusNode: _focusNode,
          autofocus: true, // Request focus automatically
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.space) {
              print("Spacebar pressed!"); // For debugging
              final audioBloc = context.read<AudioPlayerBloc>();
              final currentState = audioBloc.state;

              if (currentState is AudioPlayerLoaded) {
                if (currentState.isPlaying) {
                  print("Dispatching PauseAudio"); // For debugging
                  audioBloc.add(PauseAudio());
                } else {
                  // Also handle playing from the end
                  if (currentState.position >= currentState.duration &&
                      currentState.duration > Duration.zero) {
                    print("Seeking to 0 before playing"); // For debugging
                    audioBloc.add(const SeekAudio(position: Duration.zero));
                    // Add a small delay to ensure seek completes before play
                    Future.delayed(const Duration(milliseconds: 50), () {
                      if (mounted) {
                        // Check if widget is still mounted
                        print(
                          "Dispatching PlayAudio after seek",
                        ); // For debugging
                        audioBloc.add(PlayAudio());
                      }
                    });
                  } else {
                    print("Dispatching PlayAudio"); // For debugging
                    audioBloc.add(PlayAudio());
                  }
                }
                return KeyEventResult.handled; // Indicate the event was handled
              } else {
                print(
                  "Player not loaded, cannot toggle play.",
                ); // For debugging
              }
            }
            return KeyEventResult
                .ignored; // Let other handlers process the event
          },
          child: Row(
            children: [
              // --- Playlist Panel (Animated) ---
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
                clipBehavior:
                    Clip.hardEdge, // Prevent content overflow during animation
                child: Visibility(
                  visible: _isPlaylistPanelVisible,
                  maintainState: false, // Don't keep state when hidden
                  child: PlaylistDrawer(
                    selectedPlaylistId: _currentlySelectedPlaylistId,
                    onPlaylistSelected: _handlePlaylistSelected,
                  ),
                ),
              ),

              // --- Main Content Area ---
              Expanded(
                child: Column(
                  // Use Column to stack Search, Content, and Player
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // --- Search bar and Playlist Header ---
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
                          // Optional: Clear button
                        ),
                      ),
                    ),
                    // Display selected playlist name header
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

                    // --- Collection Content Area (Table or Tree View) ---
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
                                List<Tag> allTags =
                                    []; // Get tags for tree view highlighting

                                if (state is CollectionLoading) {
                                  isLoading = true;
                                  allTracks = state.currentTracks ?? [];
                                  rootFolders = state.currentRootFolders ?? [];
                                  allTags = state.currentAllTags ?? [];
                                } else if (state is CollectionLoaded) {
                                  isLoading = false;
                                  allTracks = state.tracks;
                                  rootFolders = state.rootFolders;
                                  allTags = state.allTags;
                                } else if (state is CollectionError) {
                                  isLoading =
                                      false; // Assume loading finished on error
                                  allTracks = state.tracks ?? [];
                                  // Still try to get roots/tags if available from previous state?
                                  // For simplicity, let's assume they might be empty on error.
                                  rootFolders = [];
                                  allTags = [];
                                  // Error message is shown via listener
                                } else if (state is CollectionInitial) {
                                  isLoading = true;
                                }
                                // --------------------------------------------------

                                if (isLoading &&
                                    allTracks.isEmpty &&
                                    rootFolders.isEmpty) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }

                                // Get the list relevant for the current view & filter
                                List<Track> displayedTracks =
                                    _getCurrentDisplayedTracks();

                                // --- Empty State Handling ---
                                if (!isLoading &&
                                    displayedTracks.isEmpty &&
                                    _viewMode == ViewMode.list) {
                                  // ... (empty state logic remains the same) ...
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
                                      /* ... Empty Collection Message ... */
                                    );
                                  } else if (allTracks.isEmpty &&
                                      rootFolders.isNotEmpty) {
                                    return const Center(
                                      child: Text(
                                        'No audio tracks found in the collection yet.',
                                      ),
                                    );
                                  }
                                  return const Center(
                                    child: Text('No tracks to display.'),
                                  ); // Fallback
                                }
                                if (!isLoading &&
                                    rootFolders.isEmpty &&
                                    _viewMode == ViewMode.tree) {
                                  return const Center(
                                    child: Text(
                                      'No root folders added. Add folders via (+) or drag & drop.',
                                    ),
                                  );
                                }
                                // --- End Empty State ---

                                // --- Build View (Table or Tree) ---
                                return Opacity(
                                  opacity:
                                      isLoading &&
                                              (allTracks.isNotEmpty ||
                                                  rootFolders.isNotEmpty)
                                          ? 0.6
                                          : 1.0, // Dim if loading in background
                                  child: Container(
                                    color:
                                        _currentlySelectedPlaylistId != null
                                            ? Theme.of(context)
                                                .colorScheme
                                                .surfaceVariant
                                                .withOpacity(0.3)
                                            : null, // Subtle background for playlist view
                                    child:
                                        _viewMode == ViewMode.list
                                            ? TrackTableWidget(
                                              tracks: displayedTracks,
                                              key: ValueKey(
                                                'track-table-${_currentlySelectedPlaylistId ?? 'all'}-${_sortColumnName}-${_sortDirectionSf.name}',
                                              ), // Use enum name
                                              selectedTrackIds:
                                                  _selectedTrackIds,
                                              audioPlayerBloc:
                                                  context
                                                      .read<AudioPlayerBloc>(),
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
                                                  _selectAndPlayTrack,
                                              onEditMetadata:
                                                  _selectAndOpenPlayer,
                                            )
                                            : FolderTreeView(
                                              tracks:
                                                  allTracks, // Tree view needs all tracks
                                              key: ValueKey(
                                                'folder-tree-${_currentlyLoadedPathInPlayer ?? 'none'}',
                                              ), // Key includes loaded path
                                              rootFolders: rootFolders,
                                              selectedTrack:
                                                  _selectedTrackForPlayer,
                                              currentlyLoadedPath:
                                                  _currentlyLoadedPathInPlayer, // Pass the path loaded in the player
                                              onTrackSelected: (track) {
                                                // Single click in tree selects for player but doesn't auto-play
                                                _handleSelectionChanged(
                                                  track.id!,
                                                  true,
                                                ); // Select in UI
                                                _selectTrackForPlayer(
                                                  track,
                                                ); // Load in player
                                              },
                                              onTrackDeleted: (trackId) {
                                                // Handle deletion initiated from tree view
                                                _confirmAndDeleteSelected(); // Use existing confirmation logic
                                              },
                                              // Optional: Add onTrackDoubleTap: _selectAndPlayTrack,
                                            ),
                                  ),
                                );
                              },
                            ), // End BlocConsumer
                            // --- Drag Overlay ---
                            if (_isDragging)
                              Container(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withOpacity(0.1),
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.upload_file,
                                        size: 60,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary.withOpacity(0.5),
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        "Drop files or folders here",
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withOpacity(0.7),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            // --- Loading Indicator Overlay (for background processing) ---
                            BlocBuilder<CollectionBloc, CollectionState>(
                              builder: (context, state) {
                                if (state is CollectionLoading &&
                                    (state.currentTracks?.isNotEmpty ??
                                        false)) {
                                  // Show only if loading in background with existing items visible
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
                    ), // End Expanded Content Area
                    if (_selectedTrackForPlayer != null)
                      CombinedAudioPlayerWidget(
                        key: ValueKey(_selectedTrackForPlayer!.id),
                        track: _selectedTrackForPlayer!,
                        // --- Pass state and callbacks ---
                        isMinimized: _isMinimized, // Pass state
                        onToggle: _handlePlayerToggle, // Pass toggle callback
                        // REMOVED animationController prop
                      ),
                  ],
                ),
              ), // End Expanded Main Content
            ],
          ),
        ),
      ),
    );
  }
} // End _HomeScreenState

// Helper extension (keep if needed)
extension TrackListNullOrEmpty on List<Track>? {
  bool get isNullOrEmpty => this == null || this!.isEmpty;
}
