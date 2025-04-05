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
      track = _trackData.firstWhere((t) => t.id == trackId);
    } catch (e) {
      debugPrint("Track with ID $trackId not found in buildRow.");
      return null;
    }

    // Removed context lookup

    return DataGridRowAdapter(
      cells:
          row.getCells().map<Widget>((dataGridCell) {
            switch (dataGridCell.columnName) {
              case 'id':
                return const SizedBox.shrink();
              case 'preview':
                final Track? cellTrack = dataGridCell.value as Track?;
                if (cellTrack == null) return const SizedBox.shrink();
                return Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (_) {}, // Absorb pointer event
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4.0,
                      vertical: 4.0,
                    ),
                    alignment: Alignment.centerLeft,
                    // Pass the stored bloc instance directly
                    child: PreviewCellWidget(
                      track: cellTrack,
                      audioPlayerBloc: _audioPlayerBloc,
                    ),
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
                final Track? ratingTrack = dataGridCell.value as Track?;
                if (ratingTrack == null || ratingTrack.id == null)
                  return const SizedBox.shrink();
                return Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (_) {}, // Absorb pointer event
                  child: Container(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 4.0,
                    ),
                    child: RatingCellWidget(
                      // RatingCellWidget does NOT get the bloc
                      trackId: ratingTrack.id!,
                      currentRating: ratingTrack.rating,
                      onRatingChanged: onRatingChanged,
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

  // Removed _getBuildContextFromSomewhere()
}
