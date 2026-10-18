import 'dart:async';
import 'dart:math';
import 'dart:ui' show Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'board.dart';
import 'gather.dart';

enum GameStatus { playing, paused, won }

class GameState {
  const GameState({
    required this.board,
    required this.par,
    required this.moves,
    required this.elapsed,
    required this.status,
    required this.selected,
    required this.hintsUsed,
    required this.history,
    required this.justLocked,
    required this.justJoined,
    required this.hintSlot,
    required this.hintTarget,
    required this.peeking,
    required this.chain,
    required this.tick,
    this.basePar = 0,
    this.peeked = false,
    this.bestLock = 0,
    this.twins,
    this.cardKeys,
    this.previewing = false,
  });

  final Board board;
  final int par;
  final int moves;
  final int elapsed;
  final GameStatus status;
  final int? selected;
  final int hintsUsed;
  final List<List<int>> history; // layout snapshots (Gather's Undo takes the last one back)
  final Set<int> justLocked;
  final Set<int> justJoined;
  final int? hintSlot;
  final int? hintTarget;
  final bool peeking;
  final int chain; // 2 when the player's last move locked 2+ cards in place
  final int tick; // increments on each lock/join, used to re-trigger animations

  /// Par of the play-through as dealt (a resumed board keeps the one it was saved with; [par]
  /// itself is recomputed on resume and stays what the stars use).
  final int basePar;

  /// Peek was used in this play-through.
  final bool peeked;

  /// Most cards a single move of the player's locked in this play-through (Magic does not count).
  final int bestLock;

  /// The board's twin cards (docs/twins.md): null until the picture has been measured.
  final Twins? twins;

  /// The board widget's key for each card, where twin swaps changed it: two twins that trade
  /// identities stay where they are on screen, so each keeps its widget (null: every card its own).
  final List<int>? cardKeys;

  /// The picture before the deal (owner, 2026-10-17): a board dealt here first shows the whole
  /// picture, every card in its place, then the cards glide to where they were dealt. Drawn like
  /// Peek, but not a Peek: free, not [peeked], not a move, and the clock waits for it.
  final bool previewing;

  /// The board shows the picture instead of the cards as they lie (Peek or the preview): nothing is
  /// played meanwhile, and a tap ends it.
  bool get showingPicture => peeking || previewing;

  /// Finished in no more moves than the dealt par.
  bool get atPar => basePar > 0 && moves <= basePar;

  int get stars => Board.starsFor(moves: moves, par: par);
  bool get canUndo => history.isNotEmpty && status == GameStatus.playing;

  /// Slots highlighted as the current selection (whole group).
  List<int> get selectedGroup => selected == null ? const [] : board.groupOf(selected!);

  GameState copyWith({
    Board? board,
    int? par,
    int? moves,
    int? elapsed,
    GameStatus? status,
    int? selected,
    bool clearSelected = false,
    int? hintsUsed,
    List<List<int>>? history,
    Set<int>? justLocked,
    Set<int>? justJoined,
    int? hintSlot,
    int? hintTarget,
    bool clearHint = false,
    bool? peeking,
    int? chain,
    int? tick,
    int? basePar,
    bool? peeked,
    int? bestLock,
    Twins? twins,
    List<int>? cardKeys,
    bool? previewing,
  }) =>
      GameState(
        board: board ?? this.board,
        par: par ?? this.par,
        moves: moves ?? this.moves,
        elapsed: elapsed ?? this.elapsed,
        status: status ?? this.status,
        selected: clearSelected ? null : (selected ?? this.selected),
        hintsUsed: hintsUsed ?? this.hintsUsed,
        history: history ?? this.history,
        justLocked: justLocked ?? this.justLocked,
        justJoined: justJoined ?? this.justJoined,
        hintSlot: clearHint ? null : (hintSlot ?? this.hintSlot),
        hintTarget: clearHint ? null : (hintTarget ?? this.hintTarget),
        peeking: peeking ?? this.peeking,
        chain: chain ?? this.chain,
        tick: tick ?? this.tick,
        basePar: basePar ?? this.basePar,
        peeked: peeked ?? this.peeked,
        bestLock: bestLock ?? this.bestLock,
        twins: twins ?? this.twins,
        cardKeys: cardKeys ?? this.cardKeys,
        previewing: previewing ?? this.previewing,
      );
}

