import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/a11y.dart';
import '../../core/theme/tokens.dart';
import '../../models/models.dart';
import '../../state/catalog.dart';
import '../../state/first_steps.dart';
import '../../state/giant.dart';
import '../../state/profile.dart';
import '../../state/progress.dart';
import '../../state/settings.dart';
import '../../state/starter_packs.dart';
import '../../state/unlocks.dart';
import '../../widgets/glass.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import '../home/header_bar.dart';
import 'pack_card.dart';
import 'pack_progress.dart';
import '../home/guided_start.dart';

/// The Library's selected chip. Other tabs set it before switching to the
/// Library, e.g. Home's "All months" opens it on Daily and the finished
/// packs row on Finished.
class LibraryFilter extends Notifier<String> {
  static const all = 'All';
  static const finished = 'Finished';
  static const started = 'Started';
  static const unlocked = 'Unlocked';
  static const fresh = 'New';
  static const daily = 'Daily';
  static const giant = 'Giant';
  static const ai = 'AI';

  /// Chips that are not pack categories; they carry an icon before the label.
  static const special = {all, fresh, finished, started, unlocked};

  /// Categories that are a different kind of pack (a calendar, giant boards, generated pictures):
  /// they carry their mark ([AppIcons.category]) and lead the categories, in this order.
  static const kinds = [daily, giant, ai];

  @override
  String build() => all;

  void select(String filter) => state = filter;
}

final libraryFilterProvider = NotifierProvider<LibraryFilter, String>(LibraryFilter.new);

/// The chips in order: All, New (only while a library pack is new, see
/// [Pack.isNewAt]), Finished, Started, Unlocked (only useful without VIP,
/// which opens everything), then the kinds of pack with their marks (Daily,
/// Giant, AI; Giant and AI only while such packs exist), then the themed
/// categories. Events have no chip: they live on Home and in Quests.
List<String> libraryChips(List<Pack> packs, {required bool showUnlocked, DateTime? now}) {
  final categories = {for (final p in packs) if (!p.isDaily && !p.hasWindow && p.category != 'Event') p.category};
  return [
    LibraryFilter.all,
    if (packs.any((p) => p.isNewAt(now ?? DateTime.now()))) LibraryFilter.fresh,
    LibraryFilter.finished,
    LibraryFilter.started,
    if (showUnlocked) LibraryFilter.unlocked,
    for (final k in LibraryFilter.kinds) if (k == LibraryFilter.daily || categories.contains(k)) k,
    ...categories.where((c) => !LibraryFilter.kinds.contains(c)),
  ];
}

/// Icon for a chip: the special views and the kinds of pack (Daily, Giant,
/// AI) carry one, themed categories are words.
IconData? libraryChipIcon(String chip) => switch (chip) {
      LibraryFilter.all => AppIcons.filterAll,
      LibraryFilter.fresh => AppIcons.filterNew,
      LibraryFilter.finished => AppIcons.filterFinished,
      LibraryFilter.started => AppIcons.filterStarted,
      LibraryFilter.unlocked => AppIcons.filterUnlocked,
      _ => LibraryFilter.kinds.contains(chip) ? AppIcons.category(chip) : null,
    };

/// Lower case without accents, apostrophes or hyphens, so "Kraków",
/// "krakow" and "KRAKOW" all match and "world's" finds "worlds".
String foldForSearch(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final ch = String.fromCharCode(r);
    b.write(_fold[ch] ?? ch);
  }
  return b.toString();
}

