import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:audio_looker/blocs/track_management/track_metadata_bloc.dart';
//           value: playlistService, // Provide PlaylistService
import 'package:audio_looker/services/collection_service.dart';

class TrackMetadataEditor extends StatefulWidget {
  final Track track;

  const TrackMetadataEditor({Key? key, required this.track}) : super(key: key);

  @override
  _TrackMetadataEditorState createState() => _TrackMetadataEditorState();
}

class _TrackMetadataEditorState extends State<TrackMetadataEditor> {
  late TextEditingController _commentController;
  late TextEditingController _tagController;

  @override
  void initState() {
    super.initState();
    _commentController = TextEditingController(text: widget.track.comment);
    _tagController = TextEditingController();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Track Metadata',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),

            // Rating Widget
            _buildRatingWidget(),

            const SizedBox(height: 16),

            // Comment Section
            Text('Comment:', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _commentController,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Add your comments about this track...',
              ),
              onChanged: (value) {
                // Update comment in real-time
                BlocProvider.of<TrackMetadataBloc>(
                  context,
                ).add(UpdateTrackComment(widget.track.id!, value));
              },
            ),

            const SizedBox(height: 16),

            // General Tags Section
            Text(
              'General Tags:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),

            // Display existing tags
            Wrap(
              spacing: 8.0,
              runSpacing: 4.0,
              children: [
                for (var tag in widget.track.generalTags)
                  Chip(
                    label: Text(tag),
                    deleteIcon: const Icon(Icons.close, size: 18),
                    onDeleted: () {
                      BlocProvider.of<TrackMetadataBloc>(
                        context,
                      ).add(RemoveTrackGeneralTag(widget.track.id!, tag));
                    },
                  ),
              ],
            ),

            const SizedBox(height: 8),

            // Add new tag
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tagController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Add a new tag...',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    if (_tagController.text.isNotEmpty) {
                      BlocProvider.of<TrackMetadataBloc>(context).add(
                        AddTrackGeneralTag(
                          widget.track.id!,
                          _tagController.text,
                        ),
                      );
                      _tagController.clear();
                    }
                  },
                  child: const Text('Add'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingWidget() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Rating:', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(5, (index) {
            return IconButton(
              icon: Icon(
                index < widget.track.rating ? Icons.star : Icons.star_border,
                color: index < widget.track.rating ? Colors.amber : Colors.grey,
                size: 32,
              ),
              onPressed: () {
                // Update rating (index + 1 because rating is 1-5)
                BlocProvider.of<TrackMetadataBloc>(
                  context,
                ).add(UpdateTrackRating(widget.track.id!, index + 1));
              },
            );
          }),
        ),
      ],
    );
  }
}
