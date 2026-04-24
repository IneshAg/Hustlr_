import 'package:flutter_bloc/flutter_bloc.dart';
import '../../services/api_service.dart';
import '../../services/storage_service.dart';
import '../../services/mock_data_service.dart';
import '../../models/worker_profile.dart';
import 'user_event.dart';
import 'user_state.dart';

class UserBloc extends Bloc<UserEvent, UserState> {
  final ApiService apiService;

  UserBloc({required this.apiService}) : super(const UserState()) {
    on<LoadUser>(_onLoadUser);
    on<UpdateUser>(_onUpdateUser);
    on<CompleteOnboarding>(_onCompleteOnboarding);
    on<RefreshISS>(_onRefreshISS);
  }

  /// Fetch worker profile from backend. Also fetches the ISS score and stores
  /// it internally — it is NEVER exposed to UI via state props.
  Future<void> _onLoadUser(LoadUser event, Emitter<UserState> emit) async {
    emit(state.copyWith(status: LoadStatus.loading));

    try {
      // ── SINGLE POINT OF TRUTH: Check MockDataService for demo users ──
      if (event.userId.startsWith('DEMO_')) {
        final mock = MockDataService.instance;
        final profile = WorkerProfile(
          id: mock.worker.id,
          name: mock.worker.name,
          phone: StorageService.phone,
          platform: mock.worker.platform,
          city: mock.worker.city,
          zone: mock.worker.zone,
          weeklyIncomeEstimate: mock.worker.weeklyIncomeEstimate.toDouble(),
        );

        emit(state.copyWith(
          user: profile,
          issScore: mock.worker.issScore.toDouble(),
          onboardingComplete: true,
          status: LoadStatus.success,
          errorMessage: null,
        ));
        return;
      }

      final data = await apiService.getWorkerById(event.userId);
      final profile = WorkerProfile.fromJson(data);

      // ISS score: backend may return it on the worker object. If not, default
      // to 62 (Karthik's baseline). INTERNAL ONLY — never bind to UI widgets.
      final issScore =
          (data['iss_score'] as num?)?.toDouble() ?? 62.0;

      final onboardingComplete = StorageService.isOnboarded;

      emit(state.copyWith(
        user: profile,
        issScore: issScore,
        onboardingComplete: onboardingComplete,
        status: LoadStatus.success,
        errorMessage: null,
      ));
    } on Exception catch (e) {
      // Try reading cached profile from StorageService before declaring failure.
      final cachedId = StorageService.userId;
      final cachedName = StorageService.getString('userName') ?? '';
      final cachedZone = StorageService.getString('userZone') ?? '';
      final cachedCity = StorageService.getString('userCity') ?? '';
      final cachedPlatform =
          StorageService.getString('userPlatform') ?? 'Zepto';

      if (cachedId.isNotEmpty && cachedName.isNotEmpty) {
        final fallback = WorkerProfile(
          id: cachedId,
          name: cachedName,
          phone: StorageService.phone,
          platform: cachedPlatform,
          city: cachedCity,
          zone: cachedZone,
          weeklyIncomeEstimate: 4200,
        );
        emit(state.copyWith(
          user: fallback,
          onboardingComplete: StorageService.isOnboarded,
          status: LoadStatus.success,
          errorMessage: null,
        ));
      } else {
        final message = _friendlyMessage(e);
        emit(state.copyWith(
          status: LoadStatus.failure,
          errorMessage: message,
        ));
      }
    }
  }

  /// Apply an in-memory update (e.g. after the onboarding form changes zone).
  Future<void> _onUpdateUser(UpdateUser event, Emitter<UserState> emit) async {
    emit(state.copyWith(
      user: event.updated,
      status: LoadStatus.success,
      errorMessage: null,
    ));
  }

  /// Persist the onboarding-complete flag locally and on the backend.
  Future<void> _onCompleteOnboarding(
      CompleteOnboarding event, Emitter<UserState> emit) async {
    await StorageService.setOnboarded(true);

    // Best-effort backend update — if it fails the local flag is already set.
    if (state.user != null) {
      try {
        await apiService.updateWorkerOnboarding(state.user!.id);
      } on Exception {
        // Silently ignore — onboarding flag is persisted locally.
      }
    }

    emit(state.copyWith(
      onboardingComplete: true,
      status: LoadStatus.success,
      errorMessage: null,
    ));
  }

  /// Re-fetch ISS score from backend and store internally without triggering
  /// UI rebuilds (issScore is excluded from Equatable props).
  Future<void> _onRefreshISS(
      RefreshISS event, Emitter<UserState> emit) async {
    try {
      final data = await apiService.getWorkerById(event.userId);
      // INTERNAL ONLY — never bind to UI widgets.
      final freshIss = (data['iss_score'] as num?)?.toDouble() ?? state.issScore;

      // Emit with updated issScore. Because issScore is NOT in props, widgets
      // will not rebuild — this is intentional and required by design.
      emit(UserState(
        user: state.user,
        onboardingComplete: state.onboardingComplete,
        issScore: freshIss, // INTERNAL ONLY
        status: state.status,
        errorMessage: state.errorMessage,
      ));
    } on Exception {
      // Silent — ISS refresh failure should never surface to the user.
    }
  }

  String _friendlyMessage(Exception e) {
    final raw = e.toString();
    if (raw.contains('SocketException') || raw.contains('Failed host lookup')) {
      return 'No internet connection. Please check your network and try again.';
    }
    if (raw.contains('404')) {
      return 'Your profile was not found. Please contact support.';
    }
    if (raw.contains('401') || raw.contains('403')) {
      return 'Your session has expired. Please log in again.';
    }
    return 'Something went wrong loading your profile. Please try again.';
  }

  @override
  Future<void> close() {
    // No open subscriptions or timers in UserBloc.
    return super.close();
  }
}
