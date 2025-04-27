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
import '../blocs/track_management/track_data_bloc.dart';
import '../blocs/track_management/track_metadata_bloc.dart';

// Import Services and Models
import '../services/collection_service.dart';
import '../models/playlist.dart';

// Import Widgets
import '../widgets/playlist_drawer.dart';
import '../widgets/folder_tree_view.dart';
import '../widgets/track_table_widget.dart';
import '../widgets/combined_audio_player_widget.dart';
import '../widgets/rating_filter_widget.dart';
import '../widgets/waveform_progress_bar.dart';

// Import Handlers
import '../handlers/track_selection_handler.dart';
import '../handlers/context_menu_handler.dart';
import '../handlers/file_handler.dart';
import '../handlers/player_control_handler.dart';

// Import Other Screens
import 'collection_manager_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as pathLib;

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
  bool _isPlaylistPanelVisible = false;
  String? _currentlySelectedPlaylistId;
  Playlist? _currentlySelectedPlaylist;
  bool _isMinimized = true; // Player starts minimized
  String? _currentlyLoadedPathInPlayer;
  final double _playlistPanelOpenWidth = 250.0;
  final double _playlistPanelClosedWidth = 50.0;

  final ValueNotifier<Set<LogicalKeyboardKey>> _folderTreeViewKeysNotifier =
      ValueNotifier({});

  // Handlers
  late TrackSelectionHandler _trackSelectionHandler;
  late ContextMenuHandler _contextMenuHandler;
  late FileHandler _fileHandler;
  late PlayerControlHandler _playerControlHandler;

  // Heights for layout calculation
  final double _filterBarHeight = 56.0; // Approx height of filter bar + padding
  final double _playlistHeaderHeight =
      38.0; // Approx height of playlist header + padding
  final double _waveformProgressBarHeight = 50.0; // Height of the progress bar

  @override
  void initState() {
    super.initState();
    context.read<CollectionManagementBloc>().add(LoadCollectionList());
    context.read<PlaylistBloc>().add(LoadPlaylists());
    _searchController.addListener(_onSearchChanged);
    _setupAudioPlayerListener();
    _setupCollectionListener();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initializeHandlers();
  }

  void _initializeHandlers() {
    final trackDataState = context.read<TrackDataBloc>().state;
    int? currentMinimumRating;
    if (trackDataState is TrackDataLoaded) {
      currentMinimumRating = trackDataState.minimumRating;
    } else if (trackDataState is TrackDataLoading) {
      currentMinimumRating = trackDataState.minimumRating;
    }

    final audioPlayerState = context.read<AudioPlayerBloc>().state;
    bool currentShuffleState = false;
    if (audioPlayerState is AudioPlayerLoaded) {
      currentShuffleState = audioPlayerState.isShuffleActive;
    }

    _trackSelectionHandler = TrackSelectionHandler(
      context: context,
      selectedTrackIds: _selectedTrackIds,
      anchorTrackId: _anchorTrackId,
      selectedTrackForPlayer: _selectedTrackForPlayer,
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
          _trackSelectionHandler.getCurrentDisplayedTracks,
      isShuffleActive: currentShuffleState,
    );
  }

  void _setupAudioPlayerListener() {
    context.read<AudioPlayerBloc>().stream.listen((playerState) {
      if (!mounted) return;
      String? newPath;
      bool shuffleStateChanged = false;

      if (playerState is AudioPlayerLoaded) {
        newPath = playerState.currentSource;
        if (_playerControlHandler.isShuffleActive !=
            playerState.isShuffleActive) {
          shuffleStateChanged = true;
        }
      } else if (playerState is! AudioPlayerLoading) {
        newPath = null;
      }

      bool pathChanged = _currentlyLoadedPathInPlayer != newPath;
      if (pathChanged) {
        setState(() {
          _currentlyLoadedPathInPlayer = newPath;
        });
      }

      if (pathChanged || shuffleStateChanged) {
        _initializeHandlers();
      }
    });
  }

  void _setupCollectionListener() {
    context.read<CollectionManagementBloc>().stream.listen((collectionState) {
      if (!mounted) return;

      if (collectionState is CollectionManagementLoaded &&
          collectionState.activeCollectionDefinition != null) {
        context.read<TrackDataBloc>().add(LoadTracks());
        context.read<TrackDataBloc>().add(CheckForNewFiles());
        context.read<PlaylistBloc>().add(LoadPlaylists());
      } else if (collectionState is CollectionManagementLoaded &&
          collectionState.activeCollectionDefinition == null) {
        context.read<TrackDataBloc>().add(const SearchTracks(''));
        context.read<PlaylistBloc>().add(LoadPlaylists());
        setState(() {
          _selectedTrackIds.clear();
          _anchorTrackId = null;
          _selectedTrackForPlayer = null;
          _currentlySelectedPlaylistId = null;
          _currentlySelectedPlaylist = null;
          _searchController.clear();
        });
        _initializeHandlers();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _searchController.dispose();
    _folderTreeViewKeysNotifier.dispose();
    super.dispose();
  }

  void _handlePlayerToggle() {
    if (!mounted) return;
    setState(() {
      _isMinimized = !_isMinimized;
    });
  }

  void _onSearchChanged() {
    context.read<TrackDataBloc>().add(SearchTracks(_searchController.text));
    setState(() {
      _selectedTrackIds.clear();
      _anchorTrackId = null;
    });
    _initializeHandlers();
  }

  void _togglePlaylistPanel() {
    setState(() {
      _isPlaylistPanelVisible = !_isPlaylistPanelVisible;
    });
  }

  void _handlePlaylistSelected(String playlistId) {
    final playlistState = context.read<PlaylistBloc>().state;
    Playlist? newSelectedPlaylist;

    if (_currentlySelectedPlaylistId == playlistId) {
      _currentlySelectedPlaylistId = null;
      newSelectedPlaylist = null;
    } else {
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
        newSelectedPlaylist = null;
        _currentlySelectedPlaylistId = null;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Playlists are still loading...')),
        );
      }
    }

    setState(() {
      _currentlySelectedPlaylist = newSelectedPlaylist;
      _selectedTrackIds.clear();
      _anchorTrackId = null;
    });
    _initializeHandlers();
  }

  void _handleSelectionStateUpdate(
    Set<int> newSelectedIds,
    int? newAnchorId,
    Track? newSelectedTrackForPlayer,
  ) {
    setState(() {
      _selectedTrackIds = newSelectedIds;
      _anchorTrackId = newAnchorId;
      _selectedTrackForPlayer = newSelectedTrackForPlayer;
    });
  }

  void _selectTrackForPlayer(Track track) {
    setState(() {
      _selectedTrackForPlayer = track;
      _selectedTrackIds = {if (track.id != null) track.id!};
      _anchorTrackId = track.id;
    });
    _initializeHandlers();
    _trackSelectionHandler.selectTrackForPlayer(track);
  }

  void _selectAndPlayTrack(Track track, bool shouldTogglePlay) {
    setState(() {
      _selectedTrackForPlayer = track;
      _selectedTrackIds = {if (track.id != null) track.id!};
      _anchorTrackId = track.id;
      // Ensure player is expanded when playing a new track
      if (_selectedTrackForPlayer?.path != _currentlyLoadedPathInPlayer ||
          !_isMinimized) {
        // Expand if track changed or already expanded
      } else {
        // Expand if minimized and same track is re-played
        _isMinimized = false;
      }
    });
    _initializeHandlers();
    _trackSelectionHandler.selectAndPlayTrack(
      track,
      togglePlay: shouldTogglePlay,
    );
  }

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
    _initializeHandlers();
  }

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
      onSelectionStateChanged: _handleSelectionStateUpdate,
    );
  }

  void _handleRatingChanged(int trackId, int newRating) {
    _trackSelectionHandler.handleRatingChanged(trackId, newRating);
  }

  void _handleSortChanged(String columnName, DataGridSortDirection direction) {
    setState(() {
      _sortColumnName = columnName;
      _sortDirectionSf = direction;
    });
    _initializeHandlers();
  }

  void _playNextTrack() {
    _playerControlHandler.playNextTrack(onTrackSelected: _selectAndPlayTrack);
  }

  void _playPreviousTrack() {
    _playerControlHandler.playPreviousTrack(
      onTrackSelected: _selectAndPlayTrack,
    );
  }

  void _handleTrackDoubleClick(Track track) {
    _selectAndPlayTrack(track, false);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.space) {
      _playerControlHandler.togglePlayPause();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _showNewFilesDialog(BuildContext context, List<String> newFilePaths) {
    final Map<String, bool> selectionStates = {
      for (var path in newFilePaths) path: true,
    };
    bool? selectAllValue = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (stfContext, stfSetState) {
            final int count = newFilePaths.length;
            final int selectedCount =
                selectionStates.values.where((v) => v).length;
            if (count == 0) {
              selectAllValue = false;
            } else if (selectedCount == 0) {
              selectAllValue = false;
            } else if (selectedCount == count) {
              selectAllValue = true;
            } else {
              selectAllValue = null;
            }

            return AlertDialog(
              title: Text('New Files Detected ($count)'),
              content: SizedBox(
                width: double.maxFinite,
                height: MediaQuery.of(context).size.height * 0.5,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Checkbox(
                          value: selectAllValue,
                          tristate: true,
                          onChanged:
                              count > 0
                                  ? (bool? newValue) {
                                    stfSetState(() {
                                      bool checkAll = selectAllValue != true;
                                      selectAllValue = checkAll;
                                      for (var key in selectionStates.keys) {
                                        selectionStates[key] = checkAll;
                                      }
                                    });
                                  }
                                  : null,
                        ),
                        const Text('Select All'),
                      ],
                    ),
                    const Divider(),
                    Expanded(
                      child:
                          count > 0
                              ? ListView.builder(
                                shrinkWrap: true,
                                itemCount: count,
                                itemBuilder: (listContext, index) {
                                  final filePath = newFilePaths[index];
                                  final fileName = pathLib.basename(filePath);
                                  return CheckboxListTile(
                                    title: Text(
                                      fileName,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    value: selectionStates[filePath] ?? false,
                                    onChanged: (bool? newValue) {
                                      if (newValue != null) {
                                        stfSetState(() {
                                          selectionStates[filePath] = newValue;
                                        });
                                      }
                                    },
                                    dense: true,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                  );
                                },
                              )
                              : const Center(
                                child: Text("No new files found."),
                              ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Skip'),
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    context.read<TrackDataBloc>().add(SkipDetectedFiles());
                  },
                ),
                TextButton(
                  onPressed:
                      selectedCount > 0
                          ? () {
                            final List<String> filesToAdd =
                                selectionStates.entries
                                    .where((entry) => entry.value)
                                    .map((entry) => entry.key)
                                    .toList();
                            Navigator.of(dialogContext).pop();
                            context.read<TrackDataBloc>().add(
                              AddDetectedFiles(filesToAdd),
                            );
                          }
                          : null,
                  child: Text('Add Selected ($selectedCount)'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showFolderDeleteConfirmationDialog(
    BuildContext context,
    String folderPath,
    String folderName,
    int trackCount,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Delete Folder "$folderName"?'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('$trackCount track(s) were removed from the collection.'),
                const SizedBox(height: 15),
                const Text(
                  'Also delete the folder from disk?',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  'Path: $folderPath',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Deleting from disk cannot be undone.',
                  style: TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Keep on Disk'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                context.read<TrackDataBloc>().add(
                  ConfirmDeleteFolderFiles(folderPath, false),
                );
              },
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete from Disk'),
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
      alignment: Alignment.topRight,
      clipBehavior: Clip.hardEdge,
      children: [
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
          clipBehavior: Clip.hardEdge,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: OverflowBox(
                  minWidth: _playlistPanelOpenWidth,
                  maxWidth: _playlistPanelOpenWidth,
                  alignment: Alignment.topLeft,
                  child: PlaylistDrawer(
                    selectedPlaylistId: _currentlySelectedPlaylistId,
                    onPlaylistSelected: _handlePlaylistSelected,
                    isOpen: _isPlaylistPanelVisible,
                  ),
                ),
              ),
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
        Positioned(
          top: 0,
          right: _isPlaylistPanelVisible ? 0 : null,
          left: _isPlaylistPanelVisible ? null : 0,
          width: _isPlaylistPanelVisible ? null : _playlistPanelClosedWidth,
          child: Container(
            height: kToolbarHeight - 8, // Adjusted for typical header height
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

  // Build the filter bar (Search, View Toggle, Rating Filter)
  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        8.0,
        8.0,
        16.0,
        8.0,
      ), // Adjusted padding
      child: Row(
        children: [
          // Home Button (Moved from AppBar)
          IconButton(
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
          // View Mode Toggle Button
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
                suffixIcon:
                    _searchController.text.isNotEmpty
                        ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          tooltip: 'Clear Search',
                          onPressed: () {
                            _searchController.clear();
                            context.read<TrackDataBloc>().add(
                              const SearchTracks(''),
                            );
                          },
                        )
                        : null,
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Rating Filter Widget
          BlocBuilder<TrackDataBloc, TrackDataState>(
            builder: (context, state) {
              int? currentFilterValue;
              if (state is TrackDataLoaded) {
                currentFilterValue = state.minimumRating;
              } else if (state is TrackDataLoading) {
                currentFilterValue = state.minimumRating;
              }

              return RatingFilterWidget(
                currentMinimumRating: currentFilterValue,
                onRatingSelected: (int? rating) {
                  context.read<TrackDataBloc>().add(SetRatingFilter(rating));
                },
                iconSize: 20,
              );
            },
          ),
        ],
      ),
    );
  }

  // Handle filter icon click (from TrackTableWidget)
  void _handleSetSearchText(String searchText) {
    _searchController.text = searchText;
    // Optionally trigger search immediately:
    // context.read<TrackDataBloc>().add(SearchTracks(searchText));
  }

  // Build the header shown when a playlist is active
  Widget _buildPlaylistHeader() {
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
                  () => _handlePlaylistSelected(_currentlySelectedPlaylistId!),
            ),
          ],
        ),
      ),
    );
  }

  // Build the main content area (Table or Tree)
  Widget _buildContentArea() {
    return DropTarget(
      onDragDone:
          (detail) async => await _fileHandler.handleDroppedFiles(detail.files),
      onDragEntered: (detail) => setState(() => _isDragging = true),
      onDragExited: (detail) => setState(() => _isDragging = false),
      child: Stack(
        children: [
          BlocBuilder<TrackDataBloc, TrackDataState>(
            builder: (context, state) {
              List<Track> allTracksForTree = [];
              List<Track> displayedTracksForTable = [];
              List<String> rootFolders = [];
              bool isLoading =
                  state is TrackDataInitial || state is TrackDataLoading;
              bool hasError = state is TrackDataError;
              String errorMessage = hasError ? (state).message : '';

              if (state is TrackDataLoaded) {
                displayedTracksForTable = state.tracks;
                rootFolders = state.rootFolders;
                allTracksForTree = state.tracks;
              } else if (state is TrackDataLoading) {
                displayedTracksForTable = state.previousTracks ?? [];
                rootFolders = state.previousRootFolders ?? [];
                allTracksForTree = state.previousTracks ?? [];
              } else if (state is TrackDataProcessingNeeded) {
                // Show data while processing
                displayedTracksForTable = state.tracks;
                rootFolders = state.rootFolders;
                allTracksForTree = state.tracks;
              } else if (state is TrackDataDeletingFolder) {
                displayedTracksForTable = state.previousTracks ?? [];
                rootFolders = state.previousRootFolders ?? [];
                allTracksForTree = state.previousTracks ?? [];
              }

              if (isLoading &&
                  displayedTracksForTable.isEmpty &&
                  rootFolders.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

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
                  return Center(child: Text('No tracks to display.'));
                }
              }

              return Container(
                color:
                    _currentlySelectedPlaylistId != null
                        ? Theme.of(
                          context,
                        ).colorScheme.surfaceVariant.withOpacity(0.1)
                        : null,
                child:
                    _viewMode == ViewMode.list
                        ? TrackTableWidget(
                          onSetSearchText: _handleSetSearchText,
                          key: ValueKey(
                            'track-table-${_currentlySelectedPlaylistId ?? 'all'}-${_sortColumnName}-${_sortDirectionSf.name}',
                          ),
                          tracks: displayedTracksForTable,
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
                          onRowDoubleTap: _handleTrackDoubleClick,
                        )
                        : KeyboardListener(
                          focusNode: FocusNode(),
                          onKeyEvent: (KeyEvent event) {
                            _folderTreeViewKeysNotifier.value =
                                HardwareKeyboard.instance.logicalKeysPressed;
                          },
                          child: FolderTreeView(
                            pressedKeysNotifier: _folderTreeViewKeysNotifier,
                            key: ValueKey(
                              'folder-tree-${rootFolders.join('-')}',
                            ),
                            tracks: allTracksForTree,
                            rootFolders: rootFolders,
                            selectedTrack: _selectedTrackForPlayer,
                            currentlyLoadedPath: _currentlyLoadedPathInPlayer,
                            onTrackSelected: (track) {
                              if (track.id != null) {
                                _handleSelectionChanged(track.id!, true);
                                _selectTrackForPlayer(track);
                              }
                            },
                            onTrackDeleted: (trackId) {
                              _contextMenuHandler.confirmAndDeleteSelected();
                            },
                            onFolderDeleted: (folderPath, folderName) {
                              context.read<TrackDataBloc>().add(
                                DeleteFolder(folderPath),
                              );
                            },
                          ),
                        ),
              );
            },
          ),
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
        ],
      ),
    );
  }

  // Build Method
  @override
  Widget build(BuildContext context) {
    // Calculate available height for the player
    // This might need adjustment based on your actual layout
    final screenHeight = MediaQuery.of(context).size.height;
    final availableHeight =
        screenHeight -
        _filterBarHeight -
        _waveformProgressBarHeight -
        (_currentlySelectedPlaylist != null ? _playlistHeaderHeight : 0) -
        MediaQuery.of(context).padding.top - // Account for status bar
        MediaQuery.of(context).padding.bottom; // Account for bottom system bars
    final maxPlayerHeight = (availableHeight * 0.8).clamp(
      200.0,
      500.0,
    ); // Example: 80% of remaining height

    return MultiBlocListener(
      listeners: [
        BlocListener<CollectionManagementBloc, CollectionManagementState>(
          listener: (context, collectionState) {}, // Handled in setup
        ),
        BlocListener<TrackDataBloc, TrackDataState>(
          listener: (context, state) {
            if (state is NewFilesDetected) {
              _showNewFilesDialog(context, state.newFilePaths);
            }
            if (state is FolderDeletionConfirmationNeeded) {
              _showFolderDeleteConfirmationDialog(
                context,
                state.folderPath,
                state.folderName,
                state.trackCount,
              );
            }
          },
        ),
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
                _initializeHandlers();
              } else {
                try {
                  final updatedPlaylist = playlistState.playlists.firstWhere(
                    (p) => p.id == _currentlySelectedPlaylistId,
                  );
                  if (_currentlySelectedPlaylist?.name !=
                          updatedPlaylist.name ||
                      _currentlySelectedPlaylist?.trackPaths.length !=
                          updatedPlaylist.trackPaths.length) {
                    setState(() {
                      _currentlySelectedPlaylist = updatedPlaylist;
                    });
                    _initializeHandlers();
                  }
                } catch (e) {}
              }
            }
          },
        ),
        BlocListener<TrackMetadataBloc, TrackMetadataState>(
          listener: (context, metadataState) {
            if (metadataState is TrackMetadataUpdateSuccess) {
              context.read<TrackDataBloc>().add(ReloadDataPreservingFilters());
              if (_selectedTrackForPlayer?.id == metadataState.trackId) {
                final updatedTrack = _trackSelectionHandler
                    .getTrackByIdFromBlocState(metadataState.trackId);
                if (updatedTrack != null) {
                  setState(() {
                    _selectedTrackForPlayer = updatedTrack;
                  });
                }
              }
            } else if (metadataState is TrackMetadataUpdateError) {
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
      child: PlatformMenuBar(
        menus: <PlatformMenuItem>[
          // --- File Menu ---
          PlatformMenu(
            label: 'File',
            menus: <PlatformMenuItem>[
              PlatformMenuItem(
                label: 'Add Files...',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyO,
                  meta: true,
                ),
                onSelected: () => _fileHandler.pickAndAddAudioFile(),
              ),
              PlatformMenuItem(
                label: 'Add Folder to Local Collection...',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyO,
                  meta: true,
                  shift: true,
                ),
                onSelected: () => _fileHandler.pickAndAddFolder(),
              ),
              PlatformMenuItem(
                label: 'Add URL...',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyU,
                  meta: true,
                ),
                onSelected: () => _fileHandler.showAddUrlDialog(),
              ),
            ],
          ),
          // --- View Menu ---
          PlatformMenu(
            label: 'View',
            menus: <PlatformMenuItem>[
              PlatformMenuItem(
                label:
                    _viewMode == ViewMode.list
                        ? 'Show Folder View'
                        : 'Show Table View',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyT,
                  meta: true,
                ),
                onSelected: _toggleViewMode,
              ),
              PlatformMenuItem(
                label:
                    _isPlaylistPanelVisible
                        ? 'Hide Playlists'
                        : 'Show Playlists',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyP,
                  meta: true,
                  shift: true,
                ),
                onSelected: _togglePlaylistPanel,
              ),
            ],
          ),
          // Add other menus (Edit, Help, etc.) if needed
        ],
        child: Scaffold(
          // --- REMOVE AppBar ---
          // appBar: _buildAppBar(), // REMOVED
          body: Focus(
            focusNode: _focusNode,
            autofocus: true,
            onKeyEvent: _handleKeyEvent,
            child: Row(
              children: [
                _buildPlaylistPanel(), // Playlist Panel (Left)
                Expanded(
                  // Main Content Area (Right)
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // --- MOVED: Player at the TOP ---
                      BlocBuilder<AudioPlayerBloc, AudioPlayerState>(
                        builder: (context, playerState) {
                          bool shouldShowPlayer = false;
                          if (_selectedTrackForPlayer != null) {
                            if (playerState is AudioPlayerLoading &&
                                playerState.loadingSource ==
                                    _selectedTrackForPlayer!.path) {
                              shouldShowPlayer = true;
                            } else if (playerState is AudioPlayerLoaded &&
                                playerState.currentSource ==
                                    _selectedTrackForPlayer!.path) {
                              shouldShowPlayer = true;
                            }
                          }

                          if (shouldShowPlayer &&
                              _selectedTrackForPlayer != null) {
                            return CombinedAudioPlayerWidget(
                              key: ValueKey(_selectedTrackForPlayer!.id),
                              track: _selectedTrackForPlayer!,
                              isMinimized: _isMinimized,
                              onToggle: _handlePlayerToggle,
                              onPreviousPressed: _playPreviousTrack,
                              onNextPressed: _playNextTrack,
                              maxExpandedHeight: maxPlayerHeight,
                            );
                          } else {
                            return const SizedBox.shrink();
                          }
                        },
                      ),
                      // --- END MOVED Player ---
                      _buildFilterBar(), // Search, View Toggle, Rating, HOME BUTTON
                      if (_currentlySelectedPlaylist != null)
                        _buildPlaylistHeader(),
                      Expanded(
                        child: _buildContentArea(),
                      ), // Table or Tree View
                      // --- REMOVED Player from bottom ---
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: const WaveformProgressBar(),
          floatingActionButton: FloatingActionButton.small(
            onPressed: _showAddMenu,
            tooltip: 'Add...',
            child: const Icon(Icons.add),
          ),
        ),
      ),
    );
  }

  // Show the 'Add' menu
  void _showAddMenu() {
    final collectionMgmtState = context.read<CollectionManagementBloc>().state;
    if (collectionMgmtState is! CollectionManagementLoaded ||
        collectionMgmtState.activeCollectionDefinition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please select or create a collection first."),
        ),
      );
      return;
    }
    final activeCollectionDef = collectionMgmtState.activeCollectionDefinition!;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        MediaQuery.of(context).size.width - 100,
        MediaQuery.of(context).size.height - 150, // Adjust position
        MediaQuery.of(context).size.width,
        MediaQuery.of(context).size.height,
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
      if (value == 'add_file') {
        _fileHandler.pickAndAddAudioFile();
      } else if (value == 'add_folder') {
        _fileHandler.pickAndAddFolder();
      } else if (value == 'add_url') {
        _fileHandler.showAddUrlDialog();
      }
    });
  }
}

extension TrackListNullOrEmpty on List<Track>? {
  bool get isNullOrEmpty => this == null || this!.isEmpty;
}