const _fold = <String, String>{
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a', 'ă': 'a', 'ą': 'a', 'æ': 'ae',
  'ç': 'c', 'ć': 'c', 'ĉ': 'c', 'ċ': 'c', 'č': 'c', 'ď': 'd', 'đ': 'd', 'ð': 'd',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ĕ': 'e', 'ė': 'e', 'ę': 'e', 'ě': 'e',
  'ĝ': 'g', 'ğ': 'g', 'ġ': 'g', 'ģ': 'g', 'ĥ': 'h', 'ħ': 'h',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ĩ': 'i', 'ī': 'i', 'į': 'i', 'ı': 'i', 'ĵ': 'j', 'ķ': 'k',
  'ĺ': 'l', 'ļ': 'l', 'ľ': 'l', 'ŀ': 'l', 'ł': 'l', 'ñ': 'n', 'ń': 'n', 'ņ': 'n', 'ň': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o', 'ŏ': 'o', 'ő': 'o', 'œ': 'oe',
  'ŕ': 'r', 'ŗ': 'r', 'ř': 'r', 'ś': 's', 'ŝ': 's', 'ş': 's', 'š': 's', 'ș': 's', 'ß': 'ss',
  'ţ': 't', 'ť': 't', 'ț': 't', 'þ': 'th',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ũ': 'u', 'ū': 'u', 'ŭ': 'u', 'ů': 'u', 'ű': 'u', 'ų': 'u',
  'ŵ': 'w', 'ý': 'y', 'ÿ': 'y', 'ŷ': 'y', 'ź': 'z', 'ż': 'z', 'ž': 'z',
  '\'': '', '’': '', '‘': '', '-': ' ', '–': ' ', '—': ' ',
};

