// lib/screens/home_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

// Import BLoCs
import '../blocs/collection_management/collection_management_bloc.dart';
import '../blocs/audio_player/audio_player_bloc.dart';
import '../blocs/playlist/playlist_bloc.dart';
import '../blocs/track_management/track_data_bloc.dart'; // <<< CHANGED: Import new BLoC
import '../blocs/track_management/track_metadata_bloc.dart'; // <<< ADDED: Import new BLoC
// import '../blocs/track_management/track_management_bloc.dart'; // <<< REMOVED: Old BLoC

// Import Services and Models
import '../services/collection_service.dart'; // Keep for Track, Tag, CollectionDefinition models
import '../models/playlist.dart';

// Import Widgets
import '../widgets/playlist_drawer.dart';
import '../widgets/folder_tree_view.dart';
import '../widgets/track_table_widget.dart';
import '../widgets/combined_audio_player_widget.dart';
import '../widgets/rating_filter_widget.dart';

// Import Handlers (already adapted in previous steps)
import '../handlers/track_selection_handler.dart';
import '../handlers/context_menu_handler.dart';
import '../handlers/file_handler.dart';
import '../handlers/player_control_handler.dart';

// Import Other Screens
import 'collection_manager_screen.dart';

// Define view mode enum
enum ViewMode { list, tree }

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // State variables (mostly unchanged)
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
  final double _playlistPanelOpenWidth = 250.0;
  final double _playlistPanelClosedWidth = 50.0;

  // Handlers (will be initialized in didChangeDependencies)
  late TrackSelectionHandler _trackSelectionHandler;
  late ContextMenuHandler _contextMenuHandler;
  late FileHandler _fileHandler;
  late PlayerControlHandler _playerControlHandler;

  @override
  void initState() {
    super.initState();

    // Initial data loading for other BLoCs
    context.read<CollectionManagementBloc>().add(LoadCollectionList());
    context.read<PlaylistBloc>().add(LoadPlaylists());

    _searchController.addListener(_onSearchChanged);

    // Set up listeners
    _setupAudioPlayerListener();
    _setupCollectionListener(); // This will now trigger TrackDataBloc
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Initialize handlers when context is ready and potentially update them if dependencies change
    _initializeHandlers();
  }

  // Initialize or update handlers based on current state
  void _initializeHandlers() {
    // Read the current rating filter from TrackDataBloc state
    final trackDataState = context.read<TrackDataBloc>().state;
    int? currentMinimumRating;
    if (trackDataState is TrackDataLoaded) {
      currentMinimumRating = trackDataState.minimumRating;
    } else if (trackDataState is TrackDataLoading) {
      currentMinimumRating = trackDataState.minimumRating;
    }

    _trackSelectionHandler = TrackSelectionHandler(
      context: context,
      selectedTrackIds: _selectedTrackIds,
      anchorTrackId: _anchorTrackId,
      selectedTrackForPlayer: _selectedTrackForPlayer,
      // currentlyLoadedPathInPlayer: _currentlyLoadedPathInPlayer, // Not directly needed by handler?
      sortColumnName: _sortColumnName,
      sortDirectionSf: _sortDirectionSf,
      currentlySelectedPlaylist: _currentlySelectedPlaylist,
      // Pass the rating filter obtained from TrackDataBloc state if needed by handler logic
      // minimumRating: currentMinimumRating, // Pass if handler needs it directly
    );

    _contextMenuHandler = ContextMenuHandler(
      context: context,
      selectedTrackIds: _selectedTrackIds,
      onSelectionChanged: _handleSelectionChanged, // Pass the method reference
      onPlayTrack: _selectAndPlayTrack, // Pass the method reference
    );

    _fileHandler = FileHandler(
      context: context,
      supportedExtensions: _supportedExtensions,
    );

    _playerControlHandler = PlayerControlHandler(
      context: context,
      selectedTrackForPlayer: _selectedTrackForPlayer,
      // Pass the function that gets the *currently displayed* tracks from the handler itself
      getCurrentDisplayedTracksFn:
          _trackSelectionHandler.getCurrentDisplayedTracks,
    );
  }

  // Listener for Audio Player state changes (mostly unchanged)
  void _setupAudioPlayerListener() {
    context.read<AudioPlayerBloc>().stream.listen((playerState) {
      if (!mounted) return;
      String? newPath;
      if (playerState is AudioPlayerLoaded) {
        newPath = playerState.currentSource;
      } else if (playerState is! AudioPlayerLoading) {
        // Clear path if stopped, error, or initial
        newPath = null;
      }
      // Only update state if the path actually changed
      if (_currentlyLoadedPathInPlayer != newPath) {
        setState(() {
          _currentlyLoadedPathInPlayer = newPath;
        });
        _initializeHandlers(); // Re-initialize handlers if player path changes
      }
    });
  }

  // Listener for Collection Management state changes
  void _setupCollectionListener() {
    context.read<CollectionManagementBloc>().stream.listen((collectionState) {
      if (!mounted) return;

      if (collectionState is CollectionManagementLoaded &&
          collectionState.activeCollectionDefinition != null) {
        final activeCollectionId =
            collectionState.activeCollectionDefinition!.id;
        print(
          "HomeScreen Listener: Collection '${collectionState.activeCollectionDefinition!.name}' loaded (ID: $activeCollectionId). Triggering TrackDataBloc load.",
        );

        // --- Trigger Loading for TrackDataBloc and Playlists ---
        context.read<TrackDataBloc>().add(
          LoadTracks(),
        ); // <<< CHANGED: Dispatch to TrackDataBloc
        context.read<PlaylistBloc>().add(LoadPlaylists());

        // Optionally trigger sync after load
        // Future.delayed(const Duration(milliseconds: 500), () {
        //   if (mounted && context.read<CollectionManagementBloc>().state == collectionState) {
        //      context.read<TrackDataBloc>().add(SyncFolders()); // <<< CHANGED: Dispatch to TrackDataBloc
        //   }
        // });
      } else if (collectionState is CollectionManagementLoaded &&
          collectionState.activeCollectionDefinition == null) {
        print(
          "HomeScreen Listener: Collection Management loaded, but no active collection.",
        );
        // Clear tracks if no collection is active
        context.read<TrackDataBloc>().add(
          const SearchTracks(''),
        ); // <<< CHANGED: Dispatch to TrackDataBloc
        context.read<PlaylistBloc>().add(
          LoadPlaylists(),
        ); // Reload (will likely result in empty)
        // Clear local state related to active collection
        setState(() {
          _selectedTrackIds.clear();
          _anchorTrackId = null;
          _selectedTrackForPlayer = null;
          _currentlySelectedPlaylistId = null;
          _currentlySelectedPlaylist = null;
          _searchController.clear(); // Clear search on collection change
        });
        _initializeHandlers(); // Re-init handlers with cleared state
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // --- UI Interaction Handlers (mostly unchanged, rely on adapted handlers) ---

  void _handlePlayerToggle() {
    if (!mounted) return;
    setState(() {
      _isMinimized = !_isMinimized;
    });
  }

  void _onSearchChanged() {
    // Dispatch search event to TrackDataBloc
    // <<< CHANGED: Dispatch to TrackDataBloc >>>
    context.read<TrackDataBloc>().add(SearchTracks(_searchController.text));
    // Clear selection when search changes
    setState(() {
      _selectedTrackIds.clear();
      _anchorTrackId = null;
      // Don't clear _selectedTrackForPlayer here, search might still contain it
    });
    _initializeHandlers(); // Re-init handlers
  }

  void _togglePlaylistPanel() {
    setState(() {
      _isPlaylistPanelVisible = !_isPlaylistPanelVisible;
    });
  }

  // Handles selecting/deselecting a playlist filter
  void _handlePlaylistSelected(String playlistId) {
    final playlistState = context.read<PlaylistBloc>().state;
    Playlist? newSelectedPlaylist; // Store the actual playlist object

    if (_currentlySelectedPlaylistId == playlistId) {
      // Deselecting the current playlist
      _currentlySelectedPlaylistId = null;
      newSelectedPlaylist = null;
    } else {
      // Selecting a new playlist
      if (playlistState is PlaylistLoaded) {
        try {
          newSelectedPlaylist = playlistState.playlists.firstWhere(
            (p) => p.id == playlistId,
          );
          _currentlySelectedPlaylistId = playlistId;
        } catch (e) {
          newSelectedPlaylist = null;
          _currentlySelectedPlaylistId = null;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error: Could not select playlist.')),
          );
        }
      } else {
        // Playlists not loaded yet
        newSelectedPlaylist = null;
        _currentlySelectedPlaylistId = null;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Playlists are still loading...')),
        );
      }
    }

    setState(() {
      _currentlySelectedPlaylist =
          newSelectedPlaylist; // Update the stored playlist object
      _selectedTrackIds.clear(); // Clear selection when playlist changes
      _anchorTrackId = null;
    });

    // Re-initialize handlers with the new playlist selection state
    _initializeHandlers();

    // Manually trigger a reload/refilter in TrackDataBloc if needed,
    // although TrackSelectionHandler reading the new playlist state might be sufficient.
    // If TrackDataBloc needs explicit filtering based on playlist:
    // context.read<TrackDataBloc>().add(ApplyPlaylistFilter(newSelectedPlaylist)); // Requires adding this event/logic
  }

  // Callback for TrackSelectionHandler to update HomeScreen's state
  void _handleSelectionStateUpdate(
    Set<int> newSelectedIds,
    int? newAnchorId,
    Track? newSelectedTrackForPlayer,
  ) {
    bool playerSelectionChanged =
        _selectedTrackForPlayer?.id != newSelectedTrackForPlayer?.id;
    setState(() {
      _selectedTrackIds = newSelectedIds;
      _anchorTrackId = newAnchorId;
      _selectedTrackForPlayer = newSelectedTrackForPlayer;
    });

    // If the player selection changed, ensure the track is loaded (without playing)
    if (playerSelectionChanged && newSelectedTrackForPlayer != null) {
      _trackSelectionHandler.selectTrackForPlayer(newSelectedTrackForPlayer);
    }

    _initializeHandlers(); // Keep handlers in sync with state
  }

  // Selects track, updates state, and tells handler to load (no auto-play)
  void _selectTrackForPlayer(Track track) {
    setState(() {
      _selectedTrackForPlayer = track;
      // Ensure the selected track is also in the selection set for UI consistency
      _selectedTrackIds = {if (track.id != null) track.id!};
      _anchorTrackId = track.id;
    });
    _initializeHandlers();
    _trackSelectionHandler.selectTrackForPlayer(track);
  }

  // Selects track, updates state, and tells handler to load AND play
  void _selectAndPlayTrack(Track track, bool shouldTogglePlay) {
    setState(() {
      _selectedTrackForPlayer = track;
      _selectedTrackIds = {if (track.id != null) track.id!};
      _anchorTrackId = track.id;
      // If playing a new track, ensure player is expanded
      // if (_selectedTrackForPlayer?.path != _currentlyLoadedPathInPlayer) {
      // _isMinimized = false;
      // }
    });
    _initializeHandlers();
    _trackSelectionHandler.selectAndPlayTrack(
      track,
      togglePlay: shouldTogglePlay,
    );
  }

  // Selects track, updates state, tells handler to load (no auto-play), and ensures player is open
  void _selectAndOpenPlayer(Track track) {
    setState(() {
      _selectedTrackForPlayer = track;
      _selectedTrackIds = {if (track.id != null) track.id!};
      _anchorTrackId = track.id;
      _isMinimized = false; // Ensure player opens
    });
    _initializeHandlers();
    _trackSelectionHandler.selectAndOpenPlayer(track);
  }

  void _toggleViewMode() {
    setState(() {
      _viewMode = _viewMode == ViewMode.list ? ViewMode.tree : ViewMode.list;
      _selectedTrackIds.clear();
      _anchorTrackId = null;
    });
    _initializeHandlers(); // Re-init handlers for the new view
  }

  // Wrapper for selection changes coming from UI widgets (like TrackTableWidget)
  void _handleSelectionChanged(
    int trackId,
    bool isSelected, {
    bool isShiftPressed = false,
    bool isCtrlPressed = false,
  }) {
    // Delegate the logic to the handler, providing the state update callback
    _trackSelectionHandler.handleSelectionChanged(
      trackId,
      isSelected,
      isShiftPressed: isShiftPressed,
      isCtrlPressed: isCtrlPressed,
      onSelectionStateChanged: _handleSelectionStateUpdate, // Pass the callback
    );
  }

  // Wrapper for rating changes coming from UI widgets (like TrackTableWidget)
  void _handleRatingChanged(int trackId, int newRating) {
    // Delegate to the handler (which now dispatches to TrackMetadataBloc)
    _trackSelectionHandler.handleRatingChanged(trackId, newRating);
    // Note: UI update for the rating itself happens optimistically within
    // TrackTableWidget/RatingCellWidget or via listening to TrackMetadataBloc success.
  }

  // Wrapper for sort changes coming from UI widgets (like TrackTableWidget)
  void _handleSortChanged(String columnName, DataGridSortDirection direction) {
    setState(() {
      _sortColumnName = columnName;
      _sortDirectionSf = direction;
    });
    _initializeHandlers(); // Update handlers with new sort settings
    // Re-filtering/sorting is handled implicitly by getCurrentDisplayedTracks
  }

  // Player control wrappers (delegate to handler)
  void _playNextTrack() {
    _playerControlHandler.playNextTrack(onTrackSelected: _selectAndPlayTrack);
  }

  void _playPreviousTrack() {
    _playerControlHandler.playPreviousTrack(
      onTrackSelected: _selectAndPlayTrack,
    );
  }

  // --- Build Method ---
  @override
  Widget build(BuildContext context) {
    // Use MultiBlocListener to react to events from multiple BLoCs
    return MultiBlocListener(
      listeners: [
        // Listener for Collection Management (triggers TrackDataBloc load)
        BlocListener<CollectionManagementBloc, CollectionManagementState>(
          listener: (context, collectionState) {
            // Logic moved to _setupCollectionListener for clarity
          },
        ),
        BlocListener<TrackDataBloc, TrackDataState>(
          listener: (context, state) {
            if (state is FolderDeletionConfirmationNeeded) {
              _showFolderDeleteConfirmationDialog(
                context,
                state.folderPath,
                state.folderName,
                state.trackCount,
              );
            }
            // Optionally listen for TrackDataDeletingFolder to show specific loading UI
            else if (state is TrackDataError) {
              // Show generic errors from TrackDataBloc if needed
              // ScaffoldMessenger.of(context).showSnackBar(
              //   SnackBar(content: Text('Error: ${state.message}')),
              // );
            }
          },
        ),
        // Listener for Playlist changes (updates local state if selected playlist changes)
        BlocListener<PlaylistBloc, PlaylistState>(
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
                _initializeHandlers(); // Update handlers
              } else {
                try {
                  final updatedPlaylist = playlistState.playlists.firstWhere(
                    (p) => p.id == _currentlySelectedPlaylistId,
                  );
                  if (_currentlySelectedPlaylist?.name !=
                          updatedPlaylist.name ||
                      _currentlySelectedPlaylist?.trackPaths.length !=
                          updatedPlaylist.trackPaths.length) {
                    // Basic change check
                    setState(() {
                      _currentlySelectedPlaylist = updatedPlaylist;
                    });
                    _initializeHandlers(); // Update handlers
                  }
                } catch (e) {
                  /* ignore */
                }
              }
            }
          },
        ),
        // Listener for Metadata updates (triggers TrackDataBloc reload on success)
        BlocListener<TrackMetadataBloc, TrackMetadataState>(
          listener: (context, metadataState) {
            if (metadataState is TrackMetadataUpdateSuccess) {
              print(
                "HomeScreen Listener: Metadata updated for track ${metadataState.trackId}, reloading track data.",
              );
              // Reload track data preserving filters
              context.read<TrackDataBloc>().add(ReloadDataPreservingFilters());
              // Also potentially update the _selectedTrackForPlayer if it was the one edited
              if (_selectedTrackForPlayer?.id == metadataState.trackId) {
                // Re-fetch the updated track data
                final updatedTrack = _trackSelectionHandler
                    .getTrackByIdFromBlocState(metadataState.trackId);
                if (updatedTrack != null) {
                  setState(() {
                    _selectedTrackForPlayer = updatedTrack;
                  });
                }
              }
            } else if (metadataState is TrackMetadataUpdateError) {
              // Show error message if metadata update fails
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Metadata Update Error: ${metadataState.message}',
                  ),
                  backgroundColor: Colors.redAccent,
                ),
              );
            }
          },
        ),
      ],
      child: Scaffold(
        appBar: _buildAppBar(),
        body: Focus(
          // Keep Focus for keyboard shortcuts
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _handleKeyEvent,
          child: Row(
            children: [
              // Container(
              //   width: 48, // Width for the button column
              //   color: Theme.of(context).canvasColor, // Match panel background
              //   child: Column(
              //     children: [
              //       IconButton(
              //         icon: Icon(
              //           _isPlaylistPanelVisible ? Icons.menu_open : Icons.menu,
              //           color: Theme.of(context).colorScheme.onSurfaceVariant,
              //         ),
              //         tooltip: 'Toggle Playlists Panel',
              //         onPressed: _togglePlaylistPanel,
              //       ),
              //       const Divider(height: 1), // Optional separator
              //     ],
              //   ),
              // ),
              _buildPlaylistPanel(), // Playlist Panel (Left)
              Expanded(
                // Main Content Area (Right)
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildFilterBar(), // Search and Rating Filter
                    if (_currentlySelectedPlaylist != null)
                      _buildPlaylistHeader(), // Header shown when playlist is selected
                    Expanded(child: _buildContentArea()), // Table or Tree View
                    // Player (Bottom) - shows only if a track is selected for the player
                    if (_selectedTrackForPlayer != null)
                      CombinedAudioPlayerWidget(
                        key: ValueKey(
                          _selectedTrackForPlayer!.id,
                        ), // Ensure widget rebuilds when track changes
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
        floatingActionButton: FloatingActionButton.small(
          // Use small for discretion
          onPressed: _showAddMenu, // Call the existing menu function
          tooltip: 'Add...',
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  // --- Build Helper Methods ---

  // Handle keyboard events (e.g., Space for play/pause)
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.space) {
      // Check if focus is not in a text field before toggling playback
      final FocusScopeNode currentFocus = FocusScope.of(context);
      if (!currentFocus.hasPrimaryFocus && currentFocus.focusedChild != null) {
        // If something has focus, but maybe not the primary (e.g., button), allow spacebar play/pause
        // This might need refinement based on specific focus behavior desired
      }
      // Allow space play/pause even if a text field has focus? Maybe not ideal.
      // Let's allow it for now.
      _playerControlHandler.togglePlayPause();
      return KeyEventResult.handled;
    }
    // Add other keyboard shortcuts here (e.g., arrow keys for selection)
    return KeyEventResult.ignored;
  }

  // Build the app bar (AppBar)
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
          String title = 'Audio Looker'; // Default title
          if (state is CollectionManagementLoaded &&
              state.activeCollectionDefinition != null) {
            title = state.activeCollectionDefinition!.name;
          } else if (state is CollectionManagementLoading &&
              state.activeCollectionDefinition != null) {
            title = "${state.activeCollectionDefinition!.name} (Loading...)";
          } else if (state is CollectionManagementInitial ||
              (state is CollectionManagementLoaded &&
                  state.activeCollectionDefinition == null)) {
            title = "Select Collection";
          } else if (state is CollectionManagementError) {
            title = "Error Loading Collection";
          }
          return Text(title);
        },
      ),
    );
  }

  // Show the 'Add' menu
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

    // --- Logic to build and show the menu is HERE ---
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        MediaQuery.of(context).size.width - 100, // Position near the button
        kToolbarHeight,
        MediaQuery.of(context).size.width,
        0,
      ),
      items: <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'add_file',
          child: ListTile(
            leading: Icon(Icons.audio_file),
            title: Text('Add Audio File(s)'),
          ),
        ),
        if (activeCollectionDef.type == CollectionType.local)
          const PopupMenuItem<String>(
            value: 'add_folder',
            child: ListTile(
              leading: Icon(Icons.folder_open),
              title: Text('Add Folder to Collection'),
            ),
          ),
        const PopupMenuItem<String>(
          value: 'add_url',
          child: ListTile(
            leading: Icon(Icons.link),
            title: Text('Add Audio from URL'),
          ),
        ),
      ],
    ).then((value) {
      // --- Call the appropriate FileHandler method AFTER selection ---
      if (value == 'add_file') {
        _fileHandler.pickAndAddAudioFile();
      } else if (value == 'add_folder') {
        _fileHandler.pickAndAddFolder();
      } else if (value == 'add_url') {
        _fileHandler.showAddUrlDialog();
      }
    });
    // --- REMOVED incorrect call: _fileHandler.showAddMenu(); ---
  }

  void _showFolderDeleteConfirmationDialog(
    BuildContext context,
    String folderPath,
    String folderName,
    int trackCount,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false, // User must choose
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Delete Folder "$folderName"?'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                // Concise message
                Text('$trackCount track(s) were removed from the collection.'),
                const SizedBox(height: 15),
                const Text(
                  'Also delete the folder from disk?', // Direct question
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  // Show path for context
                  'Path: $folderPath',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  maxLines: 2, // Limit path lines if too long
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                const Text(
                  // Keep the warning
                  'Deleting from disk cannot be undone.',
                  style: TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Keep on Disk'), // Shorter button text
              onPressed: () {
                Navigator.of(dialogContext).pop();
                context.read<TrackDataBloc>().add(
                  ConfirmDeleteFolderFiles(folderPath, false),
                );
              },
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete from Disk'), // Shorter button text
              onPressed: () {
                Navigator.of(dialogContext).pop();
                context.read<TrackDataBloc>().add(
                  ConfirmDeleteFolderFiles(folderPath, true),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildPlaylistPanel() {
    return Stack(
      alignment:
          Alignment.topRight, // Keep alignment for the arrow button container
      clipBehavior: Clip.hardEdge,
      children: [
        // Animated Container for the panel content and background
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          width:
              _isPlaylistPanelVisible
                  ? _playlistPanelOpenWidth
                  : _playlistPanelClosedWidth,
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 1.0,
              ),
            ),
            color: Theme.of(context).canvasColor,
          ),
          clipBehavior: Clip.hardEdge, // Clip internal content
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Playlist Drawer takes up most space
              Expanded(
                child: OverflowBox(
                  minWidth: _playlistPanelOpenWidth,
                  maxWidth: _playlistPanelOpenWidth,
                  alignment: Alignment.topLeft,
                  child: PlaylistDrawer(
                    selectedPlaylistId: _currentlySelectedPlaylistId,
                    onPlaylistSelected: _handlePlaylistSelected,
                    // --- ADDED: Pass visibility state ---
                    isOpen: _isPlaylistPanelVisible,
                    // --- END ADDED ---
                  ),
                ),
              ),
              // Create Playlist Button Area
              Visibility(
                visible: _isPlaylistPanelVisible,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: IconButton(
                      icon: const Icon(Icons.add),
                      tooltip: 'New Playlist',
                      onPressed: _showCreatePlaylistDialog,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Positioned Toggle Button (Arrow) - Remains the same
        Positioned(
          top: 0,
          right: _isPlaylistPanelVisible ? 0 : null,
          left: _isPlaylistPanelVisible ? null : 0,
          width: _isPlaylistPanelVisible ? null : _playlistPanelClosedWidth,
          child: Container(
            height: kToolbarHeight - 8,
            alignment: Alignment.center,
            child: IconButton(
              icon: Icon(
                _isPlaylistPanelVisible
                    ? Icons.arrow_back_ios_new
                    : Icons.arrow_forward_ios,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              tooltip:
                  _isPlaylistPanelVisible
                      ? 'Collapse Playlists'
                      : 'Expand Playlists',
              onPressed: _togglePlaylistPanel,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            ),
          ),
        ),
      ],
    );
  }

  void _showCreatePlaylistDialog() {
    final collectionState = context.read<CollectionManagementBloc>().state;
    if (collectionState is! CollectionManagementLoaded ||
        collectionState.activeCollectionDefinition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a collection first.")),
      );
      return;
    }

    final TextEditingController nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('New Playlist'),
          content: TextField(
            controller: nameController,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Playlist Name'),
            onSubmitted:
                (_) =>
                    _submitCreatePlaylist(dialogContext, nameController.text),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              child: const Text('Create'),
              onPressed:
                  () =>
                      _submitCreatePlaylist(dialogContext, nameController.text),
            ),
          ],
        );
      },
    ).then((_) => nameController.dispose());
  }

  void _submitCreatePlaylist(BuildContext dialogContext, String name) {
    final trimmedName = name.trim();
    if (trimmedName.isNotEmpty) {
      context.read<PlaylistBloc>().add(CreatePlaylist(trimmedName));
      Navigator.of(dialogContext).pop();
    } else {
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        const SnackBar(content: Text('Playlist name cannot be empty.')),
      );
    }
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              _viewMode == ViewMode.list
                  ? Icons.account_tree
                  : Icons.table_rows,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            onPressed: _toggleViewMode,
            tooltip:
                _viewMode == ViewMode.list
                    ? 'Switch to folder view'
                    : 'Switch to table view',
          ),
          const SizedBox(width: 8),
          // Search Text Field
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search collection...',
                prefixIcon: const Icon(Icons.search, size: 20),
                // Clear button
                suffixIcon:
                    _searchController.text.isNotEmpty
                        ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          tooltip: 'Clear Search',
                          onPressed: () {
                            _searchController.clear();
                            // Dispatch search event with empty query
                            context.read<TrackDataBloc>().add(
                              const SearchTracks(''),
                            );
                          },
                        )
                        : null,
              ),
            ),
          ),
          const SizedBox(width: 16), // Spacing
          // --- ADDED: View Mode Toggle Button ---
          // Spacing before rating
          // Rating Filter Widget
          BlocBuilder<TrackDataBloc, TrackDataState>(
            // Listen to TrackDataBloc for current filter
            builder: (context, state) {
              int? currentFilterValue;
              if (state is TrackDataLoaded) {
                currentFilterValue = state.minimumRating;
              } else if (state is TrackDataLoading) {
                currentFilterValue = state.minimumRating;
              }
              // Add other states if they hold the filter value

              return RatingFilterWidget(
                currentMinimumRating: currentFilterValue,
                onRatingSelected: (int? rating) {
                  // Dispatch filter event to TrackDataBloc
                  context.read<TrackDataBloc>().add(SetRatingFilter(rating));
                },
                iconSize: 20, // Adjust size if needed
              );
            },
          ),
        ],
      ),
    );
  }

  // Build the header shown when a playlist is active
  Widget _buildPlaylistHeader() {
    // Ensure playlist is not null before building
    if (_currentlySelectedPlaylist == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.secondaryContainer.withOpacity(0.6),
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
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed:
                  () => _handlePlaylistSelected(
                    _currentlySelectedPlaylistId!,
                  ), // Pass ID to deselect
            ),
          ],
        ),
      ),
    );
  }

  // Build the main content area (Table or Tree)
  Widget _buildContentArea() {
    return DropTarget(
      // Wrap content area with DropTarget
      onDragDone:
          (detail) async => await _fileHandler.handleDroppedFiles(detail.files),
      onDragEntered: (detail) => setState(() => _isDragging = true),
      onDragExited: (detail) => setState(() => _isDragging = false),
      child: Stack(
        // Use Stack to overlay drag indicator
        children: [
          // Main Content: Table or Tree View based on _viewMode
          BlocBuilder<TrackDataBloc, TrackDataState>(
            // Listen to TrackDataBloc
            builder: (context, state) {
              // --- Extract Data ---
              List<Track> allTracksForTree =
                  []; // All tracks for tree view structure
              List<Track> displayedTracksForTable =
                  []; // Filtered/sorted tracks for table
              List<String> rootFolders = [];
              bool isLoading =
                  state is TrackDataInitial || state is TrackDataLoading;
              bool hasError = state is TrackDataError;
              String errorMessage =
                  hasError ? (state as TrackDataError).message : '';

              if (state is TrackDataLoaded) {
                // TrackDataLoaded contains the ALREADY filtered/searched list
                displayedTracksForTable = state.tracks;
                rootFolders = state.rootFolders;
                // For tree view, we might need ALL tracks regardless of filter.
                // This requires TrackDataBloc to potentially hold both filtered and unfiltered lists,
                // or we fetch all tracks again here (less efficient).
                // Let's assume for now tree view also uses the filtered list for simplicity.
                // TODO: Revisit if Tree View needs unfiltered list.
                allTracksForTree = state.tracks;
              } else if (state is TrackDataLoading) {
                // Show previous data while loading
                displayedTracksForTable = state.previousTracks ?? [];
                rootFolders = state.previousRootFolders ?? [];
                allTracksForTree = state.previousTracks ?? [];
              } else if (state is TrackDataError) {
                // Show empty list on error? Or potentially previous data if stored in error state?
                // For now, show empty.
              }

              // --- Handle Loading State ---
              if (isLoading &&
                  displayedTracksForTable.isEmpty &&
                  rootFolders.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              // --- Handle Error State ---
              if (hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Error loading tracks: $errorMessage',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                );
              }

              // --- Handle Empty States ---
              final bool hasActiveFilters =
                  (_searchController.text.isNotEmpty ||
                      (state is TrackDataLoaded &&
                          state.minimumRating != null &&
                          state.minimumRating! > 0) ||
                      (state is TrackDataLoading &&
                          state.minimumRating != null &&
                          state.minimumRating! > 0) ||
                      _currentlySelectedPlaylist != null);

              if (displayedTracksForTable.isEmpty && !isLoading) {
                if (hasActiveFilters) {
                  return Center(
                    child: Text('No tracks match the current filters.'),
                  );
                } else if (rootFolders.isEmpty && allTracksForTree.isEmpty) {
                  // Truly empty collection, guide user
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
                          'Add audio files or folders using the + button or drag & drop',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                } else {
                  // Collection has roots/potential tracks, but none match current view/filters
                  return Center(child: Text('No tracks to display.'));
                }
              }

              // --- Build Table or Tree ---
              return Container(
                color:
                    _currentlySelectedPlaylistId != null
                        ? Theme.of(
                          context,
                        ).colorScheme.surfaceVariant.withOpacity(
                          0.1,
                        ) // Subtle background if playlist active
                        : null,
                child:
                    _viewMode == ViewMode.list
                        ? TrackTableWidget(
                          // Use ValueKey to ensure rebuild when fundamental data changes
                          key: ValueKey(
                            'track-table-${_currentlySelectedPlaylistId ?? 'all'}-${_sortColumnName}-${_sortDirectionSf.name}-${displayedTracksForTable.length}',
                          ),
                          tracks:
                              displayedTracksForTable, // Pass filtered/sorted tracks
                          selectedTrackIds: _selectedTrackIds,
                          audioPlayerBloc: context.read<AudioPlayerBloc>(),
                          onSelectionChanged:
                              _handleSelectionChanged, // Pass method reference
                          onShowContextMenu:
                              _contextMenuHandler
                                  .showContextMenu, // Pass method reference
                          onRatingChanged:
                              _handleRatingChanged, // Pass method reference
                          onSort: _handleSortChanged, // Pass method reference
                          initialSortColumnName: _sortColumnName,
                          initialSortDirection: _sortDirectionSf,
                          onPlayPreviewAndMinimize:
                              _selectAndPlayTrack, // Pass method reference
                          onEditMetadata:
                              _selectAndOpenPlayer, // Pass method reference
                        )
                        : FolderTreeView(
                          key: ValueKey(
                            'folder-tree-${rootFolders.join('-')}-${allTracksForTree.length}',
                          ),
                          tracks:
                              allTracksForTree, // Pass tracks for tree structure
                          rootFolders: rootFolders, // Pass root folders
                          selectedTrack:
                              _selectedTrackForPlayer, // Highlight selected track
                          currentlyLoadedPath:
                              _currentlyLoadedPathInPlayer, // Highlight playing track
                          onTrackSelected: (track) {
                            // Select track in state and load for player (no auto-play)
                            _handleSelectionChanged(
                              track.id!,
                              true,
                            ); // Update selection state
                            _selectTrackForPlayer(
                              track,
                            ); // Load track into player UI part
                          },
                          onTrackDeleted: (trackId) {
                            // Use context menu handler's delete confirmation
                            _contextMenuHandler.confirmAndDeleteSelected();
                          },
                          onFolderDeleted: (folderPath, folderName) {
                            print(
                              "Folder delete requested from TreeView: $folderName ($folderPath)",
                            );
                            // Dispatch the event to the BLoC
                            context.read<TrackDataBloc>().add(
                              DeleteFolder(folderPath),
                            );
                          },
                        ),
              );
            },
          ),

          // Drag & Drop Overlay Indicator
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

          // --- REMOVED Waveform Processing Indicator ---
          // This logic should move to a dedicated WaveformProcessingBloc and its listener/builder
        ],
      ),
    );
  }
}

// Helper extension (optional, can be removed if not used elsewhere)
extension TrackListNullOrEmpty on List<Track>? {
  bool get isNullOrEmpty => this == null || this!.isEmpty;
}
