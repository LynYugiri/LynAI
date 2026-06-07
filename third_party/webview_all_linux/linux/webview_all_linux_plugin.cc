#include "include/webview_all_linux/webview_all_linux_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <libsoup/soup.h>
#include <webkit2/webkit2.h>

#include <cstring>

struct _WebviewAllLinuxPlugin {
  GObject parent_instance;

  FlPluginRegistrar* registrar;
  FlMethodChannel* root_channel;
  GtkOverlay* overlay;
  GHashTable* webviews;
  gint next_webview_id;
};

typedef struct {
  WebviewAllLinuxPlugin* plugin;
  gint id;
  WebKitUserContentManager* content_manager;
  WebKitWebView* web_view;
  FlMethodChannel* method_channel;
  FlEventChannel* event_channel;
  gboolean event_listening;
  GHashTable* pending_nav_decisions;
  GHashTable* pending_auth_requests;
  GHashTable* pending_permission_requests;
  GHashTable* pending_script_dialogs;
  GHashTable* pending_tls_errors;
  GHashTable* js_channel_signal_ids;
  GHashTable* js_channels;
  gint next_request_id;
  gboolean console_enabled;
  gboolean scroll_enabled;
  gint frame_x;
  gint frame_y;
  gint frame_width;
  gint frame_height;
  gboolean visible;
  double last_scroll_x;
  double last_scroll_y;
} LinuxWebView;

typedef struct {
  LinuxWebView* webview;
  gchar* name;
} JavaScriptChannelHandlerData;

typedef struct {
  GTlsCertificate* certificate;
  gchar* host;
  gchar* uri;
} PendingTlsError;

typedef struct {
  WebKitPolicyDecision* decision;
  gchar* uri;
  gboolean open_in_place;
} PendingNavigationDecision;

G_DEFINE_TYPE(WebviewAllLinuxPlugin,
              webview_all_linux_plugin,
              g_object_get_type())

static void update_flutter_view_input_region(WebviewAllLinuxPlugin* self);

static void queue_webview_overlay_redraw(GtkWidget* widget) {
  if (widget == nullptr) {
    return;
  }

  gtk_widget_queue_resize(widget);
  gtk_widget_queue_draw(widget);

  GtkWidget* parent = gtk_widget_get_parent(widget);
  if (parent != nullptr) {
    gtk_widget_queue_resize(parent);
    gtk_widget_queue_draw(parent);
  }

  GtkWidget* toplevel = gtk_widget_get_toplevel(widget);
  if (toplevel != nullptr && GTK_IS_WIDGET(toplevel)) {
    gtk_widget_queue_draw(toplevel);
  }
}

static FlMethodCodec* method_codec() {
  static FlStandardMethodCodec* codec = nullptr;
  if (codec == nullptr) {
    codec = fl_standard_method_codec_new();
  }
  return FL_METHOD_CODEC(codec);
}

static FlValue* map_lookup(FlValue* map, const gchar* key) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) {
    return nullptr;
  }
  return fl_value_lookup_string(map, key);
}

static const gchar* map_lookup_string(FlValue* map, const gchar* key) {
  FlValue* value = map_lookup(map, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    return nullptr;
  }
  return fl_value_get_string(value);
}

static gboolean map_lookup_bool(FlValue* map,
                                const gchar* key,
                                gboolean fallback) {
  FlValue* value = map_lookup(map, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_BOOL) {
    return fallback;
  }
  return fl_value_get_bool(value);
}

static double map_lookup_double(FlValue* map,
                                const gchar* key,
                                double fallback) {
  FlValue* value = map_lookup(map, key);
  if (value == nullptr) {
    return fallback;
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT) {
    return fl_value_get_float(value);
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_INT) {
    return static_cast<double>(fl_value_get_int(value));
  }
  return fallback;
}

static gint64 map_lookup_int(FlValue* map, const gchar* key, gint64 fallback) {
  FlValue* value = map_lookup(map, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_INT) {
    return fallback;
  }
  return fl_value_get_int(value);
}

static FlMethodResponse* success_response(FlValue* value = nullptr) {
  return FL_METHOD_RESPONSE(fl_method_success_response_new(value));
}

static FlMethodResponse* error_response(const gchar* code,
                                        const gchar* message) {
  return FL_METHOD_RESPONSE(
      fl_method_error_response_new(code, message, nullptr));
}

static void respond(FlMethodCall* method_call, FlMethodResponse* response) {
  GError* error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to send method response: %s",
              error != nullptr ? error->message : "unknown");
    g_clear_error(&error);
  }
}

static FlValue* make_event(const gchar* type) {
  FlValue* map = fl_value_new_map();
  fl_value_set_string_take(map, "type", fl_value_new_string(type));
  return map;
}

static const gchar* fl_value_to_string_or_null(FlValue* value) {
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    return nullptr;
  }
  return fl_value_get_string(value);
}

static void destroy_pending_tls_error(gpointer data) {
  PendingTlsError* error = static_cast<PendingTlsError*>(data);
  if (error == nullptr) {
    return;
  }
  g_clear_object(&error->certificate);
  g_free(error->host);
  g_free(error->uri);
  g_free(error);
}

static void destroy_pending_navigation_decision(gpointer data) {
  PendingNavigationDecision* pending =
      static_cast<PendingNavigationDecision*>(data);
  if (pending == nullptr) {
    return;
  }
  g_clear_object(&pending->decision);
  g_free(pending->uri);
  g_free(pending);
}

static void send_event(LinuxWebView* webview, FlValue* event) {
  if (!webview->event_listening) {
    fl_value_unref(event);
    return;
  }

  GError* error = nullptr;
  fl_event_channel_send(webview->event_channel, event, nullptr, &error);
  if (error != nullptr) {
    g_warning("Failed to send event: %s", error->message);
    g_clear_error(&error);
  }
  fl_value_unref(event);
}

static void flutter_view_size_allocate_cb(GtkWidget* widget,
                                          GtkAllocation* allocation,
                                          gpointer user_data) {
  update_flutter_view_input_region(
      static_cast<WebviewAllLinuxPlugin*>(user_data));
}

static GtkOverlay* ensure_overlay(WebviewAllLinuxPlugin* self) {
  if (self->overlay != nullptr) {
    return self->overlay;
  }

  FlView* view = fl_plugin_registrar_get_view(self->registrar);
  if (view == nullptr) {
    return nullptr;
  }

  GtkWidget* view_widget = GTK_WIDGET(view);
  GtkWidget* parent = gtk_widget_get_parent(view_widget);
  if (parent == nullptr) {
    return nullptr;
  }

  if (GTK_IS_OVERLAY(parent)) {
    self->overlay = GTK_OVERLAY(parent);
    g_signal_connect(view_widget, "size-allocate",
                     G_CALLBACK(flutter_view_size_allocate_cb), self);
    return self->overlay;
  }

  GtkWidget* toplevel = gtk_widget_get_toplevel(view_widget);
  const gboolean hide_toplevel =
      toplevel != nullptr && GTK_IS_WIDGET(toplevel) &&
      gtk_widget_get_visible(toplevel);
  if (hide_toplevel) {
    gtk_widget_hide(toplevel);
  }

  g_object_ref(view_widget);
  gtk_container_remove(GTK_CONTAINER(parent), view_widget);

  GtkWidget* overlay = gtk_overlay_new();
  g_object_set_data(G_OBJECT(overlay), "webview_all_linux_overlay",
                    GINT_TO_POINTER(1));
  gtk_widget_set_hexpand(overlay, TRUE);
  gtk_widget_set_vexpand(overlay, TRUE);
  gtk_container_add(GTK_CONTAINER(parent), overlay);
  gtk_widget_set_hexpand(view_widget, TRUE);
  gtk_widget_set_vexpand(view_widget, TRUE);
  gtk_container_add(GTK_CONTAINER(overlay), view_widget);
  gtk_widget_realize(overlay);
  gtk_widget_realize(view_widget);
  gtk_widget_show(overlay);
  gtk_widget_show(view_widget);
  gtk_widget_queue_resize(overlay);
  gtk_widget_queue_resize(parent);
  if (hide_toplevel) {
    gtk_widget_show(toplevel);
  }
  g_object_unref(view_widget);

  g_signal_connect(view_widget, "size-allocate",
                   G_CALLBACK(flutter_view_size_allocate_cb), self);

  self->overlay = GTK_OVERLAY(overlay);
  return self->overlay;
}

