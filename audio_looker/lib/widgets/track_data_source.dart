import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:audio_looker/services/collection_service.dart'; // Your Track model
import 'package:audio_looker/widgets/track_table_row.dart'
    show WaveformPreviewCell; // Reuse the cell widget

class TrackDataSource extends DataGridSource {
  /// Creates the track data source class with required details.
  TrackDataSource({required List<Track> trackData}) {
    _trackData = trackData;
    _updateDataGridRows(); // Initial population
  }

  List<DataGridRow> _dataGridRows = [];
  List<Track> _trackData = [];

  // Method to update the underlying data and refresh the grid rows
  // The list passed here should already be sorted by the caller (HomeScreen)
  void updateDataGridSource({required List<Track> trackData}) {
    _trackData = trackData;
    _updateDataGridRows();
    // Important: Notify listeners after updating data and rows
    try {
      notifyListeners();
    } catch (e) {
      // Catch potential errors if listeners are notified too early or late
      debugPrint("Error notifying listeners in TrackDataSource: $e");
    }
  }

  // Helper to build the DataGridRow list from the track data
  void _updateDataGridRows() {
    _dataGridRows =
        _trackData.map<DataGridRow>((track) {
          final trackId =
              track.id ?? -1; // Use -1 or handle null ID appropriately
          return DataGridRow(
            cells: [
              DataGridCell<int>(columnName: 'id', value: trackId),
              DataGridCell<Track>(columnName: 'preview', value: track),
              DataGridCell<String>(columnName: 'title', value: track.title),
              DataGridCell<String>(columnName: 'artist', value: track.artist),
              DataGridCell<String>(columnName: 'album', value: track.album),
              DataGridCell<int>(columnName: 'rating', value: track.rating),
              DataGridCell<List<String>>(
                columnName: 'tags',
                value: track.generalTags,
              ),
            ],
          );
        }).toList();
  }

  // --- DataGridSource Overrides ---

  @override
  List<DataGridRow> get rows => _dataGridRows;

  @override
  DataGridRowAdapter? buildRow(DataGridRow row) {
    // Find the corresponding track using the hidden ID cell
    final int trackId =
        row
                .getCells()
                .firstWhere(
                  (cell) => cell.columnName == 'id',
                  orElse: () => DataGridCell<int>(columnName: 'id', value: -1),
                )
                .value
            as int? ??
        -1;
    Track? track;
    try {
      // Find track in the current internal list (_trackData should be sorted by HomeScreen)
      track = _trackData.firstWhere((t) => t.id == trackId);
    } catch (e) {
      debugPrint("Track with ID $trackId not found in buildRow.");
      return null; // Return null if track not found
    }

    // Selection state is handled visually by SfDataGrid based on controller/callbacks
    final bool isSelected =
        false; // Not needed directly here for building cells

    return DataGridRowAdapter(
      cells:
          row.getCells().map<Widget>((dataGridCell) {
            // Build cell widgets based on column name
            switch (dataGridCell.columnName) {
              case 'id':
                return const SizedBox.shrink();
              case 'preview':
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4.0,
                    vertical: 4.0,
                  ),
                  alignment: Alignment.centerLeft,
                  child: WaveformPreviewCell(
                    track: dataGridCell.value as Track,
                    isSelected: isSelected,
                    onPlayPreview: () {
                      /* Play handled by HomeScreen via onCellTap */
                    },
                  ),
                );
              case 'title':
                return Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 4.0,
                  ),
                  child: Text(
                    dataGridCell.value.toString(),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              case 'artist':
              case 'album':
                return Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 4.0,
                  ),
                  child: Text(
                    dataGridCell.value.toString(),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              case 'rating':
                return Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 4.0,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      5,
                      (i) => Icon(
                        i < (dataGridCell.value as int)
                            ? Icons.star
                            : Icons.star_border,
                        size: 14,
                        color:
                            i < (dataGridCell.value as int)
                                ? Colors.amber.shade600
                                : Colors.grey.shade500,
                      ),
                    ),
                  ),
                );
              case 'tags':
                final tags = dataGridCell.value as List<String>;
                return Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 4.0,
                  ),
                  child:
                      tags.isEmpty
                          ? const SizedBox.shrink()
                          : Wrap(
                            spacing: 4.0,
                            runSpacing: 4.0,
                            children:
                                tags
                                    .map(
                                      (tag) => Chip(
                                        label: Text(tag),
                                        labelStyle: const TextStyle(
                                          fontSize: 10,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 0,
                                        ),
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        backgroundColor: Colors.blueGrey
                                            .withOpacity(0.1),
                                        side: BorderSide.none,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    )
                                    .toList(),
                          ),
                );
              default:
                return Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 4.0,
                  ),
                  child: Text(
                    dataGridCell.value?.toString() ?? '',
                    overflow: TextOverflow.ellipsis,
                  ),
                );
            }
          }).toList(),
    );
  }

  // --- Sorting ---
  // REMOVED performSorting override. Sorting is handled before updating the source.

  // --- Selection ---
  // Selection state is managed by HomeScreen via callbacks and controller.
}
