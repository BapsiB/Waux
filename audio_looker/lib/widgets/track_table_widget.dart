// lib/widgets/track_table_widget.dart

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:collection/collection.dart';
import 'package:waux/blocs/track_management/track_metadata_bloc.dart';
import 'dart:math' as math;
import 'package:flutter_bloc/flutter_bloc.dart'; // Import BlocProvider

import 'package:waux/blocs/audio_player/audio_player_bloc.dart';
import 'package:waux/services/collection_service.dart'; // Track model and CollectionService
import 'package:waux/widgets/track_data_source.dart';

import 'dart:async';

// Callback types
typedef SelectionChangeCallback =
    void Function(
      int trackId,
      bool isSelected, {
      bool isShiftPressed,
      bool isCtrlPressed,
    });
typedef ContextMenuCallback =
    void Function(BuildContext context, Offset tapPosition, Track track);
typedef RatingChangeCallback = void Function(int trackId, int newRating);
typedef SortCallback =
    void Function(String columnName, DataGridSortDirection direction);
typedef PlayAndMinimizeCallback = void Function(Track track, bool togglePlay);
typedef SelectAndOpenPlayerCallback = void Function(Track track);
typedef DoubleTapCallback = void Function(Track track);
typedef ColumnConfigChangedCallback = void Function();

class TrackTableWidget extends StatefulWidget {
  final List<Track> tracks;
  final Set<int> selectedTrackIds;
  final AudioPlayerBloc audioPlayerBloc;
  final SelectionChangeCallback onSelectionChanged;
  final ContextMenuCallback onShowContextMenu;
  final RatingChangeCallback onRatingChanged;
  final SortCallback onSort;
  final String initialSortColumnName;
  final DataGridSortDirection initialSortDirection;
  final PlayAndMinimizeCallback onPlayPreviewAndMinimize;
  final SelectAndOpenPlayerCallback onEditMetadata;
  final SetSearchTextCallback onSetSearchText;
  final DoubleTapCallback onRowDoubleTap;
  final ColumnConfigChangedCallback? onColumnConfigChanged;

  const TrackTableWidget({
    Key? key,
    required this.tracks,
    required this.selectedTrackIds,
    required this.audioPlayerBloc,
    required this.onSelectionChanged,
    required this.onShowContextMenu,
    required this.onRatingChanged,
    required this.onSort,
    required this.initialSortColumnName,
    required this.initialSortDirection,
    required this.onPlayPreviewAndMinimize,
    required this.onEditMetadata,
    required this.onSetSearchText,
    required this.onRowDoubleTap,
    this.onColumnConfigChanged,
  }) : super(key: key);

  @override
  TrackTableWidgetState createState() => TrackTableWidgetState();
}

class TrackTableWidgetState extends State<TrackTableWidget> {
  final GlobalKey<SfDataGridState> _sfDataGridKey =
      GlobalKey<SfDataGridState>();
  final FocusNode _focusNode = FocusNode();
  late TrackDataSource _trackDataSource;
  late DataGridController _dataGridController;

  late List<GridColumn> _gridColumns = []; // Initialize empty
  bool _isColumnsInitialized = false;
  bool _isLayoutFrozen = false;
  bool _isLoadingConfig = true; // State to track config loading
  final Duration _doubleClickThreshold = const Duration(milliseconds: 300);
  DateTime? _lastTapTime;
  int? _lastTappedTrackId;

  // Add state variable to store width
  double _containerWidth = 0;
  // Flag to prevent recursive resizing loops (optional but safer)
  bool _isAdjustingLastColumn = false;

  // Map storing current width for each column name
  Map<String, double> _columnWidths = {};
  // List storing the current order of visible column names
  List<String> _columnOrder = [];
  // Set storing the names of columns that are currently visible
  Set<String> _visibleColumns = {};

  // Define minimum width specifically for the last column when auto-shrinking
  final double _minLastColShrinkWidth = 50.0;

  final double _minColWidth = 50.0;

  Timer? _clickTimer;
  DataGridCellTapDetails? _potentialEditCellDetails;
  String? _editingCellKey; // Format: "trackId_columnName"
  // Controller for the text field when editing
  final TextEditingController _cellEditController = TextEditingController();
  final FocusNode _cellEditFocusNode = FocusNode();

  // Define the full set of possible columns and their default states (used as fallback)
  final Map<String, dynamic> _defaultColumnConfig = {
    'preview': {
      'width': 250.0,
      'visible': true,
      'label': 'Preview',
      'allowSorting': false,
      'isNumeric': false,
    },
    'title': {
      'width': 150.0,
      'visible': true,
      'label': 'Title',
      'allowSorting': true,
      'isNumeric': false,
    },
    'artist': {
      'width': 150.0,
      'visible': true,
      'label': 'Artist',
      'allowSorting': true,
      'isNumeric': false,
    },
    'album': {
      'width': 150.0,
      'visible': true,
      'label': 'Album',
      'allowSorting': true,
      'isNumeric': false,
    },
    'rating': {
      'width': 100.0,
      'visible': true,
      'label': 'Rating',
      'allowSorting': true,
      'isNumeric': true,
    },
    'tags': {
      'width': 150.0,
      'visible': true,
      'label': 'Tags',
      'allowSorting': false, // Sorting for tags can be complex
      'isNumeric': false,
    },
    'duration': {
      'width': 80.0,
      'visible': true,
      'label': 'Duration',
      'allowSorting': true,
      'isNumeric': true,
    },
    'source': {
      'width': 60.0,
      'visible': true,
      'label': 'Source',
      'allowSorting': false,
      'isNumeric': false,
    },
    // Other potential columns (not visible by default unless saved in config)
    // These could be added by the user via a column picker UI in the future.
    'albumArtist': {
      'width': 150.0,
      'visible': false, // Not visible by default
      'label': 'Album Artist',
      'allowSorting': true,
      'isNumeric': false,
    },
    'composer': {
      'width': 150.0,
      'visible': false, // Not visible by default
      'label': 'Composer',
      'allowSorting': true,
      'isNumeric': false,
    },
    'genre': {
      'width': 100.0,
      'visible': false, // Not visible by default
      'label': 'Genre',
      'allowSorting': true,
      'isNumeric': false,
    },
    'year': {
      'width': 70.0,
      'visible': false, // Not visible by default
      'label': 'Year',
      'allowSorting': true,
      'isNumeric': true,
    },
    'bpm': {
      'width': 70.0,
      'visible': false, // Not visible by default
      'label': 'BPM',
      'allowSorting': true,
      'isNumeric': true,
    },
    // Fields explicitly EXCLUDED from being columns as per user request:
    // 'discNumber', 'trackNumber', 'path', 'timeMarkers', 'comment'
    // These are not included in _defaultColumnConfig, so they won't appear.
  };

