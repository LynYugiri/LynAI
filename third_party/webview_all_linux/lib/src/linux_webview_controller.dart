import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as path;
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

@immutable
class LinuxWebViewControllerCreationParams
    extends PlatformWebViewControllerCreationParams {
  const LinuxWebViewControllerCreationParams();

  const LinuxWebViewControllerCreationParams.fromPlatformWebViewControllerCreationParams(
    PlatformWebViewControllerCreationParams params,
  );
}

@immutable
class LinuxWebViewWidgetCreationParams
    extends PlatformWebViewWidgetCreationParams {
  const LinuxWebViewWidgetCreationParams({
    super.key,
    required super.controller,
    super.layoutDirection,
    super.gestureRecognizers,
  });

  LinuxWebViewWidgetCreationParams.fromPlatformWebViewWidgetCreationParams(
    PlatformWebViewWidgetCreationParams params,
  ) : this(
        key: params.key,
        controller: params.controller,
        layoutDirection: params.layoutDirection,
        gestureRecognizers: params.gestureRecognizers,
      );
}

@immutable
class LinuxNavigationDelegateCreationParams
    extends PlatformNavigationDelegateCreationParams {
  const LinuxNavigationDelegateCreationParams();

  const LinuxNavigationDelegateCreationParams.fromPlatformNavigationDelegateCreationParams(
    PlatformNavigationDelegateCreationParams params,
  );
}

class LinuxWebViewController extends PlatformWebViewController {
  LinuxWebViewController(PlatformWebViewControllerCreationParams params)
    : super.implementation(
        params is LinuxWebViewControllerCreationParams
            ? params
            : LinuxWebViewControllerCreationParams.fromPlatformWebViewControllerCreationParams(
                params,
              ),
      ) {
    _readyFuture = _initialize();
  }

  static const MethodChannel rootChannel = MethodChannel(
    'plugins.moluo/webview_all_linux',
  );

  Future<void>? _readyFuture;
  MethodChannel? _channel;
  EventChannel? _eventChannel;
  StreamSubscription<dynamic>? _eventSubscription;

  LinuxNavigationDelegate? _navigationDelegate;
  final Map<String, JavaScriptChannelParams> _javaScriptChannels =
      <String, JavaScriptChannelParams>{};

  String? _currentUrl;
  String? _title;
  String? _userAgent;
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _disposed = false;

  void Function(JavaScriptConsoleMessage consoleMessage)? _onConsoleMessage;
  void Function(ScrollPositionChange scrollPositionChange)?
  _onScrollPositionChange;
  void Function(PlatformWebViewPermissionRequest request)? _onPermissionRequest;
  Future<void> Function(JavaScriptAlertDialogRequest request)?
  _onJavaScriptAlertDialog;
  Future<bool> Function(JavaScriptConfirmDialogRequest request)?
  _onJavaScriptConfirmDialog;
  Future<String> Function(JavaScriptTextInputDialogRequest request)?
  _onJavaScriptTextInputDialog;

  Future<void> _initialize() async {
    final int id =
        await rootChannel.invokeMethod<int>('createWebView') ??
        (throw StateError('Failed to create Linux WebView instance.'));
    _channel = MethodChannel('plugins.moluo/webview_all_linux/$id');
    _eventChannel = EventChannel('plugins.moluo/webview_all_linux/$id/events');
    _eventSubscription = _eventChannel!.receiveBroadcastStream().listen(
      _handleEvent,
      onError: (_) {},
    );
  }

  Future<void> _ensureReady() async {
    await _readyFuture;
    if (_disposed) {
      throw StateError(
        'This LinuxWebViewController has already been disposed.',
      );
    }
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    await _ensureReady();
    return _channel!.invokeMethod<T>(method, arguments);
  }

