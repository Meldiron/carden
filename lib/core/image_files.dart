import 'dart:typed_data';

import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'appwrite.dart';

/// Bytes of a picture, cached on disk by [DefaultCacheManager] (on the web in [RecentPictures]).
///
/// Catalogue pictures are public Storage files and load straight from their URL. Player photos
/// (My Puzzles) and the pictures of private packs (opened with a pack code) are private files that
/// only some players can read, so they are fetched through the signed-in Appwrite client (session
/// cookie on iOS, cookie fallback on the web) and then cached under the same URL key.
class ImageFiles {
  ImageFiles._();

  static Storage? _storage;

  /// Called once by the app root with the app's Appwrite [Storage].
  static void attach(Storage storage) => _storage = storage;

  static const _privateBuckets = [AppwriteConfig.userUploadsBucket, AppwriteConfig.privatePacksBucket];

  /// The private file a URL points at (bucket, file id and, for a preview URL, its width), or null
  /// for a public picture.
  static ({String bucket, String fileId, int? width})? privateFile(String url) {
    for (final bucket in _privateBuckets) {
      final base = '${AppwriteConfig.endpoint}/storage/buckets/$bucket/files/';
      if (!url.startsWith(base)) continue;
      final rest = url.substring(base.length);
      final id = rest.split('/').first;
      if (id.isEmpty) return null;
      final preview = rest.startsWith('$id/preview');
      final width = preview ? int.tryParse(Uri.tryParse(url)?.queryParameters['width'] ?? '') : null;
      return (bucket: bucket, fileId: id, width: width);
    }
    return null;
  }

  /// File id of a private picture URL (player photo or private pack), or null for any other picture.
  static String? privateFileId(String url) => privateFile(url)?.fileId;

  static final _web = RecentPictures(maxBytes: 32 << 20);
  static final _http = HttpFileService();

  static Future<Uint8List> bytes(String url) async {
    final file = privateFile(url);
    final storage = _storage;
    if (kIsWeb) return _web.get(url, () => file != null && storage != null ? _private(storage, file) : _public(url));
    final cache = DefaultCacheManager();
    if (file == null || storage == null) {
      return (await cache.getSingleFile(url)).readAsBytes();
    }
    final hit = await cache.getFileFromCache(url);
    if (hit != null) return hit.file.readAsBytes();
    final data = await _private(storage, file);
    await cache.putFile(url, data, fileExtension: 'jpg', maxAge: const Duration(days: 30));
    return data;
  }

  static Future<Uint8List> _private(Storage storage, ({String bucket, String fileId, int? width}) file) {
    final width = file.width;
    return width != null
        ? storage.getFilePreview(bucketId: file.bucket, fileId: file.fileId, width: width, quality: 82)
        : storage.getFileView(bucketId: file.bucket, fileId: file.fileId);
  }

  static Future<Uint8List> _public(String url) async {
    final response = await _http.get(url);
    if (response.statusCode != 200) throw StateError('HTTP ${response.statusCode} for $url');
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.content) {
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }
}

/// The web's memory of recently used pictures. On the web [DefaultCacheManager] keeps every file it
/// fetched in memory and never removes one (its file system is in memory and its index stores
/// nothing), so a long session held every tile and picture it had shown. This keeps the most
/// recently used up to [maxBytes] and lets the oldest go; the browser's own HTTP cache keeps the
/// files (Storage sends a 45-day max-age), so a picture read again comes from the disk, not the
/// network. Two reads of one picture at once share one fetch.
class RecentPictures {
  RecentPictures({required this.maxBytes});

  final int maxBytes;

  // Insertion order is use order: the first entry is the one used longest ago.
  final _kept = <String, Uint8List>{};
  final _fetching = <String, Future<Uint8List>>{};
  var _bytes = 0;

  /// Bytes held now.
  int get bytes => _bytes;

  Future<Uint8List> get(String url, Future<Uint8List> Function() fetch) {
    final hit = _kept.remove(url);
    if (hit != null) {
      _kept[url] = hit;
      return Future.value(hit);
    }
    return _fetching[url] ??= fetch().then((data) {
      _keep(url, data);
      return data;
    }).whenComplete(() {
      _fetching.remove(url); // a block: returning the removed future would make this wait on itself
    });
  }

  void _keep(String url, Uint8List data) {
    if (data.length > maxBytes) return;
    final old = _kept.remove(url);
    if (old != null) _bytes -= old.length;
    _kept[url] = data;
    _bytes += data.length;
    while (_bytes > maxBytes) {
      final oldest = _kept.keys.first;
      _bytes -= _kept.remove(oldest)!.length;
    }
  }
}
