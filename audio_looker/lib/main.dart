// lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart'; // Import Provider

// Import your BLoCs and Services
import 'blocs/audio_player/audio_player_bloc.dart';
import 'blocs/collection_management/collection_management_bloc.dart';
import 'blocs/playlist/playlist_bloc.dart';
import 'blocs/track_management/track_data_bloc.dart'; // <<< ADDED: Import new BLoC
import 'blocs/track_management/track_metadata_bloc.dart'; // <<< ADDED: Import new BLoC
import 'blocs/track_management/global_tag_bloc.dart';
import 'blocs/waveform_processing/waveform_processing_bloc.dart';

import 'services/waveform_processing_service.dart'; // Import new Service
import 'services/audio_service.dart';
import 'services/collection_service.dart';
import 'services/playlist_service.dart';
import 'screens/home_screen.dart';
// Import other necessary files

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize services
  final audioService = AudioService();
  // Initialize the singleton instance
  await audioService.initialize();

  final collectionService = CollectionService();
  final playlistService = PlaylistService(); // Initialize PlaylistService
  final waveformProcessingService = WaveformProcessingService();

  runApp(
    MyApp(
      audioService: audioService,
      collectionService: collectionService,
      playlistService: playlistService, // Pass PlaylistService
      waveformProcessingService:
          waveformProcessingService, // Pass WaveformProcessingService
    ),
  );
}

class MyApp extends StatelessWidget {
  final AudioService audioService;
  final CollectionService collectionService;
  final PlaylistService playlistService; // Add PlaylistService
  final WaveformProcessingService waveformProcessingService;

  const MyApp({
    super.key,
    required this.audioService,
    required this.collectionService,
    required this.playlistService, // Add to constructor
    required this.waveformProcessingService,
  });

  @override
  Widget build(BuildContext context) {
    // Use MultiRepositoryProvider to provide services
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: audioService),
        RepositoryProvider.value(value: collectionService),
        RepositoryProvider.value(value: playlistService),
        RepositoryProvider.value(value: waveformProcessingService),
      ],
      // Use MultiBlocProvider to provide BLoCs
      child: MultiBlocProvider(
        providers: [
          // Create TrackDataBloc first
          BlocProvider<TrackDataBloc>(
            create:
                (context) => TrackDataBloc(
                  collectionService: context.read<CollectionService>(),
                  waveformProcessingService:
                      context.read<WaveformProcessingService>(),
                  // IMPORTANT: Defer accessing WaveformProcessingBloc here if possible,
                  // or ensure it's handled safely within TrackDataBloc.
                  // For this specific error, the issue is the other way around.
                  // We'll leave this as is for now, assuming TrackDataBloc doesn't immediately need WaveformProcessingBloc *during creation*.
                  // waveformProcessingBloc:
                  //     context
                  //         .read<
                  //           WaveformProcessingBloc
                  //         >(), // This might still be problematic if lazy: false below
                ),
          ),
          // THEN Create WaveformProcessingBloc, using context.read
          BlocProvider<WaveformProcessingBloc>(
            create:
                (context) => WaveformProcessingBloc(
                  waveformProcessingService:
                      context.read<WaveformProcessingService>(),
                  // Use context.read which is generally safer during build/create phases
                  trackDataBloc:
                      context.read<TrackDataBloc>(), // <<< Use context.read
                ),
            // Consider if lazy: false is strictly necessary. If true, it might create TrackDataBloc first.
            // If the error persists, you might need lazy: true here or restructure dependencies.
            lazy: false,
          ),
          // --- Ensure dependent BLoCs are created first ---
          BlocProvider<CollectionManagementBloc>(
            create:
                (context) => CollectionManagementBloc(
                  context.read<CollectionService>(),
                )..add(LoadCollectionList()), // Load collection list initially
          ),
          BlocProvider<TrackMetadataBloc>(
            // <<< Create TrackMetadataBloc
            create:
                (context) =>
                    TrackMetadataBloc(context.read<CollectionService>()),
          ),
          BlocProvider<GlobalTagBloc>(
            // <<< Create GlobalTagBloc
            create:
                (context) =>
                    GlobalTagBloc(context.read<CollectionService>())
                      ..add(LoadGlobalTags()),
          ),
          // --- BLoCs that might depend on others ---
          BlocProvider<AudioPlayerBloc>(
            create:
                (context) => AudioPlayerBloc(
                  context.read<AudioService>(),
                  context.read<TrackMetadataBloc>(),
                ),
          ),
          BlocProvider<PlaylistBloc>(
            create:
                (context) => PlaylistBloc(
                  playlistService: context.read<PlaylistService>(),
                  collectionService: context.read<CollectionService>(),
                )..add(LoadPlaylists()), // Load playlists initially
          ),
        ],
        child: MaterialApp(
          title: 'WAUX', // Updated App Name
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
            useMaterial3: true,
            visualDensity: VisualDensity.adaptivePlatformDensity,
            cardTheme: CardTheme(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.deepPurple,
              brightness: Brightness.dark, // Dark mode
            ),
            useMaterial3: true,
            visualDensity: VisualDensity.adaptivePlatformDensity,
            cardTheme: CardTheme(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
          themeMode: ThemeMode.system, // Or ThemeMode.light / ThemeMode.dark
          home: const HomeScreen(),
          // Define routes if you have more screens
        ),
      ),
    );
  }
}
