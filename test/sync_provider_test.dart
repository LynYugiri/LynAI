import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/sync_change.dart';
import 'package:lynai/providers/sync_provider.dart';
import 'package:lynai/services/storage_v2_database.dart';
import 'package:lynai/services/sync_service.dart';

void main() {
  group('SyncProvider', () {
    test('downloads every page and reloads once after remote apply', () async {
      final storage = _FakeSyncStorage();
      final service = _FakeSyncService(
        pages: [_page(seq: 1, hasMore: true), _page(seq: 2, hasMore: false)],
      );
      var reloads = 0;
      SyncApplySummary? summary;
      final provider = SyncProvider(
        service: service,
        storage: storage,
        onRemoteApplied: (value) async {
          reloads++;
          summary = value;
        },
      );

      await provider.bindScope('user-1');
      await provider.autoDownload();

      expect(service.requestedSince, [0, 1]);
      expect(storage.appliedSince, [1, 2]);
      expect(storage.sinceByScope[provider.scope], 2);
      expect(reloads, 1);
      expect(summary?.scope, 'injected|user-1');
      expect(summary?.changedTables, {'messages'});
      expect(service.requestedLimits, [1000, 1000]);
    });

    test(
      'flushes newly encountered tables and materializes notes once',
      () async {
        final storage = _FakeSyncStorage();
        final flushed = <Set<String>>[];
        final applied = <SyncApplySummary>[];
        final provider = SyncProvider(
          service: _FakeSyncService(
            pages: [
              _page(seq: 1, hasMore: true),
              _notePage(seq: 2, hasMore: true),
              _notePage(seq: 3, hasMore: false),
            ],
          ),
          storage: storage,
          beforeRemoteApply: (summary) async {
            flushed.add(summary.changedTables);
          },
          onRemoteApplied: (summary) async => applied.add(summary),
        );

        await provider.bindScope('user-1');
        flushed.clear();
        await provider.autoDownload();

        expect(flushed, [
          {'messages'},
          {'note_pages'},
        ]);
        expect(storage.materializeCalls, 1);
        expect(applied, hasLength(1));
        expect(applied.single.changedTables, {'messages', 'note_pages'});
      },
    );

    test('materializes notes once across download upload download', () async {
      final storage = _FakeSyncStorage(
        outbox: [_entry('local', version: 1)],
        acknowledgeConflict: true,
      );
      final applied = <SyncApplySummary>[];
      final provider = SyncProvider(
        service: _FakeSyncService(
          pages: [
            _notePage(seq: 1, hasMore: false),
            _notePage(seq: 2, hasMore: false),
          ],
        ),
        storage: storage,
        onRemoteApplied: (summary) async => applied.add(summary),
      );

      await provider.bindScope('user-1');
      await provider.manualSync();

      expect(storage.materializeCalls, 1);
      expect(applied, hasLength(1));
      expect(applied.single.changedTables, {'messages', 'note_pages'});
    });

    test('unbind invalidates an in-flight download result', () async {
      final storage = _FakeSyncStorage();
      final response = Completer<SyncDownloadResult>();
      final service = _BlockingSyncService(response.future);
      final provider = SyncProvider(service: service, storage: storage);
      await provider.bindScope('user-1');

      final sync = provider.autoDownload();
      await service.requestStarted.future;
      final unbind = provider.unbind();
      response.complete(_page(seq: 1, hasMore: false));
      await Future.wait([sync, unbind]);

      expect(storage.appliedOps, isEmpty);
      expect(provider.scope, isNull);
    });

    test('rejects a non-advancing non-empty download page', () async {
      final storage = _FakeSyncStorage();
      final provider = SyncProvider(
        service: _FakeSyncService(
          pages: [
            SyncDownloadResult(
              changes: [_page(seq: 1, hasMore: false).changes.single],
              latestSeq: 1,
              hasMore: false,
              nextSince: 0,
            ),
          ],
        ),
        storage: storage,
      );
      final oldDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {};
      addTearDown(() => debugPrint = oldDebugPrint);

      await provider.bindScope('user-1');
      await provider.autoDownload();

      expect(provider.error, contains('未前进'));
      expect(storage.appliedOps, isEmpty);
    });

    test('failed upload keeps persistent outbox snapshot', () async {
      final entry = _entry('m1', version: 3);
      final storage = _FakeSyncStorage(outbox: [entry]);
      final service = _FakeSyncService(uploadError: Exception('offline'));
      final oldDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {};
      addTearDown(() => debugPrint = oldDebugPrint);
      final provider = SyncProvider(service: service, storage: storage);

      await provider.bindScope('user-1');
      await provider.flushUpload();

      expect(provider.error, contains('offline'));
      expect(storage.acknowledged, isEmpty);
      expect(storage.outbox, [entry]);
    });

    test('acknowledges exactly the uploaded mutation versions', () async {
      final entries = [_entry('m1', version: 1), _entry('m2', version: 4)];
      final storage = _FakeSyncStorage(outbox: entries);
      final provider = SyncProvider(
        service: _FakeSyncService(),
        storage: storage,
      );

      await provider.bindScope('user-1');
      await provider.flushUpload();

      expect(storage.acknowledged, entries);
      expect(storage.outbox, isEmpty);
    });

    test(
      'legacy whole-batch ACK does not retry an acknowledged snapshot',
      () async {
        final entry = _entry('m1', version: 1);
        final storage = _FakeSyncStorage(outbox: [entry]);
        final service = _FakeSyncService(
          uploadResult: const SyncUploadResult(
            latestSeq: 1,
            legacyWholeBatchAcknowledgement: true,
          ),
        );

        final provider = SyncProvider(service: service, storage: storage);

        await provider.bindScope('user-1');
        await provider.flushUpload();
        await provider.flushUpload();

        expect(storage.acknowledged, [entry]);
        expect(storage.outbox, isEmpty);
        expect(
          service.calls.where((call) => call == 'uploadChanges'),
          hasLength(1),
        );
      },
    );

    test('malformed ACK keeps the outbox snapshot', () async {
      final entry = _entry('m1', version: 2);
      final storage = _FakeSyncStorage(outbox: [entry]);
      final provider = SyncProvider(
        service: _FakeSyncService(
          uploadResult: const SyncUploadResult(latestSeq: 1),
        ),
        storage: storage,
      );
      final oldDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {};
      addTearDown(() => debugPrint = oldDebugPrint);

      await provider.bindScope('user-1');
      await provider.flushUpload();

      expect(provider.error, contains('malformed ACK'));
      expect(storage.acknowledged, isEmpty);
      expect(storage.outbox, [entry]);
    });

    test(
      'does not ACK when server returns a mismatched acknowledgement',
      () async {
        final entry = _entry('m1', version: 2);
        final storage = _FakeSyncStorage(outbox: [entry]);
        final provider = SyncProvider(
          service: _FakeSyncService(
            uploadResult: const SyncUploadResult(
              latestSeq: 1,
              acknowledgements: [
                SyncAcknowledgement(changeId: 'wrong', mutationVersion: 2),
              ],
            ),
          ),
          storage: storage,
        );
        final oldDebugPrint = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {};
        addTearDown(() => debugPrint = oldDebugPrint);

        await provider.bindScope('user-1');
        await provider.flushUpload();

        expect(provider.error, contains('exact uploaded batch'));
        expect(storage.outbox, [entry]);
      },
    );

    test('downloads again after upload before advancing the cursor', () async {
      final storage = _FakeSyncStorage(outbox: [_entry('m1', version: 1)]);
      final service = _FakeSyncService();
      final provider = SyncProvider(service: service, storage: storage);

      await provider.bindScope('user-1');
      await provider.manualSync();

      expect(service.requestedSince, [0, 0]);
      expect(storage.outbox, isEmpty);
    });

    test('serializes concurrent public sync calls', () async {
      final service = _FakeSyncService(delay: const Duration(milliseconds: 20));
      final provider = SyncProvider(
        service: service,
        storage: _FakeSyncStorage(),
      );
      await provider.bindScope('user-1');

      await Future.wait([
        provider.autoDownload(),
        provider.manualSync(),
        provider.flushUpload(),
      ]);

      expect(service.maxActiveCalls, 1);
    });

    test('does not run queued work or notify after dispose', () async {
      final entry = _entry('m1', version: 1);
      final storage = _FakeSyncStorage(outbox: [entry]);
      final service = _FakeSyncService(delay: const Duration(milliseconds: 20));
      final provider = SyncProvider(service: service, storage: storage);
      await provider.bindScope('user-1');
      var notifications = 0;
      provider.addListener(() => notifications++);

      final active = provider.flushUpload();
      await Future<void>.delayed(Duration.zero);
      final queued = provider.flushUpload();
      provider.dispose();

      await expectLater(Future.wait([active, queued]), completes);
      await expectLater(provider.flushUpload(), completes);
      expect(notifications, 1);
      expect(
        service.calls.where((call) => call == 'uploadChanges'),
        hasLength(1),
      );
    });

    test('normalizes backend scope and isolates users', () async {
      final storage = _FakeSyncStorage();
      final provider = SyncProvider(
        service: _FakeSyncService(),
        storage: storage,
      );

      await provider.bindScope(' user-a ');
      final first = provider.scope;
      await provider.bindScope('user-b');

      expect(first, 'injected|user-a');
      expect(provider.scope, 'injected|user-b');
      expect(storage.activated, ['injected|user-a', 'injected|user-b']);
      expect(storage.deactivated, ['injected|user-a']);
    });

    test('uploads each missing attachment blob before changes', () async {
      final entries = [
        _resourceEntry('r1', _hashA),
        _resourceEntry('r2', _hashA),
        _resourceEntry('r3', _hashB),
      ];
      final storage = _FakeSyncStorage(
        outbox: entries,
        resourceBlobs: const [
          SyncResourceBlob(sha256: _hashA, bytes: [1]),
          SyncResourceBlob(sha256: _hashA, bytes: [1]),
          SyncResourceBlob(sha256: _hashB, bytes: [2]),
        ],
      );
      final service = _FakeSyncService(remoteBlobs: {_hashB});
      final provider = SyncProvider(service: service, storage: storage);

      await provider.bindScope('user-1');
      await provider.flushUpload();

      expect(service.uploadedBlobs, [_hashA]);
      expect(service.calls, [
        'listBlobs',
        'uploadBlob:$_hashA',
        'uploadChanges',
      ]);
      expect(storage.outbox, isEmpty);
    });

    test('loads and acknowledges the outbox in bounded windows', () async {
      final entries = [for (var i = 0; i < 300; i++) _entry('m$i', version: 1)];
      final storage = _FakeSyncStorage(outbox: entries);
      final provider = SyncProvider(
        service: _FakeSyncService(),
        storage: storage,
      );

      await provider.bindScope('user-1');
      await provider.flushUpload();

      expect(storage.loadOutboxLimits, isNotEmpty);
      expect(storage.loadOutboxLimits, everyElement(256));
      expect(storage.maxLoadedOutbox, 256);
      expect(storage.acknowledged, hasLength(300));
      expect(storage.outbox, isEmpty);
    });

    test('reads bytes only for missing blobs and one at a time', () async {
      var activeReads = 0;
      var maxActiveReads = 0;
      final storage = _FakeSyncStorage(
        outbox: [_resourceEntry('r1', _hashA), _resourceEntry('r2', _hashB)],
        resourceBlobReaders: {
          _hashA: () async {
            activeReads++;
            if (activeReads > maxActiveReads) maxActiveReads = activeReads;
            await Future<void>.delayed(Duration.zero);
            activeReads--;
            return [1];
          },
          _hashB: () async {
            activeReads++;
            if (activeReads > maxActiveReads) maxActiveReads = activeReads;
            await Future<void>.delayed(Duration.zero);
            activeReads--;
            return [2];
          },
        },
      );
      final service = _FakeSyncService(remoteBlobs: {_hashB});
      final provider = SyncProvider(service: service, storage: storage);

      await provider.bindScope('user-1');
      await provider.flushUpload();

      expect(storage.readBlobHashes, [_hashA]);
      expect(maxActiveReads, 1);
      expect(service.uploadedBlobs, [_hashA]);
    });

    test('uses advertised request, change, blob, and page limits', () async {
      final entries = [
        for (var i = 0; i < 4; i++)
          _entryWithData('m$i', data: {'id': 'm$i', 'text': '界' * 20}),
      ];
      final storage = _FakeSyncStorage(outbox: entries);
      final service = _FakeSyncService(
        limits: const SyncLimits(
          maxBlobBytes: 2,
          maxChangesRequestBytes: 430,
          maxChangesPerRequest: 2,
          maxChangeDataBytes: 100,
          maxChangesPageSize: 7,
          maxBlobsPageSize: 9,
        ),
      );
      final provider = SyncProvider(service: service, storage: storage);

      await provider.bindScope('user-1');
      await provider.manualSync();

      expect(service.uploadedBatchSizes.length, greaterThanOrEqualTo(2));
      expect(service.uploadedBatchSizes, everyElement(lessThanOrEqualTo(2)));
      expect(service.uploadedBodySizes, everyElement(lessThanOrEqualTo(430)));
      expect(service.uploadedBatchSizes.reduce((a, b) => a + b), 4);
      expect(service.requestedLimits, everyElement(7));
    });

    test(
      'oversized change does not block later eligible outbox entries',
      () async {
        final oversized = _entryWithData(
          'oversized',
          data: {'id': 'oversized', 'text': 'x' * 200},
        );
        final eligible = _entry('eligible', version: 1);
        final storage = _FakeSyncStorage(outbox: [oversized, eligible]);
        final service = _FakeSyncService(
          limits: const SyncLimits(maxChangeDataBytes: 64),
        );
        final provider = SyncProvider(service: service, storage: storage);
        final oldDebugPrint = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {};
        addTearDown(() => debugPrint = oldDebugPrint);

        await provider.bindScope('user-1');
        await provider.flushUpload();

        expect(service.uploadedRecordIds, ['eligible']);
        expect(storage.outbox, [oversized]);
        expect(provider.error, contains('exceed'));
      },
    );

    test('oversized single request does not block a later entry', () async {
      final oversized = _entryWithData(
        'oversized',
        data: {'id': 'oversized', 'text': 'x' * 120},
      );
      final eligible = _entry('eligible', version: 1);
      final storage = _FakeSyncStorage(outbox: [oversized, eligible]);
      final service = _FakeSyncService(
        limits: const SyncLimits(
          maxChangeDataBytes: 1024,
          maxChangesRequestBytes: 260,
        ),
      );
      final provider = SyncProvider(service: service, storage: storage);
      final oldDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {};
      addTearDown(() => debugPrint = oldDebugPrint);

      await provider.bindScope('user-1');
      await provider.flushUpload();

      expect(service.uploadedRecordIds, ['eligible']);
      expect(storage.outbox, [oversized]);
    });

    test('enforces advertised blob size and listing page limit', () async {
      final entry = _resourceEntry('r1', _hashA);
      final storage = _FakeSyncStorage(
        outbox: [entry],
        resourceBlobs: const [
          SyncResourceBlob(sha256: _hashA, bytes: [1, 2, 3]),
        ],
      );
      final service = _FakeSyncService(
        limits: const SyncLimits(maxBlobBytes: 2, maxBlobsPageSize: 9),
      );
      final provider = SyncProvider(service: service, storage: storage);
      final oldDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {};
      addTearDown(() => debugPrint = oldDebugPrint);

      await provider.bindScope('user-1');
      await provider.flushUpload();

      expect(service.listBlobLimits, [9]);
      expect(service.uploadedBlobs, isEmpty);
      expect(service.uploadedRecordIds, isEmpty);
      expect(provider.error, contains('exceeds 2 bytes'));
    });

    test(
      'downloads missing blob and rebuilds canonical resource path',
      () async {
        final storage = _FakeSyncStorage();
        final service = _FakeSyncService(
          pages: [_resourcePage(_hashA)],
          downloadedBlobs: const {
            _hashA: [1, 2, 3],
          },
        );
        final provider = SyncProvider(service: service, storage: storage);

        await provider.bindScope('user-1');
        await provider.autoDownload();

        expect(service.downloadedHashes, [_hashA]);
        expect(storage.installedHashes, [_hashA]);
        expect(
          storage.appliedOps.single.data?['relativePath'],
          'assets/blobs/aa/$_hashA',
        );
        expect(storage.appliedSince, [1]);
      },
    );

    test(
      'hash mismatch does not apply resource row or advance cursor',
      () async {
        final storage = _FakeSyncStorage(hashMismatch: true);
        final service = _FakeSyncService(
          pages: [_resourcePage(_hashA)],
          downloadedBlobs: const {
            _hashA: [9],
          },
        );
        final provider = SyncProvider(service: service, storage: storage);
        final oldDebugPrint = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {};
        addTearDown(() => debugPrint = oldDebugPrint);

        await provider.bindScope('user-1');
        await provider.autoDownload();

        expect(provider.error, contains('hash mismatch'));
        expect(storage.appliedOps, isEmpty);
        expect(storage.sinceByScope[provider.scope], 0);
      },
    );

    test('rejects unsafe plugin paths before downloading blobs', () async {
      final storage = _FakeSyncStorage();
      final service = _FakeSyncService(
        pages: [
          SyncDownloadResult(
            changes: [
              SyncChange(
                seq: 1,
                changeId: 'plugin-change',
                deviceId: 'device-b',
                clientCreatedAt: DateTime.utc(2026),
                table: 'plugin_files',
                op: 'upsert',
                recordId: 'plugin/../escape.lua',
                data: {
                  'id': 'plugin/../escape.lua',
                  'pluginId': 'plugin',
                  'path': '../escape.lua',
                  'sha256': _hashA,
                },
              ),
            ],
            latestSeq: 1,
            hasMore: false,
            nextSince: 1,
          ),
        ],
      );
      final provider = SyncProvider(
        service: service,
        storage: storage,
        hasPluginBlob: (_) async => false,
        installPluginBlob: (_, _) async {},
      );
      final oldDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {};
      addTearDown(() => debugPrint = oldDebugPrint);

      await provider.bindScope('user-1');
      await provider.autoDownload();

      expect(provider.error, contains('unsafe path'));
      expect(service.downloadedHashes, isEmpty);
      expect(storage.appliedOps, isEmpty);
    });

    test('rejects malicious plugin ID before downloading blobs', () async {
      final storage = _FakeSyncStorage();
      final service = _FakeSyncService(
        pages: [
          SyncDownloadResult(
            changes: [
              SyncChange(
                seq: 1,
                changeId: 'plugin-change',
                deviceId: 'device-b',
                clientCreatedAt: DateTime.utc(2026),
                table: 'plugin_files',
                op: 'upsert',
                recordId: '../../outside/main.lua',
                data: {
                  'id': '../../outside/main.lua',
                  'pluginId': '../../outside',
                  'path': 'main.lua',
                  'sha256': _hashA,
                  'size': 1,
                  'kind': 'content',
                  'builtIn': false,
                },
              ),
            ],
            latestSeq: 1,
            hasMore: false,
            nextSince: 1,
          ),
        ],
      );
      final provider = SyncProvider(
        service: service,
        storage: storage,
        hasPluginBlob: (_) async => false,
        installPluginBlob: (_, _) async {},
      );
      final oldDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {};
      addTearDown(() => debugPrint = oldDebugPrint);

      await provider.bindScope('user-1');
      await provider.autoDownload();

      expect(provider.error, contains('invalid pluginId'));
      expect(service.downloadedHashes, isEmpty);
      expect(storage.appliedOps, isEmpty);
    });

    test('missing blob download does not apply resource row', () async {
      final storage = _FakeSyncStorage();
      final service = _FakeSyncService(
        pages: [_resourcePage(_hashA)],
        downloadError: Exception('blob missing'),
      );
      final provider = SyncProvider(service: service, storage: storage);
      final oldDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {};
      addTearDown(() => debugPrint = oldDebugPrint);

      await provider.bindScope('user-1');
      await provider.autoDownload();

      expect(provider.error, contains('blob missing'));
      expect(storage.appliedOps, isEmpty);
      expect(storage.sinceByScope[provider.scope], 0);
    });

    test('unknown remote table does not advance the cursor', () async {
      final storage = _FakeSyncStorage();
      final provider = SyncProvider(
        service: _FakeSyncService(pages: [_invalidPage(table: 'unknown')]),
        storage: storage,
      );
      final oldDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {};
      addTearDown(() => debugPrint = oldDebugPrint);

      await provider.bindScope('user-1');
      await provider.autoDownload();

      expect(provider.error, contains('unsupported remote sync table'));
      expect(storage.sinceByScope[provider.scope], 0);
    });

    test('mismatched data.id does not advance the cursor', () async {
      final storage = _FakeSyncStorage();
      final provider = SyncProvider(
        service: _FakeSyncService(pages: [_invalidPage(dataId: 'other')]),
        storage: storage,
      );
      final oldDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {};
      addTearDown(() => debugPrint = oldDebugPrint);

      await provider.bindScope('user-1');
      await provider.autoDownload();

      expect(provider.error, contains('does not match recordId'));
      expect(storage.sinceByScope[provider.scope], 0);
    });

    test('rejects duplicate changeId in a page', () async {
      final storage = _FakeSyncStorage();
      final provider = SyncProvider(
        service: _FakeSyncService(
          pages: [
            SyncDownloadResult(
              changes: [
                _change(seq: 1, changeId: 'duplicate', recordId: 'm1'),
                _change(seq: 2, changeId: 'duplicate', recordId: 'm2'),
              ],
              latestSeq: 2,
              hasMore: false,
              nextSince: 2,
            ),
          ],
        ),
        storage: storage,
      );
      final oldDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {};
      addTearDown(() => debugPrint = oldDebugPrint);

      await provider.bindScope('user-1');
      await provider.autoDownload();

      expect(provider.error, contains('页内重复'));
      expect(storage.appliedOps, isEmpty);
      expect(storage.sinceByScope[provider.scope], 0);
    });

    test('rejects non-increasing seq in a page', () async {
      final storage = _FakeSyncStorage();
      final provider = SyncProvider(
        service: _FakeSyncService(
          pages: [
            SyncDownloadResult(
              changes: [
                _change(seq: 1, changeId: 'remote-1', recordId: 'm1'),
                _change(seq: 1, changeId: 'remote-2', recordId: 'm2'),
              ],
              latestSeq: 1,
              hasMore: false,
              nextSince: 1,
            ),
          ],
        ),
        storage: storage,
      );
      final oldDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {};
      addTearDown(() => debugPrint = oldDebugPrint);

      await provider.bindScope('user-1');
      await provider.autoDownload();

      expect(provider.error, contains('严格递增'));
      expect(storage.appliedOps, isEmpty);
      expect(storage.sinceByScope[provider.scope], 0);
    });

    test('rejects nextSince below the maximum page seq', () async {
      final storage = _FakeSyncStorage();
      final provider = SyncProvider(
        service: _FakeSyncService(
          pages: [
            SyncDownloadResult(
              changes: [_change(seq: 2, changeId: 'remote-2', recordId: 'm2')],
              latestSeq: 2,
              hasMore: false,
              nextSince: 1,
            ),
          ],
        ),
        storage: storage,
      );
      final oldDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {};
      addTearDown(() => debugPrint = oldDebugPrint);

      await provider.bindScope('user-1');
      await provider.autoDownload();

      expect(provider.error, contains('未覆盖最大 seq'));
      expect(storage.appliedOps, isEmpty);
      expect(storage.sinceByScope[provider.scope], 0);
    });
  });
}

