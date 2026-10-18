import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/a11y.dart';
import '../core/numbers.dart';
import '../core/theme/tokens.dart';
import '../models/models.dart';

enum AvatarSource { free, coins, achievement }

/// One avatar in the catalogue.
class AvatarDef {
  const AvatarDef(this.key, this.name, this.icon, this.color, this.source, {this.achievementId, this.glyph = Colors.white});
  final String key;
  final String name;
  final IconData icon;
  final Color color;

  /// The symbol's colour on the disc (white, except VIP's gold).
  final Color glyph;
  final AvatarSource source;
  /// Achievement family that grants this avatar (tier n = step n).
  final String? achievementId;
}

/// Semantic icon system. Every pictogram in the app comes from here so the
/// visual language stays consistent: drawn currency marks (coin, ticket,
/// hint), SF-style Cupertino symbols wherever iOS has one, and Material
/// Symbols only where it has none (wheel, piggy bank, puzzle piece, VIP,
/// categories, board tiers).
class AppIcons {
  AppIcons._();

  // Navigation / sections
  static const home = CupertinoIcons.house_fill;
  static const library = CupertinoIcons.square_grid_2x2_fill;
  static const events = CupertinoIcons.gift_fill;
  /// Quests tab (daily and weekly quests plus live events).
  static const quests = CupertinoIcons.flag_fill;
  static const questsOutline = CupertinoIcons.flag;
  static const social = CupertinoIcons.person_2_fill;
  static const profile = CupertinoIcons.person_crop_circle_fill;

  // Meta features
  static const dailyGift = CupertinoIcons.gift_fill;
  static const wheel = Icons.donut_large_rounded;
  static const piggy = Icons.savings_rounded;
  static const dailyPuzzle = CupertinoIcons.calendar_today;
  static const streak = CupertinoIcons.flame_fill;
  static const xp = CupertinoIcons.sparkles;
  static const star = CupertinoIcons.star_fill;
  static const starOutline = CupertinoIcons.star;
  static const trophy = CupertinoIcons.chart_bar_alt_fill;
  static const crown = Icons.workspace_premium_rounded;
  static const vip = Icons.workspace_premium_rounded;
  static const lock = CupertinoIcons.lock_fill;
  static const unlock = CupertinoIcons.lock_open_fill;
  static const check = CupertinoIcons.checkmark_seal_fill;
  static const photo = CupertinoIcons.photo_on_rectangle;
  static const camera = CupertinoIcons.camera_fill;
  static const credit = CupertinoIcons.camera;
  static const community = CupertinoIcons.globe;
  static const friends = CupertinoIcons.person_2_fill;
  static const addFriend = CupertinoIcons.person_add_solid;
  static const report = CupertinoIcons.exclamationmark_bubble;
  static const block = CupertinoIcons.hand_raised;
  static const noEntry = CupertinoIcons.nosign;
  static const copy = CupertinoIcons.doc_on_doc;
  static const video = CupertinoIcons.play_circle_fill;
  static const bundle = CupertinoIcons.cube_box_fill;
  static const puzzle = Icons.extension_rounded;
  static const bigBoard = CupertinoIcons.square_grid_4x3_fill;

  /// Painting: cards start in black and white and get their colour back as they lock.
  static const painting = CupertinoIcons.paintbrush_fill;

  /// Expand (difficulty screen): the whole picture, columns and rows to fit it.
  static const expand = CupertinoIcons.arrow_up_left_arrow_down_right;

  /// Zoomed-in giant board: back to the whole board.
  static const wholeBoard = CupertinoIcons.arrow_down_right_arrow_up_left;
  static const zoom = CupertinoIcons.zoom_in;

  /// Giant boards: the overview map, and Locate (a tapped card's place on the map).
  static const minimap = CupertinoIcons.map;
  static const minimapOn = CupertinoIcons.map_fill;

  /// Gather (giant boards): bring the cards that belong in view into it.
  static const gather = Icons.zoom_in_map_rounded;

  /// Settings > Redeem a pack code.
  static const packCode = CupertinoIcons.ticket;

