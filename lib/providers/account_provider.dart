import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/account.dart';
import '../services/account_service.dart';
import '../services/backend_client.dart';
import '../services/remote_account_service.dart';
import '../services/secret_store.dart';

/// 账号状态管理。
///
/// 持有当前登录用户和登录态，通过 [BackendClient] 动态选择
/// [RemoteAccountService] 作为底层实现。未连接后端时无法登录，
/// UI 应显示「未连接后端」提示。
class AccountProvider extends ChangeNotifier {
  /// 创建账号 Provider。
  ///
  /// 传入 [backend] 后会根据其连接状态动态选择 service。
  /// 传入 [service] 则直接使用（用于测试）。
  AccountProvider({
    BackendClient? backend,
    AccountService? service,
    SecretStore? secretStore,
    Future<void> Function(AccountUser? user)? onSessionChanged,
    Future<void> Function(AccountUser? user)? onDatasetActivation,
    Future<void> Function()? afterAuthenticated,
    Future<void> Function(AccountUser user)? onRemoteActivation,
  }) : _backend = backend,
       _injectedService = service,
       _secretStore = secretStore,
       _onSessionChanged = onSessionChanged,
       _onDatasetActivation = onDatasetActivation,
       _afterAuthenticated = afterAuthenticated,
       _onRemoteActivation = onRemoteActivation,
       _backendScope = backend?.backendScope ?? '' {
    _backend?.addListener(_handleBackendChanged);
  }

  final BackendClient? _backend;
  final AccountService? _injectedService;
  final SecretStore? _secretStore;
  final Future<void> Function(AccountUser? user)? _onSessionChanged;
  final Future<void> Function(AccountUser? user)? _onDatasetActivation;
  final Future<void> Function()? _afterAuthenticated;
  final Future<void> Function(AccountUser user)? _onRemoteActivation;
  RemoteAccountService? _remoteService;
  String _backendScope;
  int _operationGeneration = 0;
  bool _disposed = false;
  Future<void>? _activationFuture;
  int? _activationGeneration;

  AccountService? get _service {
    if (_injectedService != null) return _injectedService;
    if (_backend != null && _backend.isConnected) {
      final secretStore = _secretStore;
      if (secretStore == null) {
        throw StateError('AccountProvider requires SecretStore with a backend');
      }
      return _remoteService ??= RemoteAccountService(
        _backend,
        secretStore: secretStore,
        onSessionInvalidated: _handleSessionInvalidated,
      );
    }
    return null;
  }

  AccountUser? _user;
  bool _loading = false;
  String? _error;

  Future<void> _handleSessionInvalidated() async {
    if (_disposed) return;
    final generation = ++_operationGeneration;
    _loading = true;
    _error = null;
    _notifyListeners();
    try {
      await _onDatasetActivation?.call(null);
    } catch (e) {
      if (_isCurrent(generation)) {
        _loading = false;
        _error = '切换到本地数据集失败: $e';
        _notifyListeners();
      }
      return;
    }
    if (!_isCurrent(generation)) return;
    _user = null;
    _loading = false;
    _notifyListeners();
    try {
      await _onSessionChanged?.call(null);
    } catch (e) {
      debugPrint('解除账号会话绑定失败: $e');
      return;
    }
    if (!_isCurrent(generation)) return;
  }

  Future<void> reconfigureBackend({
    required String? url,
    required Future<void> Function(String? url) persist,
  }) async {
    final backend = _backend;
    if (backend == null) throw StateError('Backend client is not configured');
    final generation = ++_operationGeneration;
    await persist(url);
    if (!_isCurrent(generation)) return;
    _loading = true;
    _error = null;
    _notifyListeners();
    try {
      await _onDatasetActivation?.call(null);
    } catch (e) {
      if (_isCurrent(generation)) {
        _loading = false;
        _error = e.toString();
        _notifyListeners();
      }
      return;
    }
    if (!_isCurrent(generation)) return;
    _user = null;
    _loading = false;
    _notifyListeners();
    await _onSessionChanged?.call(null);
    if (!_isCurrent(generation)) return;
    _backendScope = BackendClient.normalizeUrl(url ?? '');
    backend.configure(url ?? '');
    _remoteService = null;
    _notifyListeners();
  }