const _hashA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _hashB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

SyncOutboxEntry _resourceEntry(String id, String hash) => SyncOutboxEntry(
  table: 'resources',
  recordId: id,
  op: 'upsert',
  data: {'id': id, 'role': 'message_attachment', 'sha256': hash},
  changeId: 'change-$id',
  deviceId: 'device-1',
  clientCreatedAt: DateTime.utc(2026, 7, 16),
  mutationVersion: 1,
);

SyncDownloadResult _resourcePage(String hash) => SyncDownloadResult(
  changes: [
    SyncChange(
      seq: 1,
      changeId: 'remote-1',
      deviceId: 'device-2',
      clientCreatedAt: DateTime.utc(2026, 7, 16),
      table: 'resources',
      op: 'upsert',
      recordId: 'r1',
      data: {
        'id': 'r1',
        'role': 'message_attachment',
        'sha256': hash,
        'relativePath': '../../outside',
        'missing': false,
      },
    ),
  ],
  latestSeq: 1,
  hasMore: false,
  nextSince: 1,
);

SyncDownloadResult _page({required int seq, required bool hasMore}) {
  return SyncDownloadResult(
    changes: [
      SyncChange(
        seq: seq,
        changeId: 'remote-$seq',
        deviceId: 'device-2',
        clientCreatedAt: DateTime.utc(2026, 7, 16),
        table: 'messages',
        op: 'upsert',
        recordId: 'm$seq',
        data: {'id': 'm$seq'},
      ),
    ],
    latestSeq: 2,
    hasMore: hasMore,
    nextSince: seq,
  );
}

