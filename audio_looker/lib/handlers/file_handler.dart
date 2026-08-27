// lib/handlers/file_handler.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as pathLib;

// Import BLoCs
import '../blocs/track_management/track_data_bloc.dart'; // <<< CHANGED: Import new BLoC
import '../blocs/collection_management/collection_management_bloc.dart';

// Import models
import '../services/collection_service.dart';

/// Handles file operations, imports, and drag & drop
class FileHandler {
  final BuildContext context;
  final List<String> supportedExtensions;

  FileHandler({required this.context, required this.supportedExtensions});

  /// Processes dropped files and folders
  Future<void> handleDroppedFiles(List<DropItem> items) async {
    if (items.isEmpty) return;

    // <<< CHANGED: Read from TrackDataBloc >>>
    final trackDataBloc = context.read<TrackDataBloc>();
    final activeCollection = _getActiveCollection();

    if (activeCollection == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Cannot add items: No active collection."),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Processing dropped items...")),
    );

    List<String> filesToAdd = [];
    List<String> foldersToProcess = []; // For adding tracks within folder
    List<String> rootsToAdd = []; // For adding root folders (local only)

    for (final item in items) {
      final path = item.path;
      try {
        print("Processing dropped path: $path");
        if (path.startsWith("web:")) {
          continue;
        }
        var type = await FileSystemEntity.type(path, followLinks: false);

        if (type == FileSystemEntityType.directory) {
          // Only add as ROOT folder if the active collection is LOCAL
          if (activeCollection.type == CollectionType.local) {
            // trackDataBloc.add(AddRootFolder(path)); // <<< Dispatch to TrackDataBloc
            rootsToAdd.add(path); // Collect roots to add
          }
          // Always process folder to add tracks inside it to the active collection
          foldersToProcess.add(path);
        } else if (type == FileSystemEntityType.file) {
          final extension = pathLib
              .extension(item.path)
              .toLowerCase()
              .replaceFirst('.', '');
          if (supportedExtensions.contains(extension)) {
            filesToAdd.add(path);
          } else {
            print("Skipping unsupported file type: $path");
          }
        } else {
          print(
            "Skipping unsupported or inaccessible path: $path (Type: $type)",
          );
        }
      } catch (e, stackTrace) {
        print("Error checking dropped path type for $path: $e\n$stackTrace");
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error processing item: $path")));
      }
    }

    // Add Root Folders (if any)
    for (final rootPath in rootsToAdd) {
      trackDataBloc.add(AddRootFolder(rootPath));
    }

    // Add individual files to the active collection
    if (filesToAdd.isNotEmpty) {
      // <<< CHANGED: Use AddTracks event >>>
      trackDataBloc.add(AddTracks(filesToAdd));
      // ScaffoldMessenger.of(context).showSnackBar(
      //   SnackBar(content: Text("Adding ${filesToAdd.length} dropped files...")),
      // );
    }

    // Process tracks within dropped folders for the active collection
    for (final folderPath in foldersToProcess) {
      await addTracksFromFolder(folderPath); // This will dispatch AddTracks
    }
  }

  /// Picks and adds a folder to the collection
  Future<void> pickAndAddFolder() async {
    // <<< CHANGED: Read from TrackDataBloc >>>
    final trackDataBloc = context.read<TrackDataBloc>();
    final activeCollection = _getActiveCollection();

    if (activeCollection?.type != CollectionType.local) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Adding root folders is only supported for 'Local' collections.",
          ),
        ),
      );
      return;
    }

    try {
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Folder to Add to Local Collection',
      );
      if (result != null) {
        // <<< CHANGED: Dispatch AddRootFolder to TrackDataBloc >>>
        trackDataBloc.add(AddRootFolder(result));
        await addTracksFromFolder(result); // Also add tracks within
      }
    } catch (e) {
      debugPrint("Error picking folder: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error selecting folder: $e")));
    }
  }

  /// Picks and adds audio files to the collection
  Future<void> pickAndAddAudioFile() async {
    // <<< CHANGED: Read from TrackDataBloc >>>
    final trackDataBloc = context.read<TrackDataBloc>();
    // Check if collection is active by checking the BLoC's state
    if (trackDataBloc.state is TrackDataInitial ||
        trackDataBloc.state is TrackDataError) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a collection first.")),
      );
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: true,
        allowedExtensions: supportedExtensions,
        dialogTitle: 'Select Audio Files',
      );
      if (result != null && result.files.isNotEmpty) {
        List<String> filePathsToAdd = [];
        for (final file in result.files) {
          if (file.path != null) {
            filePathsToAdd.add(file.path!);
          } else if (file.bytes != null) {
            // Handle files picked from memory (e.g., web)
            final tempDir = await getTemporaryDirectory();
            final tempFile = File('${tempDir.path}/${file.name}');
            await tempFile.writeAsBytes(file.bytes!);
            filePathsToAdd.add(tempFile.path);
          }
        }
        if (filePathsToAdd.isNotEmpty) {
          // <<< CHANGED: Dispatch AddTracks to TrackDataBloc >>>
          trackDataBloc.add(AddTracks(filePathsToAdd));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Adding ${filePathsToAdd.length} files...")),
          );
        }
      }
    } catch (e, stackTrace) {
      debugPrint("Error picking file(s): $e\n$stackTrace");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error selecting file(s): $e")));
    }
  }

  /// Shows dialog to add audio from URL
  void showAddUrlDialog() {
    // <<< CHANGED: Read from TrackDataBloc >>>
    final trackDataBloc = context.read<TrackDataBloc>();
    // Check if collection is active by checking the BLoC's state
    if (trackDataBloc.state is TrackDataInitial ||
        trackDataBloc.state is TrackDataError) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a collection first.")),
      );
      return;
    }

    final TextEditingController urlController = TextEditingController();

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Add Audio from URL'),
            content: TextField(
              controller: urlController,
              decoration: const InputDecoration(hintText: 'Enter audio URL...'),
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  if (urlController.text.isNotEmpty &&
                      Uri.tryParse(urlController.text)?.hasAbsolutePath ==
                          true) {
                    // <<< CHANGED: Dispatch AddTrackUrl to TrackDataBloc >>>
                    trackDataBloc.add(AddTrackUrl(urlController.text.trim()));
                    Navigator.of(context).pop();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Please enter a valid URL."),
                      ),
                    );
                  }
                },
                child: const Text('Add'),
              ),
            ],
          ),
    );
  }

  /// Add tracks from a folder recursively
  Future<void> addTracksFromFolder(String dirPath) async {
    // <<< CHANGED: Read from TrackDataBloc >>>
    final trackDataBloc = context.read<TrackDataBloc>();
    debugPrint("Scanning folder for tracks: $dirPath");
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Directory not found: $dirPath")),
        );
        return;
      }

      List<String> audioFilePaths = [];
      await findAudioFilesRecursively(dir, audioFilePaths);

      if (audioFilePaths.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "No supported audio files found in folder '$dirPath'.",
            ),
          ),
        );
        return;
      }

      // <<< CHANGED: Dispatch AddTracks to TrackDataBloc >>>
      trackDataBloc.add(AddTracks(audioFilePaths));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Adding ${audioFilePaths.length} files from '$dirPath'...",
          ),
        ),
      );
    } catch (e, stackTrace) {
      debugPrint("Error processing folder: $e\n$stackTrace");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error processing folder '$dirPath': $e")),
      );
    }
  }

  /// Helper method to find audio files recursively in a directory
  /// (This method remains the same internally)
  Future<void> findAudioFilesRecursively(
    Directory dir,
    List<String> audioFilePaths,
  ) async {
    try {
      final entities = await dir.list().toList();
      for (final entity in entities) {
        if (entity is File) {
          final extension = pathLib
              .extension(entity.path)
              .toLowerCase()
              .replaceFirst('.', '');
          if (supportedExtensions.contains(extension)) {
            audioFilePaths.add(entity.path);
          }
        } else if (entity is Directory) {
          // Recursively search subdirectories
          await findAudioFilesRecursively(entity, audioFilePaths);
        }
      }
    } catch (e) {
      print("Error scanning directory ${dir.path}: $e");
      // Continue with other directories even if one fails
    }
  }

  /// Helper to get active collection
  /// (This method remains the same, reading from CollectionManagementBloc)
  CollectionDefinition? _getActiveCollection() {
    final collectionState = context.read<CollectionManagementBloc>().state;
    if (collectionState is CollectionManagementLoaded) {
      return collectionState.activeCollectionDefinition;
    } else if (collectionState is CollectionManagementLoading) {
      // Return the definition even if loading, as adding might still be valid
      return collectionState.activeCollectionDefinition;
    }
    return null;
  }
}