  /// Points at a selected card outside the zoomed view.
  static const towards = CupertinoIcons.arrow_up;
  static const level = CupertinoIcons.rosette;
  static const swaps = CupertinoIcons.arrow_right_arrow_left;
  static const time = CupertinoIcons.time;
  static const save = CupertinoIcons.cloud_upload_fill;
  /// A caution that is not an error (a guest's progress lives on this device only).
  static const caution = CupertinoIcons.exclamationmark_triangle_fill;
  static const signal = CupertinoIcons.antenna_radiowaves_left_right;
  static const wave = CupertinoIcons.hand_raised_fill;
  static const sparkle = CupertinoIcons.sparkles;
  static const balloon = CupertinoIcons.sparkles;
  static const image = CupertinoIcons.photo;
  static const mail = CupertinoIcons.envelope_fill;
  /// Outline, beside the other outline icons of Settings > Notifications (Messages from Carden).
  static const envelope = CupertinoIcons.envelope;
  static const receipt = CupertinoIcons.doc_plaintext;

  // Play together (docs/multiplayer.md).
  static const players = CupertinoIcons.person_2_fill;
  static const invite = CupertinoIcons.person_badge_plus;
  static const share = CupertinoIcons.share;
  static const leaveGame = CupertinoIcons.square_arrow_left;
  static const endGame = CupertinoIcons.xmark_circle;

  // Library filters that are not pack categories (drawn before the label).
  static const filterAll = CupertinoIcons.square_grid_2x2_fill;
  /// New packs: a burst, so it never reads as the AI mark (sparkles) in the same row.
  static const filterNew = CupertinoIcons.burst_fill;
  static const filterFinished = CupertinoIcons.checkmark_circle_fill;
  static const filterStarted = CupertinoIcons.play_circle_fill;
  static const filterUnlocked = CupertinoIcons.lock_open_fill;

  // How to play (the first-game tutorial)
  static const tapCard = Icons.touch_app_rounded;
  static const group = CupertinoIcons.square_on_square;

  // Boosters
  static const undo = CupertinoIcons.arrow_uturn_left;
  static const peek = CupertinoIcons.eye_fill;
  static const hint = CupertinoIcons.lightbulb_fill;
  static const magic = CupertinoIcons.wand_stars;

