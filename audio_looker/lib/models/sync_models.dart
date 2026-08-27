// lib/models/sync_models.dart

import 'dart:convert';
import '../services/audio_service.dart'; // For TimeMarker

/// Represents a single change operation that needs to be synchronized
class ChangeRecord {
  final String changeId; // UUID for unique identification
  final String userId; // User who made the change
  final DateTime timestamp; // When change was made
  final String operation; // 'insert', 'update', 'delete'
  final String entityType; // 'track', 'playlist', 'ui_settings'
  final String? entityId; // Track ID, playlist ID, etc.
  final Map<String, dynamic>?
  beforeData; // Previous state (for updates/deletes)
  final Map<String, dynamic>? afterData; // New state (for inserts/updates)
  final String deviceId; // Device that made the change
  final List<String> dependencies; // IDs of changes this depends on
  final String checksum; // SHA256 hash for integrity
  final bool createdLocally; // True if created on this device

  ChangeRecord({
    required this.changeId,
    required this.userId,
    required this.timestamp,
    required this.operation,
    required this.entityType,
    this.entityId,
    this.beforeData,
    this.afterData,
    required this.deviceId,
    this.dependencies = const [],
    required this.checksum,
    this.createdLocally = true,
  });

  factory ChangeRecord.fromJson(Map<String, dynamic> json) {
    return ChangeRecord(
      changeId: json['changeId'],
      userId: json['userId'],
      timestamp: DateTime.parse(json['timestamp']),
      operation: json['operation'],
      entityType: json['entityType'],
      entityId: json['entityId'],
      beforeData: json['beforeData'],
      afterData: json['afterData'],
      deviceId: json['deviceId'],
      dependencies: List<String>.from(json['dependencies'] ?? []),
      checksum: json['checksum'],
      createdLocally: json['createdLocally'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'changeId': changeId,
      'userId': userId,
      'timestamp': timestamp.toIso8601String(),
      'operation': operation,
      'entityType': entityType,
      'entityId': entityId,
      'beforeData': beforeData,
      'afterData': afterData,
      'deviceId': deviceId,
      'dependencies': dependencies,
      'checksum': checksum,
      'createdLocally': createdLocally,
    };
  }

  /// Generate checksum for the change data
  static String generateChecksum(Map<String, dynamic> data) {
    final jsonString = jsonEncode(data);
    // In a real implementation, you'd use crypto package for SHA256
    return jsonString.hashCode.toString();
  }

  /// Create a new change record with generated checksum
  static ChangeRecord create({
    required String changeId,
    required String userId,
    required String operation,
    required String entityType,
    String? entityId,
    Map<String, dynamic>? beforeData,
    Map<String, dynamic>? afterData,
    required String deviceId,
    List<String> dependencies = const [],
    bool createdLocally = true,
  }) {
    final timestamp = DateTime.now();
    final data = {
      'changeId': changeId,
      'userId': userId,
      'timestamp': timestamp.toIso8601String(),
      'operation': operation,
      'entityType': entityType,
      'entityId': entityId,
      'beforeData': beforeData,
      'afterData': afterData,
      'deviceId': deviceId,
      'dependencies': dependencies,
    };

    return ChangeRecord(
      changeId: changeId,
      userId: userId,
      timestamp: timestamp,
      operation: operation,
      entityType: entityType,
      entityId: entityId,
      beforeData: beforeData,
      afterData: afterData,
      deviceId: deviceId,
      dependencies: dependencies,
      checksum: generateChecksum(data),
      createdLocally: createdLocally,
    );
  }
}

/// Tracks the synchronization state for a collection
class SyncState {
  final String collectionId;
  final String? lastPulledChangeId;
  final DateTime? lastPullTimestamp;
  final DateTime? lastPushTimestamp;
  final List<String> pendingChangeIds;
  final int conflictCount;

  SyncState({
    required this.collectionId,
    this.lastPulledChangeId,
    this.lastPullTimestamp,
    this.lastPushTimestamp,
    this.pendingChangeIds = const [],
    this.conflictCount = 0,
  });

