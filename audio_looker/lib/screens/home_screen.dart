// lib/screens/home_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:collection/collection.dart';

// Import BLoCs
import '../blocs/collection_management/collection_management_bloc.dart';
import '../blocs/audio_player/audio_player_bloc.dart';
import '../blocs/playlist/playlist_bloc.dart';
import '../blocs/track_management/track_data_bloc.dart';
import '../blocs/track_management/track_metadata_bloc.dart';
import '../blocs/track_management/global_tag_bloc.dart';

// Import Services and Models
import '../services/collection_service.dart';
import '../models/playlist.dart';

// Import Widgets
import '../widgets/playlist_drawer.dart';
import '../widgets/folder_tree_view.dart';
import '../widgets/track_table_widget.dart';
import '../widgets/combined_audio_player_widget.dart';
import '../widgets/rating_filter_widget.dart';
import '../widgets/multi_metadata_editor.dart';

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

  String? activeCollectionName;

  // For managing track table column visibility menu
  final GlobalKey<TrackTableWidgetState> _trackTableKey =
      GlobalKey<TrackTableWidgetState>();
  Map<String, dynamic> _trackTableDefaultConfig = {};
  Set<String> _trackTableVisibleColumns = {};
  bool _isTrackTableConfigLoaded = false;

  @override
  void initState() {
    super.initState();
    context.read<CollectionManagementBloc>().add(LoadCollectionList());
    context.read<PlaylistBloc>().add(LoadPlaylists());
    _searchController.addListener(_onSearchChanged);
    _setupAudioPlayerListener();
    _setupCollectionListener();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleTrackTableConfigChange();
    });
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
      onShowMultiEditDialog: _showMultiEditDialog,
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

  void _showMultiEditDialog(Set<int> trackIds) {
    if (trackIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No tracks selected for editing.")),
      );
      return;
    }

    // Fetch track data from TrackDataBloc state
    final trackDataState = context.read<TrackDataBloc>().state;
    List<Track> tracksToEdit = [];

    List<Track> sourceTracks = [];
    if (trackDataState is TrackDataLoaded) {
      sourceTracks = trackDataState.tracks;
    } else if (trackDataState is TrackDataLoading &&
        trackDataState.previousTracks != null) {
      sourceTracks = trackDataState.previousTracks!;
    } else if (trackDataState is TrackDataProcessingNeeded) {
      sourceTracks = trackDataState.tracks;
    } else if (trackDataState is TrackDataDeletingFolder &&
        trackDataState.previousTracks != null) {
      sourceTracks = trackDataState.previousTracks!;
    }
    // Add other relevant states if they might hold the tracks

    if (sourceTracks.isNotEmpty) {
      for (int id in trackIds) {
        try {
          tracksToEdit.add(sourceTracks.firstWhere((track) => track.id == id));
        } catch (e) {
          print("Could not find track with ID $id for multi-edit.");
        }
      }
    }

    if (tracksToEdit.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Could not load details for selected tracks."),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false, // User must explicitly save or cancel
      builder: (dialogContext) {
        // Provide necessary BLoCs to the dialog
        return MultiBlocProvider(
          providers: [
            BlocProvider.value(
              value: BlocProvider.of<TrackMetadataBloc>(context),
            ),
            BlocProvider.value(value: BlocProvider.of<GlobalTagBloc>(context)),
            // TrackDataBloc is not directly needed by the editor for *fetching*,
            // as we pass the tracks directly. But it might be needed if the editor
            // itself wants to re-fetch or react to general data changes,
            // though typically it acts on the passed data and dispatches updates.
          ],
          child: MultiMetadataEditor(selectedTracks: tracksToEdit),
        );
      },
    );
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
          _trackTableDefaultConfig = {};
          _trackTableVisibleColumns = {};
          _isTrackTableConfigLoaded = false;
        });
        _initializeHandlers();
      }
    });
  }

  @override
  void dispose() {
    _contextMenuHandler.dismiss();
    _focusNode.dispose();
    _searchController.dispose();
    _folderTreeViewKeysNotifier.dispose();
    super.dispose();
  }

  void _toggleColumnVisibility(String columnName) {
    final TrackTableWidgetState? trackTableState = _trackTableKey.currentState;
    if (trackTableState != null) {
      trackTableState.toggleColumnVisibilityAndUpdate(columnName);
    } else {
      print(
        "HomeScreen: Cannot toggle column visibility, _trackTableKey.currentState is null.",
      );
    }
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

  void _handleTrackTableConfigChange() {
    if (!mounted) return;
    final TrackTableWidgetState? trackTableState = _trackTableKey.currentState;
    if (trackTableState != null && trackTableState.isConfigLoadedInternal) {
      bool configChanged =
          !const MapEquality().equals(
            _trackTableDefaultConfig,
            trackTableState.defaultColumnConfigInternal,
          ) ||
          !const SetEquality().equals(
            _trackTableVisibleColumns,
            trackTableState.visibleColumnsInternal,
          );

      if (configChanged || !_isTrackTableConfigLoaded) {
        setState(() {
          _trackTableDefaultConfig = Map<String, dynamic>.from(
            trackTableState.defaultColumnConfigInternal,
          );
          _trackTableVisibleColumns = Set<String>.from(
            trackTableState.visibleColumnsInternal,
          );
          _isTrackTableConfigLoaded = true;
          print(
            "HomeScreen: Track table config updated. Visible: $_trackTableVisibleColumns",
          );
        });
      }
    } else {
      print(
        "HomeScreen: _handleTrackTableConfigChange called, but TrackTableWidget state or config not ready.",
      );
    }
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
      _currentlySelectedPlaylistId =
          newSelectedPlaylist?.id; // Update ID based on selection/deselection
      _selectedTrackIds.clear();
      _anchorTrackId = null;
    });

    context.read<TrackDataBloc>().add(
      SetPlaylistFilter(_currentlySelectedPlaylistId),
    );

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

    _initializeHandlers();
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
      // --- Check if a text input field has focus ---
      final FocusNode? primaryFocus = FocusManager.instance.primaryFocus;
      bool textInputHasFocus = false;

      if (primaryFocus != null && primaryFocus.context != null) {
        // Find the EditableText widget associated with the primary focus.
        // EditableText is the core widget used by TextField and TextFormField.
        final EditableText? editableText =
            primaryFocus.context!
                .findAncestorWidgetOfExactType<
                  EditableText
                >(); // <<< Keep this check

        // We consider a text input focused if EditableText is found
        textInputHasFocus = (editableText != null);

        print(
          "Space pressed. Primary focus context: ${primaryFocus.context}, EditableText found: ${editableText != null}",
        );
      } else {
        print("Space pressed. No primary focus or context found.");
      }
      // --- End Focus Check ---

      if (textInputHasFocus) {
        print("Space ignored by global handler (Text input focused).");
        // Let the focused text input handle the spacebar
        return KeyEventResult.ignored;
      } else {
        print("Space handled by global handler (Toggling play/pause).");
        // No text input focused, handle as play/pause toggle
        _playerControlHandler.togglePlayPause();
        return KeyEventResult.handled;
      }
    }
    // --- Pass other key events down ---
    _folderTreeViewKeysNotifier.value =
        HardwareKeyboard.instance.logicalKeysPressed;
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
      padding: const EdgeInsets.fromLTRB(8.0, 8.0, 16.0, 8.0),
      child: Row(
        children: [
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
          // New PopupMenuButton for column visibility
          if (_viewMode == ViewMode.list && _isTrackTableConfigLoaded)
            PopupMenuButton<String>(
              icon: Icon(
                Icons.view_column_outlined,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              tooltip: "Select Columns",
              onSelected: (String columnName) {
                _toggleColumnVisibility(columnName);
              },
              itemBuilder: (BuildContext context) {
                if (!_isTrackTableConfigLoaded ||
                    _trackTableDefaultConfig.isEmpty) {
                  return [
                    const PopupMenuItem(
                      value: "_loading",
                      enabled: false,
                      child: Text("Loading columns..."),
                    ),
                  ];
                }

                final List<PopupMenuEntry<String>> items = [];
                final sortedColumnEntries =
                    _trackTableDefaultConfig.entries.toList()..sort((a, b) {
                      final String labelA =
                          (a.value is Map && a.value['label'] is String)
                              ? a.value['label']
                              : a.key;
                      final String labelB =
                          (b.value is Map && b.value['label'] is String)
                              ? b.value['label']
                              : b.key;
                      return labelA.compareTo(labelB);
                    });

                for (var entry in sortedColumnEntries) {
                  final columnName = entry.key;
                  final columnConfig = entry.value as Map<String, dynamic>;
                  final String columnLabel =
                      columnConfig['label'] as String? ?? columnName;

                  if (columnName == 'preview')
                    continue; // Skip the 'preview' column

                  items.add(
                    CheckedPopupMenuItem<String>(
                      value: columnName,
                      checked: _trackTableVisibleColumns.contains(columnName),
                      child: Text(columnLabel),
                    ),
                  );
                }
                return items;
              },
            ),
          const Spacer(),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.2,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search...',
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
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        )
                        : null,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 0,
                ),
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: 16),
          BlocBuilder<TrackDataBloc, TrackDataState>(
            builder: (context, state) {
              int? currentFilterValue;
              if (state is TrackDataLoaded) {
                currentFilterValue = state.minimumRating;
              } else if (state is TrackDataLoading) {
                currentFilterValue = state.minimumRating;
              } else if (state is TrackDataProcessingNeeded) {
                currentFilterValue = state.minimumRating;
              } else if (state is TrackDataDeletingFolder) {
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
    return GestureDetector(
      // Keep the wrapper for outside tap dismissal
      onTap: () {
        // Dismiss the menu using the handler's dismiss method
        if (_contextMenuHandler.isMenuVisible) {
          print("GestureDetector onTap - Dismissing menu via handler");
          _contextMenuHandler.dismiss();
        }
      },
      child: DropTarget(
        onDragDone:
            (detail) async =>
                await _fileHandler.handleDroppedFiles(detail.files),
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
                            onColumnConfigChanged:
                                _handleTrackTableConfigChange,
                            key: _trackTableKey,
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
      ),
    );
  }

  void confirmAndDeleteSelected() {
    // Should be private or public within the handler
    if (_selectedTrackIds.isEmpty) return;
    final count = _selectedTrackIds.length;

    showDialog(
      context: context, // Use handler's context
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Delete'),
          content: Text('Are you sure you want to remove $count item(s)?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _performDelete(); // Call the delete logic below
              },
            ),
          ],
        );
      },
    );
  }

  void _performDelete() {
    // ... implementation using BlocProvider.of(context).add(...) ...
    final collectionBloc = BlocProvider.of<TrackDataBloc>(context);
    final audioPlayerBloc = BlocProvider.of<AudioPlayerBloc>(context);
    final idsToDelete = List<int>.from(_selectedTrackIds);

    // Stop player if needed...
    Track? currentlyPlayingTrack;
    final playerState = audioPlayerBloc.state;
    if (playerState is AudioPlayerLoaded) {
      final trackDataState = collectionBloc.state;
      List<Track> currentTracks = [];
      if (trackDataState is TrackDataLoaded)
        currentTracks = trackDataState.tracks;
      else if (trackDataState is TrackDataProcessingNeeded)
        currentTracks = trackDataState.tracks;
      // Add other states if needed
      try {
        currentlyPlayingTrack = currentTracks.firstWhere(
          (t) => t.path == playerState.currentSource,
        );
      } catch (e) {
        /* not found */
      }
    }
    if (currentlyPlayingTrack != null &&
        idsToDelete.contains(currentlyPlayingTrack.id)) {
      audioPlayerBloc.add(StopAudio());
    }

    // Dispatch delete events
    for (final trackId in idsToDelete) {
      collectionBloc.add(RemoveTrack(trackId));
    }
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
    // final maxPlayerHeight = (availableHeight * 0.6).clamp(
    //   200.0,
    //   250.0,
    // ); // Example: 80% of remaining height

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
            if (state is TrackDataLoaded ||
                state is TrackDataProcessingNeeded) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _handleTrackTableConfigChange();
              });
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
          body: GestureDetector(
            // Keep the outer GestureDetector
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              if (_contextMenuHandler.isMenuVisible) {
                // Optional: Add logic here to check if the tap is *outside* the menu bounds
                // before dismissing, if simple tap isn't enough.
                print(
                  "GestureDetector onTapDown - Dismissing menu via handler",
                );
                _contextMenuHandler.dismiss();
              }
            },
            child: Focus(
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
                            // bool shouldShowPlayer = false;
                            if (_selectedTrackForPlayer != null) {
                              if (playerState is AudioPlayerLoading &&
                                  playerState.loadingSource ==
                                      _selectedTrackForPlayer!.path) {
                                // shouldShowPlayer = true;
                              } else if (playerState is AudioPlayerLoaded &&
                                  playerState.currentSource ==
                                      _selectedTrackForPlayer!.path) {
                                // shouldShowPlayer = true;
                              }
                            }

                            // if (shouldShowPlayer &&
                            //     _selectedTrackForPlayer != null) {
                            return CombinedAudioPlayerWidget(
                              // key: ValueKey(
                              //   (_selectedTrackForPlayer != null)
                              //       ? _selectedTrackForPlayer!.id
                              //       : "",
                              // ),
                              // track: _selectedTrackForPlayer,
                              isMinimized: _isMinimized,
                              onToggle: _handlePlayerToggle,
                              onPreviousPressed: _playPreviousTrack,
                              onNextPressed: _playNextTrack,
                              // maxExpandedHeight: maxPlayerHeight,
                              activeCollectionName: activeCollectionName,
                            );
                            // } else {
                            //   return const SizedBox.shrink();
                            // }
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
