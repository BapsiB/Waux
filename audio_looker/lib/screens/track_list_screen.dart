// lib/screens/track_list_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as pathLib; // For pathLib.basename

// Import BLoCs and Models
import '../blocs/track_management/track_data_bloc.dart';
import '../services/collection_service.dart'; // For Track and MovedFileUpdate models

// Top-level function for showing the dialog
void _showFileChangesDialog(
  BuildContext dialogContext, // Important: this context is for the dialog
  List<String> newFilePaths,
  List<Track> deletedTracks,
  List<MovedFileUpdate> movedFileUpdates,
) {
  // --- PASTE THE ENTIRE _showFileChangesDialog method content here ---
  // Make sure to use 'dialogContext' where 'context' was used inside the original method for BlocProvider.of, Theme.of, etc.
  // And 'dialogContext' for showDialog's context parameter.

  Map<String, bool> newFilesSelection = {
    for (var path in newFilePaths) path: true,
  };
  Map<int, bool> deletedTracksSelection = {
    for (var track in deletedTracks) track.id!: true,
  };

  bool? selectAllNewFiles =
      newFilePaths.isNotEmpty
          ? (newFilesSelection.values.every((v) => v)
              ? true
              : (newFilesSelection.values.any((v) => v) ? null : false))
          : false;
  bool? selectAllDeletedTracks =
      deletedTracks.isNotEmpty
          ? (deletedTracksSelection.values.every((v) => v)
              ? true
              : (deletedTracksSelection.values.any((v) => v) ? null : false))
          : false;

  showDialog(
    context: dialogContext, // Use the context passed to this function
    barrierDismissible: false,
    builder: (alertDialogContext) {
      // Renamed inner context to avoid confusion
      return StatefulBuilder(
        builder: (stfContext, stfSetState) {
          if (newFilePaths.isNotEmpty) {
            final allNewSelected = newFilesSelection.values.every((v) => v);
            final noNewSelected = newFilesSelection.values.every((v) => !v);
            selectAllNewFiles =
                allNewSelected ? true : (noNewSelected ? false : null);
          } else {
            selectAllNewFiles = false;
          }

          if (deletedTracks.isNotEmpty) {
            final allDeletedSelected = deletedTracksSelection.values.every(
              (v) => v,
            );
            final noDeletedSelected = deletedTracksSelection.values.every(
              (v) => !v,
            );
            selectAllDeletedTracks =
                allDeletedSelected ? true : (noDeletedSelected ? false : null);
          } else {
            selectAllDeletedTracks = false;
          }

          final theme = Theme.of(
            alertDialogContext,
          ); // Use alertDialogContext for Theme

          final MaterialStateProperty<Color?> selectAllFillColor =
              MaterialStateProperty.resolveWith<Color?>((
                Set<MaterialState> states,
              ) {
                if (states.contains(MaterialState.selected)) {
                  return theme.colorScheme.primary.withOpacity(0.8);
                }
                return null;
              });

          return AlertDialog(
            title: const Text('File System Changes Detected'),
            content: SizedBox(
              width:
                  MediaQuery.of(alertDialogContext).size.width *
                  0.6, // Use alertDialogContext
              height:
                  MediaQuery.of(alertDialogContext).size.height *
                  0.7, // Use alertDialogContext
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (movedFileUpdates.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          'Paths Updated (Moved Files):',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.orangeAccent,
                          ),
                        ),
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 150),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: movedFileUpdates.length,
                          itemBuilder: (ctx, index) {
                            final moved = movedFileUpdates[index];
                            return ListTile(
                              dense: true,
                              leading: const Icon(
                                Icons.drive_file_move_rtl_outlined,
                                color: Colors.orangeAccent,
                                size: 20,
                              ),
                              title: Text(
                                moved.trackTitle,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              subtitle: Text(
                                "New location: ${pathLib.basename(moved.newPath)}\n(Old: ${pathLib.basename(moved.oldPath)})",
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          },
                        ),
                      ),
                      const Divider(height: 24, thickness: 1),
                    ],
                    if (newFilePaths.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          'New Files Found:',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.green,
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer
                              .withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        margin: const EdgeInsets.symmetric(vertical: 4.0),
                        child: CheckboxListTile(
                          title: Text(
                            "Add all new files",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            "${newFilePaths.length} file(s) will be added to the collection.",
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.textTheme.bodySmall?.color,
                            ),
                          ),
                          value: selectAllNewFiles,
                          tristate: true,
                          onChanged: (bool? newValue) {
                            stfSetState(() {
                              bool checkAll = selectAllNewFiles != true;
                              selectAllNewFiles = checkAll;
                              for (var key in newFilesSelection.keys) {
                                newFilesSelection[key] = checkAll;
                              }
                            });
                          },
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: false,
                          fillColor: selectAllFillColor,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8.0,
                            vertical: 4.0,
                          ),
                        ),
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 150),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: newFilePaths.length,
                          itemBuilder: (ctx, index) {
                            final path = newFilePaths[index];
                            return CheckboxListTile(
                              title: Tooltip(
                                message: path,
                                child: Text(
                                  pathLib.basename(path),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              value: newFilesSelection[path] ?? false,
                              onChanged: (bool? newValue) {
                                stfSetState(() {
                                  newFilesSelection[path] = newValue ?? false;
                                });
                              },
                              controlAffinity: ListTileControlAffinity.leading,
                              dense: true,
                            );
                          },
                        ),
                      ),
                      const Divider(height: 24, thickness: 1),
                    ],
                    if (deletedTracks.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          'Missing Files:',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.redAccent,
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer.withOpacity(
                            0.15,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        margin: const EdgeInsets.symmetric(vertical: 4.0),
                        child: CheckboxListTile(
                          title: Text(
                            "Remove all missing files",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            "${deletedTracks.length} track(s) will be removed from the collection.",
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.textTheme.bodySmall?.color,
                            ),
                          ),
                          value: selectAllDeletedTracks,
                          tristate: true,
                          onChanged: (bool? newValue) {
                            stfSetState(() {
                              bool checkAll = selectAllDeletedTracks != true;
                              selectAllDeletedTracks = checkAll;
                              for (var key in deletedTracksSelection.keys) {
                                deletedTracksSelection[key] = checkAll;
                              }
                            });
                          },
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: false,
                          fillColor: selectAllFillColor,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8.0,
                            vertical: 4.0,
                          ),
                        ),
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 150),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: deletedTracks.length,
                          itemBuilder: (ctx, index) {
                            final track = deletedTracks[index];
                            return CheckboxListTile(
                              title: Tooltip(
                                message: "Last known path: ${track.path}",
                                child: Text(
                                  "${track.title} (${pathLib.basename(track.path)})",
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              value: deletedTracksSelection[track.id] ?? false,
                              onChanged: (bool? newValue) {
                                stfSetState(() {
                                  deletedTracksSelection[track.id!] =
                                      newValue ?? false;
                                });
                              },
                              controlAffinity: ListTileControlAffinity.leading,
                              dense: true,
                            );
                          },
                        ),
                      ),
                    ],
                    if (newFilePaths.isEmpty &&
                        deletedTracks.isEmpty &&
                        movedFileUpdates.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                            "No file changes requiring action were detected.\nYour collection appears up-to-date based on the last scan.",
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Skip All & Refresh'),
                onPressed: () {
                  Navigator.of(alertDialogContext).pop();
                  // Use the dialogContext passed to the top-level function to read the BLoC
                  dialogContext.read<TrackDataBloc>().add(SkipAllFileChanges());
                },
              ),
              ElevatedButton(
                child: const Text('Apply Changes'),
                onPressed:
                    (newFilePaths.isEmpty &&
                            deletedTracks.isEmpty &&
                            movedFileUpdates.isEmpty)
                        ? null
                        : () {
                          final List<String> confirmedAdds =
                              newFilesSelection.entries
                                  .where((e) => e.value)
                                  .map((e) => e.key)
                                  .toList();
                          final List<int> confirmedDeletes =
                              deletedTracksSelection.entries
                                  .where((e) => e.value)
                                  .map((e) => e.key)
                                  .toList();

                          Navigator.of(alertDialogContext).pop();
                          // Use the dialogContext passed to the top-level function to read the BLoC
                          dialogContext.read<TrackDataBloc>().add(
                            ProcessFileChanges(
                              filesToAdd: confirmedAdds,
                              trackIdsToDelete: confirmedDeletes,
                              movedFilesToUpdate: movedFileUpdates,
                            ),
                          );
                        },
              ),
            ],
          );
        },
      );
    },
  );
}