  // Interface glyphs used across screens (every icon in the app is named here).
  static const allModes = CupertinoIcons.square_grid_2x2;
  static const appleLogo = Icons.apple;
  static const arrowCounterclockwise = CupertinoIcons.arrow_counterclockwise;
  static const arrowRight = CupertinoIcons.arrow_right;
  static const back = CupertinoIcons.back;
  static const bag = CupertinoIcons.bag;
  static const bagFill = CupertinoIcons.bag_fill;
  static const bellFill = CupertinoIcons.bell_fill;
  static const checkmark = CupertinoIcons.checkmark;
  static const checkmarkAlt = CupertinoIcons.checkmark_alt;
  static const chevronLeft = CupertinoIcons.chevron_left;
  static const chevronRight = CupertinoIcons.chevron_right;
  static const clockFill = CupertinoIcons.clock_fill;
  static const coinGlyph = Icons.monetization_on_rounded;
  static const collector = CupertinoIcons.rectangle_on_rectangle_angled;
  static const devicePhonePortrait = CupertinoIcons.device_phone_portrait;
  static const docText = CupertinoIcons.doc_text;
  static const earlyBird = CupertinoIcons.sunrise_fill;
  static const eye = CupertinoIcons.eye;
  static const gearAltFill = CupertinoIcons.gear_alt_fill;
  static const gift = CupertinoIcons.gift;
  static const house = CupertinoIcons.house;
  static const listBullet = CupertinoIcons.list_bullet;
  static const lockShield = CupertinoIcons.lock_shield;
  static const marathon = CupertinoIcons.hourglass;
  static const modeCards = CupertinoIcons.rectangle_stack_fill;
  static const modeHexagons = CupertinoIcons.hexagon_fill;
  static const modeSquares = CupertinoIcons.square_fill;
  static const modeTriangles = CupertinoIcons.triangle_fill;
  static const musicNote2 = CupertinoIcons.music_note_2;
  static const nightOwl = CupertinoIcons.moon_fill;
  static const noHints = CupertinoIcons.lightbulb_slash_fill;
  static const pauseFill = CupertinoIcons.pause_fill;
  static const pencil = CupertinoIcons.pencil;
  static const person2 = CupertinoIcons.person_2;
  static const personCropCircle = CupertinoIcons.person_crop_circle;
  static const playFill = CupertinoIcons.play_fill;
  static const plus = CupertinoIcons.plus;
  static const questionCircle = CupertinoIcons.question_circle;
  static const search = CupertinoIcons.search;
  static const shuffle = CupertinoIcons.shuffle;
  static const sliderHorizontal3 = CupertinoIcons.slider_horizontal_3;
  static const speaker2Fill = CupertinoIcons.speaker_2_fill;
  static const speakerSlash = CupertinoIcons.speaker_slash;
  static const speakerSlashFill = CupertinoIcons.speaker_slash_fill;
  static const speed = CupertinoIcons.timer;
  static const squareArrowRight = CupertinoIcons.square_arrow_right;
  static const squareGrid2x2 = CupertinoIcons.square_grid_2x2;
  static const starHoarder = CupertinoIcons.star_circle_fill;
  static const tapToPlace = CupertinoIcons.hand_draw_fill;
  static const ticketGlyph = Icons.confirmation_number_rounded;
  static const trash = CupertinoIcons.trash;
  static const waveform = CupertinoIcons.waveform;
  static const xmark = CupertinoIcons.xmark;
  static const xmarkCircle = CupertinoIcons.xmark_circle;
  // Added for glyphs the screen batches introduced.
  static const arrowUpLeftArrowDownRight = CupertinoIcons.arrow_up_left_arrow_down_right;
  static const arrowUpRight = CupertinoIcons.arrow_up_right;
  static const bell = CupertinoIcons.bell;
  static const checkmarkCircleFill = CupertinoIcons.checkmark_circle_fill;
  static const circle = CupertinoIcons.circle;
  static const circleLefthalfFill = CupertinoIcons.circle_lefthalf_fill;
  // Settings > Accessibility.
  static const textSize = CupertinoIcons.textformat_size;
  static const reduceMotion = CupertinoIcons.slowmo;
  static const contrast = CupertinoIcons.circle_righthalf_fill;
  static const shapes = CupertinoIcons.square_on_circle;
  // Settings > Privacy.
  static const usageData = CupertinoIcons.chart_bar;
  static const clock = CupertinoIcons.clock;
  static const delete = CupertinoIcons.delete;
  static const docPlaintext = CupertinoIcons.doc_plaintext;
  static const chatBubbleText = CupertinoIcons.chat_bubble_text;
  static const ellipsis = CupertinoIcons.ellipsis;
  static const flag = CupertinoIcons.flag;
  static const infoCircle = CupertinoIcons.info_circle;
  static const musicNote = CupertinoIcons.music_note;
  static const play = CupertinoIcons.play;
  static const speaker2 = CupertinoIcons.speaker_2;
  static const squareArrowLeft = CupertinoIcons.square_arrow_left;
  static const timer = CupertinoIcons.timer;

  /// Icon for a pack category chip, or none: themed categories (Nature,
  /// Cities, Abstract...) and Event are plain words; only the three kinds of
  /// pack that play or are made differently carry a mark, on pack covers and
  /// on the Library's chips alike (owner, 2026-10-15: Daily, Giant, AI).
  static IconData? category(String category) => switch (category.toLowerCase()) {
        'daily' => Icons.calendar_month_rounded,
        'giant' => Icons.grid_on_rounded, // 100-300 card boards
        'ai' => Icons.auto_awesome_rounded, // generated pictures
        _ => null,
      };

  /// Icon for a board tier (index into GridSpec.tiers).
  static IconData tier(int index) => const [
        Icons.spa_rounded,
        Icons.eco_rounded,
        Icons.coffee_rounded,
        Icons.extension_rounded,
        Icons.local_fire_department_rounded,
        Icons.diamond_rounded,
        Icons.emoji_events_rounded,
        Icons.workspace_premium_rounded,
      ][index.clamp(0, 7)];

  static IconData eventType(EventType t) => switch (t) {
        EventType.seasonal => Icons.eco_rounded,
        EventType.social => Icons.public_rounded,
        EventType.weekly => Icons.bolt_rounded,
        EventType.daily => Icons.today_rounded,
      };