static void update_flutter_view_input_region(WebviewAllLinuxPlugin* self) {
  FlView* view = fl_plugin_registrar_get_view(self->registrar);
  if (view == nullptr) {
    return;
  }

  GtkWidget* view_widget = GTK_WIDGET(view);
  GdkWindow* parent_window = gtk_widget_get_parent_window(view_widget);
  if (parent_window == nullptr) {
    return;
  }
  const gint width = gtk_widget_get_allocated_width(view_widget);
  const gint height = gtk_widget_get_allocated_height(view_widget);
  if (width <= 0 || height <= 0) {
    return;
  }

  cairo_rectangle_int_t full_rect = {0, 0, width, height};
  cairo_region_t* region = cairo_region_create_rectangle(&full_rect);

  GHashTableIter iter;
  gpointer key = nullptr;
  gpointer value = nullptr;
  g_hash_table_iter_init(&iter, self->webviews);
  while (g_hash_table_iter_next(&iter, &key, &value)) {
    LinuxWebView* webview = static_cast<LinuxWebView*>(value);
    if (webview == nullptr || !webview->visible || webview->frame_width <= 0 ||
        webview->frame_height <= 0) {
      continue;
    }

    cairo_rectangle_int_t webview_rect = {
        webview->frame_x, webview->frame_y, webview->frame_width,
        webview->frame_height};
    cairo_region_subtract_rectangle(region, &webview_rect);
  }

  gdk_window_input_shape_combine_region(parent_window, region, 0, 0);
  cairo_region_destroy(region);
}

static FlValue* serialize_js_result(JSCValue* value) {
  if (value == nullptr || jsc_value_is_null(value) ||
      jsc_value_is_undefined(value)) {
    return fl_value_new_null();
  }
  if (jsc_value_is_boolean(value)) {
    return fl_value_new_bool(jsc_value_to_boolean(value));
  }
  if (jsc_value_is_number(value)) {
    return fl_value_new_float(jsc_value_to_double(value));
  }
  if (jsc_value_is_string(value)) {
    gchar* text = jsc_value_to_string(value);
    FlValue* result = fl_value_new_string(text);
    g_free(text);
    return result;
  }

  gchar* json = jsc_value_to_json(value, 0);
  if (json == nullptr) {
    return fl_value_new_null();
  }
  FlValue* wrapper = fl_value_new_map();
  fl_value_set_string_take(wrapper, "__json__", fl_value_new_string(json));
  g_free(json);
  return wrapper;
}

static void update_history(LinuxWebView* webview) {
  FlValue* event = make_event("historyChanged");
  fl_value_set_string_take(event, "canGoBack",
                           fl_value_new_bool(
                               webkit_web_view_can_go_back(webview->web_view)));
  fl_value_set_string_take(
      event, "canGoForward",
      fl_value_new_bool(webkit_web_view_can_go_forward(webview->web_view)));
  send_event(webview, event);
}

static void emit_url_change(LinuxWebView* webview) {
  const gchar* uri = webkit_web_view_get_uri(webview->web_view);
  if (uri == nullptr) {
    return;
  }
  FlValue* event = make_event("urlChanged");
  fl_value_set_string_take(event, "url", fl_value_new_string(uri));
  send_event(webview, event);
}

static void emit_title_change(LinuxWebView* webview) {
  const gchar* title = webkit_web_view_get_title(webview->web_view);
  if (title == nullptr) {
    return;
  }
  FlValue* event = make_event("titleChanged");
  fl_value_set_string_take(event, "title", fl_value_new_string(title));
  send_event(webview, event);
}

static const gchar* error_type_name_from_error(GError* error) {
  if (error == nullptr) {
    return "unknown";
  }
  switch (error->code) {
    case WEBKIT_NETWORK_ERROR_CANCELLED:
      return "unknown";
    case WEBKIT_NETWORK_ERROR_FILE_DOES_NOT_EXIST:
      return "fileNotFound";
    case WEBKIT_NETWORK_ERROR_UNKNOWN_PROTOCOL:
      return "unsupportedScheme";
    case WEBKIT_NETWORK_ERROR_FAILED:
      return "connect";
    case WEBKIT_POLICY_ERROR_CANNOT_SHOW_URI:
      return "unsupportedScheme";
    case WEBKIT_POLICY_ERROR_CANNOT_SHOW_MIME_TYPE:
      return "file";
    case WEBKIT_DOWNLOAD_ERROR_NETWORK:
      return "connect";
    default:
      return "unknown";
  }
}

static void emit_load_error(LinuxWebView* webview, GError* error,
                            const gchar* failing_url) {
  FlValue* event = make_event("webResourceError");
  fl_value_set_string_take(event, "description",
                           fl_value_new_string(error != nullptr
                                                   ? error->message
                                                   : "Navigation failed"));
  fl_value_set_string_take(
      event, "errorCode",
      fl_value_new_int(error != nullptr ? error->code : -1));
  fl_value_set_string_take(
      event, "errorType",
      fl_value_new_string(error_type_name_from_error(error)));
  fl_value_set_string_take(event, "isForMainFrame", fl_value_new_bool(true));
  if (failing_url != nullptr) {
    fl_value_set_string_take(event, "url", fl_value_new_string(failing_url));
  }
  send_event(webview, event);
}

static void evaluate_javascript(WebKitWebView* web_view,
                                const gchar* script,
                                FlMethodCall* method_call);

static void script_finished_cb(GObject* object,
                               GAsyncResult* result,
                               gpointer user_data) {
  FlMethodCall* method_call = FL_METHOD_CALL(user_data);
  GError* error = nullptr;
  JSCValue* value = webkit_web_view_evaluate_javascript_finish(
      WEBKIT_WEB_VIEW(object), result, &error);
  if (error != nullptr) {
    respond(method_call, error_response("javascript_error", error->message));
    g_clear_error(&error);
    g_object_unref(method_call);
    return;
  }

  FlValue* payload = fl_value_new_null();
  if (value != nullptr) {
    payload = serialize_js_result(value);
    g_object_unref(value);
  }

  respond(method_call, success_response(payload));
  g_object_unref(method_call);
}

static void add_cookie_finished_cb(GObject* object,
                                   GAsyncResult* result,
                                   gpointer user_data) {
  FlMethodCall* method_call = FL_METHOD_CALL(user_data);
  GError* error = nullptr;
  webkit_cookie_manager_add_cookie_finish(WEBKIT_COOKIE_MANAGER(object), result,
                                          &error);
  if (error != nullptr) {
    respond(method_call, error_response("cookie_error", error->message));
    g_clear_error(&error);
  } else {
    respond(method_call, success_response());
  }
  g_object_unref(method_call);
}

static void clear_cookies_finished_cb(GObject* object,
                                      GAsyncResult* result,
                                      gpointer user_data) {
  FlMethodCall* method_call = FL_METHOD_CALL(user_data);
  GError* error = nullptr;
  webkit_website_data_manager_clear_finish(
      WEBKIT_WEBSITE_DATA_MANAGER(object), result, &error);
  if (error != nullptr) {
    respond(method_call, error_response("cookie_error", error->message));
    g_clear_error(&error);
  } else {
    respond(method_call, success_response(fl_value_new_bool(true)));
  }
  g_object_unref(method_call);
}

