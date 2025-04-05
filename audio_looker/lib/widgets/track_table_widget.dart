import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:syncfusion_flutter_core/theme.dart'; // Optional for theming
import 'dart:math'; // Required for max function

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
// typedef PlayPreviewCallback = void Function(Track track); // *** REMOVED ***
typedef RatingChangeCallback = void Function(int trackId, int newRating);
typedef SortCallback =
    void Function(String columnName, DataGridSortDirection direction);

class TrackTableWidget extends StatefulWidget {
  final List<Track> tracks;
  final Set<int> selectedTrackIds;
  final AudioPlayerBloc audioPlayerBloc; // *** Add Bloc parameter ***
  final SelectionChangeCallback onSelectionChanged;
  final ContextMenuCallback onShowContextMenu;
  final RatingChangeCallback onRatingChanged;
  final SortCallback onSort;
  final String initialSortColumnName;
  final DataGridSortDirection initialSortDirection;

  const TrackTableWidget({
    Key? key,
    required this.tracks,
    required this.selectedTrackIds,
    required this.audioPlayerBloc, // *** Add to constructor ***
    required this.onSelectionChanged,
    required this.onShowContextMenu,
    required this.onRatingChanged,
    required this.onSort,
    required this.initialSortColumnName,
    required this.initialSortDirection,
  }) : super(key: key);

  @override
  _TrackTableWidgetState createState() => _TrackTableWidgetState();
}

class _TrackTableWidgetState extends State<TrackTableWidget> {
  // Data source is now created in build method
  final GlobalKey<SfDataGridState> _sfDataGridKey =
      GlobalKey<SfDataGridState>();
  final FocusNode _focusNode = FocusNode();

  late List<GridColumn> _gridColumns;
  bool _isColumnsInitialized = false;
  bool _isLayoutFrozen = false;

  final double _initialPreviewWidth = 250;
  final double _initialRatingWidth = 100;
  final double _defaultTextColumnWidth = 150;

  @override
  void initState() {
    super.initState();
    // Initialize columns here

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
    _initializeColumns(useFill: true);
    _isColumnsInitialized = true;
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
    // No need to update data source based on callbacks here
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  // --- Selection Handling (remains the same) ---
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
    // context is available here
    if (!_isColumnsInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    // *** Create DataSource within build using the current context ***
    final trackDataSource = TrackDataSource(
      // removed context: context,
      trackData: widget.tracks,
      audioPlayerBloc: widget.audioPlayerBloc, // *** Pass bloc instance ***
      onRatingChanged: widget.onRatingChanged,
    );

    final colorScheme = Theme.of(context).colorScheme;

    // Update DataGridController selection when external selection changes
    final controller = DataGridController(
      selectedRows:
          trackDataSource.rows.where((row) {
            // Use local trackDataSource instance
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
          headerColor: colorScheme.surfaceVariant.withOpacity(0.5),
          headerHoverColor: colorScheme.primary.withOpacity(0.1),
        ),
        child: SfDataGrid(
          key: _sfDataGridKey,
          source: trackDataSource, // Use local trackDataSource instance
          gridLinesVisibility: GridLinesVisibility.horizontal,
          headerGridLinesVisibility: GridLinesVisibility.both,
          headerRowHeight: 30,
          rowHeight: 40,
          allowColumnsResizing: true,
          columnResizeMode: ColumnResizeMode.onResize,
          onColumnResizeUpdate: (ColumnResizeUpdateDetails details) {
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
          },
          allowSorting: true,
          onColumnSortChanged: (
            SortColumnDetails? newSortColumn,
            SortColumnDetails? oldSortColumn,
          ) {
            if (newSortColumn != null) {
              widget.onSort(newSortColumn.name, newSortColumn.sortDirection);
            } else {
              widget.onSort('title', DataGridSortDirection.ascending);
            }
          },
          selectionMode: SelectionMode.multiple,
          navigationMode: GridNavigationMode.row,
          onSelectionChanged: _handleGridSelectionChange,
          controller: controller,
          columns: _gridColumns,
          // onCellSecondaryTap: (DataGridCellSecondaryTapDetails details) {
          //   int rowIndex = details.rowColumnIndex.rowIndex - 1;
          //   if (rowIndex >= 0 && rowIndex < trackDataSource.rows.length) {
          //     // Use local trackDataSource
          //     final dataRow =
          //         trackDataSource.rows[rowIndex]; // Use local trackDataSource
          //     final idCell = dataRow.getCells().firstWhere(
          //       (cell) => cell.columnName == 'id',
          //       orElse: () => DataGridCell<int>(columnName: 'id', value: -1),
          //     );
          //     final int trackId = idCell.value as int? ?? -1;
          //     if (trackId != -1) {
          //       try {
          //         final track = widget.tracks.firstWhere(
          //           (t) => t.id == trackId,
          //         );
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
        ),
      ),
    );
  }
}
