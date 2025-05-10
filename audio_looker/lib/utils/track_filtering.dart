// lib/utils/track_filtering.dart
import '../services/collection_service.dart'; // For Track model
import 'package:path/path.dart' as pathLib;

// --- Tokenizer and AST Helper Classes/Enums ---

enum TokenType {
  WORD, // A general word or value (e.g., song_title, artist_name)
  QUOTED_STRING, // A value enclosed in double quotes (e.g., "The Best Song")
  FIELD_NAME, // A specific field identifier (e.g., title, artist) - before colon
  COLON, // Separator for field searches (:)
  AND, // Logical AND operator
  OR, // Logical OR operator
  NOT, // Logical NOT operator
  LPAREN, // Left parenthesis (
  RPAREN, // Right parenthesis )
  EOF, // End of File/Query
  UNKNOWN, // For unrecognized characters/sequences
}

class Token {
  final TokenType type;
  final String text; // The actual text of the token
  final int position; // Starting position in the original query

  Token(this.type, this.text, this.position);

  @override
  String toString() => 'Token(${type.name}, "$text", @$position)';
}

class TokenStream {
  final List<Token> _tokens;
  int _currentIndex = 0;

  TokenStream(this._tokens);

  Token consume() {
    if (isAtEnd() && _tokens.isNotEmpty && _tokens.last.type == TokenType.EOF) {
      return _tokens.last; // Return EOF token without advancing past it
    }
    if (_currentIndex < _tokens.length) {
      return _tokens[_currentIndex++];
    }
    // This should ideally not be reached if EOF is handled correctly
    throw StateError("Cannot consume past the end of token stream.");
  }

  Token peek() {
    if (_currentIndex < _tokens.length) {
      return _tokens[_currentIndex];
    }
    // If _tokens is empty or index is out of bounds (shouldn't happen with EOF)
    // Return a synthetic EOF if the list was empty or malformed initially
    return Token(TokenType.EOF, "", 0);
  }

  Token? peekNext() {
    if (_currentIndex + 1 < _tokens.length) {
      return _tokens[_currentIndex + 1];
    }
    return null;
  }

  bool isAtEnd() {
    // Considered at end if current index is at the last token which should be EOF
    // or if the stream is empty.
    if (_tokens.isEmpty) return true;
    return _currentIndex >= _tokens.length - 1 &&
        _tokens.last.type == TokenType.EOF;
  }

  bool match(List<TokenType> types) {
    if (isAtEnd() && !_tokens.any((t) => types.contains(t.type)))
      return false; // Avoid peeking past end if current is EOF and not in types
    if (types.contains(peek().type)) {
      consume();
      return true;
    }
    return false;
  }

  // Helper to check if the current token sequence looks like a field search
  bool peekIsFieldSearch() {
    if (isAtEnd()) return false;
    final current = peek();
    final next = peekNext();
    // A field name is usually a WORD token, followed by a COLON
    return current.type == TokenType.WORD && next?.type == TokenType.COLON;
  }
}

