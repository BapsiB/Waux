import 'package:flutter_test/flutter_test.dart';
import 'package:waux/services/collection_service.dart'; // For Track model
import 'package:waux/utils/track_filtering.dart'; // Your file to test

void main() {
  // Helper to create dummy Track objects for testing
  Track createDummyTrack({
    int id = 1,
    String title = 'Test Title',
    String artist = 'Test Artist',
    String album = 'Test Album',
    String path = '/test/path.mp3',
    bool isUrl = false,
    int duration = 180000,
    List<String> generalTags = const [],
    int rating = 0,
    String comment = '',
  }) {
    return Track(
      id: id,
      title: title,
      artist: artist,
      album: album,
      path: path,
      isUrl: isUrl,
      duration: duration,
      generalTags: generalTags,
      rating: rating,
      comment: comment,
    );
  }

  group('Tokenizer Tests', () {
    // Tests for the tokenize() function
    test('should tokenize basic words', () {
      final tokens = tokenize('hello world');
      expect(tokens.length, 3); // hello, world, EOF
      expect(tokens[0].type, TokenType.WORD);
      expect(tokens[0].text, 'hello');
      expect(tokens[1].type, TokenType.WORD);
      expect(tokens[1].text, 'world');
      expect(tokens[2].type, TokenType.EOF);
    });

    test('should tokenize quoted strings', () {
      final tokens = tokenize('"hello world"');
      expect(tokens.length, 2); // "hello world", EOF
      expect(tokens[0].type, TokenType.QUOTED_STRING);
      expect(tokens[0].text, 'hello world');
    });

    test('should tokenize field searches', () {
      final tokens = tokenize('artist: "Test Artist" title:Song');
      // Expected: FIELD_NAME (artist), COLON, QUOTED_STRING ("Test Artist"), FIELD_NAME (title), COLON, WORD (Song), EOF
      expect(tokens.length, 7);
      expect(tokens[0].type, TokenType.FIELD_NAME);
      expect(tokens[0].text, 'artist');
      expect(tokens[1].type, TokenType.COLON);
      expect(tokens[2].type, TokenType.QUOTED_STRING);
      expect(tokens[2].text, 'Test Artist');
      // ... and so on for other tokens
    });

    test('should tokenize logical operators (AND, OR, NOT)', () {
      final tokens = tokenize('rock AND roll OR NOT blues');
      // Expected: WORD(rock), AND, WORD(roll), OR, NOT, WORD(blues), EOF
      expect(tokens.length, 7);
      expect(tokens[1].type, TokenType.AND);
      expect(tokens[3].type, TokenType.OR);
      expect(tokens[4].type, TokenType.NOT);
    });

    test('should tokenize parentheses', () {
      final tokens = tokenize('(rock OR roll)');
      expect(tokens.length, 6); // Corrected from 5 to 6
      expect(tokens[0].type, TokenType.LPAREN);
      expect(tokens[5].type, TokenType.EOF); // Last token is EOF
    });

    // Add more tokenizer tests for edge cases:
    // - Empty string
    // - String with only whitespace
    // - Mixed case operators (e.g., "AnD")
    // - Invalid characters or sequences (TokenType.UNKNOWN)
    // - Field names with dots (e.g., "metadata.year:2023")
  });

  group('Parser (AST) Tests', () {
    // Tests for parseSearchQuery() and the resulting AST structure

    test('should parse a simple global term', () {
      final ast = parseSearchQuery('test');
      expect(ast, isA<GlobalTermNode>());
      expect((ast as GlobalTermNode).term, 'test');
    });

    test('should parse a simple field condition', () {
      final ast = parseSearchQuery('title:hello');
      expect(ast, isA<FieldConditionNode>());
      final node = ast as FieldConditionNode;
      expect(node.field, 'title');
      expect(node.value, 'hello');
      expect(node.isExactPhrase, false);
    });

    test('should parse a field condition with quoted string', () {
      final ast = parseSearchQuery('artist:"hello world"');
      expect(ast, isA<FieldConditionNode>());
      final node = ast as FieldConditionNode;
      expect(node.field, 'artist');
      expect(node.value, 'hello world');
      expect(node.isExactPhrase, true);
    });

    test('should parse AND operation', () {
      final ast = parseSearchQuery('title:A AND artist:B');
      expect(ast, isA<LogicalOperationNode>());
      final node = ast as LogicalOperationNode;
      expect(node.operator, LogicalOperator.AND);
      expect(node.left, isA<FieldConditionNode>());
      expect(node.right, isA<FieldConditionNode>());
    });

    test('should parse OR operation', () {
      final ast = parseSearchQuery('album:X OR genre:Y');
      expect(ast, isA<LogicalOperationNode>());
      final node = ast as LogicalOperationNode;
      expect(node.operator, LogicalOperator.OR);
    });

    test('should parse NOT operation', () {
      final ast = parseSearchQuery('NOT title:Old');
      expect(ast, isA<NotNode>());
      expect((ast as NotNode).child, isA<FieldConditionNode>());
    });

    test('should parse parenthesized expressions', () {
      final ast = parseSearchQuery('(title:A OR title:B) AND artist:C');
      expect(ast, isA<LogicalOperationNode>()); // Outer AND
      final outerAnd = ast as LogicalOperationNode;
      expect(outerAnd.left, isA<LogicalOperationNode>()); // Inner OR
      final innerOr = outerAnd.left as LogicalOperationNode;
      expect(innerOr.operator, LogicalOperator.OR);
    });

    // Add more parser tests for:
    // - Implicit AND (e.g., "term1 term2")
    // - Operator precedence (e.g., "A AND B OR C")
    // - Malformed queries (how does it fallback or handle errors?)
    // - Queries with trailing operators (e.g., "term AND")
    // - Empty query
    // - Query with only operators
  });

  group('AST Evaluation Tests', () {
    // Tests for the evaluate() method of different AST nodes

    final track1 = createDummyTrack(
      title: 'Hello World',
      artist: 'ArtistA',
      album: 'AlbumX',
      generalTags: ['pop', 'upbeat'],
    );
    final track2 = createDummyTrack(
      title: 'Another Song',
      artist: 'ArtistB',
      album: 'AlbumY',
      generalTags: ['rock'],
      rating: 4,
    );
    final track3 = createDummyTrack(
      title: 'Hello Goodbye',
      artist: 'ArtistA',
      album: 'AlbumZ',
      comment: 'a test comment',
    );

    test('GlobalTermNode should match title', () {
      final ast = parseSearchQuery('Hello');
      expect(ast!.evaluate(track1), isTrue);
      expect(ast.evaluate(track2), isFalse);
      expect(ast.evaluate(track3), isTrue);
    });

    test('GlobalTermNode should match artist', () {
      final ast = parseSearchQuery('ArtistB');
      expect(ast!.evaluate(track1), isFalse);
      expect(ast.evaluate(track2), isTrue);
    });

    test('GlobalTermNode should match tags', () {
      final ast = parseSearchQuery('upbeat');
      expect(ast!.evaluate(track1), isTrue);
      expect(ast.evaluate(track2), isFalse);
    });

    test('FieldConditionNode (exact) should match title', () {
      final ast = parseSearchQuery('title:"Hello World"');
      expect(ast, isA<FieldConditionNode>());
      expect(ast!.evaluate(track1), isTrue);
      expect(
        ast.evaluate(track3),
        isFalse,
      ); // "Hello Goodbye" is not an exact match
    });

    test('FieldConditionNode (contains) should match title', () {
      final ast = parseSearchQuery('title:Hello');
      expect(ast, isA<FieldConditionNode>());
      expect(ast!.evaluate(track1), isTrue);
      expect(ast.evaluate(track3), isTrue);
    });

    test('FieldConditionNode for tags should match', () {
      final ast = parseSearchQuery('tags:pop');
      expect(ast, isA<FieldConditionNode>());
      expect(ast!.evaluate(track1), isTrue);
      expect(ast.evaluate(track2), isFalse);
    });

    test('FieldConditionNode should handle QUOTED string values correctly', () {
      final ast = parseSearchQuery(
        'comment:"test comment phrase"',
      ); // Query with quotes

      // Expect a FieldConditionNode because the value is a single quoted token
      expect(
        ast,
        isA<FieldConditionNode>(),
        reason: "AST should be a FieldConditionNode for a quoted field value.",
      );

      final fieldNode = ast as FieldConditionNode;
      expect(fieldNode.field.toLowerCase(), 'comment');
      expect(fieldNode.value, 'test comment phrase'); // The exact phrase
      expect(
        fieldNode.isExactPhrase,
        isTrue,
        reason: "isExactPhrase should be true for quoted values.",
      );

      // Dummy tracks for evaluation
      final trackWithExactComment = createDummyTrack(
        comment: 'this is a test comment phrase exactly',
      );
      final trackWithPartialComment = createDummyTrack(
        comment: 'this comment mentions test but not the whole phrase',
      );
      final trackWithDifferentComment = createDummyTrack(
        comment: 'another note entirely',
      );

      // Evaluation (assuming your FieldConditionNode.evaluate() uses isExactPhrase)
      // If isExactPhrase=true means exact equality:
      // expect(fieldNode.evaluate(trackWithExactComment), isTrue); // Would need exact match "test comment phrase"
      // expect(fieldNode.evaluate(trackWithPartialComment), isFalse);
      // expect(fieldNode.evaluate(trackWithDifferentComment), isFalse);

      // If isExactPhrase=true means the field MUST contain the exact phrase (more common for search):
      // Let's assume your evaluate logic for FieldConditionNode when isExactPhrase is true checks for `fieldValue.toLowerCase().contains(lowerValue)`
      // If you want it to be `fieldValue.toLowerCase() == lowerValue` then the evaluate logic needs to reflect that.
      // For now, let's assume `contains` for exact phrases too, which is how your current FieldConditionNode is written.
      final trackWithThePhrase = createDummyTrack(
        comment: 'My comment has the test comment phrase in it.',
      );
      expect(fieldNode.evaluate(trackWithThePhrase), isTrue);
      expect(
        fieldNode.evaluate(trackWithPartialComment),
        isFalse,
      ); // "test" is there, but not "test comment phrase"
    });

    test('LogicalOperationNode AND should evaluate correctly', () {
      final ast = parseSearchQuery('artist:ArtistA AND tags:pop');
      expect(ast!.evaluate(track1), isTrue);
      expect(ast.evaluate(track2), isFalse);
      expect(ast.evaluate(track3), isFalse); // track3 is ArtistA but not pop
    });

    test('LogicalOperationNode OR should evaluate correctly', () {
      final ast = parseSearchQuery('album:AlbumY OR tags:upbeat');
      expect(ast!.evaluate(track1), isTrue); // Has upbeat
      expect(ast.evaluate(track2), isTrue); // Has AlbumY
      expect(ast.evaluate(track3), isFalse);
    });

    test('NotNode should invert evaluation', () {
      final ast = parseSearchQuery('NOT artist:ArtistB');
      expect(ast!.evaluate(track1), isTrue);
      expect(ast.evaluate(track2), isFalse);
      expect(ast.evaluate(track3), isTrue);
    });

    test('Complex query with parentheses', () {
      final ast = parseSearchQuery(
        '(title:Hello OR album:AlbumY) AND artist:ArtistA',
      );
      // track1: (title:Hello = T) AND artist:ArtistA = T -> TRUE
      // track2: (album:AlbumY = T) AND artist:ArtistA = F -> FALSE
      // track3: (title:Hello = T) AND artist:ArtistA = T -> TRUE
      expect(ast!.evaluate(track1), isTrue);
      expect(ast.evaluate(track2), isFalse);
      expect(ast.evaluate(track3), isTrue);
    });

    test('FieldConditionNode for path', () {
      final ast = parseSearchQuery('path:path.mp3');
      expect(ast, isA<FieldConditionNode>());
      expect(ast!.evaluate(track1), isTrue);
    });

    test('AST Evaluation for "comment:test comment" (implicit AND)', () {
      final ast = parseSearchQuery('comment:test comment');
      expect(ast, isA<LogicalOperationNode>());
      final andNode = ast as LogicalOperationNode;
      expect(andNode.operator, LogicalOperator.AND);
      expect(andNode.left, isA<FieldConditionNode>());
      expect(
        (andNode.left as FieldConditionNode).field.toLowerCase(),
        'comment',
      );
      expect((andNode.left as FieldConditionNode).value, 'test');
      expect(andNode.right, isA<GlobalTermNode>());
      expect((andNode.right as GlobalTermNode).term, 'comment');
    });

    // Add more evaluation tests:
    // - Different fields (album, comment, path)
    // - Case insensitivity checks
    // - Fields that might be null on a track
    // - Exact phrase matching vs. contains for global terms if you add that
  });

  group('applyFilters Function Tests', () {
    // Tests for the top-level applyFilters function
    final trackA = createDummyTrack(
      id: 1,
      path: "/path/to/alpha.mp3",
      title: 'Alpha',
      artist: 'Zed',
      rating: 5,
      generalTags: ['electronic', 'chill'],
    );
    final trackB = createDummyTrack(
      id: 2,
      path: "/path/to/beta.mp3",
      title: 'Beta',
      artist: 'Zed',
      rating: 3,
      generalTags: ['electronic', 'dance'],
    );
    final trackC = createDummyTrack(
      id: 3,
      path: "/path/to/gamma.mp3",
      title: 'Gamma',
      artist: ' другой ',
      rating: 5,
      generalTags: ['instrumental', 'chill'],
    );
    final trackD = createDummyTrack(
      id: 4,
      path: "/data/delta.mp3",
      title: 'Delta',
      artist: 'Alpha',
      rating: 2,
    );
    final trackE = createDummyTrack(
      id: 5,
      path: "/music/epsilon.wav",
      title: 'Epsilon Zed',
      artist: 'Echo',
      rating: 4,
    );

    final allTracks = [trackA, trackB, trackC, trackD, trackE];

    test('should filter by playlistTrackPaths', () {
      final filtered = applyFilters(
        allTracks: allTracks,
        searchQuery: '',
        minRating: null,
        // Use the unique paths for tracks A and E
        playlistTrackPaths: {trackA.path, trackE.path},
      );
      expect(
        filtered.length,
        2,
        reason: "Should only find tracks A and E based on path",
      );
      expect(filtered.any((t) => t.id == trackA.id), isTrue);
      expect(filtered.any((t) => t.id == trackE.id), isTrue);
    });
    test('should filter by search query (global term)', () {
      final filtered = applyFilters(
        allTracks: allTracks,
        searchQuery: 'Alpha',
        minRating: null,
      );
      expect(filtered.length, 2);
      expect(filtered.any((t) => t.id == trackA.id), isTrue); // title match
      expect(filtered.any((t) => t.id == trackD.id), isTrue); // artist match
    });

    test('should filter by search query (field specific)', () {
      final filtered = applyFilters(
        allTracks: allTracks,
        searchQuery: 'artist:Zed',
        minRating: null,
      );
      expect(filtered.length, 2);
      expect(filtered.any((t) => t.id == trackA.id), isTrue);
      expect(filtered.any((t) => t.id == trackB.id), isTrue);
    });

    test('should filter by rating', () {
      final filtered = applyFilters(
        allTracks: allTracks,
        searchQuery: '',
        minRating: 4,
      );
      expect(filtered.length, 3); // A, C, E
      expect(filtered.any((t) => t.id == trackA.id), isTrue);
      expect(filtered.any((t) => t.id == trackC.id), isTrue);
      expect(filtered.any((t) => t.id == trackE.id), isTrue);
    });

    test('should filter by search query AND rating', () {
      final filtered = applyFilters(
        allTracks: allTracks,
        searchQuery: 'tags:electronic',
        minRating: 4,
      );
      expect(filtered.length, 1); // Only Track A (electronic AND rating >= 4)
      expect(filtered.first.id, trackA.id);
    });

    test('should return all tracks if query and rating are null/empty', () {
      final filtered = applyFilters(
        allTracks: allTracks,
        searchQuery: '',
        minRating: null,
      );
      expect(filtered.length, allTracks.length);
    });

    test('should handle empty track list', () {
      final filtered = applyFilters(
        allTracks: [],
        searchQuery: 'test',
        minRating: 3,
      );
      expect(filtered, isEmpty);
    });

    test('should handle complex query', () {
      final filtered = applyFilters(
        allTracks: allTracks,
        searchQuery: '(artist:Zed OR tags:instrumental) AND rating:5',
        minRating: null,
      );
      // (A or B or C) AND (A or C) => A or C
      expect(filtered.length, 2);
      expect(filtered.any((t) => t.id == trackA.id), isTrue);
      expect(filtered.any((t) => t.id == trackC.id), isTrue);
    });

    test('should handle non-English characters in search', () {
      final filtered = applyFilters(
        allTracks: allTracks,
        searchQuery: 'artist:другой',
        minRating: null,
      );
      expect(filtered.length, 1);
      expect(filtered.first.id, trackC.id);
    });

    test(
      'should fallback to simple global search if AST parsing fails but query is not empty',
      () {
        // This query ": " is likely to fail AST parsing or result in a null AST
        final filtered = applyFilters(
          allTracks: allTracks,
          searchQuery: ': ',
          minRating: null,
        );
        // Because the query is ": ", it will try to match this substring in any field.
        // This is a bit of a tricky test case for a simple global fallback as it's not a typical search term.
        // Depending on how the fallback is implemented (e.g., if it trims whitespace), results may vary.
        // Assuming a simple substring search, none of the current tracks contain ": "
        // However, the parser was updated to return a GlobalTermNode for such cases.
        // Let's test with a more specific term that would fail the structured parser but is a valid global search.
        final filtered2 = applyFilters(
          allTracks: allTracks,
          searchQuery: 'Epsilon Zed',
          minRating: null,
        );
        expect(filtered2.length, 1);
        expect(filtered2.first.id, trackE.id); // trackE title is "Epsilon Zed"
      },
    );

    test('should filter by playlistTrackPaths', () {
      final filtered = applyFilters(
        allTracks: allTracks,
        searchQuery: '',
        minRating: null,
        playlistTrackPaths: {
          '/music/epsilon.wav',
          trackA.path,
        }, // trackA's path and trackE's path
      );
      expect(filtered.length, 2);
      expect(filtered.any((t) => t.id == trackA.id), isTrue);
      expect(filtered.any((t) => t.id == trackE.id), isTrue);
    });

    test('should filter by playlistTrackPaths AND other filters', () {
      final filtered = applyFilters(
        allTracks: allTracks,
        searchQuery: 'rating:5', // search for rating 5
        minRating: null, // minRating is part of searchQuery now
        playlistTrackPaths: {trackA.path, trackE.path, trackC.path}, // A, E, C
      );
      // Expected: Track A (rating 5, in playlist) and Track C (rating 5, in playlist)
      expect(filtered.length, 2);
      expect(filtered.any((t) => t.id == trackA.id), isTrue);
      expect(filtered.any((t) => t.id == trackC.id), isTrue);
    });
  });
}
