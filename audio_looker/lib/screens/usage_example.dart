// import 'package:flutter/material.dart';
// import 'package:flutter_bloc/flutter_bloc.dart';
// import 'package:audio_looker/blocs/audio_player/audio_player_bloc.dart';
// import 'package:audio_looker/blocs/collection/collection_bloc.dart';
// import 'package:audio_looker/services/collection_service.dart';

// class TrackDetailScreen extends StatelessWidget {
//   final Track track;

//   const TrackDetailScreen({Key? key, required this.track}) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
//       ),
//       body: AudioPlayerWidget(
//         title: track.title,
//         artist: track.artist,
//         audioSource: track.path,
//         isUrl: track.isUrl,
//         rating: track.rating,
//         notes: track.comment,
//         generalTags: track.generalTags,
//         onRatingChanged: (rating) {
//           context.read<CollectionBloc>().add(
//             UpdateTrackRating(track.id!, rating),
//           );
//         },
//         onNotesChanged: (notes) {
//           context.read<CollectionBloc>().add(
//             UpdateTrackComment(track.id!, notes),
//           );
//         },
//         onAddGeneralTag: (tag) {
//           context.read<CollectionBloc>().add(
//             AddTrackGeneralTag(track.id!, tag),
//           );
//         },
//         onRemoveGeneralTag: (tag) {
//           context.read<CollectionBloc>().add(
//             RemoveTrackGeneralTag(track.id!, tag),
//           );
//         },
//       ),
//     );
//   }
// }
