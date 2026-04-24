import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/api_service.dart';
import '../../services/mock_data_service.dart';
import '../../core/services/storage_service.dart';
import '../../models/claim.dart';
import '../../models/wallet_balance.dart';
import '../../services/app_events.dart';
import 'claims_event.dart';
import 'claims_state.dart';

class ClaimsBloc extends Bloc<ClaimsEvent, ClaimsState> {
  final ApiService apiService;
  final SupabaseClient? supabase;

  /// Supabase real-time stream subscription for claim updates.
  StreamSubscription<List<Map<String, dynamic>>>? _claimsSubscription;

  /// The userId currently being watched. Stored so the stream can reference it.
  String? _watchedUserId;

  /// External callback hook for the MockDataService demo bridge.
  /// When triggerRainDisruption() fires in demo mode, it calls this to push
  /// a ClaimStatusUpdated event through the BLoC layer.
  void Function(ClaimStatusUpdated event)? onDemoClaimReady;

  StreamSubscription? _profileSubscription;

  ClaimsBloc({required this.apiService, required this.supabase})
      : super(const ClaimsState()) {
    on<LoadClaims>(_onLoadClaims);
    on<WatchClaims>(_onWatchClaims);
    on<ClaimStatusUpdated>(_onClaimStatusUpdated);
    on<RefreshWallet>(_onRefreshWallet);
    on<WithdrawFunds>(_onWithdrawFunds);
    on<SubmitClaimAppeal>(_onSubmitAppeal);

    // Auto-refresh when persona switches
    _profileSubscription = AppEvents.instance.onProfileUpdated.listen((_) {
      final newUserId = StorageService.userId;
      if (newUserId.isNotEmpty) {
        add(LoadClaims(newUserId));
      }
    });
  }

  @override
  Future<void> close() {
    _claimsSubscription?.cancel();
    _profileSubscription?.cancel();
    _watchedUserId = null;
    return super.close();
  }

  /// Load a one-shot snapshot of claims + wallet. Does not start polling.
  Future<void> _onLoadClaims(
      LoadClaims event, Emitter<ClaimsState> emit) async {
    emit(state.copyWith(status: LoadStatus.loading));
    try {
      final results = await Future.wait([
        apiService.getClaims(event.userId),
        apiService.getWallet(event.userId),
      ]);

      var claimsData = results[0];
      var walletData = results[1];
      
      final apiClaims = (claimsData['claims'] as List<dynamic>? ?? [])
          .map((c) => Claim.fromJson(c as Map<String, dynamic>))
          .toList();
      
      final walletFromApi = WalletBalance.fromJson(walletData);

      // ── DEMO OVERRIDE: Prioritize MockDataService ONLY for demo users ──
      final isDemoSession = event.userId.startsWith('DEMO_') ||
          event.userId.startsWith('demo-') ||
          event.userId.startsWith('mock-');
      if (isDemoSession) {
        final mock = MockDataService.instance;
        final mockClaims = mock.claims.map((c) => Claim(
          id: c.id,
          userId: event.userId,
          triggerType: c.type,
          displayLabel: c.type.contains('rain') ? 'Rain Disruption' : c.type,
          status: _mapMockStatus(c.status),
          grossPayout: c.amount,
          tranche1: (c.amount * 0.7).round(),
          tranche2: (c.amount * 0.3).round(),
          zone: c.zone,
          createdAt: DateTime.now(),
        )).toList();

        // Merge Mock + API (Mock first for demo feel)
        final List<Claim> combinedClaims = [...mockClaims, ...apiClaims];
        
        // For demo users, ALWAYS prioritize MockDataService wallet as it holds the disruption results
        final wallet = WalletBalance(
          balance: mock.walletBalance.toInt(),
          totalPayouts: mock.monthlySavings.toInt(),
          totalPremiums: 0,
          transactions: mock.transactions.map((t) => WalletTransaction(
            type: t['type'] == 'credit' ? 'credit' : 'debit',
            title: t['title']?.toString() ?? '',
            subtitle: t['subtitle']?.toString() ?? '',
            amount: (t['amount'] as num?)?.toInt() ?? 0,
            createdAt: DateTime.now(),
          )).toList(),
        );

        final computed = _computeAmounts(combinedClaims, wallet);
        emit(state.copyWith(
          claims: combinedClaims, 
          wallet: wallet, 
          pendingAmount: computed.$1, 
          availableAmount: computed.$2, 
          status: LoadStatus.success
        ));
        return;
      }

      // ── REAL USER: API is primary source. ──
      final computed = _computeAmounts(apiClaims, walletFromApi);
      emit(state.copyWith(
        claims: apiClaims,
        wallet: walletFromApi,
        pendingAmount: computed.$1,
        availableAmount: computed.$2,
        status: LoadStatus.success,
      ));
    } on Exception catch (e) {
      emit(state.copyWith(
        status: LoadStatus.failure,
        errorMessage: _friendlyMessage(e),
      ));
    }
  }

