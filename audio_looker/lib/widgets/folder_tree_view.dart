// lib/widgets/folder_tree_view.dart

import 'package:flutter/material.dart';
import 'package:path/path.dart' as pathLib;
import 'package:collection/collection.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:audio_looker/services/collection_service.dart';
import 'package:flutter/services.dart';

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
  final ValueNotifier<Set<LogicalKeyboardKey>> pressedKeysNotifier;

  const FolderTreeView({
    Key? key,
    required this.tracks,
    this.selectedTrack,
    required this.rootFolders,
    this.currentlyLoadedPath,
    required this.onTrackSelected,
    required this.onTrackDeleted,
    required this.onFolderDeleted,
    required this.pressedKeysNotifier,
  }) : super(key: key);

  @override
  State<FolderTreeView> createState() => _FolderTreeViewState();
}

class _FolderTreeViewState extends State<FolderTreeView> {
  late Map<String, dynamic> _folderStructure;
  final Set<String> _expandedFolders = {};
  final Set<String> _hoveredItems = {};
  Offset _tapPosition = Offset.zero;

  final Set<String> _selectedNodeKeys = {};
  // Store the key of the last item clicked without Shift (anchor for range selection)
  String? _anchorNodeKey;
  // Keep track of the last known keyboard modifiers
  final ValueNotifier<Set<LogicalKeyboardKey>> _pressedKeys =
      ValueNotifier<Set<LogicalKeyboardKey>>({});

  Set<LogicalKeyboardKey> get _currentPressedKeys =>
      widget.pressedKeysNotifier.value;

  // Helper to generate a unique key for a track
  String _getTrackNodeKey(Track track) {
    // Ensure a unique prefix to avoid clashes with folder paths
    return 'track_${track.id ?? track.path}';
  }

  @override
  void initState() {
    super.initState();
    _buildFolderStructure();
    _expandFoldersForPath(widget.currentlyLoadedPath);
  }

