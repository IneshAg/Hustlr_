import 'package:equatable/equatable.dart';
import '../../models/worker_profile.dart';

enum LoadStatus { initial, loading, success, failure }

class UserState extends Equatable {
  final WorkerProfile? user;
  final bool onboardingComplete;

  // INTERNAL ONLY — never bind to UI widgets. The ISS score must not be
  // displayed to users: knowing the formula would allow gaming the system.
  final double issScore;

  final LoadStatus status;
  final String? errorMessage;

  const UserState({
    this.user,
    this.onboardingComplete = false,
    this.issScore = 0.0,
    this.status = LoadStatus.initial,
    this.errorMessage,
  });

  UserState copyWith({
    WorkerProfile? user,
    bool? onboardingComplete,
    double? issScore,
    LoadStatus? status,
    String? errorMessage,
  }) {
    return UserState(
      user: user ?? this.user,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      issScore: issScore ?? this.issScore,
      status: status ?? this.status,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        user,
        onboardingComplete,
        // issScore intentionally EXCLUDED from props to prevent UI rebuilds
        // triggered by ISS changes. Widgets must never observe this field.
        status,
        errorMessage,
      ];
}