SyncDownloadResult _notePage({required int seq, required bool hasMore}) {
  return SyncDownloadResult(
    changes: [
      SyncChange(
        seq: seq,
        changeId: 'note-$seq',
        deviceId: 'device-2',
        clientCreatedAt: DateTime.utc(2026, 7, 16),
        table: 'note_pages',
        op: 'upsert',
        recordId: 'p$seq',
        data: {'id': 'p$seq'},
      ),
    ],
    latestSeq: 3,
    hasMore: hasMore,
    nextSince: seq,
  );
}

SyncChange _change({
  required int seq,
  required String changeId,
  required String recordId,
}) => SyncChange(
  seq: seq,
  changeId: changeId,
  deviceId: 'device-2',
  clientCreatedAt: DateTime.utc(2026, 7, 16),
  table: 'messages',
  op: 'upsert',
  recordId: recordId,
  data: {'id': recordId},
);

SyncDownloadResult _invalidPage({
  String table = 'messages',
  String dataId = 'm1',
}) {
  return SyncDownloadResult(
    changes: [
      SyncChange(
        seq: 1,
        changeId: 'remote-1',
        deviceId: 'device-2',
        clientCreatedAt: DateTime.utc(2026, 7, 16),
        table: table,
        op: 'upsert',
        recordId: 'm1',
        data: {'id': dataId},
      ),
    ],
    latestSeq: 1,
    hasMore: false,
    nextSince: 1,
  );
}