static void get_cookies_finished_cb(GObject* object,
                                    GAsyncResult* result,
                                    gpointer user_data) {
  FlMethodCall* method_call = FL_METHOD_CALL(user_data);
  GError* error = nullptr;
  GList* cookies = webkit_cookie_manager_get_cookies_finish(
      WEBKIT_COOKIE_MANAGER(object), result, &error);
  if (error != nullptr) {
    respond(method_call, error_response("cookie_error", error->message));
    g_clear_error(&error);
    g_object_unref(method_call);
    return;
  }

  FlValue* list = fl_value_new_list();
  for (GList* item = cookies; item != nullptr; item = item->next) {
    SoupCookie* cookie = static_cast<SoupCookie*>(item->data);
    FlValue* map = fl_value_new_map();
    fl_value_set_string_take(
        map, "name",
        fl_value_new_string(soup_cookie_get_name(cookie) != nullptr
                                ? soup_cookie_get_name(cookie)
                                : ""));
    fl_value_set_string_take(
        map, "value",
        fl_value_new_string(soup_cookie_get_value(cookie) != nullptr
                                ? soup_cookie_get_value(cookie)
                                : ""));
    fl_value_set_string_take(
        map, "domain",
        fl_value_new_string(soup_cookie_get_domain(cookie) != nullptr
                                ? soup_cookie_get_domain(cookie)
                                : ""));
    fl_value_set_string_take(
        map, "path",
        fl_value_new_string(soup_cookie_get_path(cookie) != nullptr
                                ? soup_cookie_get_path(cookie)
                                : "/"));
    fl_value_append_take(list, map);
  }

  g_list_free_full(cookies, reinterpret_cast<GDestroyNotify>(soup_cookie_free));
  respond(method_call, success_response(list));
  g_object_unref(method_call);
}

static gint next_request_id(LinuxWebView* webview) {
  return webview->next_request_id++;
}

static gboolean decide_policy_cb(WebKitWebView* widget,
                                 WebKitPolicyDecision* decision,
                                 WebKitPolicyDecisionType type,
                                 gpointer user_data) {
  if (type != WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION &&
      type != WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION) {
    return FALSE;
  }

  LinuxWebView* webview = static_cast<LinuxWebView*>(user_data);
  WebKitNavigationPolicyDecision* navigation_decision =
      WEBKIT_NAVIGATION_POLICY_DECISION(decision);
  WebKitNavigationAction* navigation_action =
      webkit_navigation_policy_decision_get_navigation_action(
          navigation_decision);
  WebKitURIRequest* request =
      webkit_navigation_action_get_request(navigation_action);
  const gchar* uri = webkit_uri_request_get_uri(request);

  if (type == WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION &&
      (!webview->event_listening || uri == nullptr || *uri == '\0')) {
    if (uri != nullptr && *uri != '\0') {
      webkit_web_view_load_uri(widget, uri);
      webkit_policy_decision_ignore(decision);
      return TRUE;
    }
    return FALSE;
  }
  if (!webview->event_listening) {
    return FALSE;
  }

  gint request_id = next_request_id(webview);
  PendingNavigationDecision* pending = g_new0(PendingNavigationDecision, 1);
  pending->decision = WEBKIT_POLICY_DECISION(g_object_ref(decision));
  pending->uri = g_strdup(uri);
  pending->open_in_place =
      type == WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION;
  g_hash_table_insert(webview->pending_nav_decisions, GINT_TO_POINTER(request_id),
                      pending);

  FlValue* event = make_event("navigationRequest");
  fl_value_set_string_take(event, "requestId", fl_value_new_int(request_id));
  fl_value_set_string_take(event, "url",
                           fl_value_new_string(uri != nullptr ? uri : ""));
  fl_value_set_string_take(event, "isMainFrame", fl_value_new_bool(true));
  send_event(webview, event);
  return TRUE;
}

static void load_changed_cb(WebKitWebView* widget,
                            WebKitLoadEvent load_event,
                            gpointer user_data) {
  LinuxWebView* webview = static_cast<LinuxWebView*>(user_data);
  const gchar* uri = webkit_web_view_get_uri(widget);
  queue_webview_overlay_redraw(GTK_WIDGET(widget));
  switch (load_event) {
    case WEBKIT_LOAD_STARTED: {
      FlValue* event = make_event("pageStarted");
      fl_value_set_string_take(event, "url",
                               fl_value_new_string(uri != nullptr ? uri : ""));
      send_event(webview, event);
      break;
    }
    case WEBKIT_LOAD_FINISHED: {
      FlValue* event = make_event("pageFinished");
      fl_value_set_string_take(event, "url",
                               fl_value_new_string(uri != nullptr ? uri : ""));
      send_event(webview, event);
      break;
    }
    default:
      break;
  }
  emit_url_change(webview);
  update_history(webview);
}

static void notify_progress_cb(WebKitWebView* widget,
                               GParamSpec* pspec,
                               gpointer user_data) {
  LinuxWebView* webview = static_cast<LinuxWebView*>(user_data);
  FlValue* event = make_event("progress");
  fl_value_set_string_take(
      event, "progress",
      fl_value_new_int(static_cast<gint>(
          webkit_web_view_get_estimated_load_progress(widget) * 100.0)));
  send_event(webview, event);
}

static void notify_uri_cb(WebKitWebView* widget,
                          GParamSpec* pspec,
                          gpointer user_data) {
  emit_url_change(static_cast<LinuxWebView*>(user_data));
}

static void notify_title_cb(WebKitWebView* widget,
                            GParamSpec* pspec,
                            gpointer user_data) {
  emit_title_change(static_cast<LinuxWebView*>(user_data));
}

static gboolean load_failed_cb(WebKitWebView* widget,
                               WebKitLoadEvent load_event,
                               const gchar* failing_url,
                               GError* error,
                               gpointer user_data) {
  if (error != nullptr && error->domain == webkit_network_error_quark() &&
      error->code == WEBKIT_NETWORK_ERROR_CANCELLED) {
    return FALSE;
  }
  emit_load_error(static_cast<LinuxWebView*>(user_data), error, failing_url);
  return FALSE;
}

static gboolean authenticate_cb(WebKitWebView* widget,
                                WebKitAuthenticationRequest* request,
                                gpointer user_data) {
  LinuxWebView* webview = static_cast<LinuxWebView*>(user_data);
  if (!webview->event_listening) {
    return FALSE;
  }

  gint request_id = next_request_id(webview);
  g_hash_table_insert(webview->pending_auth_requests, GINT_TO_POINTER(request_id),
                      g_object_ref(request));

  FlValue* event = make_event("httpAuthRequest");
  fl_value_set_string_take(event, "requestId", fl_value_new_int(request_id));
  fl_value_set_string_take(
      event, "host",
      fl_value_new_string(webkit_authentication_request_get_host(request) !=
                                  nullptr
                              ? webkit_authentication_request_get_host(request)
                              : ""));
  const gchar* realm = webkit_authentication_request_get_realm(request);
  if (realm != nullptr) {
    fl_value_set_string_take(event, "realm", fl_value_new_string(realm));
  }
  send_event(webview, event);
  return TRUE;
}

