// lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart'; // Import Provider

// Import your BLoCs and Services
import 'blocs/audio_player/audio_player_bloc.dart';
import 'blocs/collection/collection_bloc.dart';
import 'blocs/playlist/playlist_bloc.dart'; // Import PlaylistBloc
import 'services/audio_service.dart';
import 'services/collection_service.dart';
import 'services/playlist_service.dart'; // Import PlaylistService
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
          BlocProvider<AudioPlayerBloc>(
            create: (context) => AudioPlayerBloc(context.read<AudioService>()),
          ),
          BlocProvider<CollectionBloc>(
            create:
                (context) => CollectionBloc(
                    // 1. Pass service as a positional argument
                    context.read<CollectionService>(),
                  )
                  // 2. Use the correct event constructor
                  ..add(LoadCollection()),
          ),

          BlocProvider<PlaylistBloc>(
            // Provide PlaylistBloc
            create:
                (context) => PlaylistBloc(
                  playlistService: context.read<PlaylistService>(),
                )..add(LoadPlaylists()), // Load initial playlists
          ),
          // Add other BLoCs if needed
        ],
        child: MaterialApp(
          title: 'Audio Organizer App',
          theme: ThemeData(
            primarySwatch: Colors.blue,
            visualDensity: VisualDensity.adaptivePlatformDensity,
            useMaterial3: true, // Optional: Use Material 3 design
          ),
          home: const HomeScreen(),
          // Define routes if you have more screens
        ),
      ),
    );
  }
}
