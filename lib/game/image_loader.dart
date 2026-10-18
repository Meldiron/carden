import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/image_files.dart';

/// Loads and decodes a puzzle image once (cached on disk, see [ImageFiles]).
final puzzleImageProvider = FutureProvider.autoDispose.family<ui.Image, String>((ref, url) async {
  final keep = ref.keepAlive();
  final image = await _decode(url, targetWidth: 1400);
  ref.onDispose(() {
    keep.close();
  });
  return image;
});

/// A Giant pack picture decoded at its full size (up to 4096 px): boards of 100 to 300 cards are
/// zoomed in up to 4x, where a 1400 px decode looks soft. Such a decode takes about 50 MB, so it
/// is not kept for the whole session like [puzzleImageProvider]: it stays 30 seconds after the
/// last screen stops using it (the difficulty screen hands over to the game), then it is freed.
final puzzleImageFullProvider = FutureProvider.autoDispose.family<ui.Image, String>((ref, url) async {
  final link = ref.keepAlive();
  Timer? release;
  ref.onCancel(() => release = Timer(const Duration(seconds: 30), link.close));
  ref.onResume(() => release?.cancel());
  final image = await _decode(url);
  ref.onDispose(() {
    release?.cancel();
    image.dispose();
  });
  return image;
});

/// The decode for a picture: full size for giant boards, else the shared 1400 px one.
FutureProvider<ui.Image> puzzleImageFor(String url, {required bool giant}) => giant ? puzzleImageFullProvider(url) : puzzleImageProvider(url);

/// Integration suites only: a pause before each picture is read, as a slow connection gives one, to
/// check what waits for the picture.
@visibleForTesting
Duration debugPictureDelay = Duration.zero;

Future<ui.Image> _decode(String url, {int? targetWidth}) async {
  if (debugPictureDelay > Duration.zero) await Future<void>.delayed(debugPictureDelay);
  Uint8List bytes;
  if (url.startsWith('asset:')) {
    bytes = (await rootBundle.load(url.substring(6))).buffer.asUint8List();
  } else {
    bytes = await ImageFiles.bytes(url);
  }
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: targetWidth, allowUpscaling: false);
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}