  void _handleEvent(dynamic event) {
    if (event is! Map) {
      return;
    }

    final String? type = event['type'] as String?;
    switch (type) {
      case 'urlChanged':
        final String url = '${event['url'] ?? ''}';
        _currentUrl = url;
        _navigationDelegate?._onUrlChange?.call(UrlChange(url: url));
        break;
      case 'pageStarted':
        final String url = '${event['url'] ?? ''}';
        _currentUrl = url;
        _navigationDelegate?._onPageStarted?.call(url);
        break;
      case 'pageFinished':
        final String url = '${event['url'] ?? ''}';
        _currentUrl = url;
        _navigationDelegate?._onProgress?.call(100);
        _navigationDelegate?._onPageFinished?.call(url);
        break;
      case 'progress':
        _navigationDelegate?._onProgress?.call(
          (event['progress'] as num?)?.round() ?? 0,
        );
        break;
      case 'historyChanged':
        _canGoBack = event['canGoBack'] == true;
        _canGoForward = event['canGoForward'] == true;
        break;
      case 'titleChanged':
        _title = event['title'] as String?;
        break;
      case 'webResourceError':
        _navigationDelegate?._onWebResourceError?.call(
          LinuxWebResourceError.fromMap(event),
        );
        break;
      case 'httpError':
        final callback = _navigationDelegate?._onHttpError;
        if (callback != null) {
          callback(
            HttpResponseError(
              response: WebResourceResponse(
                uri: Uri.tryParse('${event['url'] ?? ''}'),
                statusCode: (event['statusCode'] as num?)?.toInt() ?? 0,
              ),
            ),
          );
        }
        break;
      case 'javaScriptChannelMessage':
        final String name = '${event['channelName'] ?? ''}';
        final JavaScriptChannelParams? params = _javaScriptChannels[name];
        if (params != null) {
          params.onMessageReceived(
            JavaScriptMessage(message: '${event['message'] ?? ''}'),
          );
        }
        break;
      case 'consoleMessage':
        final callback = _onConsoleMessage;
        if (callback != null) {
          callback(
            JavaScriptConsoleMessage(
              level: _parseJavaScriptLogLevel(event['level'] as String?),
              message: '${event['message'] ?? ''}',
            ),
          );
        }
        break;
      case 'scrollPositionChange':
        final callback = _onScrollPositionChange;
        if (callback != null) {
          callback(
            ScrollPositionChange(
              (event['x'] as num?)?.toDouble() ?? 0,
              (event['y'] as num?)?.toDouble() ?? 0,
            ),
          );
        }
        break;
      case 'navigationRequest':
        _handleNavigationRequestEvent(event);
        break;
      case 'httpAuthRequest':
        unawaited(_handleHttpAuthRequestEvent(event));
        break;
      case 'sslAuthError':
        unawaited(_handleSslAuthErrorEvent(event));
        break;
      case 'permissionRequest':
        unawaited(_handlePermissionRequestEvent(event));
        break;
      case 'javaScriptDialog':
        unawaited(_handleJavaScriptDialogEvent(event));
        break;
    }
  }

  Future<void> _handleNavigationRequestEvent(
    Map<dynamic, dynamic> event,
  ) async {
    final int requestId = (event['requestId'] as num?)?.toInt() ?? -1;
    final callback = _navigationDelegate?._onNavigationRequest;
    bool allow = true;
    if (callback != null) {
      final NavigationDecision decision = await callback(
        NavigationRequest(
          url: '${event['url'] ?? ''}',
          isMainFrame: event['isMainFrame'] != false,
        ),
      );
      allow = decision == NavigationDecision.navigate;
    }

    await _invoke<void>('completeNavigationRequest', <String, Object?>{
      'requestId': requestId,
      'allow': allow,
    });
  }

  Future<void> _handleHttpAuthRequestEvent(Map<dynamic, dynamic> event) async {
    final int requestId = (event['requestId'] as num?)?.toInt() ?? -1;
    final callback = _navigationDelegate?._onHttpAuthRequest;
    if (callback == null) {
      await _invoke<void>('completeHttpAuthRequest', <String, Object?>{
        'requestId': requestId,
        'action': 'cancel',
      });
      return;
    }

    callback(
      HttpAuthRequest(
        host: '${event['host'] ?? ''}',
        realm: event['realm'] as String?,
        onProceed: (WebViewCredential credential) {
          unawaited(
            _invoke<void>('completeHttpAuthRequest', <String, Object?>{
              'requestId': requestId,
              'action': 'proceed',
              'user': credential.user,
              'password': credential.password,
            }),
          );
        },
        onCancel: () {
          unawaited(
            _invoke<void>('completeHttpAuthRequest', <String, Object?>{
              'requestId': requestId,
              'action': 'cancel',
            }),
          );
        },
      ),
    );
  }