/// The packs a Library view shows, in order.
///
/// [filter] picks the chip's packs; [hideFinished] then drops packs whose
/// every picture is solved (never in the Finished view, which would empty
/// it); [query] keeps packs where every word of it starts a word of the name,
/// category or description, ignoring case and accents, with name matches first.
List<Pack> libraryPacks(
  List<Pack> packs, {
  required String filter,
  required Map<String, PackProgress> progress,
  required bool Function(Pack) isUnlocked,
  bool hideFinished = false,
  String query = '',
  DateTime? now,
}) {
  bool finished(Pack p) => progress[p.id]?.complete ?? false;
  final library = packs.where((p) => !p.isDaily && !p.hasWindow);
  final live = packs.where((p) => p.hasWindow && p.isLive);
  final daily = packs.where((p) => p.isDaily);
  final inAllOrder = [...library, ...live, ...daily];

  var out = switch (filter) {
    LibraryFilter.all => inAllOrder,
    // Finished event packs stay here after the event ends: they are the player's.
    LibraryFilter.finished => [...library, ...live, ...packs.where((p) => p.hasWindow && p.isExpired), ...daily].where(finished).toList(),
    // Begun and not finished, or a finished pack with a board left mid-way.
    LibraryFilter.started => inAllOrder.where((p) {
        final pr = progress[p.id];
        return pr != null && pr.started && (!pr.complete || pr.playing > 0);
      }).toList(),
    // Same rule as the pack page: free, current month, bought, live event.
    LibraryFilter.unlocked => inAllOrder.where(isUnlocked).toList(),
    LibraryFilter.fresh => library.where((p) => p.isNewAt(now ?? DateTime.now())).toList(),
    LibraryFilter.daily => daily.toList(),
    _ => packs.where((p) => p.category == filter).toList(),
  };
  if (hideFinished && filter != LibraryFilter.finished) out = out.where((p) => !finished(p)).toList();

  final words = foldForSearch(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return out;
  bool all(String text) {
    final textWords = text.split(_wordBreak);
    return words.every((w) => textWords.any((t) => t.startsWith(w)));
  }
  final byName = <Pack>[], byText = <Pack>[];
  for (final p in out) {
    if (all(foldForSearch(p.name))) {
      byName.add(p);
    } else if (all(foldForSearch('${p.name} ${p.category} ${p.description}'))) {
      byText.add(p);
    }
  }
  return [...byName, ...byText];
}

/// Pictures a Library search finds: every picture of [packs] (the packs the
/// current chip and "Hide finished" show) where every word of [query] starts a
/// word of the title, ignoring case and accents ("owl" finds "Snowy owl" and
/// "Owls", never "Berry Bowl"). Daily pictures whose day has not come
/// stay out (their titles would spoil the day). Titles that start with the
/// query come first, then the rest in catalogue order; [pictures] holds at
/// most [limit] of the [total] matches.
({List<Puzzle> pictures, int total}) libraryPictures(
  Iterable<Puzzle> puzzles, {
  required List<Pack> packs,
  required String query,
  required DateTime now,
  int limit = 40,
}) {
  final words = foldForSearch(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return (pictures: const <Puzzle>[], total: 0);
  final order = {for (var i = 0; i < packs.length; i++) packs[i].id: i};
  final today = DateTime(now.year, now.month, now.day);
  final starts = <Puzzle>[], contains = <Puzzle>[];
  for (final z in puzzles) {
    if (!order.containsKey(z.packId)) continue;
    final d = z.date;
    if (d != null && DateTime(d.year, d.month, d.day).isAfter(today)) continue;
    final title = foldForSearch(z.title);
    final titleWords = title.split(_wordBreak);
    if (!words.every((w) => titleWords.any((t) => t.startsWith(w)))) continue;
    (title.startsWith(words.first) ? starts : contains).add(z);
  }
  int byPack(Puzzle a, Puzzle b) {
    final p = order[a.packId]!.compareTo(order[b.packId]!);
    return p != 0 ? p : a.sortOrder.compareTo(b.sortOrder);
  }

  starts.sort(byPack);
  contains.sort(byPack);
  final all = [...starts, ...contains];
  return (pictures: all.take(limit).toList(), total: all.length);
}

final _wordBreak = RegExp(r'[^a-z0-9]+');

/// Library: every pack behind filter chips and a search field, plus the
/// "My Puzzles" entry.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  /// Width of a pack on the search shelf: two and a bit fit an SE, so the next one peeks.
  static const _shelfCardWidth = 150.0;

  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  /// Chip keys, so a chip picked from elsewhere (a link: `/library?filter=Giant`) scrolls into view.
  final _chipKeys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _search.addListener(_onQuery);
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealChip(ref.read(libraryFilterProvider)));
  }

  void _revealChip(String chip) {
    final ctx = _chipKeys[chip]?.currentContext;
    // On a wide window every chip is in view already (they wrap); scrolling would move the page.
    if (ctx == null || !ctx.mounted || chip == LibraryFilter.all || context.isWide) return;
    Scrollable.ensureVisible(ctx, alignment: 0.5, duration: A11y.motion(context, const Duration(milliseconds: 300)), curve: Curves.easeOutCubic);
  }

  String _query = '';

  void _onQuery() {
    if (_search.text != _query) setState(() => _query = _search.text);
  }

  @override
  void dispose() {
    _search.removeListener(_onQuery);
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final packs = ref.watch(packsProvider);

    return Scaffold(
      body: packs.when(
        loading: () => const _LibrarySkeleton(),
        error: (e, _) => EmptyState(
          icon: AppIcons.signal,
          title: 'Packs did not load',
          message: 'Check your connection and try again.',
          action: BigButton(label: 'Try again', expand: false, onTap: () => ref.invalidate(catalogProvider)),
        ),
        data: _library,
      ),
    );
  }

  Widget _library(List<Pack> all) {
    final c = context.colors;
    // Guided start: daily months join after 5 pictures, event packs after 35.
    final open = ref.watch(revealsProvider);
    final list = [
      for (final p in all)
        if ((open.contains(Reveal.daily) || !p.isDaily) && (open.contains(Reveal.liveEvents) || !p.hasWindow)) p,
    ];
    final profile = ref.watch(profileProvider).value;
    final progress = ref.watch(allPackProgressProvider);
    final hideFinished = ref.watch(settingsProvider.select((s) => s.hideFinished));
    final profileN = ref.read(profileProvider.notifier);
    // VIP opens everything, so the "Unlocked" chip only helps everyone else.
    final chips = libraryChips(list, showUnlocked: profile != null && !profile.isVip)..removeWhere((c) => c == LibraryFilter.daily && !open.contains(Reveal.daily));
    // A chip that is no longer offered (e.g. Unlocked after going VIP) falls back to All.
    final selected = ref.watch(libraryFilterProvider);
    final filter = chips.contains(selected) ? selected : LibraryFilter.all;
    ref.listen(libraryFilterProvider, (_, next) => WidgetsBinding.instance.addPostFrameCallback((_) => _revealChip(next)));
    final inFinished = filter == LibraryFilter.finished;

    List<Pack> view({String? f, bool? hide, String? q}) => libraryPacks(
          list,
          filter: f ?? filter,
          progress: progress,
          isUnlocked: profileN.isUnlocked,
          hideFinished: hide ?? hideFinished,
          query: q ?? _query,
        );
    final filtered = view();
    final finishedCount = inFinished ? view(q: '').length : 0;
    final searching = _query.trim().isNotEmpty;
    final found = searching
        ? libraryPictures(ref.watch(allPuzzlesProvider).value ?? const <Puzzle>[], packs: view(q: ''), query: _query, now: DateTime.now())
        : (pictures: const <Puzzle>[], total: 0);
    final packById = {for (final p in list) p.id: p};
    final lead = !searching && filter == LibraryFilter.all ? 1 : 0;
    final wide = context.isExpanded;
    final shelfCardWidth = context.isWide ? 184.0 : _shelfCardWidth;
    final searchField = CupertinoSearchTextField(
      key: const ValueKey('library-search'),
      controller: _search,
      focusNode: _searchFocus,
      placeholder: 'Search packs and pictures',
      onSubmitted: (_) => _searchFocus.unfocus(),
      style: TextStyle(color: c.textPrimary, fontSize: TypeSize.callout, letterSpacing: -0.2),
      placeholderStyle: TextStyle(color: c.textTertiary, fontSize: TypeSize.callout, letterSpacing: -0.2),
      itemColor: c.textTertiary,
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.stroke)),
      padding: const EdgeInsetsDirectional.fromSTEB(6, 9, 6, 9),
    );
    Widget chipFor(String chip) => KeyedSubtree(
          key: _chipKeys.putIfAbsent(chip, GlobalKey.new),
          child: _FilterChip(
            key: ValueKey('library-chip-$chip'),
            label: chip,
            icon: libraryChipIcon(chip),
            selected: chip == filter,
            onTap: () => ref.read(libraryFilterProvider.notifier).select(chip),
          ),
        );
    // Search results on a wide window: the pictures in two columns.
    final pictureColumns = context.isWide ? 2 : 1;
    Widget pictureCard(List<Puzzle> pictures) => SoftCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < pictures.length; i++) ...[
                _PictureRow(puzzle: pictures[i], pack: packById[pictures[i].packId]),
                if (i < pictures.length - 1) Divider(height: 1, color: c.stroke, indent: 76),
              ],
            ],
          ),
        );

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        const HeaderBar(title: 'Library'),
        SliverPage(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 5, 20, 0),
                child: Row(
                  crossAxisAlignment: inFinished ? CrossAxisAlignment.end : CrossAxisAlignment.center,
                  children: [
                    const Expanded(child: PageTitle('Library')),
                    // A website puts the search beside the title.
                    if (wide) ...[SizedBox(width: 360, child: searchField), const SizedBox(width: 20)],
                    // In Finished, hiding finished packs would empty the view; the count says more.
                    if (inFinished)
                      Text('$finishedCount finished', key: const ValueKey('library-finished-count'), style: TextStyle(color: c.textSecondary, fontSize: TypeSize.footnote))
                    else
                      _HideFinishedToggle(value: hideFinished, onChanged: ref.read(settingsProvider.notifier).setHideFinished),
                  ],
                ),
              ),
            ),
            // Guided start: said once, the first time the player opens the Library.
            const SliverToBoxAdapter(
              child: OneTimeTip(
                id: 'library',
                icon: AppIcons.library,
                text: OneTimeTip.libraryText,
                padding: EdgeInsets.fromLTRB(20, 10, 20, 0),
              ),
            ),
            if (!wide)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: searchField,
                ),
              ),
            SliverToBoxAdapter(
              child: context.isWide
                  // Every chip in view at once: they wrap instead of scrolling sideways.
                  ? Padding(
                      key: const ValueKey('library-chips'),
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
                      child: Wrap(spacing: 8, runSpacing: 0, children: [for (final chip in chips) IntrinsicWidth(child: chipFor(chip))]),
                    )
                  : SizedBox(
                      height: 54,
                      child: ListView.separated(
                        key: const ValueKey('library-chips'),
                        scrollDirection: Axis.horizontal,
                        // Chips are 36 pt with a 44 pt touch box (TapTarget); the row keeps its 54 pt.
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 2),
                        physics: const BouncingScrollPhysics(),
                        // Every chip is built, so any of them can be scrolled to.
                        scrollCacheExtent: const ScrollCacheExtent.pixels(4000),
                        itemCount: chips.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (_, i) => chipFor(chips[i]),
                      ),
                    ),
            ),
            if (filtered.isEmpty && found.total == 0)
              SliverToBoxAdapter(child: _empty(filter, hideFinished: hideFinished, view: view))
            else if (searching && filtered.isNotEmpty) ...[
              // While searching, the matching packs are a shelf that scrolls sideways: the covers
              // look as they do everywhere else, and the matching pictures start on the first
              // screen instead of under a page of large covers.
              SliverToBoxAdapter(
                child: SectionHeader(
                  key: const ValueKey('library-packs'),
                  title: 'Packs',
                  subtitle: '${filtered.length} ${filtered.length == 1 ? 'pack' : 'packs'}',
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                ),
              ),
              SliverToBoxAdapter(
                child: Shelf(
                  listKey: const ValueKey('library-pack-shelf'),
                  // A grid card's shape (0.78) at shelf width.
                  height: shelfCardWidth / 0.78,
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => SizedBox(
                    width: shelfCardWidth,
                    child: PackCard(key: ValueKey('library-pack-${filtered[i].id}'), pack: filtered[i], onTap: () => context.go('/library/pack/${filtered[i].id}')),
                  ),
                ),
              ),
            ] else if (filtered.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                sliver: SliverGrid(
                  gridDelegate: const AdaptiveGridDelegate(childAspectRatio: 0.78),
                  // In All, My Puzzles is the first tile of the grid instead of a card above it,
                  // so the packs start right under the chips.
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => i < lead
                        ? _MyPuzzlesTile(onTap: () => context.go('/profile/my-puzzles'))
                        : PackCard(pack: filtered[i - lead], onTap: () => context.go('/library/pack/${filtered[i - lead].id}')),
                    childCount: filtered.length + lead,
                  ),
                ),
              ),
            if (found.total > 0) ...[
              SliverToBoxAdapter(
                child: SectionHeader(
                  key: const ValueKey('library-pictures'),
                  title: 'Pictures',
                  subtitle: found.total > found.pictures.length ? '${found.pictures.length} of ${found.total} · add a word to narrow it down' : '${found.total} ${found.total == 1 ? 'picture' : 'pictures'}',
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverToBoxAdapter(
                  child: pictureColumns == 1
                      ? pictureCard(found.pictures)
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: pictureCard(found.pictures.sublist(0, (found.pictures.length + 1) ~/ 2))),
                            const SizedBox(width: 12),
                            Expanded(child: found.pictures.length < 2 ? const SizedBox.shrink() : pictureCard(found.pictures.sublist((found.pictures.length + 1) ~/ 2))),
                          ],
                        ),
                ),
              ),
            ],
          ],
        ),
        SliverToBoxAdapter(child: SizedBox(height: GlassTabBar.scrollEndPadding(context))),
      ],
    );
  }

  /// Why the view is empty, most specific reason first: the search, the
  /// hide-finished toggle, then the chip itself.
  Widget _empty(String filter, {required bool hideFinished, required List<Pack> Function({String? f, bool? hide, String? q}) view}) {
    final q = _query.trim();
    final showFinished = BigButton(label: 'Show finished', kind: ButtonKind.secondary, expand: false, onTap: () => ref.read(settingsProvider.notifier).setHideFinished(false));
    if (q.isNotEmpty) {
      if (hideFinished && view(hide: false).isNotEmpty) {
        return EmptyState(icon: AppIcons.filterFinished, title: 'Only finished packs match', message: 'Finished packs are hidden. Show them to see what matches "$q".', action: showFinished);
      }
      if (filter != LibraryFilter.all && view(f: LibraryFilter.all).isNotEmpty) {
        return EmptyState(
          icon: AppIcons.search,
          title: 'Nothing found',
          message: 'Nothing in $filter matches "$q". Other packs do.',
          action: BigButton(label: 'Search all packs', kind: ButtonKind.secondary, expand: false, onTap: () => ref.read(libraryFilterProvider.notifier).select(LibraryFilter.all)),
        );
      }
      return EmptyState(icon: AppIcons.search, title: 'Nothing found', message: 'No pack or picture matches "$q". Try another word.');
    }
    if (hideFinished && view(hide: false).isNotEmpty) {
      return EmptyState(icon: AppIcons.filterFinished, title: 'Every pack here is finished', message: 'Finished packs are hidden. Show them again to replay a picture.', action: showFinished);
    }
    return switch (filter) {
      LibraryFilter.finished => const EmptyState(icon: AppIcons.filterFinished, title: 'No finished packs yet', message: 'A pack lands here once every picture in it is solved. Open a pack you have started to finish it.'),
      LibraryFilter.started => const EmptyState(icon: AppIcons.filterStarted, title: 'Nothing started yet', message: 'Packs you have begun and not finished show up here. Open a pack to start one.'),
      LibraryFilter.unlocked => const EmptyState(icon: AppIcons.filterUnlocked, title: 'Nothing unlocked yet', message: 'Packs you can play right now show up here.'),
      LibraryFilter.fresh => const EmptyState(icon: AppIcons.filterNew, title: 'No new packs this week', message: 'Packs added in the last seven days show up here.'),
      _ => const EmptyState(icon: AppIcons.library, title: 'Nothing here yet', message: 'New packs arrive with events and every month.'),
    };
  }
}