  void _handleBackendChanged() {
    if (_disposed) return;
    final scope = _backend?.backendScope ?? '';
    if (scope == _backendScope) return;
    _operationGeneration++;
    _backendScope = scope;
    _loading = false;
    _error = null;
    final hadUser = _user != null;
    if (!hadUser) {
      _notifyListeners();
      return;
    }
    final generation = _operationGeneration;
    unawaited(_clearForBackendChange(generation));
  }

  Future<void> _clearForBackendChange(int generation) async {
    _loading = true;
    _notifyListeners();
    try {
      await _onDatasetActivation?.call(null);
    } catch (e) {
      if (_isCurrent(generation)) {
        _loading = false;
        _error = '切换到本地数据集失败: $e';
        _notifyListeners();
      }
      return;
    }
    if (!_isCurrent(generation)) return;
    _user = null;
    _loading = false;
    _notifyListeners();
    await _onSessionChanged?.call(null);
  }

  /// 当前登录用户，未登录时为 null。
  AccountUser? get user => _user;

  /// 是否已登录。
  bool get isLoggedIn => _user != null;

  /// 是否正在执行登录/注册/登出操作。
  bool get loading => _loading;

  /// 最近一次操作的错误信息（展示后应调用 [clearError] 清除）。
  String? get error => _error;

  /// 当前是否已连接真实后端。
  bool get isBackendConnected =>
      _injectedService?.isBackendConnected ?? (_backend?.isConnected ?? false);

  /// 启动时从本地持久化恢复会话。
  Future<void> load() async {
    final generation = ++_operationGeneration;
    await _restoreLocalSession(generation);
    if (!_isCurrent(generation)) return;
    await _refreshCurrentSession(generation);
    if (!_isCurrent(generation)) return;
    await activateCurrentSession();
  }

  /// 仅恢复本地缓存的用户和令牌，不请求 `/auth/me`。
  Future<void> restoreLocalSession() async {
    final generation = ++_operationGeneration;
    await _restoreLocalSession(generation);
  }

  Future<void> _restoreLocalSession(int generation) async {
    retryPendingRevocations();
    final svc = _service;
    if (svc == null) return;
    try {
      final session = await switch (svc) {
        AccountSessionRecovery recovery => recovery.restoreLocalSession(),
        _ => svc.loadStoredSession(),
      };
      if (!_isCurrent(generation)) return;
      final user = session?.user;
      await _onDatasetActivation?.call(user);
      if (!_isCurrent(generation)) return;
      _user = user;
      _notifyListeners();
      await _onSessionChanged?.call(_user);
    } catch (e) {
      debugPrint('加载账号会话失败: $e');
    }
  }

  /// 使用 `/auth/me` 刷新当前缓存用户；临时失败时保留现有用户。
  Future<void> refreshCurrentSession() async {
    final generation = ++_operationGeneration;
    await _refreshCurrentSession(generation);
  }

  Future<void> _refreshCurrentSession(int generation) async {
    final svc = _service;
    if (svc == null) return;
    try {
      final user = await switch (svc) {
        AccountSessionRecovery recovery => recovery.refreshCurrentSession(),
        _ => svc.getCurrentUser(),
      };
      if (!_isCurrent(generation)) return;
      if (user == null && _user != null) {
        await _onDatasetActivation?.call(null);
        if (!_isCurrent(generation)) return;
        await _onSessionChanged?.call(null);
        if (!_isCurrent(generation)) return;
      }
      _user = user;
      _notifyListeners();
    } catch (e) {
      debugPrint('刷新账号会话失败: $e');
    }
  }

  /// Starts best-effort network work for the current locally bound session.
  Future<void> activateCurrentSession() {
    final generation = _operationGeneration;
    final user = _user;
    if (user == null || !_isCurrent(generation)) return Future.value();
    final active = _activationFuture;
    if (active != null && _activationGeneration == generation) return active;

    late final Future<void> operation;
    operation = _activateCurrentSession(generation, user).whenComplete(() {
      if (identical(_activationFuture, operation)) {
        _activationFuture = null;
        _activationGeneration = null;
      }
    });
    _activationGeneration = generation;
    return _activationFuture = operation;
  }

