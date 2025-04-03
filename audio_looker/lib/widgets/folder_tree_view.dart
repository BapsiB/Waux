import 'package:flutter/material.dart';
import 'package:path/path.dart' as pathLib;
import 'package:audio_looker/services/collection_service.dart';

class FolderTreeView extends StatefulWidget {
  final List<Track> tracks;
  final Track? selectedTrack;
  final List<String> rootFolders; // Accept root folders from parent
  final Function(Track) onTrackSelected;
  final Function(int) onTrackDeleted;

  const FolderTreeView({
    Key? key,
    required this.tracks,
    this.selectedTrack,
    required this.rootFolders, // Required parameter
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

    // Expand the special folders by default
    _expandedFolders.add('Web Links');
    _expandedFolders.add('Imported Files');
  }

  @override
  void didUpdateWidget(FolderTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tracks != widget.tracks ||
        oldWidget.rootFolders != widget.rootFolders) {
      _buildFolderStructure();
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
          if (directory.startsWith(rootPath)) {
            // This file belongs to this root folder
            foundRoot = true;

            // Get the root folder name
            final rootName = pathLib.basename(rootPath);

            // Get the relative path from the root
            String relativePath = directory.substring(rootPath.length);
            // Normalize path separators and remove leading separator
            relativePath = relativePath.replaceAll('\\', '/');
            if (relativePath.startsWith('/')) {
              relativePath = relativePath.substring(1);
            }

            // Split into path segments
            List<String> pathSegments =
                relativePath.isEmpty ? [] : relativePath.split('/');

            // Make sure the root exists in our structure (in case it was just added)
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
            break;
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
      _addToStructure(
        structure[segment] as Map<String, dynamic>,
        pathSegments.sublist(1),
        track,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Show counts at the top
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: Text(
                "${widget.tracks.length} audio files | ${widget.rootFolders.length} root folders",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ),
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
      final folderPath = newPath.join('/');
      final isExpanded = _expandedFolders.contains(folderPath);
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
                  if (isExpanded) {
                    _expandedFolders.remove(folderPath);
                  } else {
                    _expandedFolders.add(folderPath);
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
                  newPath,
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
        children.add(
          InkWell(
            onTap: () => widget.onTrackSelected(track),
            child: Container(
              color:
                  widget.selectedTrack?.id == track.id
                      ? Theme.of(context).primaryColor.withOpacity(0.1)
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
                    track.isUrl ? Icons.link : Icons.music_note,
                    size: 18,
                    color: track.isUrl ? Colors.blue : Colors.grey[700],
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
                                widget.selectedTrack?.id == track.id
                                    ? FontWeight.bold
                                    : FontWeight.normal,
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
    if (folder.containsKey("tracks")) {
      count += (folder["tracks"] as List).length;
    }

    // Count tracks in subfolders
    for (final entry in folder.entries) {
      if (entry.key != "tracks" &&
          entry.key != "rootPath" &&
          entry.value is Map) {
        count += _countTracksInFolder(entry.value as Map<String, dynamic>);
      }
    }

    return count;
  }
}
