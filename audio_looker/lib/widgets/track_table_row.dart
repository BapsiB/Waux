import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:audio_looker/services/collection_service.dart';
import 'package:audio_looker/widgets/waveform_painter.dart';
import 'package:audio_looker/blocs/audio_player/audio_player_bloc.dart'; // Needed for play button

// --- Widget for the first cell (Waveform + Play Button) ---
class WaveformPreviewCell extends StatelessWidget {
  final Track track;
  final bool isSelected;
  final VoidCallback onPlayPreview; // Callback to handle play action

  const WaveformPreviewCell({
    Key? key,
    required this.track,
    required this.isSelected,
    required this.onPlayPreview,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Determine colors based on selection
    final Color waveColor = isSelected
        ? Theme.of(context).colorScheme.onPrimary // Color on selected background
        : Theme.of(context).colorScheme.primary; // Default color
    final Color inactiveColor = isSelected
        ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
        : Colors.grey.shade300; // Lighter grey for inactive

    return Row(
      children: [
        // Play Button
        IconButton(
          icon: Icon(
            Icons.play_circle_outline,
            color: isSelected ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.primary,
            size: 20,
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          tooltip: 'Preview ${track.title}',
          onPressed: onPlayPreview,
        ),
        const SizedBox(width: 8),
        // Waveform Preview
        Expanded(
          child: Container(
            height: 24, // Keep it compact
            child: (track.waveformData != null && track.waveformData!.isNotEmpty)
                ? CustomPaint(
                    size: Size.infinite,
                    painter: WaveformPainter(
                      waveformData: track.waveformData!,
                      activeColor: waveColor,
                      inactiveColor: inactiveColor,
                      playbackProgress: 0, // No progress shown in preview
                      // Optional: simplify painter further for performance if needed
                    ),
                  )
                : Container( // Placeholder if no waveform
                    color: inactiveColor.withOpacity(0.5),
                    height: 1,
                  ),
          ),
        ),
      ],
    );
  }
}


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

  @override
  Widget build(BuildContext context) {
    // Define cell padding for consistency
    const cellPadding = EdgeInsets.symmetric(horizontal: 8.0, vertical: 10.0);

    return InkWell(
      onTap: onTap,
      onSecondaryTap: onSecondaryTap, // Use secondary tap for right-click
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).colorScheme.primary.withOpacity(0.15) : null,
          border: Border(
            bottom: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
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
                  style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
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
                  style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color),
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
                  style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color),
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
             // TODO: Add Tags column later
          ],
        ),
      ),
    );
  }
}
