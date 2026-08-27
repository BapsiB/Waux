// lib/widgets/tag_editor_popup.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Required for RawKeyboardListener and LogicalKeyboardKey
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

// Import BLoCs
import '../blocs/track_management/track_metadata_bloc.dart';
import '../blocs/track_management/global_tag_bloc.dart';

// Import Models
import '../services/collection_service.dart'; // Make sure Tag model is accessible

class TagEditorPopup extends StatefulWidget {
  final List<int> trackIds; // Changed from single trackId to list
  final Map<int, List<String>> trackTags; // Map of trackId to its current tags

  const TagEditorPopup({
    Key? key,
    required this.trackIds,
    required this.trackTags,
  }) : super(key: key);

  @override
  _TagEditorPopupState createState() => _TagEditorPopupState();
}

class _TagEditorPopupState extends State<TagEditorPopup> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _availableTagsScrollController = ScrollController();
  String _searchTerm = '';

  // State for tracking changes
  late Map<int, Set<String>> _originalTrackTags; // Original state
  late Map<int, Set<String>> _pendingTrackTags; // Pending changes
  late Set<String> _commonTags; // Tags common to all tracks
  late Set<String> _partialTags; // Tags in some tracks

  // Autocomplete State
  String? _suggestion;
  String? _suggestedTag;

  // Constants for Alignment
  final EdgeInsets _textFieldPadding = const EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 12,
  );
  final double _prefixIconTotalWidth = 33.0;

  @override
  void initState() {
    super.initState();
    // Initialize state tracking
    _originalTrackTags = {};
    _pendingTrackTags = {};

    // Convert lists to sets for easier comparison
    widget.trackTags.forEach((trackId, tags) {
      _originalTrackTags[trackId] = Set<String>.from(tags);
      _pendingTrackTags[trackId] = Set<String>.from(tags);
    });

    _updateTagSets();

    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusScope.of(context).requestFocus(_searchFocusNode);
      }
    });
  }

  void _updateTagSets() {
    if (widget.trackIds.isEmpty) return;

    // Get all unique tags across all tracks
    final allTags = _pendingTrackTags.values.expand((tags) => tags).toSet();

    // Find tags common to all tracks
    _commonTags =
        allTags
            .where(
              (tag) => _pendingTrackTags.values.every(
                (trackTags) => trackTags.contains(tag),
              ),
            )
            .toSet();

    // Find tags that are in some but not all tracks
    _partialTags =
        allTags
            .where(
              (tag) =>
                  _pendingTrackTags.values.any(
                    (trackTags) => trackTags.contains(tag),
                  ) &&
                  !_commonTags.contains(tag),
            )
            .toSet();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _availableTagsScrollController.dispose();
    super.dispose();
  }

  // Update search term and find autocomplete suggestions
  void _onSearchChanged() {
    if (!mounted) return;
    final currentText = _searchController.text;
    setState(() {
      _searchTerm = currentText.toLowerCase();
      _suggestion = null;
      _suggestedTag = null;

      if (_searchTerm.isNotEmpty) {
        // <<< CHANGED: Read from GlobalTagBloc >>>
        final tagState = context.read<GlobalTagBloc>().state;
        if (tagState is GlobalTagLoaded) {
          // Find the first available tag that starts with the search term,
          // is not the exact search term, and is not already selected for this track.
          final potentialSuggestion = tagState.allTags.firstWhere(
            (tag) =>
                tag.name.toLowerCase().startsWith(_searchTerm) &&
                tag.name.toLowerCase() != _searchTerm &&
                !_pendingTrackTags[widget.trackIds.first]!.contains(
                  tag.name,
                ), // Check against track's assigned tags
            orElse: () => Tag(name: ''), // Return dummy tag if not found
          );

          if (potentialSuggestion.name.isNotEmpty) {
            _suggestedTag = potentialSuggestion.name;
            // Calculate the part of the suggestion to display
            _suggestion = potentialSuggestion.name.substring(
              currentText.length,
            );
          }
        }
      }
    });
  }

  // Handle keyboard events (Tab for autocomplete, Enter to add/create)
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!mounted) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.tab && _suggestedTag != null) {
        _acceptSuggestion();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.enter &&
          _searchController.text.trim().isNotEmpty) {
        _createOrToggleTag(); // Changed name for clarity
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  // Autocomplete the suggestion when Tab is pressed
  void _acceptSuggestion() {
    if (_suggestedTag != null) {
      if (!mounted) return;
      setState(() {
        _searchController.text = _suggestedTag!;
        // Move cursor to the end
        _searchController.selection = TextSelection.fromPosition(
          TextPosition(offset: _searchController.text.length),
        );
        _suggestion = null; // Clear suggestion display
        _suggestedTag = null; // Clear suggestion state
        _searchTerm =
            _searchController.text.toLowerCase(); // Update search term
      });
    }
  }

  // Modified to handle multiple tracks
  void _createOrToggleTag() {
    final tagName = _searchController.text.trim();
    if (tagName.isEmpty) return;

    final tagState = context.read<GlobalTagBloc>().state;
    if (tagState is GlobalTagLoaded) {
      final allGlobalTags = tagState.allTags;
      final existingGlobalTag = allGlobalTags.firstWhere(
        (t) => t.name.toLowerCase() == tagName.toLowerCase(),
        orElse: () => Tag(name: ''),
      );

      if (existingGlobalTag.name.isNotEmpty) {
        // Tag exists globally
        final exactTagName = existingGlobalTag.name;

        // Check if tag is in all tracks
        final isInAllTracks = _pendingTrackTags.values.every(
          (trackTags) => trackTags.contains(exactTagName),
        );

        if (isInAllTracks) {
          // Remove from all tracks
          for (final trackId in widget.trackIds) {
            _pendingTrackTags[trackId]?.remove(exactTagName);
          }
        } else {
          // Add to all tracks
          for (final trackId in widget.trackIds) {
            _pendingTrackTags[trackId]?.add(exactTagName);
          }
        }
      } else {
        // Create new tag and add to all tracks
        final newTag = Tag(name: tagName);
        context.read<GlobalTagBloc>().add(AddGlobalTag(newTag));

        for (final trackId in widget.trackIds) {
          _pendingTrackTags[trackId]?.add(tagName);
        }
      }

      _updateTagSets();

      // Clear search input after action
      _searchController.clear();
      if (mounted) {
        setState(() {
          _suggestion = null;
          _suggestedTag = null;
          _searchTerm = '';
        });
        FocusScope.of(context).requestFocus(_searchFocusNode);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Global tags not loaded yet.')),
      );
    }
  }

  void _applyChanges() {
    // Apply pending changes to all tracks
    for (final trackId in widget.trackIds) {
      final originalTags = _originalTrackTags[trackId] ?? {};
      final pendingTags = _pendingTrackTags[trackId] ?? {};

      // Remove tags that were removed
      for (final tag in originalTags) {
        if (!pendingTags.contains(tag)) {
          context.read<TrackMetadataBloc>().add(
            RemoveTrackGeneralTag(trackId, tag),
          );
        }
      }

      // Add tags that were added
      for (final tag in pendingTags) {
        if (!originalTags.contains(tag)) {
          context.read<TrackMetadataBloc>().add(
            AddTrackGeneralTag(trackId, tag),
          );
        }
      }
    }

    Navigator.of(context).pop();
  }

  void _cancelChanges() {
    Navigator.of(context).pop();
  }

  // Show color picker dialog
  void _showColorPicker(BuildContext context, Tag tag) {
    Color currentColor = tag.color ?? Colors.grey; // Default color if null
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Select Color for "${tag.name}"'),
          content: SingleChildScrollView(
            child: BlockPicker(
              // Or MaterialPicker, etc.
              pickerColor: currentColor,
              onColorChanged: (color) {
                currentColor = color;
              },
              availableColors: [
                // Predefined palette
                Colors.red, Colors.pink, Colors.purple, Colors.deepPurple,
                Colors.indigo, Colors.blue, Colors.lightBlue, Colors.cyan,
                Colors.teal, Colors.green, Colors.lightGreen, Colors.lime,
                Colors.yellow, Colors.amber, Colors.orange, Colors.deepOrange,
                Colors.brown, Colors.grey, Colors.blueGrey, Colors.black,
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Set Color'),
              onPressed: () {
                if (mounted) {
                  // <<< CHANGED: Dispatch to GlobalTagBloc >>>
                  context.read<GlobalTagBloc>().add(
                    UpdateGlobalTagColor(tag.name, currentColor.value),
                  );
                }
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  // Show context menu for a tag in the "Available Tags" list
  void _showTagContextMenu(BuildContext context, Tag tag) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Wrap(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.color_lens),
              title: const Text('Set Color'),
              onTap: () {
                Navigator.pop(ctx);
                if (mounted) {
                  _showColorPicker(context, tag);
                }
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.delete_forever, color: Colors.red[700]),
              title: Text(
                'Delete Tag Definition "${tag.name}"',
                style: TextStyle(color: Colors.red[700]),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _showDeleteConfirmationDialog(context, tag);
              },
            ),
          ],
        );
      },
    );
  }

  // Show confirmation dialog before deleting a global tag definition
  void _showDeleteConfirmationDialog(BuildContext context, Tag tag) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder:
          (confirmCtx) => AlertDialog(
            title: const Text('Confirm Delete Tag Definition'),
            content: Text(
              'Are you sure you want to delete the tag definition "${tag.name}"? This will remove it from the available tags list but will NOT remove it from tracks where it is already assigned.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(confirmCtx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(confirmCtx);
                  if (!mounted) return;
                  // <<< CHANGED: Dispatch to GlobalTagBloc >>>
                  context.read<GlobalTagBloc>().add(RemoveGlobalTag(tag.name));
                },
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );
  }

  // Build individual tag chip UI
  Widget _buildTagChip({
    required BuildContext context,
    required Tag tag,
    required bool isSelectedForTrack,
    required bool isInAvailableSection,
  }) {
    final Color tagColor = tag.color ?? Colors.grey.shade600;
    final Color textColor =
        ThemeData.estimateBrightnessForColor(tagColor) == Brightness.dark
            ? Colors.white
            : Colors.black;

    return GestureDetector(
      key: ValueKey(
        'tag_chip_${tag.name}_${isInAvailableSection ? 'avail' : 'assign'}',
      ),
      // --- Primary Tap Action: Toggle assignment for all tracks ---
      onTap: () {
        if (!mounted) return;
        if (isSelectedForTrack) {
          // Remove from all tracks
          for (final trackId in widget.trackIds) {
            context.read<TrackMetadataBloc>().add(
              RemoveTrackGeneralTag(trackId, tag.name),
            );
            setState(() {
              _pendingTrackTags[trackId]?.remove(tag.name);
            });
          }
        } else {
          // Add to all tracks
          for (final trackId in widget.trackIds) {
            context.read<TrackMetadataBloc>().add(
              AddTrackGeneralTag(trackId, tag.name),
            );
            setState(() {
              _pendingTrackTags[trackId]?.add(tag.name);
            });
          }
        }
        _updateTagSets(); // Update the tag sets after changes
        // Refocus search bar after interaction
        FocusScope.of(context).requestFocus(_searchFocusNode);
      },
      // --- Secondary Tap Action (Right-click): Show context menu ONLY for available tags ---
      onSecondaryTap:
          isInAvailableSection
              ? () {
                if (mounted) _showTagContextMenu(context, tag);
              }
              : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 5.0),
        decoration: BoxDecoration(
          color: tagColor.withOpacity(isSelectedForTrack ? 1.0 : 0.7),
          borderRadius: BorderRadius.circular(15.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelectedForTrack && isInAvailableSection)
              Icon(Icons.check_circle_outline, size: 14, color: textColor),
            if (isSelectedForTrack && isInAvailableSection)
              const SizedBox(width: 4),
            Text(tag.name, style: TextStyle(color: textColor, fontSize: 13)),
            if (!isInAvailableSection) const SizedBox(width: 4),
            if (!isInAvailableSection)
              Icon(Icons.cancel, size: 14, color: textColor.withOpacity(0.8)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: (event) => _handleKeyEvent(_searchFocusNode, event),
      child: BlocBuilder<GlobalTagBloc, GlobalTagState>(
        builder: (context, tagState) {
          if (tagState is! GlobalTagLoaded) {
            return Dialog(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Center(
                  child:
                      (tagState is GlobalTagError)
                          ? Text(
                            "Error loading tags: ${tagState.message}",
                            style: TextStyle(color: Colors.red),
                          )
                          : const CircularProgressIndicator(),
                ),
              ),
            );
          }

          final allGlobalTags = tagState.allTags;
          final availableTagsSorted = List<Tag>.from(allGlobalTags)..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );

          final filteredAvailableTags =
              _searchTerm.isEmpty
                  ? availableTagsSorted
                  : availableTagsSorted
                      .where(
                        (tag) => tag.name.toLowerCase().contains(_searchTerm),
                      )
                      .toList();

          // Get Tag objects for common and partial tags
          final commonTags =
              allGlobalTags
                  .where((tag) => _commonTags.contains(tag.name))
                  .toList();
          final partialTags =
              allGlobalTags
                  .where((tag) => _partialTags.contains(tag.name))
                  .toList();

          final textStyle =
              Theme.of(context).textTheme.bodyLarge ?? const TextStyle();
          final suggestionStyle = textStyle.copyWith(color: Colors.grey[500]);
          final suggestionPadding = EdgeInsets.only(
            left: _textFieldPadding.left + _prefixIconTotalWidth,
            top: _textFieldPadding.top,
            right: _textFieldPadding.right,
            bottom: _textFieldPadding.bottom,
          );

          return AlertDialog(
            title: Text(
              widget.trackIds.length > 1
                  ? 'Edit Multiple Tracks Tags'
                  : 'Edit Track Tags',
            ),
            content: SizedBox(
              width: 450,
              height: 550,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Search and Create Row (unchanged)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            TextField(
                              controller: _searchController,
                              focusNode: _searchFocusNode,
                              style: textStyle,
                              decoration: InputDecoration(
                                hintText: 'Search or create tag...',
                                prefixIcon: const Icon(Icons.search, size: 20),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Theme.of(context).primaryColor,
                                    width: 1.5,
                                  ),
                                ),
                                contentPadding: _textFieldPadding,
                              ),
                            ),
                            if (_suggestion != null &&
                                _searchFocusNode.hasFocus)
                              Padding(
                                padding: suggestionPadding,
                                child: IgnorePointer(
                                  child: RichText(
                                    text: TextSpan(
                                      style: textStyle,
                                      children: <TextSpan>[
                                        TextSpan(
                                          text: _searchController.text,
                                          style: const TextStyle(
                                            color: Colors.transparent,
                                          ),
                                        ),
                                        TextSpan(
                                          text: _suggestion!,
                                          style: suggestionStyle,
                                        ),
                                      ],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        tooltip: 'Add/Create Tag',
                        color: Theme.of(context).colorScheme.primary,
                        onPressed:
                            _searchController.text.trim().isNotEmpty
                                ? _createOrToggleTag
                                : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),

                  // Tags Assigned in All Tracks Section
                  if (widget.trackIds.length > 1) ...[
                    Text(
                      'Tags Assigned in All Tracks:',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(maxHeight: 100),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceVariant.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child:
                          commonTags.isEmpty
                              ? const Center(
                                child: Text(
                                  'None',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              )
                              : SingleChildScrollView(
                                child: Wrap(
                                  spacing: 6.0,
                                  runSpacing: 6.0,
                                  children:
                                      commonTags
                                          .map(
                                            (tag) => _buildTagChip(
                                              context: context,
                                              tag: tag,
                                              isSelectedForTrack: true,
                                              isInAvailableSection: false,
                                            ),
                                          )
                                          .toList(),
                                ),
                              ),
                    ),
                    const SizedBox(height: 15),

                    // Tags Assigned in Some Tracks Section
                    Text(
                      'Tags Assigned in Some Tracks:',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(maxHeight: 100),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceVariant.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child:
                          partialTags.isEmpty
                              ? const Center(
                                child: Text(
                                  'None',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              )
                              : SingleChildScrollView(
                                child: Wrap(
                                  spacing: 6.0,
                                  runSpacing: 6.0,
                                  children:
                                      partialTags
                                          .map(
                                            (tag) => _buildTagChip(
                                              context: context,
                                              tag: tag,
                                              isSelectedForTrack: true,
                                              isInAvailableSection: false,
                                            ),
                                          )
                                          .toList(),
                                ),
                              ),
                    ),
                  ] else ...[
                    // Single track view (unchanged)
                    Text(
                      'Assigned Tags:',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(maxHeight: 100),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceVariant.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child:
                          _pendingTrackTags[widget.trackIds.first]?.isEmpty ??
                                  true
                              ? const Center(
                                child: Text(
                                  'None',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              )
                              : SingleChildScrollView(
                                child: Wrap(
                                  spacing: 6.0,
                                  runSpacing: 6.0,
                                  children:
                                      allGlobalTags
                                          .where(
                                            (tag) =>
                                                _pendingTrackTags[widget
                                                        .trackIds
                                                        .first]
                                                    ?.contains(tag.name) ??
                                                false,
                                          )
                                          .map(
                                            (tag) => _buildTagChip(
                                              context: context,
                                              tag: tag,
                                              isSelectedForTrack: true,
                                              isInAvailableSection: false,
                                            ),
                                          )
                                          .toList(),
                                ),
                              ),
                    ),
                  ],

                  const Divider(height: 25, thickness: 1),

                  // Available Tags Section (unchanged)
                  Text(
                    'Available Tags:',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child:
                        filteredAvailableTags.isEmpty
                            ? Center(
                              child: Text(
                                _searchTerm.isEmpty
                                    ? 'No tags created yet.'
                                    : 'No matching tags found.',
                                style: const TextStyle(color: Colors.grey),
                              ),
                            )
                            : Scrollbar(
                              controller: _availableTagsScrollController,
                              thumbVisibility: true,
                              child: SingleChildScrollView(
                                controller: _availableTagsScrollController,
                                padding: const EdgeInsets.only(
                                  right: 8,
                                  bottom: 10,
                                ),
                                child: Wrap(
                                  spacing: 6.0,
                                  runSpacing: 6.0,
                                  children:
                                      filteredAvailableTags
                                          .map(
                                            (tag) => _buildTagChip(
                                              context: context,
                                              tag: tag,
                                              isSelectedForTrack:
                                                  widget.trackIds.length > 1
                                                      ? _commonTags.contains(
                                                        tag.name,
                                                      )
                                                      : _pendingTrackTags[widget
                                                                  .trackIds
                                                                  .first]
                                                              ?.contains(
                                                                tag.name,
                                                              ) ??
                                                          false,
                                              isInAvailableSection: true,
                                            ),
                                          )
                                          .toList(),
                                ),
                              ),
                            ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Done'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          );
        },
      ),
    );
  }
}
