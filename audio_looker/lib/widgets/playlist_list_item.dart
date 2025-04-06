// lib/widgets/playlist_list_item.dart

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/playlist/playlist_bloc.dart';
import '../models/playlist.dart';

/// Represents a single item in the playlist drawer.
class PlaylistListItem extends StatefulWidget {
  final Playlist playlist;
  // *** ADD properties for selection state and callback ***
  final bool isSelected;
  final ValueChanged<String> onTap;

  const PlaylistListItem({
    super.key,
    required this.playlist,
    required this.isSelected, // Required
    required this.onTap, // Required
  });

  @override
  State<PlaylistListItem> createState() => _PlaylistListItemState();
}

class _PlaylistListItemState extends State<PlaylistListItem> {
  bool _isHovering = false;
  bool _isDraggingOver = false;
  final TextEditingController _renameController = TextEditingController();
  Offset _tapPosition = Offset.zero;

  // ... existing methods (_storePosition, _showContextMenu, _showRenameDialog, _submitRename, _showDeleteConfirmation) ...
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
                // *** Also deselect if deleting the selected playlist ***
                // Read the current selected ID from HomeScreen state (might need context access or callback)
                // For simplicity, PlaylistBloc could handle deselecting, or HomeScreen listens to PlaylistBloc state changes.
                // Let's assume deselect logic happens in HomeScreen's listener for now.
                context.read<PlaylistBloc>().add(DeletePlaylist(playlistId));
                Navigator.of(dialogContext).pop();
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
      onWillAcceptWithDetails: (details) {
        setState(() => _isDraggingOver = true);
        return true;
      },
      onLeave: (data) {
        setState(() => _isDraggingOver = false);
      },
      onAcceptWithDetails: (details) {
        final trackPath = details.data;
        context.read<PlaylistBloc>().add(
          AddTrackToPlaylist(
            playlistId: widget.playlist.id,
            trackPath: trackPath,
          ),
        );
        setState(() => _isDraggingOver = false);
      },
      builder: (context, candidateData, rejectedData) {
        // *** Determine background color based on selection, drag, and hover ***
        Color backgroundColor = Colors.transparent;
        if (widget.isSelected) {
          backgroundColor = Theme.of(
            context,
          ).colorScheme.primary.withOpacity(0.2);
        } else if (_isDraggingOver) {
          backgroundColor = Theme.of(
            context,
          ).colorScheme.primaryContainer.withOpacity(0.5);
        } else if (_isHovering) {
          backgroundColor = Theme.of(context).hoverColor;
        }

        // Use InkWell for tap feedback and hover effect
        return InkWell(
          // *** Call the onTap callback passed from the parent ***
          onTapDown:
              (TapDownDetails details) => widget.onTap(widget.playlist.id),
          onHover: (hovering) => setState(() => _isHovering = hovering),
          // Use GestureDetector to detect right-clicks (secondary tap)
          child: GestureDetector(
            onTapDown: _storePosition,
            onSecondaryTapDown: _storePosition,
            onSecondaryTap: () => _showContextMenu(context),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 12.0,
              ),
              // *** Apply the calculated background color ***
              decoration: BoxDecoration(
                color: backgroundColor,
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 0.5,
                  ),
                ),
                borderRadius: BorderRadius.circular(
                  4,
                ), // Optional: Add rounding
              ),
              child: Row(
                children: [
                  Icon(
                    // Change icon if selected?
                    widget.isSelected
                        ? Icons.playlist_play_rounded
                        : Icons.playlist_play_outlined,
                    size: 20,
                    color:
                        widget.isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.secondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.playlist.name,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight:
                            widget.isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                      ),
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
