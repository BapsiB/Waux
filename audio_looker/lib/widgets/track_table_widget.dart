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

  @override
  void initState() {
    super.initState();
    // Initialize DataSource here
    _trackDataSource = TrackDataSource(
      trackData: widget.tracks,
      audioPlayerBloc: widget.audioPlayerBloc,
      onRatingChanged: widget.onRatingChanged,
      onPlayPreviewAndMinimize: widget.onPlayPreviewAndMinimize,
    );
    // Initialize Controller here
    _dataGridController = DataGridController();
    _updateControllerSelection(); // Initial selection update

    // Keep focus logic
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusScope.of(context).requestFocus(_focusNode);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Initialize columns only once or if layout changes significantly
    if (!_isColumnsInitialized) {
      _initializeColumns(useFill: true); // Adjust useFill based on needs
      _isColumnsInitialized = true;
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
    } catch (e) {
      debugPrint(
        "Error updating controller selection (might be temporary): $e",
      );
      // Optionally clear selection if rows are unavailable
      // _dataGridController.selectedRows = [];
    }
  }

  // initializeColumns remains the same
  void _initializeColumns({required bool useFill}) {
    final textTheme = Theme.of(context).textTheme;
    final flexibleMode = useFill ? ColumnWidthMode.fill : ColumnWidthMode.none;
    final flexibleWidth = useFill ? double.nan : _defaultTextColumnWidth;

    _gridColumns = <GridColumn>[
      GridColumn(
        columnName: 'id',
        label: SizedBox.shrink(),
        width: 0,
        visible: false,
      ),
      GridColumn(
        columnName: 'preview',
        width: _initialPreviewWidth,
        columnWidthMode: ColumnWidthMode.none,
        allowSorting: false,
        label: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Text('Preview', style: textTheme.titleSmall),
        ),
      ),
      GridColumn(
        columnName: 'title',
        width: flexibleWidth,
        columnWidthMode: flexibleMode,
        label: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Text('Title', style: textTheme.titleSmall),
        ),
      ),
      GridColumn(
        columnName: 'artist',
        width: flexibleWidth,
        columnWidthMode: flexibleMode,
        label: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Text('Artist', style: textTheme.titleSmall),
        ),
      ),
      GridColumn(
        columnName: 'album',
        width: flexibleWidth,
        columnWidthMode: flexibleMode,
        label: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Text('Album', style: textTheme.titleSmall),
        ),
      ),
      GridColumn(
        columnName: 'rating',
        width: _initialRatingWidth,
        columnWidthMode: ColumnWidthMode.none,
        label: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Text('Rating', style: textTheme.titleSmall),
        ),
      ),
      GridColumn(
        columnName: 'tags',
        width: flexibleWidth,
        columnWidthMode: flexibleMode,
        allowSorting: false,
        label: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Text('Tags', style: textTheme.titleSmall),
        ),
      ),
    ];
  }

  @override
  void didUpdateWidget(TrackTableWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    bool dataSourceUpdated = false;
    // Update the data source if the tracks list changes
    if (!const ListEquality().equals(widget.tracks, oldWidget.tracks)) {
      // Deep comparison
      _trackDataSource.updateDataGridSource(trackData: widget.tracks);
      dataSourceUpdated = true;
      // Hover state is managed internally by DataSource now
    }

    // Update controller selection if external IDs change OR if datasource was updated
    // Use deep comparison for Sets as well
    if (dataSourceUpdated ||
        !const SetEquality().equals(
          widget.selectedTrackIds,
          oldWidget.selectedTrackIds,
        )) {
      _updateControllerSelection();
    }
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
          // rowHoverColor: colorScheme.onSurface.withOpacity(0.04),
        ),
        child: SfDataGrid(
          key: _sfDataGridKey,
          source: _trackDataSource, // Use the stored data source instance
          gridLinesVisibility: GridLinesVisibility.horizontal,
          headerGridLinesVisibility: GridLinesVisibility.both,
          headerRowHeight: 30,
          rowHeight: 40,
          allowColumnsResizing: true,
          columnResizeMode: ColumnResizeMode.onResize,
          onColumnResizeUpdate: (ColumnResizeUpdateDetails details) {
            // --- Column Resize Logic (Unchanged) ---
            setState(() {
              final index = _gridColumns.indexWhere(
                (col) => col.columnName == details.column.columnName,
              );
              if (index != -1) {
                double newWidth = max(50.0, details.width);
                _gridColumns[index] = GridColumn(
                  columnName: details.column.columnName,
                  label: _gridColumns[index].label,
                  width: newWidth,
                  visible: _gridColumns[index].visible,
                  columnWidthMode: ColumnWidthMode.none,
                  allowSorting: _gridColumns[index].allowSorting,
                  allowEditing: _gridColumns[index].allowEditing,
                  allowFiltering: _gridColumns[index].allowFiltering,
                );
                if (!_isLayoutFrozen) {
                  _isLayoutFrozen = true;
                  for (int i = 0; i < _gridColumns.length; i++) {
                    if (i != index &&
                        _gridColumns[i].columnWidthMode ==
                            ColumnWidthMode.fill) {
                      _gridColumns[i] = GridColumn(
                        columnName: _gridColumns[i].columnName,
                        label: _gridColumns[i].label,
                        width: _defaultTextColumnWidth,
                        visible: _gridColumns[i].visible,
                        columnWidthMode: ColumnWidthMode.none,
                        allowSorting: _gridColumns[i].allowSorting,
                        allowEditing: _gridColumns[i].allowEditing,
                        allowFiltering: _gridColumns[i].allowFiltering,
                      );
                    } else if (i != index &&
                        _gridColumns[i].columnWidthMode !=
                            ColumnWidthMode.fill &&
                        _gridColumns[i].columnWidthMode !=
                            ColumnWidthMode.none) {
                      if (_gridColumns[i].width != double.nan &&
                          _gridColumns[i].columnWidthMode !=
                              ColumnWidthMode.none) {
                        _gridColumns[i] = GridColumn(
                          columnName: _gridColumns[i].columnName,
                          label: _gridColumns[i].label,
                          width: _gridColumns[i].width,
                          visible: _gridColumns[i].visible,
                          columnWidthMode: ColumnWidthMode.none,
                          allowSorting: _gridColumns[i].allowSorting,
                          allowEditing: _gridColumns[i].allowEditing,
                          allowFiltering: _gridColumns[i].allowFiltering,
                        );
                      }
                    }
                  }
                }
              }
            });
            return true;
            // --- End Column Resize Logic ---
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
          // onCellSecondaryTap: (DataGridCellSecondaryTapDetails details) {
          //   int rowIndex = details.rowColumnIndex.rowIndex;
          //   // Adjust for header row (rowIndex 0 is header)
          //   if (rowIndex > 0 && rowIndex <= _trackDataSource.rows.length) {
          //     final dataRow = _trackDataSource.rows[rowIndex - 1];
          //     final idCell = dataRow.getCells().firstWhere(
          //       (cell) => cell.columnName == 'id',
          //       orElse: () => DataGridCell<int>(columnName: 'id', value: -1),
          //     );
          //     final int trackId = idCell.value as int? ?? -1;
          //     if (trackId != -1) {
          //       try {
          //         // Find the track from the original widget list passed in
          //         final track = widget.tracks.firstWhere(
          //           (t) => t.id == trackId,
          //         );
          //         // Use details.globalPosition for tap location
          //         widget.onShowContextMenu(
          //           context,
          //           details.globalPosition,
          //           track,
          //         );
          //       } catch (e) {
          //         debugPrint("Error finding track for context menu: $e");
          //       }
          //     }
          //   }
          // },
          // --- End Context Menu ---
        ),
      ),
    );
  }
}