SyncOutboxEntry _entry(String id, {required int version}) => SyncOutboxEntry(
  table: 'messages',
  recordId: id,
  op: 'upsert',
  data: {'id': id},
  changeId: 'change-$id-$version',
  deviceId: 'device-1',
  clientCreatedAt: DateTime.utc(2026, 7, 16),
  mutationVersion: version,
);

SyncOutboxEntry _entryWithData(
  String id, {
  required Map<String, dynamic> data,
}) => SyncOutboxEntry(
  table: 'messages',
  recordId: id,
  op: 'upsert',
  data: data,
  changeId: 'change-$id',
  deviceId: 'device-1',
  clientCreatedAt: DateTime.utc(2026, 7, 16),
  mutationVersion: 1,
);

class _FakeSyncStorage implements SyncStorage {
  _FakeSyncStorage({
    List<SyncOutboxEntry> outbox = const [],
    this.resourceBlobs = const [],
    this.resourceBlobReaders = const {},
    this.hashMismatch = false,
    this.acknowledgeConflict = false,
  }) : outbox = List.of(outbox);

  final Map<String, int> sinceByScope = {};
  final List<String> activated = [];
  final List<String> deactivated = [];
  final List<int> appliedSince = [];
  final List<SyncOutboxEntry> acknowledged = [];
  final List<SyncOutboxEntry> outbox;
  final List<SyncResourceBlob> resourceBlobs;
  final Map<String, Future<List<int>> Function()> resourceBlobReaders;
  final bool hashMismatch;
  final bool acknowledgeConflict;
  final Set<String> localHashes = {};
  final List<String> installedHashes = [];
  final List<SyncRemoteOperation> appliedOps = [];
  final List<int?> loadOutboxLimits = [];
  final List<String> readBlobHashes = [];
  int maxLoadedOutbox = 0;
  int materializeCalls = 0;

