import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:audio_looker/services/collection_service.dart'; // Your Track model
import 'package:audio_looker/widgets/track_table_row.dart';
import 'package:audio_looker/widgets/rating_cell_widget.dart'; // Reuse the cell widget
import 'package:audio_looker/widgets/preview_cell_widget.dart'; // Reuse the cell widget
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:audio_looker/blocs/audio_player/audio_player_bloc.dart'; // Import AudioPlayerBloc

// Add these typedefs for clarity
typedef PlayPreviewCallback = void Function(Track track);
typedef RatingChangeCallback = void Function(int trackId, int newRating);

class TrackDataSource extends DataGridSource {
  /// Creates the track data source class with required details.
  TrackDataSource({
    // removed BuildContext context,
    required List<Track> trackData,
    required AudioPlayerBloc audioPlayerBloc, // *** Use regular parameter ***
    required this.onRatingChanged,
  }) : _audioPlayerBloc = audioPlayerBloc {
    // *** Initialize private field ***
    _trackData = trackData;
    _updateDataGridRows(); // Initial population
  }

  // removed final BuildContext _context;
  final AudioPlayerBloc _audioPlayerBloc; // *** Keep private field ***
  List<DataGridRow> _dataGridRows = [];
  List<Track> _trackData = [];
  final RatingChangeCallback onRatingChanged;

  // Method to update the underlying data and refresh the grid rows
  void updateDataGridSource({required List<Track> trackData}) {
    _trackData = trackData;
    _updateDataGridRows();
    try {
      notifyListeners();
    } catch (e) {
      debugPrint("Error notifying listeners in TrackDataSource: $e");
    }
  }

  // Helper to build the DataGridRow list from the track data
  void _updateDataGridRows() {
    _dataGridRows =
        _trackData.map<DataGridRow>((track) {
          final trackId = track.id ?? -1;
          return DataGridRow(
            cells: [
              DataGridCell<int>(columnName: 'id', value: trackId),
              DataGridCell<Track>(columnName: 'preview', value: track),
              DataGridCell<String>(columnName: 'title', value: track.title),
              DataGridCell<String>(columnName: 'artist', value: track.artist),
              DataGridCell<String>(columnName: 'album', value: track.album),
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

  // lib/widgets/track_data_source.dart (Inside TrackDataSource class's buildRow method)

  @override
  DataGridRowAdapter? buildRow(DataGridRow row) {
    // --- Find the Track object for this row ---
    // (Your logic to get the track object might differ slightly)
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
      // Assumes _trackData holds the list of tracks for the data source
      track = _trackData.firstWhere((t) => t.id == trackId);
    } catch (e) {
      debugPrint("Track with ID $trackId not found in buildRow.");
      return null; // Return null if track not found
    }
    // --- End Track object finding ---

    // Ensure track is not null before proceeding
    if (track == null) {
      debugPrint("Track object is null for ID $trackId, cannot build row.");
      return null;
    }

    // Data to be dragged (the track's file path)
    final String draggableData =
        track.path; // Use 'path' or 'filePath' depending on your Track model

    // ----- REMOVE feedbackWidget definition from here -----

    return DataGridRowAdapter(
      cells:
          row.getCells().map<Widget>((dataGridCell) {
            // Decide which column initiates the drag (e.g., 'title')
            if (dataGridCell.columnName == 'title') {
              // --- WRAP THIS CELL'S CONTENT WITH DRAGGABLE ---
              return Draggable<String>(
                data: draggableData, // The track path is the data being dragged
                // ----- DEFINE feedbackWidget HERE using Builder or accessing context directly -----
                // Option 1: Direct access (often works if Draggable is built in a context-aware part)
                feedback: Material(
                  // Use Material for proper theme application
                  elevation: 4.0,
                  // *** Now you can access context here ***
                  child: Builder(
                    // Use Builder to ensure context is available
                    builder: (context) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        color:
                            Theme.of(
                              context,
                            ).colorScheme.primaryContainer, // Access theme here
                        child: Text(
                          track!
                              .title, // Show title while dragging (use track!)
                          style: TextStyle(
                            fontSize: 14,
                            color:
                                Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer, // Access theme here
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // ----- END feedbackWidget definition -----
                childWhenDragging: Container(
                  // Appearance of the original cell while dragging
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 4.0,
                  ),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    dataGridCell.value.toString(),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey.shade400,
                    ), // Dimmed text
                  ),
                ),
                child: Container(
                  // The actual cell content when not dragging
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 4.0,
                  ),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    dataGridCell.value.toString(),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
              // --- END DRAGGABLE WRAPPER ---
            } else {
              // --- Render other cells as before ---
              // (Your existing switch statement for other columns)
              switch (dataGridCell.columnName) {
                // ... cases for 'id', 'preview', 'rating', 'tags', default ...
                case 'id':
                  return const SizedBox.shrink(); // Hide ID column visually
                case 'preview':
                  final Track? cellTrack = dataGridCell.value as Track?;
                  if (cellTrack == null) return const SizedBox.shrink();
                  return PreviewCellWidget(
                    track: cellTrack,
                    audioPlayerBloc: _audioPlayerBloc,
                  );
                case 'rating':
                  final Track? ratingTrack = dataGridCell.value as Track?;
                  if (ratingTrack == null || ratingTrack.id == null)
                    return const SizedBox.shrink();
                  return RatingCellWidget(
                    trackId: ratingTrack.id!,
                    currentRating: ratingTrack.rating,
                    onRatingChanged: onRatingChanged,
                  );
                case 'tags':
                  final tags =
                      dataGridCell.value as List<String>? ??
                      []; // Ensure it's List<String>
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
                                      .map((tag) => Chip(label: Text(tag)))
                                      .toList(),
                            ),
                  );
                default:
                  // Default rendering for other columns (artist, album, etc.)
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
            }
          }).toList(),
    );
  }
}