List<Token> tokenize(String query) {
  final List<Token> tokens = [];
  int currentPosition = 0;

  // MODIFIED Regex:
  // Group 1: Logical operators (AND, OR, NOT)
  // Group 2: Field names (word followed by :) - field name is group 3.
  //          Field name regex ([a-zA-Z_][\w\.]*) allows letters, numbers, underscore, dot, must start with letter or underscore.
  // Group 4: Quoted strings (content in group 5)
  // Group 6: Left parenthesis
  // Group 7: Right parenthesis
  // Group 8: Unquoted words/values - MODIFIED to (\w[\w\.]*) to allow starting with a number. \w is [a-zA-Z0-9_].
  // Group 9: Colon (standalone) - should ideally be an error or handled carefully.
  // Group 10: Any other sequence of one or more non-whitespace, non-parenthesis, non-colon, non-quote characters - This will catch Unicode words and other values.
  final RegExp pattern = RegExp(
    r'\s*(?:' // Optional whitespace
    r'(\b(?:AND|OR|NOT)\b)|' // 1: Logical operators (case insensitive for keywords)
    r'(([a-zA-Z_][\w\.-]*)\s*:)|' // 2: Field names (word, dots, hyphens) followed by colon (field name in group 3)
    r'("([^"]*)")|' // 4: Quoted strings (content in group 5)
    r'(\()|' // 6: Left parenthesis
    r'(\))|' // 7: Right parenthesis
    // MODIFIED Group 8: General words/values (alphanumeric, underscore, dot, hyphen). Order is important.
    // This needs to come AFTER specific operators and field name syntax.
    r'(\w[\w\.-]*)|'
    r'(:)|' // 9: Standalone Colon
    // MODIFIED Group 10: Catch-all for other sequences of characters that are not structural (space, quotes, parens, colon)
    // This is intended to pick up Unicode words or other unquoted multi-character values.
    r'([^\s:"\(\)]+)'
    r')\s*', // Optional trailing whitespace
    caseSensitive:
        false, // Operators (AND,OR,NOT) will be matched case-insensitively
    // Field names and values will retain their case from the query for the token text
    // but field names are converted toLowerCased when creating FIELD_NAME token.
  );

  for (final Match m in pattern.allMatches(query)) {
    final int matchStart = m.start;

    if (m.group(1) != null) {
      // Logical operator
      final opText = m.group(1)!.toUpperCase(); // Normalize to uppercase
      if (opText == 'AND')
        tokens.add(Token(TokenType.AND, opText, matchStart));
      else if (opText == 'OR')
        tokens.add(Token(TokenType.OR, opText, matchStart));
      else if (opText == 'NOT')
        tokens.add(Token(TokenType.NOT, opText, matchStart));
    } else if (m.group(2) != null) {
      // Field name with colon
      tokens.add(
        Token(TokenType.FIELD_NAME, m.group(3)!.toLowerCase(), matchStart),
      ); // field name (group 3) to lowercase
      tokens.add(Token(TokenType.COLON, ":", m.start + m.group(3)!.length));
    } else if (m.group(4) != null) {
      // Quoted string
      tokens.add(
        Token(TokenType.QUOTED_STRING, m.group(5) ?? "", matchStart + 1),
      );
    } else if (m.group(6) != null) {
      // Left parenthesis
      tokens.add(Token(TokenType.LPAREN, "(", matchStart));
    } else if (m.group(7) != null) {
      // Right parenthesis
      tokens.add(Token(TokenType.RPAREN, ")", matchStart));
    } else if (m.group(8) != null) {
      // WORD (Alphanumeric, _, ., - starting with \w)
      tokens.add(Token(TokenType.WORD, m.group(8)!, matchStart));
    } else if (m.group(9) != null) {
      // Standalone Colon
      // Depending on desired strictness, this could be an UNKNOWN/error
      // For now, let's treat it as a WORD if it's not part of a field identifier.
      // However, the regex should make this group less likely to hit if a field was intended.
      tokens.add(Token(TokenType.COLON, ":", matchStart));
      // Consider if this should be UNKNOWN or if parser should handle it as an error.
      // print("Warning: Standalone colon tokenized at $matchStart");
    } else if (m.group(10) != null) {
      // Other non-whitespace, non-structural characters (e.g. Unicode words for values)
      tokens.add(Token(TokenType.WORD, m.group(10)!, matchStart));
    }
    currentPosition = m.end;
  }

  // This check is if the regex didn't consume the whole string, implying characters the regex couldn't categorize.
  // With the wide Group 10, this should be less common unless query has truly unsupported structures.
  if (currentPosition < query.length &&
      query.substring(currentPosition).trim().isNotEmpty) {
    tokens.add(
      Token(
        TokenType.UNKNOWN,
        query.substring(currentPosition).trim(),
        currentPosition,
      ),
    );
    print(
      "Warning: Trailing unknown characters found: ${query.substring(currentPosition).trim()}",
    );
  }

  tokens.add(Token(TokenType.EOF, "", query.length));
  print("Tokens: ${tokens.map((t) => t.toString()).join('\n')}");
  return tokens;
}

