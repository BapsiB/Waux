import Foundation

/// Serial access for the collection's single SQLite connection.
///
/// `CollectionService` owns `sqlite3_open` / `sqlite3_close` and the `OpaquePointer`;
/// playlist, track-group, and other code must schedule all work on ``queue`` for that connection.
final class CollectionDatabaseSession {
    let queue: DispatchQueue

    init(queueLabel: String = "com.vaux.collection.database") {
        queue = DispatchQueue(label: queueLabel, qos: .userInitiated)
    }
}
