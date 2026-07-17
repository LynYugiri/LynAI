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
    Future<void> Function()? afterAuthenticated,
  }) : _backend = backend,
       _injectedService = service,
       _secretStore = secretStore,
       _onSessionChanged = onSessionChanged,
       _afterAuthenticated = afterAuthenticated,
       _backendScope = backend?.backendScope ?? '' {
    _backend?.addListener(_handleBackendChanged);
  }

  final BackendClient? _backend;
  final AccountService? _injectedService;
  final SecretStore? _secretStore;
  final Future<void> Function(AccountUser? user)? _onSessionChanged;
  final Future<void> Function()? _afterAuthenticated;
  RemoteAccountService? _remoteService;
  String _backendScope;
  int _operationGeneration = 0;

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

  void _handleSessionInvalidated() {
    _operationGeneration++;
    _user = null;
    _loading = false;
    _error = null;
    notifyListeners();
    _notifySessionChanged();
  }

  void _handleBackendChanged() {
    final scope = _backend?.backendScope ?? '';
    if (scope == _backendScope) return;
    _operationGeneration++;
    _backendScope = scope;
    _loading = false;
    _error = null;
    final hadUser = _user != null;
    _user = null;
    notifyListeners();
    if (hadUser) _notifySessionChanged();
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
    retryPendingRevocations();
    final svc = _service;
    if (svc == null) return;
    try {
      final user = await svc.getCurrentUser();
      if (generation != _operationGeneration) return;
      _user = user;
      notifyListeners();
      await _onSessionChanged?.call(_user);
      if (generation != _operationGeneration) return;
      if (_user != null) {
        await _runAfterAuthenticated();
        if (generation != _operationGeneration) return;
      }
    } catch (e) {
      debugPrint('加载账号会话失败: $e');
    }
  }

  /// 手机号登录。
  Future<bool> login(String phone, String password) async {
    final generation = ++_operationGeneration;
    retryPendingRevocations();
    final svc = _service;
    if (svc == null) {
      _error = '未连接后端，请在设置中配置后端地址';
      notifyListeners();
      return false;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final session = await svc.login(username: phone, password: password);
      if (generation != _operationGeneration) return false;
      _user = session.user;
      _loading = false;
      notifyListeners();
      await _onSessionChanged?.call(_user);
      if (generation != _operationGeneration) return false;
      await _runAfterAuthenticated();
      if (generation != _operationGeneration) return false;
      return true;
    } catch (e) {
      if (generation != _operationGeneration) return false;
      _loading = false;
      _error = e.toString();
      notifyListeners();
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
      notifyListeners();
      return false;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final session = await svc.register(
        username: phone,
        password: password,
        displayName: displayName,
      );
      if (generation != _operationGeneration) return false;
      _user = session.user;
      _loading = false;
      notifyListeners();
      await _onSessionChanged?.call(_user);
      if (generation != _operationGeneration) return false;
      await _runAfterAuthenticated();
      if (generation != _operationGeneration) return false;
      return true;
    } catch (e) {
      if (generation != _operationGeneration) return false;
      _loading = false;
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// 登出当前用户。
  Future<void> logout() async {
    final generation = ++_operationGeneration;
    final svc = _service;
    if (svc == null) {
      _user = null;
      notifyListeners();
      await _onSessionChanged?.call(null);
      if (generation != _operationGeneration) return;
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await svc.logout();
      if (generation != _operationGeneration) return;
      _user = null;
      _loading = false;
      notifyListeners();
      await _onSessionChanged?.call(null);
      if (generation != _operationGeneration) return;
    } catch (e) {
      if (generation != _operationGeneration) return;
      _loading = false;
      _error = e.toString();
      notifyListeners();
    }
  }

  void _notifySessionChanged() {
    final callback = _onSessionChanged;
    if (callback != null) callback(_user);
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
    notifyListeners();
  }

  @override
  void dispose() {
    _backend?.removeListener(_handleBackendChanged);
    super.dispose();
  }
}
