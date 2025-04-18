// lib/widgets/waveform_progress_bar.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

// Import the BLoC and State
import '../blocs/waveform_processing/waveform_processing_bloc.dart';
import '../blocs/waveform_processing/waveform_processing_state.dart';

class WaveformProgressBar extends StatelessWidget {
  const WaveformProgressBar({super.key});

  @override
  Widget build(BuildContext context) {
    // Use BlocBuilder to react to state changes from WaveformProcessingBloc
    return BlocBuilder<WaveformProcessingBloc, WaveformProcessingState>(
      builder: (context, state) {
        // Only show the progress bar when processing is in progress
        if (state is WaveformProcessingInProgress) {
          // Calculate percentage for display
          final percentage = (state.progress * 100).toStringAsFixed(0);

          return Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            color: Colors.blueGrey[700], // Example background color
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Processing waveforms... (${state.processedTracks}/${state.totalTracks})',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: state.progress, // Value between 0.0 and 1.0
                        backgroundColor: Colors.blueGrey[500],
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.lightBlueAccent,
                        ),
                        minHeight: 6, // Make it a bit thicker
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '$percentage%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          );
        } else if (state is WaveformProcessingComplete) {
          // Optionally show a temporary completion message
          // return Container(
          //   padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          //   color: Colors.green[700],
          //   child: const Text('Waveform processing complete.', style: TextStyle(color: Colors.white)),
          // );
          // Or just hide it
          return const SizedBox.shrink();
        } else {
          // State is Initial or Error - hide the progress bar
          return const SizedBox.shrink();
        }
      },
    );
  }
}