  Future<void> _handleSslAuthErrorEvent(Map<dynamic, dynamic> event) async {
    final int requestId = (event['requestId'] as num?)?.toInt() ?? -1;
    final callback = _navigationDelegate?._onSslAuthError;
    if (callback == null) {
      await _invoke<void>('completeSslAuthError', <String, Object?>{
        'requestId': requestId,
        'proceed': false,
      });
      return;
    }

    callback(
      LinuxPlatformSslAuthError(
        description: '${event['description'] ?? 'TLS certificate error'}',
        onProceed: () {
          return _invoke<void>('completeSslAuthError', <String, Object?>{
            'requestId': requestId,
            'proceed': true,
          });
        },
        onCancel: () {
          return _invoke<void>('completeSslAuthError', <String, Object?>{
            'requestId': requestId,
            'proceed': false,
          });
        },
      ),
    );
  }

  Future<void> _handlePermissionRequestEvent(
    Map<dynamic, dynamic> event,
  ) async {
    final int requestId = (event['requestId'] as num?)?.toInt() ?? -1;
    final callback = _onPermissionRequest;
    if (callback == null) {
      await _invoke<void>('completePermissionRequest', <String, Object?>{
        'requestId': requestId,
        'grant': false,
      });
      return;
    }

    final List<Object?> rawTypes =
        (event['types'] as List<Object?>?) ?? const <Object?>[];
    callback(
      LinuxPlatformWebViewPermissionRequest(
        types: rawTypes
            .map((Object? type) => _parsePermissionType(type as String?))
            .whereType<WebViewPermissionResourceType>()
            .toSet(),
        onGrant: () {
          return _invoke<void>('completePermissionRequest', <String, Object?>{
            'requestId': requestId,
            'grant': true,
          });
        },
        onDeny: () {
          return _invoke<void>('completePermissionRequest', <String, Object?>{
            'requestId': requestId,
            'grant': false,
          });
        },
      ),
    );
  }

  Future<void> _handleJavaScriptDialogEvent(Map<dynamic, dynamic> event) async {
    final int requestId = (event['requestId'] as num?)?.toInt() ?? -1;
    final String dialogType = '${event['dialogType'] ?? ''}';
    final String message = '${event['message'] ?? ''}';
    final String url = '${event['url'] ?? ''}';
    try {
      switch (dialogType) {
        case 'alert':
          final callback = _onJavaScriptAlertDialog;
          if (callback == null) {
            await _completeJavaScriptDialog(requestId, action: 'confirm');
            return;
          }
          await callback(
            JavaScriptAlertDialogRequest(message: message, url: url),
          );
          await _completeJavaScriptDialog(requestId, action: 'confirm');
          return;
        case 'confirm':
        case 'beforeUnloadConfirm':
          final callback = _onJavaScriptConfirmDialog;
          if (callback == null) {
            await _completeJavaScriptDialog(requestId, action: 'confirm');
            return;
          }
          final bool confirmed = await callback(
            JavaScriptConfirmDialogRequest(message: message, url: url),
          );
          await _completeJavaScriptDialog(
            requestId,
            action: confirmed ? 'confirm' : 'cancel',
          );
          return;
        case 'prompt':
          final callback = _onJavaScriptTextInputDialog;
          if (callback == null) {
            await _completeJavaScriptDialog(
              requestId,
              action: 'confirm',
              text: (event['defaultText'] as String?) ?? '',
            );
            return;
          }
          final String text = await callback(
            JavaScriptTextInputDialogRequest(
              message: message,
              url: url,
              defaultText: event['defaultText'] as String?,
            ),
          );
          await _completeJavaScriptDialog(
            requestId,
            action: 'confirm',
            text: text,
          );
          return;
      }
    } catch (_) {
      await _completeJavaScriptDialog(requestId, action: 'cancel');
      return;
    }

    await _completeJavaScriptDialog(requestId, action: 'confirm');
  }

  Future<void> _completeJavaScriptDialog(
    int requestId, {
    required String action,
    String? text,
  }) {
    return _invoke<void>('completeJavaScriptDialog', <String, Object?>{
      'requestId': requestId,
      'action': action,
      'text': text,
    });
  }

  JavaScriptLogLevel _parseJavaScriptLogLevel(String? level) {
    switch (level) {
      case 'debug':
        return JavaScriptLogLevel.debug;
      case 'error':
        return JavaScriptLogLevel.error;
      case 'info':
        return JavaScriptLogLevel.info;
      case 'warning':
        return JavaScriptLogLevel.warning;
      default:
        return JavaScriptLogLevel.log;
    }
  }

