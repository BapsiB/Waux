// lib/widgets/track_table_widget.dart

import 'package:flutter/gestures.dart'; // Required for PointerHoverEvent (though callback removed)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:syncfusion_flutter_core/theme.dart'; // Optional for theming
import 'dart:math'; // Required for max function
import 'package:collection/collection.dart'; // Import for deep equality check

import 'package:audio_looker/blocs/audio_player/audio_player_bloc.dart'; // Import Bloc
import 'package:audio_looker/services/collection_service.dart'; // Your Track model
import 'package:audio_looker/widgets/track_data_source.dart'; // The DataSource

// Callback types for cleaner signatures
typedef SelectionChangeCallback =
    void Function(
      int trackId,
      bool isSelected, {
      bool isShiftPressed,
      bool isCtrlPressed,
    });
typedef ContextMenuCallback =
    void Function(BuildContext context, Offset tapPosition, Track track);
// typedef PlayPreviewCallback = void Function(Track track); // Removed
typedef RatingChangeCallback = void Function(int trackId, int newRating);
typedef SortCallback =
    void Function(String columnName, DataGridSortDirection direction);
// --- Add missing callbacks from constructor usage ---
typedef PlayAndMinimizeCallback = void Function(Track track, bool togglePlay);
typedef SelectAndOpenPlayerCallback = void Function(Track track);
// --- End missing callbacks ---

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
  final PlayAndMinimizeCallback
  onPlayPreviewAndMinimize; // <<< Added based on usage in DataSource
  final SelectAndOpenPlayerCallback onEditMetadata;

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
    required this.onPlayPreviewAndMinimize, // <<< Added
    required this.onEditMetadata, // <<< Added
  }) : super(key: key);

  @override
  _TrackTableWidgetState createState() => _TrackTableWidgetState();
}

class _TrackTableWidgetState extends State<TrackTableWidget> {
  final GlobalKey<SfDataGridState> _sfDataGridKey =
      GlobalKey<SfDataGridState>();
  final FocusNode _focusNode = FocusNode();
  late TrackDataSource _trackDataSource; // Store the data source instance
  late DataGridController _dataGridController; // Store the controller instance

  late List<GridColumn> _gridColumns;
  bool _isColumnsInitialized = false;
  bool _isLayoutFrozen = false;

  final double _initialPreviewWidth = 250;
  final double _initialRatingWidth = 100;
  final double _defaultTextColumnWidth = 150;

  // --- ADDED: State for full configuration ---
  // Map storing current width for each column name
  Map<String, double> _columnWidths = {};
  // List storing the current order of visible column names
  List<String> _columnOrder = [];
  // Set storing the names of columns that are currently visible
  Set<String> _visibleColumns = {};

  final double _initialSourceWidth = 60;