static gboolean permission_request_cb(WebKitWebView* widget,
                                      WebKitPermissionRequest* request,
                                      gpointer user_data) {
  LinuxWebView* webview = static_cast<LinuxWebView*>(user_data);
  if (!webview->event_listening) {
    return FALSE;
  }

  gint request_id = next_request_id(webview);
  g_hash_table_insert(webview->pending_permission_requests,
                      GINT_TO_POINTER(request_id), g_object_ref(request));

  FlValue* event = make_event("permissionRequest");
  FlValue* types = fl_value_new_list();
  if (WEBKIT_IS_USER_MEDIA_PERMISSION_REQUEST(request)) {
    WebKitUserMediaPermissionRequest* media_request =
        WEBKIT_USER_MEDIA_PERMISSION_REQUEST(request);
    if (webkit_user_media_permission_is_for_video_device(media_request)) {
      fl_value_append_take(types, fl_value_new_string("camera"));
    }
    if (webkit_user_media_permission_is_for_audio_device(media_request)) {
      fl_value_append_take(types, fl_value_new_string("microphone"));
    }
  }
  fl_value_set_string_take(event, "requestId", fl_value_new_int(request_id));
  fl_value_set_string_take(event, "types", types);
  send_event(webview, event);
  return TRUE;
}

static const gchar* script_dialog_type_name(WebKitScriptDialogType type) {
  switch (type) {
    case WEBKIT_SCRIPT_DIALOG_ALERT:
      return "alert";
    case WEBKIT_SCRIPT_DIALOG_CONFIRM:
      return "confirm";
    case WEBKIT_SCRIPT_DIALOG_PROMPT:
      return "prompt";
    case WEBKIT_SCRIPT_DIALOG_BEFORE_UNLOAD_CONFIRM:
      return "beforeUnloadConfirm";
  }
  return "alert";
}

static gboolean script_dialog_cb(WebKitWebView* widget,
                                 WebKitScriptDialog* dialog,
                                 gpointer user_data) {
  LinuxWebView* webview = static_cast<LinuxWebView*>(user_data);
  if (!webview->event_listening) {
    return FALSE;
  }

  gint request_id = next_request_id(webview);
  g_hash_table_insert(webview->pending_script_dialogs,
                      GINT_TO_POINTER(request_id),
                      webkit_script_dialog_ref(dialog));

  FlValue* event = make_event("javaScriptDialog");
  fl_value_set_string_take(event, "requestId", fl_value_new_int(request_id));
  fl_value_set_string_take(
      event, "dialogType",
      fl_value_new_string(
          script_dialog_type_name(webkit_script_dialog_get_dialog_type(dialog))));
  fl_value_set_string_take(
      event, "message",
      fl_value_new_string(webkit_script_dialog_get_message(dialog) != nullptr
                              ? webkit_script_dialog_get_message(dialog)
                              : ""));
  const gchar* default_text =
      webkit_script_dialog_prompt_get_default_text(dialog);
  if (default_text != nullptr) {
    fl_value_set_string_take(event, "defaultText",
                             fl_value_new_string(default_text));
  }
  const gchar* uri = webkit_web_view_get_uri(widget);
  fl_value_set_string_take(event, "url",
                           fl_value_new_string(uri != nullptr ? uri : ""));
  send_event(webview, event);
  return TRUE;
}

static gchar* describe_tls_error(const gchar* uri,
                                 const gchar* host,
                                 GTlsCertificateFlags errors) {
  GString* description = g_string_new("TLS certificate error");
  if (host != nullptr && *host != '\0') {
    g_string_append_printf(description, " for %s", host);
  }
  if (uri != nullptr && *uri != '\0') {
    g_string_append_printf(description, " while loading %s", uri);
  }
  if (errors != 0) {
    g_string_append(description, ".");
  }
  if (errors & G_TLS_CERTIFICATE_UNKNOWN_CA) {
    g_string_append(description, " Unknown certificate authority.");
  }
  if (errors & G_TLS_CERTIFICATE_BAD_IDENTITY) {
    g_string_append(description, " Certificate does not match host.");
  }
  if (errors & G_TLS_CERTIFICATE_NOT_ACTIVATED) {
    g_string_append(description, " Certificate is not yet valid.");
  }
  if (errors & G_TLS_CERTIFICATE_EXPIRED) {
    g_string_append(description, " Certificate has expired.");
  }
  if (errors & G_TLS_CERTIFICATE_REVOKED) {
    g_string_append(description, " Certificate has been revoked.");
  }
  if (errors & G_TLS_CERTIFICATE_INSECURE) {
    g_string_append(description, " Certificate uses an insecure algorithm.");
  }
  if (errors & G_TLS_CERTIFICATE_GENERIC_ERROR) {
    g_string_append(description, " Certificate validation failed.");
  }
  return g_string_free(description, FALSE);
}

static gboolean load_failed_with_tls_errors_cb(WebKitWebView* widget,
                                               const gchar* failing_uri,
                                               GTlsCertificate* certificate,
                                               GTlsCertificateFlags errors,
                                               gpointer user_data) {
  LinuxWebView* webview = static_cast<LinuxWebView*>(user_data);
  if (!webview->event_listening) {
    return FALSE;
  }

  gchar* host = nullptr;
  if (failing_uri != nullptr) {
    GUri* uri = g_uri_parse(failing_uri, G_URI_FLAGS_NONE, nullptr);
    if (uri != nullptr) {
      host = g_strdup(g_uri_get_host(uri));
      g_uri_unref(uri);
    }
  }

  PendingTlsError* pending = g_new0(PendingTlsError, 1);
  pending->certificate =
      certificate != nullptr ? G_TLS_CERTIFICATE(g_object_ref(certificate))
                             : nullptr;
  pending->host = host;
  pending->uri = g_strdup(failing_uri);

  gint request_id = next_request_id(webview);
  g_hash_table_insert(webview->pending_tls_errors, GINT_TO_POINTER(request_id),
                      pending);

  FlValue* event = make_event("sslAuthError");
  fl_value_set_string_take(event, "requestId", fl_value_new_int(request_id));
  gchar* description = describe_tls_error(failing_uri, host, errors);
  fl_value_set_string_take(event, "description",
                           fl_value_new_string(description));
  g_free(description);
  if (failing_uri != nullptr) {
    fl_value_set_string_take(event, "url", fl_value_new_string(failing_uri));
  }
  send_event(webview, event);
  return TRUE;
}

static void console_message_received_cb(WebKitUserContentManager* manager,
                                        WebKitJavascriptResult* result,
                                        gpointer user_data) {
  LinuxWebView* webview = static_cast<LinuxWebView*>(user_data);
  if (!webview->console_enabled) {
    return;
  }

  JSCValue* js_value = webkit_javascript_result_get_js_value(result);
  gchar* text = jsc_value_to_string(js_value);
  if (text == nullptr) {
    return;
  }

  FlValue* event = make_event("consoleMessage");
  fl_value_set_string_take(event, "level", fl_value_new_string("log"));
  fl_value_set_string_take(event, "message", fl_value_new_string(text));
  send_event(webview, event);
  g_free(text);
}

static void scroll_message_received_cb(WebKitUserContentManager* manager,
                                       WebKitJavascriptResult* result,
                                       gpointer user_data) {
  LinuxWebView* webview = static_cast<LinuxWebView*>(user_data);
  if (!webview->scroll_enabled) {
    return;
  }

  JSCValue* js_value = webkit_javascript_result_get_js_value(result);
  gchar* text = jsc_value_to_string(js_value);
  if (text == nullptr) {
    return;
  }

  gchar** parts = g_strsplit(text, ",", 2);
  if (parts[0] != nullptr) {
    webview->last_scroll_x = g_ascii_strtod(parts[0], nullptr);
  }
  if (parts[1] != nullptr) {
    webview->last_scroll_y = g_ascii_strtod(parts[1], nullptr);
  }

  FlValue* event = make_event("scrollPositionChange");
  fl_value_set_string_take(event, "x", fl_value_new_float(webview->last_scroll_x));
  fl_value_set_string_take(event, "y", fl_value_new_float(webview->last_scroll_y));
  send_event(webview, event);

  g_strfreev(parts);
  g_free(text);
}