  @override
  Future<void> loadFile(String absoluteFilePath) async {
    final File file = File(absoluteFilePath);
    if (!file.existsSync()) {
      throw ArgumentError.value(
        absoluteFilePath,
        'absoluteFilePath',
        'File does not exist.',
      );
    }

    await _invoke<void>('loadFile', <String, Object?>{
      'path': file.absolute.path,
    });
  }

  @override
  Future<void> loadFlutterAsset(String key) async {
    final String assetPath = _resolveFlutterAssetPath(key);
    final File file = File(assetPath);
    if (!file.existsSync()) {
      throw ArgumentError.value(key, 'key', 'Asset for key "$key" not found.');
    }

    await loadFile(assetPath);
  }

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) {
    return _invoke<void>('loadHtmlString', <String, Object?>{
      'html': html,
      'baseUrl': baseUrl,
    });
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    if (!params.uri.hasScheme) {
      throw ArgumentError(
        'LoadRequestParams#uri is required to have a scheme.',
      );
    }

    if (params.method != LoadRequestMethod.get ||
        (params.body != null && params.body!.isNotEmpty)) {
      throw UnsupportedError(
        'webview_all_linux currently supports GET requests and custom headers, '
        'but does not yet support request bodies.',
      );
    }

    await _invoke<void>('loadRequest', <String, Object?>{
      'url': params.uri.toString(),
      'headers': params.headers,
    });
  }

  @override
  Future<String?> currentUrl() async {
    await _ensureReady();
    return _currentUrl ?? await _channel!.invokeMethod<String>('currentUrl');
  }

  @override
  Future<bool> canGoBack() async {
    await _ensureReady();
    return (await _channel!.invokeMethod<bool>('canGoBack')) ?? _canGoBack;
  }

  @override
  Future<bool> canGoForward() async {
    await _ensureReady();
    return (await _channel!.invokeMethod<bool>('canGoForward')) ??
        _canGoForward;
  }

  @override
  Future<void> goBack() => _invoke<void>('goBack');

  @override
  Future<void> goForward() => _invoke<void>('goForward');

  @override
  Future<void> reload() => _invoke<void>('reload');

  @override
  Future<void> clearCache() => _invoke<void>('clearCache');

  @override
  Future<void> clearLocalStorage() => _invoke<void>('clearLocalStorage');

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    _navigationDelegate = handler as LinuxNavigationDelegate;
  }

  @override
  Future<void> runJavaScript(String javaScript) {
    return _invoke<void>('runJavaScript', <String, Object?>{
      'script': javaScript,
    });
  }

  @override
  Future<Object> runJavaScriptReturningResult(String javaScript) async {
    final Object? result = await _invoke<Object>(
      'runJavaScriptReturningResult',
      <String, Object?>{'script': javaScript},
    );

    if (result == null) {
      throw ArgumentError(
        'The JavaScript returned `null` or `undefined`, which is unsupported.',
      );
    }

    if (result case final Map<Object?, Object?> map
        when map['__json__'] is String) {
      final Object? decoded = jsonDecode(map['__json__']! as String);
      if (decoded == null) {
        throw ArgumentError(
          'The JavaScript returned `null` or `undefined`, which is unsupported.',
        );
      }
      return decoded;
    }

    return result;
  }

  @override
  Future<void> addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
  ) async {
    final String name = javaScriptChannelParams.name;
    if (_javaScriptChannels.containsKey(name)) {
      throw ArgumentError(
        'A JavaScriptChannel with name `$name` already exists.',
      );
    }

    _javaScriptChannels[name] = javaScriptChannelParams;
    await _invoke<void>('addJavaScriptChannel', <String, Object?>{
      'name': name,
    });
  }

  @override
  Future<void> removeJavaScriptChannel(String javaScriptChannelName) async {
    _javaScriptChannels.remove(javaScriptChannelName);
    await _invoke<void>('removeJavaScriptChannel', <String, Object?>{
      'name': javaScriptChannelName,
    });
  }

  @override
  Future<String?> getTitle() async {
    await _ensureReady();
    return _title ?? await _channel!.invokeMethod<String>('getTitle');
  }

  @override
  Future<void> scrollTo(int x, int y) {
    return _invoke<void>('scrollTo', <String, Object?>{'x': x, 'y': y});
  }

  @override
  Future<void> scrollBy(int x, int y) {
    return _invoke<void>('scrollBy', <String, Object?>{'x': x, 'y': y});
  }

  @override
  Future<void> setVerticalScrollBarEnabled(bool enabled) {
    return _invoke<void>('setVerticalScrollBarEnabled', <String, Object?>{
      'enabled': enabled,
    });
  }

  @override
  Future<void> setHorizontalScrollBarEnabled(bool enabled) {
    return _invoke<void>('setHorizontalScrollBarEnabled', <String, Object?>{
      'enabled': enabled,
    });
  }

  @override
  bool supportsSetScrollBarsEnabled() => true;

  @override
  Future<Offset> getScrollPosition() async {
    final Map<Object?, Object?>? offset = await _invoke<Map<Object?, Object?>>(
      'getScrollPosition',
    );
    return Offset(
      (offset?['x'] as num?)?.toDouble() ?? 0,
      (offset?['y'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  Future<void> enableZoom(bool enabled) {
    return _invoke<void>('enableZoom', <String, Object?>{'enabled': enabled});
  }

  @override
  Future<void> setBackgroundColor(Color color) {
    return _invoke<void>('setBackgroundColor', <String, Object?>{
      'r': color.r,
      'g': color.g,
      'b': color.b,
      'a': color.a,
    });
  }

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) {
    return _invoke<void>('setJavaScriptMode', <String, Object?>{
      'enabled': javaScriptMode == JavaScriptMode.unrestricted,
    });
  }

  @override
  Future<void> setUserAgent(String? userAgent) async {
    _userAgent = userAgent;
    await _invoke<void>('setUserAgent', <String, Object?>{
      'userAgent': userAgent,
    });
  }

  @override
  Future<String?> getUserAgent() async {
    await _ensureReady();
    return _userAgent ?? await _channel!.invokeMethod<String>('getUserAgent');
  }

  @override
  Future<void> setOnPlatformPermissionRequest(
    void Function(PlatformWebViewPermissionRequest request) onPermissionRequest,
  ) async {
    _onPermissionRequest = onPermissionRequest;
  }

  @override
  Future<void> setOnConsoleMessage(
    void Function(JavaScriptConsoleMessage consoleMessage) onConsoleMessage,
  ) async {
    _onConsoleMessage = onConsoleMessage;
    await _invoke<void>('setOnConsoleMessage', <String, Object?>{
      'enabled': true,
    });
  }

  @override
  Future<void> setOnScrollPositionChange(
    void Function(ScrollPositionChange scrollPositionChange)?
    onScrollPositionChange,
  ) async {
    _onScrollPositionChange = onScrollPositionChange;
    await _invoke<void>('setOnScrollPositionChange', <String, Object?>{
      'enabled': onScrollPositionChange != null,
    });
  }

  @override
  Future<void> setOnJavaScriptAlertDialog(
    Future<void> Function(JavaScriptAlertDialogRequest request)
    onJavaScriptAlertDialog,
  ) async {
    _onJavaScriptAlertDialog = onJavaScriptAlertDialog;
  }

  @override
  Future<void> setOnJavaScriptConfirmDialog(
    Future<bool> Function(JavaScriptConfirmDialogRequest request)
    onJavaScriptConfirmDialog,
  ) async {
    _onJavaScriptConfirmDialog = onJavaScriptConfirmDialog;
  }

  @override
  Future<void> setOnJavaScriptTextInputDialog(
    Future<String> Function(JavaScriptTextInputDialogRequest request)
    onJavaScriptTextInputDialog,
  ) async {
    _onJavaScriptTextInputDialog = onJavaScriptTextInputDialog;
  }

  @override
  Future<void> setOverScrollMode(WebViewOverScrollMode mode) async {
    if (mode == WebViewOverScrollMode.never) {
      await runJavaScript('''
        document.documentElement.style.overscrollBehavior = 'none';
        document.body.style.overscrollBehavior = 'none';
      ''');
    }
  }

  Future<void> setFrame(Rect rect, {required bool visible}) {
    return _invoke<void>('setFrame', <String, Object?>{
      'x': rect.left,
      'y': rect.top,
      'width': rect.width,
      'height': rect.height,
      'visible': visible,
    });
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _eventSubscription?.cancel();
    if (_channel != null) {
      try {
        await _channel!.invokeMethod<void>('dispose');
      } catch (_) {
        // Best effort during shutdown.
      }
    }
  }

  String _resolveFlutterAssetPath(String key) {
    return path.joinAll(<String>[
      path.dirname(Platform.resolvedExecutable),
      'data',
      'flutter_assets',
      ...key.split('/'),
    ]);
  }

  WebViewPermissionResourceType? _parsePermissionType(String? type) {
    switch (type) {
      case 'camera':
        return WebViewPermissionResourceType.camera;
      case 'microphone':
        return WebViewPermissionResourceType.microphone;
    }
    return null;
  }
}

class LinuxWebViewWidget extends PlatformWebViewWidget {
  LinuxWebViewWidget(PlatformWebViewWidgetCreationParams params)
    : super.implementation(
        params is LinuxWebViewWidgetCreationParams
            ? params
            : LinuxWebViewWidgetCreationParams.fromPlatformWebViewWidgetCreationParams(
                params,
              ),
      );

  @override
  Widget build(BuildContext context) {
    final LinuxWebViewController controller =
        params.controller as LinuxWebViewController;
    return _LinuxPlatformWebView(controller: controller, key: params.key);
  }
}

class _LinuxPlatformWebView extends StatefulWidget {
  const _LinuxPlatformWebView({super.key, required this.controller});

  final LinuxWebViewController controller;

  @override
  State<_LinuxPlatformWebView> createState() => _LinuxPlatformWebViewState();
}

class _LinuxPlatformWebViewState extends State<_LinuxPlatformWebView>
    with WidgetsBindingObserver {
  Rect _lastRect = Rect.zero;
  bool _attached = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _pushRect(_lastRect, visible: _attached);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.setFrame(Rect.zero, visible: false);
    super.dispose();
  }

  void _pushRect(Rect rect, {required bool visible}) {
    _lastRect = rect;
    _attached = visible;
    unawaited(widget.controller.setFrame(rect, visible: visible));
  }

  void _handlePaint(Rect rect) {
    if (!_attached || rect != _lastRect) {
      _pushRect(rect, visible: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _LinuxGeometryObserver(
      onPaint: _handlePaint,
      onDetached: () => _pushRect(Rect.zero, visible: false),
      child: const SizedBox.expand(),
    );
  }
}

class _LinuxGeometryObserver extends SingleChildRenderObjectWidget {
  const _LinuxGeometryObserver({
    required this.onPaint,
    required this.onDetached,
    required Widget child,
  }) : super(child: child);

  final ValueChanged<Rect> onPaint;
  final VoidCallback onDetached;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _LinuxGeometryRenderBox(onPaint: onPaint, onDetached: onDetached);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _LinuxGeometryRenderBox renderObject,
  ) {
    renderObject
      ..onPaint = onPaint
      ..onDetached = onDetached;
  }
}

class _LinuxGeometryRenderBox extends RenderProxyBox {
  _LinuxGeometryRenderBox({
    required ValueChanged<Rect> onPaint,
    required VoidCallback onDetached,
  }) : _onPaint = onPaint,
       _onDetached = onDetached;

  ValueChanged<Rect> _onPaint;
  VoidCallback _onDetached;

  set onPaint(ValueChanged<Rect> value) {
    _onPaint = value;
  }

  set onDetached(VoidCallback value) {
    _onDetached = value;
  }

  @override
  void detach() {
    _onDetached();
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final Matrix4 transform = getTransformTo(null);
    final Offset topLeft = MatrixUtils.transformPoint(transform, Offset.zero);
    final Offset bottomRight = MatrixUtils.transformPoint(
      transform,
      Offset(size.width, size.height),
    );
    final Rect rect = Rect.fromLTRB(
      math.min(topLeft.dx, bottomRight.dx),
      math.min(topLeft.dy, bottomRight.dy),
      math.max(topLeft.dx, bottomRight.dx),
      math.max(topLeft.dy, bottomRight.dy),
    );
    _onPaint(rect);
  }
}

class LinuxNavigationDelegate extends PlatformNavigationDelegate {
  LinuxNavigationDelegate(PlatformNavigationDelegateCreationParams params)
    : super.implementation(
        params is LinuxNavigationDelegateCreationParams
            ? params
            : LinuxNavigationDelegateCreationParams.fromPlatformNavigationDelegateCreationParams(
                params,
              ),
      );

  PageEventCallback? _onPageFinished;
  PageEventCallback? _onPageStarted;
  ProgressCallback? _onProgress;
  WebResourceErrorCallback? _onWebResourceError;
  NavigationRequestCallback? _onNavigationRequest;
  UrlChangeCallback? _onUrlChange;
  HttpResponseErrorCallback? _onHttpError;
  HttpAuthRequestCallback? _onHttpAuthRequest;
  SslAuthErrorCallback? _onSslAuthError;

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {
    _onNavigationRequest = onNavigationRequest;
  }

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {
    _onPageStarted = onPageStarted;
  }

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {
    _onPageFinished = onPageFinished;
  }

  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback onHttpError) async {
    _onHttpError = onHttpError;
  }

  @override
  Future<void> setOnProgress(ProgressCallback onProgress) async {
    _onProgress = onProgress;
  }

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) async {
    _onWebResourceError = onWebResourceError;
  }

  @override
  Future<void> setOnUrlChange(UrlChangeCallback onUrlChange) async {
    _onUrlChange = onUrlChange;
  }

  @override
  Future<void> setOnHttpAuthRequest(
    HttpAuthRequestCallback onHttpAuthRequest,
  ) async {
    _onHttpAuthRequest = onHttpAuthRequest;
  }

  @override
  Future<void> setOnSSlAuthError(SslAuthErrorCallback onSslAuthError) async {
    _onSslAuthError = onSslAuthError;
  }
}