// --- AST Node Classes ---
enum LogicalOperator { AND, OR }

abstract class QueryNode {
  bool evaluate(Track track);
}

class FieldConditionNode implements QueryNode {
  final String field;
  final String value;
  final bool isExactPhrase;

  FieldConditionNode(this.field, this.value, {this.isExactPhrase = false});

  bool evaluate(Track track) {
    final fieldValue = _getFieldValue(track, field.toLowerCase());
    final lowerValue = value.toLowerCase();

    if (fieldValue == null) return false;

    // For both quoted (exact phrase) and unquoted (single word),
    // a 'contains' check is typically more user-friendly for search.
    // The distinction of isExactPhrase is more about *how the value was tokenized*
    // (as a single unit vs. potentially multiple terms to be ANDed).
    return fieldValue.toLowerCase().contains(lowerValue);
  }

  // In lib/utils/track_filtering.dart, inside FieldConditionNode
  String? _getFieldValue(Track track, String fieldName) {
    switch (fieldName) {
      case 'title':
        return track.title;
      case 'artist':
        return track.artist;
      case 'album':
        return track.album;
      case 'comment':
        return track.comment;
      case 'tag':
      case 'tags':
        return track.generalTags.join(' ').toLowerCase();
      case 'path':
        return track.path;
      case 'rating': // <<< ADD THIS CASE
        return track.rating.toString();
      default:
        return null;
    }
  }
}

class GlobalTermNode implements QueryNode {
  final String term;
  // Could add a flag for exact phrase if global quoted terms are desired
  // final bool isExactPhrase;
  // GlobalTermNode(this.term, {this.isExactPhrase = false});

  GlobalTermNode(this.term);

  @override
  bool evaluate(Track track) {
    final lowerTerm = term.toLowerCase();
    // if (isExactPhrase) { // Logic for exact global phrase
    //   return track.title.toLowerCase() == lowerTerm ||
    //          track.artist.toLowerCase() == lowerTerm ||
    //          // ... and so on for other fields
    //          track.generalTags.any((tag) => tag.toLowerCase() == lowerTerm);
    // } else { // Contains logic
    return track.title.toLowerCase().contains(lowerTerm) ||
        track.artist.toLowerCase().contains(lowerTerm) ||
        track.album.toLowerCase().contains(lowerTerm) ||
        track.comment.toLowerCase().contains(lowerTerm) ||
        track.generalTags.any((tag) => tag.toLowerCase().contains(lowerTerm)) ||
        track.path.toLowerCase().contains(lowerTerm);
    // }
  }
}

class LogicalOperationNode implements QueryNode {
  final LogicalOperator operator;
  final QueryNode left;
  final QueryNode right;

  LogicalOperationNode(this.operator, this.left, this.right);

  @override
  bool evaluate(Track track) {
    switch (operator) {
      case LogicalOperator.AND:
        return left.evaluate(track) && right.evaluate(track);
      case LogicalOperator.OR:
        return left.evaluate(track) || right.evaluate(track);
    }
  }
}

class NotNode implements QueryNode {
  final QueryNode child;

  NotNode(this.child);

  @override
  bool evaluate(Track track) {
    return !child.evaluate(track);
  }
}

