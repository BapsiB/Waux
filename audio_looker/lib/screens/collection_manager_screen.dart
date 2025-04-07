import 'dart:io'; // <<< Import needed for Directory/File access
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart'
    as pathLib; // <<< Import needed for path manipulation

// Import BLoC and Service/Models needed
import '../blocs/collection/collection_bloc.dart';
import '../services/collection_service.dart'; // For CollectionDefinition

class CollectionManagerScreen extends StatefulWidget {
  const CollectionManagerScreen({super.key});

  @override
  State<CollectionManagerScreen> createState() =>
      _CollectionManagerScreenState();
}

class _CollectionManagerScreenState extends State<CollectionManagerScreen> {
  @override
  void initState() {
    super.initState();
    // Request the list of collections when the screen loads
    context.read<CollectionBloc>().add(LoadCollectionList());
  }

  // --- Dialog for Creating New Collection ---
  void _showCreateCollectionDialog({required bool isShared}) {
    final TextEditingController nameController = TextEditingController();
    String? selectedFolderPath; // Only used for shared

    showDialog(
      context: context,
      builder: (dialogContext) {
        // Use StatefulWidget for the dialog content if path selection needs state
        return StatefulBuilder(
          builder: (stfContext, stfSetState) {
            return AlertDialog(
              title: Text(
                isShared ? 'New Shared Collection' : 'New Local Collection',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Collection Name',
                      hintText: 'Enter a name',
                    ),
                  ),
                  if (isShared) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            selectedFolderPath ?? 'No folder selected',
                            style: TextStyle(
                              color:
                                  selectedFolderPath == null
                                      ? Colors.grey
                                      : null,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.folder_open),
                          tooltip: 'Select Root Folder',
                          onPressed: () async {
                            final String? directoryPath = await FilePicker
                                .platform
                                .getDirectoryPath(
                                  dialogTitle:
                                      'Select Shared Collection Folder',
                                );
                            if (directoryPath != null) {
                              stfSetState(() {
                                // Use stfSetState to update dialog UI
                                selectedFolderPath = directoryPath;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
                TextButton(
                  child: const Text('Create'),
                  onPressed: () {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Name cannot be empty.')),
                      );
                      return;
                    }
                    if (isShared && selectedFolderPath == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please select a root folder.'),
                        ),
                      );
                      return;
                    }

                    // Dispatch event to BLoC
                    if (isShared) {
                      context.read<CollectionBloc>().add(
                        CreateSharedCollection(
                          name: name,
                          rootPath: selectedFolderPath!,
                        ),
                      );
                    } else {
                      context.read<CollectionBloc>().add(
                        CreateLocalCollection(name),
                      );
                    }
                    Navigator.of(dialogContext).pop(); // Close the dialog
                  },
                ),
              ],
            );
          },
        );
      },
    ).then((_) => nameController.dispose());
  }

  // --- >>> NEW: Logic for Adding Existing Shared Collection <<< ---
  Future<void> _addExistingSharedCollection() async {
    // 1. Prompt user to select the ROOT FOLDER
    String? selectedFolderPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Existing Shared Collection Folder',
    );

    if (selectedFolderPath == null) {
      return; // User cancelled
    }

    // 2. Detect the database file within the selected folder
    String? detectedDbPath;
    String? suggestedName;
    final directory = Directory(selectedFolderPath);
    List<FileSystemEntity> dbFiles = [];

    try {
      if (await directory.exists()) {
        dbFiles =
            await directory
                .list()
                .where(
                  (entity) =>
                      entity is File &&
                      pathLib
                          .basename(entity.path)
                          .startsWith('_collection_') &&
                      pathLib.basename(entity.path).endsWith('.db'),
                )
                .toList();
      }
    } catch (e) {
      print("Error scanning directory for DB file: $e");
      if (!mounted) return; // Check mount status after async gap
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error scanning folder: $e')));
      return;
    }

    if (dbFiles.length == 1) {
      detectedDbPath = dbFiles.first.path;
      // Extract suggested name from filename: _collection_MyName.db -> MyName
      String baseName = pathLib.basenameWithoutExtension(
        detectedDbPath,
      ); // _collection_MyName
      if (baseName.startsWith('_collection_')) {
        suggestedName = baseName
            .substring('_collection_'.length)
            .replaceAll('_', ' ');
      } else {
        suggestedName = baseName.replaceAll(
          '_',
          ' ',
        ); // Fallback if prefix missing
      }
      print("Detected DB: $detectedDbPath, Suggested Name: $suggestedName");
    } else if (dbFiles.isEmpty) {
      print("No collection DB file found in $selectedFolderPath");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No collection database (_collection_*.db) found in the selected folder.',
          ),
        ),
      );
      return;
    } else {
      print("Multiple collection DB files found in $selectedFolderPath");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Multiple collection databases found. Please ensure only one exists.',
          ),
        ),
      );
      return;
    }

    // 3. Confirm/Get Name via Dialog
    final TextEditingController nameController = TextEditingController(
      text: suggestedName ?? '',
    );
    // Check mount status before showing dialog
    if (!mounted) return;
    final String? confirmedName = await showDialog<String>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Confirm Collection Name'),
            content: TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Collection Name'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isNotEmpty) {
                    Navigator.pop(dialogContext, name);
                  } else {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(content: Text('Name cannot be empty.')),
                    );
                  }
                },
                child: const Text('Add'),
              ),
            ],
          ),
    );

    nameController.dispose(); // Dispose controller

    // 4. Dispatch Event if name confirmed
    if (confirmedName != null && confirmedName.isNotEmpty) {
      if (!mounted) return; // Check mount status again
      context.read<CollectionBloc>().add(
        AddExistingSharedCollection(
          name: confirmedName,
          rootPath: selectedFolderPath, // The folder user selected
          dbPath: detectedDbPath!, // The detected DB file path
        ),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added collection: $confirmedName')),
      );
    }
  }

  // --- Dialog for Deleting Collection ---
  void _showDeleteConfirmationDialog(
    BuildContext context,
    CollectionDefinition collection,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Delete Collection?'),
          content: Text(
            'Are you sure you want to remove the collection "${collection.name}" from the list?\n\n'
            '${collection.type == CollectionType.shared ? 'Note: This will NOT delete the actual folder or database file on your drive.' : 'Note: This will NOT delete the local database file.'}',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
              onPressed: () {
                context.read<CollectionBloc>().add(
                  DeleteCollection(collection.id),
                );
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Collections'),
        // Optional: Add button here instead of FAB
        // actions: [
        //   IconButton(
        //     icon: const Icon(Icons.add),
        //     tooltip: 'New Collection',
        //     onPressed: _showAddCollectionMenu, // You would need to implement this menu
        //   ),
        // ],
      ),
      body: BlocBuilder<CollectionBloc, CollectionState>(
        builder: (context, state) {
          // Handle loading state for the list itself
          // Note: This screen primarily reacts to the 'availableCollections' part of the state.
          // Loading indicators for *switching* collections will be seen on HomeScreen.
          if (state is CollectionInitial &&
              state is! CollectionLoading &&
              state is! CollectionLoaded &&
              state is! CollectionError) {
            // If initial and no list loaded yet, show loading or trigger load again
            context.read<CollectionBloc>().add(LoadCollectionList());
            return const Center(child: CircularProgressIndicator());
          }

          // Extract available collections safely from any state
          List<CollectionDefinition> collections = [];
          CollectionDefinition?
          activeCollection; // Get active collection for highlighting

          if (state is CollectionLoaded) {
            collections = state.availableCollections;
            activeCollection = state.activeCollectionDefinition;
          } else if (state is CollectionLoading) {
            collections = state.availableCollections ?? [];
            activeCollection = state.activeCollectionDefinition;
            // Optionally show a loading indicator overlay if desired
          } else if (state is CollectionError) {
            collections = state.availableCollections ?? [];
            activeCollection = state.activeCollectionDefinition;
            // Display error prominently? For now, just show list if available.
            // return Center(child: Text("Error loading collections: ${state.message}"));
          }

          if (collections.isEmpty && state is! CollectionLoading) {
            return const Center(
              child: Text(
                'No collections found.\nTap (+) to create one!',
                textAlign: TextAlign.center,
              ),
            );
          }

          return ListView.builder(
            itemCount: collections.length,
            itemBuilder: (context, index) {
              final collection = collections[index];
              final bool isActive = collection.id == activeCollection?.id;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                elevation: isActive ? 4 : 1,
                shape: RoundedRectangleBorder(
                  side: BorderSide(
                    color:
                        isActive
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListTile(
                  leading: Icon(
                    collection.type == CollectionType.shared
                        ? Icons.folder_shared_outlined
                        : Icons.folder_outlined,
                    color:
                        isActive ? Theme.of(context).colorScheme.primary : null,
                  ),
                  title: Text(
                    collection.name,
                    style: TextStyle(
                      fontWeight:
                          isActive ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(
                    '${collection.type.name} - ${isActive ? "(Active)" : ""}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.redAccent,
                    ),
                    tooltip: 'Delete Collection Definition',
                    onPressed:
                        () =>
                            _showDeleteConfirmationDialog(context, collection),
                  ),
                  onTap: () {
                    // Only switch if it's not already active
                    if (!isActive) {
                      context.read<CollectionBloc>().add(
                        SwitchCollection(collection.id),
                      );
                    }
                    // Navigate back to home screen after selection (or switch attempt)
                    Navigator.pop(context);
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New Collection',
        onPressed: () {
          // Show options to create local or shared
          showModalBottomSheet(
            context: context,
            builder: (sheetContext) {
              return Wrap(
                children: <Widget>[
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: const Text('Create New Local Collection'),
                    onTap: () {
                      Navigator.pop(sheetContext); // Close bottom sheet
                      _showCreateCollectionDialog(isShared: false);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.folder_shared_outlined),
                    title: const Text('Create New Shared Collection'),
                    onTap: () {
                      Navigator.pop(sheetContext); // Close bottom sheet
                      _showCreateCollectionDialog(isShared: true);
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.drive_folder_upload_outlined,
                    ), // Example Icon
                    title: const Text('Add Existing Shared Collection'),
                    onTap: () {
                      Navigator.pop(sheetContext); // Close bottom sheet
                      _addExistingSharedCollection(); // Call the new handler logic
                    },
                  ),
                ],
              );
            },
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
