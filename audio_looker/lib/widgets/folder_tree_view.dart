import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as pathLib;
import 'package:audio_looker/services/collection_service.dart';

class FolderTreeView extends StatefulWidget {
  final List<Track> tracks;
  final Track? selectedTrack;
  final Function(Track) onTrackSelected;
  final Function(int) onTrackDeleted;

  const FolderTreeView({
    Key? key,
    required this.tracks,
    this.selectedTrack,
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
  }

  @override
  void didUpdateWidget(FolderTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tracks != widget.tracks) {
      _buildFolderStructure();
    }
  }

  // Build the folder structure from the track list
  void _buildFolderStructure() {
    _folderStructure = {};

    for (final track in widget.tracks) {
      if (track.isUrl) {
        // Handle URL tracks separately
        _addToStructure(_folderStructure, ['Web Links'], track);
      } else {
        // Get the directory path relative to the root collection folder
        final directory = pathLib.dirname(track.path);

        // Split the path into segments
        List<String> pathSegments = [];

        // On Windows, normalize backslashes
        final normalizedPath = directory.replaceAll('\\', '/');
        pathSegments = normalizedPath.split('/');

        // Remove empty segments that might occur at the start
        pathSegments =
            pathSegments.where((segment) => segment.isNotEmpty).toList();

        // Add the track to the folder structure
        _addToStructure(_folderStructure, pathSegments, track);
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
      if (!structure.containsKey('tracks')) {
        structure['tracks'] = [];
      }
      structure['tracks'].add(track);
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: _buildTreeView(_folderStructure, []),
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
        structure.entries.where((entry) => entry.key != 'tracks').toList()
          ..sort(
            (a, b) => a.key.compareTo(b.key),
          ); // Sort folders alphabetically

    for (final entry in folderEntries) {
      final newPath = List<String>.from(currentPath)..add(entry.key);
      final folderPath = newPath.join('/');
      final isExpanded = _expandedFolders.contains(folderPath);

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
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16.0 * currentPath.length,
                  top: 8.0,
                  bottom: 8.0,
                ),
                child: Row(
                  children: [
                    Icon(
                      isExpanded ? Icons.folder_open : Icons.folder,
                      color: Colors.amber,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        entry.key,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Optional: Add a count of tracks in this folder
                    Text(
                      _countTracksInFolder(entry.value).toString(),
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            if (isExpanded) _buildTreeView(entry.value, newPath),
          ],
        ),
      );
    }

    // Then add tracks at this level
    if (structure.containsKey('tracks')) {
      final dynamicList = structure['tracks'] as List<dynamic>;
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
              ),
              child: Row(
                children: [
                  const Icon(Icons.music_note, size: 18),
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
                        if (track.artist.isNotEmpty)
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
    if (folder.containsKey('tracks')) {
      count += (folder['tracks'] as List).length;
    }

    // Count tracks in subfolders
    for (final entry in folder.entries) {
      if (entry.key != 'tracks' && entry.value is Map) {
        count += _countTracksInFolder(entry.value);
      }
    }

    return count;
  }
}
