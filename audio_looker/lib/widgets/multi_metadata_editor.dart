// lib/widgets/multi_metadata_editor.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // <<< ADD THIS IMPORT
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:waux/blocs/track_management/track_metadata_bloc.dart';
import 'package:waux/blocs/track_management/global_tag_bloc.dart';
import 'package:waux/services/collection_service.dart';
import 'package:collection/collection.dart';
import 'package:waux/widgets/tag_editor_popup.dart';

const String _variesPlaceholder = "<Multiple Values>";
const String _leaveUnchangedPlaceholder =
    "<Leave Unchanged>"; // Not actively used yet, but good to have
const String _noValuePlaceholder = "<No Value Set>";

class MultiMetadataEditor extends StatefulWidget {
  final List<Track> selectedTracks;

  const MultiMetadataEditor({Key? key, required this.selectedTracks})
    : super(key: key);

  @override
  _MultiMetadataEditorState createState() => _MultiMetadataEditorState();
}

class _MultiMetadataEditorState extends State<MultiMetadataEditor> {
  late TrackMetadataBloc _trackMetadataBloc;
  late GlobalTagBloc _globalTagBloc;

  // Text Controllers
  final _titleController = TextEditingController();
  final _artistController = TextEditingController();
  final _albumController = TextEditingController();
  final _albumArtistController = TextEditingController();
  final _composerController = TextEditingController();
  final _genreController = TextEditingController();
  final _yearController = TextEditingController();
  final _bpmController = TextEditingController();
  final _commentController = TextEditingController();

  // Other state variables
  int? _rating;
  List<String> _tags = [];
  final Set<String> _modifiedFields = {};
  Map<String, dynamic> _initialFieldValues = {};

  // For managing the current displayed text in fields that might show placeholders
  Map<String, String> _displayTexts = {};

  @override
  void initState() {
    super.initState();
    _trackMetadataBloc = BlocProvider.of<TrackMetadataBloc>(context);
    _globalTagBloc = BlocProvider.of<GlobalTagBloc>(context);

    _initializeFields();
    _addListeners();
  }

  void _addListeners() {
    _titleController.addListener(
      () => _fieldChanged('title', _titleController.text),
    );
    _artistController.addListener(
      () => _fieldChanged('artist', _artistController.text),
    );
    _albumController.addListener(
      () => _fieldChanged('album', _albumController.text),
    );
    _albumArtistController.addListener(
      () => _fieldChanged('albumArtist', _albumArtistController.text),
    );
    _composerController.addListener(
      () => _fieldChanged('composer', _composerController.text),
    );
    _genreController.addListener(
      () => _fieldChanged('genre', _genreController.text),
    );
    _yearController.addListener(
      () => _fieldChanged('year', _yearController.text),
    );
    _bpmController.addListener(() => _fieldChanged('bpm', _bpmController.text));
    _commentController.addListener(
      () => _fieldChanged('comment', _commentController.text),
    );
  }

  void _fieldChanged(String fieldName, String currentValue) {
    if (mounted) {
      // A field is considered "modified" if its current display text
      // is different from its initial placeholder OR if its initial value
      // was not a placeholder and the current value is different.
      // Essentially, if the user interacts and changes it from what was initially displayed.
      bool valueActuallyChanged =
          true; // Assume changed unless proven otherwise

      if (_initialFieldValues[fieldName] == _variesPlaceholder ||
          _initialFieldValues[fieldName] == _noValuePlaceholder) {
        // If it started as a placeholder, any user input means it's modified.
        // No further check needed, it's definitely modified if the user typed.
      } else {
        // It started with a common value. Check if current text is different.
        if (fieldName == 'rating') {
          // Rating is not a text controller
          valueActuallyChanged = _rating != _initialFieldValues['rating'];
        } else if (fieldName == 'tags') {
          // Tags are not a text controller
          valueActuallyChanged =
              !const ListEquality().equals(
                _tags,
                _initialFieldValues['tags'] as List<String>? ?? [],
              );
        } else {
          valueActuallyChanged =
              currentValue !=
              (_initialFieldValues[fieldName]?.toString() ?? '');
        }
      }

      if (valueActuallyChanged) {
        if (!_modifiedFields.contains(fieldName)) {
          setState(() {
            _modifiedFields.add(fieldName);
          });
        }
      } else {
        // If the user reverted to the original common value, we might remove it from modified fields.
        // This depends on desired behavior. For now, once touched, it's considered for saving.
        // Or, more strictly:
        // if (_modifiedFields.contains(fieldName)) {
        //     setState(() {
        //         _modifiedFields.remove(fieldName);
        //     });
        // }
      }
    }
  }

