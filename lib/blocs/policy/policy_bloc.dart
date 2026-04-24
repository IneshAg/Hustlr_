import 'package:flutter_bloc/flutter_bloc.dart';
import '../../services/api_service.dart';
import '../../services/mock_data_service.dart';
import '../../models/policy.dart';
import '../../models/claim.dart';
import 'policy_event.dart';
import 'policy_state.dart';

class PolicyBloc extends Bloc<PolicyEvent, PolicyState> {
  final ApiService apiService;

  PolicyBloc({required this.apiService}) : super(const PolicyState()) {
    on<LoadPolicy>(_onLoadPolicy);
    on<ActivatePolicy>(_onActivatePolicy);
    on<CancelPolicy>(_onCancelPolicy);
    on<CheckCoverage>(_onCheckCoverage);
  }

  Future<void> _onLoadPolicy(
      LoadPolicy event, Emitter<PolicyState> emit) async {
    emit(state.copyWith(status: LoadStatus.loading));
    
    // ── DEMO OVERRIDE: Prioritize MockDataService ONLY for demo users ──
    if (event.userId.startsWith('DEMO_')) {
      final mockPolicy = MockDataService.instance.activePolicy;
      if (mockPolicy.status == 'ACTIVE') {
        final policy = Policy(
          id: 'mock-${mockPolicy.plan.toLowerCase()}',
          userId: event.userId,
          tier: mockPolicy.plan.toLowerCase().contains('full') ? PlanTier.full : (mockPolicy.plan.toLowerCase().contains('basic') ? PlanTier.basic : PlanTier.standard),
          status: PolicyStatus.active,
          basePremium: mockPolicy.premium,
          weeklyPremium: mockPolicy.premium,
          startDate: DateTime.tryParse(mockPolicy.coverageStart) ?? DateTime.now(),
          endDate: DateTime.tryParse(mockPolicy.coverageEnd) ?? DateTime.now().add(const Duration(days: 91)),
        );
        emit(state.copyWith(activePolicy: policy, selectedTier: policy.tier, coverageActive: true, status: LoadStatus.success));
        return;
      }
    }

    try {
      final data = await apiService.getPolicy(event.userId);
      final policyData = data['policy'] as Map<String, dynamic>?;

      // If API confirms a policy exists, USE IT (it will fallback to StorageService internally if offline)
      if (policyData != null) {
        final policy = Policy.fromJson(policyData);
        final now = DateTime.now();
        final coverageActive = policy.isActive &&
            policy.startDate != null &&
            now.isAfter(policy.startDate!) &&
            (policy.endDate == null || now.isBefore(policy.endDate!));

        emit(state.copyWith(
          activePolicy: policy,
          selectedTier: policy.tier,
          coverageActive: coverageActive,
          status: LoadStatus.success,
        ));
        return;
      }

      // ── SECONDARY SOURCE: Use MockDataService if API says no policy but we are in a demo session ──
      if (event.userId.startsWith('DEMO_') &&
          MockDataService.instance.hasActivePolicy) {
        final mockPolicy = MockDataService.instance.activePolicy;
        final policy = Policy(
          id: 'mock-${mockPolicy.plan.toLowerCase()}',
          userId: event.userId,
          tier: mockPolicy.plan.toLowerCase().contains('full') ? PlanTier.full : (mockPolicy.plan.toLowerCase().contains('basic') ? PlanTier.basic : PlanTier.standard),
          status: PolicyStatus.active,
          basePremium: mockPolicy.premium,
          weeklyPremium: mockPolicy.premium,
          startDate: DateTime.tryParse(mockPolicy.coverageStart) ?? DateTime.now(),
          endDate: DateTime.tryParse(mockPolicy.coverageEnd) ?? DateTime.now().add(const Duration(days: 91)),
        );
        emit(state.copyWith(activePolicy: policy, selectedTier: policy.tier, coverageActive: true, status: LoadStatus.success));
        return;
      }

      // No policy anywhere
      emit(state.copyWith(activePolicy: null, coverageActive: false, status: LoadStatus.success));
    } on Exception catch (e) {
      emit(state.copyWith(
        status: LoadStatus.failure,
        errorMessage: _friendlyMessage(e),
      ));
    }
  }

