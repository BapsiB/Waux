import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:syncfusion_flutter_core/theme.dart'; // Optional for theming
import 'dart:math'; // Required for max function

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
typedef PlayPreviewCallback = void Function(Track track);
typedef SortCallback =
    void Function(String columnName, DataGridSortDirection direction);

class TrackTableWidget extends StatefulWidget {
  final List<Track> tracks;
  final Set<int> selectedTrackIds;
  final SelectionChangeCallback onSelectionChanged;
  final ContextMenuCallback onShowContextMenu;
  final PlayPreviewCallback onPlayPreview;
  final SortCallback onSort;
  final String initialSortColumnName;
  final DataGridSortDirection initialSortDirection;

  const TrackTableWidget({
    Key? key,
    required this.tracks,
    required this.selectedTrackIds,
    required this.onSelectionChanged,
    required this.onShowContextMenu,
    required this.onPlayPreview,
    required this.onSort,
    required this.initialSortColumnName,
    required this.initialSortDirection,
  }) : super(key: key);

  @override
  _TrackTableWidgetState createState() => _TrackTableWidgetState();
}

class _TrackTableWidgetState extends State<TrackTableWidget> {
  late TrackDataSource _trackDataSource;
  final GlobalKey<SfDataGridState> _sfDataGridKey =
      GlobalKey<SfDataGridState>();
  final FocusNode _focusNode = FocusNode();

  late List<GridColumn> _gridColumns;
  bool _isColumnsInitialized = false;
  bool _isLayoutFrozen =
      false; // Flag to track if initial fill layout is frozen

  // Define initial widths for fixed columns
  final double _initialPreviewWidth = 150;
  final double _initialRatingWidth = 100;
  // Define a default width for text columns AFTER freezing the layout
  final double _defaultTextColumnWidth = 150;

