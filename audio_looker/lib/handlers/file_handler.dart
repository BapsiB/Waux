// lib/handlers/file_handler.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as pathLib;

// Import BLoCs
import 'package:audio_looker/blocs/track_management/track_management_bloc.dart';
import 'package:audio_looker/blocs/collection_management/collection_management_bloc.dart';

// Import models
import 'package:audio_looker/services/collection_service.dart';

/// Handles file operations, imports, and drag & drop
class FileHandler {
  final BuildContext context;
  final List<String> supportedExtensions;

  FileHandler({required this.context, required this.supportedExtensions});

  /// Processes dropped files and folders
  Future<void> handleDroppedFiles(List<DropItem> items) async {
    if (items.isEmpty) return;

    final collectionBloc = context.read<TrackManagementBloc>();
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

    for (final item in items) {
      final path = item.path;
      try {
        print("Processing dropped path: $path");
        if (path.startsWith("web:")) {
          // Handle web drops if necessary
          continue;
        }
        var type = await FileSystemEntity.type(path, followLinks: false);

        if (type == FileSystemEntityType.directory) {
          // Only add as ROOT folder if the active collection is LOCAL
          if (activeCollection.type == CollectionType.local) {
            collectionBloc.add(AddRootFolder(path));
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

    // Add individual files to the active collection
    if (filesToAdd.isNotEmpty) {
      collectionBloc.add(AddTracksFromPaths(filesToAdd));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Adding ${filesToAdd.length} dropped files...")),
      );
    }

    // Process tracks within dropped folders for the active collection
    for (final folderPath in foldersToProcess) {
      await addTracksFromFolder(folderPath);
    }
  }

  /// Picks and adds a folder to the collection
  Future<void> pickAndAddFolder() async {
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
        context.read<TrackManagementBloc>().add(
          AddRootFolder(result),
        ); // Add as root
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
    final collectionBloc = context.read<TrackManagementBloc>();
    if (collectionBloc.state is! TrackManagementLoaded) {
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
          collectionBloc.add(AddTracksFromPaths(filePathsToAdd));
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
    if (context.read<TrackManagementBloc>().state is! TrackManagementLoaded) {
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
                    context.read<TrackManagementBloc>().add(
                      AddTrackFromUrl(urlController.text.trim()),
                    );
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

      // Dispatch AddTracksFromPaths to add found files to the active collection
      context.read<TrackManagementBloc>().add(
        AddTracksFromPaths(audioFilePaths),
      );
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
  CollectionDefinition? _getActiveCollection() {
    final collectionState = context.read<CollectionManagementBloc>().state;
    if (collectionState is CollectionManagementLoaded) {
      return collectionState.activeCollectionDefinition;
    } else if (collectionState is CollectionManagementLoading) {
      return collectionState.activeCollectionDefinition;
    }
    return null;
  }
}
