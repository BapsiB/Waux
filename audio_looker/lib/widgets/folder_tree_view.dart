// lib/widgets/folder_tree_view.dart

import 'package:flutter/material.dart';
import 'package:path/path.dart' as pathLib;
import 'package:audio_looker/services/collection_service.dart';

class FolderTreeView extends StatefulWidget {
  final List<Track> tracks;
  final Track? selectedTrack;
  final List<String> rootFolders; // Accept root folders from parent
  final String? currentlyLoadedPath; // *** ADDED: Path of loaded track ***
  final Function(Track) onTrackSelected;
  final Function(int) onTrackDeleted;

  const FolderTreeView({
    Key? key,
    required this.tracks,
    this.selectedTrack,
    required this.rootFolders, // Required parameter
    this.currentlyLoadedPath, // *** ADDED ***
    required this.onTrackSelected,
    required this.onTrackDeleted,
  }) : super(key: key);

  @override
  State<FolderTreeView> createState() => _FolderTreeViewState();
}

class _FolderTreeViewState extends State<FolderTreeView> {
  // Map to hold our folder structure
  late Map<String, dynamic> _folderStructure;
  // Set to track expanded folders
  final Set<String> _expandedFolders = {};

  @override
  void initState() {
    super.initState();
    _buildFolderStructure();
    // *** ADDED: Expand folders for initial path if provided ***
    _expandFoldersForPath(widget.currentlyLoadedPath);
  }

  @override
  void didUpdateWidget(FolderTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    bool structureChanged = false;
    // Rebuild structure if tracks or roots change
    if (oldWidget.tracks != widget.tracks ||
        oldWidget.rootFolders != widget.rootFolders) {
      _buildFolderStructure();
      structureChanged = true;
    }

    // *** ADDED: Check if loaded path changed OR if structure changed ***
    if (structureChanged ||
        oldWidget.currentlyLoadedPath != widget.currentlyLoadedPath) {
      // Always re-apply expansion logic if path exists or structure changed
      _expandFoldersForPath(widget.currentlyLoadedPath);
    }
  }

  // Build the folder structure from the track list and root folders
  void _buildFolderStructure() {
    _folderStructure = <String, dynamic>{};

    // Add special folders first
    _folderStructure["Web Links"] = <String, dynamic>{"tracks": <dynamic>[]};
    _folderStructure["Imported Files"] = <String, dynamic>{
      "tracks": <dynamic>[],
    };

    // Add root folders (using basename as display name)
    for (final rootPath in widget.rootFolders) {
      // Normalize path separators for consistency WITHIN the structure keys if needed
      // but for display, basename is fine.
      final rootName = pathLib.basename(rootPath);
      _folderStructure[rootName] = <String, dynamic>{
        "rootPath": rootPath, // Store the full path for reference
      };
    }

    // Now add tracks to the appropriate folders
    for (final track in widget.tracks) {
      if (track.isUrl) {
        // Put URLs in Web Links
        (_folderStructure["Web Links"]["tracks"] as List<dynamic>).add(track);
      } else {
        final filePath = track.path;
        final directory = pathLib.dirname(filePath);

        // Check if this track belongs to a root folder
        bool foundRoot = false;
        for (final rootPath in widget.rootFolders) {
          // Use platform-specific path comparison if needed, but startsWith is often sufficient
          if (pathLib.isWithin(rootPath, directory) || directory == rootPath) {
            // This file belongs to this root folder
            foundRoot = true;

            // Get the root folder name (display name)
            final rootName = pathLib.basename(rootPath);

            // Get the relative path from the root
            String relativePath = pathLib.relative(directory, from: rootPath);

            // Normalize path separators for internal consistency
            relativePath = relativePath.replaceAll('\\', '/');
            if (relativePath == '.') {
              // Handle case where file is directly in root
              relativePath = '';
            }

            // Split into path segments
            List<String> pathSegments =
                relativePath.isEmpty ? [] : relativePath.split('/');

            // Make sure the root exists in our structure (should exist from loop above)
            if (!_folderStructure.containsKey(rootName)) {
              _folderStructure[rootName] = <String, dynamic>{
                "rootPath": rootPath,
              };
            }

            // Add to the structure under the root folder
            _addToStructure(
              _folderStructure[rootName] as Map<String, dynamic>,
              pathSegments,
              track,
            );
            break; // Stop checking roots once found
          }
        }

        // If not in any root folder, add to "Imported Files"
        if (!foundRoot) {
          (_folderStructure["Imported Files"]["tracks"] as List<dynamic>).add(
            track,
          );
        }
      }
    }
  }

