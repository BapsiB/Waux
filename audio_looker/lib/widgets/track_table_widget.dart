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
// Reuse typedefs from TrackDataSource
// typedef PlayPreviewCallback = void Function(Track track);
// typedef RatingChangeCallback = void Function(int trackId, int newRating);
typedef SortCallback =
    void Function(String columnName, DataGridSortDirection direction);

class TrackTableWidget extends StatefulWidget {
  final List<Track> tracks;
  final Set<int> selectedTrackIds;
  final SelectionChangeCallback onSelectionChanged;
  final ContextMenuCallback onShowContextMenu;
  final PlayPreviewCallback onPlayPreview;
  final RatingChangeCallback onRatingChanged; // *** Add this callback ***
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
    required this.onRatingChanged, // *** Add to constructor ***
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
  final double _initialPreviewWidth = 250;
  final double _initialRatingWidth =
      100; // Make rating slightly wider for buttons
  // Define a default width for text columns AFTER freezing the layout
  final double _defaultTextColumnWidth = 150;

  @override
  void initState() {
    super.initState();
    // *** Pass callbacks to DataSource ***
    _trackDataSource = TrackDataSource(
      trackData: widget.tracks,
      onPlayPreview: widget.onPlayPreview,
      onRatingChanged: widget.onRatingChanged,
    );
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
    // Use 'fill' initially, switch to 'none' after first resize
    final flexibleMode = useFill ? ColumnWidthMode.fill : ColumnWidthMode.none;
    // Assign width only if not using fill (i.e., after freezing)
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
        columnWidthMode: ColumnWidthMode.none, // Always fixed
        allowSorting: false,
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
        width: _initialRatingWidth, // Use the adjusted width
        columnWidthMode: ColumnWidthMode.none, // Always fixed
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
    if (widget.tracks != oldWidget.tracks) {
      _trackDataSource.updateDataGridSource(trackData: widget.tracks);
    }
    // Update DataSource if callbacks change (less common, but good practice)
    if (widget.onPlayPreview != oldWidget.onPlayPreview ||
        widget.onRatingChanged != oldWidget.onRatingChanged) {
      _trackDataSource = TrackDataSource(
        trackData: widget.tracks,
        onPlayPreview: widget.onPlayPreview,
        onRatingChanged: widget.onRatingChanged,
      );
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  // --- Selection Handling ---
  // SfDataGrid's onSelectionChanged handles row selection state internally
  // We just need to report the changes back to the parent (HomeScreen)
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
    _trackDataSource.updateDataGridSource(trackData: widget.tracks);

    // Update DataGridController selection when external selection changes
    final controller = DataGridController(
      selectedRows:
          _trackDataSource.rows.where((row) {
            final idCell = row.getCells().firstWhere(
              (c) => c.columnName == 'id',
              orElse: () => DataGridCell<int>(columnName: 'id', value: -1),
            );
            return idCell.value != null &&
                widget.selectedTrackIds.contains(idCell.value as int);
          }).toList(),
    );

    return Focus(
      focusNode: _focusNode,
      child: SfDataGridTheme(
        data: SfDataGridThemeData(
          selectionColor: colorScheme.primary.withOpacity(0.2),
          // Optional: Customize header style
          headerColor: colorScheme.surfaceVariant.withOpacity(0.5),
          headerHoverColor: colorScheme.primary.withOpacity(0.1),
        ),
        child: SfDataGrid(
          key: _sfDataGridKey,
          source: _trackDataSource,
          gridLinesVisibility: GridLinesVisibility.horizontal,
          headerGridLinesVisibility: GridLinesVisibility.both,
          headerRowHeight: 30,
          rowHeight: 40, // Adjust row height if needed for buttons
          allowColumnsResizing: true,
          columnResizeMode: ColumnResizeMode.onResize,
          // --- *** CORRECTED onColumnResizeUpdate *** ---
          onColumnResizeUpdate: (ColumnResizeUpdateDetails details) {
            setState(() {
              final index = _gridColumns.indexWhere(
                (col) => col.columnName == details.column.columnName,
              );
              if (index != -1) {
                // Ensure minimum width, allow user to resize
                double newWidth = max(50.0, details.width);

                // Update the specific column being resized
                _gridColumns[index] = GridColumn(
                  columnName: details.column.columnName,
                  label: _gridColumns[index].label,
                  width: newWidth,
                  visible: _gridColumns[index].visible,
                  // Freeze to 'none' once resized
                  columnWidthMode: ColumnWidthMode.none,
                  allowSorting: _gridColumns[index].allowSorting,
                  allowEditing:
                      _gridColumns[index].allowEditing, // Keep other properties
                  allowFiltering:
                      _gridColumns[index]
                          .allowFiltering, // Keep other properties
                );

                // Freeze layout on first resize interaction
                if (!_isLayoutFrozen) {
                  _isLayoutFrozen = true;
                  // Freeze other 'fill' columns to 'none' with default widths
                  for (int i = 0; i < _gridColumns.length; i++) {
                    // Check if it's a different column AND it's still 'fill'
                    if (i != index &&
                        _gridColumns[i].columnWidthMode ==
                            ColumnWidthMode.fill) {
                      _gridColumns[i] = GridColumn(
                        columnName: _gridColumns[i].columnName,
                        label: _gridColumns[i].label,
                        // Assign default width when freezing
                        width: _defaultTextColumnWidth,
                        visible: _gridColumns[i].visible,
                        // Freeze mode
                        columnWidthMode: ColumnWidthMode.none,
                        allowSorting: _gridColumns[i].allowSorting,
                        allowEditing:
                            _gridColumns[i]
                                .allowEditing, // Keep other properties
                        allowFiltering:
                            _gridColumns[i]
                                .allowFiltering, // Keep other properties
                      );
                    }
                    // Ensure already fixed columns (like preview, rating) remain 'none'
                    else if (i != index &&
                        _gridColumns[i].columnWidthMode !=
                            ColumnWidthMode.fill &&
                        _gridColumns[i].columnWidthMode !=
                            ColumnWidthMode.none) {
                      // This condition might be redundant if initial setup only uses 'fill' or 'none'
                      // But it ensures explicitly fixed columns stay fixed.
                      if (_gridColumns[i].width != double.nan &&
                          _gridColumns[i].columnWidthMode !=
                              ColumnWidthMode.none) {
                        _gridColumns[i] = GridColumn(
                          columnName: _gridColumns[i].columnName,
                          label: _gridColumns[i].label,
                          width: _gridColumns[i].width, // Keep existing width
                          visible: _gridColumns[i].visible,
                          columnWidthMode:
                              ColumnWidthMode.none, // Ensure mode is none
                          allowSorting: _gridColumns[i].allowSorting,
                          allowEditing:
                              _gridColumns[i]
                                  .allowEditing, // Keep other properties
                          allowFiltering:
                              _gridColumns[i]
                                  .allowFiltering, // Keep other properties
                        );
                      }
                    }
                  }
                }
              }
            });
            return true;
          },
          // --- *** END CORRECTION *** ---
          allowSorting: true,
          // Apply initial sorting state
          // sortedColumns: [
          //   SortColumnDetails(
          //     name: widget.initialSortColumnName,
          //     sortDirection: widget.initialSortDirection,
          //   ),
          // ],
          onColumnSortChanged: (
            SortColumnDetails? newSortColumn,
            SortColumnDetails? oldSortColumn,
          ) {
            if (newSortColumn != null) {
              widget.onSort(newSortColumn.name, newSortColumn.sortDirection);
            } else {
              // Optional: Handle case where sorting is removed (e.g., revert to default)
              widget.onSort(
                'title',
                DataGridSortDirection.ascending,
              ); // Example default
            }
          },
          selectionMode: SelectionMode.multiple,
          navigationMode: GridNavigationMode.row,
          onSelectionChanged: _handleGridSelectionChange,
          controller: controller, // Use the updated controller
          columns: _gridColumns,
          // onCellSecondaryTap: (DataGridCellSecondaryTapDetails details) {
          //   int rowIndex =
          //       details.rowColumnIndex.rowIndex - 1; // Adjust for header row
          //   if (rowIndex >= 0 && rowIndex < _trackDataSource.rows.length) {
          //     final dataRow = _trackDataSource.rows[rowIndex];
          //     // Find track using hidden 'id' cell
          //     final idCell = dataRow.getCells().firstWhere(
          //       (cell) => cell.columnName == 'id',
          //       orElse: () => DataGridCell<int>(columnName: 'id', value: -1),
          //     );
          //     final int trackId = idCell.value as int? ?? -1;

          //     if (trackId != -1) {
          //       // Find the track object from the original list (widget.tracks)
          //       try {
          //         final track = widget.tracks.firstWhere(
          //           (t) => t.id == trackId,
          //         );
          //         // Get global position for the context menu
          //         final RenderBox cellRenderBox =
          //             context.findRenderObject() as RenderBox;
          //         final Offset globalPosition = cellRenderBox.localToGlobal(
          //           details.localPosition,
          //         );
          //         widget.onShowContextMenu(context, globalPosition, track);
          //       } catch (e) {
          //         debugPrint("Error finding track for context menu: $e");
          //       }
          //     }
          //   }
          // },
          // *** REMOVED onCellTap ***
        ),
      ),
    );
  }
}