  /// Avatar catalogue. Keys are stored on the profile; a tiered avatar is
  /// stored as `family@tier` (e.g. `solver@3`).
  static const avatars = <AvatarDef>[
    // Free starters
    AvatarDef('fox', 'Fox', Icons.pets_rounded, Color(0xFFB45309), AvatarSource.free),
    AvatarDef('leaf', 'Leaf', Icons.eco_rounded, Color(0xFF15803D), AvatarSource.free),
    AvatarDef('drop', 'Drop', Icons.water_drop_rounded, Color(0xFF1D4ED8), AvatarSource.free),
    AvatarDef('star', 'Star', Icons.star_rounded, Color(0xFF4338CA), AvatarSource.free),
    // Shop
    AvatarDef('bolt', 'Bolt', Icons.bolt_rounded, Color(0xFF92400E), AvatarSource.coins),
    AvatarDef('heart', 'Heart', Icons.favorite_rounded, Color(0xFFBE123C), AvatarSource.coins),
    AvatarDef('flower', 'Flower', Icons.local_florist_rounded, Color(0xFFA21CAF), AvatarSource.coins),
    AvatarDef('sun', 'Sun', Icons.wb_sunny_rounded, Color(0xFFC2410C), AvatarSource.coins),
    AvatarDef('moon', 'Moon', Icons.nightlight_round, Color(0xFF3730A3), AvatarSource.coins),
    AvatarDef('rocket', 'Rocket', Icons.rocket_launch_rounded, Color(0xFF475569), AvatarSource.coins),
    AvatarDef('music', 'Note', Icons.music_note_rounded, Color(0xFF0F766E), AvatarSource.coins),
    AvatarDef('game', 'Controller', Icons.sports_esports_rounded, Color(0xFF6D28D9), AvatarSource.coins),
    AvatarDef('camera', 'Camera', Icons.photo_camera_rounded, Color(0xFF0369A1), AvatarSource.coins),
    AvatarDef('palette', 'Palette', Icons.palette_rounded, Color(0xFF9F1239), AvatarSource.coins),
    AvatarDef('diamond', 'Diamond', Icons.diamond_rounded, Color(0xFF0E7490), AvatarSource.coins),
    AvatarDef('sparkle', 'Sparkle', Icons.auto_awesome_rounded, Color(0xFF7E22CE), AvatarSource.coins),
    AvatarDef('anchor', 'Anchor', Icons.anchor_rounded, Color(0xFF1E3A8A), AvatarSource.coins),
    AvatarDef('cat', 'Cat', Icons.cruelty_free_rounded, Color(0xFF78350F), AvatarSource.coins),
    AvatarDef('mountain', 'Mountain', Icons.landscape_rounded, Color(0xFF365314), AvatarSource.coins),
    AvatarDef('wave', 'Wave', Icons.waves_rounded, Color(0xFF155E75), AvatarSource.coins),
    AvatarDef('coffee', 'Coffee', Icons.coffee_rounded, Color(0xFF713F12), AvatarSource.coins),
    AvatarDef('book', 'Book', Icons.menu_book_rounded, Color(0xFF5B5B66), AvatarSource.coins),
    AvatarDef('bike', 'Bicycle', Icons.pedal_bike_rounded, Color(0xFF115E59), AvatarSource.coins),
    AvatarDef('plane', 'Plane', Icons.flight_rounded, Color(0xFF1E40AF), AvatarSource.coins),
    AvatarDef('umbrella', 'Umbrella', Icons.beach_access_rounded, Color(0xFF9D174D), AvatarSource.coins),
    AvatarDef('snow', 'Snowflake', Icons.ac_unit_rounded, Color(0xFF1F5F8B), AvatarSource.coins),
    AvatarDef('pizza', 'Pizza', Icons.local_pizza_rounded, Color(0xFFB91C1C), AvatarSource.coins),
    AvatarDef('cake', 'Cake', Icons.cake_rounded, Color(0xFFBE185D), AvatarSource.coins),
    AvatarDef('globe', 'Globe', Icons.public_rounded, Color(0xFF166534), AvatarSource.coins),
    AvatarDef('key', 'Key', Icons.key_rounded, Color(0xFF854D0E), AvatarSource.coins),
    AvatarDef('ghost', 'Ghost', Icons.blur_on_rounded, Color(0xFF475569), AvatarSource.coins),
    AvatarDef('bug', 'Ladybird', Icons.bug_report_rounded, Color(0xFF991B1B), AvatarSource.coins),
    // Achievement rewards (tiered families share a key; tier is appended as @n)
    AvatarDef('solver', 'Solver', Icons.extension_rounded, Color(0xFF4338CA), AvatarSource.achievement, achievementId: 'solver'),
    AvatarDef('perfect', 'Perfectionist', Icons.star_rounded, Color(0xFFB45309), AvatarSource.achievement, achievementId: 'perfect'),
    AvatarDef('flame', 'Streak', Icons.local_fire_department_rounded, Color(0xFFC2410C), AvatarSource.achievement, achievementId: 'streak'),
    AvatarDef('medal', 'Veteran', Icons.military_tech_rounded, Color(0xFF6D28D9), AvatarSource.achievement, achievementId: 'level'),
    AvatarDef('cards', 'Card Sharp', Icons.style_rounded, Color(0xFF0F766E), AvatarSource.achievement, achievementId: 'cards'),
    AvatarDef('square', 'Square Deal', Icons.grid_view_rounded, Color(0xFF1D4ED8), AvatarSource.achievement, achievementId: 'squares'),
    AvatarDef('triangle', 'Triangulate', Icons.change_history_rounded, Color(0xFF9F1239), AvatarSource.achievement, achievementId: 'triangles'),
    AvatarDef('hex', 'Honeycomb', Icons.hexagon_rounded, Color(0xFF92400E), AvatarSource.achievement, achievementId: 'hexagons'),
    AvatarDef('grid', 'Big Boards', Icons.grid_on_rounded, Color(0xFF475569), AvatarSource.achievement, achievementId: 'big'),
    AvatarDef('crown', 'Master', Icons.workspace_premium_rounded, Color(0xFF854D0E), AvatarSource.achievement, achievementId: 'master'),
    AvatarDef('mind', 'No Hints', Icons.psychology_rounded, Color(0xFF3730A3), AvatarSource.achievement, achievementId: 'nohints'),
    AvatarDef('album', 'Collector', Icons.collections_bookmark_rounded, Color(0xFF0369A1), AvatarSource.achievement, achievementId: 'collector'),
    AvatarDef('calendar', 'Daily Devotee', Icons.today_rounded, Color(0xFF15803D), AvatarSource.achievement, achievementId: 'daily'),
    AvatarDef('ticket', 'Event Goer', Icons.confirmation_number_rounded, Color(0xFFBE123C), AvatarSource.achievement, achievementId: 'events'),
    AvatarDef('owl', 'Night Owl', Icons.dark_mode_rounded, Color(0xFF4A5578), AvatarSource.achievement, achievementId: 'nightowl'),
    AvatarDef('bird', 'Early Bird', Icons.wb_twilight_rounded, Color(0xFFC2410C), AvatarSource.achievement, achievementId: 'earlybird'),
    AvatarDef('speed', 'Quick Hands', Icons.speed_rounded, Color(0xFF0E7490), AvatarSource.achievement, achievementId: 'speed'),
    AvatarDef('marathon', 'Marathon', Icons.directions_run_rounded, Color(0xFF065F46), AvatarSource.achievement, achievementId: 'marathon'),
    AvatarDef('shapes', 'All Modes', Icons.category_rounded, Color(0xFF7E22CE), AvatarSource.achievement, achievementId: 'allmodes'),
    AvatarDef('stars', 'Star Hoarder', Icons.stars_rounded, Color(0xFFA16207), AvatarSource.achievement, achievementId: 'starhoarder'),
    AvatarDef('vault', 'Rich', Icons.savings_rounded, Color(0xFF166534), AvatarSource.achievement, achievementId: 'rich'),
    AvatarDef('vip', 'VIP', Icons.workspace_premium_rounded, Color(0xFF26262E), AvatarSource.achievement, achievementId: 'vip', glyph: Brand.coin),
    AvatarDef('friends', 'Social', Icons.people_alt_rounded, Color(0xFF155E75), AvatarSource.achievement, achievementId: 'social'),
  ];