  @override
  void initState() {
    super.initState();
    _trackDataSource = TrackDataSource(trackData: widget.tracks);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusScope.of(context).requestFocus(_focusNode);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isColumnsInitialized) {
      // Initialize with 'fill' for flexible columns initially
      _initializeColumns(useFill: true);
      _isColumnsInitialized = true;
    }
  }

  // Modified to accept 'useFill' flag
  void _initializeColumns({required bool useFill}) {
    final textTheme = Theme.of(context).textTheme;
    // Determine mode and width based on the flag
    final flexibleMode = useFill ? ColumnWidthMode.fill : ColumnWidthMode.none;
    // Assign width only if not using fill
    final flexibleWidth = useFill ? double.nan : _defaultTextColumnWidth;

    _gridColumns = <GridColumn>[
      GridColumn(
        // Hidden ID column
        columnName: 'id',
        label: SizedBox.shrink(),
        width: 0,
        visible: false,
      ),
      GridColumn(
        // Preview column - Always Fixed Width
        columnName: 'preview',
        width: _initialPreviewWidth,
        columnWidthMode: ColumnWidthMode.none,
        label: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Text('Preview', style: textTheme.titleSmall),
        ),
      ),
      GridColumn(
        // Title column - Initial Fill or Fixed
        columnName: 'title',
        width: flexibleWidth, // Use calculated width or NaN
        columnWidthMode: flexibleMode, // Use calculated mode
        label: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Text('Title', style: textTheme.titleSmall),
        ),
      ),
      GridColumn(
        // Artist column - Initial Fill or Fixed
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
        // Album column - Initial Fill or Fixed
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
        // Rating column - Always Fixed Width
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
        // Tags column - Initial Fill or Fixed
        columnName: 'tags',
        width: flexibleWidth,
        columnWidthMode: flexibleMode,
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
    if (widget.tracks != oldWidget.tracks) {
      _trackDataSource.updateDataGridSource(trackData: widget.tracks);
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  // --- Selection Handling ---
  void _handleGridSelectionChange(
    List<DataGridRow> addedRows,
    List<DataGridRow> removedRows,
  ) {
    final keyState = HardwareKeyboard.instance;
    final bool isShiftPressed = keyState.isShiftPressed;
    final bool isCtrlPressed =
        keyState.isControlPressed || keyState.isMetaPressed;

    for (var row in addedRows) {
      final idCell = row.getCells().firstWhere((c) => c.columnName == 'id');
      if (idCell.value != null && idCell.value != -1) {
        widget.onSelectionChanged(
          idCell.value as int,
          true, // isSelected = true
          isShiftPressed: isShiftPressed,
          isCtrlPressed: isCtrlPressed,
        );
      }
    }
    for (var row in removedRows) {
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
    if (mounted) {
      FocusScope.of(context).requestFocus(_focusNode);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isColumnsInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final colorScheme = Theme.of(context).colorScheme;
    _trackDataSource.updateDataGridSource(trackData: widget.tracks);

    return Focus(
      focusNode: _focusNode,
      child: SfDataGridTheme(
        data: SfDataGridThemeData(
          selectionColor: colorScheme.primary.withOpacity(0.2),
        ),
        child: SfDataGrid(
          key: _sfDataGridKey,
          source: _trackDataSource,
          gridLinesVisibility: GridLinesVisibility.horizontal,
          headerGridLinesVisibility: GridLinesVisibility.horizontal,
          // --- Column Resizing ---
          allowColumnsResizing: true,
          columnResizeMode: ColumnResizeMode.onResize,
          onColumnResizeStart: (ColumnResizeStartDetails details) {
            debugPrint('Resize Start: ${details.column.columnName}');
            return true;
          },
          onColumnResizeUpdate: (ColumnResizeUpdateDetails details) {
            setState(() {
              final index = _gridColumns.indexWhere(
                (col) => col.columnName == details.column.columnName,
              );
              if (index != -1) {
                double newWidth = max(30.0, details.width);
                // Update the resized column
                _gridColumns[index] = GridColumn(
                  columnName: details.column.columnName,
                  label: _gridColumns[index].label,
                  width: newWidth,
                  visible: _gridColumns[index].visible,
                  columnWidthMode: ColumnWidthMode.none, // Explicit width now
                  allowSorting: _gridColumns[index].allowSorting,
                  allowEditing: _gridColumns[index].allowEditing,
                  allowFiltering: _gridColumns[index].allowFiltering,
                );

                // FIX: Freeze layout on first resize interaction
                if (!_isLayoutFrozen) {
                  debugPrint('Freezing layout...');
                  // Iterate through all columns to freeze any remaining 'fill' columns
                  for (int i = 0; i < _gridColumns.length; i++) {
                    // Skip the column currently being resized (already handled)
                    // and columns that are already 'none' or fixed
                    if (i != index &&
                        _gridColumns[i].columnWidthMode ==
                            ColumnWidthMode.fill) {
                      debugPrint(
                        'Freezing column: ${_gridColumns[i].columnName}',
                      );
                      // Replace with 'none' mode and a default width
                      // Getting the *actual* current width of these 'fill' columns
                      // before freezing is complex, so we use a default.
                      _gridColumns[i] = GridColumn(
                        columnName: _gridColumns[i].columnName,
                        label: _gridColumns[i].label,
                        width: _defaultTextColumnWidth, // Assign default width
                        visible: _gridColumns[i].visible,
                        columnWidthMode: ColumnWidthMode.none, // Freeze mode
                        allowSorting: _gridColumns[i].allowSorting,
                        allowEditing: _gridColumns[i].allowEditing,
                        allowFiltering: _gridColumns[i].allowFiltering,
                      );
                    }
                  }
                  _isLayoutFrozen = true; // Freeze only once
                }
              }
            });
            debugPrint(
              'Resize Update: ${details.column.columnName} -> ${details.width}',
            );
            return true;
          },
          onColumnResizeEnd: (ColumnResizeEndDetails details) {
            debugPrint(
              'Resize End: ${details.column.columnName} -> ${details.width}',
            );
            // No need to call setState here if already done in onColumnResizeUpdate
            // setState(() {});
          },
          // --- Sorting ---
          allowSorting: true,
          onColumnSortChanged: (
            SortColumnDetails? newSortColumn,
            SortColumnDetails? oldSortColumn,
          ) {
            if (newSortColumn != null) {
              widget.onSort(newSortColumn.name, newSortColumn.sortDirection);
            }
          },
          // --- Selection ---
          selectionMode: SelectionMode.multiple,
          navigationMode: GridNavigationMode.row,
          onSelectionChanged: _handleGridSelectionChange,
          controller: DataGridController(
            selectedRows:
                _trackDataSource.rows.where((row) {
                  final idCell = row.getCells().firstWhere(
                    (c) => c.columnName == 'id',
                  );
                  return idCell.value != null &&
                      widget.selectedTrackIds.contains(idCell.value as int);
                }).toList(),
          ),

          // --- Columns Definition ---
          columns: _gridColumns, // Use the state variable
          // --- Context Menu ---
          // onCellSecondaryTap: (DataGridCellSecondaryTapDetails details) {
          //   int rowIndex = details.rowColumnIndex.rowIndex - 1;
          //   if (rowIndex >= 0 && rowIndex < _trackDataSource.rows.length) {
          //     final dataRow = _trackDataSource.rows[rowIndex];
          //     final trackCell = dataRow.getCells().firstWhere(
          //       (cell) => cell.columnName == 'preview',
          //       orElse:
          //           () => DataGridCell<Track?>(
          //             columnName: 'preview',
          //             value: null,
          //           ),
          //     );
          //     final Track? track = trackCell.value as Track?;

          //     if (track != null && track.id != null) {
          //       final RenderBox cellRenderBox =
          //           context.findRenderObject() as RenderBox;
          //       final Offset globalPosition = cellRenderBox.localToGlobal(
          //         details.localPosition,
          //       );
          //       widget.onShowContextMenu(context, globalPosition, track);
          //     }
          //   }
          // },
          // --- Cell Taps (for Play Preview) ---
          onCellTap: (DataGridCellTapDetails details) {
            int rowIndex = details.rowColumnIndex.rowIndex - 1;
            int cellIndex = details.rowColumnIndex.columnIndex;
            if (rowIndex >= 0 && cellIndex == 1) {
              // Preview column is index 1
              final trackCell = _trackDataSource.rows[rowIndex]
                  .getCells()
                  .firstWhere(
                    (cell) => cell.columnName == 'preview',
                    orElse:
                        () => DataGridCell<Track?>(
                          columnName: 'preview',
                          value: null,
                        ),
                  );
              final Track? track = trackCell.value as Track?;
              if (track != null) {
                widget.onPlayPreview(track);
              }
            } else if (rowIndex >= 0) {
              final idCell = _trackDataSource.rows[rowIndex]
                  .getCells()
                  .firstWhere((c) => c.columnName == 'id');
              if (idCell.value != null && idCell.value != -1) {
                final keyState = HardwareKeyboard.instance;
                widget.onSelectionChanged(
                  idCell.value as int,
                  !widget.selectedTrackIds.contains(idCell.value),
                  isShiftPressed: keyState.isShiftPressed,
                  isCtrlPressed:
                      keyState.isControlPressed || keyState.isMetaPressed,
                );
              }
            }
          },
        ),
      ),
    );
  }
}
