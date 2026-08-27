// lib/widgets/custom_context_menu.dart

import 'package:flutter/material.dart';

/// Represents a single item in the custom context menu.
class CustomContextMenuItem {
  final IconData? icon;
  final String label;
  final VoidCallback? onTap;
  final bool enabled;
  final Color? color; // Optional color for text/icon

  const CustomContextMenuItem({
    this.icon,
    required this.label,
    this.onTap,
    this.enabled = true,
    this.color,
  });
}

/// A basic custom context menu widget.
class CustomContextMenu extends StatelessWidget {
  final List<CustomContextMenuItem> items;
  final VoidCallback onDismiss; // Callback when an item is tapped

  const CustomContextMenu({
    Key? key,
    required this.items,
    required this.onDismiss,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Use Material for elevation and theme defaults
    return Material(
      elevation: 8.0,
      borderRadius: BorderRadius.circular(8.0),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min, // Take minimum vertical space
          children:
              items.map((item) {
                return InkWell(
                  onTap:
                      item.enabled
                          ? () {
                            onDismiss(); // Dismiss the menu first
                            item.onTap?.call(); // Then call the item's action
                          }
                          : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 12.0,
                    ),
                    child: Row(
                      children: [
                        if (item.icon != null) ...[
                          Icon(
                            item.icon,
                            size: 20,
                            color:
                                item.enabled
                                    ? (item.color ??
                                        Theme.of(
                                          context,
                                        ).iconTheme.color?.withOpacity(0.7))
                                    : Theme.of(context).disabledColor,
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Text(
                            item.label,
                            style: TextStyle(
                              color:
                                  item.enabled
                                      ? (item.color ??
                                          Theme.of(
                                            context,
                                          ).textTheme.bodyLarge?.color)
                                      : Theme.of(context).disabledColor,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
        ),
      ),
    );
  }
}