  /// Open a Supabase real-time subscription. On stream update, map claims and emit
  /// [ClaimStatusUpdated] for any claim whose status changed or is new.
  Future<void> _onWatchClaims(
      WatchClaims event, Emitter<ClaimsState> emit) async {
    // Cancel any existing subscription before starting a new one.
    _claimsSubscription?.cancel();
    _watchedUserId = event.userId;

    // Perform an immediate load before starting the stream.
    await _onLoadClaims(LoadClaims(event.userId), emit);

    if (supabase == null) {
      return;
    }

    try {
      final stream = supabase!
          .from('claims')
          .stream(primaryKey: ['id']).eq('user_id', event.userId);

      _claimsSubscription = stream.listen((payload) {
        if (payload.isEmpty || isClosed) return;

        final freshClaims = payload.map((c) => Claim.fromJson(c)).toList();

        // Detect status changes compared to current state.
        for (final fresh in freshClaims) {
          final existing = state.claims.where((c) => c.id == fresh.id);
          if (existing.isEmpty) {
            // New claim arrived — fire update.
            add(ClaimStatusUpdated(fresh));
          } else if (existing.first.status != fresh.status) {
            // Status changed — fire update.
            add(ClaimStatusUpdated(fresh));
          }
        }
      });
    } on Exception {
      // Degrade gracefully if real-time stream init fails.
    }
  }

  /// Merge an updated claim into state. When approved, also refresh the wallet
  /// so Dashboard and Wallet screens update without extra API calls.
  Future<void> _onClaimStatusUpdated(
      ClaimStatusUpdated event, Emitter<ClaimsState> emit) async {
    final updatedClaims = state.claims.map((c) {
      return c.id == event.updatedClaim.id ? event.updatedClaim : c;
    }).toList();

    // If this claim is new (not yet in state), append it.
    if (!state.claims.any((c) => c.id == event.updatedClaim.id)) {
      updatedClaims.insert(0, event.updatedClaim);
    }

    WalletBalance wallet = state.wallet;

    // On approval, refresh the wallet balance immediately so both Dashboard
    // and Wallet screens reflect the new balance without a separate API call.
    if (event.updatedClaim.status == ClaimStatus.approved &&
        _watchedUserId != null) {
      try {
        final walletData = await apiService.getWallet(_watchedUserId!);
        wallet = WalletBalance.fromJson(walletData);
      } on Exception {
        // Optimistically apply tranche1 to the last known balance.
        wallet = wallet.copyWith(
          balance: wallet.balance + event.updatedClaim.tranche1,
        );
      }
    }

    final computed = _computeAmounts(updatedClaims, wallet);

    emit(state.copyWith(
      claims: updatedClaims,
      wallet: wallet,
      pendingAmount: computed.$1,
      availableAmount: computed.$2,
      status: LoadStatus.success,
      errorMessage: null,
    ));
  }

