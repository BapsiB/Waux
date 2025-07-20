// lib/widgets/sync_status_widget.dart

import 'package:flutter/material.dart';
import '../models/sync_models.dart';
import '../services/collection_service.dart';
import '../services/sync_service.dart';

class SyncStatusWidget extends StatefulWidget {
  final CollectionService collectionService;

  const SyncStatusWidget({Key? key, required this.collectionService})
    : super(key: key);

  @override
  State<SyncStatusWidget> createState() => _SyncStatusWidgetState();
}

class _SyncStatusWidgetState extends State<SyncStatusWidget> {
  SyncService? _syncService;
  SyncStatus _currentStatus = SyncStatus.idle;
  int _pendingChanges = 0;

  @override
  void initState() {
    super.initState();
    _initializeSyncService();
  }

  void _initializeSyncService() {
    final collection = widget.collectionService.getActiveCollection();
    if (collection?.type == CollectionType.shared) {
      _syncService = widget.collectionService.getSyncService();
      if (_syncService != null) {
        // Listen to sync status changes
        _syncService!.syncStatusStream.listen((status) {
          if (mounted) {
            setState(() {
              _currentStatus = status;
            });
          }
        });

        // Listen to pending changes count
        _syncService!.pendingChangesCountStream.listen((count) {
          if (mounted) {
            setState(() {
              _pendingChanges = count;
            });
          }
        });

        // Get initial values
        _currentStatus = _syncService!.currentStatus;
        _syncService!.getPendingChangesCount().then((count) {
          if (mounted) {
            setState(() {
              _pendingChanges = count;
            });
          }
        });
      }
    }
  }

  @override
  void didUpdateWidget(SyncStatusWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collectionService != widget.collectionService) {
      _initializeSyncService();
    }
  }

  Color _getStatusColor() {
    switch (_currentStatus) {
      case SyncStatus.idle:
        return Colors.green;
      case SyncStatus.pulling:
      case SyncStatus.pushing:
      case SyncStatus.syncing:
        return Colors.blue;
      case SyncStatus.conflict:
        return Colors.orange;
      case SyncStatus.error:
        return Colors.red;
    }
  }

  IconData _getStatusIcon() {
    switch (_currentStatus) {
      case SyncStatus.idle:
        return Icons.cloud_done;
      case SyncStatus.pulling:
        return Icons.cloud_download;
      case SyncStatus.pushing:
        return Icons.cloud_upload;
      case SyncStatus.syncing:
        return Icons.sync;
      case SyncStatus.conflict:
        return Icons.warning;
      case SyncStatus.error:
        return Icons.error;
    }
  }

  String _getStatusText() {
    switch (_currentStatus) {
      case SyncStatus.idle:
        return _pendingChanges > 0 ? 'Ready to sync' : 'Up to date';
      case SyncStatus.pulling:
        return 'Pulling changes...';
      case SyncStatus.pushing:
        return 'Pushing changes...';
      case SyncStatus.syncing:
        return 'Syncing...';
      case SyncStatus.conflict:
        return 'Conflicts detected';
      case SyncStatus.error:
        return 'Sync error';
    }
  }

  Future<void> _performSync() async {
    if (_syncService != null && _currentStatus == SyncStatus.idle) {
      try {
        await _syncService!.performFullSync();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sync completed successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sync failed: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final collection = widget.collectionService.getActiveCollection();

    // Only show for shared collections
    if (collection?.type != CollectionType.shared || _syncService == null) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            // Status icon
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              child: Icon(_getStatusIcon(), color: _getStatusColor(), size: 24),
            ),

            const SizedBox(width: 12),

            // Status text and pending changes
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _getStatusText(),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (_pendingChanges > 0)
                    Text(
                      '$_pendingChanges pending changes',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.orange),
                    ),
                ],
              ),
            ),

            // Sync button
            if (_currentStatus == SyncStatus.idle && _pendingChanges > 0)
              ElevatedButton.icon(
                onPressed: _performSync,
                icon: const Icon(Icons.sync, size: 18),
                label: const Text('Sync'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              )
            else if (_currentStatus != SyncStatus.idle)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }
}
