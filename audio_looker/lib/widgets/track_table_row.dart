import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:waux/services/collection_service.dart';
import 'package:waux/widgets/waveform_painter.dart';
import 'package:waux/blocs/audio_player/audio_player_bloc.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

// --- Widget for the first cell (Waveform + Play Button) ---
// lib/widgets/track_table_row.dart (Relevant part)

// --- Widget for the first cell (Waveform + Play Button) ---
class WaveformPreviewCell extends StatelessWidget {
  final Track track;
  final bool
  isSelected; // Keep for potential future styling based on row selection
  final VoidCallback onPlayPreview; // Callback to handle play action

  const WaveformPreviewCell({
    Key? key,
    required this.track,
    required this.isSelected,
    required this.onPlayPreview, // Ensure this is required
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final Color waveColor = Colors.grey.shade300; // Simplified color
    final Color inactiveColor = Colors.grey.shade800; // Simplified color

    return Row(
      children: [
        // Play Button
        IconButton(
          icon: Icon(
            Icons.play_circle_outline,
            color: Theme.of(context).colorScheme.primary, // Use theme color
            size: 20,
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          tooltip: 'Preview ${track.title}',
          // *** Ensure onPressed calls the callback ***
          onPressed: onPlayPreview,
        ),
        const SizedBox(width: 8),
        // Waveform Preview (rest of the code remains the same)
        Expanded(
          child: SizedBox(
            height: 24,
            child:
                (track.waveformData != null && track.waveformData!.isNotEmpty)
                    ? CustomPaint(
                      size: Size.infinite,
                      painter: WaveformPainter(
                        waveformData: track.waveformData!,
                        // Use less prominent colors for preview
                        activeColor: Theme.of(
                          context,
                        ).colorScheme.primary.withOpacity(0.6),
                        inactiveColor: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.2),
                        playbackProgress: 0,
                      ),
                    )
                    : Container(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.1),
                      height: 1,
                    ),
          ),
        ),
      ],
    );
  }
}

// The TrackTableRow widget itself can likely be removed if not used elsewhere,
// as TrackDataSource now builds the cells directly.

// --- Widget representing a single row in the data table ---
class TrackTableRow extends StatelessWidget {
  final Track track;
  final bool isSelected;
  final VoidCallback onTap; // For selection
  final VoidCallback onSecondaryTap; // For context menu
  final VoidCallback onPlayPreview; // Passed down to the cell

  const TrackTableRow({
    Key? key,
    required this.track,
    required this.isSelected,
    required this.onTap,
    required this.onSecondaryTap,
    required this.onPlayPreview,
    // TODO: Add parameters for visible columns later
  }) : super(key: key);

