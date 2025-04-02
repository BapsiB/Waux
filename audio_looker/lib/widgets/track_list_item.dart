import 'package:flutter/material.dart';
import 'package:audio_looker/services/collection_service.dart';
import 'package:audio_looker/widgets/waveform_painter.dart';

class TrackListItem extends StatelessWidget {
  final Track track;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const TrackListItem({
    Key? key,
    required this.track,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 8,
      ),
      color: isSelected
          ? Theme.of(context).primaryColor.withOpacity(0.2)
          : null,
      child: Column(
        children: [
          ListTile(
            leading: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.music_note),
                if (track.rating > 0)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.star,
                        size: 12,
                        color: Colors.amber,
                      ),
                      Text(
                        '${track.rating}',
                        style: TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
              ],
            ),
            title: Text(track.title),
            subtitle: Text(
              '${track.artist} • ${track.album}',
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete),
              onPressed: onDelete,
            ),
            onTap: onTap,
          ),
          
          // Waveform preview
          if (track.waveformData != null && track.waveformData!.isNotEmpty)
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: CustomPaint(
                size: Size.infinite,
                painter: WaveformPainter(
                  waveformData: track.waveformData!,
                  activeColor: Theme.of(context).primaryColor.withOpacity(0.6),
                  inactiveColor: Colors.grey[400]!,
                  playbackProgress: 0, // No playback in the list view
                ),
              ),
            ),
          
          // Tags preview
          if (track.generalTags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              child: SizedBox(
                height: 22,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: track.generalTags.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 4),
                  itemBuilder: (context, index) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        track.generalTags[index],
                        style: TextStyle(fontSize: 10),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}