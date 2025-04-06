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

  // --- Grid/Table State ---
  String _sortColumnName = 'title';
  DataGridSortDirection _sortDirectionSf = DataGridSortDirection.ascending;
  final Set<int> _selectedTrackIds = {};
  int? _anchorTrackId;
  bool _isPlaylistPanelVisible = true;

  String? _currentlySelectedPlaylistId;
  Playlist? _currentlySelectedPlaylist;

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
      _selectedTrackForPlayer = null;
      _anchorTrackId = null;
    });
  }

  void _togglePlaylistPanel() {
    setState(() {
      _isPlaylistPanelVisible = !_isPlaylistPanelVisible;
    });
  }

  void _handlePlaylistSelected(String playlistId) {
    final playlistState =
        context.read<PlaylistBloc>().state; // Read PlaylistBloc state

    setState(() {
      if (_currentlySelectedPlaylistId == playlistId) {
        // Deselect if the same playlist is tapped again
        _currentlySelectedPlaylistId = null;
        _currentlySelectedPlaylist = null;
        print("Playlist deselected.");
      } else {
        // Select the new playlist
        if (playlistState is PlaylistLoaded) {
          try {
            // Find the playlist object from the loaded playlists
            _currentlySelectedPlaylist = playlistState.playlists.firstWhere(
              (p) => p.id == playlistId,
            );
            _currentlySelectedPlaylistId = playlistId;
            print("Playlist selected: ${_currentlySelectedPlaylist?.name}");
          } catch (e) {
            // Handle case where playlist might not be found (e.g., deleted just before tap)
            _currentlySelectedPlaylist = null;
            _currentlySelectedPlaylistId = null;
            print("Error selecting playlist ID $playlistId: $e");
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Error: Could not select playlist.'),
              ),
            );
          }
        } else {
          // Handle case where playlists are not loaded yet
          _currentlySelectedPlaylist = null;
          _currentlySelectedPlaylistId = null;
          print("Cannot select playlist: Playlists not loaded.");
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Playlists are still loading...')),
          );
        }
      }
      // Optional: Clear track selection when changing playlist view
      _selectedTrackIds.clear();
      _selectedTrackForPlayer = null;
      _anchorTrackId = null;
      _updatePlayerSelection(); // Assuming this method deselects player if needed
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

  // --- File/Folder Handling Methods ---
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
  // --- End File/Folder Handling ---

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
      _selectedTrackIds.clear();
      _selectedTrackForPlayer = null;
      _anchorTrackId = null;
    });
  }
  // --- End Sorting Logic ---

  // --- Selection Logic ---
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
            _anchorTrackId = trackId;
          } else {
            _selectedTrackIds.clear();
            _selectedTrackIds.add(trackId);
            _anchorTrackId = trackId;
          }
        } else {
          _selectedTrackIds.clear();
          _selectedTrackIds.add(trackId);
          _anchorTrackId = trackId;
        }
      } else {
        if (isCtrlPressed) {
          _selectedTrackIds.remove(trackId);
          if (_anchorTrackId == trackId) _anchorTrackId = null;
        } else {
          _selectedTrackIds.remove(trackId);
          if (_anchorTrackId == trackId) _anchorTrackId = null;
        }
      }
      _updatePlayerSelection();
    });
  }

  List<Track> _getCurrentDisplayedTracks() {
    final state = context.read<CollectionBloc>().state;
    List<Track> tracks = [];
    if (state is CollectionLoaded) {
      tracks = state.tracks;
    } else if (state is CollectionLoading && state.currentTracks != null) {
      tracks = state.currentTracks!;
    }
    return _viewMode == ViewMode.list ? _getSortedTracks(tracks) : tracks;
  }

  void _updatePlayerSelection() {
    // This method should handle setting _selectedTrackForPlayer based on _selectedTrackIds
    // For now, ensure it can handle nulling the player selection
    if (_selectedTrackIds.isEmpty && _selectedTrackForPlayer != null) {
      setState(() {
        _selectedTrackForPlayer = null;
        // Optionally stop audio player via bloc event
      });
    }
    // Add logic to set _selectedTrackForPlayer if _selectedTrackIds has one item
    else if (_selectedTrackIds.length == 1) {
      final newSelectedTrack = _getTrackById(_selectedTrackIds.first);
      if (_selectedTrackForPlayer?.id != newSelectedTrack?.id) {
        setState(() {
          _selectedTrackForPlayer = newSelectedTrack;
          // ... rest of your existing logic in _updatePlayerSelection ...
        });
        if (newSelectedTrack != null) {
          context.read<AudioPlayerBloc>().add(
            LoadAudio(
              source: newSelectedTrack.path,
              isUrl: newSelectedTrack.isUrl,
            ),
          );
        }
      }
    }
  }
  // --- End Selection Logic ---

  // --- Context Menu Logic ---
  void _showContextMenu(BuildContext context, Offset tapPosition, Track track) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    if (!_selectedTrackIds.contains(track.id)) {
      setState(() {
        _selectedTrackIds.clear();
        _selectedTrackIds.add(track.id!);
        _anchorTrackId = track.id;
        _updatePlayerSelection();
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
          value: 'play_now',
          enabled: _selectedTrackIds.length == 1,
          child: ListTile(
            leading: Icon(Icons.play_arrow),
            title: Text('Play Now'),
          ),
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
      if (value == 'play_now' && _selectedTrackIds.length == 1) {
        final trackToPlay = _getTrackById(_selectedTrackIds.first);
        if (trackToPlay != null) {
          setState(() {
            _selectedTrackForPlayer = trackToPlay;
            if (_isPlayerMinimized) _togglePlayerSize();
          });
          context.read<AudioPlayerBloc>().add(
            LoadAudio(source: trackToPlay.path, isUrl: trackToPlay.isUrl),
          );
          Future.delayed(const Duration(milliseconds: 100), () {
            final state = context.read<AudioPlayerBloc>().state;
            if (state is AudioPlayerLoaded &&
                state.currentSource == trackToPlay.path) {
              context.read<AudioPlayerBloc>().add(PlayAudio());
            }
          });
        }
      } else if (value == 'edit' && _selectedTrackIds.length == 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Edit action (not implemented)')),
        );
      } else if (value == 'delete') {
        _confirmAndDeleteSelected();
      }
    });
  }

  Track? _getTrackById(int id) {
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

  // --- Rating Handler ---
  void _handleRatingChanged(int trackId, int newRating) {
    print("Rating changed in table: Track $trackId -> $newRating stars");
    context.read<CollectionBloc>().add(UpdateTrackRating(trackId, newRating));
  }
  // --- End rating handler ---

  @override
  Widget build(BuildContext context) {
    final audioPlayerBloc = context.read<AudioPlayerBloc>();

    // Use a BlocListener to react to PlaylistBloc changes if needed
    // e.g., to clear selection if the selected playlist is deleted
    return BlocListener<PlaylistBloc, PlaylistState>(
      listener: (context, playlistState) {
        if (playlistState is PlaylistLoaded &&
            _currentlySelectedPlaylistId != null) {
          // Check if the selected playlist still exists
          bool selectedExists = playlistState.playlists.any(
            (p) => p.id == _currentlySelectedPlaylistId,
          );
          if (!selectedExists) {
            // Playlist was deleted, clear selection
            setState(() {
              _currentlySelectedPlaylistId = null;
              _currentlySelectedPlaylist = null;
              print("Selected playlist was deleted, clearing selection.");
            });
          } else {
            // Update playlist details if they changed (e.g., name, tracks)
            try {
              final updatedPlaylist = playlistState.playlists.firstWhere(
                (p) => p.id == _currentlySelectedPlaylistId,
              );
              // Avoid unnecessary rebuilds if the object is identical
              if (!identical(_currentlySelectedPlaylist, updatedPlaylist) &&
                  _currentlySelectedPlaylist != updatedPlaylist) {
                setState(() {
                  _currentlySelectedPlaylist = updatedPlaylist;
                });
              }
            } catch (e) {
              /* ignore if not found */
            }
          }
        }
      },
      child: Scaffold(
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
            const SizedBox(width: 8),
          ],
        ),
        body: Row(
          children: [
            // Playlist Panel
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
                maintainState: false,
                child: PlaylistDrawer(
                  // Or PlaylistPanel
                  selectedPlaylistId: _currentlySelectedPlaylistId,
                  onPlaylistSelected: _handlePlaylistSelected,
                ),
              ),
            ),

            // --- Main Content Area ---
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch, // Stretch header
                children: [
                  // Search bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        // Filled placeholder
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

                  // Playlist Header (conditionally displayed)
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
                              // Pass the current ID to deselect, or null if you prefer
                              onPressed:
                                  () => _handlePlaylistSelected(
                                    _currentlySelectedPlaylistId!,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Collection content area (Table or Tree View + Player)
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
                              // Filled placeholder (kept existing listener logic)
                              if (state is CollectionError) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error: ${state.message}'),
                                    backgroundColor: Colors.redAccent,
                                  ),
                                );
                              }
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
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
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
                              // Logic to get tracks, folders, loading state
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
                                allTracks = state.tracks ?? [];
                              } else if (state is CollectionInitial) {
                                isLoading = true;
                              }

                              if (isLoading && allTracks.isEmpty) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }

                              // FILTER tracks based on selected playlist
                              List<Track> tracksToShow;
                              if (_currentlySelectedPlaylist != null) {
                                final playlistTrackPaths = Set<String>.from(
                                  _currentlySelectedPlaylist!.trackPaths,
                                );
                                tracksToShow =
                                    allTracks
                                        .where(
                                          (track) => playlistTrackPaths
                                              .contains(track.path),
                                        )
                                        .toList();
                              } else {
                                tracksToShow = allTracks; // Show all tracks
                              }

                              // Apply sorting
                              List<Track> displayedTracks =
                                  _viewMode == ViewMode.list
                                      ? _getSortedTracks(tracksToShow)
                                      : tracksToShow;

                              // Empty State Handling
                              if (!isLoading && displayedTracks.isEmpty) {
                                if (_currentlySelectedPlaylist != null) {
                                  return Center(
                                    child: Text(
                                      'Playlist "${_currentlySelectedPlaylist!.name}" is empty.',
                                    ),
                                  );
                                } else if (_searchController.text.isNotEmpty) {
                                  return Center(
                                    child: Text(
                                      'No tracks found for "${_searchController.text}"',
                                    ),
                                  );
                                } else if (rootFolders.isEmpty &&
                                    _viewMode == ViewMode.list) {
                                  // Filled placeholder: Your original empty collection message
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
                                            'Add files/folders using drag & drop.',
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
                                  // Handle empty state for tree view if needed
                                  return const Center(
                                    child: Text('No root folders added.'),
                                  );
                                }
                              }

                              // Build the appropriate view (List or Tree) within a Column with the player
                              return Column(
                                children: [
                                  Expanded(
                                    child: Opacity(
                                      opacity: isLoading ? 0.6 : 1.0,
                                      child: Container(
                                        color:
                                            _currentlySelectedPlaylistId != null
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .surfaceVariant
                                                    .withOpacity(0.3)
                                                : null,
                                        child:
                                            _viewMode == ViewMode.list
                                                ? TrackTableWidget(
                                                  tracks: displayedTracks,
                                                  key: const ValueKey(
                                                    'track-table',
                                                  ),
                                                  selectedTrackIds:
                                                      _selectedTrackIds,
                                                  audioPlayerBloc:
                                                      audioPlayerBloc,
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
                                                )
                                                : FolderTreeView(
                                                  tracks:
                                                      allTracks, // Tree view needs all tracks
                                                  key: const ValueKey(
                                                    'folder-tree',
                                                  ),
                                                  rootFolders: rootFolders,
                                                  selectedTrack:
                                                      _selectedTrackForPlayer,
                                                  onTrackSelected: (track) {
                                                    // Filled placeholder
                                                    setState(() {
                                                      _selectedTrackIds.clear();
                                                      if (track.id != null) {
                                                        _selectedTrackIds.add(
                                                          track.id!,
                                                        );
                                                        _anchorTrackId =
                                                            track.id;
                                                      } else {
                                                        _anchorTrackId = null;
                                                      }
                                                      _updatePlayerSelection();
                                                    });
                                                  },
                                                  onTrackDeleted: (trackId) {
                                                    // Filled placeholder
                                                    context
                                                        .read<CollectionBloc>()
                                                        .add(
                                                          RemoveTrack(trackId),
                                                        );
                                                  },
                                                ),
                                      ),
                                    ),
                                  ),
                                  // --- Audio Player ---
                                  if (_selectedTrackForPlayer != null)
                                    AnimatedContainer(
                                      // Filled placeholder
                                      duration: const Duration(
                                        milliseconds: 300,
                                      ),
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
                                          // Player Minimize/Expand Toggle Bar
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
                                                  onPressed: _togglePlayerSize,
                                                  tooltip:
                                                      _isPlayerMinimized
                                                          ? 'Expand player'
                                                          : 'Minimize player',
                                                ),
                                              ],
                                            ),
                                          ),
                                          // Player Content Area
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
                                                    milliseconds: 200,
                                                  ),
                                                  child: IgnorePointer(
                                                    ignoring:
                                                        _isPlayerMinimized,
                                                    child: AudioPlayerWidget(
                                                      key: ValueKey(
                                                        _selectedTrackForPlayer!
                                                            .id,
                                                      ),
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
                                                      onNotesChanged: (notes) {
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
                                                        }
                                                      },
                                                    ),
                                                  ),
                                                ),
                                                // Minimized Player
                                                AnimatedOpacity(
                                                  opacity:
                                                      _isPlayerMinimized
                                                          ? 1.0
                                                          : 0.0,
                                                  duration: const Duration(
                                                    milliseconds: 200,
                                                  ),
                                                  child: IgnorePointer(
                                                    ignoring:
                                                        !_isPlayerMinimized,
                                                    child:
                                                        _buildMinimizedPlayer(),
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
                              // Filled placeholder
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
                                    color:
                                        Theme.of(context).colorScheme.surface,
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
                                        Icons.file_download_done_outlined,
                                        size: 48,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'Drop Audio Files or Folders Here',
                                        style:
                                            Theme.of(
                                              context,
                                            ).textTheme.titleMedium,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          // Loading Indicator Overlay
                          BlocBuilder<CollectionBloc, CollectionState>(
                            // Filled placeholder
                            builder: (context, state) {
                              if (state is CollectionLoading) {
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
                        ], // End Stack children
                      ), // End Stack
                    ), // End DropTarget
                  ), // End Expanded (Collection content area)
                ], // End Main Column Children
              ), // End Main Column
            ), // End Expanded (Main Content Area)
          ], // End Row Children
        ), // End Row
      ), // End BlocListener
    ); // End Scaffold
  }

  // Minimized player view
  Widget _buildMinimizedPlayer() {
    if (_selectedTrackForPlayer == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      height: double.infinity,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(Icons.music_note, color: Colors.white70, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedTrackForPlayer!.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 2),
                Text(
                  _selectedTrackForPlayer!.artist,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey[400]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          BlocBuilder<AudioPlayerBloc, AudioPlayerState>(
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
                  IconButton(
                    icon: Icon(Icons.skip_previous),
                    onPressed: () {},
                    tooltip: 'Previous',
                    iconSize: 24,
                  ),
                  IconButton(
                    icon: Icon(
                      isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                      size: 32,
                    ),
                    onPressed: () {
                      final bloc = context.read<AudioPlayerBloc>();
                      if (isCurrentTrackLoaded) {
                        if (isPlaying) {
                          bloc.add(PauseAudio());
                        } else {
                          bloc.add(PlayAudio());
                        }
                      } else {
                        bloc.add(
                          LoadAudio(
                            source: _selectedTrackForPlayer!.path,
                            isUrl: _selectedTrackForPlayer!.isUrl,
                          ),
                        );
                        Future.delayed(const Duration(milliseconds: 100), () {
                          final postDelayState =
                              context.read<AudioPlayerBloc>().state;
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
                  IconButton(
                    icon: Icon(Icons.skip_next),
                    onPressed: () {},
                    tooltip: 'Next',
                    iconSize: 24,
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
