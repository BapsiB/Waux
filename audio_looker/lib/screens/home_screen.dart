import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audio_looker/blocs/collection/collection_bloc.dart';
import 'package:audio_looker/services/collection_service.dart';
import 'package:audio_looker/widgets/audio_player_widget.dart';
import 'package:path_provider/path_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  Track? _selectedTrack;

  @override
  void initState() {
    super.initState();
    // Load collection when screen initializes
    context.read<CollectionBloc>().add(LoadCollection());

    // Listen to search changes
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    context.read<CollectionBloc>().add(
      SearchCollection(_searchController.text),
    );
  }

  Future<void> _pickAndAddAudioFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
        allowedExtensions: ['mp3', 'wav', 'ogg', 'm4a', 'aac'],
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;

        // For macOS: Use the path directly without creating a File object
        if (file.path != null) {
          print("Selected file path: ${file.path}");

          // Instead of creating a File object, just pass the path
          context.read<CollectionBloc>().add(
            AddTrackFromPath(
              file.path!,
            ), // Change your event to accept path instead of File
          );
        } else if (file.bytes != null) {
          // Handle in-memory file if path isn't available
          final tempDir = await getTemporaryDirectory();
          final tempFile = File('${tempDir.path}/${file.name}');
          await tempFile.writeAsBytes(file.bytes!);

          context.read<CollectionBloc>().add(AddTrackFromPath(tempFile.path));
        }
      }
    } catch (e, stackTrace) {
      print("Error picking file: $e");
      print(stackTrace);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error selecting file: ${e.toString()}")),
      );
    }
  }

  void _showAddUrlDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Add Audio from URL'),
            content: TextField(
              controller: _urlController,
              decoration: const InputDecoration(hintText: 'Enter audio URL'),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  if (_urlController.text.isNotEmpty) {
                    context.read<CollectionBloc>().add(
                      AddTrackFromUrl(_urlController.text),
                    );
                    Navigator.of(context).pop();
                  }
                },
                child: const Text('Add'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Looker'),
        actions: [
          IconButton(
            icon: const Icon(Icons.link),
            onPressed: _showAddUrlDialog,
            tooltip: 'Add from URL',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _pickAndAddAudioFile,
            tooltip: 'Add audio file',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search your collection...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),

          // Collection list and player
          Expanded(
            child: BlocBuilder<CollectionBloc, CollectionState>(
              builder: (context, state) {
                if (state is CollectionInitial || state is CollectionLoading) {
                  return const Center(child: CircularProgressIndicator());
                } else if (state is CollectionError) {
                  return Center(child: Text('Error: ${state.message}'));
                } else if (state is CollectionLoaded) {
                  final tracks = state.tracks;

                  if (tracks.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.music_note,
                            size: 64,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            state.searchQuery != null
                                ? 'No tracks found for "${state.searchQuery}"'
                                : 'Your collection is empty',
                            style: const TextStyle(fontSize: 16),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Add Audio Files'),
                            onPressed: _pickAndAddAudioFile,
                          ),
                        ],
                      ),
                    );
                  }

                  return Column(
                    children: [
                      // Tracks list
                      Expanded(
                        child: ListView.builder(
                          itemCount: tracks.length,
                          itemBuilder: (context, index) {
                            final track = tracks[index];
                            final isSelected = _selectedTrack?.id == track.id;

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              color:
                                  isSelected
                                      ? Theme.of(
                                        context,
                                      ).primaryColor.withOpacity(0.2)
                                      : null,
                              child: ListTile(
                                leading: const Icon(Icons.music_note),
                                title: Text(track.title),
                                subtitle: Text(
                                  '${track.artist} • ${track.album}',
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete),
                                  onPressed: () {
                                    if (track.id != null) {
                                      context.read<CollectionBloc>().add(
                                        RemoveTrack(track.id!),
                                      );
                                      if (_selectedTrack?.id == track.id) {
                                        setState(() {
                                          _selectedTrack = null;
                                        });
                                      }
                                    }
                                  },
                                ),
                                onTap: () {
                                  setState(() {
                                    _selectedTrack = track;
                                  });
                                },
                              ),
                            );
                          },
                        ),
                      ),

                      // Audio player
                      if (_selectedTrack != null)
                        Container(
                          height: 450,
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 8,
                                offset: const Offset(0, -2),
                              ),
                            ],
                          ),
                          child: AudioPlayerWidget(
                            title: _selectedTrack!.title,
                            artist: _selectedTrack!.artist,
                            audioSource: _selectedTrack!.path,
                            isUrl: _selectedTrack!.isUrl,
                          ),
                        ),
                    ],
                  );
                }

                return const Center(child: Text('Something went wrong'));
              },
            ),
          ),
        ],
      ),
    );
  }
}