  /// Purchase and activate a policy. Coverage window starts only AFTER
  /// the backend confirms the payment — never speculatively.
  Future<void> _onActivatePolicy(
      ActivatePolicy event, Emitter<PolicyState> emit) async {
    emit(state.copyWith(status: LoadStatus.loading));
    try {
      final result = await apiService.createPolicy(
        userId: event.userId,
        planTier: event.tier.apiKey,
      );

      final policyData = result['policy'] as Map<String, dynamic>?;
      if (policyData == null) {
        throw Exception('Policy activation response was empty.');
      }

      final policy = Policy.fromJson(policyData);

      // Coverage window begins NOW — after confirmed server response.
      final coverageStartTime = DateTime.now();

      emit(state.copyWith(
        activePolicy: policy,
        selectedTier: policy.tier,
        coverageActive: true,
        coverageStartTime: coverageStartTime,
        status: LoadStatus.success,
        errorMessage: null,
      ));
    } on Exception catch (e) {
      emit(state.copyWith(
        status: LoadStatus.failure,
        errorMessage: _friendlyMessage(e),
      ));
    }
  }

  /// Cancel policy. Blocked if any claim is currently pending or processing.
  Future<void> _onCancelPolicy(
      CancelPolicy event, Emitter<PolicyState> emit) async {
    // Guard: do not allow cancellation while a claim is in-flight.
    final hasPendingClaim = state.pendingClaims.any(
      (c) =>
          c.status == ClaimStatus.pending ||
          c.status == ClaimStatus.processing,
    );

    if (hasPendingClaim) {
      emit(state.copyWith(
        status: LoadStatus.failure,
        errorMessage:
            'You cannot cancel your policy while a claim is being processed. '
            'Please wait for your open claim to be resolved first.',
      ));
      return;
    }

    emit(state.copyWith(status: LoadStatus.loading));
    try {
      await apiService.cancelPolicy(event.userId);

      emit(state.copyWith(
        activePolicy: state.activePolicy?.copyWith(
          status: PolicyStatus.cancelled,
        ),
        coverageActive: false,
        coverageStartTime: null,
        status: LoadStatus.success,
        errorMessage: null,
      ));
    } on Exception catch (e) {
      emit(state.copyWith(
        status: LoadStatus.failure,
        errorMessage: _friendlyMessage(e),
      ));
    }
  }

  /// Verify the coverage window without hitting the backend — purely local.
  Future<void> _onCheckCoverage(
      CheckCoverage event, Emitter<PolicyState> emit) async {
    final policy = state.activePolicy;

    if (policy == null || !policy.isActive) {
      emit(state.copyWith(
        coverageActive: false,
        status: LoadStatus.success,
        errorMessage: null,
      ));
      return;
    }

    if (state.coverageStartTime == null) {
      emit(state.copyWith(
        coverageActive: false,
        status: LoadStatus.success,
        errorMessage: null,
      ));
      return;
    }

    final now = DateTime.now();
    // A policy week runs Monday–Sunday. Check that now is within the window.
    final start = state.coverageStartTime!;
    final weekStart = start.subtract(Duration(days: start.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 7));
    final isWithinWindow = now.isAfter(start) && now.isBefore(weekEnd);

    emit(state.copyWith(
      coverageActive: isWithinWindow,
      status: LoadStatus.success,
      errorMessage: null,
    ));
  }

  String _friendlyMessage(Exception e) {
    final raw = e.toString();
    if (raw.contains('SocketException') || raw.contains('Failed host lookup')) {
      return 'No internet connection. Please check your network and try again.';
    }
    if (raw.contains('already has an active policy')) {
      return 'You already have an active policy. Go to Policy & Plans to manage it.';
    }
    if (raw.contains('404')) {
      return 'No policy found for your account.';
    }
    return 'Something went wrong with your policy. Please try again.';
  }

  @override
  Future<void> close() {
    // No open subscriptions or timers in PolicyBloc.
    return super.close();
  }
}