  /// Re-fetch wallet only — for pull-to-refresh on the Wallet screen.
  Future<void> _onRefreshWallet(
      RefreshWallet event, Emitter<ClaimsState> emit) async {
    try {
      final walletData = await apiService.getWallet(event.userId);
      final wallet = WalletBalance.fromJson(walletData);
      final computed = _computeAmounts(state.claims, wallet);

      emit(state.copyWith(
        wallet: wallet,
        pendingAmount: computed.$1,
        availableAmount: computed.$2,
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

  Future<void> _onSubmitAppeal(
    SubmitClaimAppeal event,
    Emitter<ClaimsState> emit,
  ) async {
    emit(state.copyWith(status: LoadStatus.loading));
    try {
      await apiService.submitClaimAppeal(
        claimId: event.claimId,
        workerId: event.workerId,
        selectedReason: event.selectedReason,
        additionalContext: event.additionalContext,
      );
      // Refresh claims list so the appealed claim shows updated status
      final updatedData = await apiService.getClaims(event.workerId);
      final rawClaims = updatedData['claims'] as List<dynamic>? ?? [];
      final claims = rawClaims
          .map((c) => Claim.fromJson(c as Map<String, dynamic>))
          .toList();
      emit(state.copyWith(status: LoadStatus.success, claims: claims));
    } catch (e) {
      emit(state.copyWith(
        status: LoadStatus.failure,
        errorMessage: 'Appeal could not be submitted. Please try again.',
      ));
    }
  }

  /// UPI withdrawal. Optimistically deducts from balance and rolls back on failure.
  Future<void> _onWithdrawFunds(
      WithdrawFunds event, Emitter<ClaimsState> emit) async {
    if (event.amount <= 0) {
      emit(state.copyWith(
        status: LoadStatus.failure,
        errorMessage: 'Withdrawal amount must be greater than zero.',
      ));
      return;
    }

    if (event.amount > state.wallet.balance) {
      emit(state.copyWith(
        status: LoadStatus.failure,
        errorMessage:
            'Insufficient balance. Your available balance is ₹${state.wallet.balance}.',
      ));
      return;
    }

    // Optimistic update before the API call.
    final optimisticWallet = state.wallet.copyWith(
      balance: state.wallet.balance - event.amount.toInt(),
    );
    final computed = _computeAmounts(state.claims, optimisticWallet);
    emit(state.copyWith(
      wallet: optimisticWallet,
      availableAmount: computed.$2,
      status: LoadStatus.loading,
    ));

    try {
      await ApiService.walletDebit(
        userId: event.userId,
        amount: event.amount.toInt(),
        description: 'UPI Withdrawal',
      );
      emit(state.copyWith(
        status: LoadStatus.success,
        errorMessage: null,
      ));
    } on Exception catch (e) {
      // Roll back the optimistic update.
      final rolledBack = state.wallet.copyWith(
        balance: state.wallet.balance + event.amount.toInt(),
      );
      final recomputed = _computeAmounts(state.claims, rolledBack);
      emit(state.copyWith(
        wallet: rolledBack,
        pendingAmount: recomputed.$1,
        availableAmount: recomputed.$2,
        status: LoadStatus.failure,
        errorMessage: _friendlyMessage(e),
      ));
    }
  }

  /// Compute pendingAmount and availableAmount from the claims list and wallet.
  ///
  /// - [pendingAmount]: sum of tranche2 for non-settled claims (held for fraud review).
  /// - [availableAmount]: the server-confirmed wallet balance (tranche1 already credited).
  (double, double) _computeAmounts(List<Claim> claims, WalletBalance wallet) {
    final pending = claims
        .where((c) =>
            c.status == ClaimStatus.pending ||
            c.status == ClaimStatus.processing)
        .fold<int>(0, (sum, c) => sum + c.tranche2);

    return (pending.toDouble(), wallet.balance.toDouble());
  }

  String _friendlyMessage(Exception e) {
    final raw = e.toString();
    if (raw.contains('SocketException') || raw.contains('Failed host lookup')) {
      return 'No internet connection. Please check your network and try again.';
    }
    if (raw.contains('Insufficient')) {
      return 'Insufficient balance for this withdrawal.';
    }
    if (raw.contains('404')) {
      return 'No claims found for your account.';
    }
    return 'Something went wrong. Please try again.';
  }

  ClaimStatus _mapMockStatus(String? status) {
    switch (status?.toLowerCase()) {
      case 'approved':
      case 'paid':
        return ClaimStatus.approved;
      case 'pending':
        return ClaimStatus.pending;
      case 'flagged':
      case 'rejected':
        return ClaimStatus.rejected;
      default:
        return ClaimStatus.processing;
    }
  }

}
