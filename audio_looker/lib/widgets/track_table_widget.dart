// lib/widgets/track_table_widget.dart

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'dart:math';
import 'package:collection/collection.dart';
import 'package:flutter_bloc/flutter_bloc.dart'; // Import BlocProvider

import 'package:waux/blocs/audio_player/audio_player_bloc.dart';
import 'package:waux/services/collection_service.dart'; // Track model and CollectionService
import 'package:waux/widgets/track_data_source.dart';

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
  }) : super(key: key);

  @override
  _TrackTableWidgetState createState() => _TrackTableWidgetState();
}

class _TrackTableWidgetState extends State<TrackTableWidget> {
  final GlobalKey<SfDataGridState> _sfDataGridKey =
      GlobalKey<SfDataGridState>();
  final FocusNode _focusNode = FocusNode();
  late TrackDataSource _trackDataSource;
  late DataGridController _dataGridController;

  late List<GridColumn> _gridColumns = []; // Initialize empty
  bool _isColumnsInitialized = false;
  bool _isLayoutFrozen = false;
  bool _isLoadingConfig = true; // State to track config loading

  // Map storing current width for each column name
  Map<String, double> _columnWidths = {};
  // List storing the current order of visible column names
  List<String> _columnOrder = [];
  // Set storing the names of columns that are currently visible
  Set<String> _visibleColumns = {};

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
      'allowSorting': false,
      'isNumeric': false,
    },
    'duration': {
      'width': 80.0, // Adjust width as needed
      'visible': true, // Make it visible by default
      'label': 'Duration',
      'allowSorting': true, // Allow sorting by duration
      'isNumeric': true, // Important for sorting
    },
    'source': {
      'width': 60.0,
      'visible': true,
      'label': 'Source',
      'allowSorting': false,
      'isNumeric': false,
    },
    // Add other potential columns like 'duration' if needed
  };

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
    );

    // Initialize Controller
    _dataGridController = DataGridController();

    // Load configuration asynchronously
    _loadConfigFromService();

    // Focus logic
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusScope.of(context).requestFocus(_focusNode);
        _updateControllerSelection();
      }
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

  // Ensures all required columns have settings and order is consistent
  void _ensureDefaultConfigApplied() {
    // Ensure all default columns have at least a default width if not saved
    for (var key in _defaultColumnConfig.keys) {
      _columnWidths.putIfAbsent(
        key,
        () => (_defaultColumnConfig[key]['width'] as num).toDouble(),
      );
    }
    // Ensure all default visible columns are in the visible set if not saved
    for (var key in _defaultColumnConfig.keys) {
      if (_defaultColumnConfig[key]['visible'] as bool) {
        _visibleColumns.add(key);
      }
    }
    // Ensure order contains all visible columns, add missing ones at the end
    final currentVisibleSet = Set<String>.from(_visibleColumns);
    // Filter _columnOrder to only contain currently visible columns, preserving their order
    List<String> finalOrder =
        _columnOrder.where((c) => currentVisibleSet.contains(c)).toList();
    // Add any visible columns that were missing from the saved order to the end
    for (var col in currentVisibleSet) {
      if (!finalOrder.contains(col)) {
        finalOrder.add(col);
      }
    }
    _columnOrder = finalOrder;

    // Ensure _visibleColumns only contains columns that actually exist in defaults
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
    if (!mounted) return; // Ensure widget is mounted

    final textTheme = Theme.of(context).textTheme;

    // Ensure order reflects visibility changes
    List<String> currentVisibleOrder =
        _columnOrder.where((name) => _visibleColumns.contains(name)).toList();
    for (var visibleCol in _visibleColumns) {
      if (!currentVisibleOrder.contains(visibleCol)) {
        currentVisibleOrder.add(visibleCol);
      }
    }
    _columnOrder = currentVisibleOrder; // Update the state variable

    final List<GridColumn> newColumns = [];

    // Add visible columns based on the current order and visibility
    for (final columnName in _columnOrder) {
      if (_defaultColumnConfig.containsKey(columnName)) {
        final config = _defaultColumnConfig[columnName];
        final width =
            _columnWidths[columnName] ?? (config['width'] as num).toDouble();
        // Use 'none' mode after initial load/resize for stability
        final widthMode =
            _isLayoutFrozen
                ? ColumnWidthMode.none
                : ColumnWidthMode.auto; // Or adjust logic

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
            overflow: TextOverflow.ellipsis, // Add this line
            maxLines:
                1, // Add this line (optional, but good practice with ellipsis)
            // softWrap: false, // Alternative to maxLines: 1 if needed
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
            visible: true, // Columns added here are implicitly visible
          ),
        );
      }
    }

    // Update the state to apply the new column list
    if (mounted) {
      setState(() {
        _gridColumns = newColumns;
      });
    } else {
      _gridColumns = newColumns;
    }
  }

  // Updates the SfDataGrid controller's selection based on widget.selectedTrackIds
  void _updateControllerSelection() {
    if (_isLoadingConfig || !_isColumnsInitialized)
      return; // Don't update if loading/not ready
    try {
      _dataGridController.selectedRows =
          _trackDataSource.rows.where((row) {
            final idCell = row.getCells().firstWhere(
              (c) =>
                  c.columnName ==
                  'id', // Assumes 'id' cell exists even if not visible column
              orElse: () => DataGridCell<int>(columnName: 'id', value: -1),
            );
            return idCell.value != null &&
                widget.selectedTrackIds.contains(idCell.value as int);
          }).toList();
      _dataGridController.selectedRow =
          _dataGridController.selectedRows.firstOrNull;
    } catch (e) {
      debugPrint(
        "Error updating controller selection (might be temporary): $e",
      );
    }
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
      );
      // After recreating, we might need to re-apply selection
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateControllerSelection();
      });
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
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
    // --- END MODIFICATION ---

    if (mounted && (addedRows.isNotEmpty || removedRows.isNotEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) FocusScope.of(context).requestFocus(_focusNode);
      });
    }
  }

  // Freezes layout after first resize and rebuilds columns
  void _freezeLayoutAndRebuildColumns(String resizedColumnName) {
    if (!_isLayoutFrozen) {
      _isLayoutFrozen = true;
    }
    _buildGridColumnsFromState(); // Rebuild columns using the updated widths
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
      child: SfDataGridTheme(
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
                  _columnOrder = _gridColumns.map((c) => c.columnName).toList();

                  // Update the DataSource with the new order
                  _trackDataSource.updateColumnOrder(_columnOrder);
                  print("Column order updated: $_columnOrder");

                  // Save the new configuration
                  _saveColumnConfiguration();
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
          // --- Column Resizing Handler ---
          onColumnResizeUpdate: (ColumnResizeUpdateDetails details) {
            final columnName = details.column.columnName;
            // Ensure minimum width
            double newWidth = max(50.0, details.width);

            // Update the width in the state map
            setState(() {
              _columnWidths[columnName] = newWidth;
              // Rebuild columns to apply the new width and freeze layout
              _freezeLayoutAndRebuildColumns(columnName);
            });
            // Save the configuration after resize
            _saveColumnConfiguration();
            return true; // Indicate resize was handled
          },
          allowSorting: true,
          // --- Sorting Handler ---
          onColumnSortChanged: (
            SortColumnDetails? newSortColumn,
            SortColumnDetails? oldSortColumn,
          ) {
            if (newSortColumn != null) {
              widget.onSort(newSortColumn.name, newSortColumn.sortDirection);
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
                orElse: () => DataGridCell<int>(columnName: 'id', value: -1),
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
      ),
    );
  }
}
