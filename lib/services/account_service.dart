import '../models/account.dart';

/// 账号服务抽象。
///
/// 定义注册、登录、登出、当前用户查询和同步能力，不绑定具体后端实现。
/// 前端页面和 Provider 只依赖这个抽象，后端就绪后用
/// [RemoteAccountService] 实现。
abstract class AccountService {
  /// 注册新用户，返回登录会话。
  Future<AuthSession> register({
    required String username,
    required String password,
    String? displayName,
  });

  /// 手机号和密码登录，返回登录会话。
  Future<AuthSession> login({
    required String username,
    required String password,
  });

  /// 登出当前用户，清理本地凭证。
  Future<void> logout();

  /// 获取当前登录用户，未登录或会话失效返回 null。
  Future<AccountUser?> getCurrentUser();

  /// 加载本地持久化的会话状态（启动时调用）。
  ///
  /// 返回 null 表示本地无保存的会话。实现应从安全存储读取 token，
  /// 并从普通持久化存储读取非敏感用户元数据。
  Future<AuthSession?> loadStoredSession();

  /// 当前服务是否已连接到真实后端。
  ///
  /// [RemoteAccountService] 返回 true。
  /// 页面据此决定显示真实登录表单还是「未连接后端」提示。
  bool get isBackendConnected;
}
