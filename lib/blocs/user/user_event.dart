import 'package:equatable/equatable.dart';
import '../../models/worker_profile.dart';

abstract class UserEvent extends Equatable {
  const UserEvent();

  @override
  List<Object?> get props => [];
}

/// Fetch a worker profile by ID. Dispatched after OTP login succeeds.
class LoadUser extends UserEvent {
  final String userId;
  const LoadUser(this.userId);

  @override
  List<Object?> get props => [userId];
}

/// Apply in-memory updates to the user profile (e.g. zone change).
class UpdateUser extends UserEvent {
  final WorkerProfile updated;
  const UpdateUser(this.updated);

  @override
  List<Object?> get props => [updated];
}

/// Mark onboarding as complete and persist the flag.
class CompleteOnboarding extends UserEvent {
  const CompleteOnboarding();
}

/// Trigger a backend ISS recalculation. Result is stored internally only —
/// it must never be exposed to UI widgets.
class RefreshISS extends UserEvent {
  final String userId;
  const RefreshISS(this.userId);

  @override
  List<Object?> get props => [userId];
}