  factory SyncState.fromJson(Map<String, dynamic> json) {
    return SyncState(
      collectionId: json['collectionId'],
      lastPulledChangeId: json['lastPulledChangeId'],
      lastPullTimestamp:
          json['lastPullTimestamp'] != null
              ? DateTime.parse(json['lastPullTimestamp'])
              : null,
      lastPushTimestamp:
          json['lastPushTimestamp'] != null
              ? DateTime.parse(json['lastPushTimestamp'])
              : null,
      pendingChangeIds: List<String>.from(json['pendingChangeIds'] ?? []),
      conflictCount: json['conflictCount'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'collectionId': collectionId,
      'lastPulledChangeId': lastPulledChangeId,
      'lastPullTimestamp': lastPullTimestamp?.toIso8601String(),
      'lastPushTimestamp': lastPushTimestamp?.toIso8601String(),
      'pendingChangeIds': pendingChangeIds,
      'conflictCount': conflictCount,
    };
  }

  SyncState copyWith({
    String? collectionId,
    String? lastPulledChangeId,
    DateTime? lastPullTimestamp,
    DateTime? lastPushTimestamp,
    List<String>? pendingChangeIds,
    int? conflictCount,
  }) {
    return SyncState(
      collectionId: collectionId ?? this.collectionId,
      lastPulledChangeId: lastPulledChangeId ?? this.lastPulledChangeId,
      lastPullTimestamp: lastPullTimestamp ?? this.lastPullTimestamp,
      lastPushTimestamp: lastPushTimestamp ?? this.lastPushTimestamp,
      pendingChangeIds: pendingChangeIds ?? this.pendingChangeIds,
      conflictCount: conflictCount ?? this.conflictCount,
    );
  }
}

/// Represents a conflict that needs resolution
class ConflictRecord {
  final String conflictId;
  final String changeIdLocal;
  final String changeIdRemote;
  final String entityType;
  final String? entityId;
  final Map<String, dynamic>? localData;
  final Map<String, dynamic>? remoteData;
  final DateTime timestamp;
  final bool resolved;
  final ConflictResolutionStrategy? resolutionStrategy;

  ConflictRecord({
    required this.conflictId,
    required this.changeIdLocal,
    required this.changeIdRemote,
    required this.entityType,
    this.entityId,
    this.localData,
    this.remoteData,
    required this.timestamp,
    this.resolved = false,
    this.resolutionStrategy,
  });

  factory ConflictRecord.fromJson(Map<String, dynamic> json) {
    return ConflictRecord(
      conflictId: json['conflictId'],
      changeIdLocal: json['changeIdLocal'],
      changeIdRemote: json['changeIdRemote'],
      entityType: json['entityType'],
      entityId: json['entityId'],
      localData: json['localData'],
      remoteData: json['remoteData'],
      timestamp: DateTime.parse(json['timestamp']),
      resolved: json['resolved'] ?? false,
      resolutionStrategy:
          json['resolutionStrategy'] != null
              ? ConflictResolutionStrategy.values.firstWhere(
                (e) => e.name == json['resolutionStrategy'],
              )
              : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'conflictId': conflictId,
      'changeIdLocal': changeIdLocal,
      'changeIdRemote': changeIdRemote,
      'entityType': entityType,
      'entityId': entityId,
      'localData': localData,
      'remoteData': remoteData,
      'timestamp': timestamp.toIso8601String(),
      'resolved': resolved,
      'resolutionStrategy': resolutionStrategy?.name,
    };
  }
}

/// Strategy for resolving conflicts
enum ConflictResolutionStrategy {
  lastWriteWins, // Use timestamp to determine winner
  manualResolve, // Present to user for decision
  mergeFields, // Attempt automatic field-level merge
  keepBoth, // Create duplicate entries where possible
  keepLocal, // Always prefer local changes
  keepRemote, // Always prefer remote changes
}

/// Sync operation types
enum SyncOperation { insert, update, delete }

/// Entity types that can be synchronized
enum SyncEntityType { track, playlist, playlistTrack, uiSettings, localRoot }

/// Sync status
enum SyncStatus { idle, pulling, pushing, syncing, conflict, error }