  DataGridRow buildTrackTableRow(Track track) {
    // The data for the draggable is the track's file path
    final String draggableData = track.path;

    // Feedback widget shown while dragging
    final Widget feedbackWidget = Material(
      // Wrap in Material for theme styles
      elevation: 4.0, // Add shadow
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey.shade300, // Simple background
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          track.title, // Show filename while dragging
          style: const TextStyle(fontSize: 14),
        ),
      ),
    );

    // Widget shown underneath the feedback widget at the original position
    final Widget childWhenDragging = Container(
      // Optional: Style the placeholder differently
      // color: Colors.grey.withOpacity(0.3),
      // child: Center(child: Text('...')), // Placeholder content
    );

    return DataGridRow(
      cells: [
        // --- Make the first cell (or the whole row conceptually) draggable ---
        DataGridCell<Track>(
          columnName: 'filename',
          value: track,
          // Wrap the cell content (e.g., Text) in Draggable
          // Note: Syncfusion DataGrid cells expect specific Widget types sometimes.
          // A common approach is to wrap the *content* of the cell.
          // If wrapping the cell directly causes issues, you might need a custom cell renderer
          // or wrap the entire Row widget if possible (depends on DataGrid structure).
          // Let's try wrapping the content displayed within the cell.
          // ASSUMPTION: The cell typically displays a Text widget.
          // We need to wrap this Text widget. This often happens within the
          // DataGridSource's buildRow method or a custom cell renderer.

          // --- IMPORTANT MODIFICATION ---
          // The actual wrapping needs to happen where the cell's widget is built.
          // This usually occurs in your `TrackDataSource.buildRow` method or
          // if you are using `DataGridSource.buildRow`.

          // Let's assume your DataGridSource builds the cell like this:
          // case 'filename':
          //   return Container( // Or whatever widget holds the text
          //     padding: EdgeInsets.all(8.0),
          //     alignment: Alignment.centerLeft,
          //     child: Text(track.fileName), // The widget to wrap
          //   );

          // You would modify that part in TrackDataSource to include Draggable:
          /*
        case 'filename':
           return Draggable<String>(
             data: draggableData, // The track path
             feedback: feedbackWidget,
             childWhenDragging: Container( // Placeholder for the cell content
                 padding: EdgeInsets.all(8.0),
                 alignment: Alignment.centerLeft,
                 child: Text(track.fileName, style: TextStyle(color: Colors.grey))), // Dimmed original
             child: Container( // The actual cell content when not dragging
               padding: EdgeInsets.all(8.0),
               alignment: Alignment.centerLeft,
               child: Text(track.fileName),
             ),
           );
        */
          // For now, we just set the value here. The Draggable logic needs to be
          // implemented in the DataGridSource's build method for the 'filename' column.
        ),
        DataGridCell<String>(columnName: 'artist', value: track.artist),
        DataGridCell<String>(columnName: 'album', value: track.album),
        // DataGridCell<String>(columnName: 'genre', value: track.genre),
        // DataGridCell<int>(columnName: 'year', value: track.year),
        DataGridCell<int>(columnName: 'rating', value: track.rating),
        DataGridCell<Track>(
          columnName: 'preview',
          value: track,
        ), // For preview widget
        DataGridCell<List<String>>(
          columnName: 'tags',
          value: track.generalTags, // Use the correct List<String> field
        ),
        // Add other cells as needed
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Define cell padding for consistency
    const cellPadding = EdgeInsets.symmetric(horizontal: 8.0, vertical: 10.0);
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      onSecondaryTap: onSecondaryTap, // Use secondary tap for right-click
      child: Container(
        decoration: BoxDecoration(
          color:
              isSelected
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.15)
                  : null,
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            // --- Column 1: Waveform Preview & Play (Fixed Width) ---
            Container(
              width: 150, // Example fixed width
              padding: cellPadding,
              child: WaveformPreviewCell(
                track: track,
                isSelected: isSelected,
                onPlayPreview: onPlayPreview,
              ),
            ),

            // --- Column 2: Title (Flexible Width) ---
            Expanded(
              flex: 3, // Give title more space
              child: Container(
                padding: cellPadding,
                child: Text(
                  track.title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),

            // --- Column 3: Artist (Flexible Width) ---
            Expanded(
              flex: 2,
              child: Container(
                padding: cellPadding,
                child: Text(
                  track.artist,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: textTheme.bodySmall?.color),
                ),
              ),
            ),

            // --- Column 4: Album (Flexible Width) ---
            Expanded(
              flex: 2,
              child: Container(
                padding: cellPadding,
                child: Text(
                  track.album,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: textTheme.bodySmall?.color),
                ),
              ),
            ),

            // --- Column 5: Rating (Fixed Width) ---
            Container(
              width: 100, // Example fixed width
              padding: cellPadding,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  5,
                  (index) => Icon(
                    index < track.rating ? Icons.star : Icons.star_border,
                    size: 14,
                    color: index < track.rating ? Colors.amber : Colors.grey,
                  ),
                ),
              ),
            ),

            // --- Column 6: Tags (Flexible Width) ---
            Expanded(
              flex: 2, // Adjust flex as needed
              child: Container(
                padding: cellPadding,
                child:
                    track.generalTags.isEmpty
                        ? null // Show nothing if no tags
                        : Wrap(
                          // Use Wrap to handle multiple tags
                          spacing: 4.0, // Horizontal space between chips
                          runSpacing:
                              2.0, // Vertical space between lines of chips
                          children:
                              track.generalTags.map((tag) {
                                // Basic chip styling, colors can be added later if needed
                                return Chip(
                                  label: Text(tag),
                                  labelStyle: const TextStyle(fontSize: 10),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 0,
                                  ),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.secondary.withOpacity(0.1),
                                  side: BorderSide.none,
                                );
                              }).toList(),
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
