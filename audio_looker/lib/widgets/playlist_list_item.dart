// lib/widgets/playlist_list_item.dart

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/playlist/playlist_bloc.dart';
import '../models/playlist.dart';

/// Represents a single item in the playlist drawer.
/// Handles displaying playlist info, drag targeting, and context menu actions.
class PlaylistListItem extends StatefulWidget {
  final Playlist playlist;

  const PlaylistListItem({super.key, required this.playlist});

  @override
  State<PlaylistListItem> createState() => _PlaylistListItemState();
}

class _PlaylistListItemState extends State<PlaylistListItem> {
  bool _isHovering = false; // Track hover state for visual feedback
  bool _isDraggingOver = false; // Track drag-over state for visual feedback
  final TextEditingController _renameController = TextEditingController();
  Offset _tapPosition = Offset.zero; // Store tap position for context menu

  // Store tap position to show context menu nearby
  void _storePosition(TapDownDetails details) {
    _tapPosition = details.globalPosition;
  }

  // --- Context Menu ---
  void _showContextMenu(BuildContext context) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        // Position the menu close to the tap position
        _tapPosition & const Size(40, 40), // Small rectangle at tap pos
        Offset.zero & overlay.size, // Bigger rectangle of the overlay
      ),
      items: <PopupMenuEntry>[
        PopupMenuItem(
          onTap: () => _showRenameDialog(context, widget.playlist),
          child: const ListTile(
            leading: Icon(Icons.edit),
            title: Text('Rename'),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          onTap: () => _showDeleteConfirmation(context, widget.playlist.id),
          child: const ListTile(
            leading: Icon(Icons.delete, color: Colors.red),
            title: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ),
      ],
    );
  }

  // --- Rename Dialog ---
  void _showRenameDialog(BuildContext context, Playlist playlist) {
    _renameController.text = playlist.name; // Pre-fill with current name
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Rename Playlist'),
          content: TextField(
            controller: _renameController,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Enter new name'),
            onSubmitted: (_) => _submitRename(dialogContext, playlist.id),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              child: const Text('Rename'),
              onPressed: () => _submitRename(dialogContext, playlist.id),
            ),
          ],
        );
      },
    );
  }

  void _submitRename(BuildContext dialogContext, String playlistId) {
    final newName = _renameController.text.trim();
    if (newName.isNotEmpty) {
      context.read<PlaylistBloc>().add(
        RenamePlaylist(playlistId: playlistId, newName: newName),
      );
      Navigator.of(dialogContext).pop(); // Close the dialog
    } else {
      // Show error or feedback if name is empty
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Playlist name cannot be empty.')),
      );
    }
  }

  // --- Delete Confirmation ---
  void _showDeleteConfirmation(BuildContext context, String playlistId) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Delete Playlist?'),
          content: Text(
            'Are you sure you want to delete "${widget.playlist.name}"? This cannot be undone.',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
              onPressed: () {
                context.read<PlaylistBloc>().add(DeletePlaylist(playlistId));
                Navigator.of(dialogContext).pop(); // Close the dialog
                print("Dispatching DeletePlaylist for ID: $playlistId");
              },
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _renameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // DragTarget accepts data of type String (the track path)
    return DragTarget<String>(
      // Called when a draggable enters the target area
      onWillAcceptWithDetails: (details) {
        // You could add logic here to check if the data format is correct
        // For now, we accept any String (assuming it's a track path)
        setState(() => _isDraggingOver = true);
        print(
          "Playlist '${widget.playlist.name}': Draggable entering - ${details.data}",
        );
        return true; // Accept the draggable
      },
      // Called when a draggable leaves the target area
      onLeave: (data) {
        setState(() => _isDraggingOver = false);
        print("Playlist '${widget.playlist.name}': Draggable leaving");
      },
      // Called when a draggable is dropped and accepted
      onAcceptWithDetails: (details) {
        final trackPath = details.data;
        print("Playlist '${widget.playlist.name}': Accepted drop - $trackPath");
        context.read<PlaylistBloc>().add(
          AddTrackToPlaylist(
            playlistId: widget.playlist.id,
            trackPath: trackPath,
          ),
        );
        setState(() => _isDraggingOver = false); // Reset visual state
      },
      // Builds the appearance of the drag target
      builder: (context, candidateData, rejectedData) {
        // Use InkWell for tap feedback and hover effect
        return InkWell(
          onTap: () {
            // TODO: Implement selecting playlist to show its tracks
            print("Tapped on playlist: ${widget.playlist.name}");
          },
          onHover: (hovering) => setState(() => _isHovering = hovering),
          // Use GestureDetector to detect right-clicks (secondary tap)
          child: GestureDetector(
            onTapDown: _storePosition, // Store position for context menu
            onSecondaryTapDown: _storePosition, // Also store for secondary tap
            onSecondaryTap: () => _showContextMenu(context),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 12.0,
              ),
              // Change background color based on hover and drag-over state
              decoration: BoxDecoration(
                color:
                    _isDraggingOver
                        ? Theme.of(context)
                            .colorScheme
                            .primaryContainer // Highlight when dragging over
                        : _isHovering
                        ? Theme.of(context)
                            .hoverColor // Highlight on hover
                        : Colors.transparent, // Default background
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.playlist_play,
                    size: 20,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.playlist.name,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                  // Optionally show track count
                  Text(
                    '(${widget.playlist.trackPaths.length})',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
