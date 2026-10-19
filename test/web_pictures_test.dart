import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:carden/core/image_files.dart';
import 'package:carden/game/image_loader.dart';
import 'package:flutter_test/flutter_test.dart';

// The web's picture memory (2026-10-19): giant pictures decoded at most webGiantSide on their
// longer side (their size read from the header), and RecentPictures in place of the cache
// manager's memory, which never let a picture go.
void main() {
  group('encodedSize', () {
    testWidgets('matches the decoded size of the bundled JPEGs and a PNG', (tester) async {
      await tester.runAsync(() async {
        final files = [
          ...Directory('assets/welcome').listSync().whereType<File>().where((f) => f.path.endsWith('.jpg')),
          File('web/icons/Icon-192.png'),
        ];
        expect(files.length, greaterThan(5));
        for (final f in files) {
          final bytes = f.readAsBytesSync();
          final codec = await ui.instantiateImageCodec(bytes);
          final image = (await codec.getNextFrame()).image;
          expect(encodedSize(bytes), (image.width, image.height), reason: f.path);
          image.dispose();
          codec.dispose();
        }
      });
    });

    test('reads a progressive JPEG past its other segments, as the giant pictures are', () {
      final bytes = Uint8List.fromList([
        0xFF, 0xD8, // start of image
        0xFF, 0xE0, 0x00, 0x06, 0x4A, 0x46, 0x49, 0x46, // APP0
        0xFF, 0xDB, 0x00, 0x03, 0x00, // a quantisation table
        0xFF, 0xFF, // fill byte
        0xFF, 0xC2, 0x00, 0x11, 0x08, 0x10, 0x00, 0x0C, 0x00, 0x03, 0, 0, 0, 0, 0, 0, 0, 0, 0, // SOF2: 3072 x 4096
      ]);
      expect(encodedSize(bytes), (3072, 4096));
    });

    test('is null for anything else', () {
      expect(encodedSize(Uint8List.fromList([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0, 0, 0, 0])), isNull);
      expect(encodedSize(Uint8List.fromList([0xFF, 0xD8, 0xFF])), isNull);
      expect(encodedSize(Uint8List(0)), isNull);
    });
  });

  test('fitLongerSide holds the longer side to the limit and keeps small pictures', () {
    expect(fitLongerSide((3072, 4096), webGiantSide), (null, 2048));
    expect(fitLongerSide((4096, 3072), webGiantSide), (2048, null));
    expect(fitLongerSide((4096, 4096), webGiantSide), (2048, null));
    expect(fitLongerSide((1600, 2048), webGiantSide), (null, null));
    expect(fitLongerSide(null, webGiantSide), (2048, null));
  });

  group('RecentPictures', () {
    Uint8List kb(int n) => Uint8List(n * 1024);

    test('lets the picture used longest ago go once over the limit', () async {
      final cache = RecentPictures(maxBytes: 10 * 1024);
      var fetches = 0;
      Future<Uint8List> fetch(int n) async {
        fetches++;
        return kb(n);
      }

      await cache.get('a', () => fetch(4));
      await cache.get('b', () => fetch(4));
      await cache.get('a', () => fetch(4)); // a is now the newest
      expect(fetches, 2);
      await cache.get('c', () => fetch(4)); // 12 KB: b goes
      expect(cache.bytes, 8 * 1024);
      await cache.get('a', () => fetch(4));
      expect(fetches, 3);
      await cache.get('b', () => fetch(4));
      expect(fetches, 4);
      expect(cache.bytes, lessThanOrEqualTo(10 * 1024));
    });

    test('shares one fetch between reads at once and keeps nothing bigger than the limit', () async {
      final cache = RecentPictures(maxBytes: 4 * 1024);
      var fetches = 0;
      Future<Uint8List> fetch() async {
        fetches++;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return kb(8);
      }

      final both = await Future.wait([cache.get('big', fetch), cache.get('big', fetch)]);
      expect(fetches, 1);
      expect(both[0].length, 8 * 1024);
      expect(cache.bytes, 0);
      await cache.get('big', fetch);
      expect(fetches, 2);
    });

    test('a failed fetch is not kept and the next read tries again', () async {
      final cache = RecentPictures(maxBytes: 4 * 1024);
      await expectLater(cache.get('x', () async => throw StateError('HTTP 500')), throwsStateError);
      expect(await cache.get('x', () async => kb(1)), hasLength(1024));
      expect(cache.bytes, 1024);
    });
  });
}
