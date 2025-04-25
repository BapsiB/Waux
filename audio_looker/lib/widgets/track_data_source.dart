import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:waux/services/collection_service.dart'; // Your Track model
import 'package:waux/widgets/rating_cell_widget.dart'; // Reuse the cell widget
import 'package:waux/widgets/preview_cell_widget.dart'; // Reuse the cell widget
// import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:waux/blocs/audio_player/audio_player_bloc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/services.dart';
// import '../utils/track_filtering.dart'; // Import the filtering utility

// Add these typedefs for clarity
typedef PlayPreviewCallback = void Function(Track track);
typedef RatingChangeCallback = void Function(int trackId, int newRating);
typedef PlayAndMinimizeCallback = void Function(Track track, bool togglePlay);
typedef SelectAndOpenPlayerCallback = void Function(Track track);
typedef SetSearchTextCallback = void Function(String searchText);
typedef GetEditingCellKeyCallback = String? Function();
typedef EndEditingCallback = void Function({String? newValue});

// lib/widgets/track_data_source.dart

class TrackDataSource extends DataGridSource {
  /// Creates the track data source class with required details.
  TrackDataSource({
    required List<Track> trackData,
    required AudioPlayerBloc audioPlayerBloc,
    required this.onRatingChanged,
    required this.onPlayPreviewAndMinimize,
    required this.onEditMetadata,
    required List<String> initialColumnOrder,
    required this.onSetSearchText,
    required this.getEditingCellKey,
    required this.onEndEditing,
    required this.cellEditController,
    required this.cellEditFocusNode,
  }) : _audioPlayerBloc = audioPlayerBloc,
       _currentColumnOrder = List<String>.from(
         initialColumnOrder.where((name) => name != 'id'),
       ) // Store initial order (exclude 'id')
       {
    _trackData = trackData;
    _updateDataGridRows();
  }

  final AudioPlayerBloc _audioPlayerBloc;
  List<DataGridRow> _dataGridRows = [];
  List<Track> _trackData = [];
  final RatingChangeCallback onRatingChanged;
  final PlayAndMinimizeCallback onPlayPreviewAndMinimize;
  final SelectAndOpenPlayerCallback onEditMetadata;
  final SetSearchTextCallback onSetSearchText;
  final GetEditingCellKeyCallback getEditingCellKey;
  final EndEditingCallback onEndEditing;
  final TextEditingController cellEditController;
  final FocusNode cellEditFocusNode;

  final Map<String, bool> _cellHoverState =
      {}; // Use a compound key: "rowId_colName"
  String? _currentlyHoveredCellKey;

  List<String> _currentColumnOrder;

  void updateColumnOrder(List<String> newOrder) {
    // Filter out 'id' if it's present in the new order list
    _currentColumnOrder = List<String>.from(
      newOrder.where((name) => name != 'id'),
    );
    // Important: Notify listeners AFTER updating the order internally
    // This tells the SfDataGrid to request rows again using the new order logic
    notifyListeners();
  }

  // --- State Management for Hover ---
  final Map<int, bool> _rowHoverState = {};
  int? _currentlyHoveredTrackId;

  // --- Updated setHoverState for cells ---
  void setHoverState(String? cellKey, bool isHovering) {
    bool changed = false;
    if (isHovering && cellKey != null) {
      // Hover Enter
      if (_currentlyHoveredCellKey != cellKey) {
        // Clear previous hover state if different cell
        if (_currentlyHoveredCellKey != null) {
          _cellHoverState[_currentlyHoveredCellKey!] = false;
          // No need to track previousHoveredCellKey for rowIndices anymore
        }
        // Set new hover state
        _cellHoverState[cellKey] = true;
        _currentlyHoveredCellKey = cellKey;
        changed = true;
      }
    } else {
      // Hover Exit (only clear if exiting the currently hovered cell)
      if (_currentlyHoveredCellKey != null &&
          _currentlyHoveredCellKey == cellKey) {
        _cellHoverState[_currentlyHoveredCellKey!] = false;
        // No need to track previousHoveredCellKey for rowIndices anymore
        _currentlyHoveredCellKey = null;
        changed = true;
      }
    }

    if (changed) {
      // --- FIXED: Call notifyListeners without arguments ---
      // The grid will determine which rows need updating based on
      // the changed hover state affecting the buildRow output.
      notifyListeners();
    }
  }