/// Parameters for a game session: which puzzle, which grid, and optionally a
/// saved layout to resume from.
class GameArgs {
  const GameArgs({
    required this.puzzleId,
    required this.spec,
    this.layout,
    this.moves = 0,
    this.elapsed = 0,
    this.hintsUsed = 0,
    this.session = 0,
    this.par = 0,
    this.peeked = false,
    this.bestLock = 0,
    this.preview = false,
  });
  final String puzzleId;
  final BoardSpec spec;
  final List<int>? layout;
  final int moves;
  final int elapsed;
  final int hintsUsed;

  /// The saved play-through's par, Peek and longest lock (0 / false on saves from older versions).
  final int par;
  final bool peeked;
  final int bestLock;

  /// A board dealt here (not resumed) opens on the picture ([GameState.previewing]).
  final bool preview;

  /// Distinguishes sessions on the same board (the game screen bumps it when
  /// it settles the board for the loaded picture), so each gets its own
  /// controller.
  final int session;

  @override
  bool operator ==(Object other) => other is GameArgs && other.puzzleId == puzzleId && other.spec == spec && other.session == session;
  @override
  int get hashCode => Object.hash(puzzleId, spec, session);
}

/// Events the UI reacts to with sound/haptics/particles. [rearrange]: Shuffle or Gather moved
/// cards (not a move).
enum GameEventKind { pick, move, join, lock, doubleLock, win, invalid, undo, rearrange }

class GameController extends Notifier<GameState> {
  GameController(this.args);
  final GameArgs args;

  Timer? _timer;
  Timer? _peekTimer;

  /// The board was dealt here (not resumed from a save).
  bool _dealt = false;
  final _events = StreamController<GameEventKind>.broadcast();
  Stream<GameEventKind> get events => _events.stream;

  @override
  GameState build() {
    ref.onDispose(() {
      _timer?.cancel();
      _peekTimer?.cancel();
      _events.close();
    });
    // A save only resumes when it still describes this board: the right
    // length, a permutation, every card in a slot of its own shape. Saves
    // from before a layout changed start fresh instead.
    final restore = Board.isValidLayout(args.spec, args.layout);
    _dealt = !restore;
    final board = restore ? Board(args.spec, args.layout!) : Board.shuffled(args.spec);
    final par = restore ? args.moves + board.par : board.par;
    _startTimer();
    return restore
        ? _fresh(board,
            par: max(par, 1),
            moves: args.moves,
            elapsed: args.elapsed,
            hintsUsed: args.hintsUsed,
            basePar: args.par > 0 ? args.par : max(par, 1),
            peeked: args.peeked,
            bestLock: args.bestLock)
        // The preview waits for the board to be on screen ([startPreview]).
        : _fresh(board, par: max(par, 1), previewing: args.preview);
  }