QueryNode? parseSearchQuery(String query) {
  query = query.trim();
  if (query.isEmpty) {
    return null;
  }

  try {
    List<Token> rawTokens = tokenize(query);
    // Filter out UNKNOWN tokens that are purely whitespace or effectively empty.
    // Keep UNKNOWN tokens with actual text content for potential global search fallback.
    List<Token> tokens =
        rawTokens
            .where(
              (t) => !(t.type == TokenType.UNKNOWN && t.text.trim().isEmpty),
            )
            .toList();

    if (tokens.isEmpty ||
        (tokens.first.type == TokenType.EOF &&
            tokens.length == 1 &&
            tokens.first.text.trim().isEmpty)) {
      // If only whitespace or truly unknown characters led to this, and original query had content
      if (query.isNotEmpty &&
          rawTokens.any(
            (t) => t.type == TokenType.UNKNOWN && t.text.trim().isNotEmpty,
          )) {
        print(
          "Parser: Query seems to contain only unparseable (unknown) tokens. Global search for: '$query'",
        );
        return GlobalTermNode(query);
      }
      return null;
    }

    // Ensure EOF is the last significant token if not already present or if list is empty after filtering.
    if (tokens.isEmpty || tokens.last.type != TokenType.EOF) {
      tokens.add(
        Token(TokenType.EOF, "", query.length),
      ); // Ensure EOF for parser termination
    }

    TokenStream tokenStream = TokenStream(tokens);
    QueryNode ast = _parseOrExpression(tokenStream);

    // Check for unconsumed tokens that are not just EOF.
    // This can happen if there's valid prefix but then garbage data, or a trailing operator
    // that wasn't fully handled by the lenient parsing (though the changes below aim to handle trailing operators).
    if (!tokenStream.isAtEnd() && tokenStream.peek().type != TokenType.EOF) {
      final remainingToken = tokenStream.peek();
      // If the remaining token is an operator, it means it was a trailing one we might have intentionally ignored.
      // If it's something else, it's more like a syntax error after a valid prefix.
      if (remainingToken.type != TokenType.AND &&
          remainingToken.type != TokenType.OR &&
          remainingToken.type != TokenType.NOT) {
        print(
          "Parser warning: Trailing unconsumed tokens detected starting with: ${remainingToken}. Query: '$query'. Using parsed prefix AST.",
        );
        // Potentially, if there's significant unparsed non-operator text, one might choose to invalidate the AST
        // and fall back to global search of the whole query. For now, we use the parsed prefix.
      } else {
        print(
          "Parser: Trailing operator ${remainingToken.type} was likely handled by lenient parsing. Using parsed prefix AST.",
        );
      }
    }
    return ast;
  } catch (e) {
    print(
      "Critical error during query parsing for '$query': $e. Falling back to global search of the entire query.",
    );
    return GlobalTermNode(
      query,
    ); // Fallback for critical, unexpected parsing errors
  }
}

QueryNode _parseOrExpression(TokenStream tokens) {
  QueryNode left = _parseAndExpression(tokens);

  while (tokens.peek().type == TokenType.OR) {
    Token operatorToken = tokens.consume(); // Consume OR

    // Check if there's a valid token for the right operand
    final nextToken = tokens.peek();
    if (nextToken.type == TokenType.EOF || !_isStartOfExpression(nextToken)) {
      print(
        "Parser: Trailing OR operator at position ${operatorToken.position}. Using expression parsed so far (LHS: $left).",
      );
      // If query ends after OR or next token can't start an expression,
      // then the OR is incomplete. Return the left operand.
      return left;
    }
    QueryNode right = _parseAndExpression(tokens);
    left = LogicalOperationNode(LogicalOperator.OR, left, right);
  }
  return left;
}

QueryNode _parseAndExpression(TokenStream tokens) {
  QueryNode left = _parseNotExpression(tokens);

  while (true) {
    final peekedToken = tokens.peek();
    if (peekedToken.type == TokenType.AND) {
      Token operatorToken = tokens.consume(); // Consume explicit AND

      final nextToken = tokens.peek();
      if (nextToken.type == TokenType.EOF || !_isStartOfExpression(nextToken)) {
        print(
          "Parser: Trailing AND operator at position ${operatorToken.position}. Using expression parsed so far (LHS: $left).",
        );
        return left; // Incomplete AND, return what was parsed before it.
      }
      QueryNode right = _parseNotExpression(tokens);
      left = LogicalOperationNode(LogicalOperator.AND, left, right);
    } else if (peekedToken.type != TokenType.OR &&
        peekedToken.type != TokenType.RPAREN &&
        peekedToken.type != TokenType.EOF &&
        _isStartOfExpression(peekedToken)) {
      // Implicit AND: No operator token to consume. peekedToken is the start of the right operand.
      QueryNode right = _parseNotExpression(
        tokens,
      ); // This will consume the peekedToken as part of the right expression
      left = LogicalOperationNode(LogicalOperator.AND, left, right);
    } else {
      break; // No more ANDs (explicit or implicit) or other conditions met
    }
  }
  return left;
}