  static const freeAvatarKeys = ['fox', 'leaf', 'drop', 'star'];

  /// Splits `family@tier` into its parts; plain keys are tier 1.
  static ({String family, int tier}) splitAvatarKey(String? key) {
    if (key == null || key.isEmpty) return (family: 'fox', tier: 1);
    final i = key.indexOf('@');
    if (i < 0) return (family: key, tier: 1);
    return (family: key.substring(0, i), tier: int.tryParse(key.substring(i + 1)) ?? 1);
  }

  static AvatarDef avatar(String? key) {
    final family = splitAvatarKey(key).family;
    return avatars.firstWhere((a) => a.key == family, orElse: () => avatars.first);
  }
}

/// What a price or a reward is counted in. Peeks and Magic are boosters in stock (Lucky Wheel
/// prizes), never a price.
enum Currency { coins, tickets, hints, peeks, magics }

/// Round gold coin with an embossed star – the app's coin mark.
class CoinIcon extends StatelessWidget {
  const CoinIcon({super.key, this.size = 18, this.mono = false, this.color});
  final double size;

  /// With Increase contrast, a silhouette on a filled surface (white unless [color] is given, or
  /// the [CurrencyInk]); otherwise the coin keeps its gold.
  final bool mono;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final contrast = A11y.increaseContrastOf(context);
    final ink = contrast ? (color ?? (mono ? Colors.white : CurrencyInk.of(context))) : null;
    if (ink != null) return Icon(CupertinoIcons.star_circle_fill, size: size, color: ink);
    // Increase contrast in light mode: a deeper rim, 3:1 on white.
    final edge = contrast && !context.isDark ? const Color(0xFFAD7A00) : const Color(0xFFE09E00);
    return CustomPaint(size: Size.square(size), painter: _CoinPainter(edge));
  }
}