  @override
  Future<void> activateScope(String scope, String deviceId) async {
    activated.add(scope);
    sinceByScope.putIfAbsent(scope, () => 0);
  }

  @override
  Future<void> deactivateScope(String scope) async => deactivated.add(scope);

  @override
  Future<int> since(String scope) async => sinceByScope[scope] ?? 0;

  @override
  Future<List<SyncOutboxEntry>> loadOutbox(
    String scope, {
    int? limit,
    int offset = 0,
  }) async {
    loadOutboxLimits.add(limit);
    final end = limit == null
        ? outbox.length
        : (offset + limit).clamp(0, outbox.length);
    final result = offset >= outbox.length
        ? <SyncOutboxEntry>[]
        : outbox.sublist(offset, end);
    if (result.length > maxLoadedOutbox) maxLoadedOutbox = result.length;
    return List.of(result);
  }

  @override
  Future<List<SyncConflictEntry>> loadConflicts(String scope) async => const [];

  @override
  Future<void> resolveConflict(
    String scope,
    int seq,
    SyncConflictResolution resolution,
  ) async {}

  @override
  Future<bool> acknowledgeOutbox(
    String scope,
    List<SyncOutboxEntry> entries,
  ) async {
    acknowledged.addAll(entries);
    outbox.removeWhere(
      (item) => entries.any(
        (entry) =>
            entry.table == item.table &&
            entry.recordId == item.recordId &&
            entry.mutationVersion == item.mutationVersion,
      ),
    );
    return acknowledgeConflict;
  }

