import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:audio_looker/services/collection_service.dart'; // Your Track model
import 'package:audio_looker/widgets/track_table_row.dart';
import 'package:audio_looker/widgets/rating_cell_widget.dart'; // Reuse the cell widget

// Add these typedefs for clarity
typedef PlayPreviewCallback = void Function(Track track);
typedef RatingChangeCallback = void Function(int trackId, int newRating);

class TrackDataSource extends DataGridSource {
  /// Creates the track data source class with required details.
  TrackDataSource({
    required List<Track> trackData,
    required this.onPlayPreview, // Add callback
    required this.onRatingChanged, // Add callback
  }) {
    _trackData = trackData;
    _updateDataGridRows(); // Initial population
  }

  List<DataGridRow> _dataGridRows = [];
  List<Track> _trackData = [];
  final PlayPreviewCallback onPlayPreview; // Store callback
  final RatingChangeCallback onRatingChanged; // Store callback

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
              // Store the track itself for the rating cell to access ID and rating
              DataGridCell<Track>(columnName: 'rating', value: track),
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
    // We don't need the isSelected flag here for building interactive cells
    // final bool isSelected = false;

    return DataGridRowAdapter(
      // Use a transparent color to let SfDataGrid handle selection highlight
      // color: Colors.transparent, // Let SfDataGrid handle selection color
      cells:
          row.getCells().map<Widget>((dataGridCell) {
            // Build cell widgets based on column name
            switch (dataGridCell.columnName) {
              case 'id':
                return const SizedBox.shrink();
              case 'preview':
                // Make sure the track from the cell value is not null
                final Track? cellTrack = dataGridCell.value as Track?;
                if (cellTrack == null) return const SizedBox.shrink();
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4.0,
                    vertical: 4.0,
                  ),
                  alignment: Alignment.centerLeft,
                  child: WaveformPreviewCell(
                    track: cellTrack,
                    isSelected: false, // isSelected handled by SfDataGrid
                    // *** Pass the callback ***
                    onPlayPreview: () => onPlayPreview(cellTrack),
                  ),
                );
              case 'title':
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
                // Make sure the track from the cell value is not null
                final Track? ratingTrack = dataGridCell.value as Track?;
                if (ratingTrack == null || ratingTrack.id == null)
                  return const SizedBox.shrink();

                // *** Use the new RatingCellWidget ***
                return Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0, // Adjust padding if needed
                    vertical: 4.0,
                  ),
                  child: RatingCellWidget(
                    trackId: ratingTrack.id!,
                    currentRating: ratingTrack.rating,
                    onRatingChanged: onRatingChanged, // Pass the callback down
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
}
