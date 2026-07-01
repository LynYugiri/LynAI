/// 账号系统中的用户身份。
///
/// [phone] 是唯一登录标识，[displayName] 是用户可见的昵称（不唯一）。
/// [id] 是后端分配的雪花 ID（序列化为字符串防精度丢失）。
class AccountUser {
  /// 用户唯一标识符（后端雪花 ID，字符串形式）。
  final String id;

  /// 手机号（唯一登录标识）。
  final String phone;

  /// 显示昵称（用户可修改，不唯一）。
  final String displayName;

  /// 头像 URL（远端资源，可能为空）。
  final String? avatarUrl;

  /// 邮箱（可能为空）。
  final String? email;

  /// 是否为管理员。
  final bool isAdmin;

  /// 创建账号用户实例。
  const AccountUser({
    required this.id,
    required this.phone,
    required this.displayName,
    this.avatarUrl,
    this.email,
    this.isAdmin = false,
  });

  /// 从后端 JSON 构造用户实例，容忍缺失字段。
  factory AccountUser.fromJson(Map<String, dynamic> json) {
    return AccountUser(
      id: json['id'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String?,
      email: json['email'] as String?,
      isAdmin: json['isAdmin'] as bool? ?? false,
    );
  }

  /// 序列化为 JSON，用于本地缓存或测试断言。
  Map<String, dynamic> toJson() => {
    'id': id,
    'phone': phone,
    'displayName': displayName,
    if (avatarUrl != null) 'avatarUrl': avatarUrl,
    if (email != null) 'email': email,
    'isAdmin': isAdmin,
  };
}

/// 认证令牌。
///
/// 承载后端返回的访问令牌和刷新令牌。Provider 持有它用于后续
/// 需要鉴权的请求；UI 不直接读取 token 内容。
class AuthToken {
  /// 访问令牌。
  final String accessToken;

  /// 刷新令牌。
  final String? refreshToken;

  /// 过期时间（毫秒 epoch，可选）。
  final int? expiresAt;

  /// 创建认证令牌实例。
  const AuthToken({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
  });

  /// 从后端 JSON 构造令牌实例。
  factory AuthToken.fromJson(Map<String, dynamic> json) {
    return AuthToken(
      accessToken: json['accessToken'] as String? ?? '',
      refreshToken: json['refreshToken'] as String?,
      expiresAt: json['expiresAt'] as int?,
    );
  }

  /// 序列化为 JSON。
  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    if (refreshToken != null) 'refreshToken': refreshToken,
    if (expiresAt != null) 'expiresAt': expiresAt,
  };
}

/// 登录结果，包含用户和令牌。
class AuthSession {
  /// 登录用户。
  final AccountUser user;

  /// 认证令牌。
  final AuthToken token;

  /// 创建登录结果实例。
  const AuthSession({required this.user, required this.token});

  /// 从后端 JSON 构造实例。
  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      user: AccountUser.fromJson(
        Map<String, dynamic>.from(json['user'] as Map? ?? const {}),
      ),
      token: AuthToken.fromJson(
        Map<String, dynamic>.from(json['token'] as Map? ?? const {}),
      ),
    );
  }
}

/// 后端尚未连接或账号服务不可用时的统一异常。
class AccountUnavailableException implements Exception {
  final String message;
  const AccountUnavailableException(this.message);

  @override
  String toString() => 'AccountUnavailableException: $message';
}
