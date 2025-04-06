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

  const PlaylistDrawer({
    super.key,
    required this.selectedPlaylistId,
    required this.onPlaylistSelected,
  });

  // --- Dialog to Create New Playlist ---
  void _showCreatePlaylistDialog(BuildContext context) {
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
      (_) => nameController.dispose(),
    ); // Dispose controller when dialog closes
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
          height: 120, // Adjust height as needed
          child: DrawerHeader(
            // Keep DrawerHeader for styling if desired
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
            ),
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8), // Adjust padding
            margin: EdgeInsets.zero, // Remove default margin
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Playlists',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                // --- Add Playlist Button ---
                IconButton(
                  icon: const Icon(Icons.add_circle),
                  tooltip: 'Create New Playlist',
                  onPressed: () => _showCreatePlaylistDialog(context),
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ],
            ),
          ),
        ),

        // --- Playlist List ---
        Expanded(
          child: BlocConsumer<PlaylistBloc, PlaylistState>(
            listener: (context, state) {
              // Show feedback for errors (optional, can be handled globally too)
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
              // Handle Loading State
              if (state is PlaylistLoading && state is! PlaylistLoaded) {
                // Show loading indicator only if not already loaded
                // Ensure LoadingIndicator constructor is correct (e.g., takes child)
                return Center(child: LoadingIndicator(child: Container()));
              }
              // Handle Loaded State
              else if (state is PlaylistLoaded) {
                // Handle Empty Playlist Case
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
                // Display the list of playlists
                return ListView.builder(
                  padding: EdgeInsets.zero, // Remove default padding
                  itemCount: state.playlists.length,
                  itemBuilder: (context, index) {
                    final playlist = state.playlists[index];
                    // Pass selection state and callback to PlaylistListItem
                    return PlaylistListItem(
                      key: ValueKey(playlist.id), // Use unique key
                      playlist: playlist,
                      isSelected:
                          playlist.id ==
                          selectedPlaylistId, // Check if selected
                      onTap: (String id) {
                        onPlaylistSelected(id);
                      }, // Pass the callback from HomeScreen
                    );
                  },
                );
              }
              // Handle Error State
              else if (state is PlaylistError) {
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
              // Handle Initial State or other unexpected states
              return Center(
                child: LoadingIndicator(child: Container()),
              ); // Default/Initial loading
            },
          ),
        ),
      ],
    );
  }
}
