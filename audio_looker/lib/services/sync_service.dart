// lib/services/sync_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as pathLib;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/sync_models.dart';
import 'collection_service.dart';

/// Service responsible for synchronizing shared collections
class SyncService {
  static const String _syncDirName = '.sync';
  static const String _changesDirName = 'changes';
  static const String _locksDirName = 'locks';
  static const String _metadataDirName = 'metadata';
  static const String _syncLockFileName = 'sync.lock';

  // Database table names for sync
  static const String _tablePendingChanges = 'pending_changes';
  static const String _tableSyncState = 'sync_state';
  static const String _tableSyncConflicts = 'sync_conflicts';

  final CollectionService _collectionService;
  final String _userId;
  final String _deviceId;
  final _uuid = const Uuid();

  // Streams for status updates
  final _syncStatusController = StreamController<SyncStatus>.broadcast();
  final _conflictController =
      StreamController<List<ConflictRecord>>.broadcast();
  final _pendingChangesController = StreamController<int>.broadcast();

  Stream<SyncStatus> get syncStatusStream => _syncStatusController.stream;
  Stream<List<ConflictRecord>> get conflictStream => _conflictController.stream;
  Stream<int> get pendingChangesCountStream => _pendingChangesController.stream;

  SyncStatus _currentStatus = SyncStatus.idle;
  Timer? _pullTimer;

  SyncService(this._collectionService, this._userId, this._deviceId);

  /// Initialize the sync service for the current collection
  Future<void> initialize() async {
    final collection = _collectionService.getActiveCollection();
    if (collection?.type != CollectionType.shared) {
      throw Exception('SyncService can only be used with shared collections');
    }

    await _ensureSyncDirectoryStructure();
    await _ensureSyncTables();
    await _startAutoPull();

    print('SyncService initialized for collection: ${collection!.name}');
  }

  /// Dispose resources
  Future<void> dispose() async {
    _pullTimer?.cancel();
    await _syncStatusController.close();
    await _conflictController.close();
    await _pendingChangesController.close();
  }

  /// Get current sync status
  SyncStatus get currentStatus => _currentStatus;

  /// Set sync status and notify listeners
  void _setStatus(SyncStatus status) {
    if (_currentStatus != status) {
      _currentStatus = status;
      _syncStatusController.add(status);
      print('SyncService: Status changed to ${status.name}');
    }
  }

