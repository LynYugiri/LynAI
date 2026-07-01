import 'package:flutter/foundation.dart';

import '../models/account.dart';
import '../services/account_service.dart';
import '../services/backend_client.dart';
import '../services/remote_account_service.dart';

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
  AccountProvider({BackendClient? backend, AccountService? service})
    : _backend = backend,
      _injectedService = service;

  final BackendClient? _backend;
  final AccountService? _injectedService;
  RemoteAccountService? _remoteService;

  AccountService? get _service {
    if (_injectedService != null) return _injectedService;
    if (_backend != null && _backend.isConnected) {
      return _remoteService ??= RemoteAccountService(_backend);
    }
    return null;
  }

  AccountUser? _user;
  bool _loading = false;
  String? _error;

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
    final svc = _service;
    if (svc == null) return;
    try {
      final user = await svc.getCurrentUser();
      _user = user;
      notifyListeners();
    } catch (e) {
      debugPrint('加载账号会话失败: $e');
    }
  }

  /// 手机号登录。
  Future<bool> login(String phone, String password) async {
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
      _user = session.user;
      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
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
      _user = session.user;
      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _loading = false;
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// 登出当前用户。
  Future<void> logout() async {
    final svc = _service;
    if (svc == null) {
      _user = null;
      notifyListeners();
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await svc.logout();
      _user = null;
      _loading = false;
      notifyListeners();
    } catch (e) {
      _loading = false;
      _error = e.toString();
      notifyListeners();
    }
  }

  /// 清除最近一次操作的错误信息。
  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }
}
