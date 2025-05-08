import '../services/collection_service.dart';
import 'package:path/path.dart' as pathLib;

List<Track> applyFilters({
  required List<Track> allTracks,
  required String searchQuery,
  required int? minRating,
  Set<String>? playlistTrackPaths, // <<< Keep this
}) {
  List<Track> filtered = allTracks;

  // --- Playlist Filter (Apply FIRST) ---
  if (playlistTrackPaths != null) {
    print(
      "Applying playlist filter: ${playlistTrackPaths.length} tracks in playlist set",
    );
    // Normalize paths in the playlist set ONCE for efficiency
    // *** FIX: Explicitly cast the result of toSet() to Set<String> ***
    final Set<String> normalizedPlaylistPaths =
        playlistTrackPaths.map(pathLib.normalize).toSet().cast<String>();
    filtered =
        filtered.where((track) {
          // Normalize the track's path for comparison
          // Handle potential errors during normalization (e.g., invalid characters)
          try {
            final normalizedTrackPath = pathLib.normalize(track.path);
            return normalizedPlaylistPaths.contains(normalizedTrackPath);
          } catch (e) {
            print(
              "Warning: Could not normalize track path '${track.path}': $e",
            );
            return false; // Exclude tracks with paths that cannot be normalized
          }
        }).toList();
    print("Playlist filter result count: ${filtered.length}");
  }
  // --- END Playlist Filter ---

  // --- Field-Specific Filtering Logic ---
  final fieldFilterRegex = RegExp(r'^(\w+):(.+)$'); // Matches "field:value"
  final match = fieldFilterRegex.firstMatch(searchQuery);
  bool fieldFilterApplied = false;

  if (match != null) {
    final field = match.group(1)?.toLowerCase();
    // Handle potential quotes around the value
    String? value = match.group(2)?.trim();
    if (value != null &&
        value.startsWith('"') &&
        value.endsWith('"') &&
        value.length >= 2) {
      value = value.substring(1, value.length - 1); // Remove quotes
    }
    value = value?.toLowerCase(); // Lowercase after removing quotes

    if (field != null && value != null && value.isNotEmpty) {
      print(
        "Applying field filter: Field='$field', Value='$value'",
      ); // Log field filter
      filtered =
          filtered.where((track) {
            switch (field) {
              case 'title':
                return track.title.toLowerCase().contains(value!);
              case 'artist':
                return track.artist.toLowerCase().contains(value!);
              case 'album':
                return track.album.toLowerCase().contains(value!);
              case 'comment':
                return track.comment.toLowerCase().contains(value!);
              case 'tag':
              case 'tags':
                return track.generalTags.any(
                  (tag) => tag.toLowerCase().contains(value!),
                );
              case 'path':
                return track.path.toLowerCase().contains(value!);
              // Add other filterable fields here if needed
              default:
                return false; // Unknown field
            }
          }).toList();
      fieldFilterApplied = true;
      print("Field filter result count: ${filtered.length}");
    }
  }
  // --- END: Field-Specific Filtering Logic ---

  // --- Apply Global Search ONLY if field filter was NOT applied ---
  if (!fieldFilterApplied && searchQuery.isNotEmpty) {
    final lowerCaseQuery = searchQuery.toLowerCase();
    print("Applying global filter: '$lowerCaseQuery'"); // Log global filter
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
    print("Global filter result count: ${filtered.length}");
  }
  // --- End Global Search ---

  // Apply Rating Filter
  if (minRating != null && minRating > 0) {
    print("Applying rating filter: >= $minRating"); // Log rating filter
    filtered = filtered.where((track) => track.rating >= minRating).toList();
    print("Rating filter result count: ${filtered.length}");
  }

  print(
    "Filtering complete. Final count: ${filtered.length}",
  ); // Log final count
  return filtered;
}