  Future<void> _activateCurrentSession(int generation, AccountUser user) async {
    await _runAfterAuthenticated();
    if (!_isCurrent(generation) || _user?.id != user.id) return;
    try {
      await _onRemoteActivation?.call(user);
    } catch (e) {
      debugPrint('激活远端账号会话失败: $e');
    }
  }

  /// 手机号登录。
  Future<bool> login(String phone, String password) async {
    final generation = ++_operationGeneration;
    retryPendingRevocations();
    final svc = _service;
    if (svc == null) {
      _error = '未连接后端，请在设置中配置后端地址';
      _notifyListeners();
      return false;
    }
    _loading = true;
    _error = null;
    _notifyListeners();
    try {
      final session = await svc.login(username: phone, password: password);
      if (!_isCurrent(generation)) return false;
      try {
        await _onDatasetActivation?.call(session.user);
      } catch (_) {
        try {
          await svc.logout();
        } catch (_) {}
        rethrow;
      }
      if (!_isCurrent(generation)) return false;
      _user = session.user;
      _loading = false;
      _notifyListeners();
      await _onSessionChanged?.call(_user);
      if (!_isCurrent(generation)) return false;
      unawaited(activateCurrentSession());
      return true;
    } catch (e) {
      if (!_isCurrent(generation)) return false;
      _loading = false;
      _error = e.toString();
      _notifyListeners();
      return false;
    }
  }

  /// 手机号注册。
  Future<bool> register(
    String phone,
    String password, {
    String? displayName,
  }) async {
    final generation = ++_operationGeneration;
    final svc = _service;
    if (svc == null) {
      _error = '未连接后端，请在设置中配置后端地址';
      _notifyListeners();
      return false;
    }
    _loading = true;
    _error = null;
    _notifyListeners();
    try {
      final session = await svc.register(
        username: phone,
        password: password,
        displayName: displayName,
      );
      if (!_isCurrent(generation)) return false;
      try {
        await _onDatasetActivation?.call(session.user);
      } catch (_) {
        try {
          await svc.logout();
        } catch (_) {}
        rethrow;
      }
      if (!_isCurrent(generation)) return false;
      _user = session.user;
      _loading = false;
      _notifyListeners();
      await _onSessionChanged?.call(_user);
      if (!_isCurrent(generation)) return false;
      unawaited(activateCurrentSession());
      return true;
    } catch (e) {
      if (!_isCurrent(generation)) return false;
      _loading = false;
      _error = e.toString();
      _notifyListeners();
      return false;
    }
  }

  /// 登出当前用户。
  Future<void> logout() async {
    final generation = ++_operationGeneration;
    final svc = _service;
    if (svc == null) {
      await _activateLocalThenPublishLogout(generation);
      return;
    }
    _loading = true;
    _error = null;
    _notifyListeners();
    try {
      await svc.logout();
      if (!_isCurrent(generation)) return;
      await _activateLocalThenPublishLogout(generation);
    } catch (e) {
      if (!_isCurrent(generation)) return;
      _loading = false;
      _error = e.toString();
      _notifyListeners();
    }
  }

  Future<void> _activateLocalThenPublishLogout(int generation) async {
    await _onDatasetActivation?.call(null);
    if (!_isCurrent(generation)) return;
    _user = null;
    _loading = false;
    _notifyListeners();
    await _onSessionChanged?.call(null);
  }

  bool _isCurrent(int generation) =>
      !_disposed && generation == _operationGeneration;

  void _notifyListeners() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _runAfterAuthenticated() async {
    try {
      await _afterAuthenticated?.call();
    } catch (e) {
      debugPrint('设备注册失败: $e');
    }
  }

  /// Starts a best-effort retry of refresh-token revocations queued at logout.
  void retryPendingRevocations() {
    final service = _service;
    if (service is RemoteAccountService) {
      unawaited(service.retryPendingRevocations());
    }
  }

  /// 清除最近一次操作的错误信息。
  void clearError() {
    if (_error == null) return;
    _error = null;
    _notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _operationGeneration++;
    _backend?.removeListener(_handleBackendChanged);
    super.dispose();
  }
}
