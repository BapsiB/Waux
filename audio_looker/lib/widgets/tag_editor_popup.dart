// --- lib/widgets/tag_editor_popup.dart ---

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Required for RawKeyboardListener and LogicalKeyboardKey
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
  final FocusNode _searchFocusNode = FocusNode(); // FocusNode for the TextField
  final ScrollController _availableTagsScrollController = ScrollController();
  String _searchTerm = '';
  late Set<String> _selectedTags;

  // --- Autocomplete State ---
  String? _suggestion;
  String? _suggestedTag;
  // --- End Autocomplete State ---

  // --- Constants for Alignment ---
  // These values should match the TextField's decoration properties
  final EdgeInsets _textFieldPadding = const EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 12,
  );
  // Estimate or measure the space taken by the prefix icon + its internal padding
  final double _prefixIconTotalWidth = 33.0;
  // --- End Constants ---

  @override
  void initState() {
    super.initState();
    _selectedTags = Set<String>.from(widget.currentTrackTags);
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_searchFocusNode);
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _availableTagsScrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final currentText = _searchController.text;
    // Use mounted check before calling setState
    if (!mounted) return;
    setState(() {
      _searchTerm = currentText.toLowerCase();
      _suggestion = null;
      _suggestedTag = null;

      if (_searchTerm.isNotEmpty) {
        final collectionState = context.read<CollectionBloc>().state;
        if (collectionState is CollectionLoaded) {
          final potentialSuggestion = collectionState.allTags.firstWhere(
            (tag) =>
                tag.name.toLowerCase().startsWith(_searchTerm) &&
                tag.name.toLowerCase() != _searchTerm &&
                !_selectedTags.contains(tag.name),
            orElse: () => Tag(name: ''),
          );

          if (potentialSuggestion.name.isNotEmpty) {
            _suggestedTag = potentialSuggestion.name;
            _suggestion = potentialSuggestion.name.substring(
              currentText.length,
            );
          }
        }
      }
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    // Use mounted check
    if (!mounted) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.tab && _suggestedTag != null) {
        _acceptSuggestion();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.enter &&
          _searchController.text.trim().isNotEmpty) {
        _createOrAddTag();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _acceptSuggestion() {
    if (_suggestedTag != null) {
      // Use mounted check before calling setState
      if (!mounted) return;
      setState(() {
        _searchController.text = _suggestedTag!;
        _searchController.selection = TextSelection.fromPosition(
          TextPosition(offset: _searchController.text.length),
        );
        _suggestion = null;
        _suggestedTag = null;
        _searchTerm = _searchController.text.toLowerCase();
      });
    }
  }

  void _createOrAddTag() {
    final tagName = _searchController.text.trim();
    if (tagName.isEmpty) return;

    final collectionState = context.read<CollectionBloc>().state;
    if (collectionState is CollectionLoaded) {
      final existingTag = collectionState.allTags.any(
        (t) => t.name.toLowerCase() == tagName.toLowerCase(),
      );

      if (existingTag) {
        if (!_selectedTags.contains(tagName)) {
          context.read<CollectionBloc>().add(
            AddTrackGeneralTag(widget.trackId, tagName),
          );
          // Use mounted check before calling setState
          if (mounted) {
            setState(() {
              _selectedTags.add(tagName);
            });
          }
        }
      } else {
        context.read<CollectionBloc>().add(CreateGeneralTag(tagName));
        context.read<CollectionBloc>().add(
          AddTrackGeneralTag(widget.trackId, tagName),
        );
        // Use mounted check before calling setState
        if (mounted) {
          setState(() {
            _selectedTags.add(tagName);
          });
        }
      }
      _searchController.clear();
      // Use mounted check before calling setState
      if (mounted) {
        setState(() {
          _suggestion = null;
          _suggestedTag = null;
          _searchTerm = '';
        });
      }
    }
  }

  void _showColorPicker(BuildContext context, Tag tag) {
    Color currentColor = tag.color ?? Colors.grey;
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
                Colors.red,
                Colors.pink,
                Colors.purple,
                Colors.deepPurple,
                Colors.indigo,
                Colors.blue,
                Colors.lightBlue,
                Colors.cyan,
                Colors.teal,
                Colors.green,
                Colors.lightGreen,
                Colors.lime,
                Colors.yellow,
                Colors.amber,
                Colors.orange,
                Colors.deepOrange,
                Colors.brown,
                Colors.grey,
                Colors.blueGrey,
                Colors.black,
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
                // Use mounted check before accessing context
                if (mounted) {
                  context.read<CollectionBloc>().add(
                    SetGeneralTagColor(tag.name, currentColor.value),
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
                // Use mounted check before accessing context
                if (mounted) {
                  _showColorPicker(context, tag);
                }
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
                // Use mounted check before accessing context
                if (!mounted) return;
                showDialog(
                  context: context,
                  builder:
                      (confirmCtx) => AlertDialog(
                        title: const Text('Confirm Deletion'),
                        content: Text(
                          'Are you sure you want to delete the tag "${tag.name}" globally? This will remove it from all tracks and cannot be undone.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(confirmCtx),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(confirmCtx);
                              // Use mounted check before accessing context
                              if (mounted) {
                                context.read<CollectionBloc>().add(
                                  DeleteGeneralTag(tag.name),
                                );
                                setState(() {
                                  _selectedTags.remove(tag.name);
                                });
                              }
                            },
                            child: Text(
                              'Delete',
                              style: TextStyle(color: Colors.red),
                            ),
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

  Widget _buildTagChip({
    required BuildContext context,
    required Tag tag,
    required bool isSelected,
    required bool isAvailableSection,
  }) {
    final Color tagColor = tag.color ?? Colors.grey.shade600;
    final Color textColor =
        ThemeData.estimateBrightnessForColor(tagColor) == Brightness.dark
            ? Colors.white
            : Colors.black;
    final bool showAsSelected = _selectedTags.contains(tag.name);

    return InkWell(
      onTap: () {
        // Use mounted check before calling setState or accessing context
        if (!mounted) return;
        if (showAsSelected) {
          context.read<CollectionBloc>().add(
            RemoveTrackGeneralTag(widget.trackId, tag.name),
          );
          setState(() {
            _selectedTags.remove(tag.name);
          });
        } else {
          context.read<CollectionBloc>().add(
            AddTrackGeneralTag(widget.trackId, tag.name),
          );
          setState(() {
            _selectedTags.add(tag.name);
          });
        }
        FocusScope.of(context).requestFocus(_searchFocusNode);
      },
      onLongPress:
          isAvailableSection
              ? () {
                // Use mounted check before accessing context
                if (mounted) {
                  _showTagContextMenu(context, tag);
                }
              }
              : null,
      borderRadius: BorderRadius.circular(15.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 5.0),
        decoration: BoxDecoration(
          color: tagColor.withOpacity(showAsSelected ? 1.0 : 0.7),
          borderRadius: BorderRadius.circular(15.0),
          border:
              showAsSelected && isAvailableSection
                  ? Border.all(color: Colors.white, width: 1.5)
                  : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showAsSelected && isAvailableSection)
              Icon(Icons.check_circle_outline, size: 14, color: textColor),
            if (showAsSelected && isAvailableSection) const SizedBox(width: 4),
            Text(tag.name, style: TextStyle(color: textColor, fontSize: 13)),
            if (!isAvailableSection) const SizedBox(width: 4),
            if (!isAvailableSection)
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
      child: BlocBuilder<CollectionBloc, CollectionState>(
        builder: (context, state) {
          if (state is! CollectionLoaded) {
            return const Dialog(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: Center(child: CircularProgressIndicator()),
              ),
            );
          }

          final allTags = state.allTags;
          final filteredAvailableTags =
              allTags
                  .where((tag) => tag.name.toLowerCase().contains(_searchTerm))
                  .toList();
          final assignedTags =
              allTags.where((tag) => _selectedTags.contains(tag.name)).toList();

          final textStyle =
              Theme.of(context).textTheme.titleMedium ?? const TextStyle();
          final suggestionStyle = textStyle.copyWith(color: Colors.grey[400]);

          // Calculate the exact padding needed for the suggestion overlay
          final suggestionPadding = EdgeInsets.only(
            left:
                _textFieldPadding.left +
                _prefixIconTotalWidth, // Start after icon
            top: _textFieldPadding.top,
            right: _textFieldPadding.right,
            bottom: _textFieldPadding.bottom,
          );

          return AlertDialog(
            title: const Text('Edit Track Tags'),
            content: SizedBox(
              width: 400,
              height: 500,
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
                          alignment: Alignment.centerLeft,
                          children: [
                            // --- Actual TextField ---
                            TextField(
                              controller: _searchController,
                              focusNode: _searchFocusNode,
                              style: textStyle,
                              decoration: InputDecoration(
                                hintText: 'Search or create tag...',
                                prefixIcon: const Icon(Icons.search, size: 20),
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: Colors.white,
                                // Use the constant padding
                                contentPadding: _textFieldPadding,
                              ),
                            ),
                            // --- Suggestion Text Overlay ---
                            if (_suggestion != null &&
                                _searchFocusNode.hasFocus)
                              // *** Use Padding for alignment ***
                              Padding(
                                padding:
                                    suggestionPadding, // Apply calculated padding
                                child: IgnorePointer(
                                  child: RichText(
                                    text: TextSpan(
                                      style: textStyle, // Base style
                                      children: <TextSpan>[
                                        // Invisible part matching typed text
                                        TextSpan(
                                          text: _searchController.text,
                                          style: TextStyle(
                                            color: Colors.transparent,
                                          ), // Make it invisible
                                        ),
                                        // Visible suggestion part
                                        TextSpan(
                                          text: _suggestion!,
                                          style:
                                              suggestionStyle, // Suggestion style
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
                      // --- Add Button ---
                      IconButton(
                        icon: const Icon(Icons.add_circle),
                        tooltip: 'Add/Create Tag',
                        color: Theme.of(context).colorScheme.primary,
                        onPressed:
                            _searchController.text.trim().isNotEmpty
                                ? _createOrAddTag
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
                    constraints: const BoxConstraints(maxHeight: 100),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 6.0,
                        runSpacing: 6.0,
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
                                        isSelected: true,
                                        isAvailableSection: false,
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
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                            : Scrollbar(
                              controller: _availableTagsScrollController,
                              thumbVisibility: true,
                              child: SingleChildScrollView(
                                controller: _availableTagsScrollController,
                                child: Wrap(
                                  spacing: 6.0,
                                  runSpacing: 6.0,
                                  children:
                                      filteredAvailableTags
                                          .map(
                                            (tag) => _buildTagChip(
                                              context: context,
                                              tag: tag,
                                              isSelected: _selectedTags
                                                  .contains(tag.name),
                                              isAvailableSection: true,
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
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
