// lib/widgets/playlist_drawer.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/playlist/playlist_bloc.dart';
import '../models/playlist.dart'; // Import Playlist model
import 'playlist_list_item.dart'; // Import the item widget
import 'loading_indicator.dart'; // Assuming you have this

/// A Drawer widget that displays the list of playlists.
class PlaylistDrawer extends StatelessWidget {
  const PlaylistDrawer({super.key});

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
      BlocProvider.of<PlaylistBloc>(
        dialogContext,
        listen: false,
      ).add(CreatePlaylist(trimmedName));
      Navigator.of(dialogContext).pop(); // Close the dialog
    } else {
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        const SnackBar(content: Text('Playlist name cannot be empty.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          // --- Drawer Header ---
          SizedBox(
            height: 120, // Adjust height as needed
            child: DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                // Show feedback for errors
                if (state is PlaylistError) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Playlist Error: ${state.message}'),
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                  );
                }
                // Optional: Show feedback on success actions if needed
                // else if (state is PlaylistLoaded) {
                //   // Could show a temporary confirmation message here
                // }
              },
              builder: (context, state) {
                if (state is PlaylistLoading && state is! PlaylistLoaded) {
                  // Show loading only if not already loaded
                  return Center(child: SizedBox(height: 100));
                } else if (state is PlaylistLoaded) {
                  if (state.playlists.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          'No playlists yet. Click (+) to create one!',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  // Display the list of playlists
                  return ListView.builder(
                    itemCount: state.playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = state.playlists[index];
                      // Use the PlaylistListItem widget
                      return PlaylistListItem(
                        key: ValueKey(playlist.id),
                        playlist: playlist,
                      );
                    },
                  );
                } else if (state is PlaylistError) {
                  // Show error message and potentially a retry button
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Error loading playlists: ${state.message}'),
                          const SizedBox(height: 10),
                          ElevatedButton(
                            onPressed:
                                () => context.read<PlaylistBloc>().add(
                                  LoadPlaylists(),
                                ),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                // Initial state or unexpected state
                return const Center(child: Text('Loading playlists...'));
              },
            ),
          ),
        ],
      ),
    );
  }
}