class _CoinPainter extends CustomPainter {
  _CoinPainter(this.edge);
  final Color edge;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..color = edge);
    canvas.drawCircle(
      c.translate(0, -r * 0.06),
      r * 0.92,
      Paint()
        ..shader = const RadialGradient(center: Alignment(-0.3, -0.4), colors: [Color(0xFFFFE08A), Color(0xFFFFC53D)]).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.drawCircle(c, r * 0.68, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, r * 0.12)
      ..color = const Color(0xFFE09E00).withValues(alpha: 0.85));
    final path = Path();
    const n = 5;
    for (var i = 0; i < n * 2; i++) {
      final a = -math.pi / 2 + i * math.pi / n;
      final rad = i.isEven ? r * 0.42 : r * 0.19;
      final p = Offset(c.dx + math.cos(a) * rad, c.dy + math.sin(a) * rad);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFB97800));
  }

  @override
  bool shouldRepaint(covariant _CoinPainter o) => o.edge != edge;
}

/// Monochrome ink for currency marks drawn on a filled surface (a primary
/// or tinted button). [BigButton] provides it with its label colour, so a
/// ticket on a cobalt button turns into a white pass instead of a teal one
/// that fights the blue. Coins and hints keep their colours: gold and amber
/// read well on the accent.
class CurrencyInk extends InheritedWidget {
  const CurrencyInk({super.key, required this.color, required super.child});
  final Color color;

  static Color? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<CurrencyInk>()?.color;

  @override
  bool updateShouldNotify(CurrencyInk old) => old.color != color;
}

/// Teal admission ticket with notched sides.
///
/// On a filled surface it is drawn as a monochrome silhouette: either when
/// [mono] is set (white, or [color]) or inside a [CurrencyInk]. The star and
/// the tear line are cut out, so the fill underneath shows through them.
class TicketIcon extends StatelessWidget {
  const TicketIcon({super.key, this.size = 18, this.mono = false, this.color});
  final double size;
  /// Silhouette for accent-coloured buttons (white unless [color] is given).
  final bool mono;
  /// Ink of the silhouette; setting it implies [mono].
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final ink = color ?? (mono ? Colors.white : CurrencyInk.of(context));
    // Increase contrast in light mode: a deeper teal, 3:1 on white.
    final body = A11y.increaseContrastOf(context) && !context.isDark ? const Color(0xFF0F8A7E) : Brand.ticket;
    return CustomPaint(size: Size(size * 0.8, size), painter: _TicketPainter(ink, body));
  }
}

/// Upright pass with notches top and bottom, a star and a short tear line.
class _TicketPainter extends CustomPainter {
  _TicketPainter(this.ink, this.fill);
  /// Null: the teal ticket with a white star. Otherwise a silhouette in this colour.
  final Color? ink;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final r = Rect.fromLTWH(w * 0.08, h * 0.06, w * 0.84, h * 0.88);
    final body = Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(r.width * 0.22)));
    final n = r.width * 0.2;
    final holes = Path()
      ..addOval(Rect.fromCircle(center: Offset(r.center.dx, r.top), radius: n))
      ..addOval(Rect.fromCircle(center: Offset(r.center.dx, r.bottom), radius: n));
    final shape = Path.combine(PathOperation.difference, body, holes);
    final star = _star(Offset(w / 2, h * 0.44), w * 0.24);
    final stroke = math.max(1.0, h * 0.05);
    void tearLine(Paint p) {
      for (var x = w * 0.26; x < w * 0.78; x += w * 0.16) {
        canvas.drawLine(Offset(x, h * 0.72), Offset(x + w * 0.08, h * 0.72), p);
      }
    }

    final mono = ink;
    if (mono == null) {
      canvas.drawPath(shape, Paint()..color = fill);
      canvas.drawPath(star, Paint()..color = Colors.white);
      tearLine(Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round);
      return;
    }
    // Silhouette: the star and tear line are punched out of the body.
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawPath(shape, Paint()..color = mono);
    canvas.drawPath(star, Paint()..blendMode = BlendMode.dstOut);
    tearLine(Paint()
      ..blendMode = BlendMode.dstOut
      ..color = const Color(0xD9000000)
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round);
    canvas.restore();
  }

  Path _star(Offset c, double r) {
    final p = Path();
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final rr = i.isEven ? r : r * 0.45;
      final o = Offset(c.dx + rr * math.cos(a), c.dy + rr * math.sin(a));
      i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
    }
    return p..close();
  }

  @override
  bool shouldRepaint(covariant _TicketPainter o) => o.ink != ink || o.fill != fill;
}