/// A picture found by the search: thumbnail, title, pack, and its state.
/// It opens the picture when its pack is open and its day has come, else the
/// pack page (which explains the price or the date).
class _PictureRow extends ConsumerWidget {
  const _PictureRow({required this.puzzle, required this.pack});
  final Puzzle puzzle;
  final Pack? pack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    ref.watch(profileProvider);
    final pack = this.pack;
    if (pack != null && formerlyFreePacks.contains(pack.id)) ref.watch(playedPacksProvider); // stays open once played
    // A Giant pack's picture before giant boards open shows its pack, where the gate explains
    // level 10 and the early opening.
    final giantClosed = pack != null && isGiantPack(pack) && !ref.watch(openFeaturesProvider).giant;
    final open = pack != null && ref.read(profileProvider.notifier).isUnlocked(pack) && !puzzle.isLockedByDate && !giantClosed;
    final saved = ref.watch(progressProvider.select((m) => m.value?[puzzle.id]));
    final stars = saved != null && saved.completed ? saved.stars : 0;
    return Pressable(
      key: ValueKey('library-picture-${puzzle.id}'),
      scale: 0.99,
      onTap: () => open ? context.push('/play/${puzzle.id}') : context.go('/library/pack/${puzzle.packId}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            NetImage(url: puzzle.thumbUrl, blurhash: puzzle.blurhash, width: 52, height: 52, radius: 10),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(puzzle.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: TypeSize.body)),
                  const SizedBox(height: 2),
                  Text(pack?.name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textSecondary, fontSize: TypeSize.footnote)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (!open)
              Icon(AppIcons.lock, size: 16, color: c.textTertiary)
            else if (stars > 0)
              Row(mainAxisSize: MainAxisSize.min, children: [for (var i = 0; i < 3; i++) Icon(i < stars ? AppIcons.star : AppIcons.starOutline, size: 14, color: i < stars ? context.star : c.textTertiary)])
            else
              Icon(AppIcons.chevronRight, size: 16, color: c.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// My Puzzles as the first tile of the All grid: the same card shape as a
/// pack, with the photo mark on the accent tint where a cover would be.
class _MyPuzzlesTile extends StatelessWidget {
  const _MyPuzzlesTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      key: const ValueKey('library-my-puzzles'),
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(Radii.lg), border: Border.all(color: c.stroke)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                color: c.accentTint,
                alignment: Alignment.center,
                child: Icon(AppIcons.photo, size: 44, color: context.accent),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('My Puzzles', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: TypeSize.body, letterSpacing: -0.2)),
                  const SizedBox(height: 4),
                  Text('Your own photos', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textSecondary, fontSize: TypeSize.footnote)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A Library chip; the special views (All, Finished, Started, Unlocked) lead
/// with an icon in the label colour, so it reads on the cobalt and the plain chip.
class _FilterChip extends StatelessWidget {
  const _FilterChip({super.key, required this.label, required this.icon, required this.selected, required this.onTap});
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = selected ? context.onAccent : c.textSecondary;
    return Pressable(
      onTap: onTap,
      child: TapTarget(
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 36,
        padding: EdgeInsets.only(left: icon == null ? 14 : 11, right: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? context.accentFill : c.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? context.accentFill : c.controlStroke),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Differentiate without colour: a check on the chosen filter, not only the fill.
            if (selected && A11y.symbolsOf(context)) ...[Icon(AppIcons.checkmark, size: 13, color: fg), const SizedBox(width: 4)],
            if (icon != null) ...[Icon(icon, size: 15, color: fg), const SizedBox(width: 5)],
            Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: TypeSize.footnote, color: fg)),
          ],
        ),
      ),
      ),
    );
  }
}