  // Define the full set of possible columns and their default states
  // This helps in initializing and managing visibility toggles.
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
    }, // Assuming rating is sortable
    'tags': {
      'width': 150.0,
      'visible': true,
      'label': 'Tags',
      'allowSorting': false,
      'isNumeric': false,
    },
    'source': {
      'width': 60.0,
      'visible': true,
      'label': 'Source',
      'allowSorting': false,
      'isNumeric': false,
    }, // Header could be icon
    // Add other potential columns here if needed (e.g., genre, year, duration)
    // 'duration': {'width': 80.0, 'visible': false, 'label': 'Duration', 'allowSorting': true, 'isNumeric': true},
  };

  @override
  void initState() {
    super.initState();

    // Load configuration data (DOES NOT use context)
    Map<String, dynamic> savedConfig = _loadPlaceholderConfig();
    _columnWidths = Map<String, double>.from(savedConfig['widths'] ?? {});
    _columnOrder = List<String>.from(
      savedConfig['order'] ?? _defaultColumnConfig.keys.toList(),
    );
    _visibleColumns = Set<String>.from(
      savedConfig['visible'] ??
          _defaultColumnConfig.keys.where(
            (k) => _defaultColumnConfig[k]['visible'],
          ),
    );
    _ensureDefaultConfigApplied(); // Applies defaults and ensures _columnOrder is correct

    // Initialize DataSource here, passing the initial order
    _trackDataSource = TrackDataSource(
      trackData: widget.tracks,
      audioPlayerBloc: widget.audioPlayerBloc,
      onRatingChanged: widget.onRatingChanged,
      onPlayPreviewAndMinimize: widget.onPlayPreviewAndMinimize,
      onEditMetadata: widget.onEditMetadata,
      initialColumnOrder: _columnOrder, // <<< PASS INITIAL ORDER HERE
    );

    // Initialize Controller here
    _dataGridController = DataGridController();

    // Focus logic
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusScope.of(context).requestFocus(_focusNode);
        _updateControllerSelection();
      }
    });
  }

  void _ensureDefaultConfigApplied() {
    // Ensure all default columns have at least a default width if not saved
    for (var key in _defaultColumnConfig.keys) {
      _columnWidths.putIfAbsent(key, () => _defaultColumnConfig[key]['width']);
    }
    // Ensure all default visible columns are in the visible set if not saved
    for (var key in _defaultColumnConfig.keys) {
      if (_defaultColumnConfig[key]['visible']) {
        _visibleColumns.add(key);
      }
    }
    // Ensure order contains all visible columns, add missing ones at the end
    final currentVisibleSet = Set<String>.from(_visibleColumns);
    final orderedVisibleSet = Set<String>.from(
      _columnOrder.where((c) => currentVisibleSet.contains(c)),
    );
    List<String> finalOrder =
        _columnOrder.where((c) => currentVisibleSet.contains(c)).toList();
    for (var col in currentVisibleSet) {
      if (!orderedVisibleSet.contains(col)) {
        finalOrder.add(col);
      }
    }
    _columnOrder = finalOrder;
  }

  Map<String, dynamic> _loadPlaceholderConfig() {
    // In a real app, load from SharedPreferences, a file, or database
    print("Loading placeholder column config");
    // Return default structure for now
    return {
      'widths': {
        for (var k in _defaultColumnConfig.keys)
          k: _defaultColumnConfig[k]['width'],
      },
      'order': _defaultColumnConfig.keys.toList(),
      'visible':
          _defaultColumnConfig.keys
              .where((k) => _defaultColumnConfig[k]['visible'])
              .toSet(),
    };
  }

  void _saveColumnConfiguration() {
    // Prepare the config object from the current state
    final configToSave = {
      'widths': _columnWidths,
      'order':
          _gridColumns
              .where((c) => c.columnName != 'id')
              .map((c) => c.columnName)
              .toList(), // Get order from current _gridColumns
      'visible': _visibleColumns,
    };

    print("Saving column config: $configToSave");
    // TODO: Replace with actual saving logic using CollectionService/Persistence
    // Example: await collectionService.saveColumnConfig(configToSave);
  }

  void _showColumnVisibilityDialog() {
    // Keep track of changes made within the dialog
    Set<String> originalVisibleColumns = Set<String>.from(_visibleColumns);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        // Dialog builder context
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // StatefulBuilder context + state setter
            return AlertDialog(
              title: const Text('Show/Hide Columns'),
              content: SizedBox(
                width: 250, // Adjust width as needed
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _defaultColumnConfig.length,
                  itemBuilder: (context, index) {
                    // ListView builder context
                    final columnName = _defaultColumnConfig.keys.elementAt(
                      index,
                    );
                    final config = _defaultColumnConfig[columnName];

                    return CheckboxListTile(
                      title: Text(config['label']),
                      value: _visibleColumns.contains(columnName),
                      onChanged: (bool? newValue) {
                        if (newValue != null) {
                          setDialogState(() {
                            // Use the dialog's state setter
                            if (newValue) {
                              _visibleColumns.add(columnName);
                            } else {
                              _visibleColumns.remove(columnName);
                            }
                          });
                          // Update the main widget state immediately to rebuild columns
                          // This also recalculates _columnOrder based on visibility
                          _buildGridColumnsFromState(); // Rebuilds _gridColumns and updates _columnOrder internally if needed
                        }
                      },
                    );
                  }, // End itemBuilder
                ), // End ListView.builder
              ), // End SizedBox
              actions: <Widget>[
                TextButton(
                  child: const Text('Done'),
                  onPressed: () {
                    Navigator.of(
                      context,
                    ).pop(); // Use the dialog's context to pop
                    // Saving moved to .then()
                  },
                ),
              ],
            ); // End AlertDialog
          }, // End StatefulBuilder builder
        ); // End StatefulBuilder
      }, // End showDialog builder
    ).then((_) {
      // .then callback after dialog closes
      // This runs AFTER the dialog is closed
      // Check if visibility actually changed before updating datasource and saving
      if (!const SetEquality().equals(
        originalVisibleColumns,
        _visibleColumns,
      )) {
        print("Column visibility changed, updating DataSource order.");
        // Ensure _columnOrder reflects the final visible set and their order
        _columnOrder =
            _gridColumns
                .where((c) => c.columnName != 'id')
                .map((c) => c.columnName)
                .toList();
        // *** Update DataSource AFTER dialog is closed and state is finalized ***
        _trackDataSource.updateColumnOrder(_columnOrder);
        _saveColumnConfiguration(); // Save only if changes were made
      }
    }); // End .then()
  } // End _showColumnVisibilityDialog

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Build the initial columns list here, as it depends on Theme.of(context)
    // Use the flag to prevent rebuilding unnecessarily on every dependency change
    if (!_isColumnsInitialized) {
      _buildGridColumnsFromState(); // Now safe to call here
      _isColumnsInitialized = true;
    }
  }

  void _buildGridColumnsFromState() {
    // This method uses Theme.of(context), so it must NOT be called before didChangeDependencies
    // Ensure context is available before accessing Theme
    if (!mounted) return; // Add a check if called potentially when not mounted

    final textTheme = Theme.of(context).textTheme;

    // Create the final ordered list of column names based on visibility
    // This ensures columns added/removed via the dialog are ordered correctly
    List<String> currentVisibleOrder =
        _columnOrder.where((name) => _visibleColumns.contains(name)).toList();
    // Add any newly visible columns that weren't in the previous order (append at the end)
    for (var visibleCol in _visibleColumns) {
      if (!currentVisibleOrder.contains(visibleCol)) {
        currentVisibleOrder.add(visibleCol);
      }
    }
    // Update the main state variable for order
    _columnOrder = currentVisibleOrder;

    final List<GridColumn> newColumns = [];

    // Add the hidden 'id' column first (important for datasource lookups)
    // newColumns.add(
    //   GridColumn(
    //     columnName: 'id',
    //     label: SizedBox.shrink(),
    //     width: 0,
    //     visible: false, // This column is never visible to the user
    //   ),
    // );

    // Add visible columns based on the current order and visibility
    for (final columnName in _columnOrder) {
      // Iterate using the UPDATED _columnOrder
      // We already filtered _columnOrder, but double-check existence in defaults
      if (_defaultColumnConfig.containsKey(columnName)) {
        final config = _defaultColumnConfig[columnName];
        final width = _columnWidths[columnName] ?? config['width'];
        // Default to 'none' mode after initial load/resize for stability
        final widthMode = ColumnWidthMode.none;

        // Build header label (special case for 'source')
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
          headerLabel = Text(config['label'], style: textTheme.titleSmall);
        }

        newColumns.add(
          GridColumn(
            columnName: columnName,
            width: width,
            columnWidthMode: widthMode,
            allowSorting:
                config['allowSorting'] ??
                true, // Default allowSorting to true if not specified
            label: Container(
              alignment: headerAlignment,
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: headerLabel,
            ),
            // 'visible' property for GridColumn itself should be true for columns added here.
            // SfDataGrid determines visibility based on *which columns are included* in this list.
            visible: true,
          ),
        );
      }
    }

    // Update the state to apply the new column list
    // Check if mounted because this might be called during interactions
    if (mounted) {
      setState(() {
        _gridColumns = newColumns;
      });
    } else {
      // Avoid calling setState if not mounted (e.g., during dispose)
      _gridColumns = newColumns;
    }
  }

  // Helper method to update controller selection based on widget state
  void _updateControllerSelection() {
    // Use a try-catch block as rows might be temporarily unavailable during updates
    try {
      _dataGridController.selectedRows =
          _trackDataSource.rows.where((row) {
            final idCell = row.getCells().firstWhere(
              (c) => c.columnName == 'id',
              orElse: () => DataGridCell<int>(columnName: 'id', value: -1),
            );
            // Ensure value is not null before checking contains
            return idCell.value != null &&
                widget.selectedTrackIds.contains(idCell.value as int);
          }).toList();
      _dataGridController.selectedRow =
          _dataGridController.selectedRows.firstOrNull;
    } catch (e) {
      debugPrint(
        "Error updating controller selection (might be temporary): $e",
      );
      // Optionally clear selection if rows are unavailable
      // _dataGridController.selectedRows = [];
    }
  }

  // initializeColumns remains the same
  // void _initializeColumns({required bool useFill}) {
  //   final textTheme = Theme.of(context).textTheme;
  //   final flexibleMode = useFill ? ColumnWidthMode.fill : ColumnWidthMode.none;
  //   final flexibleWidth = useFill ? double.nan : _defaultTextColumnWidth;

  //   _gridColumns = <GridColumn>[
  //     GridColumn(
  //       columnName: 'id',
  //       label: SizedBox.shrink(),
  //       width: 0,
  //       visible: false,
  //     ),
  //     GridColumn(
  //       columnName: 'preview',
  //       width: _initialPreviewWidth,
  //       columnWidthMode: ColumnWidthMode.none,
  //       allowSorting: false,
  //       label: Container(
  //         alignment: Alignment.centerLeft,
  //         padding: const EdgeInsets.symmetric(horizontal: 8.0),
  //         child: Text('Preview', style: textTheme.titleSmall),
  //       ),
  //     ),
  //     GridColumn(
  //       columnName: 'title',
  //       width: flexibleWidth,
  //       columnWidthMode: flexibleMode,
  //       label: Container(
  //         alignment: Alignment.centerLeft,
  //         padding: const EdgeInsets.symmetric(horizontal: 8.0),
  //         child: Text('Title', style: textTheme.titleSmall),
  //       ),
  //     ),
  //     GridColumn(
  //       columnName: 'artist',
  //       width: flexibleWidth,
  //       columnWidthMode: flexibleMode,
  //       label: Container(
  //         alignment: Alignment.centerLeft,
  //         padding: const EdgeInsets.symmetric(horizontal: 8.0),
  //         child: Text('Artist', style: textTheme.titleSmall),
  //       ),
  //     ),
  //     GridColumn(
  //       columnName: 'album',
  //       width: flexibleWidth,
  //       columnWidthMode: flexibleMode,
  //       label: Container(
  //         alignment: Alignment.centerLeft,
  //         padding: const EdgeInsets.symmetric(horizontal: 8.0),
  //         child: Text('Album', style: textTheme.titleSmall),
  //       ),
  //     ),
  //     GridColumn(
  //       columnName: 'rating',
  //       width: _initialRatingWidth,
  //       columnWidthMode: ColumnWidthMode.none,
  //       label: Container(
  //         alignment: Alignment.centerLeft,
  //         padding: const EdgeInsets.symmetric(horizontal: 8.0),
  //         child: Text('Rating', style: textTheme.titleSmall),
  //       ),
  //     ),
  //     GridColumn(
  //       columnName: 'tags',
  //       width: flexibleWidth,
  //       columnWidthMode: flexibleMode,
  //       allowSorting: false,
  //       label: Container(
  //         alignment: Alignment.centerLeft,
  //         padding: const EdgeInsets.symmetric(horizontal: 8.0),
  //         child: Text('Tags', style: textTheme.titleSmall),
  //       ),
  //     ),
  //     GridColumn(
  //       columnName: 'source',
  //       width: 60, // Adjust width as needed
  //       columnWidthMode: ColumnWidthMode.none,
  //       allowSorting: false, // Sorting by icon might not be useful
  //       label: Container(
  //         alignment: Alignment.center, // Center the label/icon
  //         padding: const EdgeInsets.symmetric(horizontal: 8.0),
  //         child: Tooltip(
  //           // Add tooltip for clarity
  //           message: 'Source Type',
  //           child: Icon(
  //             Icons.link,
  //             size: 16,
  //             color: textTheme.titleSmall?.color,
  //           ), // Generic icon for header
  //         ),
  //         // child: Text('Src', style: textTheme.titleSmall), // Alternative: Text label
  //       ),
  //     ),
  //   ];
  // }

  @override
  void didUpdateWidget(TrackTableWidget oldWidget) {
    bool dataSourceUpdated = false;
    // Update the data source if the tracks list changes
    if (!const ListEquality().equals(widget.tracks, oldWidget.tracks)) {
      // Deep comparison
      _trackDataSource.updateDataGridSource(trackData: widget.tracks);
      dataSourceUpdated = true;
      // Hover state is managed internally by DataSource now
    }

    // Update controller selection if external IDs change OR if datasource was updated
    if (dataSourceUpdated ||
        !const SetEquality().equals(
          widget.selectedTrackIds, // Detects change here
          oldWidget.selectedTrackIds,
        )) {
      _updateControllerSelection(); // Updates the grid controller's selection
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _dataGridController.dispose(); // Dispose the controller
    // Dispose the data source if necessary
    super.dispose();
  }

  // --- Selection Handling ---
  // This method now primarily informs the parent about the selection attempt.
  // The grid itself handles enforcing single selection due to the mode change.
  void _handleGridSelectionChange(
    List<DataGridRow> addedRows,
    List<DataGridRow> removedRows,
  ) {
    // Read modifier keys (though they won't enable multi-select in single mode)
    final keyState = HardwareKeyboard.instance;
    final bool isShiftPressed = keyState.isShiftPressed;
    final bool isCtrlPressed =
        keyState.isControlPressed || keyState.isMetaPressed;

    // Report the newly added row (if any) to the parent
    if (addedRows.isNotEmpty) {
      final row = addedRows.first; // In single mode, only one row can be added
      final idCell = row.getCells().firstWhere((c) => c.columnName == 'id');
      if (idCell.value != null && idCell.value != -1) {
        widget.onSelectionChanged(
          idCell.value as int,
          true, // isSelected = true
          isShiftPressed:
              isShiftPressed, // Pass modifiers even if unused by grid
          isCtrlPressed: isCtrlPressed,
        );
      }
    } else if (removedRows.isNotEmpty) {
      // If a row was deselected (e.g., by clicking it again or programmatically)
      // report the removal. In single mode, clicking another row handles deselection implicitly.
      final row = removedRows.first;
      final idCell = row.getCells().firstWhere((c) => c.columnName == 'id');
      if (idCell.value != null && idCell.value != -1) {
        widget.onSelectionChanged(
          idCell.value as int,
          false, // isSelected = false
          isShiftPressed: isShiftPressed,
          isCtrlPressed: isCtrlPressed,
        );
      }
    }

    // Refocus after selection change if needed
    if (mounted && (addedRows.isNotEmpty || removedRows.isNotEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          FocusScope.of(context).requestFocus(_focusNode);
        }
      });
    }
  }

  void _freezeLayoutAndRebuildColumns(String resizedColumnName) {
    // Freeze layout if not already frozen
    if (!_isLayoutFrozen) {
      _isLayoutFrozen = true;
      // Potentially update width modes of other columns to 'none' here if needed,
      // but simply relying on _columnWidths might be sufficient.
    }
    _buildGridColumnsFromState(); // Rebuild columns using the updated widths
  }

  @override
  Widget build(BuildContext context) {
    if (!_isColumnsInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final colorScheme = Theme.of(context).colorScheme;

    return Focus(
      focusNode: _focusNode,
      child: SfDataGridTheme(
        data: SfDataGridThemeData(
          selectionColor: colorScheme.primary.withOpacity(0.2),
          headerColor: colorScheme.surfaceVariant.withOpacity(0.5),
          headerHoverColor: colorScheme.primary.withOpacity(0.1),
          // rowHoverColor: colorScheme.onSurface.withOpacity(0.04), // Handled by DataSource now
        ),
        child: SfDataGrid(
          key: _sfDataGridKey,
          source: _trackDataSource, // Use the stored data source instance
          gridLinesVisibility: GridLinesVisibility.horizontal,
          headerGridLinesVisibility: GridLinesVisibility.both,
          headerRowHeight: 30,
          rowHeight: 40,
          allowColumnsResizing: true,
          allowColumnsDragging: true,
          onColumnDragging: (DataGridColumnDragDetails details) {
            if (details.action == DataGridColumnDragAction.dropping) {
              setState(() {
                final int fromIndex = details.from;
                final int toIndex = details.to!;

                if (fromIndex >= 0 &&
                    fromIndex < _gridColumns.length &&
                    toIndex >= 0 &&
                    toIndex < _gridColumns.length &&
                    fromIndex != toIndex) {
                  final GridColumn draggedColumn = _gridColumns.removeAt(
                    fromIndex,
                  );
                  _gridColumns.insert(toIndex, draggedColumn);

                  // Update the _columnOrder state variable used internally and for saving
                  _columnOrder =
                      _gridColumns
                          .where((c) => c.columnName != 'id')
                          .map((c) => c.columnName)
                          .toList();

                  // *** ADD THIS: Update the DataSource with the new order ***
                  _trackDataSource.updateColumnOrder(_columnOrder);
                  // Note: _trackDataSource.updateColumnOrder now calls notifyListeners() internally
                } else {
                  print(
                    "Column drag index out of bounds or invalid: from $fromIndex, to $toIndex",
                  );
                }
              });
              _saveColumnConfiguration(); // Save the new order
            }
            return true;
          },
          columnResizeMode: ColumnResizeMode.onResize,
          onColumnResizeUpdate: (ColumnResizeUpdateDetails details) {
            // --- Update specific width in _columnWidths ---
            final index = _gridColumns.indexWhere(
              (col) => col.columnName == details.column.columnName,
            );
            if (index != -1) {
              final columnName = details.column.columnName;
              double newWidth = max(50.0, details.width); // Apply min width
              setState(() {
                _columnWidths[columnName] = newWidth; // Update the width map
                // Rebuild columns to apply the new width and potentially freeze layout
                _freezeLayoutAndRebuildColumns(columnName);
              });
              _saveColumnConfiguration(); // Save after update
            }
            return true;
          },
          allowSorting: true,
          onColumnSortChanged: (
            SortColumnDetails? newSortColumn,
            SortColumnDetails? oldSortColumn,
          ) {
            if (newSortColumn != null) {
              widget.onSort(newSortColumn.name, newSortColumn.sortDirection);
            } else {
              // Default sort if sorting is cleared
              widget.onSort('title', DataGridSortDirection.ascending);
            }
          },
          // *** CHANGE SELECTION MODE HERE ***
          selectionMode: SelectionMode.single, // Changed from multiple
          navigationMode: GridNavigationMode.row,
          onSelectionChanged: _handleGridSelectionChange,
          controller: _dataGridController, // Use the controller from state
          columns: _gridColumns,

          // --- Context Menu (Right-Click) ---
          // *** UNCOMMENTED AND ENABLED ***Function( details
          onCellSecondaryTap: (DataGridCellTapDetails details) {
            int rowIndex = details.rowColumnIndex.rowIndex;
            // Adjust for header row (rowIndex 0 is header)
            if (rowIndex > 0 && rowIndex <= _trackDataSource.rows.length) {
              final dataRow = _trackDataSource.rows[rowIndex - 1];
              final idCell = dataRow.getCells().firstWhere(
                (cell) => cell.columnName == 'id',
                orElse: () => DataGridCell<int>(columnName: 'id', value: -1),
              );
              final int trackId = idCell.value as int? ?? -1;
              if (trackId != -1) {
                try {
                  // Find the track from the original widget list passed in
                  // This ensures we pass the correct Track object with resolved paths if necessary
                  final track = widget.tracks.firstWhere(
                    (t) => t.id == trackId,
                  );
                  // Use details.globalPosition for tap location
                  widget.onShowContextMenu(
                    // Call the handler passed from HomeScreen
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
          // --- End Context Menu ---
        ),
      ),
    );
  }
}