  @override
  Future<void> applyRemoteChanges(
    String scope,
    List<SyncRemoteOperation> ops,
    int nextSince,
  ) async {
    appliedOps.addAll(ops);
    appliedSince.add(nextSince);
    sinceByScope[scope] = nextSince;
  }

  @override
  Future<void> updateSince(String scope, int since) async {
    sinceByScope[scope] = since;
  }

  @override
  Future<List<SyncResourceBlob>> resourceBlobsForOutbox(
    List<SyncOutboxEntry> entries,
  ) async => resourceBlobs;

  @override
  Future<List<SyncBlobDescriptor>> resourceBlobDescriptorsForOutbox(
    List<SyncOutboxEntry> entries,
  ) async {
    if (resourceBlobReaders.isEmpty) {
      return [
        for (final blob in resourceBlobs)
          SyncBlobDescriptor(
            sha256: blob.sha256,
            readBytes: () async => blob.bytes,
          ),
      ];
    }
    return [
      for (final item in resourceBlobReaders.entries)
        SyncBlobDescriptor(
          sha256: item.key,
          readBytes: () async {
            readBlobHashes.add(item.key);
            return item.value();
          },
        ),
    ];
  }

  @override
  Future<bool> hasResourceBlob(String sha256) async =>
      localHashes.contains(sha256);

