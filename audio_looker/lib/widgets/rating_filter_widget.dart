import 'package:flutter/material.dart';
import 'dart:math' as math; // For clamp

// Callback type remains the same
typedef RatingFilterCallback = void Function(int? rating);

// Convert to StatefulWidget
class RatingFilterWidget extends StatefulWidget {
  final int? currentMinimumRating;
  final RatingFilterCallback onRatingSelected;
  final double iconSize;
  final EdgeInsets padding;

  const RatingFilterWidget({
    Key? key,
    required this.currentMinimumRating,
    required this.onRatingSelected,
    this.iconSize = 15.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 0),
  }) : super(key: key);

  @override
  _RatingFilterWidgetState createState() => _RatingFilterWidgetState();
}

class _RatingFilterWidgetState extends State<RatingFilterWidget> {
  // State variable to show rating feedback during drag
  int? _dragRating;
  // GlobalKey to get the widget's size for position calculation
  final GlobalKey _widgetKey = GlobalKey();

  // Calculates the rating (0-5) based on horizontal position within the widget
  int _calculateRatingFromPosition(Offset localPosition) {
    final RenderBox? box =
        _widgetKey.currentContext?.findRenderObject() as RenderBox?;
    // Return 0 if size is not available yet
    if (box == null || !box.hasSize || box.size.width <= 0) return 0;

    final widgetWidth = box.size.width;
    // Clamp the x-position to be within the widget bounds
    final positionX = localPosition.dx.clamp(0.0, widgetWidth);

    // Calculate rating based on position. Divide width into 6 segments.
    // The first segment (approx 1/6th of width) corresponds to 0 stars.
    final rating = (positionX / (widgetWidth / 6.0)).floor();

    // Clamp the result between 0 and 5
    return rating.clamp(0, 5);
  }

  @override
  Widget build(BuildContext context) {
    // Wrap the Row of stars with a GestureDetector
    return GestureDetector(
      key: _widgetKey, // Assign key to get size
      // Update visual feedback during drag
      onHorizontalDragUpdate: (details) {
        int calculatedRating = _calculateRatingFromPosition(
          details.localPosition,
        );
        // Update the temporary drag state if it changed
        if (calculatedRating != _dragRating) {
          setState(() {
            _dragRating = calculatedRating;
          });
        }
      },
      // When drag ends, call the callback with the final rating
      onHorizontalDragEnd: (details) {
        // Use the last calculated drag rating
        // Pass null to the callback if rating is 0, otherwise pass the rating
        widget.onRatingSelected(_dragRating);
        // Reset the temporary drag state
        setState(() {
          _dragRating = null;
        });
      },
      // Handle taps as well for quick selection/clearing
      onTapUp: (details) {
        int tappedRating = _calculateRatingFromPosition(details.localPosition);
        int? currentActualRating = widget.currentMinimumRating;

        // If tapped rating is 0, or same as current, clear filter (null)
        if (tappedRating == 0 || tappedRating == currentActualRating) {
          widget.onRatingSelected(null);
        } else {
          // Otherwise, select the tapped rating
          widget.onRatingSelected(tappedRating);
        }
        // Ensure drag state is cleared after tap
        if (_dragRating != null) {
          setState(() {
            _dragRating = null;
          });
        }
      },
      // Use MouseRegion for visual cue on hover
      child: MouseRegion(
        cursor: SystemMouseCursors.click, // Show clickable cursor
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(5, (index) {
            final starValue = index + 1;
            // Determine if star should be filled based on drag state OR actual state
            final ratingToDisplay = _dragRating ?? widget.currentMinimumRating;
            print(
              "ratingToDisplay = $ratingToDisplay, _dragRating = $_dragRating",
            );
            bool isSelected = starValue <= (ratingToDisplay ?? 0);

            return Padding(
              padding: widget.padding,
              child: Icon(
                isSelected ? Icons.star : Icons.star_border,
                color: isSelected ? Colors.amber : Colors.grey[500],
                size: widget.iconSize,
              ),
            );
          }),
        ),
      ),
    );
  }
}
