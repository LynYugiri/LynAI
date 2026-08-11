import 'package:flutter/foundation.dart';

import '../models/sync_change.dart';

/// Holds the capabilities last advertised by the active backend scope.
class ServerCapabilitiesService extends ChangeNotifier {
  SyncCapabilities _capabilities = const SyncCapabilities();

  SyncCapabilities get capabilities => _capabilities;
  bool get webSearchConfigured => _capabilities.webSearch;

  bool has(String name) => _capabilities.has(name);

  void update(SyncCapabilities capabilities) {
    if (_capabilities.advertised == capabilities.advertised &&
        mapEquals(_capabilities.values, capabilities.values)) {
      return;
    }
    _capabilities = capabilities;
    notifyListeners();
  }

  void reset() => update(const SyncCapabilities());
}