/// "Hide finished" with a compact native switch; the label toggles it too.
class _HideFinishedToggle extends StatelessWidget {
  const _HideFinishedToggle({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MergeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(!value),
            child: Padding(
              // 44 pt touch height for the label.
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Text('Hide finished', style: TextStyle(color: c.textSecondary, fontSize: TypeSize.footnote, fontWeight: FontWeight.w500)),
            ),
          ),
          const SizedBox(width: 8),
          // 80% of the system switch: a view option, not a setting.
          SizedBox(
            width: 51 * 0.8,
            height: 31 * 0.8,
            child: FittedBox(
              child: CupertinoSwitch(key: const ValueKey('library-hide-finished'), value: value, activeTrackColor: context.highContrast ? context.colors.success : Brand.success, onChanged: onChanged),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Library while the catalogue loads: its bar, title and search in place, and pack cards to come.
class _LibrarySkeleton extends StatelessWidget {
  const _LibrarySkeleton();
  @override
  Widget build(BuildContext context) => CustomScrollView(
        physics: const NeverScrollableScrollPhysics(),
        slivers: [
          const HeaderBar(title: 'Library'),
          SliverPage(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                  child: Text('Library', style: Theme.of(context).textTheme.headlineLarge),
                ),
              ),
              const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 0), child: Skeleton(height: 40, radius: Radii.md))),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
                  child: Row(children: [Skeleton(width: 64, height: 32, radius: 16), SizedBox(width: 8), Skeleton(width: 72, height: 32, radius: 16), SizedBox(width: 8), Skeleton(width: 92, height: 32, radius: 16)]),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                sliver: SliverGrid(
                  gridDelegate: const AdaptiveGridDelegate(childAspectRatio: 0.78),
                  delegate: SliverChildBuilderDelegate((_, _) => const SkeletonPackCard(), childCount: context.isWide ? 10 : 6),
                ),
              ),
            ],
          ),
        ],
      );
}