  @override
  Future<void> installResourceBlob(String sha256, List<int> bytes) async {
    if (hashMismatch) throw StateError('hash mismatch');
    installedHashes.add(sha256);
    localHashes.add(sha256);
  }

  @override
  Future<bool> hasNoteBlob(String sha256) async => localHashes.contains(sha256);

  @override
  Future<void> installNoteBlob(String sha256, List<int> bytes) async {
    installedHashes.add(sha256);
    localHashes.add(sha256);
  }

  @override
  Future<void> materializeNotes() async => materializeCalls++;

  @override
  Map<String, dynamic> normalizeRemoteResource(Map<String, dynamic> data) {
    final hash = data['sha256'] as String?;
    if (data['missing'] != true && hash == null) {
      throw StateError('remote resource missing hash');
    }
    return {
      ...data,
      'relativePath': hash == null
          ? null
          : 'assets/blobs/${hash.substring(0, 2)}/$hash',
      'missing': hash == null,
    };
  }
}

class _BlockingSyncService extends _FakeSyncService {
  _BlockingSyncService(this.response);

  final Future<SyncDownloadResult> response;
  final requestStarted = Completer<void>();

  @override
  Future<SyncDownloadResult> getChanges({required int since, int limit = 500}) {
    if (!requestStarted.isCompleted) requestStarted.complete();
    return response;
  }
}