class TrackListScreen extends StatelessWidget {
  const TrackListScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Use BlocConsumer to listen for states and build UI
    return BlocConsumer<TrackDataBloc, TrackDataState>(
      listener: (context, state) {
        // Listen for the FilesystemChangesDetected state
        if (state is FilesystemChangesDetected && state.hasChanges) {
          // Call the dialog function, passing the necessary data and context
          _showFileChangesDialog(
            context, // This context is from the BlocConsumer/TrackListScreen
            state.newFilePaths,
            state.deletedTracks,
            state.movedFileUpdates,
          );
        }
        // You can add other listeners here if TrackListScreen needs to react to other states
      },
      builder: (context, state) {
        if (state is TrackDataInitial) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is TrackDataLoading) {
          // Show tracks from previous state if available, else loading
          final tracksToShow = state.previousTracks ?? [];
          if (tracksToShow.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          // If you want to show the list while loading new data:
          // return _buildTrackList(context, tracksToShow, isLoading: true);
          return _buildTrackList(
            context,
            tracksToShow,
          ); // Or just simple loading
        }
        if (state is TrackDataError) {
          return Center(child: Text('Error: ${state.message}'));
        }
        if (state is TrackDataLoaded) {
          return _buildTrackList(context, state.tracks);
        }
        if (state is TrackDataProcessingNeeded) {
          // Show tracks while processing waveform in background
          return _buildTrackList(context, state.tracks);
        }
        if (state is TrackDataDeletingFolder) {
          final tracksToShow = state.previousTracks ?? [];
          // Show tracks while deleting folder in background
          return _buildTrackList(context, tracksToShow);
        }
        if (state is FilesystemChangesDetected) {
          // Show the current UI state's tracks while the dialog is potentially active
          return _buildTrackList(context, state.currentTracksInUI);
        }

        // Fallback for any other unhandled state
        return const Center(child: Text('Waiting for track data...'));
      },
    );
  }

  // Placeholder _buildTrackList method as per your instruction
  Widget _buildTrackList(
    BuildContext context,
    List<Track> tracks, {
    bool isLoading = false,
  }) {
    if (tracks.isEmpty && !isLoading) {
      return const Center(child: Text('No tracks to display.'));
    }
    // Replace this with your actual TrackTableWidget or ListView.builder
    // For now, a simple ListView showing titles:
    return ListView.builder(
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        return ListTile(
          title: Text(track.title),
          subtitle: Text(track.artist),
          // Add more details or use your TrackListItem widget
        );
      },
    );
  }
}
