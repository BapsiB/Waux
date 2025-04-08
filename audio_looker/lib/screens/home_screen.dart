// lib/screens/home_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

// Import BLoCs
import 'package:audio_looker/blocs/track_management/track_management_bloc.dart';
import 'package:audio_looker/blocs/collection_management/collection_management_bloc.dart';
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

// Import handlers
import 'package:audio_looker/handlers/track_selection_handler.dart';
import 'package:audio_looker/handlers/context_menu_handler.dart';
import 'package:audio_looker/handlers/file_handler.dart';
import 'package:audio_looker/handlers/player_control_handler.dart';

// Import the Collection Manager Screen
import 'package:audio_looker/screens/collection_manager_screen.dart';

// Define view mode enum
enum ViewMode { list, tree }

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // State variables
  final TextEditingController _searchController = TextEditingController();
  Track? _selectedTrackForPlayer;
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
  Set<int> _selectedTrackIds = {};
  int? _anchorTrackId;
  bool _isPlaylistPanelVisible = true;
  String? _currentlySelectedPlaylistId;
  Playlist? _currentlySelectedPlaylist;
  bool _isMinimized = true;
  String? _currentlyLoadedPathInPlayer;

  // Create handler instances lazily
  late TrackSelectionHandler _trackSelectionHandler;
  late ContextMenuHandler _contextMenuHandler;
  late FileHandler _fileHandler;
  late PlayerControlHandler _playerControlHandler;

  @override
  void initState() {
    super.initState();

    // Initial data loading
    context.read<CollectionManagementBloc>().add(LoadCollectionList());
    context.read<PlaylistBloc>().add(LoadPlaylists());

    _searchController.addListener(_onSearchChanged);

    // Set up listeners
    _setupAudioPlayerListener();
    _setupCollectionListener();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Initialize handlers when context is ready
    _initializeHandlers();
  }

  void _initializeHandlers() {
    _trackSelectionHandler = TrackSelectionHandler(
      context: context,
      selectedTrackIds: _selectedTrackIds,
      anchorTrackId: _anchorTrackId,
      selectedTrackForPlayer: _selectedTrackForPlayer,
      currentlyLoadedPathInPlayer: _currentlyLoadedPathInPlayer,
      sortColumnName: _sortColumnName,
      sortDirectionSf: _sortDirectionSf,
      currentlySelectedPlaylist: _currentlySelectedPlaylist,
    );

    _contextMenuHandler = ContextMenuHandler(
      context: context,
      selectedTrackIds: _selectedTrackIds,
      onSelectionChanged: _handleSelectionChanged,
      onPlayTrack: _selectAndPlayTrack,
    );

    _fileHandler = FileHandler(
      context: context,
      supportedExtensions: _supportedExtensions,
    );

    _playerControlHandler = PlayerControlHandler(
      context: context,
      selectedTrackForPlayer: _selectedTrackForPlayer,
      getCurrentDisplayedTracksFn:
          () => _trackSelectionHandler.getCurrentDisplayedTracks(),
    );
  }

  void _setupAudioPlayerListener() {
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
  }

  void _setupCollectionListener() {
    context.read<CollectionManagementBloc>().stream.listen((collectionState) {
      if (!mounted) return; // Ensure widget is still mounted

      // Check if the state indicates a collection is successfully loaded and active
      if (collectionState is CollectionManagementLoaded &&
          collectionState.activeCollectionDefinition != null) {
        final activeCollectionId =
            collectionState.activeCollectionDefinition!.id;
        print(
          "HomeScreen Listener: Collection '${collectionState.activeCollectionDefinition!.name}' loaded (ID: $activeCollectionId).",
        );

        // --- Trigger Loading for other BLoCs ---
        print("HomeScreen Listener: Reloading playlists.");
        context.read<PlaylistBloc>().add(LoadPlaylists());

        print("HomeScreen Listener: Reloading tracks and folders.");
        context.read<TrackManagementBloc>().add(
          LoadTracksForActiveCollection(),
        );

        // *** ADDED: Trigger Folder Sync ***
        print(
          "HomeScreen Listener: Triggering folder sync for active collection.",
        );
        context.read<TrackManagementBloc>().add(
          SyncActiveCollectionFolders(),
        ); // <<< ADD THIS DISPATCH
      } else if (collectionState is CollectionManagementLoaded &&
          collectionState.activeCollectionDefinition == null) {
        // Handle case where loading finished but no collection is active
        print(
          "HomeScreen Listener: Collection Management loaded, but no active collection.",
        );
        // Clear potentially displayed tracks from previous collection
        context.read<TrackManagementBloc>().add(
          const SearchTracks(''),
        ); // Clear search/filter
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handlePlayerToggle() {
    if (!mounted) return;
    setState(() {
      _isMinimized = !_isMinimized;
    });
  }

  void _onSearchChanged() {
    // Check if a collection is actually loaded before searching
    if (context.read<TrackManagementBloc>().state is TrackManagementLoaded) {
      context.read<TrackManagementBloc>().add(
        SearchTracks(_searchController.text),
      );
      setState(() {
        _selectedTrackIds.clear();
        _anchorTrackId = null;
      });
    } else {
      print("Cannot search: No collection loaded.");
    }
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
      _anchorTrackId = null;
    });

    // Update handlers with new state
    _initializeHandlers();
  }

  // void _selectAndPlayTrack(Track track) {
  //   setState(() {
  //     _selectedTrackForPlayer = track;
  //     _selectedTrackIds.clear();
  //     if (track.id != null) _selectedTrackIds.add(track.id!);
  //     _anchorTrackId = track.id;
  //   });

  //   _initializeHandlers(); // Update handlers with new selection
  //   _trackSelectionHandler.selectAndPlayTrack(track);
  // }

  void _selectAndOpenPlayer(Track track) {
    setState(() {
      _selectedTrackForPlayer = track;
      _selectedTrackIds.clear();
      if (track.id != null) _selectedTrackIds.add(track.id!);
      _anchorTrackId = track.id;
      _isMinimized = false; // Ensure player opens
    });

    _initializeHandlers(); // Update handlers with new selection
    _trackSelectionHandler.selectAndOpenPlayer(track);
  }

  void _selectTrackForPlayer(Track track) {
    setState(() {
      _selectedTrackForPlayer = track;
    });

    _initializeHandlers(); // Update handlers with new selection
    _trackSelectionHandler.selectTrackForPlayer(track);
  }

  void _toggleViewMode() {
    setState(() {
      _viewMode = _viewMode == ViewMode.list ? ViewMode.tree : ViewMode.list;
      _selectedTrackIds.clear();
      _anchorTrackId = null;
    });
  }

  // Selection handler that updates state
  void _handleSelectionChanged(
    int trackId,
    bool isSelected, {
    bool isShiftPressed = false,
    bool isCtrlPressed = false,
  }) {
    _trackSelectionHandler.handleSelectionChanged(
      trackId,
      isSelected,
      isShiftPressed: isShiftPressed,
      isCtrlPressed: isCtrlPressed,
      onSelectionStateChanged: (newSelectedIds, newAnchorId, newSelectedTrack) {
        setState(() {
          _selectedTrackIds = Set<int>.from(newSelectedIds);

          _anchorTrackId = newAnchorId;

          // Update player selection if it changed
          if (_selectedTrackForPlayer?.id != newSelectedTrack?.id) {
            _selectedTrackForPlayer = newSelectedTrack;

            // Load the new track if selected
            if (newSelectedTrack != null) {
              _trackSelectionHandler.selectTrackForPlayer(newSelectedTrack);
            }
          }
        });
      },
    );
  }

  // Rating change handler
  void _handleRatingChanged(int trackId, int newRating) {
    _trackSelectionHandler.handleRatingChanged(trackId, newRating);

    // Optimistically update local state
    if (_selectedTrackForPlayer?.id == trackId) {
      setState(() {
        _selectedTrackForPlayer = _selectedTrackForPlayer?.copyWith(
          rating: newRating,
        );
      });
    }
  }

  // Sort handler
  void _handleSortChanged(String columnName, DataGridSortDirection direction) {
    setState(() {
      _sortColumnName = columnName;
      _sortDirectionSf = direction;
    });

    // Update handler with new sort settings
    _initializeHandlers();
  }

  // Play next track
  void _playNextTrack() {
    _playerControlHandler.playNextTrack(onTrackSelected: _selectAndPlayTrack);
  }

  // Play previous track
  void _playPreviousTrack() {
    _playerControlHandler.playPreviousTrack(
      onTrackSelected: _selectAndPlayTrack,
    );
  }

  void _selectAndPlayTrack(Track track) {
    setState(() {
      _selectedTrackForPlayer = track;
      // --- MODIFIED: Create a new Set ---
      _selectedTrackIds = {
        if (track.id != null) track.id!,
      }; // Creates a new Set with the single ID
      // --- END MODIFICATION ---
      _anchorTrackId = track.id;
    });

    _initializeHandlers();
    _trackSelectionHandler.selectAndPlayTrack(track);
  }

  // --- Build Method ---
  @override
  Widget build(BuildContext context) {
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
        appBar: _buildAppBar(),
        body: Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _handleKeyEvent,
          child: Row(
            children: [
              _buildPlaylistPanel(),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSearchBar(),
                    if (_currentlySelectedPlaylist != null)
                      _buildPlaylistHeader(),
                    Expanded(child: _buildContentArea()),
                    if (_selectedTrackForPlayer != null)
                      CombinedAudioPlayerWidget(
                        key: ValueKey(_selectedTrackForPlayer!.id),
                        track: _selectedTrackForPlayer!,
                        isMinimized: _isMinimized,
                        onToggle: _handlePlayerToggle,
                        onPreviousPressed: _playPreviousTrack,
                        onNextPressed: _playNextTrack,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Handle keyboard events
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.space) {
      _playerControlHandler.togglePlayPause();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // Build the app bar
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.home),
        tooltip: 'Manage Collections',
        onPressed:
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const CollectionManagerScreen(),
              ),
            ),
      ),
      title: BlocBuilder<CollectionManagementBloc, CollectionManagementState>(
        builder: (context, state) {
          String title = 'Audio Looker';
          if (state is CollectionManagementLoaded &&
              state.activeCollectionDefinition != null) {
            title = state.activeCollectionDefinition!.name;
          } else if (state is CollectionManagementLoading &&
              state.activeCollectionDefinition != null) {
            title = "${state.activeCollectionDefinition!.name} (Loading...)";
          } else if (state is CollectionManagementInitial) {
            title = "Select Collection";
          } else if (state is CollectionManagementError) {
            title = "Error Loading Collection";
          }
          return Text(title);
        },
      ),
      actions: [
        IconButton(
          icon: Icon(_isPlaylistPanelVisible ? Icons.menu_open : Icons.menu),
          tooltip: 'Toggle Playlists Panel',
          onPressed: _togglePlaylistPanel,
        ),
        IconButton(
          icon: Icon(
            _viewMode == ViewMode.list ? Icons.account_tree : Icons.table_rows,
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
          onPressed: _showAddMenu,
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  // Show add menu
  void _showAddMenu() {
    // 1. Read from CollectionManagementBloc to check for an active collection
    final collectionMgmtState = context.read<CollectionManagementBloc>().state;

    // Check if loaded AND if there's an active collection definition
    if (collectionMgmtState is! CollectionManagementLoaded ||
        collectionMgmtState.activeCollectionDefinition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please select or create a collection first."),
        ),
      );
      return;
    }

    // We know state is CollectionManagementLoaded and activeCollectionDefinition is not null here
    final activeCollectionDef = collectionMgmtState.activeCollectionDefinition!;

    showMenu<String>(
      // Specify type argument for value
      context: context,
      position: RelativeRect.fromLTRB(
        MediaQuery.of(context).size.width - 100,
        kToolbarHeight, // Assuming kToolbarHeight is defined or imported
        MediaQuery.of(context).size.width,
        0,
      ),
      items: <PopupMenuEntry<String>>[
        // Specify type argument for PopupMenuEntry
        const PopupMenuItem<String>(
          // Specify type argument
          value: 'add_file',
          child: ListTile(
            leading: Icon(Icons.audio_file),
            title: Text('Add Audio File(s)'),
          ),
        ),
        // 2. Check collection type from the active definition for 'Add Folder'
        if (activeCollectionDef.type == CollectionType.local)
          const PopupMenuItem<String>(
            // Specify type argument
            value: 'add_folder',
            child: ListTile(
              leading: Icon(Icons.folder_open),
              title: Text('Add Folder to Collection'),
            ),
          ),
        const PopupMenuItem<String>(
          // Specify type argument
          value: 'add_url',
          child: ListTile(
            leading: Icon(Icons.link),
            title: Text('Add Audio from URL'),
          ),
        ),
      ],
    ).then((value) {
      // 3. Call the appropriate helper method (which should dispatch to TrackManagementBloc)
      if (value == 'add_file')
        _fileHandler.pickAndAddAudioFile();
      else if (value == 'add_folder')
        _fileHandler.pickAndAddFolder();
      else if (value == 'add_url')
        _fileHandler.showAddUrlDialog();
    });
  }

  // Build playlist panel
  Widget _buildPlaylistPanel() {
    return AnimatedContainer(
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
          selectedPlaylistId: _currentlySelectedPlaylistId,
          onPlaylistSelected: _handlePlaylistSelected,
        ),
      ),
    );
  }

  // Build search bar
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search collection...',
          prefixIcon: const Icon(Icons.search, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          isDense: true,
        ),
      ),
    );
  }

  // Build playlist header
  Widget _buildPlaylistHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
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
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
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
                  () => _handlePlaylistSelected(_currentlySelectedPlaylistId!),
            ),
          ],
        ),
      ),
    );
  }

  // Build main content area
  Widget _buildContentArea() {
    return DropTarget(
      onDragDone:
          (detail) async => await _fileHandler.handleDroppedFiles(detail.files),
      onDragEntered: (detail) => setState(() => _isDragging = true),
      onDragExited: (detail) => setState(() => _isDragging = false),
      child: Stack(
        children: [
          // Main Content: Table or Tree View
          BlocConsumer<TrackManagementBloc, TrackManagementState>(
            listener: (context, state) {
              if (state is TrackManagementError) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error: ${state.message}'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }

              // Update selection if underlying data changes
              if (state is TrackManagementLoaded) {
                final currentTrackIds = state.tracks.map((t) => t.id).toSet();
                bool selectionChanged = false;

                // Remove selected ids that no longer exist
                _selectedTrackIds.removeWhere((id) {
                  if (!currentTrackIds.contains(id)) {
                    selectionChanged = true;
                    if (_anchorTrackId == id) _anchorTrackId = null;
                    return true;
                  }
                  return false;
                });

                print("_selectedTrackIds length ${_selectedTrackIds.length}");

                if (selectionChanged) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() {
                        // Update player if selected track was deleted
                        if (_selectedTrackForPlayer != null &&
                            !_selectedTrackIds.contains(
                              _selectedTrackForPlayer!.id,
                            )) {
                          _selectedTrackForPlayer = null;
                        }

                        // Update handlers with new state
                        _initializeHandlers();
                      });
                    }
                  });
                }
              }
            },
            builder: (context, state) {
              // Get tracks, folders, tags and loading state
              List<Track> allTracks = [];
              List<String> rootFolders = [];
              List<Tag> allTags = [];
              bool isLoading =
                  state
                      is TrackManagementInitial; // Only initial is true loading state now

              if (state is TrackManagementLoading) {
                allTracks = state.currentTracks ?? [];
                rootFolders = state.currentRootFolders ?? [];
                allTags = state.currentAllTags ?? [];
              } else if (state is TrackManagementLoaded) {
                allTracks = state.tracks;
                rootFolders = state.rootFolders;
                allTags = state.allTags;
              } else if (state is TrackManagementProcessingWaveforms) {
                allTracks = state.tracks; // Use tracks from processing state
                rootFolders = state.rootFolders;
                allTags = state.allTags;
                isLoading = false; // Not considered initial loading
              } else if (state is TrackManagementError) {
                allTracks = state.tracks ?? [];
                rootFolders = state.rootFolders ?? [];
                // Optionally show error message here or rely on snackbar
              }

              if (isLoading && allTracks.isEmpty && rootFolders.isEmpty) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.green),
                );
              }

              // Get displayed tracks based on current filters
              List<Track> displayedTracks =
                  _trackSelectionHandler.getCurrentDisplayedTracks();

              // Handle empty states
              if (!isLoading &&
                  displayedTracks.isEmpty &&
                  _viewMode == ViewMode.list) {
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
                } else if (allTracks.isEmpty && rootFolders.isEmpty) {
                  // True empty collection
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.library_music_outlined,
                          size: 60,
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Your collection is empty',
                          style: TextStyle(fontSize: 18),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Add audio files or folders using the + button',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                } else if (allTracks.isEmpty && rootFolders.isNotEmpty) {
                  return const Center(
                    child: Text('No audio tracks found in the collection yet.'),
                  );
                }
                return const Center(child: Text('No tracks to display.'));
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

              // Build the main view
              return Container(
                color:
                    _currentlySelectedPlaylistId != null
                        ? Theme.of(
                          context,
                        ).colorScheme.surfaceVariant.withOpacity(0.3)
                        : null,
                child:
                    _viewMode == ViewMode.list
                        ? TrackTableWidget(
                          // Ensure keys update if underlying data structure changes significantly
                          key: ValueKey(
                            'track-table-${_currentlySelectedPlaylistId ?? 'all'}-${_sortColumnName}-${_sortDirectionSf.name}-${allTracks.length}',
                          ),
                          tracks:
                              displayedTracks, // Pass currently filtered/sorted tracks
                          selectedTrackIds: _selectedTrackIds,
                          audioPlayerBloc: context.read<AudioPlayerBloc>(),
                          onSelectionChanged: _handleSelectionChanged,
                          onShowContextMenu:
                              _contextMenuHandler.showContextMenu,
                          onRatingChanged: _handleRatingChanged,
                          onSort: _handleSortChanged,
                          initialSortColumnName: _sortColumnName,
                          initialSortDirection: _sortDirectionSf,
                          onPlayPreviewAndMinimize: _selectAndPlayTrack,
                          onEditMetadata: _selectAndOpenPlayer,
                        )
                        : FolderTreeView(
                          key: ValueKey(
                            'folder-tree-${rootFolders.join('-')}-${allTracks.length}',
                          ),
                          tracks:
                              allTracks, // Pass all tracks for tree structure
                          rootFolders: rootFolders,
                          selectedTrack: _selectedTrackForPlayer,
                          currentlyLoadedPath: _currentlyLoadedPathInPlayer,
                          onTrackSelected: (track) {
                            _handleSelectionChanged(track.id!, true);
                            _selectTrackForPlayer(track);
                          },
                          onTrackDeleted: (trackId) {
                            _contextMenuHandler.confirmAndDeleteSelected();
                          },
                        ),
              );
            }, // End Builder for main content
          ),

          BlocBuilder<TrackManagementBloc, TrackManagementState>(
            builder: (context, state) {
              if (state is TrackManagementProcessingWaveforms) {
                double progress =
                    (state.totalCount > 0)
                        ? (state.processedCount / state.totalCount).clamp(
                          0.0,
                          1.0,
                        )
                        : 0.0;
                return Positioned(
                  // Position the progress bar
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    color: Colors.black.withOpacity(
                      0.7,
                    ), // Semi-transparent background
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            value: progress, // Show determinate progress
                            strokeWidth: 3,
                            backgroundColor: Colors.white24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Processing waveforms (${state.processedCount}/${state.totalCount})...',
                            style: const TextStyle(color: Colors.white),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              } else if (state is TrackManagementLoading &&
                  state.currentTracks == null &&
                  state.currentRootFolders == null) {
                // Show general loading if nothing else is displayed yet
                return const Center(
                  child: CircularProgressIndicator(color: Colors.lightGreen),
                );
              }
              return const SizedBox.shrink(); // Hide if not processing waveforms
            },
          ),

          // Drag overlay
          if (_isDragging)
            Container(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
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
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Loading indicator overlay
          // BlocBuilder<TrackManagementBloc, TrackManagementState>(
          //   builder: (context, state) {
          //     if (state is TrackManagementLoading &&
          //         (state.currentTracks?.isNotEmpty ?? false)) {
          //       return Positioned.fill(
          //         child: Container(
          //           color: Colors.black.withOpacity(0.4),
          //           child: const Center(
          //             child: Column(
          //               mainAxisSize: MainAxisSize.min,
          //               children: [
          //                 CircularProgressIndicator(color: Colors.white),
          //                 SizedBox(height: 16),
          //                 Text(
          //                   'Processing audio...',
          //                   style: TextStyle(color: Colors.white, fontSize: 16),
          //                 ),
          //               ],
          //             ),
          //           ),
          //         ),
          //       );
          //     }
          //     return const SizedBox.shrink();
          //   },
          // ),
        ],
      ),
    );
  }
}

// Helper extension
extension TrackListNullOrEmpty on List<Track>? {
  bool get isNullOrEmpty => this == null || this!.isEmpty;
}