class _FakeSyncService implements SyncService {
  _FakeSyncService({
    List<SyncDownloadResult> pages = const [],
    this.uploadError,
    this.downloadError,
    this.delay = Duration.zero,
    this.remoteBlobs = const {},
    this.downloadedBlobs = const {},
    this.uploadResult,
    this.limits = const SyncLimits(),
  }) : _pages = List.of(pages);

  final List<SyncDownloadResult> _pages;
  final Object? uploadError;
  final Object? downloadError;
  final Duration delay;
  final Set<String> remoteBlobs;
  final Map<String, List<int>> downloadedBlobs;
  final SyncUploadResult? uploadResult;
  final SyncLimits limits;
  final List<int> requestedSince = [];
  final List<int> requestedLimits = [];
  final List<String> uploadedBlobs = [];
  final List<int> listBlobLimits = [];
  final List<String> downloadedHashes = [];
  final List<String> calls = [];
  final List<int> uploadedBatchSizes = [];
  final List<int> uploadedBodySizes = [];
  final List<String> uploadedRecordIds = [];
  int activeCalls = 0;
  int maxActiveCalls = 0;

  Future<T> _call<T>(FutureOr<T> Function() action) async {
    activeCalls++;
    if (activeCalls > maxActiveCalls) maxActiveCalls = activeCalls;
    try {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      return await action();
    } finally {
      activeCalls--;
    }
  }

  @override
  Future<SyncDownloadResult> getChanges({
    required int since,
    int limit = 500,
  }) => _call(() {
    requestedSince.add(since);
    requestedLimits.add(limit);
    if (_pages.isNotEmpty) return _pages.removeAt(0);
    return SyncDownloadResult(
      changes: const [],
      latestSeq: since,
      hasMore: false,
      nextSince: since,
    );
  });

  @override
  Future<SyncUploadResult> uploadChanges(List<SyncChangeRecord> changes) =>
      _call(() {
        calls.add('uploadChanges');
        uploadedBatchSizes.add(changes.length);
        uploadedRecordIds.addAll(changes.map((change) => change.recordId));
        uploadedBodySizes.add(
          utf8
              .encode(
                jsonEncode({
                  'requestId': RemoteSyncService.requestIdForChanges(changes),
                  'changes': changes.map((change) => change.toJson()).toList(),
                }),
              )
              .length,
        );
        if (uploadError != null) throw uploadError!;
        return uploadResult ??
            SyncUploadResult(
              latestSeq: 0,
              acknowledgements: changes
                  .map(
                    (change) => SyncAcknowledgement(
                      changeId: change.changeId,
                      mutationVersion: change.mutationVersion,
                    ),
                  )
                  .toList(growable: false),
            );
      });

  @override
  Future<SyncStatus> getStatus() async =>
      SyncStatus(lastSeq: 0, blobCount: 0, limits: limits);

  @override
  Future<List<BlobInfo>> listBlobs({int limit = 1000}) async {
    calls.add('listBlobs');
    listBlobLimits.add(limit);
    return remoteBlobs.map((hash) => BlobInfo(sha256: hash, size: 1)).toList();
  }

  @override
  Future<List<int>> downloadBlob(String sha256) async {
    downloadedHashes.add(sha256);
    if (downloadError != null) throw downloadError!;
    return downloadedBlobs[sha256] ?? const [];
  }

  @override
  Future<void> uploadBlob(String sha256, List<int> bytes) async {
    calls.add('uploadBlob:$sha256');
    uploadedBlobs.add(sha256);
  }
}
