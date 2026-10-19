import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
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
/// On the web it is decoded at most [webGiantSide] on its longer side (see there).
final puzzleImageFullProvider = FutureProvider.autoDispose.family<ui.Image, String>((ref, url) async {
  final link = ref.keepAlive();
  Timer? release;
  ref.onCancel(() => release = Timer(const Duration(seconds: 30), link.close));
  ref.onResume(() => release?.cancel());
  final image = await _decode(url, maxSide: kIsWeb ? webGiantSide : null);
  ref.onDispose(() {
    release?.cancel();
    image.dispose();
  });
  return image;
});

/// The decode for a picture: full size for giant boards, else the shared 1400 px one.
FutureProvider<ui.Image> puzzleImageFor(String url, {required bool giant}) => giant ? puzzleImageFullProvider(url) : puzzleImageProvider(url);

/// Longest side of a giant picture decoded on the web. A browser tab holds the picture several
/// times (the decode, its GPU texture with mipmaps): a 22x22 board of a 3072x4096 picture took
/// about 1.2 GB in Chromium, the likely cause of a tab crash on an 8 GB Mac (2026-10-19). At
/// 2048 px it is a quarter of the pixels, and a card at the zoom limit still shows about 70
/// picture pixels across on the biggest boards. The iPhone keeps the full size.
const webGiantSide = 2048;

/// Integration suites only: a pause before each picture is read, as a slow connection gives one, to
/// check what waits for the picture.
@visibleForTesting
Duration debugPictureDelay = Duration.zero;

/// Decodes [url] at [targetWidth], or with its longer side at most [maxSide].
Future<ui.Image> _decode(String url, {int? targetWidth, int? maxSide}) async {
  if (debugPictureDelay > Duration.zero) await Future<void>.delayed(debugPictureDelay);
  Uint8List bytes;
  if (url.startsWith('asset:')) {
    bytes = (await rootBundle.load(url.substring(6))).buffer.asUint8List();
  } else {
    bytes = await ImageFiles.bytes(url);
  }
  int? targetHeight;
  if (maxSide != null) (targetWidth, targetHeight) = fitLongerSide(encodedSize(bytes), maxSide);
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: targetWidth, targetHeight: targetHeight, allowUpscaling: false);
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

/// The target width or height that brings a picture of [size] to at most [maxSide] on its longer
/// side (the other follows the picture's shape), (null, null) when it is small enough; a picture
/// whose size could not be read is held to [maxSide] in width.
@visibleForTesting
(int?, int?) fitLongerSide((int, int)? size, int maxSide) {
  if (size == null) return (maxSide, null);
  final (w, h) = size;
  if (w <= maxSide && h <= maxSide) return (null, null);
  return w >= h ? (maxSide, null) : (null, maxSide);
}

/// Width and height of a JPEG or PNG from its header, without decoding it (the web cannot read
/// an `ImageDescriptor`); null for any other format or a header it cannot read.
@visibleForTesting
(int, int)? encodedSize(Uint8List b) {
  int u16(int i) => (b[i] << 8) | b[i + 1];
  // PNG: the signature, then the IHDR chunk's width and height.
  if (b.length >= 24 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
    return ((u16(16) << 16) | u16(18), (u16(20) << 16) | u16(22));
  }
  // JPEG: segment by segment to the first start of frame, which holds the height, then the width.
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
  var i = 2;
  while (i + 8 < b.length) {
    if (b[i] != 0xFF) return null;
    final marker = b[i + 1];
    if (marker == 0xFF) {
      i++; // fill byte
    } else if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD8)) {
      i += 2; // a marker without a length
    } else if (marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC) {
      return (u16(i + 7), u16(i + 5));
    } else {
      i += 2 + u16(i + 2);
    }
  }
  return null;
}
