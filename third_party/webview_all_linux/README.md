# webview_all_linux

`webview_all_linux` is the Linux implementation used by [`webview_all`](https://github.com/moluopro/webview_all).
It embeds `WebKitGTK 4.1` into a Flutter Linux app and exposes the same platform-interface surface used by `webview_flutter`.

## What It Provides

This plugin is intended to make `webview_all` work on Linux with an API shape close to `webview_flutter`.

Currently supported:

- `WebViewWidget` embedding inside Flutter Linux windows
- Page loading: URL, local file, Flutter asset, HTML string
- Navigation: back, forward, reload, current URL, title, progress
- Navigation delegate callbacks
- JavaScript execution and JavaScript channels
- Cookie management
- HTTP auth callback
- TLS/SSL error callback
- JavaScript dialog callbacks: alert, confirm, prompt
- Permission request callback for media permissions
- Basic scroll position APIs
- Background color, JavaScript mode, user agent

## Integration

In normal use you do not need to depend on this package directly. Add `webview_all` and Linux will resolve to `webview_all_linux` automatically.

```yaml
dependencies:
  webview_all: ^0.9.3
```

If you are developing this package locally, use a path override in the consuming app:

```yaml
dependency_overrides:
  webview_all_linux:
    path: ../webview_all_linux
```

## Linux Requirements

This plugin depends on `WebKitGTK 4.1` and GTK 3 development files.

Typical Ubuntu packages:

```bash
sudo apt install libgtk-3-dev libwebkit2gtk-4.1-dev libsoup-3.0-dev
```

For better video and subtitle support in modern sites, these runtime packages are also recommended:

```bash
sudo apt install gstreamer1.0-plugins-bad gstreamer1.0-libav gstreamer1.0-plugins-ugly
```

## Linux Runner Setup

Linux apps may need one small runner change so `WebViewWidget` can be hosted in
a `GtkOverlay`.

Edit:

```text
linux/runner/my_application.cc
```

Add:

```cc
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}
```

Then replace the default runner part:

```cpp
  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  gtk_widget_show(GTK_WIDGET(window));

  FlView* view = fl_view_new(project);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
```

with:

```cpp
  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  gtk_widget_show(GTK_WIDGET(view));

  GtkWidget* overlay = gtk_overlay_new();
  gtk_widget_show(overlay);
  gtk_container_add(GTK_CONTAINER(overlay), GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), overlay);

  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb), self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
```

Do not move `FlView* view = fl_view_new(project);` above the `project`
initialization.

Optional but recommended:

```cc
gtk_widget_set_hexpand(GTK_WIDGET(view), TRUE);
gtk_widget_set_vexpand(GTK_WIDGET(view), TRUE);
```

The important part is:

```text
GtkWindow -> GtkOverlay -> FlView
```

## Example

```dart
import 'package:flutter/material.dart';
import 'package:webview_all/webview_all.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: WebPage());
  }
}

class WebPage extends StatefulWidget {
  const WebPage({super.key});

  @override
  State<WebPage> createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  late final WebViewController controller;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) => debugPrint('Loading $url'),
          onPageFinished: (String url) => debugPrint('Finished $url'),
          onWebResourceError: (WebResourceError error) {
            debugPrint('${error.errorCode}: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse('https://flutter.dev'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Linux WebView')),
      body: WebViewWidget(controller: controller),
    );
  }
}
```

## Current Limitations

- `loadRequest` currently supports `GET` requests and custom headers, but not request bodies.
- Permission mapping is currently focused on camera and microphone style requests.
- Some advanced platform-specific WebKit behaviors are approximated rather than being exact mobile-platform equivalents.
- Multimedia capability depends heavily on the host Linux system's GStreamer setup.

## Common Runtime Messages

You may see logs like these while developing:

- `Unable to load from the cursor theme`
  This usually comes from the desktop environment or cursor theme setup, not from the plugin.
- `WebKit wasn't able to find a WebVTT encoder`
  This indicates missing `gstreamer1.0-plugins-bad`; subtitles may be degraded.
- `GStreamer element h264parse not found`
  This indicates missing video codec plugins; some video playback may fail.
- `Sticky event misordering`
  This is typically a GStreamer/WebKit warning in the media pipeline, not a Flutter API failure by itself.

## Notes

- Linux support is implemented with native GTK overlay embedding.
- This package is designed for desktop Linux and is not intended for mobile Linux targets.
- If your app runs through `flutter run` but the terminal later reports `Lost connection to device`, verify whether the app window is still alive before treating it as a WebView crash.