static void javascript_channel_message_received_cb(
    WebKitUserContentManager* manager,
    WebKitJavascriptResult* result,
    gpointer user_data) {
  JavaScriptChannelHandlerData* data =
      static_cast<JavaScriptChannelHandlerData*>(user_data);
  LinuxWebView* webview = data->webview;
  JSCValue* js_value = webkit_javascript_result_get_js_value(result);
  gchar* text = jsc_value_to_string(js_value);
  FlValue* event = make_event("javaScriptChannelMessage");
  fl_value_set_string_take(
      event, "channelName",
      fl_value_new_string(data->name != nullptr ? data->name : ""));
  fl_value_set_string_take(event, "message",
                           fl_value_new_string(text != nullptr ? text : ""));
  send_event(webview, event);
  g_free(text);
}

static void destroy_js_channel_handler_data(gpointer data, GClosure* closure) {
  JavaScriptChannelHandlerData* handler_data =
      static_cast<JavaScriptChannelHandlerData*>(data);
  if (handler_data == nullptr) {
    return;
  }
  g_free(handler_data->name);
  g_free(handler_data);
}

static void evaluate_javascript(WebKitWebView* web_view,
                                const gchar* script,
                                FlMethodCall* method_call) {
  g_object_ref(method_call);
  webkit_web_view_evaluate_javascript(web_view, script, -1, nullptr, nullptr,
                                      nullptr, script_finished_cb,
                                      method_call);
}

static void add_user_script(WebKitUserContentManager* manager,
                            const gchar* source) {
  WebKitUserScript* script = webkit_user_script_new(
      source, WEBKIT_USER_CONTENT_INJECT_ALL_FRAMES,
      WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START, nullptr, nullptr);
  webkit_user_content_manager_add_script(manager, script);
  webkit_user_script_unref(script);
}

static void rebuild_user_scripts(LinuxWebView* webview) {
  webkit_user_content_manager_remove_all_scripts(webview->content_manager);

  add_user_script(webview->content_manager, R"(
    (function() {
      if (window.__webviewAllConsoleHookInstalled) return;
      window.__webviewAllConsoleHookInstalled = true;
      ['log', 'info', 'warn', 'error', 'debug'].forEach(function(level) {
        const original = console[level];
        console[level] = function() {
          try {
            window.webkit.messageHandlers.__webview_all_console.postMessage(
              Array.from(arguments).map(function(arg) {
                return typeof arg === 'string' ? arg : JSON.stringify(arg);
              }).join(' ')
            );
          } catch (_) {}
          if (original) original.apply(console, arguments);
        };
      });
    })();
  )");

  add_user_script(webview->content_manager, R"(
    (function() {
      if (window.__webviewAllScrollHookInstalled) return;
      window.__webviewAllScrollHookInstalled = true;
      window.addEventListener('scroll', function() {
        try {
          window.webkit.messageHandlers.__webview_all_scroll.postMessage(
            [window.scrollX || 0, window.scrollY || 0].join(',')
          );
        } catch (_) {}
      }, { passive: true });
    })();
  )");

  GHashTableIter iter;
  gpointer key = nullptr;
  g_hash_table_iter_init(&iter, webview->js_channels);
  while (g_hash_table_iter_next(&iter, &key, nullptr)) {
    const gchar* name = static_cast<const gchar*>(key);
    gchar* source = g_strdup_printf(
        "window.%s = { postMessage: function(message) { "
        "window.webkit.messageHandlers.%s.postMessage(String(message)); } };",
        name, name);
    add_user_script(webview->content_manager, source);
    g_free(source);
  }
}

static FlMethodErrorResponse* event_listen_cb(FlEventChannel* channel,
                                              FlValue* args,
                                              gpointer user_data) {
  LinuxWebView* webview = static_cast<LinuxWebView*>(user_data);
  webview->event_listening = TRUE;
  return nullptr;
}

static FlMethodErrorResponse* event_cancel_cb(FlEventChannel* channel,
                                              FlValue* args,
                                              gpointer user_data) {
  LinuxWebView* webview = static_cast<LinuxWebView*>(user_data);
  webview->event_listening = FALSE;
  return nullptr;
}

static void destroy_linux_webview(gpointer data) {
  LinuxWebView* webview = static_cast<LinuxWebView*>(data);
  if (webview == nullptr) {
    return;
  }

  if (webview->web_view != nullptr) {
    gtk_widget_destroy(GTK_WIDGET(webview->web_view));
    g_object_unref(webview->web_view);
  }
  g_clear_object(&webview->method_channel);
  g_clear_object(&webview->event_channel);
  g_clear_object(&webview->content_manager);
  g_hash_table_destroy(webview->pending_nav_decisions);
  g_hash_table_destroy(webview->pending_auth_requests);
  g_hash_table_destroy(webview->pending_permission_requests);
  g_hash_table_destroy(webview->pending_script_dialogs);
  g_hash_table_destroy(webview->pending_tls_errors);
  g_hash_table_destroy(webview->js_channel_signal_ids);
  g_hash_table_destroy(webview->js_channels);
  g_free(webview);
}

