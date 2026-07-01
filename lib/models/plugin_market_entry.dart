/// 远端插件市场中的插件目录条目。
///
/// 描述一个可从后端下载安装的插件，字段对齐 [PluginManifest] 中用户可见
/// 的元数据。与 [InstalledPlugin] 分开，因为市场条目只承载目录信息，
/// 不承载本地启用状态、授权或文件路径——那些属于本地安装后的运行时视图。
class MarketPluginEntry {
  /// 插件唯一标识符，与安装后的 `PluginManifest.id` 一致。
  final String id;

  /// 插件显示名称。
  final String name;

  /// 插件作者。
  final String author;

  /// 插件简介。
  final String description;

  /// 当前市场版本号。
  final String version;

  /// 图标 URL（远端资源）。
  final String? iconUrl;

  /// 截图 URL 列表，用于详情页轮播。
  final List<String> screenshots;

  /// 插件声明的权限清单，供安装前预览。
  final List<String> permissions;

  /// 下载地址（相对后端根 URL 的路径或绝对 URL）。
  final String downloadUrl;

  /// ZIP 包的 SHA-256 校验值，用于下载完整性校验。
  final String? sha256;

  /// 市场分类标签。
  final String category;

  /// 审核状态：pending、approved、rejected。
  final String status;

  /// 审核备注或驳回原因。
  final String? reviewNote;

  /// 创建市场插件条目实例。
  const MarketPluginEntry({
    required this.id,
    required this.name,
    required this.author,
    required this.description,
    required this.version,
    required this.downloadUrl,
    this.iconUrl,
    this.screenshots = const [],
    this.permissions = const [],
    this.sha256,
    this.category = '',
    this.status = 'approved',
    this.reviewNote,
  });

  /// 从后端 JSON 构造条目，容忍缺失字段。
  factory MarketPluginEntry.fromJson(Map<String, dynamic> json) {
    return MarketPluginEntry(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? json['id'] as String? ?? '',
      author: json['author'] as String? ?? '',
      description: json['description'] as String? ?? '',
      version: json['version'] as String? ?? '0.0.0',
      iconUrl: json['iconUrl'] as String?,
      screenshots: (json['screenshots'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      permissions: (json['permissions'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      downloadUrl: json['downloadUrl'] as String? ?? '',
      sha256: json['sha256'] as String?,
      category: json['category'] as String? ?? '',
      status: json['status'] as String? ?? 'approved',
      reviewNote: json['reviewNote'] as String?,
    );
  }

  /// 序列化为 JSON，用于本地缓存或测试断言。
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'author': author,
    'description': description,
    'version': version,
    if (iconUrl != null) 'iconUrl': iconUrl,
    if (screenshots.isNotEmpty) 'screenshots': screenshots,
    if (permissions.isNotEmpty) 'permissions': permissions,
    'downloadUrl': downloadUrl,
    if (sha256 != null) 'sha256': sha256,
    if (category.isNotEmpty) 'category': category,
    'status': status,
    if (reviewNote != null) 'reviewNote': reviewNote,
  };
}

/// 市场查询参数。
///
/// 把搜索、分类、分页参数聚合成一个值对象，避免 service 方法签名随参数
/// 增加而膨胀。后端实现可自由扩展字段而不破坏调用方。
class MarketQuery {
  /// 分类筛选，空字符串表示不限。
  final String category;

  /// 搜索关键词。
  final String query;

  /// 页码，从 1 开始。
  final int page;

  /// 每页条数。
  final int pageSize;

  /// 创建市场查询实例。
  const MarketQuery({
    this.category = '',
    this.query = '',
    this.page = 1,
    this.pageSize = 20,
  });

  /// 当前查询是否为默认空查询（无分类、无关键词、第一页）。
  bool get isDefault =>
      category.isEmpty && query.isEmpty && page == 1 && pageSize == 20;
}

/// 市场查询结果。
class MarketQueryResult {
  /// 当前页的插件条目。
  final List<MarketPluginEntry> entries;

  /// 是否还有更多页可加载。
  final bool hasMore;

  /// 创建市场查询结果实例。
  const MarketQueryResult({required this.entries, required this.hasMore});
}

/// 后端尚未连接或市场不可用时的统一异常。
class MarketUnavailableException implements Exception {
  final String message;
  const MarketUnavailableException(this.message);

  @override
  String toString() => 'MarketUnavailableException: $message';
}
