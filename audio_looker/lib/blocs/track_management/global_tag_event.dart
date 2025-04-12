// lib/blocs/global_tag/global_tag_event.dart

part of 'global_tag_bloc.dart';

abstract class GlobalTagEvent extends Equatable {
  const GlobalTagEvent();

  @override
  List<Object?> get props => [];
}

/// Event to load all globally defined tags.
class LoadGlobalTags extends GlobalTagEvent {}

/// Event to add a new global tag definition.
class AddGlobalTag extends GlobalTagEvent {
  final Tag tag;
  const AddGlobalTag(this.tag);
  @override
  List<Object?> get props => [tag];
}

/// Event to remove a global tag definition by its name.
class RemoveGlobalTag extends GlobalTagEvent {
  final String tagName;
  const RemoveGlobalTag(this.tagName);
  @override
  List<Object?> get props => [tagName];
}

/// Event to update the color of a global tag definition.
class UpdateGlobalTagColor extends GlobalTagEvent {
  final String tagName;
  final int? colorValue; // Store color as int (nullable to clear color)
  const UpdateGlobalTagColor(this.tagName, this.colorValue);
  @override
  List<Object?> get props => [tagName, colorValue];
}