/// Amber bulb mark for hints.
class HintIcon extends StatelessWidget {
  const HintIcon({super.key, this.size = 18, this.mono = false, this.color});
  final double size;

  /// With Increase contrast, the bulb alone on a filled surface (white unless [color] is given,
  /// or the [CurrencyInk]).
  final bool mono;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final contrast = A11y.increaseContrastOf(context);
    final ink = contrast ? (color ?? (mono ? Colors.white : CurrencyInk.of(context))) : null;
    if (ink != null) return Icon(Icons.lightbulb_rounded, size: size, color: ink);
    // Increase contrast: a deeper amber disc in light mode, a dark bulb in dark mode.
    final disc = contrast && !context.isDark ? const Color(0xFFB67507) : Brand.hint;
    final bulb = contrast && context.isDark ? const Color(0xFF2A1F00) : Colors.white;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: disc),
      child: Icon(Icons.lightbulb_rounded, size: size * 0.62, color: bulb),
    );
  }
}

/// A Peek or a Magic in stock: the booster's glyph on a cobalt disc, the same size as [HintIcon].
class BoosterIcon extends StatelessWidget {
  const BoosterIcon(this.icon, {super.key, this.size = 18});
  final IconData icon;
  final double size;
  @override
  Widget build(BuildContext context) {
    // Increase contrast: the theme's accent fill, which keeps 3:1 on dark cards too.
    final contrast = A11y.increaseContrastOf(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: contrast ? context.accentFill : Brand.accent),
      child: Icon(icon, size: size * 0.62, color: contrast ? context.onAccent : Colors.white),
    );
  }
}

/// [mono] draws the ticket as a silhouette for accent buttons (white, or
/// [monoColor]); coins and hints keep their own colours, which already read
/// well on the accent. Inside a [CurrencyInk] the ticket is a silhouette anyway.
Widget currencyIcon(Currency c, {double size = 18, bool mono = false, Color? monoColor}) => switch (c) {
      Currency.coins => CoinIcon(size: size, mono: mono, color: mono ? monoColor : null),
      Currency.tickets => TicketIcon(size: size, mono: mono, color: mono ? monoColor : null),
      Currency.hints => HintIcon(size: size, mono: mono, color: mono ? monoColor : null),
      Currency.peeks => BoosterIcon(AppIcons.peek, size: size),
      Currency.magics => BoosterIcon(AppIcons.magic, size: size),
    };

/// Inline "icon + number" used for prices, rewards and balances.
class Amount extends StatelessWidget {
  const Amount({
    super.key,
    required this.currency,
    required this.value,
    this.size = 16,
    this.fontSize,
    this.color,
    this.prefix = '',
    this.suffix = '',
    this.weight = FontWeight.w700,
  });
  final Currency currency;
  final Object value;
  final double size;
  final double? fontSize;
  final Color? color;
  final String prefix;
  final String suffix;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        currencyIcon(currency, size: size),
        SizedBox(width: size * 0.3),
        Text('$prefix${value is int ? formatCount(value as int) : value}$suffix', style: TextStyle(fontWeight: weight, fontSize: fontSize ?? size * 0.95, color: color ?? context.colors.textPrimary)),
      ],
    );
  }
}

