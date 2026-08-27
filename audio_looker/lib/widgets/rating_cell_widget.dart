import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:waux/services/collection_service.dart';
import 'package:waux/widgets/track_table_row.dart'
    show WaveformPreviewCell; // Reuse the cell widget

// Add these typedefs for clarity
typedef PlayPreviewCallback = void Function(Track track);
typedef RatingChangeCallback = void Function(int trackId, int newRating);

// --- New StatefulWidget for Rating Cell ---
class RatingCellWidget extends StatefulWidget {
  final int trackId;
  final int currentRating;
  final RatingChangeCallback onRatingChanged;

  const RatingCellWidget({
    Key? key,
    required this.trackId,
    required this.currentRating,
    required this.onRatingChanged,
  }) : super(key: key);

  @override
  _RatingCellWidgetState createState() => _RatingCellWidgetState();
}

class _RatingCellWidgetState extends State<RatingCellWidget> {
  int _hoverRating = 0; // 0 means no hover

  @override
  Widget build(BuildContext context) {
    // Use MouseRegion to detect hover over the entire rating area
    return MouseRegion(
      onEnter: (_) {
        // Optional: Can add logic here if needed when entering the general area
      },
      onExit: (_) {
        // Reset hover state when mouse leaves the entire rating area
        if (mounted) {
          // Check if the widget is still in the tree
          setState(() {
            _hoverRating = 0;
          });
        }
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (index) {
          final ratingValue = index + 1;
          bool isHovered = ratingValue <= _hoverRating;
          bool isSelected = ratingValue <= widget.currentRating;

          IconData iconData;
          Color iconColor;

          if (_hoverRating > 0) {
            // Hover state is active
            iconData = isHovered ? Icons.star : Icons.star_border;
            // Use a distinct hover color (e.g., white or light grey)
            iconColor = isHovered ? Colors.white70 : Colors.grey.shade600;
          } else {
            // No hover state, show current rating
            iconData = isSelected ? Icons.star : Icons.star_border;
            iconColor =
                isSelected ? Colors.amber.shade600 : Colors.grey.shade500;
          }

          // Wrap each IconButton in its own MouseRegion to track hover per star
          return MouseRegion(
            onEnter: (_) {
              if (mounted) {
                setState(() {
                  _hoverRating = ratingValue;
                });
              }
            },
            // onExit is handled by the parent MouseRegion
            child: IconButton(
              icon: Icon(iconData, size: 16, color: iconColor),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              splashRadius: 12, // Smaller splash radius
              onPressed:
                  () => widget.onRatingChanged(widget.trackId, ratingValue),
            ),
          );
        }),
      ),
    );
  }
}
