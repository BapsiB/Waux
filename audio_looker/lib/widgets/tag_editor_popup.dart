// lib/widgets/tag_editor_popup.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Required for RawKeyboardListener and LogicalKeyboardKey
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

// Import BLoCs
// import '../blocs/track_management/track_management_bloc.dart'; // <<< REMOVED
import '../blocs/track_management/track_metadata_bloc.dart'; // <<< ADDED
import '../blocs/track_management/global_tag_bloc.dart'; // <<< ADDED

// Import Models
import '../services/collection_service.dart'; // Make sure Tag model is accessible

class TagEditorPopup extends StatefulWidget {
  final int trackId;
  final List<String> currentTrackTags; // Pass the track's current assigned tags

  const TagEditorPopup({
    Key? key,
    required this.trackId,
    required this.currentTrackTags,
  }) : super(key: key);

  @override
  _TagEditorPopupState createState() => _TagEditorPopupState();
}

class _TagEditorPopupState extends State<TagEditorPopup> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _availableTagsScrollController = ScrollController();
  String _searchTerm = '';
  late Set<String>
  _selectedTags; // Holds the tags currently ASSIGNED to this track

  // Autocomplete State
  String? _suggestion;
  String? _suggestedTag; // The full name of the suggested tag

  // Constants for Alignment
  final EdgeInsets _textFieldPadding = const EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 12,
  );
  final double _prefixIconTotalWidth =
      33.0; // Approx width of search icon + padding

  @override
  void initState() {
    super.initState();
    // Initialize the set of selected tags based on the track's current tags
    _selectedTags = Set<String>.from(widget.currentTrackTags);
    _searchController.addListener(_onSearchChanged);
    // Request focus after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusScope.of(context).requestFocus(_searchFocusNode);
      }
    });
    // Load global tags if not already loaded (optional, main.dart might handle initial load)
    // context.read<GlobalTagBloc>().add(LoadGlobalTags());
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
                !_selectedTags.contains(
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

  // Create a new global tag OR add/remove an existing tag for the current track
  void _createOrToggleTag() {
    final tagName = _searchController.text.trim();
    if (tagName.isEmpty) return;

    // <<< CHANGED: Read from GlobalTagBloc >>>
    final tagState = context.read<GlobalTagBloc>().state;
    if (tagState is GlobalTagLoaded) {
      final allGlobalTags = tagState.allTags;
      final existingGlobalTag = allGlobalTags.firstWhere(
        (t) => t.name.toLowerCase() == tagName.toLowerCase(),
        orElse: () => Tag(name: ''), // Dummy tag if not found
      );

      if (existingGlobalTag.name.isNotEmpty) {
        // Tag definition exists globally, toggle assignment for this track
        final exactTagName = existingGlobalTag.name; // Use the correct casing
        if (_selectedTags.contains(exactTagName)) {
          // Tag is currently assigned -> Remove it
          // <<< CHANGED: Dispatch to TrackMetadataBloc >>>
          context.read<TrackMetadataBloc>().add(
            RemoveTrackGeneralTag(widget.trackId, exactTagName),
          );
          if (mounted) {
            setState(() {
              _selectedTags.remove(exactTagName);
            });
          }
        } else {
          // Tag is not assigned -> Add it
          // <<< CHANGED: Dispatch to TrackMetadataBloc >>>
          context.read<TrackMetadataBloc>().add(
            AddTrackGeneralTag(widget.trackId, exactTagName),
          );
          if (mounted) {
            setState(() {
              _selectedTags.add(exactTagName);
            });
          }
        }
      } else {
        // Tag definition does NOT exist globally -> Create it AND assign it
        final newTag = Tag(name: tagName); // Create with user's casing
        // <<< CHANGED: Dispatch to GlobalTagBloc >>>
        context.read<GlobalTagBloc>().add(AddGlobalTag(newTag));
        // <<< CHANGED: Dispatch to TrackMetadataBloc >>>
        context.read<TrackMetadataBloc>().add(
          AddTrackGeneralTag(widget.trackId, tagName),
        );
        if (mounted) {
          setState(() {
            _selectedTags.add(tagName);
          });
        }
      }

      // Clear search input after action
      _searchController.clear();
      if (mounted) {
        setState(() {
          _suggestion = null;
          _suggestedTag = null;
          _searchTerm = '';
        });
        // Refocus after action
        FocusScope.of(context).requestFocus(_searchFocusNode);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Global tags not loaded yet.')),
      );
    }
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
    required bool
    isSelectedForTrack, // Is this tag currently assigned to the track?
    required bool
    isInAvailableSection, // Is this chip in the bottom "Available" list?
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
      // --- Primary Tap Action: Toggle assignment for the current track ---
      onTap: () {
        if (!mounted) return;
        if (isSelectedForTrack) {
          // Remove from track
          // <<< CHANGED: Dispatch to TrackMetadataBloc >>>
          context.read<TrackMetadataBloc>().add(
            RemoveTrackGeneralTag(widget.trackId, tag.name),
          );
          setState(() {
            _selectedTags.remove(tag.name);
          });
        } else {
          // Add to track
          // <<< CHANGED: Dispatch to TrackMetadataBloc >>>
          context.read<TrackMetadataBloc>().add(
            AddTrackGeneralTag(widget.trackId, tag.name),
          );
          setState(() {
            _selectedTags.add(tag.name);
          });
        }
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
          // Use full opacity if assigned, slightly transparent if only available
          color: tagColor.withOpacity(isSelectedForTrack ? 1.0 : 0.7),
          borderRadius: BorderRadius.circular(15.0),
          // Optional: Add border for visual distinction, e.g., when selected in available list
          // border: isSelectedForTrack && isInAvailableSection
          //     ? Border.all(color: Theme.of(context).colorScheme.outline, width: 1.5)
          //     : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Show checkmark if selected in the "Available" section
            if (isSelectedForTrack && isInAvailableSection)
              Icon(Icons.check_circle_outline, size: 14, color: textColor),
            if (isSelectedForTrack && isInAvailableSection)
              const SizedBox(width: 4),

            // Tag Name
            Text(tag.name, style: TextStyle(color: textColor, fontSize: 13)),

            // Show remove icon only for chips in the "Assigned" section
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
    // Use KeyboardListener for Tab/Enter keys
    return KeyboardListener(
      focusNode: FocusNode(), // Use a local FocusNode for the listener itself
      onKeyEvent: (event) => _handleKeyEvent(_searchFocusNode, event),
      // <<< CHANGED: Build based on GlobalTagBloc state >>>
      child: BlocBuilder<GlobalTagBloc, GlobalTagState>(
        builder: (context, tagState) {
          // Handle loading or error states for the global tag list
          if (tagState is! GlobalTagLoaded) {
            return Dialog(
              // Use Dialog for consistent sizing
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Center(
                  child:
                      (tagState is GlobalTagError)
                          ? Text(
                            "Error loading tags: ${tagState.message}",
                            style: TextStyle(color: Colors.red),
                          )
                          : const CircularProgressIndicator(), // Show loading indicator
                ),
              ),
            );
          }

          // --- Data Extraction (when GlobalTagLoaded) ---
          final allGlobalTags = tagState.allTags;
          // Sort available tags alphabetically for consistent display
          final availableTagsSorted = List<Tag>.from(allGlobalTags)..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );

          // Filter available tags based on search term
          final filteredAvailableTags =
              _searchTerm.isEmpty
                  ? availableTagsSorted // Show all if search is empty
                  : availableTagsSorted
                      .where(
                        (tag) => tag.name.toLowerCase().contains(_searchTerm),
                      )
                      .toList();

          // Get assigned tags based on current _selectedTags set, preserving order if needed
          // We need the Tag objects (with color) for the assigned tags list
          final assignedTags =
              allGlobalTags // Filter from the global list
                  .where((tag) => _selectedTags.contains(tag.name))
                  .toList();
          // Optional: Sort assigned tags if needed
          // assignedTags.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

          // --- UI Styles ---
          final textStyle =
              Theme.of(context).textTheme.bodyLarge ?? const TextStyle();
          final suggestionStyle = textStyle.copyWith(color: Colors.grey[500]);
          final suggestionPadding = EdgeInsets.only(
            left: _textFieldPadding.left + _prefixIconTotalWidth,
            top: _textFieldPadding.top,
            right: _textFieldPadding.right,
            bottom: _textFieldPadding.bottom,
          );

          // --- Build Dialog ---
          return AlertDialog(
            title: const Text('Edit Track Tags'),
            content: SizedBox(
              // Constrain dialog size
              width: 450,
              height: 550,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- Search and Create Row ---
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Stack(
                          // Stack for suggestion overlay
                          alignment: Alignment.centerLeft,
                          children: [
                            // Actual TextField
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
                            // Suggestion Text Overlay
                            if (_suggestion != null &&
                                _searchFocusNode.hasFocus)
                              Padding(
                                padding: suggestionPadding,
                                child: IgnorePointer(
                                  // Make overlay non-interactive
                                  child: RichText(
                                    text: TextSpan(
                                      style: textStyle, // Base style
                                      children: <TextSpan>[
                                        TextSpan(
                                          text: _searchController.text,
                                          style: const TextStyle(
                                            color: Colors.transparent,
                                          ),
                                        ), // Invisible part matching input
                                        TextSpan(
                                          text: _suggestion!,
                                          style: suggestionStyle,
                                        ), // Visible suggestion
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
                      // Add/Create Button
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

                  // --- Assigned Tags Section ---
                  Text(
                    'Assigned Tags:',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(
                      maxHeight: 100,
                    ), // Limit height
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceVariant
                          .withOpacity(0.3), // Subtle background
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child:
                        assignedTags.isEmpty
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
                                    assignedTags
                                        .map(
                                          (tag) => _buildTagChip(
                                            context: context,
                                            tag: tag,
                                            isSelectedForTrack:
                                                true, // Always true here
                                            isInAvailableSection: false,
                                          ),
                                        )
                                        .toList(),
                              ),
                            ),
                  ),

                  const Divider(height: 25, thickness: 1),

                  // --- Available Tags Section ---
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
                              // Add Scrollbar
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
                                              // Check if this available tag is also in the track's assigned set
                                              isSelectedForTrack: _selectedTags
                                                  .contains(tag.name),
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
                child: const Text('Close'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          );
        },
      ),
    );
  }
}
