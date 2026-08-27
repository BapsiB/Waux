/// Defines the columns that can be specifically filtered in the track table.
enum FilterableColumn {
  title,
  artist,
  album,
  genre,
  year,
  rating,
  tags,
  // Add other filterable columns as needed (e.g., duration, bpm)
  none, // Represents no specific column filter
}

// You could potentially add more complex filter models here later,
// e.g., for range filters (like year ranges) or specific rating filters.
// class RatingFilter {
//   final int minRating;
//   final int maxRating;
//   RatingFilter(this.minRating, this.maxRating);
// }
