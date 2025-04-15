// lib/widgets/folder_tree_view.dart

import 'package:flutter/material.dart';
import 'package:path/path.dart' as pathLib;
import 'package:collection/collection.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:audio_looker/services/collection_service.dart';

typedef FolderDeleteCallback =
    void Function(String folderPath, String folderName);

class FolderTreeView extends StatefulWidget {
  final List<Track> tracks;
  final Track? selectedTrack;
  final List<String> rootFolders;
  final String? currentlyLoadedPath;
  final Function(Track) onTrackSelected;
  final Function(int) onTrackDeleted;
  final FolderDeleteCallback onFolderDeleted;

  const FolderTreeView({
    Key? key,
    required this.tracks,
    this.selectedTrack,
    required this.rootFolders,
    this.currentlyLoadedPath,
    required this.onTrackSelected,
    required this.onTrackDeleted,
    required this.onFolderDeleted,
  }) : super(key: key);

  @override
  State<FolderTreeView> createState() => _FolderTreeViewState();
}

class _FolderTreeViewState extends State<FolderTreeView> {
  late Map<String, dynamic> _folderStructure;
  final Set<String> _expandedFolders = {};
  final Set<String> _hoveredItems = {};
  Offset _tapPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    _buildFolderStructure();
    _expandFoldersForPath(widget.currentlyLoadedPath);
  }

  @override
  void didUpdateWidget(FolderTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    bool structureChanged = false;
    if (!const DeepCollectionEquality().equals(
          oldWidget.tracks,
          widget.tracks,
        ) ||
        !const DeepCollectionEquality().equals(
          oldWidget.rootFolders,
          widget.rootFolders,
        )) {
      _buildFolderStructure();
      structureChanged = true;
    }

    if (structureChanged ||
        oldWidget.currentlyLoadedPath != widget.currentlyLoadedPath) {
      _expandFoldersForPath(widget.currentlyLoadedPath);
    }

    if (widget.selectedTrack != oldWidget.selectedTrack) {
      if (mounted) {
        setState(() {
          _hoveredItems.clear();
        });
      }
    }
  }

  // --- Build Folder Structure Methods (Keep previous versions) ---
  void _buildFolderStructure() {
    _folderStructure = <String, dynamic>{};
    _folderStructure["Web Links"] = <String, dynamic>{"tracks": <dynamic>[]};
    _folderStructure["Imported Files"] = <String, dynamic>{
      "tracks": <dynamic>[],
    };

    for (final rootPath in widget.rootFolders) {
      final normalizedRootPath = rootPath.replaceAll(
        '\\',
        '/',
      ); // Normalize root path
      final rootName = pathLib.basename(normalizedRootPath);
      _folderStructure[rootName] = <String, dynamic>{
        "rootPath": normalizedRootPath, // Store normalized path
        "isRoot": true,
      };
    }

    for (final track in widget.tracks) {
      if (track.isUrl) {
        (_folderStructure["Web Links"]["tracks"] as List<dynamic>).add(track);
      } else {
        final filePath = track.path;
        final normalizedFilePath = filePath.replaceAll(
          '\\',
          '/',
        ); // Normalize track path
        final directory = pathLib.dirname(normalizedFilePath);

        bool foundRoot = false;
        for (final rootPath in widget.rootFolders) {
          final normalizedRootPath = rootPath.replaceAll('\\', '/');
          // Use normalized paths for comparison
          if (directory == normalizedRootPath ||
              directory.startsWith('$normalizedRootPath/')) {
            foundRoot = true;
            final rootName = pathLib.basename(normalizedRootPath);
            String relativePath = pathLib.relative(
              directory,
              from: normalizedRootPath,
            );
            relativePath = relativePath.replaceAll(
              '\\',
              '/',
            ); // Ensure relative path is normalized
            if (relativePath == '.') relativePath = '';

            List<String> pathSegments =
                relativePath.isEmpty ? [] : relativePath.split('/');

            // Ensure the root entry exists (it should from the loop above)
            if (!_folderStructure.containsKey(rootName)) {
              _folderStructure[rootName] = <String, dynamic>{
                "rootPath": normalizedRootPath,
                "isRoot": true,
              };
            }
            // *** Pass the parent's actual path for context ***
            _addToStructure(
              _folderStructure[rootName] as Map<String, dynamic>,
              pathSegments,
              track,
              normalizedRootPath,
            );
            break;
          }
        }
        if (!foundRoot) {
          (_folderStructure["Imported Files"]["tracks"] as List<dynamic>).add(
            track,
          );
        }
      }
    }
  }

  // *** Modify _addToStructure to accept and pass parent path ***
  void _addToStructure(
    Map<String, dynamic> structure,
    List<String> pathSegments,
    Track track,
    String parentAbsolutePath,
  ) {
    if (pathSegments.isEmpty) {
      if (!structure.containsKey("tracks")) structure["tracks"] = <dynamic>[];
      (structure["tracks"] as List<dynamic>).add(track);
    } else {
      final segment = pathSegments.first;
      // Calculate the absolute path for this segment
      final currentAbsolutePath = pathLib.join(parentAbsolutePath, segment);

      if (!structure.containsKey(segment)) {
        structure[segment] = <String, dynamic>{
          // Store the absolute path for this folder segment
          "folderAbsolutePath": currentAbsolutePath,
        };
      } else if (structure[segment] is Map<String, dynamic>) {
        // Ensure folderAbsolutePath exists if map already exists
        (structure[segment] as Map<String, dynamic>).putIfAbsent(
          "folderAbsolutePath",
          () => currentAbsolutePath,
        );
      }

      final nextLevel = structure[segment];
      if (nextLevel is Map<String, dynamic>) {
        // Pass the *current* segment's absolute path down
        _addToStructure(
          nextLevel,
          pathSegments.sublist(1),
          track,
          currentAbsolutePath,
        );
      } else {
        print(
          "Structure conflict: Expected Map for segment '$segment', found ${nextLevel.runtimeType}. Overwriting.",
        );
        structure[segment] = <String, dynamic>{
          "folderAbsolutePath": currentAbsolutePath,
        };
        _addToStructure(
          structure[segment] as Map<String, dynamic>,
          pathSegments.sublist(1),
          track,
          currentAbsolutePath,
        );
      }
    }
  }

  void _expandFoldersForPath(String? loadedPath) {
    if (loadedPath == null || loadedPath.isEmpty) return;
    bool changed = false;
    try {
      if (Uri.tryParse(loadedPath)?.isAbsolute ?? false) {
        if (_expandedFolders.add('Web Links')) changed = true;
      } else {
        final normalizedLoadedPath = loadedPath.replaceAll('\\', '/');
        final String directory = pathLib.dirname(normalizedLoadedPath);
        String? matchingRootPath;
        String? rootName;

        for (final root in widget.rootFolders) {
          final normalizedRoot = root.replaceAll('\\', '/');
          if (directory == normalizedRoot ||
              directory.startsWith('$normalizedRoot/')) {
            matchingRootPath = normalizedRoot;
            rootName = pathLib.basename(normalizedRoot);
            break;
          }
        }

        if (matchingRootPath != null && rootName != null) {
          String relativePath = pathLib.relative(
            directory,
            from: matchingRootPath,
          );
          relativePath = relativePath.replaceAll('\\', '/');
          if (relativePath == '.') relativePath = '';
          List<String> pathSegments =
              relativePath.isEmpty ? [] : relativePath.split('/');
          String currentPathKey = rootName;
          if (_expandedFolders.add(currentPathKey)) changed = true;
          for (final segment in pathSegments) {
            if (segment.isNotEmpty) {
              currentPathKey += '/$segment';
              if (_expandedFolders.add(currentPathKey)) changed = true;
            }
          }
        } else {
          if (_expandedFolders.add('Imported Files')) changed = true;
        }
      }
    } catch (e) {
      print("Error calculating expansion path for $loadedPath: $e");
    }
    if (changed && mounted) setState(() {});
  }

  void _storePosition(TapDownDetails details) {
    _tapPosition = details.globalPosition;
  }

  void _showTrackContextMenu(BuildContext context, Track track) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        _tapPosition & const Size(40, 40), // Small rectangle at tap pos
        Offset.zero & overlay.size, // Bigger rectangle of the overlay
      ),
      items: <PopupMenuEntry>[
        PopupMenuItem(
          value: 'reveal_enclosing', // Unique value for this action
          child: ListTile(
            leading: Icon(Icons.folder_open_outlined),
            title: Text('Open Enclosing Folder'),
          ),
        ),
        // Add other track-specific options here if needed (e.g., Play, Add to Playlist)
        // You might want to reuse logic from ContextMenuHandler if you add more options.
      ],
    ).then((value) {
      // Handle menu selection
      if (value == 'reveal_enclosing') {
        // Use the existing _revealFolderLocation, passing the file's *parent* directory
        _revealEnclosingFolder(track.path);
      }
    });
  }

  Future<void> _revealEnclosingFolder(String filePath) async {
    try {
      // Ensure the path is absolute before getting the directory
      if (!pathLib.isAbsolute(filePath)) {
        print(
          "Error revealing enclosing folder: Path is not absolute: $filePath",
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Cannot reveal location for relative path: $filePath",
            ),
          ),
        );
        return;
      }

      // Get the parent directory path
      final String directoryPath = pathLib.dirname(filePath);

      // Check if dirname returned the root or '.' which might not be launchable directly
      if (directoryPath == '.' ||
          directoryPath == '/' ||
          directoryPath == pathLib.dirname(directoryPath)) {
        print("Cannot reveal root or invalid directory: $directoryPath");
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Cannot open directory: $directoryPath")),
        );
        return;
      }

      final Uri directoryUri = Uri.file(directoryPath);

      if (await canLaunchUrl(directoryUri)) {
        await launchUrl(directoryUri);
      } else {
        throw Exception('Could not launch directory URI: $directoryUri');
      }
    } catch (e) {
      print("Error revealing enclosing folder: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Could not open enclosing folder: $e")),
      );
    }
  }

  void _showFolderContextMenu(
    BuildContext context,
    String folderName,
    String folderAbsolutePath,
  ) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        _tapPosition & const Size(40, 40), // Small rectangle at tap pos
        Offset.zero & overlay.size, // Bigger rectangle of the overlay
      ),
      items: <PopupMenuEntry>[
        PopupMenuItem(
          value: 'reveal', // Unique value for this action
          child: ListTile(
            leading: Icon(Icons.folder_open),
            // Optional: Use Platform.isMacOS ? 'Reveal in Finder' : 'Show in Explorer'
            title: Text('Reveal in Finder'),
          ),
        ),
        // Add other folder-specific options here if needed
      ],
    ).then((value) {
      // Handle menu selection
      if (value == 'reveal') {
        _revealFolderLocation(folderAbsolutePath);
      }
    });
  }

  Future<void> _revealFolderLocation(String folderPath) async {
    try {
      // The folderPath received should already be absolute
      if (!pathLib.isAbsolute(folderPath)) {
        print("Error revealing folder: Path is not absolute: $folderPath");
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Cannot reveal relative path: $folderPath")),
        );
        return;
      }

      // We want to open the folder itself, not its parent like for files
      final Uri directoryUri = Uri.file(folderPath);

      if (await canLaunchUrl(directoryUri)) {
        await launchUrl(directoryUri);
      } else {
        throw Exception('Could not launch directory URI: $directoryUri');
      }
    } catch (e) {
      print("Error revealing folder location: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Could not open folder: $e")));
    }
  }

  // --- Build Methods ---
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          // *** Pass the initial parent path (empty string for top level) ***
          children: [_buildTreeView(_folderStructure, [], "")],
        ),
      ),
    );
  }

  // *** Modify _buildTreeView to accept and pass parent path ***
  Widget _buildTreeView(
    Map<String, dynamic> structure,
    List<String> currentPathSegments,
    String parentAbsolutePath,
  ) {
    List<Widget> children = [];

    // --- Render Folders ---
    final folderEntries =
        structure.entries
            .where(
              (entry) =>
                  entry.key != "tracks" &&
                  entry.key != "rootPath" &&
                  entry.key != "isRoot" &&
                  entry.key != "folderAbsolutePath",
            ) // Exclude helper keys
            .toList()
          ..sort((a, b) {
            if (a.key == "Web Links") return -1;
            if (b.key == "Web Links") return 1;
            if (a.key == "Imported Files") return -1;
            if (b.key == "Imported Files") return 1;
            return a.key.toLowerCase().compareTo(b.key.toLowerCase());
          });

    for (final entry in folderEntries) {
      final newPathSegments = List<String>.from(currentPathSegments)
        ..add(entry.key);
      final folderPathKey = newPathSegments.join(
        '/',
      ); // Key for expansion/hover
      final isExpanded = _expandedFolders.contains(folderPathKey);
      final isSpecialFolder =
          entry.key == "Web Links" || entry.key == "Imported Files";
      final folderData = entry.value as Map<String, dynamic>? ?? {};
      final isRootFolder = folderData["isRoot"] == true;
      final trackCount = _countTracksInFolder(folderData);

      // *** Determine the correct absolute path for THIS folder ***
      String currentFolderAbsolutePath;
      if (isRootFolder) {
        currentFolderAbsolutePath =
            folderData["rootPath"] as String? ??
            entry.key; // Use stored rootPath
      } else {
        // Construct path from parent and current segment name
        // Use folderAbsolutePath stored during _addToStructure if available, otherwise construct it
        currentFolderAbsolutePath =
            folderData["folderAbsolutePath"] as String? ??
            pathLib.join(parentAbsolutePath, entry.key);
      }
      // Normalize just in case
      currentFolderAbsolutePath = pathLib.normalize(
        currentFolderAbsolutePath.replaceAll('\\', '/'),
      );

      if (trackCount == 0 && !isSpecialFolder && !isRootFolder) continue;

      children.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTapDown:
                  (details) =>
                      _storePosition(details), // Store position for menu
              onSecondaryTapDown:
                  (details) =>
                      _storePosition(details), // Store position for menu
              onSecondaryTap: () {
                // Only show context menu for non-special folders
                if (!isSpecialFolder) {
                  _showFolderContextMenu(
                    context,
                    entry.key,
                    currentFolderAbsolutePath,
                  );
                }
              },
              child: MouseRegion(
                // Wrap only the interactive row
                onEnter:
                    (_) => setState(() => _hoveredItems.add(folderPathKey)),
                onExit:
                    (_) => setState(() => _hoveredItems.remove(folderPathKey)),
                child: InkWell(
                  onTap:
                      () => setState(() {
                        if (isExpanded)
                          _expandedFolders.remove(folderPathKey);
                        else
                          _expandedFolders.add(folderPathKey);
                      }),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color:
                          _hoveredItems.contains(folderPathKey)
                              ? Theme.of(context).hoverColor
                              : (isRootFolder
                                  ? Theme.of(
                                    context,
                                  ).primaryColor.withOpacity(0.05)
                                  : null),
                    ),
                    padding: EdgeInsets.only(
                      left: 16.0 * currentPathSegments.length,
                      top: 6.0,
                      bottom: 6.0,
                      right: 8.0,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isExpanded ? Icons.folder_open : Icons.folder,
                          color:
                              isSpecialFolder
                                  ? Colors.blueGrey.shade400
                                  : (isRootFolder
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.amber.shade700),
                          size: isRootFolder ? 20 : 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            entry.key, // Display name
                            style: TextStyle(
                              fontWeight:
                                  isRootFolder || isSpecialFolder
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                              fontSize: isRootFolder ? 14 : 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Visibility(
                          visible:
                              _hoveredItems.contains(folderPathKey) &&
                              !isSpecialFolder,
                          maintainSize: true,
                          maintainAnimation: true,
                          maintainState: true,
                          child: IconButton(
                            icon: Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: Colors.redAccent.shade100,
                            ),
                            onPressed: () {
                              // *** Pass the calculated absolute path ***
                              print(
                                "Delete requested for Absolute Path: $currentFolderAbsolutePath (display name: ${entry.key})",
                              );
                              widget.onFolderDeleted(
                                currentFolderAbsolutePath,
                                entry.key,
                              );
                            },
                            tooltip: 'Remove Folder',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ),
                        Visibility(
                          visible:
                              !(_hoveredItems.contains(folderPathKey) &&
                                  !isSpecialFolder),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  isRootFolder
                                      ? Theme.of(
                                        context,
                                      ).primaryColor.withOpacity(0.1)
                                      : Colors.grey.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              trackCount.toString(),
                              style: TextStyle(
                                fontSize: 11,
                                color:
                                    isRootFolder
                                        ? Theme.of(context).primaryColor
                                        : Colors.grey[700],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // *** Pass the current folder's absolute path down to children ***
            if (isExpanded)
              Padding(
                padding: const EdgeInsets.only(left: 0.0),
                child: _buildTreeView(
                  folderData,
                  newPathSegments,
                  currentFolderAbsolutePath,
                ),
              ),
          ],
        ),
      );
    }

    // --- Render Tracks (Keep previous version, no changes needed here) ---
    if (structure.containsKey("tracks") &&
        structure["tracks"] is List &&
        (structure["tracks"] as List).isNotEmpty) {
      final tracks =
          (structure["tracks"] as List).cast<Track>().toList(); // Safe casting
      tracks.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      ); // Sort tracks

      for (final track in tracks) {
        final isCurrentlyPlaying = widget.currentlyLoadedPath == track.path;
        final isSelected = widget.selectedTrack?.id == track.id;
        final trackHoverKey =
            'track_${track.id ?? track.path}'; // Use path as fallback key

        children.add(
          Padding(
            // Use padding for indentation
            padding: EdgeInsets.only(left: 16.0 * currentPathSegments.length),
            child: GestureDetector(
              // <<< Wrap existing MouseRegion/InkWell
              onTapDown: _storePosition, // Store position for menu
              onSecondaryTapDown: _storePosition, // Store position for menu
              onSecondaryTap: () {
                // Only show context menu for local files, not URLs
                if (!track.isUrl) {
                  _showTrackContextMenu(context, track);
                }
              },
              child: MouseRegion(
                onEnter:
                    (_) => setState(() => _hoveredItems.add(trackHoverKey)),
                onExit:
                    (_) => setState(() => _hoveredItems.remove(trackHoverKey)),
                child: InkWell(
                  onTap: () => widget.onTrackSelected(track),
                  child: Container(
                    color:
                        isSelected || isCurrentlyPlaying
                            ? Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(0.1)
                            : (_hoveredItems.contains(trackHoverKey)
                                ? Theme.of(context).hoverColor
                                : null),
                    padding: const EdgeInsets.only(
                      left: 16 + 4,
                      top: 6.0,
                      bottom: 6.0,
                      right: 8.0,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isCurrentlyPlaying
                              ? Icons.volume_up
                              : (track.isUrl ? Icons.link : Icons.music_note),
                          size: 16,
                          color:
                              isCurrentlyPlaying
                                  ? Theme.of(context).colorScheme.primary
                                  : (track.isUrl
                                      ? Colors.blueAccent.shade100
                                      : Colors.grey.shade600),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                track.title,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight:
                                      isSelected || isCurrentlyPlaying
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                  color:
                                      isCurrentlyPlaying
                                          ? Theme.of(
                                            context,
                                          ).colorScheme.primary
                                          : null,
                                ),
                              ),
                              if (track.artist.isNotEmpty &&
                                  track.artist != 'Unknown')
                                Text(
                                  track.artist,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 11,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (track.rating > 0)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(
                              5,
                              (index) => Icon(
                                index < track.rating
                                    ? Icons.star
                                    : Icons.star_border,
                                size: 13,
                                color: Colors.amber.shade600,
                              ),
                            ),
                          ),
                        const SizedBox(width: 4),
                        Visibility(
                          visible: _hoveredItems.contains(trackHoverKey),
                          maintainSize: true,
                          maintainAnimation: true,
                          maintainState: true,
                          child: IconButton(
                            icon: Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: Colors.redAccent.shade100,
                            ),
                            onPressed:
                                track.id != null
                                    ? () => widget.onTrackDeleted(track.id!)
                                    : null,
                            tooltip: 'Remove from collection',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ),
                        if (!_hoveredItems.contains(trackHoverKey))
                          const SizedBox(width: 40),
                      ],
                    ),
                  ),
                ),
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

  int _countTracksInFolder(Map<String, dynamic> folder) {
    int count = 0;
    if (folder.containsKey("tracks") && folder["tracks"] is List) {
      count += (folder["tracks"] as List).length;
    }
    for (final entry in folder.entries) {
      if (entry.key != "tracks" &&
          entry.key != "rootPath" &&
          entry.key != "isRoot" &&
          entry.key != "folderAbsolutePath" &&
          entry.value is Map<String, dynamic>) {
        count += _countTracksInFolder(entry.value as Map<String, dynamic>);
      }
    }
    return count;
  }
}
