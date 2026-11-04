import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// App Review rejected 2.0.0 (Guideline 2.3.2, 2026-11-04) over the VIP promotional images: one image shared by
/// both plans, text too small to read and a price reference ("7 days free"). The images now carry no text
/// (tools/store/make_promo.py, tools/brand/vip-promo.js); tools/store/asc_publish.py refuses the same mistakes on upload.
void main() {
  const plans = ['vip_monthly', 'vip_yearly'];
  Map<String, dynamic> plan(String id) => jsonDecode(File('store/metadata/subscriptions/$id.json').readAsStringSync()) as Map<String, dynamic>;

  test('each VIP plan has its own 1024 x 1024 RGB promotional image', () {
    final images = <String, Uint8List>{};
    for (final id in plans) {
      final path = plan(id)['promotionalImage'] as String;
      final bytes = File(path).readAsBytesSync();
      // A PNG: the signature, then the IHDR chunk with width, height, bit depth and colour type.
      expect(bytes.sublist(1, 4), utf8.encode('PNG'), reason: path);
      final header = ByteData.sublistView(bytes);
      expect(header.getUint32(16), 1024, reason: '$path width');
      expect(header.getUint32(20), 1024, reason: '$path height');
      expect(bytes[25], 2, reason: '$path must be RGB without alpha (PNG colour type 2)');
      images[path] = bytes;
    }
    expect(images.length, plans.length, reason: 'the plans must not share one promotional image');
    expect(images.values.first, isNot(equals(images.values.last)), reason: 'the two promotional images must differ');
  });

  test('VIP plan names and descriptions say nothing about price or a free trial', () {
    final priceWords = RegExp(r'free|trial|price|\d|[$€£]', caseSensitive: false);
    for (final id in plans) {
      final en = (plan(id)['localizations'] as Map)['en-US'] as Map;
      final name = en['name'] as String, description = en['description'] as String;
      expect(name.length, lessThanOrEqualTo(30), reason: '$id name');
      expect(description.length, lessThanOrEqualTo(45), reason: '$id description');
      for (final text in [name, description]) {
        expect(priceWords.hasMatch(text), isFalse, reason: '$id: "$text"');
      }
    }
  });
}