class LinuxPlatformWebViewPermissionRequest
    extends PlatformWebViewPermissionRequest {
  LinuxPlatformWebViewPermissionRequest({
    required super.types,
    required Future<void> Function() onGrant,
    required Future<void> Function() onDeny,
  }) : _onGrant = onGrant,
       _onDeny = onDeny;

  final Future<void> Function() _onGrant;
  final Future<void> Function() _onDeny;

  @override
  Future<void> grant() => _onGrant();

  @override
  Future<void> deny() => _onDeny();
}

class LinuxPlatformSslAuthError extends PlatformSslAuthError {
  LinuxPlatformSslAuthError({
    required String description,
    required Future<void> Function() onProceed,
    required Future<void> Function() onCancel,
  }) : _onProceed = onProceed,
       _onCancel = onCancel,
       super(certificate: const X509Certificate(), description: description);

  final Future<void> Function() _onProceed;
  final Future<void> Function() _onCancel;

  @override
  Future<void> proceed() => _onProceed();

  @override
  Future<void> cancel() => _onCancel();
}

class LinuxWebResourceError extends WebResourceError {
  LinuxWebResourceError({
    required super.errorCode,
    required super.description,
    required super.errorType,
    super.isForMainFrame,
    super.url,
  });

  factory LinuxWebResourceError.fromMap(Map<dynamic, dynamic> map) {
    return LinuxWebResourceError(
      errorCode: (map['errorCode'] as num?)?.toInt() ?? -1,
      description: '${map['description'] ?? 'Navigation failed'}',
      errorType: _mapErrorType((map['errorType'] as String?) ?? 'unknown'),
      isForMainFrame: map['isForMainFrame'] != false,
      url: map['url'] as String?,
    );
  }