  Map<String, dynamic> get defaultColumnConfigInternal => _defaultColumnConfig;
  Set<String> get visibleColumnsInternal => _visibleColumns;
  bool get isConfigLoadedInternal => !_isLoadingConfig;

  @override
  void initState() {
    super.initState();

    // Initialize DataSource with empty/default order initially
    _trackDataSource = TrackDataSource(
      trackData: widget.tracks,
      audioPlayerBloc: widget.audioPlayerBloc,
      onRatingChanged: widget.onRatingChanged,
      onPlayPreviewAndMinimize: widget.onPlayPreviewAndMinimize,
      onEditMetadata: widget.onEditMetadata,
      initialColumnOrder: [],
      onSetSearchText: widget.onSetSearchText,
      getEditingCellKey: () => _editingCellKey,
      onEndEditing: _handleEndEditing, // Add callback
      cellEditController: _cellEditController, // Pass controller
      cellEditFocusNode: _cellEditFocusNode, // Pass focus node
    );

    // Initialize Controller
    _dataGridController = DataGridController();

    // Load configuration asynchronously
    _loadConfigFromService();

    // Focus logic
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // FocusScope.of(context).requestFocus(_focusNode);
        _updateControllerSelection();
      }
    });
  }

  void _handleEndEditing({String? newValue}) {
    if (_editingCellKey == null) return;

    final parts = _editingCellKey!.split('_');
    if (parts.length == 2) {
      final trackIdStr = parts[0];
      final columnName = parts[1];
      final trackId = int.tryParse(trackIdStr);

      if (trackId != null && newValue != null) {
        Track? originalTrack;
        try {
          originalTrack = widget.tracks.firstWhere((t) => t.id == trackId);
        } catch (e) {
          print("Error finding track for editing: $e");
        }
        final originalValue =
            originalTrack != null
                ? _getTrackValueByColumn(originalTrack, columnName)
                : null;

        if (newValue != originalValue) {
          print(
            "Saving Track ID: $trackId, Column: $columnName, New Value: '$newValue'",
          );
          try {
            final metadataBloc = context.read<TrackMetadataBloc>();
            switch (columnName) {
              case 'title':
                metadataBloc.add(UpdateTrackTitle(trackId, newValue));
                break;
              case 'artist':
                metadataBloc.add(UpdateTrackArtist(trackId, newValue));
                break;
              case 'album':
                metadataBloc.add(UpdateTrackAlbum(trackId, newValue));
                break;
              // Add cases for other editable columns if they are added
              // e.g., 'albumArtist', 'composer', 'genre', 'year', 'bpm'
              case 'albumArtist':
                metadataBloc.add(UpdateTrackAlbumArtist(trackId, newValue));
                break;
              case 'composer':
                metadataBloc.add(UpdateTrackComposer(trackId, newValue));
                break;
              case 'genre':
                metadataBloc.add(UpdateTrackGenre(trackId, newValue));
                break;
              case 'year':
                metadataBloc.add(
                  UpdateTrackYear(trackId, int.tryParse(newValue)),
                );
                break;
              case 'bpm':
                metadataBloc.add(
                  UpdateTrackBpm(trackId, int.tryParse(newValue)),
                );
                break;
              default:
                print("Warning: Tried to save unhandled column: $columnName");
            }
          } catch (e) {
            print("Error dispatching metadata update: $e");
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Error saving changes: $e')));
          }
        } else {
          print("Value not changed for $_editingCellKey. No save needed.");
        }
      } else {
        print("Edit cancelled or invalid ID for $_editingCellKey");
      }
    }

    setState(() {
      _editingCellKey = null;
      _potentialEditCellDetails = null;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusScope.of(context).requestFocus(_focusNode);
    });
  }

  // Helper to get track value by column name (you already have this)
  String _getTrackValueByColumn(Track track, String columnName) {
    switch (columnName) {
      case 'title':
        return track.title;
      case 'artist':
        return track.artist;
      case 'album':
        return track.album;
      case 'albumArtist':
        return track.albumArtist ?? '';
      case 'composer':
        return track.composer ?? '';
      case 'genre':
        return track.genre ?? '';
      case 'year':
        return track.year?.toString() ?? '';
      case 'bpm':
        return track.bpm?.toString() ?? '';
      // Note: 'rating', 'tags', 'duration', 'preview', 'source' are handled by custom widgets
      // or different data types and are not directly text-editable in this generic way.
      default:
        return '';
    }
  }

  // --- Helper to check if a row index corresponds to a selected track ---
  bool _isRowSelected(int rowIndex) {
    if (rowIndex <= 0 || rowIndex > _trackDataSource.rows.length) return false;
    final dataRow =
        _trackDataSource.rows[rowIndex - 1]; // Adjust for header row
    final idCell = dataRow.getCells().firstWhere(
      (cell) => cell.columnName == 'id',
      orElse: () => DataGridCell<int>(columnName: 'id', value: -1),
    );
    final int trackId = idCell.value as int? ?? -1;
    return trackId != -1 && widget.selectedTrackIds.contains(trackId);
  }

  // --- Logic to start the edit timer ---
  void _startEditTimer(DataGridCellTapDetails details) {
    _clickTimer?.cancel(); // Cancel previous timer
    _potentialEditCellDetails = details; // Store details for the timer callback

    _clickTimer = Timer(_doubleClickThreshold, () {
      // Timer expired - this is a slow single click
      if (_potentialEditCellDetails == null) return;

      final int rowIndex = _potentialEditCellDetails!.rowColumnIndex.rowIndex;
      final int columnIndex =
          _potentialEditCellDetails!.rowColumnIndex.columnIndex;
      // Ensure row index is valid (greater than 0 for data rows)
      if (rowIndex <= 0 ||
          columnIndex < 0 ||
          columnIndex >= _gridColumns.length)
        return;

      final String columnName = _gridColumns[columnIndex].columnName;
      final List<String> editableColumns = [
        'title', 'artist', 'album',
        'albumArtist',
        'composer',
        'genre',
        'year',
        'bpm', // Add new editable fields
      ];

      if (editableColumns.contains(columnName)) {
        final dataRow =
            _trackDataSource.rows[rowIndex - 1]; // Adjust for header
        final idCell = dataRow.getCells().firstWhere(
          (cell) => cell.columnName == 'id',
          orElse: () => DataGridCell<int>(columnName: 'id', value: -1),
        );
        final int trackId = idCell.value as int? ?? -1;

        if (trackId != -1) {
          final String newEditingCellKey = "${trackId}_$columnName";
          // Check if already editing this cell to prevent infinite loop? No, should be fine.
          if (_editingCellKey != newEditingCellKey) {
            try {
              final track = widget.tracks.firstWhere((t) => t.id == trackId);
              final currentValue = _getTrackValueByColumn(track, columnName);
              _cellEditController.text = currentValue; // Pre-fill controller
              setState(() {
                _editingCellKey = newEditingCellKey;
              });
              // Request focus after state update
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  FocusScope.of(context).requestFocus(_cellEditFocusNode);
                  // Select all text in the text field
                  _cellEditController.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: _cellEditController.text.length,
                  );
                }
              });
            } catch (e) {
              print("Error finding track to edit: $e");
              _handleEndEditing(); // Clear editing state on error
            }
          }
        }
      }
      _potentialEditCellDetails = null; // Clear potential edit details
    });
  }

  // Asynchronously load configuration from CollectionService
  Future<void> _loadConfigFromService() async {
    setState(() => _isLoadingConfig = true);
    try {
      // Access CollectionService using BlocProvider.of or context.read
      final service = context.read<CollectionService>();
      final savedConfig = await service.loadColumnConfig();

      if (mounted) {
        setState(() {
          _applyLoadedConfig(savedConfig); // Apply loaded or defaults
          _isColumnsInitialized = true; // Columns can now be built
          _isLoadingConfig = false; // End loading
        });
        // Update the datasource with the final order AFTER config is loaded and state is set
        _trackDataSource.updateColumnOrder(_columnOrder);
        // Rebuild columns based on the loaded state
        _buildGridColumnsFromState();
      }
    } catch (e) {
      print("Error loading config in TrackTableWidget: $e");
      if (mounted) {
        setState(() {
          _applyLoadedConfig(null); // Apply defaults on error
          _isColumnsInitialized = true;
          _isLoadingConfig = false;
        });
        _trackDataSource.updateColumnOrder(_columnOrder);
        _buildGridColumnsFromState();
      }
    }
  }

  // Applies loaded config or defaults to the state variables
  void _applyLoadedConfig(Map<String, dynamic>? savedConfig) {
    if (savedConfig != null) {
      print("Applying saved config: $savedConfig");
      // Safely parse widths, ensuring they are doubles
      _columnWidths =
          (savedConfig['widths'] as Map<String, dynamic>?)?.map(
            (key, value) => MapEntry(key, (value as num).toDouble()),
          ) ??
          {};
      // Safely parse order
      _columnOrder = List<String>.from(savedConfig['order'] as List? ?? []);
      // Safely parse visible columns
      _visibleColumns = Set<String>.from(savedConfig['visible'] as List? ?? []);
    } else {
      print("Applying default config.");
      // Apply defaults if no saved config
      _columnWidths = {
        for (var k in _defaultColumnConfig.keys)
          k: (_defaultColumnConfig[k]['width'] as num).toDouble(),
      };
      _columnOrder = _defaultColumnConfig.keys.toList();
      _visibleColumns =
          _defaultColumnConfig.keys
              .where((k) => _defaultColumnConfig[k]['visible'] as bool)
              .toSet();
    }
    _ensureDefaultConfigApplied(); // Ensure completeness and consistency
  }

  void _ensureDefaultConfigApplied() {
    for (var key in _defaultColumnConfig.keys) {
      _columnWidths.putIfAbsent(
        key,
        () => (_defaultColumnConfig[key]['width'] as num).toDouble(),
      );
      if (_defaultColumnConfig[key]['visible'] as bool? ?? true) {
        // Ensure 'preview' is always visible and cannot be hidden by user config
        if (key == 'preview') {
          _visibleColumns.add(key);
        } else if (!_visibleColumns.contains(key) &&
            (_defaultColumnConfig[key]['visible'] as bool? ?? false)) {
          // Add if default is visible and not already in _visibleColumns (e.g. from saved config)
          _visibleColumns.add(key);
        }
      }
    }
    // Ensure 'preview' is always first if it's visible
    if (_visibleColumns.contains('preview')) {
      _columnOrder.remove('preview');
      _columnOrder.insert(0, 'preview');
    }

    final currentVisibleSet = Set<String>.from(_visibleColumns);
    List<String> finalOrder =
        _columnOrder
            .where(
              (c) =>
                  currentVisibleSet.contains(c) &&
                  _defaultColumnConfig.containsKey(c),
            )
            .toList();

    // Add any visible columns that were missing from _columnOrder, respecting _defaultColumnConfig order
    List<String> defaultOrderKeys = _defaultColumnConfig.keys.toList();
    for (String colNameFromDefault in defaultOrderKeys) {
      if (_visibleColumns.contains(colNameFromDefault) &&
          !finalOrder.contains(colNameFromDefault)) {
        finalOrder.add(colNameFromDefault);
      }
    }

    _columnOrder = finalOrder;
    _visibleColumns.removeWhere(
      (colName) => !_defaultColumnConfig.containsKey(colName),
    );
  }

  // Saves the current column configuration using CollectionService
  Future<void> _saveColumnConfiguration() async {
    if (_isLoadingConfig) return; // Don't save while loading initial config

    // Get the current order directly from the _gridColumns state
    final currentOrder =
        _gridColumns
            .where(
              (c) => c.columnName != 'id',
            ) // Exclude hidden 'id' column if present
            .map((c) => c.columnName)
            .toList();

    final configToSave = {
      'widths': _columnWidths,
      'order': currentOrder, // Use the actual current order
      'visible': _visibleColumns.toList(), // Convert set to list for JSON
    };

    print("Saving column config: $configToSave");
    try {
      // Access CollectionService using context
      final service = context.read<CollectionService>();
      await service.saveColumnConfig(configToSave);
    } catch (e) {
      print("Error saving column config in TrackTableWidget: $e");
      // Optionally show a snackbar or log the error
    }
  }

  // Builds the GridColumn list based on the current state (_columnOrder, _visibleColumns, _columnWidths)
  void _buildGridColumnsFromState() {
    if (!mounted) return;
    final textTheme = Theme.of(context).textTheme;

    // 1. Determine the final order of VISIBLE columns based on current _columnOrder and _visibleColumns
    // _columnOrder should ideally already be filtered by visibility by the time this is called,
    // but we ensure it here.
    List<String> finalVisibleOrder =
        _columnOrder
            .where(
              (name) =>
                  _visibleColumns.contains(name) &&
                  _defaultColumnConfig.containsKey(name),
            )
            .toList();

    // If _columnOrder somehow became empty or didn't respect _visibleColumns, rebuild it.
    if (finalVisibleOrder.isEmpty && _visibleColumns.isNotEmpty) {
      finalVisibleOrder =
          _defaultColumnConfig.keys
              .where((key) => _visibleColumns.contains(key))
              .toList();
    }
    // Ensure 'preview' is always first if it's visible
    if (_visibleColumns.contains('preview')) {
      finalVisibleOrder.remove('preview');
      finalVisibleOrder.insert(0, 'preview');
    }

    // Update the internal _columnOrder to this definitive list
    _columnOrder = finalVisibleOrder;

    // 2. Update the TrackDataSource with this exact order
    // This is crucial for keeping SfDataGrid.columns and DataGridRowAdapter.cells in sync.
    _trackDataSource.updateColumnOrder(_columnOrder);

    // 3. Build GridColumn objects based on this final visible order
    final List<GridColumn> newColumns = [];
    for (final String columnName in _columnOrder) {
      if (_defaultColumnConfig.containsKey(columnName)) {
        // Should always be true due to above filtering
        final config = _defaultColumnConfig[columnName];
        final width =
            _columnWidths[columnName] ?? (config['width'] as num).toDouble();
        final widthMode =
            _isLayoutFrozen ? ColumnWidthMode.none : ColumnWidthMode.auto;

        Widget headerLabel;
        Alignment headerAlignment = Alignment.centerLeft;
        if (columnName == 'source') {
          headerAlignment = Alignment.center;
          headerLabel = Tooltip(
            message: config['label'],
            child: Icon(
              Icons.link,
              size: 16,
              color: textTheme.titleSmall?.color,
            ),
          );
        } else {
          headerLabel = Text(
            config['label'],
            style: textTheme.titleSmall,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          );
        }

        newColumns.add(
          GridColumn(
            columnName: columnName,
            width: width,
            columnWidthMode: widthMode,
            allowSorting: config['allowSorting'] ?? true,
            label: Container(
              alignment: headerAlignment,
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: headerLabel,
            ),
            visible: true,
          ),
        );
      }
    }

    // 4. Update state and notify HomeScreen
    if (mounted) {
      setState(() {
        _gridColumns =
            newColumns; // This list's length now matches _trackDataSource._currentColumnOrder.length
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onColumnConfigChanged?.call();
      });
    } else {
      _gridColumns = newColumns;
    }
  }

  // Updates the SfDataGrid controller's selection based on widget.selectedTrackIds
  // Inside TrackTableWidgetState class in lib/widgets/track_table_widget.dart

  // 1. Add the helper method:
  /// Checks if a given DataGridRow should be part of the current selection
  /// based on widget.selectedTrackIds.
  bool _shouldSelectRow(DataGridRow row) {
    // Find the cell containing the ID, safely using firstWhereOrNull.
    final idCell = row.getCells().firstWhereOrNull((c) => c.columnName == 'id');

    // --- Validation Step 1: Check if ID cell exists and has a value ---
    if (idCell?.value == null) {
      // This row cannot be selected if it doesn't have a valid ID cell.
      // This situation *shouldn't* occur based on how TrackDataSource is built,
      // but checking makes the code more robust.
      // print("[LOG] _shouldSelectRow: Skipping row - ID cell or value is null."); // Debug log (optional)
      return false;
    }

    // --- Validation Step 2: Verify the value is an integer ---
    // Although TrackDataSource defines it as DataGridCell<int>,
    // an extra check prevents runtime errors if something unexpected happened.
    if (idCell?.value is! int) {
      print(
        "[LOG] _shouldSelectRow: Skipping row - ID cell value is not type int (Type: ${idCell?.value.runtimeType}). Value: ${idCell?.value}",
      ); // More detailed log
      return false;
    }

    // --- Cast and Check Selection ---
    final trackId = idCell?.value as int; // Safe to cast now
    final isSelected = widget.selectedTrackIds.contains(trackId);

    // print("[LOG] _shouldSelectRow: Checking Row ID $trackId -> In selection set? $isSelected"); // Verbose log (optional)
    return isSelected;
  }

  // 2. Modify _updateControllerSelection to use the helper:
  void _updateControllerSelection() {
    // ... (existing initial checks: mounted, loading, grid context etc.) ...
    print("[LOG] TrackTableWidget: Running _updateControllerSelection.");
    print(
      "[LOG]   Target selected IDs (widget.selectedTrackIds): ${widget.selectedTrackIds}",
    );

    try {
      final currentRows = _trackDataSource.rows;
      print("[LOG]   Current DataSource rows count: ${currentRows.length}");

      if (currentRows.isEmpty) {
        // ... (handle empty rows) ...
        return;
      }

      // --- Calculate the new selection using the helper function ---
      print(
        "[LOG]   Filtering current rows using _shouldSelectRow predicate...",
      );
      // Use the extracted helper method directly in the 'where' clause.
      final List<DataGridRow> newSelectedRows =
          currentRows.where(_shouldSelectRow).toList();
      // --- End Calculation ---

      // --- Logging the result (as before) ---
      final List<int?> newSelectedRowIds =
          newSelectedRows.map((r) {
            final idCell = r.getCells().firstWhereOrNull(
              (c) => c.columnName == 'id',
            );
            return idCell?.value as int?;
          }).toList();
      print(
        "[LOG]   Calculated newSelectedRows count: ${newSelectedRows.length}",
      );
      print("[LOG]   Calculated newSelectedRows IDs: $newSelectedRowIds");
      // ---

      // --- Compare and Apply the selection (as before) ---
      final currentControllerSelectedIds =
          _dataGridController.selectedRows
              .map((row) {
                final idCell = row.getCells().firstWhereOrNull(
                  (c) => c.columnName == 'id',
                );
                return idCell?.value as int?;
              })
              .whereNotNull()
              .toSet();
      print(
        "[LOG]   Current Controller Selected IDs: $currentControllerSelectedIds",
      );

      final targetSelectedIds = widget.selectedTrackIds;

      bool needsUpdate =
          !const SetEquality<int>().equals(
            currentControllerSelectedIds,
            targetSelectedIds,
          );

      if (needsUpdate) {
        // Optional check (as before)
        // if (newSelectedRows.length != targetSelectedIds.length) { ... }

        print(
          "[LOG]   Applying new selection to controller: ${newSelectedRows.length} rows.",
        );
        _dataGridController.selectedRows = newSelectedRows; // THE ASSIGNMENT
        _dataGridController.selectedRow = newSelectedRows.firstOrNull;

        print(
          "[LOG]   Controller selectedRows count after update: ${_dataGridController.selectedRows.length}",
        );
      } else {
        print(
          "[LOG]   Controller selection already matches target IDs. Skipping update.",
        );
      }
      // ---
    } catch (e, stackTrace) {
      debugPrint(
        "TrackTableWidget: Error in _updateControllerSelection: $e\n$stackTrace",
      );
    }
    print("[LOG] TrackTableWidget: Finished _updateControllerSelection.");
  }

  @override
  void didUpdateWidget(TrackTableWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    bool dataSourceUpdated = false;
    // Update the data source if the tracks list changes
    if (!const ListEquality().equals(widget.tracks, oldWidget.tracks)) {
      _trackDataSource.updateDataGridSource(trackData: widget.tracks);
      dataSourceUpdated = true;
    }

    // Update controller selection if external IDs change OR if datasource was updated
    if (dataSourceUpdated ||
        !const SetEquality().equals(
          widget.selectedTrackIds,
          oldWidget.selectedTrackIds,
        )) {
      _updateControllerSelection();
    }

    if (widget.onSetSearchText != oldWidget.onSetSearchText) {
      // Assuming TrackDataSource has a method or way to update its callback reference
      // This depends on how TrackDataSource is implemented. If it stores the callback directly,
      // we might need to recreate the TrackDataSource instance or add an update method.
      // For simplicity, let's recreate if the callback changes.
      // NOTE: Recreating the datasource might have performance implications.
      _trackDataSource = TrackDataSource(
        trackData: widget.tracks,
        audioPlayerBloc: widget.audioPlayerBloc,
        onRatingChanged: widget.onRatingChanged,
        onPlayPreviewAndMinimize: widget.onPlayPreviewAndMinimize,
        onEditMetadata: widget.onEditMetadata,
        initialColumnOrder: _columnOrder, // Use current order
        onSetSearchText: widget.onSetSearchText, // <<< PASS UPDATED CALLBACK
        getEditingCellKey: () => _editingCellKey,
        onEndEditing: _handleEndEditing, // Add callback
        cellEditController: _cellEditController, // Pass controller
        cellEditFocusNode: _cellEditFocusNode, // Pass focus node
      );
      // After recreating, we might need to re-apply selection
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateControllerSelection();
      });
    }

    if (widget.onColumnConfigChanged != oldWidget.onColumnConfigChanged) {
      // If the callback itself changes, we might want to call it immediately
      // if the config is already loaded.
      if (isConfigLoadedInternal) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onColumnConfigChanged?.call();
        });
      }
    }
  }

  @override
  void dispose() {
    _clickTimer?.cancel();
    _cellEditController.dispose();
    _cellEditFocusNode.dispose();
    _focusNode.dispose();
    // _focusNode.dispose();
    _dataGridController.dispose();
    super.dispose();
  }

  void _handleGridSelectionChange(
    List<DataGridRow> addedRows,
    List<DataGridRow> removedRows,
  ) {
    final keyState = HardwareKeyboard.instance;
    final bool isShiftPressed = keyState.isShiftPressed;
    final bool isCtrlPressed =
        keyState.isControlPressed || keyState.isMetaPressed;

    // --- MODIFIED: Handle multiple added/removed rows ---
    // Process removals first
    for (final row in removedRows) {
      final idCell = row.getCells().firstWhere(
        (c) => c.columnName == 'id',
        orElse: () => DataGridCell<int>(columnName: 'id', value: -1),
      );
      if (idCell.value != null && idCell.value != -1) {
        // Report deselection to the parent handler
        widget.onSelectionChanged(
          idCell.value as int,
          false, // isSelected is false for removal
          isShiftPressed: isShiftPressed, // Pass modifiers
          isCtrlPressed: isCtrlPressed,
        );
      }
    }

    // Process additions
    for (final row in addedRows) {
      final idCell = row.getCells().firstWhere(
        (c) => c.columnName == 'id',
        orElse: () => DataGridCell<int>(columnName: 'id', value: -1),
      );
      if (idCell.value != null && idCell.value != -1) {
        // Report selection to the parent handler
        widget.onSelectionChanged(
          idCell.value as int,
          true, // isSelected is true for addition
          isShiftPressed: isShiftPressed, // Pass modifiers
          isCtrlPressed: isCtrlPressed,
        );
      }
    }

    if (mounted && (addedRows.isNotEmpty || removedRows.isNotEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) FocusScope.of(context).requestFocus(_focusNode);
      });
    }

    print(
      "SelectionChange: Shift=$isShiftPressed, Ctrl/Meta=$isCtrlPressed. Added: ${addedRows.length}, Removed: ${removedRows.length}",
    );
  }

  // Updated method to handle resize logic
  void _handleColumnResize(
    ColumnResizeUpdateDetails details,
    double containerWidth,
  ) {
    if (_isAdjustingLastColumn || containerWidth <= 0)
      return; // Prevent potential recursion and handle zero width

    final String resizedColumnName = details.column.columnName;
    // Ensure minimum width for the resized column
    double newWidth = math.max(_minColWidth, details.width);

    // Create a temporary map to calculate potential new total width
    final Map<String, double> tentativeWidths = Map.from(_columnWidths);
    tentativeWidths[resizedColumnName] = newWidth;

    // Calculate the total width of *visible* columns with the new width applied
    double currentTotalWidth = 0;
    final List<String> visibleOrderedColumns =
        _columnOrder.where((name) => _visibleColumns.contains(name)).toList();

    if (visibleOrderedColumns.isEmpty) {
      print("Warning: No visible columns found during resize.");
    } else {
      for (final colName in visibleOrderedColumns) {
        currentTotalWidth +=
            tentativeWidths[colName] ??
            _minColWidth; // Use default if somehow missing
      }

      print(
        "Container Width: $containerWidth, Tentative Total Width: $currentTotalWidth",
      );

      final String lastVisibleColumnName = visibleOrderedColumns.last;
      final bool isResizingLastColumn =
          (lastVisibleColumnName == resizedColumnName);
      double lastColCurrentWidth =
          _columnWidths[lastVisibleColumnName] ??
          _minColWidth; // Use width *before* this resize event

      // --- Logic Branching ---
      if (currentTotalWidth < containerWidth) {
        // ** CASE 1: Total width is TOO SMALL - Expand last column **
        double difference = containerWidth - currentTotalWidth;
        double lastColTargetWidth =
            (isResizingLastColumn ? newWidth : lastColCurrentWidth) +
            difference;

        // Ensure the last column doesn't shrink below minimum (shouldn't happen here, but safe)
        tentativeWidths[lastVisibleColumnName] = math.max(
          _minColWidth,
          lastColTargetWidth,
        );
        print(
          "Expanding last column '$lastVisibleColumnName' width to ${tentativeWidths[lastVisibleColumnName]}",
        );
      } else if (currentTotalWidth > containerWidth) {
        // ** CASE 2: Total width is TOO BIG - Shrink last column (if possible) **
        double excessWidth = currentTotalWidth - containerWidth;

        // Only shrink if the last column isn't the one being actively resized *larger*
        // Or if the last column is being resized smaller anyway
        if (!isResizingLastColumn ||
            (isResizingLastColumn && newWidth < lastColCurrentWidth)) {
          // Calculate the width the last column *would* have if we remove the excess
          double potentialNewLastColWidth =
              (isResizingLastColumn ? newWidth : lastColCurrentWidth) -
              excessWidth;

          // Apply the shrink, but respect the minimum last column shrink width
          double newLastColWidth = math.max(
            _minLastColShrinkWidth,
            potentialNewLastColWidth,
          );

          // Only apply if this new width is actually smaller than its current tentative width
          if (newLastColWidth <
              (tentativeWidths[lastVisibleColumnName] ?? _minColWidth)) {
            tentativeWidths[lastVisibleColumnName] = newLastColWidth;
            print(
              "Shrinking last column '$lastVisibleColumnName' width to ${tentativeWidths[lastVisibleColumnName]} to fit container",
            );
          } else {
            print(
              "Cannot shrink last column '$lastVisibleColumnName' further (Minimum: $_minLastColShrinkWidth, Current: ${tentativeWidths[lastVisibleColumnName]})",
            );
          }
        } else {
          print(
            "Skipping shrink for last column '$lastVisibleColumnName' as it was resized larger.",
          );
        }
      }
      // ** CASE 3: Total width is EXACTLY container width - No adjustment needed **
      else {
        print("Total width matches container width. No adjustment needed.");
      }
    }

    // Apply the final widths (potentially adjusted) to the state
    setState(() {
      _columnWidths = tentativeWidths;
      _freezeLayoutAndRebuildColumns(resizedColumnName);
    });

    _saveColumnConfiguration();
  }

  // Update the existing onColumnResizeUpdate in SfDataGrid to call the new handler:
  // Inside SfDataGrid properties:
  // onColumnResizeUpdate: (ColumnResizeUpdateDetails details) {
  //   _handleColumnResize(details, _containerWidth); // Pass container width
  //   return true; // Indicate resize was handled
  // },

  // Modify _freezeLayoutAndRebuildColumns if needed (or ensure it uses _columnWidths)
  void _freezeLayoutAndRebuildColumns(String resizedColumnName) {
    // This method should ideally just rebuild the _gridColumns list
    // based on the current state (_columnWidths, _columnOrder, _visibleColumns)
    // No need to set _isLayoutFrozen here repeatedly, maybe set it once after initial load/first resize
    if (!mounted) return;
    _buildGridColumnsFromState(); // Rebuild columns using the updated widths
  }

  // This method is public and can be called from HomeScreen
  void toggleColumnVisibilityAndUpdate(String columnName) {
    if (_isLoadingConfig) {
      print(
        "TrackTableWidget: Config still loading, cannot toggle column visibility yet.",
      );
      return;
    }

    setState(() {
      if (_visibleColumns.contains(columnName)) {
        _visibleColumns.remove(columnName);
        print(
          "TrackTableWidget: Hiding column $columnName. Visible: $_visibleColumns",
        );
      } else {
        _visibleColumns.add(columnName);
        print(
          "TrackTableWidget: Showing column $columnName. Visible: $_visibleColumns",
        );
      }

      // Rebuild _columnOrder to only include visible columns, maintaining original relative order
      // and adding newly visible columns according to _defaultColumnConfig order.
      List<String> newOrder =
          _defaultColumnConfig.keys
              .where((key) => _visibleColumns.contains(key))
              .toList();

      // Sort newOrder based on the original _columnOrder for existing visible columns
      // This preserves the user's preferred order for columns that remain visible.
      newOrder.sort((a, b) {
        int indexA = _columnOrder.indexOf(a);
        int indexB = _columnOrder.indexOf(b);
        if (indexA != -1 && indexB != -1) return indexA.compareTo(indexB);
        if (indexA != -1) return -1; // a was in old order, b was not
        if (indexB != -1) return 1; // b was in old order, a was not
        // If neither were in the old order, maintain default config order (already handled by initial creation of newOrder)
        return 0;
      });
      _columnOrder = newOrder;
      print("TrackTableWidget: Updated column order: $_columnOrder");
    });

    _saveColumnConfiguration();
    _buildGridColumnsFromState();
  }

  @override
  Widget build(BuildContext context) {
    // Show loading indicator while config is loading
    if (_isLoadingConfig) {
      return const Center(child: CircularProgressIndicator());
    }
    // Ensure columns are built before rendering the grid
    if (!_isColumnsInitialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isColumnsInitialized) {
          _buildGridColumnsFromState(); // Try building columns again after frame
          setState(() => _isColumnsInitialized = true);
        }
      });
      return const Center(
        child: Text("Initializing columns..."),
      ); // Or another placeholder
    }

    final colorScheme = Theme.of(context).colorScheme;

    return Focus(
      focusNode: _focusNode,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Store the container width
          _containerWidth = constraints.maxWidth;

          return SfDataGridTheme(
            data: SfDataGridThemeData(
              selectionColor: colorScheme.primary.withOpacity(0.2),
              headerColor: colorScheme.surfaceVariant.withOpacity(0.5),
              headerHoverColor: colorScheme.primary.withOpacity(0.1),
            ),
            child: SfDataGrid(
              key: _sfDataGridKey,
              source: _trackDataSource,
              selectionMode: SelectionMode.multiple,
              gridLinesVisibility: GridLinesVisibility.horizontal,
              headerGridLinesVisibility: GridLinesVisibility.both,
              headerRowHeight: 30,
              rowHeight: 40,
              allowColumnsResizing: true,
              allowColumnsDragging: true,
              // --- Column Dragging Handler ---
              onColumnDragging: (DataGridColumnDragDetails details) {
                if (details.action == DataGridColumnDragAction.dropping) {
                  setState(() {
                    final int fromIndex = details.from;
                    final int toIndex = details.to!;

                    // Find the actual column objects based on the visible columns in _gridColumns
                    if (fromIndex >= 0 &&
                        fromIndex < _gridColumns.length &&
                        toIndex >= 0 &&
                        toIndex < _gridColumns.length &&
                        fromIndex != toIndex) {
                      final GridColumn draggedColumn = _gridColumns.removeAt(
                        fromIndex,
                      );
                      _gridColumns.insert(toIndex, draggedColumn);

                      // Update the internal _columnOrder state based on the new _gridColumns order
                      _columnOrder =
                          _gridColumns.map((c) => c.columnName).toList();

                      // Update the DataSource with the new order
                      _trackDataSource.updateColumnOrder(_columnOrder);
                      print("Column order updated: $_columnOrder");

                      // Save the new configuration
                      _saveColumnConfiguration();
                      widget.onColumnConfigChanged?.call();
                    } else {
                      print(
                        "Column drag index out of bounds or invalid: from $fromIndex, to $toIndex",
                      );
                    }
                  });
                }
                return true; // Indicate drag was handled
              },
              columnResizeMode: ColumnResizeMode.onResize,
              onColumnResizeUpdate: (ColumnResizeUpdateDetails details) {
                // Pass container width to the handler
                _handleColumnResize(details, _containerWidth);
                return true; // Indicate resize was handled
              },
              // onCellDoubleTap: (DataGridCellDoubleTapDetails details) {
              //   final int rowIndex = details.rowColumnIndex.rowIndex;
              //   // Ensure it's a data row (not header)
              //   if (rowIndex > 0 && rowIndex <= _trackDataSource.rows.length) {
              //     final dataRow = _trackDataSource.rows[rowIndex - 1];
              //     final idCell = dataRow.getCells().firstWhere(
              //       (cell) => cell.columnName == 'id',
              //       orElse:
              //           () => DataGridCell<int>(columnName: 'id', value: -1),
              //     );
              //     final int trackId = idCell.value as int? ?? -1;

              //     if (trackId != -1) {
              //       try {
              //         // Find the track corresponding to the double-tapped row
              //         final track = widget.tracks.firstWhere(
              //           (t) => t.id == trackId,
              //         );
              //         // Call the callback passed from HomeScreen
              //         widget.onRowDoubleTap(track);
              //         print(
              //           "Double tapped on track: ${track.title}",
              //         ); // Optional log
              //       } catch (e) {
              //         debugPrint("Error finding track for double tap: $e");
              //       }
              //     }
              //   }
              // },
              allowSorting: true,
              onCellTap: (DataGridCellTapDetails details) {
                final int rowIndex = details.rowColumnIndex.rowIndex;
                final int columnIndex = details.rowColumnIndex.columnIndex;
                final bool isDataRow = rowIndex > 0;
                // final bool isEditing = _editingCellKey != null; // Keep editing logic if needed

                print("Cell Tapped: Row $rowIndex, Col $columnIndex"); // Debug

                if (!isDataRow ||
                    columnIndex < 0 ||
                    columnIndex >= _gridColumns.length) {
                  // Handle header/invalid clicks, finish editing if necessary
                  // ... (existing logic for finishing edit on outside click) ...
                  if (_editingCellKey != null) {
                    print(
                      "Clicked header/invalid column while editing. Finishing edit.",
                    );
                    _handleEndEditing(newValue: _cellEditController.text);
                  }
                  // Clear tap tracking if clicking outside data rows
                  _lastTapTime = null;
                  _lastTappedTrackId = null;
                  return;
                }

                // --- Get Track ID ---
                final dataRow =
                    _trackDataSource.rows[rowIndex -
                        1]; // Adjust for header row
                final idCell = dataRow.getCells().firstWhere(
                  (cell) => cell.columnName == 'id',
                  orElse: () => DataGridCell<int>(columnName: 'id', value: -1),
                );
                final int currentTrackId = idCell.value as int? ?? -1;

                if (currentTrackId == -1) return; // Invalid track ID

                // --- Custom Double-Click Logic ---
                final DateTime now = DateTime.now();
                bool isDoubleClick = false;

                if (_lastTapTime != null &&
                    _lastTappedTrackId == currentTrackId &&
                    now.difference(_lastTapTime!) < _doubleClickThreshold) {
                  // --- Double Click Detected ---
                  isDoubleClick = true;
                  print("Double Click Detected on Track ID: $currentTrackId");

                  // Find the track and trigger the double-click callback
                  try {
                    final track = widget.tracks.firstWhere(
                      (t) => t.id == currentTrackId,
                    );
                    widget.onRowDoubleTap(track); // Call the load/play callback
                  } catch (e) {
                    debugPrint("Error finding track for double tap: $e");
                  }

                  // Reset tap tracking after a double-click
                  _lastTapTime = null;
                  _lastTappedTrackId = null;
                } else {
                  // --- Single Click ---
                  // Update last tap info for potential next click
                  _lastTapTime = now;
                  _lastTappedTrackId = currentTrackId;
                }
                // --- End Custom Double-Click Logic ---

                // --- IMPORTANT: Always handle selection immediately on the first tap ---
                // The selection logic relies on the SfDataGrid's internal mechanism
                // triggered by the tap, which then calls onSelectionChanged.
                // We don't need to explicitly call widget.onSelectionChanged here.
                // The selection highlight should appear instantly via the grid's default behavior.

                // --- Handle Cell Editing (if applicable, after double-click check) ---
                if (!isDoubleClick) {
                  // --- Get details of the tapped cell ---
                  final String tappedColumnName =
                      _gridColumns[columnIndex].columnName;
                  final List<String> editableColumns = [
                    'title', 'artist', 'album',
                    'albumArtist',
                    'composer',
                    'genre',
                    'year',
                    'bpm', // Added new editable fields
                  ];
                  final bool isTappedCellEditable = editableColumns.contains(
                    tappedColumnName,
                  );
                  final String tappedCellKey =
                      "${currentTrackId}_$tappedColumnName";
                  final bool isEditing =
                      _editingCellKey != null; // Check editing state *now*

                  // --- Cell Editing Logic (mostly unchanged from before) ---
                  if (isEditing && _editingCellKey == tappedCellKey) {
                    // Tapped inside the currently editing cell
                    return;
                  }
                  if (isEditing && _editingCellKey != tappedCellKey) {
                    // Tapped different cell while editing, finish previous
                    _handleEndEditing(newValue: _cellEditController.text);
                    // Reset tap tracking because the action was finishing an edit
                    _lastTapTime = null;
                    _lastTappedTrackId = null;
                    return;
                  }
                  if (!isEditing) {
                    if (_isRowSelected(rowIndex) && isTappedCellEditable) {
                      // Start editing
                      print("Starting edit for $tappedCellKey");
                      try {
                        final track = widget.tracks.firstWhere(
                          (t) => t.id == currentTrackId,
                        );
                        final currentValue = _getTrackValueByColumn(
                          track,
                          tappedColumnName,
                        );
                        _cellEditController.text = currentValue;
                        setState(() {
                          _editingCellKey = tappedCellKey;
                        });
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          // ... (focus and selection logic) ...
                          Future.delayed(const Duration(milliseconds: 50), () {
                            if (mounted) {
                              print("Requesting focus and selection NOW");
                              FocusScope.of(
                                context,
                              ).requestFocus(_cellEditFocusNode);
                              _cellEditController.selection = TextSelection(
                                baseOffset: 0,
                                extentOffset: _cellEditController.text.length,
                              );
                            }
                          });
                        });
                      } catch (e) {
                        print("Error finding track to edit: $e");
                        _handleEndEditing();
                      }
                    } else {
                      print(
                        "Tap conditions not met for starting edit (Row Selected: ${_isRowSelected(rowIndex)}, Cell Editable: $isTappedCellEditable, Track ID: $currentTrackId).",
                      );
                      // No edit action needed for single click here. Selection handled by grid.
                    }
                  }
                  // --- End Cell Editing Logic ---
                }
              }, // End onCellTap

              onColumnSortChanged: (
                SortColumnDetails? newSortColumn,
                SortColumnDetails? oldSortColumn,
              ) {
                if (newSortColumn != null) {
                  widget.onSort(
                    newSortColumn.name,
                    newSortColumn.sortDirection,
                  );
                } else {
                  // Default sort if sorting is cleared (optional)
                  widget.onSort('title', DataGridSortDirection.ascending);
                }
              },
              navigationMode: GridNavigationMode.row,
              onSelectionChanged: _handleGridSelectionChange,
              controller: _dataGridController,
              columns: _gridColumns, // Use the dynamically built columns

              onCellSecondaryTap: (DataGridCellTapDetails details) {
                int rowIndex = details.rowColumnIndex.rowIndex;
                if (rowIndex > 0 && rowIndex <= _trackDataSource.rows.length) {
                  final dataRow = _trackDataSource.rows[rowIndex - 1];
                  final idCell = dataRow.getCells().firstWhere(
                    (cell) => cell.columnName == 'id',
                    orElse:
                        () => DataGridCell<int>(columnName: 'id', value: -1),
                  );
                  final int trackId = idCell.value as int? ?? -1;
                  if (trackId != -1) {
                    try {
                      final track = widget.tracks.firstWhere(
                        (t) => t.id == trackId,
                      );
                      widget.onShowContextMenu(
                        context,
                        details.globalPosition,
                        track,
                      );
                    } catch (e) {
                      debugPrint("Error finding track for context menu: $e");
                    }
                  }
                }
              },
            ),
          );
        },
      ),
    );
  }
}
