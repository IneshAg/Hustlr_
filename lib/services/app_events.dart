import 'dart:async';

class AppEvents {
  static final instance = AppEvents._();
  AppEvents._();

  final _policyUpdated   = StreamController<void>.broadcast();
  final _walletUpdated   = StreamController<void>.broadcast();
  final _claimUpdated    = StreamController<void>.broadcast();
  final _profileUpdated  = StreamController<void>.broadcast();
  final _connectivityRestored = StreamController<void>.broadcast();

  Stream<void> get onPolicyUpdated  => _policyUpdated.stream;
  Stream<void> get onWalletUpdated  => _walletUpdated.stream;
  Stream<void> get onClaimUpdated   => _claimUpdated.stream;
  Stream<void> get onProfileUpdated => _profileUpdated.stream;
  Stream<void> get onConnectivityRestored => _connectivityRestored.stream;

  void policyUpdated()  => _policyUpdated.add(null);
  void walletUpdated()  => _walletUpdated.add(null);
  void claimUpdated()   => _claimUpdated.add(null);
  void profileUpdated() => _profileUpdated.add(null);
  void connectivityRestored() => _connectivityRestored.add(null);

  void dispose() {
    _policyUpdated.close();
    _walletUpdated.close();
    _claimUpdated.close();
    _profileUpdated.close();
    _connectivityRestored.close();
  }
}