  static WebResourceErrorType _mapErrorType(String type) {
    switch (type) {
      case 'authentication':
        return WebResourceErrorType.authentication;
      case 'badUrl':
        return WebResourceErrorType.badUrl;
      case 'connect':
        return WebResourceErrorType.connect;
      case 'failedSslHandshake':
        return WebResourceErrorType.failedSslHandshake;
      case 'file':
        return WebResourceErrorType.file;
      case 'fileNotFound':
        return WebResourceErrorType.fileNotFound;
      case 'hostLookup':
        return WebResourceErrorType.hostLookup;
      case 'io':
        return WebResourceErrorType.io;
      case 'proxyAuthentication':
        return WebResourceErrorType.proxyAuthentication;
      case 'redirectLoop':
        return WebResourceErrorType.redirectLoop;
      case 'timeout':
        return WebResourceErrorType.timeout;
      case 'tooManyRequests':
        return WebResourceErrorType.tooManyRequests;
      case 'unsafeResource':
        return WebResourceErrorType.unsafeResource;
      case 'unsupportedScheme':
        return WebResourceErrorType.unsupportedScheme;
      case 'webContentProcessTerminated':
        return WebResourceErrorType.webContentProcessTerminated;
      case 'webViewInvalidated':
        return WebResourceErrorType.webViewInvalidated;
      default:
        return WebResourceErrorType.unknown;
    }
  }
}