  GameState _fresh(Board board, {required int par, int moves = 0, int elapsed = 0, int hintsUsed = 0, int? basePar, bool peeked = false, int bestLock = 0, Twins? twins, bool previewing = false}) => GameState(
        board: board,
        par: par,
        moves: moves,
        elapsed: elapsed,
        status: board.isSolved ? GameStatus.won : GameStatus.playing,
        selected: null,
        hintsUsed: hintsUsed,
        history: const [],
        justLocked: const {},
        justJoined: const {},
        hintSlot: null,
        hintTarget: null,
        peeking: false,
        chain: 0,
        tick: 0,
        basePar: basePar ?? par,
        peeked: peeked,
        bestLock: bestLock,
        twins: twins,
        previewing: previewing,
      );

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.status == GameStatus.playing && !state.previewing) {
        state = state.copyWith(elapsed: state.elapsed + 1);
      }
    });
  }

  /// A board dealt here waits for its twins before it is shown, so the deal can take them into
  /// account ([useTwins]).
  bool get awaitsTwins => _dealt && state.twins == null;

  /// The board's twin cards, once the picture has been measured (docs/twins.md). A board dealt
  /// here and not played yet is dealt again with them (it is not on screen yet, see
  /// [awaitsTwins]); a resumed board keeps its cards where they are.
  void useTwins(Twins twins) {
    if (state.twins != null) return;
    if (_dealt && state.moves == 0 && state.history.isEmpty && !twins.isEmpty) {
      final board = Board.shuffled(args.spec, twins: twins);
      final par = max(board.par, 1);
      state = state.copyWith(board: board, par: par, basePar: par, twins: twins, clearSelected: true, clearHint: true);
    } else {
      state = state.copyWith(twins: twins);
    }
  }

  void pause() {
    if (state.status == GameStatus.playing) state = state.copyWith(status: GameStatus.paused, clearSelected: true);
  }

  void resume() {
    if (state.status == GameStatus.paused) state = state.copyWith(status: GameStatus.playing);
  }

  /// Tap-to-select (selects the whole group) then tap a destination for the
  /// tapped card; the group travels with it.
  void tap(int slot) {
    if (state.status != GameStatus.playing || state.previewing) return;
    final b = state.board;
    final sel = state.selected;
    if (sel == null) {
      if (b.isLocked(slot)) {
        _events.add(GameEventKind.invalid);
        return;
      }
      state = state.copyWith(selected: slot);
      _events.add(GameEventKind.pick);
    } else if (sel == slot) {
      state = state.copyWith(clearSelected: true);
    } else {
      // Tapping another cell of the same group shifts the whole group.
      _apply(b.moveTo(sel, slot));
    }
  }

  /// Drag-and-drop: the card at [from] (and its group) lands on [to].
  void drop(int from, int to) {
    if (state.status != GameStatus.playing || state.previewing) return;
    if (from == to) {
      state = state.copyWith(clearSelected: true);
      return;
    }
    _apply(state.board.moveTo(from, to));
  }

  /// Puts [after] on the table: [moves] is what it adds to the count (Magic counts each card it
  /// sends, Shuffle and Gather nothing). Only the player's own moves count as a chain (the double
  /// lock and the longest lock); a tool that locks cards plays the plain lock. [event] replaces
  /// the move's own sound unless the board is finished. A move [settle]s with the twins: a card
  /// put on its twin's place or next to a twin's neighbour counts (docs/twins.md); Shuffle and
  /// Gather never put one there.
  void _apply(Board? moved, {int moves = 1, bool byPlayer = true, GameEventKind? event, bool settle = true}) {
    if (moved == null) {
      state = state.copyWith(clearSelected: true);
      _events.add(GameEventKind.invalid);
      return;
    }
    final before = state.board;
    var after = moved;
    var keys = state.cardKeys;
    final twins = state.twins;
    if (settle && twins != null && !twins.isEmpty) {
      final settled = twins.settle(before, moved);
      after = settled.board;
      // Two twins that trade identities keep their places on screen, so they trade widgets too.
      if (settled.swaps.isNotEmpty) {
        final k = keys = List<int>.from(keys ?? List<int>.generate(after.cells, (i) => i));
        for (final (a, b) in settled.swaps) {
          final t = k[a];
          k[a] = k[b];
          k[b] = t;
        }
      }
    }
    final newlyLocked = <int>{for (var i = 0; i < after.cells; i++) if (after.isLocked(i) && !before.isLocked(i)) i};
    // Cards that gained a joined neighbour (new snap) – excluding in-place locks.
    final newlyJoined = <int>{};
    if (after.joinCount > before.joinCount) {
      for (var s = 0; s < after.cells; s++) {
        if (after.isLocked(s)) continue;
        final g = after.groupOf(s);
        if (g.length > 1 && before.groupOf(before.slotOfCard(after.slots[s])).length < g.length) newlyJoined.add(s);
      }
    }
    final won = after.isSolved;
    state = state.copyWith(
      board: after,
      moves: state.moves + moves,
      history: [...state.history, before.slots],
      justLocked: newlyLocked,
      justJoined: newlyJoined,
      chain: byPlayer && newlyLocked.length >= 2 ? 2 : 0,
      bestLock: byPlayer ? max(state.bestLock, newlyLocked.length) : state.bestLock,
      tick: newlyLocked.isEmpty && newlyJoined.isEmpty ? state.tick : state.tick + 1,
      clearSelected: true,
      clearHint: true,
      status: won ? GameStatus.won : state.status,
      cardKeys: keys,
    );
    if (won) {
      _events.add(GameEventKind.win);
      _timer?.cancel();
    } else if (event != null) {
      _events.add(event);
    } else if (byPlayer && newlyLocked.length >= 2) {
      _events.add(GameEventKind.doubleLock);
    } else if (newlyLocked.isNotEmpty) {
      _events.add(GameEventKind.lock);
    } else if (newlyJoined.isNotEmpty) {
      _events.add(GameEventKind.join);
    } else {
      _events.add(GameEventKind.move);
    }
  }

  /// Takes the last change back: Gather's Undo, offered on its toast while nothing else has
  /// changed (owner, 2026-10-17: there is no Undo button any more). Not a move.
  void undo() {
    if (!state.canUndo) return;
    final previous = state.history.last;
    final history = state.history.sublist(0, state.history.length - 1);
    state = state.copyWith(
      board: Board(state.board.spec, previous),
      history: history,
      justLocked: const {},
      justJoined: const {},
      chain: 0,
      clearSelected: true,
      clearHint: true,
    );
    _events.add(GameEventKind.undo);
  }

  /// The first board's hints: outlines where the picked card belongs (free, not a Hint), or
  /// clears the outline.
  void guide(int? target) {
    if (state.status != GameStatus.playing) return;
    state = target == null ? state.copyWith(clearHint: true) : state.copyWith(hintTarget: target);
  }

  /// Highlights a misplaced card and where it belongs. The caller handles
  /// payment before invoking this.
  bool showHint() {
    if (state.status != GameStatus.playing) return false;
    final b = state.board;
    final candidates = <int>[for (var i = 0; i < b.cells; i++) if (!b.isLocked(i)) i];
    if (candidates.isEmpty) return false;
    final slot = state.selected != null && !b.isLocked(state.selected!) ? state.selected! : candidates[Random().nextInt(candidates.length)];
    final target = b.homeOf(slot);
    state = state.copyWith(hintSlot: slot, hintTarget: target, hintsUsed: state.hintsUsed + 1, clearSelected: true);
    _events.add(GameEventKind.pick);
    return true;
  }

  /// Magic (owner, 2026-10-17): puts one card in its place, then each of its picture neighbours
  /// (the cards whose places border its own), every one with its group: up to 5 of the 9 cards on
  /// a 3x3. One move per card it sends; a tool's lock, not the player's (no double lock, and the
  /// longest lock stays the player's).
  bool magicLock() {
    if (state.status != GameStatus.playing) return false;
    final b = state.board;
    final candidates = <int>[for (var i = 0; i < b.cells; i++) if (!b.isLocked(i)) i];
    if (candidates.isEmpty) return false;
    // The selected card first (owner, 2026-10-14: Magic puts that exact card in place), then the
    // card a Hint is showing, else any card not in place.
    final sel = state.selected;
    final slot = sel != null && !b.isLocked(sel) ? sel : state.hintSlot ?? candidates[Random().nextInt(candidates.length)];
    // A card's number is its place, so its picture neighbours are the cards numbered like the
    // cells around that place.
    final card = b.slots[slot];
    final home = b.moveTo(slot, card);
    if (home == null) return false;
    var after = home;
    var sent = 1;
    for (final c in b.tiling.neighbours(card)) {
      if (after.isLocked(c)) continue;
      final next = after.moveTo(after.slotOfCard(c), c);
      if (next == null) continue;
      after = next;
      sent++;
    }
    state = state.copyWith(hintsUsed: state.hintsUsed + 1);
    _apply(after, moves: sent, byPlayer: false);
    return true;
  }

  /// Shuffle (owner, 2026-10-17: the free round button left of the tools): the loose cards trade
  /// places at random ([shuffleLoose]); on a giant board only the ones in [view] (board
  /// coordinates at the board's [size]). Cards in place and joined groups stay. Not a move.
  /// Returns how many cards moved: 0 when nothing is left to shuffle.
  int shuffle({Rect? view, Size? size, Random? random}) {
    if (state.status != GameStatus.playing || state.showingPicture) return 0;
    final before = state.board;
    final twins = state.twins;
    final after = view != null && size != null ? shuffleInView(before, view, size, random: random, twins: twins) : shuffleLoose(before, random: random, twins: twins);
    if (after == null) return 0;
    _apply(after, moves: 0, byPlayer: false, event: GameEventKind.rearrange, settle: false);
    return [for (var s = 0; s < after.cells; s++) if (after.slots[s] != before.slots[s]) s].length;
  }

  /// Peek: every card not in place flies to its place, the picture shows for a moment and the
  /// cards fly back (the board draws the flight while [GameState.peeking] is on). [duration] is
  /// the time the cards spend away, the flight there included. The caller handles payment.
  void peek({Duration duration = peekTime}) {
    if (state.status != GameStatus.playing || state.showingPicture) return;
    _peekTimer?.cancel();
    state = state.copyWith(peeking: true, peeked: true, clearSelected: true);
    _peekTimer = Timer(duration, endPeek);
  }

  /// How long a Peek keeps the cards in their places, and the longer look on a giant board.
  static const peekTime = Duration(milliseconds: 2400);
  static const giantPeekTime = Duration(milliseconds: 3200);

  /// Ends Peek or the preview now (owner, 2026-10-17: a tap while the picture shows): the cards
  /// fly back to where they lie at once.
  void endPeek() {
    _peekTimer?.cancel();
    if (_events.isClosed || !state.showingPicture) return;
    state = state.copyWith(peeking: false, previewing: false);
  }

  /// The board is on screen and in view: the preview's picture shows for a moment ([previewTime],
  /// shorter on a giant board), then the cards are dealt. Called once the cards are drawn, and
  /// again each time the board comes back into view ([holdPreview]); the time counts from then.
  void startPreview() {
    if (!state.previewing || (_peekTimer?.isActive ?? false)) return;
    _peekTimer = Timer(args.spec.isGiant ? giantPreviewTime : previewTime, endPeek);
  }

  /// The board went out of view while the picture shows before the deal (the app is not in front,
  /// a sheet or another screen covers it): the picture waits, and shows again for the full time
  /// once the board is back ([startPreview]). The clock waits with it.
  void holdPreview() {
    if (!state.previewing) return;
    _peekTimer?.cancel();
  }

  static const previewTime = Duration(milliseconds: 1300);
  static const giantPreviewTime = Duration(milliseconds: 1000);

  /// Gather (giant boards): brings the cards that belong in [view] (board coordinates at the
  /// board's [size]) into it, trading places with cards that belong elsewhere (see
  /// [gatherInto]). Returns how many came in: 0 when there is nothing to gather (the button is
  /// off then, see [canGather]). Not a move; [undo] takes it back.
  int gather(Rect view, Size size) {
    if (state.status != GameStatus.playing || state.showingPicture) return 0;
    final before = state.board;
    final after = gatherInto(before, view, size, twins: state.twins);
    if (after == null) return 0;
    _apply(after, moves: 0, byPlayer: false, event: GameEventKind.rearrange, settle: false);
    return [for (var s = 0; s < after.cells; s++) if (after.slots[s] != before.slots[s]) s].length ~/ 2;
  }

  /// Play together (docs/multiplayer.md): puts the shared board [layout] on the table, the other
  /// players' changes or this player's own change going back. Not a move: nothing is counted and
  /// nothing goes into the history; locks still flash, and a finished board is won.
  void showShared(List<int> layout) {
    if (!Board.isValidLayout(args.spec, layout)) return;
    final before = state.board;
    final after = Board(args.spec, layout);
    // Twins that traded identities on the other player's screen keep their places here too.
    final keys = sharedCardKeys(state.twins, before.slots, after.slots, state.cardKeys);
    final locked = <int>{for (var i = 0; i < after.cells; i++) if (after.isLocked(i) && !before.isLocked(i)) i};
    final sel = state.selected, hint = state.hintSlot;
    bool moved(int? s) => s != null && (s >= before.cells || before.slots[s] != after.slots[s]);
    final won = after.isSolved && state.status != GameStatus.won;
    state = state.copyWith(
      board: after,
      justLocked: locked,
      justJoined: const {},
      chain: 0,
      tick: locked.isEmpty ? state.tick : state.tick + 1,
      clearSelected: moved(sel) || (sel != null && after.isLocked(sel)),
      clearHint: moved(hint),
      status: won ? GameStatus.won : state.status,
      cardKeys: keys,
    );
    if (won) {
      _events.add(GameEventKind.win);
      _timer?.cancel();
    } else if (locked.isNotEmpty) {
      _events.add(GameEventKind.lock);
    }
  }

  /// The board widget's keys after another player's change ([before] to [after], slot to card), so
  /// that cards which look the same do not fly across the board (docs/twins.md, docs/multiplayer.md).
  /// A change can hold twin trades (`Twins.settle` on the mover's screen: the dropped card took its
  /// twin's identity, the twin kept its place). Within each class of twins any widget may show any
  /// card of the class, so: a card that stayed keeps its widget; a card now where a twin of it was
  /// takes that twin's widget (it stays put, and `_TwinFade` changes the picture); the rest keep
  /// their own widget where it is free, else take a free one of the class. Without twins (or before
  /// they are measured on this device) the keys stay as they are.
  @visibleForTesting
  static List<int>? sharedCardKeys(Twins? twins, List<int> before, List<int> after, List<int>? keys) {
    if (twins == null || twins.isEmpty || before.length != after.length) return keys;
    final n = after.length;
    final posBefore = List<int>.filled(n, 0), posAfter = List<int>.filled(n, 0);
    for (var s = 0; s < n; s++) {
      posBefore[before[s]] = s;
      posAfter[after[s]] = s;
    }
    final k = keys ?? List<int>.generate(n, (i) => i);
    List<int>? out;
    for (final cls in twins.classes) {
      if (!cls.any((c) => posAfter[c] != posBefore[c])) continue;
      final widgetOf = <int, int>{}; // card -> the card whose widget it takes
      final used = <int>{};
      for (final c in cls) {
        if (posAfter[c] == posBefore[c]) {
          widgetOf[c] = c;
          used.add(c);
        }
      }
      for (final c in cls) {
        if (widgetOf.containsKey(c)) continue;
        final d = before[posAfter[c]];
        if (d != c && twins.same(c, d) && !used.contains(d)) {
          widgetOf[c] = d;
          used.add(d);
        }
      }
      for (final c in cls) {
        if (!widgetOf.containsKey(c) && !used.contains(c)) {
          widgetOf[c] = c;
          used.add(c);
        }
      }
      final free = [for (final c in cls) if (!used.contains(c)) c];
      var i = 0;
      for (final c in cls) {
        widgetOf[c] ??= free[i++];
      }
      for (final MapEntry(key: c, value: d) in widgetOf.entries) {
        if (c == d) continue;
        (out ??= List<int>.from(k))[c] = k[d];
      }
    }
    return out ?? keys;
  }

  /// A new deal of the same board (Shuffle and restart, Replay); with [preview] it opens on the
  /// picture, which shows at once (the board is on screen).
  void restart({bool preview = false}) {
    _peekTimer?.cancel();
    final twins = state.twins;
    final board = Board.shuffled(args.spec, twins: twins);
    state = _fresh(board, par: max(board.par, 1), twins: twins, previewing: preview);
    _startTimer();
    startPreview();
  }

  void clearSelection() {
    if (state.selected != null) state = state.copyWith(clearSelected: true);
  }
}

final gameControllerProvider = NotifierProvider.autoDispose.family<GameController, GameState, GameArgs>(GameController.new);

/// Formats seconds as m:ss or h:mm:ss.
String formatDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

@visibleForTesting
Board debugBoard(BoardSpec spec, List<int> slots) => Board(spec, slots);
