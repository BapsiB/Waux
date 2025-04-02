// Update your home_screen.dart file with the following changes

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audio_looker/blocs/collection/collection_bloc.dart';
import 'package:audio_looker/services/collection_service.dart';
import 'package:audio_looker/widgets/audio_player_widget.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audio_looker/widgets/track_list_item.dart';
import 'package:desktop_drop/desktop_drop.dart'; // New import for drag & drop
import 'package:path/path.dart' as pathLib; // New import for path operations

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  Track? _selectedTrack;
  bool _isPlayerMinimized = false;

  // New variables for drag and drop
  bool _isDragging = false;
  List<String> _supportedExtensions = [
    'mp3',
    'wav',
    'ogg',
    'm4a',
    'aac',
    'flac',
  ];

  // Animation controller for the player
  late AnimationController _animationController;
  late Animation<double> _playerHeightAnimation;

  @override
  void initState() {
    super.initState();
    // Load collection when screen initializes
    context.read<CollectionBloc>().add(LoadCollection());

    // Listen to search changes
    _searchController.addListener(_onSearchChanged);

    // Initialize animation controller
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // Create animation for player height
    _playerHeightAnimation = Tween<double>(
      begin: 490, // Full height
      end: 100, // Minimized height
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    // Add listener to rebuild widget when animation values change
    _animationController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _urlController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    context.read<CollectionBloc>().add(
      SearchCollection(_searchController.text),
    );
  }

  void _togglePlayerSize() {
    setState(() {
      _isPlayerMinimized = !_isPlayerMinimized;
      if (_isPlayerMinimized) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  // Process a single file by adding it to the collection
  Future<void> _processFile(String filePath) async {
    final extension = pathLib
        .extension(filePath)
        .toLowerCase()
        .replaceAll('.', '');
    if (_supportedExtensions.contains(extension)) {
      context.read<CollectionBloc>().add(AddTrackFromPath(filePath));
      return;
    }
  }

  Future<void> _processDirectory(String dirPath) async {
    debugPrint("Processing directory: $dirPath");
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        debugPrint("Directory doesn't exist: $dirPath");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Directory doesn't exist: $dirPath")),
        );
        return;
      }

      // Collect all audio files from the directory and subdirectories
      List<String> audioFilePaths = [];

      // Process files recursively
      await _findAudioFilesRecursively(dir, audioFilePaths);

      debugPrint(
        "Found ${audioFilePaths.length} audio files in directory and subdirectories",
      );

      if (audioFilePaths.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("No supported audio files found in folder"),
          ),
        );
        return;
      }

      // Add all files as a batch instead of one by one
      context.read<CollectionBloc>().add(AddTracksFromPaths(audioFilePaths));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Adding ${audioFilePaths.length} audio files from folder",
          ),
        ),
      );
    } catch (e, stackTrace) {
      debugPrint("Error processing folder: $e");
      debugPrint(stackTrace.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error processing folder: ${e.toString()}")),
      );
    }
  }

  // Add this helper method to find audio files recursively
  Future<void> _findAudioFilesRecursively(
    Directory dir,
    List<String> audioFilePaths,
  ) async {
    try {
      final entities = await dir.list().toList();

      // First, process all files in this directory
      for (var entity in entities) {
        if (entity is File) {
          final extension = pathLib
              .extension(entity.path)
              .toLowerCase()
              .replaceAll('.', '');
          if (_supportedExtensions.contains(extension)) {
            debugPrint("Found audio file: ${entity.path}");
            audioFilePaths.add(entity.path);
          }
        }
      }

      // Then process all subdirectories
      for (var entity in entities) {
        if (entity is Directory) {
          debugPrint("Processing subdirectory: ${entity.path}");
          await _findAudioFilesRecursively(entity, audioFilePaths);
        }
      }
    } catch (e) {
      debugPrint("Error processing directory: $e");
    }
  }

  // Handle dropped files
  Future<void> _handleDroppedFiles(List<DropItem> paths) async {
    debugPrint("Paths dropped: ${paths.length} items");
    if (paths.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("No files were dropped")));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Processing dropped items...")),
    );

    List<String> filesToAdd = [];
    List<String> foldersToProcess = [];

    // First, separate files and directories
    for (final item in paths) {
      final path = item.path;
      try {
        debugPrint("Processing dropped path: $path");

        // Handle web paths differently
        if (path.startsWith("web:")) {
          filesToAdd.add(path);
          continue;
        }

        // For desktop platforms
        if (await FileSystemEntity.isDirectory(path)) {
          foldersToProcess.add(path);
        } else if (await FileSystemEntity.isFile(path)) {
          final extension = pathLib
              .extension(item.path)
              .toLowerCase()
              .replaceFirst('.', '');
          if (_supportedExtensions.contains(extension)) {
            filesToAdd.add(path);
          }
        } else {
          debugPrint("Path doesn't exist or is not accessible: $path");
        }
      } catch (e, stackTrace) {
        debugPrint("Error checking path: $e");
        debugPrint(stackTrace.toString());
      }
    }

    // Process individual files first
    if (filesToAdd.isNotEmpty) {
      debugPrint("Adding ${filesToAdd.length} dropped files");
      context.read<CollectionBloc>().add(AddTracksFromPaths(filesToAdd));

      if (filesToAdd.length == 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Added file: ${pathLib.basename(filesToAdd[0])}"),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Added ${filesToAdd.length} files")),
        );
      }
    }

    // Then process folders one by one
    for (final folderPath in foldersToProcess) {
      await _processDirectory(folderPath);
    }
  }

  Future<void> _pickAndAddAudioFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: true, // Changed to allow multiple files
        allowedExtensions: _supportedExtensions,
      );

      if (result != null && result.files.isNotEmpty) {
        for (final file in result.files) {
          if (file.path != null) {
            print("Selected file path: ${file.path}");
            context.read<CollectionBloc>().add(AddTrackFromPath(file.path!));
          } else if (file.bytes != null) {
            // Handle in-memory file if path isn't available
            final tempDir = await getTemporaryDirectory();
            final tempFile = File('${tempDir.path}/${file.name}');
            await tempFile.writeAsBytes(file.bytes!);
            context.read<CollectionBloc>().add(AddTrackFromPath(tempFile.path));
          }
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

  Future<void> _pickAndAddFolder() async {
    try {
      final result = await FilePicker.platform.getDirectoryPath();

      if (result != null) {
        await _processDirectory(result);
      }
    } catch (e) {
      print("Error picking folder: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error selecting folder: ${e.toString()}")),
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
            icon: const Icon(Icons.folder),
            onPressed: _pickAndAddFolder,
            tooltip: 'Add folder',
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
            child: DropTarget(
              onDragDone: (detail) async {
                setState(() {
                  _isDragging = false;
                });
                await _handleDroppedFiles(detail.files);
              },
              onDragEntered: (detail) {
                setState(() {
                  _isDragging = true;
                });
              },
              onDragExited: (detail) {
                setState(() {
                  _isDragging = false;
                });
              },
              child: Stack(
                children: [
                  // Collection content
                  BlocBuilder<CollectionBloc, CollectionState>(
                    builder: (context, state) {
                      if (state is CollectionInitial ||
                          state is CollectionLoading) {
                        return const Center(
                          child: CircularProgressIndicator(color: Colors.brown),
                        );
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
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.add),
                                      label: const Text('Add Files'),
                                      onPressed: _pickAndAddAudioFile,
                                    ),
                                    const SizedBox(width: 12),
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.folder),
                                      label: const Text('Add Folder'),
                                      onPressed: _pickAndAddFolder,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Or drag and drop files and folders here',
                                  style: TextStyle(color: Colors.grey),
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
                                itemCount: state.tracks.length,
                                itemBuilder: (context, index) {
                                  final track = state.tracks[index];
                                  final isSelected =
                                      _selectedTrack?.id == track.id;

                                  return TrackListItem(
                                    track: track,
                                    isSelected: isSelected,
                                    onTap: () {
                                      setState(() {
                                        _selectedTrack = track;
                                        // Expand player if it's minimized
                                        if (_isPlayerMinimized) {
                                          _togglePlayerSize();
                                        }
                                      });
                                    },
                                    onDelete: () {
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
                                  );
                                },
                              ),
                            ),

                            // Animated audio player
                            if (_selectedTrack != null)
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                height: _playerHeightAnimation.value,
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
                                child: Column(
                                  children: [
                                    // Toggle button for player size
                                    Container(
                                      height: 36,
                                      color: Theme.of(
                                        context,
                                      ).primaryColor.withOpacity(0.1),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          IconButton(
                                            icon: Icon(
                                              _isPlayerMinimized
                                                  ? Icons.keyboard_arrow_up
                                                  : Icons.keyboard_arrow_down,
                                            ),
                                            onPressed: _togglePlayerSize,
                                            tooltip:
                                                _isPlayerMinimized
                                                    ? 'Expand player'
                                                    : 'Minimize player',
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Audio player content
                                    Expanded(
                                      child:
                                          _isPlayerMinimized
                                              ? _buildMinimizedPlayer()
                                              : AudioPlayerWidget(
                                                key: ValueKey(
                                                  _selectedTrack!.path,
                                                ),
                                                title: _selectedTrack!.title,
                                                artist: _selectedTrack!.artist,
                                                audioSource:
                                                    _selectedTrack!.path,
                                                isUrl: _selectedTrack!.isUrl,
                                                rating: _selectedTrack!.rating,
                                                notes: _selectedTrack!.comment,
                                                generalTags:
                                                    _selectedTrack!.generalTags,
                                                onRatingChanged: (rating) {
                                                  if (_selectedTrack?.id !=
                                                      null) {
                                                    context
                                                        .read<CollectionBloc>()
                                                        .add(
                                                          UpdateTrackRating(
                                                            _selectedTrack!.id!,
                                                            rating,
                                                          ),
                                                        );
                                                  }
                                                },
                                                onNotesChanged: (notes) {
                                                  if (_selectedTrack?.id !=
                                                      null) {
                                                    context
                                                        .read<CollectionBloc>()
                                                        .add(
                                                          UpdateTrackComment(
                                                            _selectedTrack!.id!,
                                                            notes,
                                                          ),
                                                        );
                                                  }
                                                },
                                                onAddGeneralTag: (tag) {
                                                  if (_selectedTrack?.id !=
                                                      null) {
                                                    context
                                                        .read<CollectionBloc>()
                                                        .add(
                                                          AddTrackGeneralTag(
                                                            _selectedTrack!.id!,
                                                            tag,
                                                          ),
                                                        );
                                                  }
                                                },
                                                onRemoveGeneralTag: (tag) {
                                                  if (_selectedTrack?.id !=
                                                      null) {
                                                    context
                                                        .read<CollectionBloc>()
                                                        .add(
                                                          RemoveTrackGeneralTag(
                                                            _selectedTrack!.id!,
                                                            tag,
                                                          ),
                                                        );
                                                  }
                                                },
                                              ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        );
                      }

                      return const Center(child: Text('Something went wrong'));
                    },
                  ),

                  // Drag overlay
                  if (_isDragging)
                    Container(
                      color: Theme.of(context).primaryColor.withOpacity(0.3),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 30,
                            vertical: 20,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(
                                Icons.file_download,
                                size: 48,
                                color: Colors.orange,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'Drop audio files or folders here',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Supported formats: MP3, WAV, OGG, M4A, AAC, FLAC',
                                style: TextStyle(fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Minimized player view
  Widget _buildMinimizedPlayer() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedTrack!.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _selectedTrack!.artist,
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous),
                onPressed: () {
                  // Add functionality to play previous track
                },
              ),
              IconButton(
                icon: const Icon(Icons.play_arrow),
                onPressed: () {
                  // Add functionality to play/pause
                },
              ),
              IconButton(
                icon: const Icon(Icons.skip_next),
                onPressed: () {
                  // Add functionality to play next track
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