  @override
  void dispose() {
    _pressedKeys.dispose(); // Dispose the notifier
    super.dispose();
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

  void _handleItemTap(String tappedNodeKey, {required bool isFolder}) {
    // Use the getter to access the current keys from the widget's notifier
    final Set<LogicalKeyboardKey> keysPressed =
        HardwareKeyboard.instance.logicalKeysPressed;
    final bool isShiftPressed =
        keysPressed.contains(LogicalKeyboardKey.shiftLeft) ||
        keysPressed.contains(LogicalKeyboardKey.shiftRight);
    final bool isCtrlPressed =
        keysPressed.contains(LogicalKeyboardKey.controlLeft) ||
        keysPressed.contains(LogicalKeyboardKey.controlRight) ||
        keysPressed.contains(
          LogicalKeyboardKey.metaLeft,
        ) || // For macOS Command key
        keysPressed.contains(LogicalKeyboardKey.metaRight);

    print(
      "Tapped: $tappedNodeKey, Shift: $isShiftPressed, Ctrl: $isCtrlPressed",
    ); // Debugging

    setState(() {
      if (isCtrlPressed) {
        // Toggle selection for the clicked item
        if (_selectedNodeKeys.contains(tappedNodeKey)) {
          _selectedNodeKeys.remove(tappedNodeKey);
          // Adjust anchor if the removed item was the anchor
          if (_anchorNodeKey == tappedNodeKey) {
            _anchorNodeKey =
                _selectedNodeKeys.isNotEmpty ? _selectedNodeKeys.last : null;
          }
        } else {
          _selectedNodeKeys.add(tappedNodeKey);
          _anchorNodeKey = tappedNodeKey; // Set anchor on Ctrl+add
        }
      } else if (isShiftPressed && _anchorNodeKey != null) {
        // Range selection
        final List<String> visibleNodeKeys =
            _getVisibleNodeKeys(); // Needs implementation
        final int anchorIndex = visibleNodeKeys.indexOf(_anchorNodeKey!);
        final int clickedIndex = visibleNodeKeys.indexOf(tappedNodeKey);

        if (anchorIndex != -1 && clickedIndex != -1) {
          final int start =
              anchorIndex < clickedIndex ? anchorIndex : clickedIndex;
          final int end =
              anchorIndex > clickedIndex ? anchorIndex : clickedIndex;

          // Clear previous selection ONLY if Ctrl is NOT pressed
          if (!isCtrlPressed) {
            _selectedNodeKeys.clear();
          }

          // Select the range
          for (int i = start; i <= end; i++) {
            if (i >= 0 && i < visibleNodeKeys.length) {
              _selectedNodeKeys.add(visibleNodeKeys[i]);
            }
          }
          // Anchor remains the same for shift-range selection
        } else {
          // If anchor or clicked item not found in visible list, just select the clicked one
          _selectedNodeKeys.clear();
          _selectedNodeKeys.add(tappedNodeKey);
          _anchorNodeKey = tappedNodeKey;
        }
      } else {
        // Simple click: Select only the clicked item
        _selectedNodeKeys.clear();
        _selectedNodeKeys.add(tappedNodeKey);
        _anchorNodeKey = tappedNodeKey;
      }

      // --- Single Selection Behavior (Original Logic) ---
      // If it's a track, call the original callback for player interaction
      // if (!isFolder) {
      //   // Find the track corresponding to the key
      //   // This requires iterating through the built structure or having a map
      //   Track? tappedTrack = _findTrackByKey(tappedNodeKey);
      //   if (tappedTrack != null) {
      //     widget.onTrackSelected(tappedTrack);
      //   }
      // }
      // --- End Single Selection Behavior ---
    });
  }

  List<String> _getVisibleNodeKeys() {
    List<String> keys = [];
    // Recursive helper function to traverse the structure
    void traverse(
      Map<String, dynamic> structure,
      List<String> currentPathSegments,
    ) {
      final sortedFolderKeys =
          structure.entries
              .where(
                (entry) =>
                    entry.key != "tracks" &&
                    entry.key != "rootPath" &&
                    entry.key != "isRoot" &&
                    entry.key != "folderAbsolutePath",
              )
              .map((e) => e.key)
              .toList()
            ..sort((a, b) {
              // Add your sorting logic from _buildTreeView here if needed
              if (a == "Web Links") return -1;
              if (b == "Web Links") return 1;
              if (a == "Imported Files") return -1;
              if (b == "Imported Files") return 1;
              return a.toLowerCase().compareTo(b.toLowerCase());
            });

      for (final key in sortedFolderKeys) {
        final newPathSegments = List<String>.from(currentPathSegments)
          ..add(key);
        final folderPathKey = newPathSegments.join('/');
        keys.add(folderPathKey); // Add folder key

        final isExpanded = _expandedFolders.contains(folderPathKey);
        if (isExpanded && structure[key] is Map<String, dynamic>) {
          traverse(
            structure[key] as Map<String, dynamic>,
            newPathSegments,
          ); // Recurse if expanded
        }
      }

      // Add tracks at this level
      if (structure.containsKey("tracks") && structure["tracks"] is List) {
        final tracks = (structure["tracks"] as List).cast<Track>().toList();
        tracks.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        ); // Sort tracks
        for (final track in tracks) {
          keys.add(_getTrackNodeKey(track)); // Add track key
        }
      }
    }

    traverse(_folderStructure, []); // Start traversal from root
    // print("Visible Keys: $keys"); // Debugging
    return keys;
  }

