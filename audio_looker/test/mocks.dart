// test/mocks.dart (or directly in your test file)
import 'package:mocktail/mocktail.dart';
import 'package:waux/services/playlist_service.dart';
import 'package:waux/services/collection_service.dart';
import 'package:waux/models/playlist.dart'; // Import Playlist model

// Mock PlaylistService
class MockPlaylistService extends Mock implements PlaylistService {}

// Mock CollectionService
class MockCollectionService extends Mock {}

// Mock Playlist (optional, if needed for complex setups)
class MockPlaylist extends Mock implements Playlist {}

class FakeCollectionService extends Fake implements CollectionService {}