  // Recursively add a track to the folder structure
  void _addToStructure(
    Map<String, dynamic> structure,
    List<String> pathSegments,
    Track track,
  ) {
    if (pathSegments.isEmpty) {
      // We're at the leaf node, add the track
      if (!structure.containsKey("tracks")) {
        structure["tracks"] = <dynamic>[];
      }
      (structure["tracks"] as List<dynamic>).add(track);
    } else {
      // We're still traversing directories
      final segment = pathSegments.first;
      if (!structure.containsKey(segment)) {
        structure[segment] = <String, dynamic>{};
      }
      // Ensure the entry is a Map before recursing
      if (structure[segment] is Map<String, dynamic>) {
        _addToStructure(
          structure[segment] as Map<String, dynamic>,
          pathSegments.sublist(1),
          track,
        );
      } else {
        print(
          "Warning: Structure conflict for segment '$segment'. Expected Map, found ${structure[segment].runtimeType}",
        );
        // Handle error or overwrite if necessary
        structure[segment] = <String, dynamic>{};
        _addToStructure(
          structure[segment] as Map<String, dynamic>,
          pathSegments.sublist(1),
          track,
        );
      }
    }
  }

  // *** ADDED: Method to calculate and set expanded folders for a given path ***
  void _expandFoldersForPath(String? loadedPath) {
    if (loadedPath == null || loadedPath.isEmpty) {
      // Optional: Collapse folders if path becomes null? Or do nothing.
      // _expandedFolders.clear(); // Example: Clear all expansions
      // if (mounted) setState(() {});
      return;
    }

    // Keep track if any changes were made to avoid unnecessary setState calls
    bool changed = false;

    try {
      // Handle URLs
      if (Uri.tryParse(loadedPath)?.isAbsolute ?? false) {
        if (_expandedFolders.add('Web Links')) changed = true;
      }
      // Handle File Paths
      else {
        final String directory = pathLib.dirname(loadedPath);
        String? matchingRootPath;
        String? rootName;

        // Find the root folder this path belongs to
        for (final root in widget.rootFolders) {
          if (pathLib.isWithin(root, directory) || directory == root) {
            matchingRootPath = root;
            rootName = pathLib.basename(root);
            break;
          }
        }

        if (matchingRootPath != null && rootName != null) {
          // Calculate relative path and segments
          String relativePath = pathLib.relative(
            directory,
            from: matchingRootPath,
          );
          relativePath = relativePath.replaceAll('\\', '/');
          if (relativePath == '.')
            relativePath = ''; // Handle file directly in root

          List<String> pathSegments =
              relativePath.isEmpty ? [] : relativePath.split('/');

          // Add root folder itself to expansion set
          if (_expandedFolders.add(rootName)) changed = true;

          // Add intermediate folders
          String currentPathKey = rootName;
          for (final segment in pathSegments) {
            if (segment.isNotEmpty) {
              // Avoid empty segments if path ends with /
              currentPathKey +=
                  '/$segment'; // Use '/' as consistent key separator
              if (_expandedFolders.add(currentPathKey)) changed = true;
            }
          }
          print("Expanding folders: $_expandedFolders for path: $loadedPath");
        } else {
          // Not under a known root, assume "Imported Files"
          if (_expandedFolders.add('Imported Files')) changed = true;
        }
      }
    } catch (e) {
      print("Error calculating expansion path for $loadedPath: $e");
    }

    // Trigger rebuild only if the expansion set actually changed
    if (changed && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild structure just in case (might be redundant with didUpdateWidget)
    // Consider if _buildFolderStructure only needs to run when tracks/roots change
    // _buildFolderStructure();

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Show counts at the top
            const Divider(),
            // Build the tree view
            _buildTreeView(_folderStructure, []),
          ],
        ),
      ),
    );
  }

  // Build the tree view recursively
  Widget _buildTreeView(
    Map<String, dynamic> structure,
    List<String> currentPath,
  ) {
    List<Widget> children = [];

    // First add folders (non-track entries)
    final folderEntries =
        structure.entries
            .where((entry) => entry.key != "tracks" && entry.key != "rootPath")
            .toList()
          ..sort((a, b) {
            // Special folders come first
            if (a.key == "Web Links") return -1;
            if (b.key == "Web Links") return 1;
            if (a.key == "Imported Files") return -1;
            if (b.key == "Imported Files") return 1;
            // Then sort alphabetically
            return a.key.compareTo(b.key);
          });

    for (final entry in folderEntries) {
      final newPath = List<String>.from(currentPath)..add(entry.key);
      // *** Use '/' as the consistent separator for keys ***
      final folderPathKey = newPath.join('/');
      // Check expansion state using the consistent key
      final isExpanded = _expandedFolders.contains(folderPathKey);
      final isSpecialFolder =
          entry.key == "Web Links" || entry.key == "Imported Files";
      final isRootFolder = currentPath.isEmpty;

      // Count tracks in this folder
      final trackCount = _countTracksInFolder(
        entry.value as Map<String, dynamic>,
      );

      // Skip empty folders (except special folders and root folders)
      if (trackCount == 0 && !isSpecialFolder && !isRootFolder) {
        continue;
      }

      children.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () {
                setState(() {
                  // Use the consistent key for adding/removing
                  if (isExpanded) {
                    _expandedFolders.remove(folderPathKey);
                  } else {
                    _expandedFolders.add(folderPathKey);
                  }
                });
              },
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color:
                      isRootFolder
                          ? Theme.of(context).primaryColor.withOpacity(0.1)
                          : null,
                ),
                padding: EdgeInsets.only(
                  left: 16.0 * currentPath.length,
                  top: 8.0,
                  bottom: 8.0,
                  right: 8.0,
                ),
                child: Row(
                  children: [
                    // Use different icons for different folder types
                    Icon(
                      isExpanded ? Icons.folder_open : Icons.folder,
                      color:
                          isSpecialFolder
                              ? Colors.blueGrey
                              : isRootFolder
                              ? Colors.amber.shade700
                              : Colors.amber,
                      size: isRootFolder ? 22 : 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        entry.key,
                        style: TextStyle(
                          fontWeight:
                              isRootFolder || isSpecialFolder
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                          fontSize: isRootFolder ? 15 : 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Show track count badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color:
                            isRootFolder
                                ? Theme.of(
                                  context,
                                ).primaryColor.withOpacity(0.2)
                                : Colors.grey.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        trackCount.toString(),
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              isRootFolder
                                  ? Theme.of(context).primaryColor
                                  : Colors.grey[800],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (isExpanded)
              Padding(
                padding: const EdgeInsets.only(left: 4.0),
                child: _buildTreeView(
                  entry.value as Map<String, dynamic>,
                  newPath, // Pass the path segments for indentation calculation
                ),
              ),
          ],
        ),
      );
    }

    // Then add tracks at this level
    if (structure.containsKey("tracks")) {
      final dynamicList = structure["tracks"] as List<dynamic>;
      final tracks = dynamicList.map((item) => item as Track).toList();

      // Sort tracks alphabetically by title
      tracks.sort((a, b) => a.title.compareTo(b.title));

      for (final track in tracks) {
        bool isCurrentlyPlaying = widget.currentlyLoadedPath == track.path;
        bool isSelected = widget.selectedTrack?.id == track.id;

        children.add(
          InkWell(
            onTap: () => widget.onTrackSelected(track),
            child: Container(
              // Highlight if selected OR currently playing
              color:
                  isSelected || isCurrentlyPlaying
                      ? Theme.of(context).colorScheme.primary.withOpacity(0.15)
                      : null,
              padding: EdgeInsets.only(
                left: 16.0 * (currentPath.length + 1),
                top: 8.0,
                bottom: 8.0,
                right: 8.0,
              ),
              child: Row(
                children: [
                  Icon(
                    // Show play icon if currently playing
                    isCurrentlyPlaying
                        ? Icons.volume_up
                        : (track.isUrl ? Icons.link : Icons.music_note),
                    size: 18,
                    color:
                        isCurrentlyPlaying
                            ? Theme.of(context).colorScheme.primary
                            : (track.isUrl ? Colors.blue : Colors.grey[700]),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight:
                                isSelected || isCurrentlyPlaying
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                            color:
                                isCurrentlyPlaying
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                          ),
                        ),
                        if (track.artist.isNotEmpty &&
                            track.artist != 'Unknown')
                          Text(
                            track.artist,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  // Track rating (if any)
                  if (track.rating > 0)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(
                        5,
                        (index) => Icon(
                          index < track.rating ? Icons.star : Icons.star_border,
                          size: 14,
                          color: Colors.amber,
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  // Delete button
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed:
                        track.id != null
                            ? () => widget.onTrackDeleted(track.id!)
                            : null,
                    tooltip: 'Remove from collection',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  // Helper method to count total tracks in a folder (including subfolders)
  int _countTracksInFolder(Map<String, dynamic> folder) {
    int count = 0;

    // Count direct tracks in this folder
    if (folder.containsKey("tracks") && folder["tracks"] is List) {
      count += (folder["tracks"] as List).length;
    }

    // Count tracks in subfolders
    for (final entry in folder.entries) {
      if (entry.key != "tracks" &&
          entry.key != "rootPath" &&
          entry.value is Map<String, dynamic>) {
        // Ensure it's a map
        count += _countTracksInFolder(entry.value as Map<String, dynamic>);
      }
    }

    return count;
  }
}
