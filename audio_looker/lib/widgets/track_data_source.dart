import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:audio_looker/services/collection_service.dart'; // Your Track model
import 'package:audio_looker/widgets/rating_cell_widget.dart'; // Reuse the cell widget
import 'package:audio_looker/widgets/preview_cell_widget.dart'; // Reuse the cell widget
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:audio_looker/blocs/audio_player/audio_player_bloc.dart'; // Import AudioPlayerBloc

// Add these typedefs for clarity
typedef PlayPreviewCallback = void Function(Track track);
typedef RatingChangeCallback = void Function(int trackId, int newRating);
typedef PlayAndMinimizeCallback = void Function(Track track);

class TrackDataSource extends DataGridSource {
  /// Creates the track data source class with required details.
  TrackDataSource({
    required List<Track> trackData,
    required AudioPlayerBloc audioPlayerBloc,
    required this.onRatingChanged,
    required this.onPlayPreviewAndMinimize, // Callback for play/edit button
  }) : _audioPlayerBloc = audioPlayerBloc {
    _trackData = trackData;
    _updateDataGridRows();
  }

  final AudioPlayerBloc _audioPlayerBloc;
  List<DataGridRow> _dataGridRows = [];
  List<Track> _trackData = [];
  final RatingChangeCallback onRatingChanged;
  final PlayAndMinimizeCallback onPlayPreviewAndMinimize; // Store callback

  // --- State Management for Hover ---
  final Map<int, bool> _rowHoverState = {};
  int? _currentlyHoveredTrackId; // Track the currently hovered row ID
  // --- End State Management ---

  // --- Method to update hover state externally ---
  void setHoverState(int? trackId, bool isHovering) {
    bool changed = false;
    int? previousHoveredTrackId = _currentlyHoveredTrackId;

    // Use trackId directly if provided, otherwise use _currentlyHoveredTrackId for exit logic
    int? targetTrackId = trackId ?? _currentlyHoveredTrackId;
    if (targetTrackId == null) return; // No track ID to act upon

    if (isHovering) {
      // Hover Enter
      if (_currentlyHoveredTrackId != targetTrackId) {
        // Clear previous hover state if different row
        if (_currentlyHoveredTrackId != null) {
          _rowHoverState[_currentlyHoveredTrackId!] = false;
          // Ensure previousHoveredTrackId is set for notification below
          previousHoveredTrackId = _currentlyHoveredTrackId;
        }
        // Set new hover state
        _rowHoverState[targetTrackId] = true;
        _currentlyHoveredTrackId = targetTrackId;
        changed = true;
      }
    } else {
      // Hover Exit (only clear if exiting the currently hovered row)
      if (_currentlyHoveredTrackId == targetTrackId) {
        _rowHoverState[targetTrackId] = false;
        _currentlyHoveredTrackId = null;
        changed = true;
        // Ensure previousHoveredTrackId is set for notification below
        previousHoveredTrackId = targetTrackId;
      }
      // No need for the trackId == null check here, as exit from a specific cell handles it
    }

    if (changed) {
      try {
        // Notify listeners about the change
        // Using the basic notifyListeners as the optimized version had issues
        notifyListeners();
      } catch (e) {
        debugPrint("Error notifying hover listeners: $e");
        notifyListeners(); // Fallback
      }
    }
  }
  // --- End Method ---

