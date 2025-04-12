// lib/blocs/global_tag/global_tag_state.dart

part of 'global_tag_bloc.dart';

abstract class GlobalTagState extends Equatable {
  const GlobalTagState();

  @override
  List<Object> get props => [];
}

/// Initial state before global tags are loaded.
class GlobalTagInitial extends GlobalTagState {}

/// State indicating global tags are being loaded.
// Optional: Can be added if loading takes significant time.
// class GlobalTagLoading extends GlobalTagState {}

/// State representing successfully loaded global tag definitions.
class GlobalTagLoaded extends GlobalTagState {
  final List<Tag> allTags;
  const GlobalTagLoaded(this.allTags);

  @override
  List<Object> get props => [allTags];
}

/// State indicating an error occurred during global tag operations.
class GlobalTagError extends GlobalTagState {
  final String message;
  const GlobalTagError(this.message);

  @override
  List<Object> get props => [message];
}