static void instance_method_call_cb(FlMethodChannel* channel,
                                    FlMethodCall* method_call,
                                    gpointer user_data) {
  LinuxWebView* webview = static_cast<LinuxWebView*>(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  if (strcmp(method, "setFrame") == 0) {
    GtkWidget* widget = GTK_WIDGET(webview->web_view);
    webview->frame_x = static_cast<gint>(map_lookup_double(args, "x", 0));
    webview->frame_y = static_cast<gint>(map_lookup_double(args, "y", 0));
    webview->frame_width =
        static_cast<gint>(map_lookup_double(args, "width", 0));
    webview->frame_height =
        static_cast<gint>(map_lookup_double(args, "height", 0));
    webview->visible = map_lookup_bool(args, "visible", TRUE) &&
                       webview->frame_width > 0 && webview->frame_height > 0;
    gtk_widget_set_halign(widget, GTK_ALIGN_START);
    gtk_widget_set_valign(widget, GTK_ALIGN_START);
    gtk_widget_set_margin_start(widget, webview->frame_x);
    gtk_widget_set_margin_top(widget, webview->frame_y);
    gtk_widget_set_size_request(widget, webview->frame_width,
                                webview->frame_height);
    if (webview->visible) {
      gtk_widget_show(widget);
    } else {
      gtk_widget_hide(widget);
    }
    update_flutter_view_input_region(webview->plugin);
    queue_webview_overlay_redraw(widget);
    respond(method_call, success_response());
    return;
  }

  if (strcmp(method, "loadFile") == 0) {
    const gchar* file_path = map_lookup_string(args, "path");
    GError* error = nullptr;
    gchar* uri = g_filename_to_uri(file_path, nullptr, &error);
    if (error != nullptr) {
      respond(method_call, error_response("load_file_error", error->message));
      g_clear_error(&error);
      g_free(uri);
      return;
    }
    webkit_web_view_load_uri(webview->web_view, uri);
    queue_webview_overlay_redraw(GTK_WIDGET(webview->web_view));
    g_free(uri);
    respond(method_call, success_response());
    return;
  }

  if (strcmp(method, "loadHtmlString") == 0) {
    webkit_web_view_load_html(webview->web_view,
                              map_lookup_string(args, "html"),
                              map_lookup_string(args, "baseUrl"));
    queue_webview_overlay_redraw(GTK_WIDGET(webview->web_view));
    respond(method_call, success_response());
    return;
  }

  if (strcmp(method, "loadRequest") == 0) {
    const gchar* url = map_lookup_string(args, "url");
    FlValue* headers = map_lookup(args, "headers");
    WebKitURIRequest* request = webkit_uri_request_new(url);
    if (headers != nullptr &&
        fl_value_get_type(headers) == FL_VALUE_TYPE_MAP) {
      SoupMessageHeaders* request_headers =
          webkit_uri_request_get_http_headers(request);
      const size_t header_count = fl_value_get_length(headers);
      for (size_t i = 0; i < header_count; ++i) {
        const gchar* key =
            fl_value_to_string_or_null(fl_value_get_map_key(headers, i));
        const gchar* value =
            fl_value_to_string_or_null(fl_value_get_map_value(headers, i));
        if (key != nullptr && value != nullptr) {
          soup_message_headers_append(request_headers, key, value);
        }
      }
    }
    webkit_web_view_load_request(webview->web_view, request);
    queue_webview_overlay_redraw(GTK_WIDGET(webview->web_view));
    g_object_unref(request);
    respond(method_call, success_response());
    return;
  }

  if (strcmp(method, "currentUrl") == 0) {
    const gchar* uri = webkit_web_view_get_uri(webview->web_view);
    respond(method_call,
            success_response(uri != nullptr ? fl_value_new_string(uri)
                                            : fl_value_new_null()));
    return;
  }

  if (strcmp(method, "canGoBack") == 0) {
    respond(method_call,
            success_response(fl_value_new_bool(
                webkit_web_view_can_go_back(webview->web_view))));
    return;
  }

  if (strcmp(method, "canGoForward") == 0) {
    respond(method_call,
            success_response(fl_value_new_bool(
                webkit_web_view_can_go_forward(webview->web_view))));
    return;
  }

  if (strcmp(method, "goBack") == 0) {
    webkit_web_view_go_back(webview->web_view);
    respond(method_call, success_response());
    return;
  }

  if (strcmp(method, "goForward") == 0) {
    webkit_web_view_go_forward(webview->web_view);
    respond(method_call, success_response());
    return;
  }

  if (strcmp(method, "reload") == 0) {
    webkit_web_view_reload(webview->web_view);
    respond(method_call, success_response());
    return;
  }

  if (strcmp(method, "clearCache") == 0) {
    webkit_web_context_clear_cache(
        webkit_web_view_get_context(webview->web_view));
    respond(method_call, success_response());
    return;
  }

  if (strcmp(method, "clearLocalStorage") == 0) {
    evaluate_javascript(
        webview->web_view,
        "try { localStorage.clear(); sessionStorage.clear(); } catch (_) {}",
        method_call);
    return;
  }

  if (strcmp(method, "runJavaScript") == 0 ||
      strcmp(method, "runJavaScriptReturningResult") == 0) {
    evaluate_javascript(webview->web_view, map_lookup_string(args, "script"),
                        method_call);
    return;
  }

  if (strcmp(method, "addJavaScriptChannel") == 0) {
    const gchar* name = map_lookup_string(args, "name");
    if (!webkit_user_content_manager_register_script_message_handler(
            webview->content_manager, name)) {
      respond(method_call,
              error_response("channel_error", "Failed to register JS channel."));
      return;
    }
    gchar* signal_name = g_strdup_printf("script-message-received::%s", name);
    JavaScriptChannelHandlerData* data =
        g_new0(JavaScriptChannelHandlerData, 1);
    data->webview = webview;
    data->name = g_strdup(name);
    guint signal_id = g_signal_connect_data(
        webview->content_manager, signal_name,
        G_CALLBACK(javascript_channel_message_received_cb), data,
        destroy_js_channel_handler_data, GConnectFlags(0));
    g_free(signal_name);
    g_hash_table_insert(webview->js_channels, g_strdup(name),
                        GINT_TO_POINTER(1));
    g_hash_table_insert(webview->js_channel_signal_ids, g_strdup(name),
                        GUINT_TO_POINTER(signal_id));
    rebuild_user_scripts(webview);
    respond(method_call, success_response());
    return;
  }

  if (strcmp(method, "removeJavaScriptChannel") == 0) {
    const gchar* name = map_lookup_string(args, "name");
    gpointer signal_id_ptr =
        g_hash_table_lookup(webview->js_channel_signal_ids, name);
    if (signal_id_ptr != nullptr) {
      g_signal_handler_disconnect(webview->content_manager,
                                  GPOINTER_TO_UINT(signal_id_ptr));
      g_hash_table_remove(webview->js_channel_signal_ids, name);
    }
    webkit_user_content_manager_unregister_script_message_handler(
        webview->content_manager, name);
    g_hash_table_remove(webview->js_channels, name);
    rebuild_user_scripts(webview);
    respond(method_call, success_response());
    return;
  }

  if (strcmp(method, "getTitle") == 0) {
    const gchar* title = webkit_web_view_get_title(webview->web_view);
    respond(method_call,
            success_response(title != nullptr ? fl_value_new_string(title)
                                              : fl_value_new_null()));
    return;
  }

  if (strcmp(method, "scrollTo") == 0) {
    gchar* script = g_strdup_printf("window.scrollTo(%" G_GINT64_FORMAT
                                    ", %" G_GINT64_FORMAT ");",
                                    map_lookup_int(args, "x", 0),
                                    map_lookup_int(args, "y", 0));
    evaluate_javascript(webview->web_view, script, method_call);
    g_free(script);
    return;
  }

  if (strcmp(method, "scrollBy") == 0) {
    gchar* script = g_strdup_printf("window.scrollBy(%" G_GINT64_FORMAT
                                    ", %" G_GINT64_FORMAT ");",
                                    map_lookup_int(args, "x", 0),
                                    map_lookup_int(args, "y", 0));
    evaluate_javascript(webview->web_view, script, method_call);
    g_free(script);
    return;
  }

  if (strcmp(method, "getScrollPosition") == 0) {
    FlValue* result = fl_value_new_map();
    fl_value_set_string_take(result, "x",
                             fl_value_new_float(webview->last_scroll_x));
    fl_value_set_string_take(result, "y",
                             fl_value_new_float(webview->last_scroll_y));
    respond(method_call, success_response(result));
    return;
  }

  if (strcmp(method, "setVerticalScrollBarEnabled") == 0 ||
      strcmp(method, "setHorizontalScrollBarEnabled") == 0) {
    gboolean enabled = map_lookup_bool(args, "enabled", TRUE);
    gchar* script = g_strdup_printf(
        "document.documentElement.style.overflow = '%s'; "
        "document.body.style.overflow = '%s';",
        enabled ? "auto" : "hidden", enabled ? "auto" : "hidden");
    evaluate_javascript(webview->web_view, script, method_call);
    g_free(script);
    return;
  }

  if (strcmp(method, "enableZoom") == 0) {
    respond(method_call, success_response());
    return;
  }

  if (strcmp(method, "setBackgroundColor") == 0) {
    GdkRGBA color = {
        map_lookup_double(args, "r", 1.0), map_lookup_double(args, "g", 1.0),
        map_lookup_double(args, "b", 1.0), map_lookup_double(args, "a", 1.0)};
    webkit_web_view_set_background_color(webview->web_view, &color);
    respond(method_call, success_response());
    return;
  }

  if (strcmp(method, "setJavaScriptMode") == 0) {
    WebKitSettings* settings = webkit_web_view_get_settings(webview->web_view);
    webkit_settings_set_enable_javascript(
        settings, map_lookup_bool(args, "enabled", TRUE));
    respond(method_call, success_response());
    return;
  }

  if (strcmp(method, "setUserAgent") == 0) {
    WebKitSettings* settings = webkit_web_view_get_settings(webview->web_view);
    const gchar* user_agent = map_lookup_string(args, "userAgent");
    webkit_settings_set_user_agent(settings, user_agent);
    respond(method_call, success_response());
    return;
  }

  if (strcmp(method, "getUserAgent") == 0) {
    WebKitSettings* settings = webkit_web_view_get_settings(webview->web_view);
    const gchar* user_agent = webkit_settings_get_user_agent(settings);
    respond(method_call,
            success_response(user_agent != nullptr
                                 ? fl_value_new_string(user_agent)
                                 : fl_value_new_null()));
    return;
  }

  if (strcmp(method, "setOnConsoleMessage") == 0) {
    webview->console_enabled = map_lookup_bool(args, "enabled", TRUE);
    respond(method_call, success_response());
    return;
  }

  if (strcmp(method, "setOnScrollPositionChange") == 0) {
    webview->scroll_enabled = map_lookup_bool(args, "enabled", TRUE);
    respond(method_call, success_response());
    return;
  }

  if (strcmp(method, "completeNavigationRequest") == 0) {
    gint request_id = static_cast<gint>(map_lookup_int(args, "requestId", -1));
    gboolean allow = map_lookup_bool(args, "allow", TRUE);
    PendingNavigationDecision* pending =
        static_cast<PendingNavigationDecision*>(
            g_hash_table_lookup(webview->pending_nav_decisions,
                                GINT_TO_POINTER(request_id)));
    if (pending != nullptr) {
      if (allow) {
        if (pending->open_in_place && pending->uri != nullptr) {
          webkit_web_view_load_uri(webview->web_view, pending->uri);
          webkit_policy_decision_ignore(pending->decision);
        } else {
          webkit_policy_decision_use(pending->decision);
        }
      } else {
        webkit_policy_decision_ignore(pending->decision);
      }
      g_hash_table_remove(webview->pending_nav_decisions,
                          GINT_TO_POINTER(request_id));
    }
    respond(method_call, success_response());
    return;
  }

  if (strcmp(method, "completeHttpAuthRequest") == 0) {
    gint request_id = static_cast<gint>(map_lookup_int(args, "requestId", -1));
    WebKitAuthenticationRequest* request = WEBKIT_AUTHENTICATION_REQUEST(
        g_hash_table_lookup(webview->pending_auth_requests,
                            GINT_TO_POINTER(request_id)));
    if (request != nullptr) {
      const gchar* action = map_lookup_string(args, "action");
      if (g_strcmp0(action, "proceed") == 0) {
        WebKitCredential* credential = webkit_credential_new(
            map_lookup_string(args, "user") != nullptr
                ? map_lookup_string(args, "user")
                : "",
            map_lookup_string(args, "password") != nullptr
                ? map_lookup_string(args, "password")
                : "",
            WEBKIT_CREDENTIAL_PERSISTENCE_NONE);
        webkit_authentication_request_authenticate(request, credential);
        webkit_credential_free(credential);
      } else {
        webkit_authentication_request_cancel(request);
      }
      g_hash_table_remove(webview->pending_auth_requests,
                          GINT_TO_POINTER(request_id));
    }
    respond(method_call, success_response());
    return;
  }

  if (strcmp(method, "completePermissionRequest") == 0) {
    gint request_id = static_cast<gint>(map_lookup_int(args, "requestId", -1));
    WebKitPermissionRequest* request = WEBKIT_PERMISSION_REQUEST(
        g_hash_table_lookup(webview->pending_permission_requests,
                            GINT_TO_POINTER(request_id)));
    if (request != nullptr) {
      if (map_lookup_bool(args, "grant", FALSE)) {
        webkit_permission_request_allow(request);
      } else {
        webkit_permission_request_deny(request);
      }
      g_hash_table_remove(webview->pending_permission_requests,
                          GINT_TO_POINTER(request_id));
    }
    respond(method_call, success_response());
    return;
  }

  if (strcmp(method, "completeJavaScriptDialog") == 0) {
    gint request_id = static_cast<gint>(map_lookup_int(args, "requestId", -1));
    WebKitScriptDialog* dialog = static_cast<WebKitScriptDialog*>(
        g_hash_table_lookup(webview->pending_script_dialogs,
                            GINT_TO_POINTER(request_id)));
    if (dialog != nullptr) {
      const gchar* action = map_lookup_string(args, "action");
      switch (webkit_script_dialog_get_dialog_type(dialog)) {
        case WEBKIT_SCRIPT_DIALOG_ALERT:
          break;
        case WEBKIT_SCRIPT_DIALOG_CONFIRM:
        case WEBKIT_SCRIPT_DIALOG_BEFORE_UNLOAD_CONFIRM:
          webkit_script_dialog_confirm_set_confirmed(
              dialog, g_strcmp0(action, "confirm") == 0);
          break;
        case WEBKIT_SCRIPT_DIALOG_PROMPT:
          if (g_strcmp0(action, "cancel") != 0) {
            webkit_script_dialog_prompt_set_text(
                dialog, map_lookup_string(args, "text"));
          }
          break;
      }
      webkit_script_dialog_close(dialog);
      g_hash_table_remove(webview->pending_script_dialogs,
                          GINT_TO_POINTER(request_id));
    }
    respond(method_call, success_response());
    return;
  }

  if (strcmp(method, "completeSslAuthError") == 0) {
    gint request_id = static_cast<gint>(map_lookup_int(args, "requestId", -1));
    PendingTlsError* pending = static_cast<PendingTlsError*>(
        g_hash_table_lookup(webview->pending_tls_errors,
                            GINT_TO_POINTER(request_id)));
    if (pending != nullptr) {
      if (map_lookup_bool(args, "proceed", FALSE) &&
          pending->certificate != nullptr && pending->host != nullptr) {
        WebKitWebContext* context =
            webkit_web_view_get_context(webview->web_view);
        webkit_web_context_allow_tls_certificate_for_host(
            context, pending->certificate, pending->host);
        if (pending->uri != nullptr) {
          webkit_web_view_load_uri(webview->web_view, pending->uri);
        }
      }
      g_hash_table_remove(webview->pending_tls_errors,
                          GINT_TO_POINTER(request_id));
    }
    respond(method_call, success_response());
    return;
  }

  if (strcmp(method, "dispose") == 0) {
    GtkWidget* widget = GTK_WIDGET(webview->web_view);
    gtk_widget_hide(widget);
    webview->visible = FALSE;
    update_flutter_view_input_region(webview->plugin);
    queue_webview_overlay_redraw(widget);
    respond(method_call, success_response());
    return;
  }

  respond(method_call,
          FL_METHOD_RESPONSE(fl_method_not_implemented_response_new()));
}

static LinuxWebView* create_linux_webview(WebviewAllLinuxPlugin* self) {
  GtkOverlay* overlay = ensure_overlay(self);
  if (overlay == nullptr) {
    return nullptr;
  }

  LinuxWebView* webview = g_new0(LinuxWebView, 1);
  webview->plugin = self;
  webview->id = self->next_webview_id++;
  webview->content_manager = webkit_user_content_manager_new();
  webview->web_view = WEBKIT_WEB_VIEW(
      webkit_web_view_new_with_user_content_manager(webview->content_manager));
  webview->pending_nav_decisions =
      g_hash_table_new_full(g_direct_hash, g_direct_equal, nullptr,
                            destroy_pending_navigation_decision);
  webview->pending_auth_requests =
      g_hash_table_new_full(g_direct_hash, g_direct_equal, nullptr,
                            reinterpret_cast<GDestroyNotify>(g_object_unref));
  webview->pending_permission_requests =
      g_hash_table_new_full(g_direct_hash, g_direct_equal, nullptr,
                            reinterpret_cast<GDestroyNotify>(g_object_unref));
  webview->pending_script_dialogs =
      g_hash_table_new_full(g_direct_hash, g_direct_equal, nullptr,
                            reinterpret_cast<GDestroyNotify>(
                                webkit_script_dialog_unref));
  webview->pending_tls_errors =
      g_hash_table_new_full(g_direct_hash, g_direct_equal, nullptr,
                            destroy_pending_tls_error);
  webview->js_channel_signal_ids =
      g_hash_table_new_full(g_str_hash, g_str_equal, g_free, nullptr);
  webview->js_channels =
      g_hash_table_new_full(g_str_hash, g_str_equal, g_free, nullptr);
  webview->next_request_id = 1;

  gchar* method_name =
      g_strdup_printf("plugins.moluo/webview_all_linux/%d", webview->id);
  webview->method_channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(self->registrar), method_name,
      method_codec());
  g_free(method_name);

  gchar* event_name =
      g_strdup_printf("plugins.moluo/webview_all_linux/%d/events", webview->id);
  webview->event_channel = fl_event_channel_new(
      fl_plugin_registrar_get_messenger(self->registrar), event_name,
      method_codec());
  g_free(event_name);

  fl_method_channel_set_method_call_handler(webview->method_channel,
                                            instance_method_call_cb, webview,
                                            nullptr);
  fl_event_channel_set_stream_handlers(webview->event_channel, event_listen_cb,
                                       event_cancel_cb, webview, nullptr);

  webkit_user_content_manager_register_script_message_handler(
      webview->content_manager, "__webview_all_console");
  webkit_user_content_manager_register_script_message_handler(
      webview->content_manager, "__webview_all_scroll");
  g_signal_connect(webview->content_manager,
                   "script-message-received::__webview_all_console",
                   G_CALLBACK(console_message_received_cb), webview);
  g_signal_connect(webview->content_manager,
                   "script-message-received::__webview_all_scroll",
                   G_CALLBACK(scroll_message_received_cb), webview);

  rebuild_user_scripts(webview);

  g_signal_connect(webview->web_view, "decide-policy",
                   G_CALLBACK(decide_policy_cb), webview);
  g_signal_connect(webview->web_view, "load-changed",
                   G_CALLBACK(load_changed_cb), webview);
  g_signal_connect(webview->web_view, "notify::estimated-load-progress",
                   G_CALLBACK(notify_progress_cb), webview);
  g_signal_connect(webview->web_view, "notify::uri", G_CALLBACK(notify_uri_cb),
                   webview);
  g_signal_connect(webview->web_view, "notify::title",
                   G_CALLBACK(notify_title_cb), webview);
  g_signal_connect(webview->web_view, "load-failed",
                   G_CALLBACK(load_failed_cb), webview);
  g_signal_connect(webview->web_view, "authenticate",
                   G_CALLBACK(authenticate_cb), webview);
  g_signal_connect(webview->web_view, "permission-request",
                   G_CALLBACK(permission_request_cb), webview);
  g_signal_connect(webview->web_view, "script-dialog",
                   G_CALLBACK(script_dialog_cb), webview);
  g_signal_connect(webview->web_view, "load-failed-with-tls-errors",
                   G_CALLBACK(load_failed_with_tls_errors_cb), webview);

  gtk_widget_set_halign(GTK_WIDGET(webview->web_view), GTK_ALIGN_START);
  gtk_widget_set_valign(GTK_WIDGET(webview->web_view), GTK_ALIGN_START);
  gtk_widget_set_hexpand(GTK_WIDGET(webview->web_view), FALSE);
  gtk_widget_set_vexpand(GTK_WIDGET(webview->web_view), FALSE);
  gtk_widget_set_can_focus(GTK_WIDGET(webview->web_view), TRUE);
  gtk_widget_set_sensitive(GTK_WIDGET(webview->web_view), TRUE);
  gtk_widget_add_events(GTK_WIDGET(webview->web_view),
                        GDK_BUTTON_PRESS_MASK | GDK_BUTTON_RELEASE_MASK |
                            GDK_SCROLL_MASK | GDK_SMOOTH_SCROLL_MASK |
                            GDK_POINTER_MOTION_MASK);
  gtk_widget_set_size_request(GTK_WIDGET(webview->web_view), 1, 1);
  gtk_widget_hide(GTK_WIDGET(webview->web_view));
  gtk_overlay_add_overlay(overlay, GTK_WIDGET(webview->web_view));
  gtk_overlay_set_overlay_pass_through(overlay, GTK_WIDGET(webview->web_view),
                                       FALSE);
  gtk_widget_show(GTK_WIDGET(webview->web_view));
  gtk_widget_grab_focus(GTK_WIDGET(webview->web_view));
  gtk_widget_hide(GTK_WIDGET(webview->web_view));

  g_hash_table_insert(self->webviews, GINT_TO_POINTER(webview->id), webview);
  return webview;
}

