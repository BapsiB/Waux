// --- lib/widgets/tag_editor_popup.dart ---

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../blocs/collection/collection_bloc.dart';
import '../services/collection_service.dart'; // Make sure Tag model is accessible

class TagEditorPopup extends StatefulWidget {
  final int trackId;
  final List<String> currentTrackTags; // Pass the track's current tags

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
  String _searchTerm = '';
  // Use a Set for efficient lookup of selected tags
  late Set<String> _selectedTags;

  @override
  void initState() {
    super.initState();
    _selectedTags = Set<String>.from(widget.currentTrackTags);
    _searchController.addListener(() {
      setState(() {
        _searchTerm = _searchController.text.toLowerCase();
      });
    });
    // Optional: Dispatch LoadAllTags if not reliably loaded elsewhere
    // Future.microtask(() => context.read<CollectionBloc>().add(LoadAllTags()));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // --- Context Menu and Color Picker Logic (Keep from previous version) ---
  void _showColorPicker(BuildContext context, Tag tag) {
    Color currentColor = tag.color ?? Colors.grey; // Default color
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Select Color for "${tag.name}"'),
          content: SingleChildScrollView(
            child: BlockPicker(
              pickerColor: currentColor,
              onColorChanged: (color) {
                currentColor = color;
              },
              availableColors: [
                // Provide your 16 colors
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
                context.read<CollectionBloc>().add(
                  SetGeneralTagColor(tag.name, currentColor.value),
                );
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

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
                _showColorPicker(context, tag);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete, color: Colors.red[700]),
              title: Text(
                'Delete "${tag.name}" Globally',
                style: TextStyle(color: Colors.red[700]),
              ),
              onTap: () {
                Navigator.pop(ctx);
                showDialog(
                  context: context,
                  builder:
                      (confirmCtx) => AlertDialog(
                        title: const Text('Confirm Deletion'),
                        content: Text(
                          'Are you sure you want to delete the tag "${tag.name}" globally? This cannot be undone.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(confirmCtx),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(confirmCtx);
                              context.read<CollectionBloc>().add(
                                DeleteGeneralTag(tag.name),
                              );
                            },
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                );
              },
            ),
          ],
        );
      },
    );
  }
  // --- End Context Menu ---

  // --- Helper to build individual tag chips ---
  Widget _buildTagChip({
    required BuildContext context,
    required Tag tag,
    required bool isSelected, // Is the tag currently assigned to *this* track?
    required bool
    isAvailableSection, // Is this chip in the "Available" section?
  }) {
    final Color tagColor = tag.color ?? Colors.grey.shade600; // Default color
    // Determine text color based on background brightness
    final Color textColor =
        ThemeData.estimateBrightnessForColor(tagColor) == Brightness.dark
            ? Colors.white
            : Colors.black;
    final bool showAsSelected = _selectedTags.contains(tag.name);

    return InkWell(
      // Use InkWell for tap feedback if needed
      onTap: () {
        if (showAsSelected) {
          // Remove tag
          context.read<CollectionBloc>().add(
            RemoveTrackGeneralTag(widget.trackId, tag.name),
          );
          setState(() {
            _selectedTags.remove(tag.name);
          });
        } else {
          // Add tag
          context.read<CollectionBloc>().add(
            AddTrackGeneralTag(widget.trackId, tag.name),
          );
          setState(() {
            _selectedTags.add(tag.name);
          });
        }
      },
      onLongPress:
          isAvailableSection
              ? () => _showTagContextMenu(context, tag)
              : null, // Only allow context menu in available list
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 5.0),
        decoration: BoxDecoration(
          color: tagColor,
          borderRadius: BorderRadius.circular(15.0),
          border:
              showAsSelected &&
                      isAvailableSection // Add border if selected in available list
                  ? Border.all(color: Colors.white, width: 1.5)
                  : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showAsSelected &&
                isAvailableSection) // Show check only if selected in available list
              Icon(Icons.check_circle_outline, size: 14, color: textColor),
            if (showAsSelected && isAvailableSection) const SizedBox(width: 4),
            Text(tag.name, style: TextStyle(color: textColor, fontSize: 13)),
            if (!isAvailableSection) // Show delete icon only in assigned list
              const SizedBox(width: 4),
            if (!isAvailableSection)
              Icon(Icons.cancel, size: 14, color: textColor.withOpacity(0.8)),
          ],
        ),
      ),
    );
  }
  // --- End Helper ---

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CollectionBloc, CollectionState>(
      builder: (context, state) {
        if (state is! CollectionLoaded) {
          return const Dialog(
            child: Padding(
              padding: EdgeInsets.all(20.0),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        // --- Filter available tags based on search term ---
        final allTags = state.allTags;
        final filteredAvailableTags =
            allTags
                .where((tag) => tag.name.toLowerCase().contains(_searchTerm))
                .toList();
        // --- Get assigned tags based on the local state ---
        final assignedTags =
            allTags.where((tag) => _selectedTags.contains(tag.name)).toList();

        return AlertDialog(
          title: const Text('Edit Track Tags'),
          // Make content scrollable if it overflows
          content: SizedBox(
            width: double.maxFinite, // Make dialog use available width
            // Consider setting a max height if needed: height: MediaQuery.of(context).size.height * 0.6,
            child: Column(
              mainAxisSize: MainAxisSize.min, // Take minimum vertical space
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- Search and Create Row ---
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search or create tag...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle),
                      tooltip: 'Create Tag',
                      color: Theme.of(context).colorScheme.primary,
                      onPressed:
                          (_searchController.text.trim().isNotEmpty &&
                                  !allTags.any(
                                    (t) =>
                                        t.name.toLowerCase() ==
                                        _searchController.text
                                            .trim()
                                            .toLowerCase(),
                                  ))
                              ? () {
                                context.read<CollectionBloc>().add(
                                  CreateGeneralTag(
                                    _searchController.text.trim(),
                                  ),
                                );
                                _searchController
                                    .clear(); // Clear after creation
                              }
                              : null, // Disable if empty or tag exists
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
                  constraints: const BoxConstraints(
                    maxHeight: 100,
                  ), // Limit height
                  child: SingleChildScrollView(
                    // Make assigned tags scrollable if they overflow
                    child: Wrap(
                      spacing: 6.0, // Gap between chips
                      runSpacing: 6.0, // Gap between lines
                      children:
                          assignedTags.isEmpty
                              ? [
                                const Text(
                                  'None',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ]
                              : assignedTags
                                  .map(
                                    (tag) => _buildTagChip(
                                      context: context,
                                      tag: tag,
                                      isSelected:
                                          true, // Always selected in this section
                                      isAvailableSection:
                                          false, // This is the "assigned" section
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
                  // Allow this section to take remaining space
                  child:
                      filteredAvailableTags.isEmpty
                          ? Center(
                            child: Text(
                              _searchTerm.isEmpty
                                  ? 'No tags created yet.'
                                  : 'No matching tags found.',
                            ),
                          )
                          : SingleChildScrollView(
                            // Ensure scrolling if many tags
                            child: Wrap(
                              spacing: 6.0,
                              runSpacing: 6.0,
                              children:
                                  filteredAvailableTags
                                      .map(
                                        (tag) => _buildTagChip(
                                          context: context,
                                          tag: tag,
                                          isSelected: _selectedTags.contains(
                                            tag.name,
                                          ), // Check if selected
                                          isAvailableSection:
                                              true, // This is the "available" section
                                        ),
                                      )
                                      .toList(),
                            ),
                          ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Close'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
}
