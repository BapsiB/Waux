import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:audio_looker/blocs/audio_player/audio_player_bloc.dart';
import 'package:audio_looker/blocs/collection/collection_bloc.dart';
import 'package:audio_looker/screens/home_screen.dart';
import 'package:audio_looker/services/audio_service.dart';
import 'package:audio_looker/services/collection_service.dart';

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize services
  final collectionService = CollectionService();
  await collectionService.initialize();

  final audioService = AudioService();
  await audioService.initialize();

  runApp(
    MyApp(collectionService: collectionService, audioService: audioService),
  );
}

class MyApp extends StatelessWidget {
  final CollectionService collectionService;
  final AudioService audioService;

  const MyApp({
    Key? key,
    required this.collectionService,
    required this.audioService,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<CollectionBloc>(
          create: (context) {
            final collectionService = CollectionService();
            // ONLY add LoadCollection initially
            return CollectionBloc(collectionService)..add(
              LoadCollection(),
            ); // <-- LoadCollection now loads everything needed initially
            // ..add(LoadAllTags());   // <-- REMOVE this line for initial load
          },
        ),
        BlocProvider<AudioPlayerBloc>(
          create: (context) => AudioPlayerBloc(audioService),
        ),
      ],
      child: MaterialApp(
        title: 'Music Collector',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.deepPurple,
          brightness: Brightness.dark,
          // fontFamily: 'Poppins', // Remove this reference
          useMaterial3: true,
          cardTheme: const CardTheme(
            elevation: 4,
            margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              elevation: 2,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          appBarTheme: const AppBarTheme(elevation: 0, centerTitle: false),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