bool _isStartOfExpression(Token token) {
  return token.type == TokenType.WORD ||
      token.type == TokenType.QUOTED_STRING ||
      token.type == TokenType.FIELD_NAME ||
      token.type == TokenType.LPAREN ||
      token.type == TokenType.NOT;
}

QueryNode _parseNotExpression(TokenStream tokens) {
  if (tokens.peek().type == TokenType.NOT) {
    Token operatorToken = tokens.consume(); // Consume NOT

    final nextToken = tokens.peek();
    if (nextToken.type == TokenType.EOF || !_isStartOfExpression(nextToken)) {
      // Check if NOT is dangling
      print(
        "Parser: Trailing NOT operator at position ${operatorToken.position}. Treating as syntax error / ignoring for now by returning a node that evaluates to true or handle error.",
      );
      // A lone "NOT" doesn't make sense. How to handle?
      // Option 1: Throw error (current behavior via _parseAtom if nextToken is EOF)
      // Option 2: Return a special "always true" node (effectively ignoring the dangling NOT)
      // Option 3: Modify parser to consume this dangling NOT and not form a NotNode (complex)
      // For now, _parseAtom will throw if nextToken is EOF after NOT, which is caught by top-level parseSearchQuery.
      // If nextToken is another operator, _parseAtom will also throw.
      // This seems acceptable; a dangling NOT is a clear syntax error.
      // The existing _parseAtom will likely throw "Unexpected end of query after NOT" or "Unexpected token..."
    }
    QueryNode child = _parseAtom(tokens);
    return NotNode(child);
  }
  return _parseAtom(tokens);
}

QueryNode _parseAtom(TokenStream tokens) {
  final currentToken = tokens.peek();

  if (currentToken.type == TokenType.LPAREN) {
    tokens.consume(); // Consume (
    QueryNode node = _parseOrExpression(
      tokens,
    ); // Recurse, starting from OR for precedence within ()
    if (tokens.peek().type != TokenType.RPAREN) {
      throw Exception(
        "Mismatched parentheses: Expected ')' but found ${tokens.peek()} at position ${tokens.peek().position} (following '${currentToken.text}' at ${currentToken.position})",
      );
    }
    tokens.consume(); // Consume )
    return node;
  } else if (currentToken.type == TokenType.FIELD_NAME) {
    final fieldToken =
        tokens.consume(); // Consumes the field name (e.g., "comment")
    if (tokens.peek().type != TokenType.COLON) {
      throw Exception(
        "Expected ':' after field name '${fieldToken.text}' at ${fieldToken.position} but found ${tokens.peek()}",
      );
    }
    tokens.consume(); // Consume COLON (":")

    final valueToken = tokens.peek(); // Look at the token for the value

    if (valueToken.type == TokenType.QUOTED_STRING) {
      // <<<< KEY PART HERE
      tokens
          .consume(); // Consumes the entire quoted string (e.g., "test comment")
      // Creates a FieldConditionNode with isExactPhrase: true
      return FieldConditionNode(
        fieldToken.text, // e.g., "comment"
        valueToken.text, // e.g., "test comment"
        isExactPhrase: true,
      );
    } else if (valueToken.type == TokenType.WORD) {
      tokens.consume(); // Consumes a single unquoted word
      return FieldConditionNode(fieldToken.text, valueToken.text);
    } else {
      throw Exception(
        "Expected value (word or quoted string) after '${fieldToken.text}:' but found ${valueToken} at ${valueToken.position}",
      );
    }
  } else if (currentToken.type == TokenType.WORD ||
      currentToken.type == TokenType.QUOTED_STRING) {
    tokens.consume();
    return GlobalTermNode(currentToken.text);
  } else if (currentToken.type == TokenType.EOF) {
    // This can happen if an operator was expecting an operand but query ended.
    // Example: "term1 AND" - after AND is consumed, next call to _parseAtom sees EOF.
    throw Exception(
      "Unexpected end of query at position ${currentToken.position}. Expected an expression atom (e.g., a word, field, or parenthesized expression).",
    );
  }

  throw Exception(
    "Unexpected token during parsing atom: ${currentToken}. Cannot start an atom here.",
  );
}