/// Rounded-square icon tile used by quick actions, boosters and list rows.
/// Four sizes only, with a radius that follows the size (30%, the iOS
/// continuous-corner proportion): [small] leads a list row, [medium] leads a
/// card, [tool] is a toolbar button, [large] heads a sheet.
class IconTile extends StatelessWidget {
  const IconTile({super.key, required this.icon, this.size = medium, this.gradient, this.color, this.iconColor = Colors.white, double? radius, this.child}) : radius = radius ?? size * 0.3;
  static const small = 32.0;
  static const medium = 40.0;
  static const tool = 48.0;
  static const large = 64.0;

  final IconData icon;
  final double size;
  final Gradient? gradient;
  final Color? color;
  final Color iconColor;
  final double radius;
  final Widget? child;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(gradient: gradient, color: gradient == null ? (color ?? context.colors.accentTint) : null, borderRadius: BorderRadius.circular(radius)),
        child: child ?? Icon(icon, size: size * 0.52, color: gradient == null && color == null ? context.accent : iconColor),
      );
}

/// Circular avatar drawn from the profile's avatar key. Tiered avatars
/// (`family@n`) earn a frame that grows with the tier.
class AvatarCircle extends StatelessWidget {
  const AvatarCircle({super.key, required this.avatarKey, this.size = 40, this.border = false, this.tier});
  final String? avatarKey;
  final double size;
  final bool border;
  /// Overrides the tier parsed from [avatarKey].
  final int? tier;

  @override
  Widget build(BuildContext context) {
    final parts = AppIcons.splitAvatarKey(avatarKey);
    final a = AppIcons.avatar(parts.family);
    final t = tier ?? parts.tier;
    // Dark mode: discs darker than 30% lightness (VIP, Night Owl, Snowflake,
    // Rocket, Book, Anchor) are lifted to it, keeping their hue, so they do
    // not melt into dark cards. White icons stay above 7:1.
    final color = context.isDark ? _lift(a.color) : a.color;
    final ring = switch (t) { <= 1 => 0.0, 2 => size * 0.06, _ => size * 0.08 };
    final disc = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: border && t <= 1 ? Border.all(color: context.colors.card, width: 3) : null,
      ),
      child: Container(
        width: size * 0.78,
        height: size * 0.78,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: t >= 2 ? Color.lerp(color, Colors.black, 0.22) : color),
        child: Icon(a.icon, size: size * 0.5, color: a.glyph),
      ),
    );
    if (t <= 1) return disc;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          CustomPaint(size: Size.square(size), painter: _TierRingPainter(tier: t, ring: ring, card: context.colors.card)),
          Padding(padding: EdgeInsets.all(ring + (t >= 4 ? size * 0.05 : size * 0.02)), child: FittedBox(child: disc)),
          if (t >= 4)
            Positioned(
              right: -size * 0.02,
              bottom: -size * 0.02,
              child: Container(
                width: size * 0.3,
                height: size * 0.3,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Brand.coin, border: Border.all(color: context.colors.card, width: math.max(1, size * 0.04))),
                child: Icon(Icons.star_rounded, size: size * 0.2, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

Color _lift(Color c) {
  final hsl = HSLColor.fromColor(c);
  return hsl.lightness >= 0.30 ? c : hsl.withLightness(0.30).toColor();
}

class _TierRingPainter extends CustomPainter {
  _TierRingPainter({required this.tier, required this.ring, required this.card});
  final int tier;
  final double ring;
  final Color card;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - ring / 2;
    final color = tier == 2 ? const Color(0xFFA3A8B5) : Brand.coin;
    canvas.drawCircle(c, r, Paint()..style = PaintingStyle.stroke..strokeWidth = ring..color = color);
    if (tier >= 3) {
      // Notch marks on the gold ring.
      final notch = Paint()..style = PaintingStyle.stroke..strokeWidth = math.max(1.2, ring * 0.35)..color = card.withValues(alpha: 0.9)..strokeCap = StrokeCap.round;
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        canvas.drawLine(Offset(c.dx + math.cos(a) * (r - ring * 0.35), c.dy + math.sin(a) * (r - ring * 0.35)), Offset(c.dx + math.cos(a) * (r + ring * 0.35), c.dy + math.sin(a) * (r + ring * 0.35)), notch);
      }
    }
    if (tier >= 4) {
      canvas.drawCircle(c, r - ring * 1.6, Paint()..style = PaintingStyle.stroke..strokeWidth = ring * 0.5..color = color);
    }
  }

  @override
  bool shouldRepaint(_TierRingPainter o) => o.tier != tier || o.ring != ring || o.card != card;
}
