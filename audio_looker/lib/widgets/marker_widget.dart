// lib/widgets/marker_widget.dart
import 'package:flutter/material.dart';
import '../services/audio_service.dart'; // For TimeMarker

class MarkerWidget extends StatefulWidget {
  final TimeMarker marker;
  final VoidCallback onPlayFromMarker;
  final VoidCallback? onTapMarker;
  final Color defaultColor;
  final Color hoverColor;
  final double markerLineWidth;
  final double waveformContainerHeight; // <<< ADDED: Need height reference

  const MarkerWidget({
    Key? key,
    required this.marker,
    required this.onPlayFromMarker,
    this.onTapMarker,
    this.defaultColor = Colors.blue,
    this.hoverColor = Colors.purple,
    this.markerLineWidth = 2.0,
    required this.waveformContainerHeight, // <<< ADDED
  }) : super(key: key);

  @override
  State<MarkerWidget> createState() => _MarkerWidgetState();
}

class _MarkerWidgetState extends State<MarkerWidget> {
  bool _isHovering = false;

  // Define dimensions/padding for hovered content
  final double _hoveredContentHeight = 28.0;
  final double _hoveredContentMinWidth = 100.0;
  final EdgeInsets _hoverContentPadding = const EdgeInsets.symmetric(
    horizontal: 4.0,
  );

  @override
  Widget build(BuildContext context) {
    final markerBarColor =
        _isHovering ? widget.hoverColor : widget.defaultColor;

    // --- Interactive Content Widget (Build separately for clarity) ---
    Widget interactiveContent = Material(
      elevation: 4.0,
      borderRadius: BorderRadius.circular(6),
      color: widget.hoverColor.withOpacity(0.95),
      child: InkWell(
        // Use InkWell for tap feedback on the whole hover area
        onTap: widget.onTapMarker ?? widget.onPlayFromMarker,
        borderRadius: BorderRadius.circular(6),
        child: ConstrainedBox(
          // Ensure minimum width
          constraints: BoxConstraints(minWidth: _hoveredContentMinWidth),
          child: Container(
            height: _hoveredContentHeight,
            padding: _hoverContentPadding,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Play Button
                IconButton(
                  icon: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                  ), // Assuming white is good contrast
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Play from "${widget.marker.label}"',
                  onPressed: widget.onPlayFromMarker,
                ),
                const SizedBox(width: 4),
                // Label
                Flexible(
                  child: Text(
                    widget.marker.label,
                    style: const TextStyle(
                      color: Colors.white, // Assuming white is good contrast
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // --- Main Stack ---
    return Stack(
      clipBehavior: Clip.none, // Allow hover content to potentially overflow
      alignment:
          Alignment.topCenter, // Align items at the top center horizontally
      children: [
        // --- Layer 1: The Persistent Vertical Bar ---
        Positioned(
          // Position the bar itself; the Stack alignment handles horizontal centering
          top: 0,
          // left: 0, // Centered by Stack alignment
          // right: 0, // Centered by Stack alignment
          child: MouseRegion(
            onEnter: (_) => setState(() => _isHovering = true),
            onExit: (_) => setState(() => _isHovering = false),
            cursor: SystemMouseCursors.click,
            child: Tooltip(
              // Add tooltip to the bar itself
              message: widget.marker.label,
              child: GestureDetector(
                // Allow clicking the bar itself
                onTap: widget.onTapMarker ?? widget.onPlayFromMarker,
                child: Container(
                  width:
                      widget.markerLineWidth +
                      4, // Make hit area slightly wider
                  height: widget.waveformContainerHeight, // Span full height
                  decoration: BoxDecoration(
                    color: markerBarColor.withOpacity(0.8),
                    // Optional: Add subtle border or different shape
                    // borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),

        // --- Layer 2: The Hover-Activated Interactive Content ---
        // Position it slightly above the bar, centered horizontally relative to the bar
        Positioned(
          // *** REMOVE 'bottom' property ***
          // bottom: widget.waveformContainerHeight - (_hoveredContentHeight / 2) + 8,

          // *** ADD 'top' property ***
          // Position it relative to the top of the Stack.
          // Start with top: 0, adjust as needed (e.g., negative value to go above).
          top: 0,

          // We might need to explicitly center it horizontally if Stack alignment was removed
          // This calculation attempts to center the hover content over the bar
          left:
              -(_hoveredContentMinWidth / 2) +
              ((widget.markerLineWidth + 4) /
                  2), // Center hover box over bar center

          child: IgnorePointer(
            ignoring: !_isHovering,
            child: AnimatedOpacity(
              opacity: _isHovering ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 150),
              child: interactiveContent,
            ),
          ),
        ),
      ],
    );
  }
}
