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
            // <<< Create AudioPlayerBloc
            create:
                (context) => AudioPlayerBloc(
                  context.read<AudioService>(),
                  context
                      .read<
                        TrackMetadataBloc
                      >(), // <<< Inject TrackMetadataBloc
                ),
          ),
          BlocProvider<PlaylistBloc>(
            // <<< Create PlaylistBloc
            create:
                (context) => PlaylistBloc(
                  playlistService: context.read<PlaylistService>(),
                  collectionService: context.read<CollectionService>(),
                )..add(LoadPlaylists()), // Load playlists initially
          ),
          BlocProvider<TrackDataBloc>(
            // <<< Create TrackDataBloc
            create:
                (context) => TrackDataBloc(context.read<CollectionService>()),
          ),
        ],
        child: MaterialApp(
          title: 'Audio Looker', // Updated App Name
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