  // Method to update the underlying data and refresh the grid rows
  void updateDataGridSource({required List<Track> trackData}) {
    _trackData = trackData;
    _updateDataGridRows();
    // Clear hover states when data source updates
    _rowHoverState.clear();
    _currentlyHoveredTrackId = null;
    try {
      // Use WidgetsBinding to ensure notifyListeners is called safely
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (rows.isNotEmpty) {
          notifyListeners();
        }
      });
    } catch (e) {
      debugPrint("Error scheduling notifyListeners in TrackDataSource: $e");
    }
  }

  // Helper to build the DataGridRow list from the track data
  void _updateDataGridRows() {
    _dataGridRows =
        _trackData.map<DataGridRow>((track) {
          final trackId = track.id ?? -1;
          // Map track data to DataGridCells
          return DataGridRow(
            cells: [
              DataGridCell<int>(columnName: 'id', value: trackId),
              DataGridCell<Track>(columnName: 'preview', value: track),
              DataGridCell<String>(columnName: 'title', value: track.title),
              DataGridCell<String>(columnName: 'artist', value: track.artist),
              DataGridCell<String>(columnName: 'album', value: track.album),
              DataGridCell<Track>(columnName: 'rating', value: track),
              // The 'tags' cell now just holds the track, the widget building happens in buildRow
              DataGridCell<Track>(columnName: 'tags', value: track),
            ],
          );
        }).toList();
  }

  // --- DataGridSource Overrides ---

  @override
  List<DataGridRow> get rows => _dataGridRows;

  @override
  DataGridRowAdapter? buildRow(DataGridRow row) {
    // --- Find the Track object for this row ---
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
      return null; // Return null if track not found
    }
    // --- End Track object finding ---

    if (track == null) return null;

    // Data to be dragged (the track's file path)
    final String draggableData = track.path;

    // Get hover state for this specific row from the map
    final bool isHovering = _rowHoverState[trackId] ?? false;

    // Generate the list of cell widgets using the isHovering state
    List<Widget> cellWidgets =
        row.getCells().map<Widget>((dataGridCell) {
          Widget cellContent; // Widget to hold the actual cell content

          // --- Cell Rendering Logic ---
          switch (dataGridCell.columnName) {
            case 'id':
              cellContent = const SizedBox.shrink(); // Hide ID column visually
              break; // IMPORTANT: Added break statement

            case 'preview':
              // Use the existing PreviewCellWidget
              cellContent = PreviewCellWidget(
                track: track!, // Use track! (safe due to null check above)
                audioPlayerBloc: _audioPlayerBloc,
                onPlayAndMinimize: () => onPlayPreviewAndMinimize(track!),
              );
              break; // IMPORTANT: Added break statement

            case 'title':
              // --- WRAP 'title' CELL WITH DRAGGABLE ---
              cellContent = Draggable<String>(
                data: draggableData,
                feedback: Material(
                  // Ensure Material widget for theme context
                  elevation: 4.0,
                  child: Builder(
                    builder: (BuildContext context) {
                      // Explicitly name the context
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        color: Theme.of(context).colorScheme.primaryContainer,
                        child: Text(
                          track!.title, // Use track!
                          style: TextStyle(
                            fontSize: 14,
                            color:
                                Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                childWhenDragging: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 4.0,
                  ),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    dataGridCell.value.toString(),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade400),
                  ),
                ),
                child: Container(
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
              break; // IMPORTANT: Added break statement
            // --- END DRAGGABLE WRAPPER ---

            case 'rating':
              // Use the existing RatingCellWidget
              cellContent = RatingCellWidget(
                trackId: track!.id!, // Use track!
                currentRating: track.rating,
                onRatingChanged: onRatingChanged,
              );
              break; // IMPORTANT: Added break statement

            case 'tags':
              // --- Modified 'tags' cell to include the hover button ---
              final tags = track!.generalTags; // Use track!
              Widget tagsWidget =
                  tags.isEmpty
                      ? const SizedBox.shrink() // Show nothing if no tags
                      : Wrap(
                        spacing: 4.0,
                        runSpacing: 4.0,
                        children:
                            tags
                                .map(
                                  (tag) => Chip(
                                    label: Text(tag),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 0,
                                    ),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    labelStyle: const TextStyle(fontSize: 11),
                                  ),
                                )
                                .toList(),
                      );

              // Container holding a Row with tags and the conditional button
              cellContent = Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 8.0,
                  vertical: 4.0,
                ),
                child: Builder(
                  builder: (context) {
                    // Use Builder for context
                    return Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween, // Align items
                      children: [
                        Expanded(
                          child: tagsWidget,
                        ), // Tags take available space
                        // --- Conditional Play/Edit Button ---
                        if (isHovering)
                          IconButton(
                            icon: const Icon(Icons.edit),
                            iconSize: 18,
                            color: Theme.of(context).colorScheme.primary,
                            tooltip: 'Edit Metadatas',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            splashRadius: 18,
                            onPressed:
                                () => onPlayPreviewAndMinimize(
                                  track!,
                                ), // Call callback
                          ),
                        // --- End Conditional Button ---
                      ],
                    );
                  },
                ),
              );
              break; // IMPORTANT: Added break statement

            default:
              // Default rendering for other columns (artist, album, etc.)
              cellContent = Container(
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
              break; // IMPORTANT: Added break statement
          }
          // --- End Cell Rendering Logic ---

          // *** Wrap the generated cellContent widget with MouseRegion ***
          return MouseRegion(
            // Use trackId which is guaranteed non-null here
            onEnter: (_) => setHoverState(trackId, true),
            onExit: (_) => setHoverState(trackId, false),
            child: cellContent, // The actual widget for the cell
          );
        }).toList(); // End map

    // Return the DataGridRowAdapter directly.
    return DataGridRowAdapter(
      cells: cellWidgets, // Pass the list of widgets here
    );
  }
}