  void _initializeFields() {
    if (widget.selectedTracks.isEmpty) return;
    final firstTrack = widget.selectedTracks.first;

    // Helper to determine common value or placeholder for String fields
    String setStringField(
      String Function(Track) getter,
      String fieldName,
      TextEditingController controller,
    ) {
      final firstValue = getter(firstTrack);
      bool allSame = widget.selectedTracks.every(
        (track) => getter(track) == firstValue,
      );
      String displayValue;
      if (allSame) {
        displayValue = firstValue;
        _initialFieldValues[fieldName] = firstValue;
      } else {
        displayValue = ''; // Empty for TextField, placeholder in hint
        _initialFieldValues[fieldName] = _variesPlaceholder;
      }
      controller.text = displayValue;
      _displayTexts[fieldName] = displayValue;
      return displayValue; // Not really needed to be returned here anymore
    }

    // Helper for nullable String fields
    String setNullableStringField(
      String? Function(Track) getter,
      String fieldName,
      TextEditingController controller,
    ) {
      final firstValue = getter(firstTrack);
      bool allSame = widget.selectedTracks.every(
        (track) => getter(track) == firstValue,
      );
      String displayValue;
      if (allSame) {
        displayValue = firstValue ?? '';
        _initialFieldValues[fieldName] = firstValue ?? '';
      } else {
        displayValue = '';
        _initialFieldValues[fieldName] = _variesPlaceholder;
      }
      controller.text = displayValue;
      _displayTexts[fieldName] = displayValue;
      return displayValue;
    }

    // Helper for Int fields
    String setIntField(
      int? Function(Track) getter,
      String fieldName,
      TextEditingController controller,
    ) {
      final firstValue = getter(firstTrack);
      bool allSame = widget.selectedTracks.every(
        (track) => getter(track) == firstValue,
      );
      String displayValue;
      if (allSame) {
        displayValue = firstValue?.toString() ?? '';
        _initialFieldValues[fieldName] = firstValue?.toString() ?? '';
      } else {
        displayValue = '';
        _initialFieldValues[fieldName] = _variesPlaceholder;
      }
      controller.text = displayValue;
      _displayTexts[fieldName] = displayValue;
      return displayValue;
    }

    setStringField((t) => t.title, 'title', _titleController);
    setStringField((t) => t.artist, 'artist', _artistController);
    setStringField((t) => t.album, 'album', _albumController);
    setNullableStringField(
      (t) => t.albumArtist,
      'albumArtist',
      _albumArtistController,
    );
    setNullableStringField((t) => t.composer, 'composer', _composerController);
    setNullableStringField((t) => t.genre, 'genre', _genreController);
    setIntField((t) => t.year, 'year', _yearController);
    setIntField((t) => t.bpm, 'bpm', _bpmController);
    setStringField((t) => t.comment, 'comment', _commentController);

    // Rating
    final firstRating = firstTrack.rating;
    bool allRatingsSame = widget.selectedTracks.every(
      (track) => track.rating == firstRating,
    );
    _rating = allRatingsSame ? firstRating : null;
    _initialFieldValues['rating'] =
        allRatingsSame ? firstRating : null; // Store null if varies

    // Tags
    List<String> getCommonTags() {
      if (widget.selectedTracks.isEmpty) return [];
      List<String> common = List.from(widget.selectedTracks.first.generalTags);
      for (int i = 1; i < widget.selectedTracks.length; i++) {
        common.retainWhere(
          (tag) => widget.selectedTracks[i].generalTags.contains(tag),
        );
      }
      return common;
    }

    bool allTagsIdentical() {
      if (widget.selectedTracks.isEmpty) return true;
      final firstTags = widget.selectedTracks.first.generalTags;
      for (int i = 1; i < widget.selectedTracks.length; i++) {
        if (!const ListEquality().equals(
          widget.selectedTracks[i].generalTags,
          firstTags,
        )) {
          return false;
        }
      }
      return true;
    }

    if (allTagsIdentical()) {
      _tags = List.from(firstTrack.generalTags);
      _initialFieldValues['tags'] = List<String>.from(firstTrack.generalTags);
    } else {
      _tags = []; // Start with empty if they vary, user must input new set
      _initialFieldValues['tags'] = _variesPlaceholder;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    _albumArtistController.dispose();
    _composerController.dispose();
    _genreController.dispose();
    _yearController.dispose();
    _bpmController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  void _saveChanges() {
    if (widget.selectedTracks.isEmpty) return;

    for (final track in widget.selectedTracks) {
      if (track.id == null) continue;

      if (_modifiedFields.contains('title')) {
        _trackMetadataBloc.add(
          UpdateTrackTitle(track.id!, _titleController.text.trim()),
        );
      }
      if (_modifiedFields.contains('artist')) {
        _trackMetadataBloc.add(
          UpdateTrackArtist(track.id!, _artistController.text.trim()),
        );
      }
      if (_modifiedFields.contains('album')) {
        _trackMetadataBloc.add(
          UpdateTrackAlbum(track.id!, _albumController.text.trim()),
        );
      }
      if (_modifiedFields.contains('albumArtist')) {
        final value = _albumArtistController.text.trim();
        _trackMetadataBloc.add(
          UpdateTrackAlbumArtist(track.id!, value.isEmpty ? null : value),
        );
      }
      if (_modifiedFields.contains('composer')) {
        final value = _composerController.text.trim();
        _trackMetadataBloc.add(
          UpdateTrackComposer(track.id!, value.isEmpty ? null : value),
        );
      }
      if (_modifiedFields.contains('genre')) {
        final value = _genreController.text.trim();
        _trackMetadataBloc.add(
          UpdateTrackGenre(track.id!, value.isEmpty ? null : value),
        );
      }
      if (_modifiedFields.contains('year')) {
        final yearText = _yearController.text.trim();
        _trackMetadataBloc.add(
          UpdateTrackYear(
            track.id!,
            yearText.isEmpty ? null : int.tryParse(yearText),
          ),
        );
      }
      if (_modifiedFields.contains('bpm')) {
        final bpmText = _bpmController.text.trim();
        _trackMetadataBloc.add(
          UpdateTrackBpm(
            track.id!,
            bpmText.isEmpty ? null : int.tryParse(bpmText),
          ),
        );
      }
      if (_modifiedFields.contains('comment')) {
        _trackMetadataBloc.add(
          UpdateTrackComment(track.id!, _commentController.text.trim()),
        );
      }
      if (_modifiedFields.contains('rating')) {
        // Check if rating was modified
        _trackMetadataBloc.add(
          UpdateTrackRating(track.id!, _rating ?? 0),
        ); // Use 0 if _rating is null (user cleared it)
      }
      if (_modifiedFields.contains('tags')) {
        // Remove all old tags for this track
        for (final oldTag in track.generalTags) {
          _trackMetadataBloc.add(RemoveTrackGeneralTag(track.id!, oldTag));
        }
        // Add all new tags from the _tags list
        for (final newTag in _tags) {
          if (newTag.trim().isNotEmpty) {
            _trackMetadataBloc.add(
              AddTrackGeneralTag(track.id!, newTag.trim()),
            );
          }
        }
      }
    }
    Navigator.of(context).pop();
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    String fieldName, {
    bool isNumeric = false,
    int? maxLength,
  }) {
    String? hintText;
    if (_initialFieldValues[fieldName] == _variesPlaceholder) {
      hintText = _variesPlaceholder;
    } else if (_initialFieldValues[fieldName] == '' && controller.text == '') {
      // This condition might need refinement if _noValuePlaceholder was used for empty strings
      // For now, if initial was empty and controller is empty, it's "No Value Set" effectively
      hintText = '(No value set)';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller, // Directly use the main controller
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText, // Show placeholder if values varied or were empty
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
        inputFormatters:
            isNumeric
                ? [
                  FilteringTextInputFormatter.digitsOnly,
                  if (maxLength != null)
                    LengthLimitingTextInputFormatter(maxLength),
                ]
                : [],
        onChanged:
            (value) => _fieldChanged(
              fieldName,
              value,
            ), // Keep this to mark as modified
      ),
    );
  }

  Widget _buildRatingField() {
    bool ratingVaries =
        _initialFieldValues['rating'] == null &&
        widget.selectedTracks.length > 1;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Rating: ', style: Theme.of(context).textTheme.titleMedium),
              if (ratingVaries)
                Text(
                  _variesPlaceholder,
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).hintColor,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: List.generate(5, (index) {
              final starValue = index + 1;
              return IconButton(
                icon: Icon(
                  (_rating ?? 0) >= starValue ? Icons.star : Icons.star_border,
                  color:
                      (_rating ?? 0) >= starValue ? Colors.amber : Colors.grey,
                ),
                onPressed: () {
                  setState(() {
                    _rating = (_rating == starValue) ? 0 : starValue;
                    _fieldChanged(
                      'rating',
                      _rating.toString(),
                    ); // Pass a string representation for consistency
                  });
                },
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildTagsField() {
    bool tagsVary = _initialFieldValues['tags'] == _variesPlaceholder;
    List<String> displayTags = [];

    if (!tagsVary && _initialFieldValues['tags'] is List<String>) {
      displayTags = _initialFieldValues['tags'];
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Tags: ', style: Theme.of(context).textTheme.titleMedium),
              if (tagsVary)
                Text(
                  _variesPlaceholder,
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).hintColor,
                  ),
                ),
              if (widget.selectedTracks.length > 1) ...[
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.edit),
                  iconSize: 18,
                  tooltip: 'Edit Tags',
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (dialogContext) {
                        return MultiBlocProvider(
                          providers: [
                            BlocProvider.value(
                              value: BlocProvider.of<TrackMetadataBloc>(
                                context,
                              ),
                            ),
                            BlocProvider.value(
                              value: BlocProvider.of<GlobalTagBloc>(context),
                            ),
                          ],
                          child: TagEditorPopup(
                            trackIds:
                                widget.selectedTracks
                                    .map((t) => t.id!)
                                    .toList(),
                            trackTags: Map.fromEntries(
                              widget.selectedTracks.map(
                                (t) => MapEntry(t.id!, t.generalTags),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (!tagsVary && displayTags.isNotEmpty)
            Text(
              'Current common tags: ${displayTags.join(", ")}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).hintColor,
              ),
            ),
          if (widget.selectedTracks.length == 1) ...[
            const SizedBox(height: 8),
            TextFormField(
              initialValue: _tags.join(', '),
              decoration: InputDecoration(
                labelText: 'Set New Tags (comma-separated)',
                hintText: 'e.g., energetic, vocal, instrumental',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) {
                setState(() {
                  _tags =
                      value
                          .split(',')
                          .map((t) => t.trim())
                          .where((t) => t.isNotEmpty)
                          .toList();
                  _fieldChanged('tags', value);
                });
              },
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.selectedTracks.isEmpty) {
      return const AlertDialog(
        title: Text('Error'),
        content: Text('No tracks selected for editing.'),
        actions: [CloseButton()],
      );
    }

    return AlertDialog(
      title: Text(
        'Edit Metadata (${widget.selectedTracks.length} track${widget.selectedTracks.length > 1 ? 's' : ''})',
      ),
      content: SizedBox(
        width: 450,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _buildTextField(_titleController, 'Title', 'title'),
              _buildTextField(_artistController, 'Artist', 'artist'),
              _buildTextField(_albumController, 'Album', 'album'),
              _buildRatingField(),
              _buildTextField(
                _albumArtistController,
                'Album Artist',
                'albumArtist',
              ),
              _buildTextField(_composerController, 'Composer', 'composer'),
              _buildTextField(_genreController, 'Genre', 'genre'),
              _buildTextField(
                _yearController,
                'Year (YYYY)',
                'year',
                isNumeric: true,
                maxLength: 4,
              ),
              _buildTextField(
                _bpmController,
                'BPM',
                'bpm',
                isNumeric: true,
                maxLength: 3,
              ),
              _buildTagsField(),
              _buildTextField(_commentController, 'Comment', 'comment'),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        ElevatedButton(
          // Only enable save if there are actual modifications
          onPressed: _modifiedFields.isNotEmpty ? _saveChanges : null,
          child: const Text('Save Changes'),
        ),
      ],
    );
  }
}
