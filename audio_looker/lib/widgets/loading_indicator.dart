import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:audio_looker/blocs/collection/collection_bloc.dart';

class LoadingIndicator extends StatelessWidget {
  final Widget child;

  const LoadingIndicator({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CollectionBloc, CollectionState>(
      builder: (context, state) {
        if (state is CollectionLoading) {
          return Stack(
            children: [
              // Show existing content if available
              if (state.currentTracks != null)
                Opacity(opacity: 0.5, child: child),

              // Loading overlay
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'Processing audio data...',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        return child;
      },
    );
  }
}