  // Method to update the underlying data and refresh the grid rows
  void updateDataGridSource({required List<Track> trackData}) {
    _trackData = trackData;
    _updateDataGridRows();
    // Clear hover states when data source updates
    _rowHoverState.clear();
    _currentlyHoveredTrackId = null;
    try {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Check if the source is still associated with a grid and has listeners
        // *** CORRECTED CHECK HERE ***
        if (hasListeners) {
          // Use the hasListeners getter directly
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
          // --- Keep this structure based on ACTUAL track data ---
          return DataGridRow(
            cells: [
              DataGridCell<int>(
                columnName: 'id',
                value: trackId,
              ), // Keep id cell
              DataGridCell<Track>(columnName: 'preview', value: track),
              DataGridCell<String>(columnName: 'title', value: track.title),
              DataGridCell<String>(columnName: 'artist', value: track.artist),
              DataGridCell<String>(columnName: 'album', value: track.album),
              DataGridCell<Track>(columnName: 'rating', value: track),
              DataGridCell<Track>(columnName: 'tags', value: track),
              DataGridCell<int>(columnName: 'duration', value: track.duration),
              DataGridCell<Track>(columnName: 'source', value: track),
            ],
          );
        }).toList();
  }

  // Helper function to format duration (add this within the class or globally)
  String _formatDuration(int milliseconds) {
    if (milliseconds <= 0) return '--:--'; // Handle zero or negative duration
    final duration = Duration(milliseconds: milliseconds);
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    // Optionally add hours if needed:
    // String hours = duration.inHours > 0 ? '${twoDigits(duration.inHours)}:' : '';
    // return "$hours$twoDigitMinutes:$twoDigitSeconds";
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  // --- DataGridSource Overrides ---

  @override
  List<DataGridRow> get rows => _dataGridRows;

  @override
  DataGridRowAdapter? buildRow(DataGridRow row) {
    // --- Find the Track object for this row (remains the same) ---
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
      return null;
    }
    if (track == null) return null;
    // --- End Track object finding ---

    final String draggableData = track.path;

    // *** MODIFIED: Build cellWidgets list based on _currentColumnOrder ***
    final List<Widget> cellWidgets = [];

    // Create a map of cells from the row for easy lookup by columnName
    final Map<String, DataGridCell> cellMap = {
      for (var cell in row.getCells()) cell.columnName: cell,
    };

    final String? editingKey = getEditingCellKey();

    // Iterate through the CURRENT VISUAL ORDER
    for (final String columnName in _currentColumnOrder) {
      final DataGridCell? dataGridCell = cellMap[columnName];
      Widget cellContent; // Widget to hold the actual cell content
      final cellKey = "${trackId}_$columnName";
      final bool isHovering = _cellHoverState[cellKey] ?? false;
      final bool isEditing = editingKey == cellKey;

      if (dataGridCell == null) {
        // Should not happen if _currentColumnOrder is correct, but handle defensively
        cellContent = SizedBox.shrink();
        print(
          "Warning: Could not find cell for columnName '$columnName' in buildRow",
        );
      } else {
        // --- Cell Rendering Logic (Use existing switch, but apply it to the looked-up cell) ---
        switch (dataGridCell.columnName) {
          // NOTE: 'id' case is removed because we iterate through _currentColumnOrder which excludes 'id'
          case 'preview':
            cellContent = PreviewCellWidget(
              track: track,
              audioPlayerBloc: _audioPlayerBloc,
              onPlayAndMinimize: () => onPlayPreviewAndMinimize(track!, true),
            );
            break;
          case 'title':
          case 'artist':
          case 'album':
            if (isEditing) {
              // --- Show TextField for editing ---
              // Wrap with Builder to get context for Theme
              cellContent = Builder(
                // <<< Wrap TextField's parent or TextField itself
                builder: (context) {
                  // <<< Builder provides the context
                  return RawKeyboardListener(
                    focusNode:
                        FocusNode(), // Local focus node for keyboard listener
                    onKey: (RawKeyEvent event) {
                      if (event is RawKeyDownEvent) {
                        if (event.logicalKey == LogicalKeyboardKey.enter ||
                            event.logicalKey ==
                                LogicalKeyboardKey.numpadEnter) {
                          onEndEditing(newValue: cellEditController.text);
                        } else if (event.logicalKey ==
                            LogicalKeyboardKey.escape) {
                          onEndEditing(); // Cancel edit
                        }
                      }
                    },
                    child: TextField(
                      controller: cellEditController,
                      focusNode: cellEditFocusNode,
                      // autofocus: true,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          vertical: 8.0,
                          horizontal: 2.0,
                        ),
                        border: OutlineInputBorder(borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(
                          // *** Use context from Builder ***
                          borderSide: BorderSide(
                            color: Theme.of(context).primaryColor,
                            width: 1.0,
                          ),
                        ),
                      ),

                      style: TextStyle(fontSize: 13), // Match text style
                      onSubmitted: (newValue) {
                        onEndEditing(newValue: newValue);
                      },
                      // Optional: Handle focus loss to save/cancel
                      // onEditingComplete: () {
                      //    // This might be called too often, onSubmitted is usually better
                      //    // Check if focus is truly lost before calling onEndEditing
                      //    if (!cellEditFocusNode.hasFocus) {
                      //       onEndEditing(newValue: cellEditController.text);
                      //    }
                      // },
                    ),
                  );
                },
              );
            } else {
              // --- Show regular Text or Draggable Text ---
              final String cellValue = dataGridCell.value?.toString() ?? '';
              Widget textWidget = Text(
                cellValue,
                overflow: TextOverflow.ellipsis,
                // Apply any specific styling if needed
              );

              if (columnName == 'title') {
                // Wrap title in Draggable
                cellContent = Draggable<String>(
                  data: draggableData,
                  feedback: Material(/* ... existing feedback ... */),
                  childWhenDragging: Container(
                    /* ... existing placeholder ... */
                  ),
                  child: Container(
                    // Container needed for Draggable child
                    alignment: Alignment.centerLeft, // Ensure alignment
                    // padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0), // Padding handled by outer container
                    child: textWidget,
                  ),
                );
              } else {
                // For Artist/Album, add hover filter icon logic
                final String fieldName = columnName;
                cellContent = Row(
                  children: [
                    Expanded(child: textWidget),
                    const SizedBox(width: 4),
                    if (isHovering && cellValue.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.filter_alt_outlined),
                        iconSize: 20,
                        onPressed: () {
                          final filterValue =
                              cellValue.contains(' ')
                                  ? '"$cellValue"'
                                  : cellValue;

                          final filterString = '$fieldName:$filterValue';
                          onSetSearchText(filterString);
                        },
                      )
                    else
                      const SizedBox(width: 30), // Placeholder
                  ],
                );
              }
            }
            break;
          case 'source':
            final Track sourceTrack = dataGridCell.value as Track;
            IconData iconData;
            Color? defaultIconColor;
            String tooltip;
            switch (sourceTrack.sourceType) {
              case TrackSource.local:
                iconData = Icons.music_note_outlined;
                tooltip = 'Local File';
                break;
              case TrackSource.url:
                iconData = Icons.link;
                tooltip = 'Web URL';
                break;
              case TrackSource.youtube:
                iconData = FontAwesomeIcons.youtube;
                defaultIconColor = Colors.red;
                tooltip = 'YouTube';
                break;
            }
            cellContent = Builder(
              builder: (context) {
                final Color iconColor =
                    defaultIconColor ??
                    Theme.of(context).colorScheme.onSurfaceVariant;
                return Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Tooltip(
                    message: tooltip,
                    child: FaIcon(iconData, size: 16, color: iconColor),
                  ),
                );
              },
            );
            break;
          case 'duration':
            cellContent = Container(
              alignment: Alignment.centerRight, // Align numeric data right
              padding: EdgeInsets.symmetric(
                horizontal: 8.0,
                vertical: isEditing ? 0.0 : 4.0,
              ),
              child: Text(
                _formatDuration(dataGridCell.value as int? ?? 0),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ), // Adjust style
              ),
            );
            break;
          case 'rating':
            cellContent = RatingCellWidget(
              trackId: track.id!,
              currentRating: track.rating,
              onRatingChanged: onRatingChanged,
            );
            break;
          case 'tags':
            final tags = track.generalTags;
            Widget tagsWidget =
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
            cellContent = Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(
                horizontal: 8.0,
                vertical: 4.0,
              ),
              child: Builder(
                builder: (context) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: tagsWidget),
                      if (isHovering)
                        IconButton(
                          icon: const Icon(Icons.edit),
                          iconSize: 18,
                          color: Theme.of(context).colorScheme.primary,
                          tooltip: 'Edit Metadatas',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          splashRadius: 18,
                          onPressed: () => onEditMetadata(track!),
                        ),
                    ],
                  );
                },
              ),
            );
            break;
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
            break;
        }
      }
      // Wrap the cell content with MouseRegion and alignment container
      cellWidgets.add(
        MouseRegion(
          // <<< MouseRegion is now the outer wrapper
          onEnter: (_) => setHoverState(cellKey, true),
          onExit: (_) => setHoverState(cellKey, false),
          child: Container(
            // Container provides padding and alignment
            alignment:
                (columnName == 'duration')
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: cellContent, // The actual cell content (Row, Text, etc.)
          ),
        ),
      );
    } // End for loop through _currentColumnOrder

    // Return the DataGridRowAdapter with cells in the correct visual order.
    return DataGridRowAdapter(cells: cellWidgets);
  }
}