  /// Ensure the sync directory structure exists in the shared collection
  Future<void> _ensureSyncDirectoryStructure() async {
    final collection = _collectionService.getActiveCollection()!;
    final syncDir = Directory(pathLib.join(collection.rootPath!, _syncDirName));
    final changesDir = Directory(pathLib.join(syncDir.path, _changesDirName));
    final locksDir = Directory(pathLib.join(syncDir.path, _locksDirName));
    final metadataDir = Directory(pathLib.join(syncDir.path, _metadataDirName));

    for (final dir in [syncDir, changesDir, locksDir, metadataDir]) {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        print('Created sync directory: ${dir.path}');
      }
    }
  }

  /// Ensure sync tables exist in the local database
  Future<void> _ensureSyncTables() async {
    final db = _collectionService.getActiveDatabase();
    if (db == null) throw Exception('No active database');

    // Pending changes table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tablePendingChanges (
        change_id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        operation TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT,
        before_data TEXT,
        after_data TEXT,
        device_id TEXT NOT NULL,
        dependencies TEXT,
        checksum TEXT NOT NULL,
        created_locally INTEGER DEFAULT 1
      )
    ''');

    // Sync state table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableSyncState (
        collection_id TEXT PRIMARY KEY,
        last_pulled_change_id TEXT,
        last_pull_timestamp INTEGER,
        last_push_timestamp INTEGER,
        pending_change_count INTEGER DEFAULT 0
      )
    ''');

    // Sync conflicts table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableSyncConflicts (
        conflict_id TEXT PRIMARY KEY,
        change_id_local TEXT NOT NULL,
        change_id_remote TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT,
        local_data TEXT,
        remote_data TEXT,
        timestamp INTEGER NOT NULL,
        resolved INTEGER DEFAULT 0,
        resolution_strategy TEXT
      )
    ''');

    print('SyncService: Sync tables created/verified');
  }

  /// Record a change for synchronization
  Future<void> recordChange({
    required String operation,
    required String entityType,
    String? entityId,
    Map<String, dynamic>? beforeData,
    Map<String, dynamic>? afterData,
    List<String> dependencies = const [],
  }) async {
    final db = _collectionService.getActiveDatabase();
    if (db == null) throw Exception('No active database');

    final changeRecord = ChangeRecord.create(
      changeId: _uuid.v4(),
      userId: _userId,
      operation: operation,
      entityType: entityType,
      entityId: entityId,
      beforeData: beforeData,
      afterData: afterData,
      deviceId: _deviceId,
      dependencies: dependencies,
    );

    // Store in local pending changes
    await db.insert(_tablePendingChanges, {
      'change_id': changeRecord.changeId,
      'user_id': changeRecord.userId,
      'timestamp': changeRecord.timestamp.millisecondsSinceEpoch,
      'operation': changeRecord.operation,
      'entity_type': changeRecord.entityType,
      'entity_id': changeRecord.entityId,
      'before_data':
          changeRecord.beforeData != null
              ? jsonEncode(changeRecord.beforeData)
              : null,
      'after_data':
          changeRecord.afterData != null
              ? jsonEncode(changeRecord.afterData)
              : null,
      'device_id': changeRecord.deviceId,
      'dependencies': jsonEncode(changeRecord.dependencies),
      'checksum': changeRecord.checksum,
      'created_locally': 1,
    });

    // Write change file to shared directory
    await _writeChangeFile(changeRecord);

    // Update pending changes count
    await _updatePendingChangesCount();

    print(
      'SyncService: Recorded change ${changeRecord.changeId} (${changeRecord.operation} ${changeRecord.entityType})',
    );
  }

  /// Write a change file to the shared directory
  Future<void> _writeChangeFile(ChangeRecord change) async {
    final collection = _collectionService.getActiveCollection()!;
    final changesDir = pathLib.join(
      collection.rootPath!,
      _syncDirName,
      _changesDirName,
    );
    final fileName =
        '${change.userId}_${change.deviceId}_${change.changeId}.json';
    final file = File(pathLib.join(changesDir, fileName));

    await file.writeAsString(jsonEncode(change.toJson()));
    print('SyncService: Wrote change file: $fileName');
  }

  /// Start automatic pulling of remote changes
  Future<void> _startAutoPull() async {
    // Pull every 5 seconds for demo - in production this would be configurable
    _pullTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_currentStatus == SyncStatus.idle) {
        _pullRemoteChanges();
      }
    });
  }

  /// Pull remote changes from shared directory
  Future<void> _pullRemoteChanges() async {
    if (_currentStatus != SyncStatus.idle) return;

    _setStatus(SyncStatus.pulling);

    try {
      final collection = _collectionService.getActiveCollection()!;
      final changesDir = Directory(
        pathLib.join(collection.rootPath!, _syncDirName, _changesDirName),
      );

      if (!await changesDir.exists()) {
        _setStatus(SyncStatus.idle);
        return;
      }

      final changeFiles =
          await changesDir
              .list()
              .where(
                (entity) => entity is File && entity.path.endsWith('.json'),
              )
              .cast<File>()
              .toList();

      final lastPulledId = await _getLastPulledChangeId();
      final newChanges = <ChangeRecord>[];

      for (final file in changeFiles) {
        try {
          final content = await file.readAsString();
          final change = ChangeRecord.fromJson(jsonDecode(content));

          // Skip if we've already processed this change
          if (lastPulledId != null &&
              change.timestamp.isBefore(
                await _getLastPullTimestamp() ?? DateTime(0),
              )) {
            continue;
          }

          // Skip changes created by this device
          if (change.deviceId == _deviceId) continue;

          newChanges.add(change);
        } catch (e) {
          print('SyncService: Error reading change file ${file.path}: $e');
        }
      }

      if (newChanges.isNotEmpty) {
        // Sort by timestamp
        newChanges.sort((a, b) => a.timestamp.compareTo(b.timestamp));

        for (final change in newChanges) {
          await _applyRemoteChange(change);
        }

        // Update last pulled info
        if (newChanges.isNotEmpty) {
          await _updateLastPulledInfo(newChanges.last.changeId);
        }

        print('SyncService: Applied ${newChanges.length} remote changes');
      }

      _setStatus(SyncStatus.idle);
    } catch (e) {
      print('SyncService: Error during pull: $e');
      _setStatus(SyncStatus.error);
    }
  }

  /// Apply a remote change to the local database
  Future<void> _applyRemoteChange(ChangeRecord change) async {
    final db = _collectionService.getActiveDatabase()!;

    try {
      switch (change.entityType) {
        case 'track':
          await _applyTrackChange(change);
          break;
        case 'playlist':
          await _applyPlaylistChange(change);
          break;
        case 'ui_settings':
          await _applyUiSettingsChange(change);
          break;
        default:
          print('SyncService: Unknown entity type: ${change.entityType}');
      }

      // Record that we've processed this change
      await db.insert(_tablePendingChanges, {
        'change_id': change.changeId,
        'user_id': change.userId,
        'timestamp': change.timestamp.millisecondsSinceEpoch,
        'operation': change.operation,
        'entity_type': change.entityType,
        'entity_id': change.entityId,
        'before_data':
            change.beforeData != null ? jsonEncode(change.beforeData) : null,
        'after_data':
            change.afterData != null ? jsonEncode(change.afterData) : null,
        'device_id': change.deviceId,
        'dependencies': jsonEncode(change.dependencies),
        'checksum': change.checksum,
        'created_locally': 0,
      });
    } catch (e) {
      print('SyncService: Error applying change ${change.changeId}: $e');
      // TODO: Handle conflicts here
    }
  }

  /// Apply track changes
  Future<void> _applyTrackChange(ChangeRecord change) async {
    final db = _collectionService.getActiveDatabase()!;

    switch (change.operation) {
      case 'insert':
        if (change.afterData != null) {
          await db.insert('music', change.afterData!);
        }
        break;
      case 'update':
        if (change.afterData != null && change.entityId != null) {
          await db.update(
            'music',
            change.afterData!,
            where: 'id = ?',
            whereArgs: [int.parse(change.entityId!)],
          );
        }
        break;
      case 'delete':
        if (change.entityId != null) {
          await db.delete(
            'music',
            where: 'id = ?',
            whereArgs: [int.parse(change.entityId!)],
          );
        }
        break;
    }
  }

  /// Apply playlist changes
  Future<void> _applyPlaylistChange(ChangeRecord change) async {
    final db = _collectionService.getActiveDatabase()!;

    switch (change.operation) {
      case 'insert':
        if (change.afterData != null) {
          await db.insert('playlists', change.afterData!);
        }
        break;
      case 'update':
        if (change.afterData != null && change.entityId != null) {
          await db.update(
            'playlists',
            change.afterData!,
            where: 'id = ?',
            whereArgs: [change.entityId],
          );
        }
        break;
      case 'delete':
        if (change.entityId != null) {
          await db.delete(
            'playlists',
            where: 'id = ?',
            whereArgs: [change.entityId],
          );
        }
        break;
    }
  }

  /// Apply UI settings changes
  Future<void> _applyUiSettingsChange(ChangeRecord change) async {
    final db = _collectionService.getActiveDatabase()!;

    switch (change.operation) {
      case 'insert':
      case 'update':
        if (change.afterData != null) {
          await db.insert(
            'ui_settings',
            change.afterData!,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        break;
      case 'delete':
        if (change.entityId != null) {
          await db.delete(
            'ui_settings',
            where: 'key = ?',
            whereArgs: [change.entityId],
          );
        }
        break;
    }
  }

  /// Get the last pulled change ID
  Future<String?> _getLastPulledChangeId() async {
    final db = _collectionService.getActiveDatabase()!;
    final collection = _collectionService.getActiveCollection()!;

    final result = await db.query(
      _tableSyncState,
      where: 'collection_id = ?',
      whereArgs: [collection.id],
      limit: 1,
    );

    return result.isNotEmpty
        ? result.first['last_pulled_change_id'] as String?
        : null;
  }

  /// Get the last pull timestamp
  Future<DateTime?> _getLastPullTimestamp() async {
    final db = _collectionService.getActiveDatabase()!;
    final collection = _collectionService.getActiveCollection()!;

    final result = await db.query(
      _tableSyncState,
      where: 'collection_id = ?',
      whereArgs: [collection.id],
      limit: 1,
    );

    if (result.isNotEmpty && result.first['last_pull_timestamp'] != null) {
      return DateTime.fromMillisecondsSinceEpoch(
        result.first['last_pull_timestamp'] as int,
      );
    }
    return null;
  }

  /// Update last pulled change info
  Future<void> _updateLastPulledInfo(String changeId) async {
    final db = _collectionService.getActiveDatabase()!;
    final collection = _collectionService.getActiveCollection()!;

    await db.insert(_tableSyncState, {
      'collection_id': collection.id,
      'last_pulled_change_id': changeId,
      'last_pull_timestamp': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Update pending changes count and notify listeners
  Future<void> _updatePendingChangesCount() async {
    final db = _collectionService.getActiveDatabase()!;

    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $_tablePendingChanges WHERE created_locally = 1',
    );

    final count = result.first['count'] as int;
    _pendingChangesController.add(count);
  }

  /// Get count of pending local changes
  Future<int> getPendingChangesCount() async {
    final db = _collectionService.getActiveDatabase()!;

    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $_tablePendingChanges WHERE created_locally = 1',
    );

    return result.first['count'] as int;
  }

  /// Manual sync trigger - pushes all pending changes to shared database
  Future<void> performFullSync() async {
    if (_currentStatus != SyncStatus.idle) {
      throw Exception('Sync already in progress');
    }

    _setStatus(SyncStatus.syncing);

    try {
      // First pull any new remote changes
      await _pullRemoteChanges();

      // Then push our changes
      await _pushLocalChanges();

      _setStatus(SyncStatus.idle);
      print('SyncService: Full sync completed successfully');
    } catch (e) {
      print('SyncService: Error during full sync: $e');
      _setStatus(SyncStatus.error);
      rethrow;
    }
  }

  /// Push local changes to shared database
  Future<void> _pushLocalChanges() async {
    final db = _collectionService.getActiveDatabase()!;
    final collection = _collectionService.getActiveCollection()!;

    // Get all pending local changes
    final pendingChanges = await db.query(
      _tablePendingChanges,
      where: 'created_locally = 1',
      orderBy: 'timestamp ASC',
    );

    if (pendingChanges.isEmpty) {
      print('SyncService: No pending changes to push');
      return;
    }

    _setStatus(SyncStatus.pushing);

    // Acquire sync lock
    final lockAcquired = await _acquireSyncLock();
    if (!lockAcquired) {
      throw Exception('Could not acquire sync lock');
    }

    try {
      final sharedDbPath = pathLib.join(collection.rootPath!, 'collection.db');
      final sharedDb = await openDatabase(sharedDbPath);

      // Apply all pending changes to shared database
      for (final changeMap in pendingChanges) {
        final change = ChangeRecord.fromJson({
          'changeId': changeMap['change_id'],
          'userId': changeMap['user_id'],
          'timestamp':
              DateTime.fromMillisecondsSinceEpoch(
                changeMap['timestamp'] as int,
              ).toIso8601String(),
          'operation': changeMap['operation'],
          'entityType': changeMap['entity_type'],
          'entityId': changeMap['entity_id'],
          'beforeData':
              changeMap['before_data'] != null
                  ? jsonDecode(changeMap['before_data'] as String)
                  : null,
          'afterData':
              changeMap['after_data'] != null
                  ? jsonDecode(changeMap['after_data'] as String)
                  : null,
          'deviceId': changeMap['device_id'],
          'dependencies': jsonDecode(changeMap['dependencies'] as String),
          'checksum': changeMap['checksum'],
          'createdLocally': (changeMap['created_locally'] as int) == 1,
        });

        await _applyChangeToSharedDb(sharedDb, change);
      }

      await sharedDb.close();

      // Clear pending changes
      await db.delete(_tablePendingChanges, where: 'created_locally = 1');

      // Update sync state
      await db.insert(_tableSyncState, {
        'collection_id': collection.id,
        'last_push_timestamp': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await _updatePendingChangesCount();

      print(
        'SyncService: Pushed ${pendingChanges.length} changes to shared database',
      );
    } finally {
      await _releaseSyncLock();
    }
  }

  /// Apply a change to the shared database
  Future<void> _applyChangeToSharedDb(
    Database sharedDb,
    ChangeRecord change,
  ) async {
    switch (change.entityType) {
      case 'track':
        await _applyTrackChangeToSharedDb(sharedDb, change);
        break;
      case 'playlist':
        await _applyPlaylistChangeToSharedDb(sharedDb, change);
        break;
      case 'ui_settings':
        await _applyUiSettingsChangeToSharedDb(sharedDb, change);
        break;
    }
  }

  /// Apply track change to shared database
  Future<void> _applyTrackChangeToSharedDb(
    Database sharedDb,
    ChangeRecord change,
  ) async {
    switch (change.operation) {
      case 'insert':
        if (change.afterData != null) {
          await sharedDb.insert('music', change.afterData!);
        }
        break;
      case 'update':
        if (change.afterData != null && change.entityId != null) {
          await sharedDb.update(
            'music',
            change.afterData!,
            where: 'id = ?',
            whereArgs: [int.parse(change.entityId!)],
          );
        }
        break;
      case 'delete':
        if (change.entityId != null) {
          await sharedDb.delete(
            'music',
            where: 'id = ?',
            whereArgs: [int.parse(change.entityId!)],
          );
        }
        break;
    }
  }

  /// Apply playlist change to shared database
  Future<void> _applyPlaylistChangeToSharedDb(
    Database sharedDb,
    ChangeRecord change,
  ) async {
    switch (change.operation) {
      case 'insert':
        if (change.afterData != null) {
          await sharedDb.insert('playlists', change.afterData!);
        }
        break;
      case 'update':
        if (change.afterData != null && change.entityId != null) {
          await sharedDb.update(
            'playlists',
            change.afterData!,
            where: 'id = ?',
            whereArgs: [change.entityId],
          );
        }
        break;
      case 'delete':
        if (change.entityId != null) {
          await sharedDb.delete(
            'playlists',
            where: 'id = ?',
            whereArgs: [change.entityId],
          );
        }
        break;
    }
  }

  /// Apply UI settings change to shared database
  Future<void> _applyUiSettingsChangeToSharedDb(
    Database sharedDb,
    ChangeRecord change,
  ) async {
    switch (change.operation) {
      case 'insert':
      case 'update':
        if (change.afterData != null) {
          await sharedDb.insert(
            'ui_settings',
            change.afterData!,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        break;
      case 'delete':
        if (change.entityId != null) {
          await sharedDb.delete(
            'ui_settings',
            where: 'key = ?',
            whereArgs: [change.entityId],
          );
        }
        break;
    }
  }

  /// Acquire sync lock
  Future<bool> _acquireSyncLock() async {
    final collection = _collectionService.getActiveCollection()!;
    final lockFile = File(
      pathLib.join(
        collection.rootPath!,
        _syncDirName,
        _locksDirName,
        _syncLockFileName,
      ),
    );

    // Check if lock already exists
    if (await lockFile.exists()) {
      final content = await lockFile.readAsString();
      final lockData = jsonDecode(content);
      final lockTime = DateTime.parse(lockData['timestamp']);

      // If lock is older than 5 minutes, consider it stale and remove it
      if (DateTime.now().difference(lockTime).inMinutes > 5) {
        await lockFile.delete();
        print('SyncService: Removed stale sync lock');
      } else {
        print(
          'SyncService: Sync lock held by ${lockData['userId']} since $lockTime',
        );
        return false;
      }
    }

    // Create lock
    final lockData = {
      'userId': _userId,
      'deviceId': _deviceId,
      'timestamp': DateTime.now().toIso8601String(),
    };

    await lockFile.writeAsString(jsonEncode(lockData));
    print('SyncService: Acquired sync lock');
    return true;
  }

  /// Release sync lock
  Future<void> _releaseSyncLock() async {
    final collection = _collectionService.getActiveCollection()!;
    final lockFile = File(
      pathLib.join(
        collection.rootPath!,
        _syncDirName,
        _locksDirName,
        _syncLockFileName,
      ),
    );

    if (await lockFile.exists()) {
      await lockFile.delete();
      print('SyncService: Released sync lock');
    }
  }
}
