import '../services/collection_service.dart';

List<Track> applyFilters({
  required List<Track> allTracks,
  required String searchQuery,
  required int? minRating,
}) {
  List<Track> filtered = allTracks;

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
              // Add other filterable fields here (e.g., year, genre)
              // case 'year': return track.year?.toString() == value; // Example: Exact match for year
              default:
                return false; // Unknown field, don't match
            }
          }).toList();
      fieldFilterApplied = true;
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
  }
  // --- End Global Search ---

  // Apply Rating Filter (remains the same)
  if (minRating != null && minRating > 0) {
    print("Applying rating filter: >= $minRating"); // Log rating filter
    filtered = filtered.where((track) => track.rating >= minRating).toList();
  }

  print(
    "Filtering complete. Final count: ${filtered.length}",
  ); // Log final count
  return filtered;
}