  Track? _findTrackByKey(String nodeKey) {
    if (!nodeKey.startsWith('track_')) return null;

    Track? foundTrack;
    void search(Map<String, dynamic> structure) {
      if (foundTrack != null) return; // Stop if found

      if (structure.containsKey("tracks") && structure["tracks"] is List) {
        final tracks = (structure["tracks"] as List).cast<Track>();
        for (final track in tracks) {
          if (_getTrackNodeKey(track) == nodeKey) {
            foundTrack = track;
            return;
          }
        }
      }

      // Recurse into subfolders
      structure.forEach((key, value) {
        if (value is Map<String, dynamic> &&
            key != "tracks" &&
            key != "rootPath" &&
            key != "isRoot" &&
            key != "folderAbsolutePath") {
          search(value);
        }
      });
    }

    search(_folderStructure);
    return foundTrack;
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

  void _showItemContextMenu(
    BuildContext context,
    String nodeKey,
    bool isFolder,
  ) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final bool isMultiSelect = _selectedNodeKeys.length > 1;
    final bool isClickedItemSelected = _selectedNodeKeys.contains(nodeKey);

    List<PopupMenuEntry<dynamic>> items = [];

    // --- Add Play/Reveal based on single item type ---
    if (!isMultiSelect && isClickedItemSelected) {
      // Only show these for single selected item
      if (isFolder) {
        final folderData = _findNodeData(nodeKey); // Helper needed
        if (folderData != null) {
          final folderName = nodeKey.split('/').last;
          final folderAbsolutePath =
              folderData["folderAbsolutePath"] as String? ??
              folderData["rootPath"] as String? ??
              nodeKey; // Get path
          items.add(
            PopupMenuItem(
              value: {'action': 'reveal_folder', 'path': folderAbsolutePath},
              child: const ListTile(
                leading: Icon(Icons.folder_open),
                title: Text('Reveal Folder'),
              ),
            ),
          );
        }
      } else {
        // It's a track
        Track? track = _findTrackByKey(nodeKey);
        if (track != null) {
          if (!track.isUrl) {
            items.add(
              PopupMenuItem(
                value: {'action': 'reveal_track_location', 'path': track.path},
                child: const ListTile(
                  leading: Icon(Icons.folder_open_outlined),
                  title: Text('Open Enclosing Folder'),
                ),
              ),
            );
          }
          // Add other single-track actions if needed (Play, Add to Playlist...)
        }
      }
    }

    // --- Add Delete Action ---
    if (isClickedItemSelected || isMultiSelect) {
      // Show delete if clicking a selected item OR if multiple items selected
      items.add(const PopupMenuDivider());
      items.add(
        PopupMenuItem(
          value: {'action': 'delete_selection'}, // Use a map for clarity
          child: ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: Text(
              isMultiSelect
                  ? 'Delete ${_selectedNodeKeys.length} Selected Items'
                  : 'Delete Item',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),
      );
    }

    if (items.isEmpty) return; // Don't show empty menu

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        _tapPosition & const Size(40, 40), // Small rectangle at tap pos
        Offset.zero & overlay.size,
      ),
      items: items,
    ).then((value) {
      if (value is Map<String, dynamic>) {
        _handleContextMenuSelection(value);
      }
    });
  }

  // --- NEW: Handle Context Menu Selection ---
  void _handleContextMenuSelection(Map<String, dynamic> value) {
    final action = value['action'];

    if (action == 'delete_selection') {
      _deleteSelectedItems();
    } else if (action == 'reveal_folder') {
      _revealFolderLocation(value['path'] as String);
    } else if (action == 'reveal_track_location') {
      _revealEnclosingFolder(value['path'] as String);
    }
    // Handle other actions...
  }

  // --- NEW: Delete Selected Items Logic ---
  void _deleteSelectedItems() {
    if (_selectedNodeKeys.isEmpty) return;

    // Optional: Show confirmation dialog
    showDialog(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text('Confirm Delete'),
            content: Text(
              'Are you sure you want to delete ${_selectedNodeKeys.length} selected item(s)? Folders will be removed recursively.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text('Cancel'),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () {
                  Navigator.pop(dialogContext);
                  // Proceed with deletion
                  final keysToDelete = Set<String>.from(
                    _selectedNodeKeys,
                  ); // Copy the set
                  setState(() {
                    _selectedNodeKeys.clear(); // Clear selection in UI
                    _anchorNodeKey = null;
                  });

                  for (final nodeKey in keysToDelete) {
                    if (nodeKey.startsWith('track_')) {
                      Track? track = _findTrackByKey(nodeKey);
                      if (track?.id != null) {
                        print("Dispatching RemoveTrack for ${track!.id}");
                        widget.onTrackDeleted(
                          track.id!,
                        ); // Use existing callback
                      }
                    } else {
                      // It's a folder path key
                      final folderData = _findNodeData(
                        nodeKey,
                      ); // Helper needed
                      if (folderData != null) {
                        final folderName = nodeKey.split('/').last;
                        // Determine the correct absolute path to delete
                        final folderAbsolutePath =
                            folderData["folderAbsolutePath"] as String? ??
                            folderData["rootPath"] as String? ??
                            nodeKey; // Get path reliably
                        print(
                          "Dispatching DeleteFolder for $folderName ($folderAbsolutePath)",
                        );
                        widget.onFolderDeleted(
                          folderAbsolutePath,
                          folderName,
                        ); // Use existing callback
                      }
                    }
                  }
                },
                child: Text('Delete'),
              ),
            ],
          ),
    );
  }

  // --- NEW: Helper to find node data (folder path needed) ---
  Map<String, dynamic>? _findNodeData(String nodeKey) {
    List<String> segments = nodeKey.split('/');
    Map<String, dynamic>? currentLevel = _folderStructure;
    for (int i = 0; i < segments.length; i++) {
      final segment = segments[i];
      if (currentLevel != null &&
          currentLevel.containsKey(segment) &&
          currentLevel[segment] is Map<String, dynamic>) {
        currentLevel = currentLevel[segment] as Map<String, dynamic>;
        // If this is the last segment, return the data for this node
        if (i == segments.length - 1) {
          return currentLevel;
        }
      } else {
        return null; // Path not found or structure mismatch
      }
    }
    return null; // Should not happen if segments is not empty
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

      final bool isSelected = _selectedNodeKeys.contains(folderPathKey);

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
                _showItemContextMenu(context, folderPathKey, true);
              },
              child: MouseRegion(
                // Wrap only the interactive row
                onEnter:
                    (_) => setState(() => _hoveredItems.add(folderPathKey)),
                onExit:
                    (_) => setState(() => _hoveredItems.remove(folderPathKey)),
                child: InkWell(
                  onTap: () {
                    // --- MODIFIED Call ---
                    _handleItemTap(folderPathKey, isFolder: true);
                    // Original expansion logic:
                    setState(() {
                      if (isExpanded)
                        _expandedFolders.remove(folderPathKey);
                      else
                        _expandedFolders.add(folderPathKey);
                    });
                    // --- END MODIFIED ---
                  },
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
        final trackNodeKey = _getTrackNodeKey(track); // <<< NEW Track Key
        final bool isSelected = _selectedNodeKeys.contains(
          trackNodeKey,
        ); // <<< NEW Check selection
        final isCurrentlyPlaying =
            widget.currentlyLoadedPath == track.path; // Keep this
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
                _showItemContextMenu(context, trackNodeKey, false);
              },
              child: MouseRegion(
                onEnter:
                    (_) => setState(() => _hoveredItems.add(trackHoverKey)),
                onExit:
                    (_) => setState(() => _hoveredItems.remove(trackHoverKey)),
                child: InkWell(
                  onTap: () => _handleItemTap(trackNodeKey, isFolder: false),

                  child: Container(
                    decoration:
                        isSelected
                            ? BoxDecoration(
                              color:
                                  isSelected // Prioritize selection color
                                      ? Theme.of(
                                        context,
                                      ).colorScheme.primary.withOpacity(0.2)
                                      : isCurrentlyPlaying // Then playing color
                                      ? Theme.of(
                                        context,
                                      ).colorScheme.primary.withOpacity(0.1)
                                      : (_hoveredItems.contains(
                                            trackHoverKey,
                                          ) // Then hover
                                          ? Theme.of(context).hoverColor
                                          : null),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 0.8,
                              ),
                            )
                            : null,

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