List<Track> applyFilters({
  required List<Track> allTracks,
  required String searchQuery,
  required int? minRating,
  Set<String>? playlistTrackPaths,
}) {
  List<Track> filtered = allTracks;

  // 1. Playlist Filter
  if (playlistTrackPaths != null && playlistTrackPaths.isNotEmpty) {
    // Added isNotEmpty check
    print(
      "Applying playlist filter: ${playlistTrackPaths.length} tracks in playlist set",
    );
    final Set<String> normalizedPlaylistPaths =
        playlistTrackPaths.map(pathLib.normalize).toSet().cast<String>();
    filtered =
        filtered.where((track) {
          try {
            final normalizedTrackPath = pathLib.normalize(track.path);
            return normalizedPlaylistPaths.contains(normalizedTrackPath);
          } catch (e) {
            print(
              "Warning: Could not normalize track path '${track.path}': $e",
            );
            return false;
          }
        }).toList();
    print("Playlist filter result count: ${filtered.length}");
  }

  // 2. Advanced Text Query Filter
  if (searchQuery.trim().isNotEmpty) {
    print(
      "Attempting to parse and apply advanced search query: '$searchQuery'",
    );
    QueryNode? queryAst = parseSearchQuery(searchQuery);

    if (queryAst != null) {
      try {
        filtered =
            filtered.where((track) {
              try {
                return queryAst.evaluate(track);
              } catch (evalError) {
                print(
                  "Error evaluating node for track ${track.id}: $evalError",
                );
                return false; // If a specific node evaluation fails, treat as non-match for that track
              }
            }).toList();
        print("Advanced text query filter result count: ${filtered.length}");
      } catch (e) {
        // This catch is more for unexpected issues during the .where() or list creation
        print("Error applying AST filter: $e. For query: '$searchQuery'.");
      }
    } else {
      // queryAst is null, meaning parsing likely failed to produce a usable tree or query was effectively empty for AST.
      print(
        "Advanced parsing yielded no AST or query was empty for AST logic for: '$searchQuery'. Falling back to simple global search if query is not empty.",
      );
      // Fallback to simple global search if the original query was not empty but AST is null
      final trimmedQuery = searchQuery.trim();
      if (trimmedQuery.isNotEmpty) {
        final lowerCaseQuery = trimmedQuery.toLowerCase();
        filtered =
            filtered.where((track) {
              return track.title.toLowerCase().contains(lowerCaseQuery) ||
                  track.artist.toLowerCase().contains(lowerCaseQuery) ||
                  track.album.toLowerCase().contains(lowerCaseQuery) ||
                  track.comment.toLowerCase().contains(lowerCaseQuery) ||
                  track.generalTags.any(
                    (tag) => tag.toLowerCase().contains(lowerCaseQuery),
                  ) ||
                  track.path.toLowerCase().contains(lowerCaseQuery);
            }).toList();
        print("Fallback global search result count: ${filtered.length}");
      }
    }
  }

  // 3. Rating Filter
  if (minRating != null && minRating > 0) {
    print("Applying rating filter: >= $minRating");
    filtered = filtered.where((track) => track.rating >= minRating).toList();
    print("Rating filter result count: ${filtered.length}");
  }

  print("Filtering complete. Final count: ${filtered.length}");
  return filtered;
}
