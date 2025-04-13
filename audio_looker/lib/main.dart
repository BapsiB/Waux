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

  runApp(
    MyApp(
      audioService: audioService,
      collectionService: collectionService,
      playlistService: playlistService, // Pass PlaylistService
    ),
  );
}

class MyApp extends StatelessWidget {
  final AudioService audioService;
  final CollectionService collectionService;
  final PlaylistService playlistService; // Add PlaylistService

  const MyApp({
    super.key,
    required this.audioService,
    required this.collectionService,
    required this.playlistService, // Add to constructor
  });

  @override
  Widget build(BuildContext context) {
    // Use MultiRepositoryProvider to provide services
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: audioService),
        RepositoryProvider.value(value: collectionService),
        RepositoryProvider.value(
          value: playlistService,
        ), // Provide PlaylistService
      ],
      // Use MultiBlocProvider to provide BLoCs
      child: MultiBlocProvider(
        providers: [
          // Keep existing BLoCs
          BlocProvider<AudioPlayerBloc>(
            create: (context) => AudioPlayerBloc(context.read<AudioService>()),
          ),
          BlocProvider<PlaylistBloc>(
            create:
                (context) => PlaylistBloc(
                  playlistService: context.read<PlaylistService>(),
                  // PlaylistBloc depends on CollectionService to know the active collection
                  collectionService: context.read<CollectionService>(),
                )..add(LoadPlaylists()), // Load playlists initially
          ),
          BlocProvider<CollectionManagementBloc>(
            create:
                (context) => CollectionManagementBloc(
                  context.read<CollectionService>(),
                )..add(LoadCollectionList()), // Load collection list initially
          ),

          // --- REMOVED Old TrackManagementBloc Provider ---
          // BlocProvider<TrackManagementBloc>( ... ),

          // +++ ADDED New BLoC Providers +++

          // 1. TrackDataBloc
          BlocProvider<TrackDataBloc>(
            create:
                (context) => TrackDataBloc(context.read<CollectionService>()),
            // Note: Initial data loading for TrackDataBloc is typically triggered
            // by the UI (e.g., HomeScreen) listening to CollectionManagementBloc
            // and dispatching LoadTracks when a collection becomes active.
          ),

          // 2. TrackMetadataBloc
          BlocProvider<TrackMetadataBloc>(
            create:
                (context) =>
                    TrackMetadataBloc(context.read<CollectionService>()),
          ),
          // +++ ADD GlobalTagBloc Provider HERE +++
          BlocProvider<GlobalTagBloc>(
            create:
                (context) => GlobalTagBloc(
                  context.read<CollectionService>(),
                  // Optionally load tags immediately after creation
                )..add(LoadGlobalTags()),
          ),
          // Add other BLoCs if needed (e.g., GlobalTagBloc, WaveformProcessingBloc later)
        ],
        child: MaterialApp(
          title: 'Audio Looker', // Updated App Name
          theme: ThemeData(
            // Consider using a seed color for Material 3 theming
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
            useMaterial3: true,
            visualDensity: VisualDensity.adaptivePlatformDensity,
            // Optional: Define specific theme components
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
