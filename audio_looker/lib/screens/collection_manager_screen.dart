import 'dart:io'; // Already likely there
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as pathLib; // Already likely there
import 'package:url_launcher/url_launcher.dart'; // <<< Add this

// Import BLoC and Service/Models needed
import '../blocs/collection_management/collection_management_bloc.dart';
import '../services/collection_service.dart';

class CollectionManagerScreen extends StatefulWidget {
  const CollectionManagerScreen({super.key});

  @override
  State<CollectionManagerScreen> createState() =>
      _CollectionManagerScreenState();
}

class _CollectionManagerScreenState extends State<CollectionManagerScreen> {
  Offset _tapPosition = Offset.zero; // Store tap position

  void _storePosition(TapDownDetails details) {
    _tapPosition = details.globalPosition;
  }

  @override
  void initState() {
    super.initState();
    // Request the list of collections when the screen loads
    context.read<CollectionManagementBloc>().add(LoadCollectionList());
  }

  void _showCollectionContextMenu(
    BuildContext context,
    CollectionDefinition collection,
  ) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        _tapPosition & const Size(40, 40), // Small rectangle at tap pos
        Offset.zero & overlay.size, // Bigger rectangle of the overlay
      ),
      items: <PopupMenuEntry>[
        PopupMenuItem(
          value: 'reveal_db', // Unique value for this action
          child: const ListTile(
            leading: Icon(Icons.folder_open),
            title: Text('Reveal in Finder'),
          ),
        ),
        // Add other options like Rename later if needed
        // const PopupMenuDivider(),
        // PopupMenuItem( ... ),
      ],
    ).then((value) {
      // Handle menu selection
      if (value != null) {
        _handleCollectionMenuSelection(value, collection);
      }
    });
  }

  // Method to perform the reveal action
  Future<void> _revealDbLocation(CollectionDefinition collection) async {
    try {
      final String dbPath = collection.dbPath;
      // Ensure the path is absolute before getting the directory
      if (!pathLib.isAbsolute(dbPath)) {
        print("Error revealing location: DB path is not absolute: $dbPath");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Cannot reveal relative path: $dbPath")),
        );
        return;
      }

      final String directoryPath = pathLib.dirname(dbPath);
      final Uri directoryUri = Uri.file(directoryPath);

      if (await canLaunchUrl(directoryUri)) {
        await launchUrl(directoryUri);
      } else {
        throw Exception('Could not launch directory URI: $directoryUri');
      }
    } catch (e) {
      print("Error revealing DB location: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Could not open folder: $e")));
    }
  }

  // Method to handle menu selection
  void _handleCollectionMenuSelection(
    dynamic value,
    CollectionDefinition collection,
  ) {
    if (value == 'reveal_db') {
      _revealDbLocation(collection);
    }
    // Handle other potential menu values here
  }

  // --- Dialog for Creating New Collection ---
  // In lib/screens/collection_manager_screen.dart

  // --- Dialog for Creating New Collection ---
  // In lib/screens/collection_manager_screen.dart

  // --- Dialog for Creating New Collection ---
  // In lib/screens/collection_manager_screen.dart

  // --- Dialog for Creating New Collection ---
  void _showCreateCollectionDialog({required bool isShared}) {
    final TextEditingController nameController = TextEditingController();
    // --- *** ADD FocusNode *** ---
    final FocusNode nameFocusNode = FocusNode();
    // --- *** END ADD *** ---
    String? selectedFolderPath;
    String? detectedDbPath;
    String? suggestedName;
    bool dbDetected = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (stfContext, stfSetState) {
            return AlertDialog(
              title: Text(
                isShared ? 'New Shared Collection' : 'New Local Collection',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      // --- *** ADD focusNode property *** ---
                      focusNode: nameFocusNode,
                      // --- *** END ADD *** ---
                      enabled: !dbDetected,
                      // --- MODIFIED: Autofocus local immediately, shared after folder select ---
                      autofocus: !isShared,
                      // --- END MODIFIED ---
                      decoration: InputDecoration(
                        labelText: 'Collection Name',
                        hintText:
                            dbDetected
                                ? '(From existing database)'
                                : 'Enter a name',
                      ),
                    ),
                    if (isShared) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      Text(
                        'Select Shared Folder:',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
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
                                fontStyle:
                                    selectedFolderPath == null
                                        ? FontStyle.italic
                                        : FontStyle.normal,
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
                                  selectedFolderPath = directoryPath;
                                  detectedDbPath = null;
                                  suggestedName = null;
                                  dbDetected = false;
                                  nameController.text = '';
                                });

                                List<FileSystemEntity> dbFiles = [];
                                String? foundDbPath;
                                String? extractedName;
                                final directory = Directory(directoryPath);

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
                                                      .startsWith(
                                                        '_collection_',
                                                      ) &&
                                                  pathLib
                                                      .basename(entity.path)
                                                      .endsWith('.db'),
                                            )
                                            .toList();

                                    if (dbFiles.length == 1) {
                                      foundDbPath = dbFiles.first.path;
                                      String baseName = pathLib
                                          .basenameWithoutExtension(
                                            foundDbPath,
                                          );
                                      if (baseName.startsWith('_collection_')) {
                                        extractedName = baseName
                                            .substring('_collection_'.length)
                                            .replaceAll('_', ' ');
                                      } else {
                                        extractedName = baseName.replaceAll(
                                          '_',
                                          ' ',
                                        );
                                      }
                                      print(
                                        "Detected DB: $foundDbPath, Extracted Name: $extractedName",
                                      );
                                    } else if (dbFiles.length > 1) {
                                      print(
                                        "Multiple collection DB files found in $directoryPath",
                                      );
                                      if (stfContext.mounted) {
                                        ScaffoldMessenger.of(
                                          stfContext,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Multiple collection databases found. Please ensure only one exists.',
                                            ),
                                          ),
                                        );
                                      }
                                      selectedFolderPath = null;
                                    } else {
                                      print(
                                        "No collection DB file found in $directoryPath",
                                      );
                                    }
                                  }
                                } catch (e) {
                                  print(
                                    "Error scanning directory for DB file: $e",
                                  );
                                  if (stfContext.mounted) {
                                    ScaffoldMessenger.of(
                                      stfContext,
                                    ).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Error scanning folder: $e',
                                        ),
                                      ),
                                    );
                                  }
                                  selectedFolderPath = null;
                                }

                                stfSetState(() {
                                  if (foundDbPath != null &&
                                      extractedName != null) {
                                    detectedDbPath = foundDbPath;
                                    suggestedName = extractedName;
                                    dbDetected = true;
                                    nameController.text = suggestedName!;
                                  } else {
                                    detectedDbPath = null;
                                    suggestedName = null;
                                    dbDetected = false;
                                    nameController.clear();
                                    // --- *** FIX: Request focus using FocusNode *** ---
                                    if (foundDbPath == null &&
                                        dbFiles.length <= 1) {
                                      // Use WidgetsBinding to request focus after the current frame
                                      WidgetsBinding.instance.addPostFrameCallback((
                                        _,
                                      ) {
                                        if (stfContext.mounted) {
                                          // Check mount status again in callback
                                          FocusScope.of(
                                            stfContext,
                                          ).requestFocus(nameFocusNode);
                                        }
                                      });
                                    }
                                  }
                                });
                              }
                            },
                          ),
                        ],
                      ),
                      if (dbDetected)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            'Existing database detected. Name is set automatically.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
                TextButton(
                  child: Text(dbDetected ? 'Add Existing' : 'Create'),
                  onPressed: () {
                    final name = nameController.text.trim();

                    if (isShared && selectedFolderPath == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please select a shared folder.'),
                        ),
                      );
                      return;
                    }
                    if (!dbDetected && name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Collection Name cannot be empty.'),
                        ),
                      );
                      return;
                    }

                    if (isShared) {
                      if (dbDetected) {
                        context.read<CollectionManagementBloc>().add(
                          AddExistingSharedCollection(
                            name: name,
                            rootPath: selectedFolderPath!,
                            dbPath: detectedDbPath!,
                          ),
                        );
                        print("Dispatching AddExistingSharedCollection");
                      } else {
                        context.read<CollectionManagementBloc>().add(
                          CreateSharedCollection(
                            name: name,
                            rootPath: selectedFolderPath!,
                          ),
                        );
                        print("Dispatching CreateSharedCollection");
                      }
                    } else {
                      context.read<CollectionManagementBloc>().add(
                        CreateLocalCollection(name),
                      );
                      print("Dispatching CreateLocalCollection");
                    }
                    Navigator.of(dialogContext).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      // --- *** ADD Dispose FocusNode *** ---
      nameFocusNode.dispose();
      // --- *** END ADD *** ---
      nameController.dispose();
    });
  }
  // // --- >>> NEW: Logic for Adding Existing Shared Collection <<< ---
  // Future<void> _addExistingSharedCollection() async {
  //   // 1. Prompt user to select the ROOT FOLDER
  //   String? selectedFolderPath = await FilePicker.platform.getDirectoryPath(
  //     dialogTitle: 'Select Existing Shared Collection Folder',
  //   );

  //   if (selectedFolderPath == null) {
  //     return; // User cancelled
  //   }

  //   // 2. Detect the database file within the selected folder
  //   String? detectedDbPath;
  //   String? suggestedName;
  //   final directory = Directory(selectedFolderPath);
  //   List<FileSystemEntity> dbFiles = [];

  //   try {
  //     if (await directory.exists()) {
  //       dbFiles =
  //           await directory
  //               .list()
  //               .where(
  //                 (entity) =>
  //                     entity is File &&
  //                     pathLib
  //                         .basename(entity.path)
  //                         .startsWith('_collection_') &&
  //                     pathLib.basename(entity.path).endsWith('.db'),
  //               )
  //               .toList();
  //     }
  //   } catch (e) {
  //     print("Error scanning directory for DB file: $e");
  //     if (!mounted) return; // Check mount status after async gap
  //     ScaffoldMessenger.of(
  //       context,
  //     ).showSnackBar(SnackBar(content: Text('Error scanning folder: $e')));
  //     return;
  //   }

  //   if (dbFiles.length == 1) {
  //     detectedDbPath = dbFiles.first.path;
  //     // Extract suggested name from filename: _collection_MyName.db -> MyName
  //     String baseName = pathLib.basenameWithoutExtension(
  //       detectedDbPath,
  //     ); // _collection_MyName
  //     if (baseName.startsWith('_collection_')) {
  //       suggestedName = baseName
  //           .substring('_collection_'.length)
  //           .replaceAll('_', ' ');
  //     } else {
  //       suggestedName = baseName.replaceAll(
  //         '_',
  //         ' ',
  //       ); // Fallback if prefix missing
  //     }
  //     print("Detected DB: $detectedDbPath, Suggested Name: $suggestedName");
  //   } else if (dbFiles.isEmpty) {
  //     print("No collection DB file found in $selectedFolderPath");
  //     if (!mounted) return;
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       const SnackBar(
  //         content: Text(
  //           'No collection database (_collection_*.db) found in the selected folder.',
  //         ),
  //       ),
  //     );
  //     return;
  //   } else {
  //     print("Multiple collection DB files found in $selectedFolderPath");
  //     if (!mounted) return;
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       const SnackBar(
  //         content: Text(
  //           'Multiple collection databases found. Please ensure only one exists.',
  //         ),
  //       ),
  //     );
  //     return;
  //   }

  //   // 3. Confirm/Get Name via Dialog
  //   final TextEditingController nameController = TextEditingController(
  //     text: suggestedName ?? '',
  //   );
  //   // Check mount status before showing dialog
  //   if (!mounted) return;
  //   final String? confirmedName = await showDialog<String>(
  //     context: context,
  //     builder:
  //         (dialogContext) => AlertDialog(
  //           title: const Text('Confirm Collection Name'),
  //           content: TextField(
  //             controller: nameController,
  //             autofocus: true,
  //             decoration: const InputDecoration(labelText: 'Collection Name'),
  //           ),
  //           actions: [
  //             TextButton(
  //               onPressed: () => Navigator.pop(dialogContext),
  //               child: const Text('Cancel'),
  //             ),
  //             TextButton(
  //               onPressed: () {
  //                 final name = nameController.text.trim();
  //                 if (name.isNotEmpty) {
  //                   Navigator.pop(dialogContext, name);
  //                 } else {
  //                   ScaffoldMessenger.of(dialogContext).showSnackBar(
  //                     const SnackBar(content: Text('Name cannot be empty.')),
  //                   );
  //                 }
  //               },
  //               child: const Text('Add'),
  //             ),
  //           ],
  //         ),
  //   );

  //   nameController.dispose(); // Dispose controller

  //   // 4. Dispatch Event if name confirmed
  //   if (confirmedName != null && confirmedName.isNotEmpty) {
  //     if (!mounted) return; // Check mount status again
  //     context.read<CollectionManagementBloc>().add(
  //       AddExistingSharedCollection(
  //         name: confirmedName,
  //         rootPath: selectedFolderPath, // The folder user selected
  //         dbPath: detectedDbPath!, // The detected DB file path
  //       ),
  //     );
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(content: Text('Added collection: $confirmedName')),
  //     );
  //   }
  // }

  // --- Dialog for Deleting Collection ---
  void _showDeleteConfirmationDialog(
    BuildContext context,
    CollectionDefinition collection,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        // --- >>> MODIFY DIALOG CONTENT <<< ---
        String deletionNote =
            collection.type == CollectionType.shared
                ? 'Note: This will NOT delete the actual folder or database file on your drive.'
                : 'Note: This WILL delete the associated local database file (${pathLib.basename(collection.dbPath)}). This action cannot be undone.';
        // --- >>> END MODIFICATION <<< ---

        return AlertDialog(
          title: Text('Delete Collection?'),
          content: Text(
            // Use the dynamic deletionNote
            'Are you sure you want to remove the collection "${collection.name}" from the list?\n\n$deletionNote',
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
                context.read<CollectionManagementBloc>().add(
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

  Widget _buildCollectionOptionCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2.0,
      clipBehavior: Clip.antiAlias, // Clip content to card shape
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min, // Take minimum vertical space
            crossAxisAlignment:
                CrossAxisAlignment.center, // Center items horizontally
            children: [
              Icon(
                icon,
                size: 40.0,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
                // Optional: Limit lines if description gets too long
                // maxLines: 3,
                // overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
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
      body: BlocBuilder<CollectionManagementBloc, CollectionManagementState>(
        builder: (context, state) {
          // Handle loading state for the list itself
          // Note: This screen primarily reacts to the 'availableCollections' part of the state.
          // Loading indicators for *switching* collections will be seen on HomeScreen.
          if (state is CollectionManagementInitial &&
              state is! CollectionManagementLoading &&
              state is! CollectionManagementLoaded &&
              state is! CollectionManagementError) {
            // If initial and no list loaded yet, show loading or trigger load again
            context.read<CollectionManagementBloc>().add(LoadCollectionList());
            return const Center(
              child: CircularProgressIndicator(color: Colors.amber),
            );
          }

          // Extract available collections safely from any state
          List<CollectionDefinition> collections = [];
          CollectionDefinition?
          activeCollection; // Get active collection for highlighting

          if (state is CollectionManagementLoaded) {
            collections = state.availableCollections;
            activeCollection = state.activeCollectionDefinition;
          } else if (state is CollectionManagementLoading) {
            collections = state.availableCollections ?? [];
            activeCollection = state.activeCollectionDefinition;
            // Optionally show a loading indicator overlay if desired
          } else if (state is CollectionManagementError) {
            collections = state.availableCollections ?? [];
            activeCollection = state.activeCollectionDefinition;
          }

          if (collections.isEmpty && state is! CollectionManagementLoading) {
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

              return GestureDetector(
                // <<< Wrap with GestureDetector
                onTapDown: _storePosition, // Store position for menu
                onSecondaryTapDown: _storePosition, // Store position for menu
                onSecondaryTap:
                    () => _showCollectionContextMenu(
                      context,
                      collection,
                    ), // Show menu
                child: Card(
                  // Keep the Card and ListTile inside
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
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
                          isActive
                              ? Theme.of(context).colorScheme.primary
                              : null,
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
                          () => _showDeleteConfirmationDialog(
                            context,
                            collection,
                          ),
                    ),
                    onTap: () {
                      if (!isActive) {
                        context.read<CollectionManagementBloc>().add(
                          SwitchCollection(collection.id),
                        );
                      }
                      Navigator.pop(context);
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New Collection',
        // Inside the FloatingActionButton's onPressed in lib/screens/collection_manager_screen.dart
        onPressed: () {
          showModalBottomSheet(
            context: context,
            builder: (sheetContext) {
              return Container(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Create a Collection',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        // --- Option 1: Local Collection ---
                        Expanded(
                          child: _buildCollectionOptionCard(
                            context: sheetContext,
                            icon: Icons.folder_outlined,
                            title: 'New Local Collection',
                            // --- MODIFIED Description ---
                            description:
                                'Private collection stored on this device. Can include tracks from multiple different folders.',
                            // --- END MODIFICATION ---
                            onTap: () {
                              Navigator.pop(sheetContext);
                              _showCreateCollectionDialog(isShared: false);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),

                        // --- Option 2: Shared Collection ---
                        Expanded(
                          child: _buildCollectionOptionCard(
                            context: sheetContext,
                            icon: Icons.folder_shared_outlined,
                            title: 'New Shared Collection',
                            // --- MODIFIED Description ---
                            description:
                                'Stored in one folder, usable across devices (via cloud sync). Cannot link files outside its folder.',
                            // --- END MODIFICATION ---
                            onTap: () {
                              Navigator.pop(sheetContext);
                              _showCreateCollectionDialog(isShared: true);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              );
            },
          );
        }, // End onPressed
        child: const Icon(Icons.add),
      ),
    );
  }
}