static void root_method_call_cb(FlMethodChannel* channel,
                                FlMethodCall* method_call,
                                gpointer user_data) {
  WebviewAllLinuxPlugin* self = static_cast<WebviewAllLinuxPlugin*>(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  if (strcmp(method, "createWebView") == 0) {
    LinuxWebView* webview = create_linux_webview(self);
    if (webview == nullptr) {
      respond(method_call, error_response("creation_error",
                                          "Unable to create Linux WebView."));
      return;
    }
    respond(method_call, success_response(fl_value_new_int(webview->id)));
    return;
  }

  WebKitWebContext* context = webkit_web_context_get_default();
  WebKitCookieManager* cookie_manager =
      webkit_web_context_get_cookie_manager(context);
  WebKitWebsiteDataManager* website_data_manager =
      webkit_web_context_get_website_data_manager(context);

  if (strcmp(method, "clearCookies") == 0) {
    g_object_ref(method_call);
    webkit_website_data_manager_clear(
        website_data_manager, WEBKIT_WEBSITE_DATA_COOKIES, 0, nullptr,
        clear_cookies_finished_cb, method_call);
    return;
  }

  if (strcmp(method, "setCookie") == 0) {
    const gchar* name = map_lookup_string(args, "name");
    const gchar* value = map_lookup_string(args, "value");
    const gchar* domain = map_lookup_string(args, "domain");
    const gchar* path = map_lookup_string(args, "path");
    SoupCookie* cookie = soup_cookie_new(name, value, domain, path, -1);
    g_object_ref(method_call);
    webkit_cookie_manager_add_cookie(cookie_manager, cookie, nullptr,
                                     add_cookie_finished_cb, method_call);
    soup_cookie_free(cookie);
    return;
  }

  if (strcmp(method, "getCookies") == 0) {
    g_object_ref(method_call);
    webkit_cookie_manager_get_cookies(
        cookie_manager, map_lookup_string(args, "url"), nullptr,
        get_cookies_finished_cb, method_call);
    return;
  }

  respond(method_call,
          FL_METHOD_RESPONSE(fl_method_not_implemented_response_new()));
}

static void webview_all_linux_plugin_dispose(GObject* object) {
  WebviewAllLinuxPlugin* self =
      reinterpret_cast<WebviewAllLinuxPlugin*>(object);

  g_clear_object(&self->registrar);
  g_clear_object(&self->root_channel);
  if (self->webviews != nullptr) {
    g_hash_table_destroy(self->webviews);
    self->webviews = nullptr;
  }

  G_OBJECT_CLASS(webview_all_linux_plugin_parent_class)->dispose(object);
}

static void webview_all_linux_plugin_class_init(
    WebviewAllLinuxPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = webview_all_linux_plugin_dispose;
}

static void webview_all_linux_plugin_init(WebviewAllLinuxPlugin* self) {
  self->next_webview_id = 1;
  self->webviews = g_hash_table_new_full(g_direct_hash, g_direct_equal, nullptr,
                                         destroy_linux_webview);
}

void webview_all_linux_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  WebviewAllLinuxPlugin* plugin = reinterpret_cast<WebviewAllLinuxPlugin*>(
      g_object_new(webview_all_linux_plugin_get_type(), nullptr));

  plugin->registrar = FL_PLUGIN_REGISTRAR(g_object_ref(registrar));
  plugin->root_channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "plugins.moluo/webview_all_linux", method_codec());

  fl_method_channel_set_method_call_handler(plugin->root_channel,
                                            root_method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);
  g_object_unref(plugin);
}
