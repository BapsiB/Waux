// lib/widgets/playlist_drawer.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/playlist/playlist_bloc.dart';
import '../models/playlist.dart';
import 'playlist_list_item.dart';
import 'loading_indicator.dart'; // Assuming you have this

/// A Panel widget that displays the list of playlists.
class PlaylistDrawer extends StatelessWidget {
  // Properties to receive state and callback from HomeScreen
  final String? selectedPlaylistId;
  final ValueChanged<String> onPlaylistSelected;
  final bool isOpen; // <<< ADDED: Parameter to control fade

  const PlaylistDrawer({
    super.key,
    required this.selectedPlaylistId,
    required this.onPlaylistSelected,
    required this.isOpen, // <<< ADDED: Make it required
  });

  // --- Dialog to Create New Playlist ---
  // This logic is now handled in HomeScreen, but keep it here if
  // the button inside the drawer needs to remain functional.
  // If the button inside the drawer is removed, this can be removed too.
  void _showCreatePlaylistDialog(BuildContext context) {
    // ... (keep existing dialog logic if needed) ...
    final TextEditingController nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('New Playlist'),
          content: TextField(
            controller: nameController,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Playlist Name'),
            onSubmitted:
                (_) =>
                    _submitCreatePlaylist(dialogContext, nameController.text),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              child: const Text('Create'),
              onPressed:
                  () =>
                      _submitCreatePlaylist(dialogContext, nameController.text),
            ),
          ],
        );
      },
    ).then(
      (_) => nameController.dispose(), // Dispose controller when dialog closes
    );
  }

  void _submitCreatePlaylist(BuildContext dialogContext, String name) {
    final trimmedName = name.trim();
    if (trimmedName.isNotEmpty) {
      // Use the context from the main build method to access the BLoC
      // listen: false prevents rebuilding this widget when the bloc is accessed
      BlocProvider.of<PlaylistBloc>(
        dialogContext,
        listen: false,
      ).add(CreatePlaylist(trimmedName));
      Navigator.of(dialogContext).pop(); // Close the dialog
    } else {
      // Show error if name is empty
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        const SnackBar(content: Text('Playlist name cannot be empty.')),
      );
    }
  }
  // --- End Create Playlist Dialog ---

  @override
  Widget build(BuildContext context) {
    // Use Column directly as this is now a panel, not a standard Drawer
    return Column(
      children: [
        // --- Header ---
        SizedBox(
          height: 48, // Adjust height as needed
          child: DrawerHeader(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
            margin: EdgeInsets.zero,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // --- MODIFIED: Wrap Title with AnimatedOpacity ---
                Expanded(
                  // Allow title to take space but fade
                  child: AnimatedOpacity(
                    opacity: isOpen ? 1.0 : 0.0, // Fade based on isOpen
                    duration: const Duration(milliseconds: 150), // Faster fade
                    curve: Curves.easeOut, // Adjust curve if needed
                    child: Text(
                      'Playlists',
                      style: Theme.of(
                        context,
                      ).textTheme.titleLarge?.copyWith(color: Colors.blueGrey),
                      overflow:
                          TextOverflow
                              .ellipsis, // Prevent overflow when visible
                      maxLines: 1,
                    ),
                  ),
                ),
                // --- END MODIFIED ---

                // --- REMOVED: Add Playlist Button (moved to HomeScreen panel) ---
                // IconButton(
                //   icon: const Icon(Icons.add_circle_outline),
                //   tooltip: 'Create New Playlist',
                //   onPressed: () => _showCreatePlaylistDialog(context),
                //   color: Theme.of(context).colorScheme.primary,
                // ),
                // --- END REMOVED ---
              ],
            ),
          ),
        ),
        // --- Playlist List ---
        Expanded(
          child: BlocConsumer<PlaylistBloc, PlaylistState>(
            listener: (context, state) {
              if (state is PlaylistError) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Playlist Error: ${state.message}'),
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                );
              }
            },
            builder: (context, state) {
              if (state is PlaylistLoading && state is! PlaylistLoaded) {
                return Center(child: LoadingIndicator(child: Container()));
              } else if (state is PlaylistLoaded) {
                if (state.playlists.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        'No playlists yet.\nClick (+) to create one!',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: state.playlists.length,
                  itemBuilder: (context, index) {
                    final playlist = state.playlists[index];
                    return PlaylistListItem(
                      key: ValueKey(playlist.id),
                      playlist: playlist,
                      isSelected: playlist.id == selectedPlaylistId,
                      onTap: onPlaylistSelected,
                    );
                  },
                );
              } else if (state is PlaylistError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: Colors.redAccent,
                          size: 48,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Error: ${state.message}',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                          onPressed:
                              () => context.read<PlaylistBloc>().add(
                                LoadPlaylists(),
                              ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return Center(child: LoadingIndicator(child: Container()));
            },
          ),
        ),
      ],
    );
  }
}
