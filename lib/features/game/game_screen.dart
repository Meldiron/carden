import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:confetti/confetti.dart';
import 'package:flutter/foundation.dart' show kIsWeb, setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/a11y.dart';
import '../../core/analytics.dart';
import '../../core/haptics.dart';
import '../../core/sfx.dart';
import '../../core/theme/tokens.dart';
import '../../data/sync/ops.dart';
import '../../game/board.dart';
import '../../game/game_controller.dart';
import '../../game/gather.dart';
import '../../game/image_loader.dart';
import '../../game/twins_loader.dart';
import '../../models/models.dart';
import '../../router.dart' show rootNavigatorKey;
import '../../state/catalog.dart';
import '../../state/first_steps.dart';
import '../../state/giant.dart';
import '../../state/profile.dart';
import '../../state/progress.dart';
import '../../state/rewards.dart';
import '../../state/settings.dart';
import '../../state/social.dart';
import '../../state/sync.dart';
import '../../state/unlocks.dart';
import '../../widgets/glass.dart';
import '../../widgets/hash_image.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import '../../state/coop/coop_bridge.dart';
import '../../state/coop/coop_controller.dart';
import '../../state/coop/coop_live.dart';
import '../../state/coop/coop_models.dart';
import '../ads/house_ads.dart';
import '../coop/coop_alerts.dart';
import '../coop/coop_players.dart';
import '../coop/coop_routes.dart';
import '../coop/guest_finish.dart';
import '../coop/join_flow.dart';
import '../coop/players_sheet.dart';
import '../events/quest_rewards.dart';
import '../sync/board_choice_sheet.dart';
import 'board_widget.dart';
import 'giant_board.dart';

/// The play screen: HUD, board, booster bar, pause and completion overlays.
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key, required this.puzzleId, required this.gridCode, this.painting = false, this.expand = false, this.first = false, this.coopId, this.coopNext = false});
  final String puzzleId;
  final String gridCode;

  /// Play together (docs/multiplayer.md): the game whose shared board this is (`?coop=`).
  final String? coopId;

  /// The host's next board for the game (`&next=1`): dealt here as usual, then handed to the game.
  final bool coopNext;

  /// The guided start's first board, opened by the welcome pages over a Home the player has not
  /// seen yet (`?first=1`): the way out is called Home.
  final bool first;

  /// A new board starts in Painting (a saved board resumes the way it was saved).
  final bool painting;

  /// Chosen with Expand (`?expand=1`): the next picture is dealt with Expand too.
  final bool expand;

  /// A board dealt here opens on its whole picture for a moment, then the cards are dealt (owner,
  /// 2026-10-17; a resumed or shared board does not). Integration suites that play a board the
  /// moment it shows turn it off.
  static bool dealPreview = true;

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> with WidgetsBindingObserver, TickerProviderStateMixin {
  /// The board being played. It starts from the route code and is settled
  /// for the picture once the picture is decoded (see [_fitToPicture]).
  late BoardSpec _spec = BoardSpec.fromCode(widget.gridCode, expand: widget.expand);

  /// Painting on this board: the saved board's choice when one resumes, else the route's.
  late bool _painting = widget.painting;

  /// Zoom of giant boards (the zoom bar and the board share it).
  late final BoardZoom _zoom = BoardZoom(vsync: this);

  /// Giant boards: the overview map (remembered; the selected card's place
  /// shows on it), and the saved view, restored once when a board resumes
  /// and written shortly after the player stops zooming or panning.
  late bool _showMap = ref.read(giantViewsProvider).showMap;

  bool _viewRestored = false;
  bool _viewCleared = false;
  String? _viewId;
  Timer? _viewSave;

  /// The board's size on screen at zoom 1 (from the layout), for Shuffle and Gather on a giant board.
  Size? _boardSize;

  /// Giant boards: whether Gather has anything to do for the view (the button is dimmed
  /// otherwise), worked out once the view settles and after the board changes, never per frame.
  bool _canGather = false;
  Board? _gatherChecked;
  Timer? _gatherCheck;
  GameArgs? _args;
  bool _fitted = false;
  GameArgs? _listening;
  StreamSubscription<GameEventKind>? _sub;
  Timer? _saveDebounce;
  final _confetti = ConfettiController(duration: const Duration(seconds: 2));

  /// The ticks of a Shuffle or Gather still to come.
  HapticRun? _ticks;
  bool _completionHandled = false;

  /// The win was this picture's first solve (a pack it completes is celebrated).
  bool _firstSolve = false;
  ({int coins, int xp, bool levelUp, int level})? _reward;

  /// Quests this win finished (ready to claim) and what the level-up opened, for the overlay.
  List<Goal> _questsReady = const [];
  List<Unlock> _unlocked = const [];
  /// The first board's hints, one per step (null when the player has had them).
  _CoachStep? _coach;
  Timer? _coachTimer;

  /// Moves since the last lock or join: six in a row bring the one-time "Stuck?" tip.
  int _dryMoves = 0;
  int _chainFlash = 0;

  /// The play-through being saved (lifetime totals add up per play-through), and whether it
  /// continues the board that was saved for the picture.
  String _playId = SyncOp.newId();
  bool _resumed = false;
  StreamSubscription<BoardUpdate>? _boardSub;
  bool _askingBoard = false;

  /// This play-through was finished on another device: the board here is not saved any more.
  bool _solvedElsewhere = false;

  /// Play together: the game this board is shared with (null: the player's own board), the bridge
  /// that shares this player's changes and shows the others', what the next change is (Magic,
  /// Shuffle and Gather say so before they change the board), whether a shared change is being
  /// put on the board (not this player's, so not shared back), and the host dealing the next board.
  String? _coopGameId;

  /// This screen shows a board shared by someone else (this player joined it as a guest). It stays
  /// theirs after the game ends or this player is removed: nothing of it is saved here, and the
  /// screen closes (`CoopHost`) once the alert is read.
  bool _guestBoard = false;
  CoopBridge? _bridge;

  /// Play together, live: the others' dragged cards, redrawn every frame while they move
  /// ([_tickGhosts]); each player's colour and initial; whether this player's last drop moved.
  final _ghosts = ValueNotifier<Map<int, CoopGhost>>(const {});
  late final Ticker _ghostTicker = createTicker(_tickGhosts);
  StreamSubscription<void>? _liveWakeSub;
  Map<String, CoopCardMark> _playerMarks = const {};
  bool _dropMoved = false;

  /// Who has a card (Play together, "first grab wins"): the cards another player holds and their
  /// groups, by card, with the player; what moved each card last; the claim that beat this player's
  /// own; when each card last said no (so a tapping finger hears it once).
  Map<int, String> _holders = const {};
  final _lastMover = <int, String>{};
  final _saidNo = <int, DateTime>{};
  String? _lostTo;
  bool _puttingDown = false;
  late final CoopController _coopCtrl = ref.read(coopProvider.notifier);
  ProviderSubscription<GameState>? _stateSub;
  CoopOpKind _nextKind = CoopOpKind.move;
  bool _showingShared = false;
  bool _coopNextPending = false;
  bool _coopStarting = false;
  ({int coins, int xp})? _coopReward;

  /// Each screen counts its sessions from its own base: a screen that replaces another one for the
  /// same picture and board (another device's board reopened) must not get the old screen's
  /// controller, which is still alive while the two swap.
  static int _screens = 0;
  final int _base = 1000 * ++_screens;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _coopCtrl; // read now: dispose may not read providers
    _liveWakeSub = ref.read(coopProvider.notifier).liveWake.listen((_) {
      if (mounted && _inCoop && !_ghostTicker.isActive) _ghostTicker.start();
    });
    final coop = ref.read(coopProvider);
    final coopGame = coop.playing && coop.game!.id == widget.coopId ? coop.game : null;
    if (coopGame != null && widget.coopNext && coop.isHost) {
      _coopNextPending = true;
    } else if (coopGame != null) {
      _coopGameId = coopGame.id;
      _guestBoard = !coop.isHost;
      _spec = BoardSpec.fromCode(coopGame.grid);
    }
    _args = _coopGameId != null ? _coopArgs(_base) : _argsFor(_spec, resume: true, session: _base);
    // No first-board hints on a shared board: the player came to play with someone.
    _coach = ref.read(settingsProvider).tutorialSeen || _spec.isGiant || widget.coopId != null ? null : _CoachStep.pick;
    _boardSub = ref.read(syncProvider.notifier).boardUpdates.listen(_onBoardUpdate);
    _zoom.addListener(_onZoomChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _listen());
  }

  void _onZoomChanged() {
    _scheduleGatherCheck();
    _maybeLocateTip();
    if (_viewId == null || _viewCleared) return;
    _viewSave?.cancel();
    _viewSave = Timer(const Duration(milliseconds: 600), _saveView);
  }

  /// The first time a giant board is zoomed in with the map and Locate on:
  /// how to find a card's place.
  void _maybeLocateTip() {
    if (!_zoom.zoomed || _zoom.zoom < 1.5 || !_showMap) return;
    final views = ref.read(giantViewsProvider);
    if (views.locateTipShown) return;
    views.locateTipShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showToast(context, 'Tap a card to see its place on the map', icon: AppIcons.minimap);
    });
  }

  void _saveView() {
    final id = _viewId;
    if (id == null || _viewCleared) return;
    ref.read(giantViewsProvider).write(id, _zoom.snapshot);
  }

  /// Giant boards: opens a resumed board on the view it was left at, and
  /// forgets the view once the board is finished.
  void _syncView(GameState state) {
    final id = GiantViews.id(widget.puzzleId, state.board.spec);
    if (_viewId != id) {
      _viewId = id;
      _viewRestored = false;
    }
    if (state.status == GameStatus.won) {
      if (!_viewCleared) {
        _viewCleared = true;
        _viewSave?.cancel();
        ref.read(giantViewsProvider).clear(id);
      }
      return;
    }
    if (_viewRestored) return;
    _viewRestored = true;
    final saved = _resumed ? ref.read(giantViewsProvider).read(id) : null;
    if (saved == null) return;
    // Before the board's first layout the view waits for its size; later it
    // must not change in the middle of this build.
    if (_zoom.viewport.isEmpty) {
      _zoom.restore(saved.zoom, saved.centre);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _zoom.restore(saved.zoom, saved.centre);
      });
    }
  }

  /// Session arguments for [spec], resuming the saved board when [resume]
  /// and the save is for this mode and piece count.
  GameArgs _argsFor(BoardSpec spec, {required bool resume, int session = 0}) {
    final existing = ref.read(puzzleProgressProvider(widget.puzzleId));
    final ok = resume && existing != null && existing.inProgress && existing.gridSize == spec.cells && existing.mode == spec.mode.code;
    _resumed = ok;
    _painting = ok ? existing.painting : widget.painting;
    _playId = ok && existing.session.isNotEmpty ? existing.session : SyncOp.newId();
    return GameArgs(
      puzzleId: widget.puzzleId,
      spec: spec,
      layout: ok ? existing.layout : null,
      moves: ok ? existing.moves : 0,
      elapsed: ok ? existing.elapsedSeconds : 0,
      hintsUsed: ok ? existing.hintsUsed : 0,
      session: session,
      par: ok ? existing.par : 0,
      peeked: ok && existing.peeked,
      bestLock: ok ? existing.bestLock : 0,
      // A board dealt here opens on the picture; not the boards of a game of Play together.
      preview: !ok && widget.coopId == null && GameScreen.dealPreview,
    );
  }

  /// Session arguments for the shared board: the board as everyone has it now. The host goes on with
  /// their own saved moves and time on it (the board is the host's own); a guest starts at none.
  GameArgs _coopArgs(int session) {
    final coop = ref.read(coopProvider);
    final shared = ref.read(coopProvider.notifier).log?.layout ?? coop.game!.layout;
    if (coop.isHost) {
      final own = _argsFor(_spec, resume: true, session: session);
      _painting = coop.game!.painting;
      return GameArgs(
        puzzleId: widget.puzzleId,
        spec: _spec,
        layout: shared,
        moves: own.moves,
        elapsed: own.elapsed,
        hintsUsed: own.hintsUsed,
        session: session,
        par: own.par,
        peeked: own.peeked,
        bestLock: own.bestLock,
      );
    }
    _painting = coop.game!.painting;
    _resumed = false;
    _playId = SyncOp.newId();
    return GameArgs(puzzleId: widget.puzzleId, spec: _spec, layout: shared, session: session);
  }

  bool get _inCoop {
    final coop = ref.read(coopProvider);
    return _coopGameId != null && coop.playing && coop.game?.id == _coopGameId;
  }

  /// A guest on a shared board: nothing is saved, and the finish is the guest's (also once the game
  /// is over, while its alert shows).
  bool get _coopGuest => _guestBoard || (_inCoop && !ref.read(coopProvider).isHost);

  /// Shares this board from now on (Play together started here, or the next board handed over).
  void _attachCoop(String gameId) {
    setState(() {
      _coopGameId = gameId;
      _coach = null;
    });
    _bridge?.dispose();
    _bridge = CoopBridge(ref.read(coopProvider.notifier), _SharedBoard(this));
    _bridge!.resync();
  }

  /// The game is over for this board (ended, left, removed): the host goes on alone; a guest's
  /// screen is closed by `CoopHost`.
  void _detachCoop() {
    _bridge?.dispose();
    _bridge = null;
    if (mounted) setState(() => _coopGameId = null);
  }

  /// Every change of the board: this player's own are shared (a move, Magic, Shuffle, Gather), the
  /// card picked up is shown to the others, and the host's board is saved after the others' changes.
  void _onState(GameState? prev, GameState next) {
    if (prev == null || !_inCoop) return;
    final coop = ref.read(coopProvider.notifier);
    if (!identical(prev.board, next.board) && prev.board.cells == next.board.cells) {
      if (_showingShared) {
        if (!_coopGuest) _scheduleSave();
      } else {
        final kind = _nextKind;
        _nextKind = CoopOpKind.move;
        _bridge?.localChange(kind, prev.board.slots, next.board.slots);
      }
    }
    if (prev.selected != next.selected || !identical(prev.board, next.board)) {
      final sel = next.selected;
      coop.hold(sel == null || sel >= next.board.cells ? null : next.board.slots[sel]);
    }
  }

  /// The others' dragged cards where they are now (on the path they are played back along; at the
  /// newest position under Reduce motion). Runs every frame while there are any.
  void _tickGhosts(Duration _) {
    if (!mounted) return;
    final views = _inCoop ? ref.read(coopProvider.notifier).liveTracks.ghosts(DateTime.now(), latest: A11y.reduceMotionOf(context)) : const <LiveGhost>[];
    final next = <int, CoopGhost>{
      for (final v in views)
        if (_playerMarks[v.userId] case final mark?) v.card: CoopGhost(card: v.card, at: Offset(v.x, v.y), mark: mark),
    };
    // A drag that started or ended changes who has which card: the screen works it out again.
    final changed = !setEquals(next.keys.toSet(), _ghosts.value.keys.toSet());
    if (next.isEmpty) {
      if (_ghosts.value.isNotEmpty) _ghosts.value = const {};
      _ghostTicker.stop();
      if (changed) setState(() {});
      return;
    }
    _ghosts.value = next;
    if (changed) setState(() {});
  }

  /// The cards another player has in hand at [board] (with their groups), and the claim of theirs
  /// that beat this player's own (docs/multiplayer.md, "Who has a card"): first grab wins, by the
  /// server's time; until the server has answered this player's own grab, nothing is decided.
  ({Map<int, String> holders, LiveClaim? beat}) _claimsOn(Board board) {
    final coop = ref.read(coopProvider.notifier);
    final mine = coop.myClaim;
    final mineSlot = mine == null ? -1 : board.slotOfCard(mine.card);
    final mineCards = mineSlot < 0 ? const <int>{} : {for (final s in board.groupOf(mineSlot)) board.slots[s]};
    final holders = <int, String>{};
    LiveClaim? beat;
    for (final c in coop.claims()) {
      final slot = board.slotOfCard(c.card);
      if (slot < 0 || board.isLocked(slot)) continue;
      final cards = {for (final s in board.groupOf(slot)) board.slots[s]};
      if (mine != null && cards.any(mineCards.contains)) {
        if (mine.since == null && c.since != null) continue;
        if (mine.before(c)) continue;
        beat = c;
      }
      for (final k in cards) {
        holders[k] = c.userId;
      }
    }
    return (holders: holders, beat: beat);
  }

  String _nameOf(String userId) => ref.read(playerProfileProvider(userId)).value?.displayName ?? 'Player';

  /// Another player has [card]: a light tap and a short word, once in a while.
  void _sayHeld(int card) {
    final holder = _holders[card];
    if (holder == null) return;
    Haptics.light();
    final last = _saidNo[card];
    if (last != null && DateTime.now().difference(last) < const Duration(milliseconds: 1500)) return;
    _saidNo[card] = DateTime.now();
    showToast(context, '${_nameOf(holder)} has this card', icon: AppIcons.players);
  }

  /// A tap: a card another player has cannot be picked, nor be the place a picked card goes.
  void _tap(int slot) {
    if (_inCoop && _holders.isNotEmpty) {
      final board = ref.read(gameControllerProvider(_args!)).board;
      if (slot < board.cells && _holders.containsKey(board.slots[slot])) return _sayHeld(board.slots[slot]);
    }
    _ctrl.tap(slot);
  }

  /// This player's drag was taken from under the finger: the cards went back; say why.
  void _onDragLost(int card, DragLoss reason) {
    if (!mounted || !_inCoop) return;
    Haptics.light();
    final who = reason == DragLoss.claimed ? (_holders[card] ?? _lostTo) : _lastMover[card];
    if (who == null) return;
    final name = _nameOf(who);
    showToast(
      context,
      switch (reason) {
        DragLoss.claimed => '$name took it first',
        DragLoss.locked => '$name placed this card',
        DragLoss.moved => '$name moved this card',
      },
      icon: AppIcons.players,
    );
  }

  /// A drag refused at once: another player has the card.
  void _onDragRefused(int slot) {
    final board = ref.read(gameControllerProvider(_args!)).board;
    if (slot < board.cells) _sayHeld(board.slots[slot]);
  }

  /// A drop on the board; [_dropMoved] says whether it moved anything (the others then wait for the
  /// move instead of sending the card back).
  void _drop(int from, int to) {
    final before = ref.read(gameControllerProvider(_args!)).board;
    // Not onto a card another player has: the dragged card goes back.
    if (_inCoop && to < before.cells && _holders.containsKey(before.slots[to])) {
      _dropMoved = false;
      return _sayHeld(before.slots[to]);
    }
    _ctrl.drop(from, to);
    _dropMoved = !identical(before, ref.read(gameControllerProvider(_args!)).board);
  }

  /// This player's drag, for the others to see (Play together).
  void _dragMove(int slot, Offset at, bool start) {
    if (!_inCoop) return;
    final coop = ref.read(coopProvider.notifier);
    if (start) {
      _dropMoved = false;
      final board = ref.read(gameControllerProvider(_args!)).board;
      if (slot < board.cells) coop.dragStart(board.slots[slot], at.dx, at.dy);
    } else {
      coop.dragMove(at.dx, at.dy);
    }
  }

  void _dragEnd(int slot) {
    if (!_inCoop) return;
    ref.read(coopProvider.notifier).dragEnd(dropped: _dropMoved);
    _dropMoved = false;
  }

  /// Puts the shared board on the table (the others' changes, or this player's going back).
  void _showShared(CoopBoardUpdate u) {
    if (!mounted || _args == null) return;
    for (final op in u.update.applied) {
      for (final c in op.change.slots) {
        _lastMover[c.after] = op.userId;
      }
    }
    _showingShared = true;
    try {
      _ctrl.showShared(u.update.after);
    } finally {
      _showingShared = false;
    }
    // This player's change lost to an earlier one: its cards went back.
    if (u.update.dropped.isNotEmpty) Haptics.light();
  }

  /// The host's next board: dealt here, then handed to the game, which moves the guests onto it.
  Future<void> _handNextBoard() async {
    if (!_coopNextPending || !_fitted || _args == null || _listening != _args) return;
    _coopNextPending = false;
    setState(() => _coopStarting = true);
    try {
      await _dealtWithTwins();
      if (!mounted) return;
      final s = ref.read(gameControllerProvider(_args!));
      final g = await ref.read(coopProvider.notifier).nextBoard(puzzleId: widget.puzzleId, grid: BoardCode.toPath(_spec.fullCode), layout: s.board.slots, painting: _painting);
      if (mounted) _attachCoop(g.id);
    } on CoopRefusal catch (e) {
      if (mounted) await showRefusal(context, e);
    } finally {
      if (mounted) setState(() => _coopStarting = false);
    }
  }

  /// The host leaves a finished shared board: the guests are waiting for the next board, so leaving
  /// ends the game for everyone (after asking). True when the host may go.
  Future<bool> _endBeforeLeaving() async {
    if (!await confirmEndForEveryone(context) || !mounted) return false;
    try {
      await ref.read(coopProvider.notifier).endForEveryone();
    } on CoopRefusal catch (e) {
      debugPrint('coop end: $e');
    }
    _detachCoop();
    return true;
  }

  /// A board dealt here is dealt again once its twins are measured (docs/twins.md): the layout
  /// shared with a game is the final deal, so this waits for it (a moment; the measure gives up
  /// after 8 s and the board then keeps its deal).
  Future<void> _dealtWithTwins() async {
    for (var i = 0; i < 120 && mounted && _args != null && ref.read(gameControllerProvider(_args!).notifier).awaitsTwins; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  /// Pause > Play together: the game starts on this board as it is, and the share sheet opens.
  Future<void> _playTogether() async {
    await _dealtWithTwins();
    if (!mounted) return;
    final puzzle = ref.read(resolvedPuzzleProvider(widget.puzzleId));
    if (puzzle == null || _args == null) return;
    final s = ref.read(gameControllerProvider(_args!));
    final game = await startPlayTogether(context, ref, puzzle: puzzle, grid: BoardCode.toPath(_spec.fullCode), layout: s.board.slots, painting: _painting);
    if (game != null && mounted) _attachCoop(game.id);
  }

  /// Settles the board for the decoded picture, once. A square board stays
  /// as it is; an Expand board follows the picture's proportions, so a board
  /// picked on the difficulty screen already matches (the same decode), while
  /// the next picture of a pack gets the size its tier has for this picture.
  /// A save resumes on the board it was dealt on (found by its piece count:
  /// square, Expand or a board of an older build); a save no board of this
  /// picture matches (a layout that changed) starts fresh.
  void _fitToPicture(ui.Image image, {required bool giant}) {
    if (_fitted) return;
    _fitted = true;
    // A shared board is the host's board as dealt: it is not laid out again here.
    if (_coopGameId != null) return;
    if (_coopNextPending) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _handNextBoard();
      });
    }
    final aspect = image.width / image.height;
    final current = _args!;
    var next = _spec.fitTo(aspect);
    // A Giant pack picture deals only giant sizes and other pictures only
    // normal ones, whatever size the route named (a pack's next picture).
    if (next.isGiant != giant) next = BoardSpec.forPicture(next.mode, giant ? BoardSpec.firstGiantTier : 2, aspect, expand: _spec.expand);
    var resume = false;
    if (current.layout != null) {
      final saved = BoardSpec.fromSaved(_spec.mode, _spec.cells, aspect, layout: current.layout);
      if (saved != null && Board.isValidLayout(saved, current.layout)) {
        // A square board saved with Expand on keeps Expand for the next picture.
        next = saved.withExpand(saved.expand || _spec.expand);
        resume = true;
      }
    }
    if (next == _spec && resume == (current.layout != null)) return _started();
    _spec = next;
    _args = _argsFor(next, resume: resume, session: current.session + 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _listen();
    });
    _started();
  }

  /// `puzzle_started`, once the board is settled for the picture (a board in progress resumes).
  void _started() => AppAnalytics.event('puzzle_started', {..._boardProps(), 'resumed': _resumed, 'first': widget.first});

  /// The board, for analytics: no ids but the catalogue pack's (player photos are `my-puzzles`).
  Map<String, Object?> _boardProps() => {
        'mode': _spec.mode.code,
        'board': _spec.code,
        'cards': _spec.cells,
        'painting': _painting,
        'giant': _spec.isGiant,
        'expand': _spec.expand,
        'daily': ref.read(dailyPuzzleProvider)?.id == widget.puzzleId,
        'pack': ref.read(resolvedPuzzleProvider(widget.puzzleId))?.packId,
      };

  /// Follows the events of the current session's controller.
  void _listen() {
    if (_args == null || _args == _listening) return;
    _sub?.cancel();
    _listening = _args;
    _sub = ref.read(gameControllerProvider(_args!).notifier).events.listen(_onEvent);
    _stateSub?.close();
    _stateSub = ref.listenManual(gameControllerProvider(_args!), _onState);
    if (_coopGameId != null) {
      _bridge?.dispose();
      _bridge = CoopBridge(ref.read(coopProvider.notifier), _SharedBoard(this));
      _bridge!.resync();
    }
    if (_coopNextPending && _fitted) _handNextBoard();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _routeAnimation?.removeStatusListener(_onRouteAnimation);
    // The board closes: nothing of it stays in this player's hand for the others.
    if (_coopGameId != null) {
      _coopCtrl.dragEnd(dropped: false);
      _coopCtrl.hold(null);
    }
    _liveWakeSub?.cancel();
    _ghostTicker.dispose();
    _ghosts.dispose();
    _sub?.cancel();
    _stateSub?.close();
    _bridge?.dispose();
    _boardSub?.cancel();
    _saveDebounce?.cancel();
    _confetti.dispose();
    _ticks?.cancel();
    if (_viewSave?.isActive ?? false) {
      _viewSave!.cancel();
      _saveView();
    }
    _zoom.removeListener(_onZoomChanged);
    _zoom.dispose();
    _coachTimer?.cancel();
    _gatherCheck?.cancel();
    super.dispose();
  }

  /// The board can be seen (the picture before the deal counts only then; owner, TestFlight
  /// 2026-10-18): the app is in front (iOS keeps drawing an app that is not: the screenshot editor
  /// and TestFlight's feedback sheet, Control Center, a call), this screen is on top with its way
  /// in finished (Next puzzle fades it in), and nothing covers it (a sheet, an alert, another page).
  /// On the web a window without focus is still in view.
  bool _inView(BuildContext context) {
    final life = WidgetsBinding.instance.lifecycleState;
    if (life != null && life != AppLifecycleState.resumed && !(kIsWeb && life == AppLifecycleState.inactive)) return false;
    final route = ModalRoute.of(context);
    if (route != null && (!route.isCurrent || !(route.animation?.isCompleted ?? true))) return false;
    return TickerMode.valuesOf(context).enabled;
  }

  /// The way in of this screen's page: the picture before the deal waits until it is done.
  Animation<double>? _routeAnimation;

  void _onRouteAnimation(AnimationStatus _) {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (!identical(animation, _routeAnimation)) {
      _routeAnimation?.removeStatusListener(_onRouteAnimation);
      _routeAnimation = animation?..addStatusListener(_onRouteAnimation);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The picture before the deal waits while the app is not in front (no frame may come to say so).
    if (_args != null && state != AppLifecycleState.resumed && !(kIsWeb && state == AppLifecycleState.inactive)) _ctrl.holdPreview();
    if (mounted) setState(() {});
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _saveNow();
      if (_viewSave?.isActive ?? false) {
        _viewSave!.cancel();
        _saveView();
      }
    }
  }

  GameController get _ctrl => ref.read(gameControllerProvider(_args!).notifier);

  void _onEvent(GameEventKind e) {
    switch (e) {
      // Haptics (docs/native-ui.md): a click to pick up, a light tap to put down, a firmer one when
      // cards join or lock, the success touch for a double lock; never a heavy one.
      case GameEventKind.pick:
        Sfx.instance.pick();
        Haptics.selection();
      case GameEventKind.move:
        Sfx.instance.swap();
        Haptics.light();
        _scheduleSave();
      case GameEventKind.join:
        Sfx.instance.snap();
        Haptics.medium();
        _scheduleSave();
      case GameEventKind.lock:
        Sfx.instance.lock();
        Haptics.medium();
        _scheduleSave();
      case GameEventKind.doubleLock:
        Sfx.instance.lock();
        Haptics.success();
        setState(() => _chainFlash++);
        _scheduleSave();
        // The "Lock 5 cards in one move" quests count it when the board is finished.
        final locked = ref.read(gameControllerProvider(_args!)).justLocked.length;
        if (locked >= Goals.lockRun) showToast(context, '$locked cards locked in one move', icon: AppIcons.lock);
      case GameEventKind.undo:
        Sfx.instance.whoosh();
        Haptics.light();
        _scheduleSave();
      case GameEventKind.rearrange:
        Sfx.instance.whoosh();
        _shuffleTicks();
        _scheduleSave();
      case GameEventKind.invalid:
        Sfx.instance.error();
        Haptics.light();
      case GameEventKind.win:
        _onWin();
    }
    if (_coach != null) _coachOn(e);
    _maybeStuckTip(e);
  }

  /// Shuffle and Gather: a few soft ticks while the cards slide (280 ms), then a light tap as they
  /// settle; under Reduce motion the cards jump, so one tap.
  void _shuffleTicks() {
    _ticks?.cancel();
    if (A11y.reduceMotionOf(context)) return Haptics.light();
    _ticks = Haptics.run(const [Duration.zero, Duration(milliseconds: 90), Duration(milliseconds: 180)], lastAt: const Duration(milliseconds: 280));
  }

  /// The first board's hints follow what the player does: pick a card (its place is outlined),
  /// put it there, see it lock or join, then the tools come in.
  void _coachOn(GameEventKind e) {
    final s = ref.read(gameControllerProvider(_args!));
    final moved = e == GameEventKind.move || e == GameEventKind.join || e == GameEventKind.lock || e == GameEventKind.doubleLock;
    switch (_coach!) {
      case _CoachStep.pick || _CoachStep.retry || _CoachStep.place:
        if (e == GameEventKind.pick && s.selected != null) {
          _ctrl.guide(s.board.homeOf(s.selected!));
          _setCoach(_CoachStep.place);
        } else if (moved) {
          _ctrl.guide(null);
          final locked = e == GameEventKind.lock || e == GameEventKind.doubleLock;
          _setCoach(locked ? _CoachStep.locked : e == GameEventKind.join ? _CoachStep.joined : _CoachStep.retry);
          if (locked || e == GameEventKind.join) _coachTimer = Timer(const Duration(seconds: 6), () => _finishCoach(toast: true));
        }
      case _CoachStep.locked || _CoachStep.joined:
        if (moved) _finishCoach(toast: true);
    }
  }

  void _setCoach(_CoachStep step) {
    _coachTimer?.cancel();
    if (mounted) setState(() => _coach = step);
  }

  /// The hints are done (or closed): the tools come in, and the board is never explained again.
  void _finishCoach({bool toast = false}) {
    _coachTimer?.cancel();
    if (_coach == null || !mounted) return;
    ref.read(settingsProvider.notifier).setTutorialSeen();
    if (_args != null) _ctrl.guide(null);
    setState(() => _coach = null);
    if (toast) showToast(context, 'Fewer moves earn more stars. Take your time.', icon: AppIcons.star);
  }

  /// A new player making move after move without a lock or join hears once where help is.
  void _maybeStuckTip(GameEventKind e) {
    if (e == GameEventKind.join || e == GameEventKind.lock || e == GameEventKind.doubleLock || e == GameEventKind.undo) {
      _dryMoves = 0;
      return;
    }
    if (e != GameEventKind.move || _coach != null) return;
    if (++_dryMoves < 6) return;
    final steps = ref.read(firstStepsProvider);
    if (!steps.guided || steps.tips.contains('stuck')) return;
    ref.read(firstStepsProvider.notifier).sawTip('stuck');
    showToast(context, 'Stuck? Hint shows where one card belongs.', icon: AppIcons.hint);
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 900), _saveNow);
  }

  void _saveNow() {
    // Nothing to save before the board is settled for the picture (and a
    // save then could overwrite the one being resumed).
    if (_args == null || !mounted || !_fitted || _solvedElsewhere) return;
    // A guest's shared board is the host's: nothing of it is saved for the guest.
    if (_coopGuest) return;
    final s = ref.read(gameControllerProvider(_args!));
    if (s.status == GameStatus.won) return;
    ref.read(progressProvider.notifier).saveBoard(
      widget.puzzleId,
      gridSize: _spec.cells,
      mode: _spec.mode.code,
      layout: s.board.slots,
      moves: s.moves,
      seconds: s.elapsed,
      hints: s.hintsUsed,
      session: _playId,
      resumed: _resumed,
      painting: _painting,
      par: s.basePar,
      peeked: s.peeked,
      bestLock: s.bestLock,
    );
  }

  /// Another device changed this picture's board while it is open here.
  Future<void> _onBoardUpdate(BoardUpdate u) async {
    if (u.puzzleId != widget.puzzleId || !mounted || !_fitted || _args == null || _askingBoard) return;
    // A shared board follows the game, not the saves of the player's other devices.
    if (_coopGameId != null) return;
    final s = ref.read(gameControllerProvider(_args!));
    if (s.status == GameStatus.won || _solvedElsewhere) return;
    if (!u.after.inProgress) {
      // The picture's board was finished elsewhere. When it was this play-through, nothing is left
      // to play here, and a save from this screen would bring the old board back.
      if (u.after.completed && u.after.session == _playId) _closeSolvedElsewhere();
      return;
    }
    // Already the board on screen (this device's own save coming back).
    if (u.after.layout?.join(',') == s.board.slots.join(',')) return;
    if (u.chosen) {
      _openSaved(u.after);
      return;
    }
    if (u.continued) {
      // The player went on with this same board elsewhere: its newer state replaces this one.
      _openSaved(u.after);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = rootNavigatorKey.currentContext;
        if (ctx == null || !ctx.mounted) return;
        showAppAlert(
          ctx,
          title: 'Board updated',
          message: 'You played this picture on another device. Its newer board is loaded here.',
          confirmLabel: 'Continue',
          cancelLabel: null,
        );
      });
      return;
    }
    _askingBoard = true;
    _ctrl.pause();
    final here = PuzzleProgress.fromRow('', {
      'puzzleId': widget.puzzleId,
      'gridSize': _spec.cells,
      'mode': _spec.mode.code,
      'layout': s.board.slots.join(','),
      'moves': s.moves,
      'elapsedSeconds': s.elapsed,
    });
    final title = ref.read(resolvedPuzzleProvider(widget.puzzleId))?.title;
    final choice = await showBoardChoiceSheet(context, title: title, device: here, other: u.after);
    _askingBoard = false;
    if (!mounted) return;
    if (choice == BoardChoice.other) {
      _openSaved(u.after);
    } else {
      _ctrl.resume();
      _saveNow();
    }
  }

  /// The player finished this board on another device: the clock stops, the screen closes.
  Future<void> _closeSolvedElsewhere() async {
    _solvedElsewhere = true;
    _saveDebounce?.cancel();
    _ctrl.pause();
    final route = ModalRoute.of(context);
    await showAppAlert(
      context,
      title: 'Solved on another device',
      message: 'You finished this board on another device. Its stars and time are saved.',
      confirmLabel: 'Close board',
      cancelLabel: null,
    );
    if (!mounted) return;
    // A sheet open over the board (the pause menu) closes with it.
    if (route != null) Navigator.of(context).popUntil((r) => r == route);
    context.pop();
  }

  /// A new play-through (restart, replay): its moves and time add to the picture's totals.
  void _newPlay() {
    _playId = SyncOp.newId();
    _resumed = false;
  }

  /// Reopens the picture on the board saved for it (another device's).
  void _openSaved(PuzzleProgress p) {
    _saveDebounce?.cancel();
    final spec = BoardSpec.fromCells(GameMode.fromCode(p.mode), p.gridSize);
    context.pushReplacement('/game/${widget.puzzleId}/${BoardCode.toPath(spec.fullCode)}');
  }

  Future<void> _onWin() async {
    if (_completionHandled) return;
    if (_coopGuest) return _onCoopWin();
    _completionHandled = true;
    // The first board is done: no need to explain it again.
    if (_coach != null) _finishCoach();
    _saveDebounce?.cancel();
    Sfx.instance.win();
    Haptics.success();
    // Reduce motion: no confetti (decorative motion); the completion card says it all.
    if (!A11y.reduceMotionOf(context)) _confetti.play();
    final s = ref.read(gameControllerProvider(_args!));
    final existing = ref.read(puzzleProgressProvider(widget.puzzleId));
    final firstTime = existing?.completed != true;
    _firstSolve = firstTime;
    final stars = s.stars;
    final puzzle = ref.read(resolvedPuzzleProvider(widget.puzzleId));
    final daily = ref.read(dailyPuzzleProvider);
    // Quests this win finishes: the ones ready with the solve counted, minus those ready before.
    final now = DateTime.now();
    final profileBefore = ref.read(profileProvider).value;
    final open = ref.read(openFeaturesProvider);
    final rows = {...?ref.read(progressProvider).value};
    // Guided start: only pictures finished after Quests opened count (none while they are locked).
    final questsSince = ref.read(countsFromProvider(Reveal.quests));
    final readyBefore = {for (final g in readyGoals(rows.values, profileBefore, open, now, dailyPuzzle: daily?.id, since: questsSince)) g.key};
    rows[widget.puzzleId] = PuzzleProgress.fromRow(existing?.id ?? '', {
      ...?existing?.toData(),
      'puzzleId': widget.puzzleId,
      'gridSize': _spec.cells,
      'mode': _spec.mode.code,
      'layout': '',
      'moves': s.moves,
      'elapsedSeconds': s.elapsed,
      'completed': true,
      'completedAt': now.toUtc().toIso8601String(),
      'stars': math.max(existing?.stars ?? 0, stars),
      'painting': _painting,
      'par': s.basePar,
      'peeked': s.peeked,
      'bestLock': s.bestLock,
      // This board as the quests count it, as the win op records it.
      'finishes': BoardFinish.logWith(existing?.toData() ?? const {}, BoardFinish(
        at: now,
        mode: _spec.mode.code,
        gridSize: _spec.cells,
        painting: _painting,
        par: s.basePar,
        moves: s.moves,
        seconds: s.elapsed,
        peeked: s.peeked,
        bestLock: s.bestLock,
        stars: stars,
        hints: s.hintsUsed,
      )),
    });
    final questsReady = [for (final g in readyGoals(rows.values, profileBefore, open, now, dailyPuzzle: daily?.id, since: questsSince)) if (!readyBefore.contains(g.key)) g];
    AppAnalytics.event('puzzle_completed', {..._boardProps(), 'stars': stars, 'moves': s.moves, 'par': s.basePar, 'seconds': s.elapsed, 'hints': s.hintsUsed, 'resumed': _resumed, 'firstTime': firstTime});
    if (widget.first) AppAnalytics.event('first_board_completed', {'moves': s.moves, 'seconds': s.elapsed, 'stars': stars});
    ref.read(progressProvider.notifier).complete(
      widget.puzzleId,
      gridSize: _spec.cells,
      mode: _spec.mode.code,
      moves: s.moves,
      seconds: s.elapsed,
      hints: s.hintsUsed,
      stars: stars,
      session: _playId,
      resumed: _resumed,
      painting: _painting,
      par: s.basePar,
      peeked: s.peeked,
      bestLock: s.bestLock,
    );
    final reward = await ref.read(profileProvider.notifier).recordCompletion(
          puzzleId: widget.puzzleId,
          cells: _spec.playableCells,
          stars: stars,
          firstTime: firstTime,
          mode: _spec.mode,
          painting: _painting,
          moves: s.moves,
          seconds: s.elapsed,
          dailyBonus: daily != null && daily.id == widget.puzzleId ? 50 : 0,
        );
    unawaited(bumpEventProgress(ref, packId: puzzle?.packId));
    if (reward.levelUp) AppAnalytics.event('level_up', {'level': reward.level});
    if (!mounted) return;
    final before = profileBefore?.level ?? reward.level;
    setState(() {
      _reward = (coins: reward.coins, xp: reward.xp, levelUp: reward.levelUp, level: reward.level);
      _questsReady = questsReady;
      _unlocked = [
        for (var l = before + 1; l <= reward.level; l++)
          for (final u in Unlocks.atLevel(l))
            if (!open.has(u)) u,
      ];
    });
    for (final u in _unlocked) {
      AppAnalytics.event('feature_unlocked', {'feature': u.name, 'by': 'level'});
    }
  }

  /// A guest finished a shared board. With a card of their own locked on it, they get what the board
  /// would pay as their own (coins, XP, piggy bank, level); nothing else is written: no progress,
  /// solve totals, quests, achievements, pack progress or first-steps counts.
  Future<void> _onCoopWin() async {
    _completionHandled = true;
    _saveDebounce?.cancel();
    Sfx.instance.win();
    Haptics.success();
    if (!A11y.reduceMotionOf(context)) _confetti.play();
    final coop = ref.read(coopProvider);
    final log = ref.read(coopProvider.notifier).log;
    if (!coop.placedACard || log == null) return;
    final stars = Board.starsFor(moves: log.applied, par: math.max(1, Board(_spec, log.base).par));
    final firstTime = ref.read(puzzleProgressProvider(widget.puzzleId))?.completed != true;
    final reward = await ref.read(profileProvider.notifier).recordCoopReward(
          gameId: coop.game!.id,
          board: coop.game!.board,
          cells: _spec.playableCells,
          stars: stars,
          firstTime: firstTime,
          mode: _spec.mode,
          painting: _painting,
        );
    if (mounted) setState(() => _coopReward = (coins: reward.coins, xp: reward.xp));
  }

  Future<void> _hint() async {
    final profile = ref.read(profileProvider).value;
    if (profile == null) return;
    final ok = await ref.read(profileProvider.notifier).useHint();
    if (!mounted) return;
    if (!ok) {
      Sfx.instance.error();
      _offerStore('No hints left. Buy one for ${countOf(Economy.hintCostCoins, 'coin')}.');
      return;
    }
    _toolUsed('hint', stock: profile.hints);
    Sfx.instance.coin();
    _ctrl.showHint();
  }

  /// Magic: from stock (Lucky Wheel prizes) first, then for coins.
  Future<void> _magic() async {
    final stock = ref.read(profileProvider).value?.magics ?? 0;
    final ok = await ref.read(profileProvider.notifier).useMagic();
    if (!mounted) return;
    if (!ok) {
      Sfx.instance.error();
      _offerStore('Not enough coins. Magic costs ${countOf(Economy.magicLockCostCoins, 'coin')}.');
      return;
    }
    _toolUsed('magic', stock: stock);
    Sfx.instance.coin();
    _nextKind = CoopOpKind.magic;
    if (!_ctrl.magicLock()) _nextKind = CoopOpKind.move;
  }

  /// Peek: the cards fly to their places for a moment and back (a little
  /// longer on giant boards, where there is more to read). From stock first,
  /// then for coins.
  Future<void> _peek() async {
    final state = ref.read(gameControllerProvider(_args!));
    if (state.showingPicture) return;
    final giant = state.board.spec.isGiant;
    final stock = ref.read(profileProvider).value?.peeks ?? 0;
    final ok = await ref.read(profileProvider.notifier).usePeek();
    if (!mounted) return;
    if (!ok) {
      Sfx.instance.error();
      _offerStore('Not enough coins. Peek costs ${countOf(Economy.peekCostCoins, 'coin')}.');
      return;
    }
    _toolUsed('peek', stock: stock);
    Sfx.instance.whoosh();
    Haptics.light();
    _ctrl.peek(duration: giant ? GameController.giantPeekTime : GameController.peekTime);
  }

  /// Shuffle (free, owner 2026-10-17): the loose cards trade places; on a giant board only the
  /// ones in view. Cards in place and joined groups stay.
  void _shuffle() {
    final giant = ref.read(gameControllerProvider(_args!)).board.spec.isGiant;
    final size = _boardSize;
    _nextKind = CoopOpKind.shuffle;
    final moved = giant && size != null ? _ctrl.shuffle(view: _zoom.visible, size: size) : _ctrl.shuffle();
    _nextKind = CoopOpKind.move;
    if (moved == 0) {
      showToast(context, 'Nothing left to shuffle', icon: AppIcons.shuffle);
    } else {
      _toolUsed('shuffle', cards: moved);
    }
  }

  /// `tool_used`: [stock] is what the player held before (a paid tool comes from stock while there
  /// is any, else for coins); free tools give the cards they moved.
  void _toolUsed(String tool, {int? stock, int? cards}) =>
      AppAnalytics.event('tool_used', {'tool': tool, 'paid': stock == null ? 'free' : stock > 0 ? 'stock' : 'coins', 'cards': cards, 'giant': _spec.isGiant});

  /// Gather (giant boards, at any zoom): the cards that belong in view come into it. The toast
  /// offers Undo while nothing else has changed.
  void _gather(Size boardSize) {
    _nextKind = CoopOpKind.gather;
    final n = _ctrl.gather(_zoom.visible, boardSize);
    _nextKind = CoopOpKind.move;
    if (n == 0) {
      showToast(context, 'Every card for this view is here or nearby', icon: AppIcons.gather);
      return;
    }
    _toolUsed('gather', cards: n);
    // A shared board has no Undo: the others may have moved since.
    if (_inCoop) {
      showToast(context, '${formatCount(n)} card${n == 1 ? '' : 's'} gathered', icon: AppIcons.gather);
      return;
    }
    final args = _args;
    final mark = ref.read(gameControllerProvider(args!)).history.length;
    showToast(
      context,
      '${formatCount(n)} card${n == 1 ? '' : 's'} gathered',
      icon: AppIcons.gather,
      action: (
        label: 'Undo',
        onTap: () {
          if (!mounted || _args != args) return;
          final s = ref.read(gameControllerProvider(args));
          if (s.history.length != mark || s.status != GameStatus.playing) {
            showToast(context, 'The board has changed since, so the gather stays', icon: AppIcons.gather);
            return;
          }
          _ctrl.undo();
          _toolUsed('gather_undo');
        },
      ),
    );
  }

  void _scheduleGatherCheck() {
    _gatherCheck?.cancel();
    _gatherCheck = Timer(const Duration(milliseconds: 150), _checkGather);
  }

  void _checkGather() {
    final size = _boardSize;
    if (!mounted || _args == null || size == null || _zoom.viewport.isEmpty) return;
    final state = ref.read(gameControllerProvider(_args!));
    final board = state.board;
    if (!board.spec.isGiant) return;
    _gatherChecked = board;
    final can = canGather(board, _zoom.visible, size, twins: state.twins);
    if (can != _canGather) setState(() => _canGather = can);
  }

  void _offerStore(String message) {
    showToast(context, message, leading: const CoinIcon(size: 20));
    context.push('/store');
  }

  void _openPause() {
    _ctrl.pause();
    final coop = ref.read(coopProvider);
    final shared = _inCoop;
    final puzzle = ref.read(resolvedPuzzleProvider(widget.puzzleId));
    final playing = ref.read(gameControllerProvider(_args!)).status != GameStatus.won;
    final together = shared
        ? (coop.isHost ? _Together.host : _Together.guest)
        : !widget.first && !_guestBoard && playing && puzzle != null && canPlayTogether(ref, puzzle)
            ? _Together.start
            : _Together.none;
    showAppSheet(
      context,
      builder: (ctx) => _PauseSheet(
        together: together,
        onTogether: () async {
          final container = ProviderScope.containerOf(context, listen: false);
          switch (together) {
            case _Together.start:
              Navigator.pop(ctx);
              await _playTogether();
            case _Together.host:
              if (!await confirmEndForEveryone(context) || !mounted || !ctx.mounted) return;
              Navigator.pop(ctx);
              try {
                await container.read(coopProvider.notifier).endForEveryone();
                _detachCoop();
                if (mounted) showToast(context, 'Game ended. The board is yours.', icon: AppIcons.players);
              } on CoopRefusal catch (e) {
                if (mounted) await showRefusal(context, e);
              }
            case _Together.guest:
              if (!await confirmLeaveGame(context) || !mounted || !ctx.mounted) return;
              Navigator.pop(ctx);
              await container.read(coopProvider.notifier).leave();
              CoopRoutes.exit(container);
            case _Together.none:
              return;
          }
        },
        onResume: () => Navigator.pop(ctx),
        onRestart: () async {
          // A started board is thrown away: ask first, like Discard and pick a board does.
          final moves = ref.read(gameControllerProvider(_args!)).moves;
          if (moves > 0) {
            final ok = await showAppAlert(
              context,
              title: 'Shuffle and restart?',
              message: 'This board and its $moves ${moves == 1 ? 'move' : 'moves'} are thrown away and the cards are dealt again. Stars and records stay.',
              confirmLabel: 'Shuffle',
              destructive: true,
            );
            if (!ok || !mounted || !ctx.mounted) return;
          }
          Navigator.pop(ctx);
          AppAnalytics.event('puzzle_restarted', {..._boardProps(), 'from': 'pause', 'moves': moves});
          _completionHandled = false;
          _newPlay();
          _ctrl.restart(preview: GameScreen.dealPreview);
        },
        onQuit: () {
          Navigator.pop(ctx);
          _saveNow();
          final router = GoRouter.of(context);
          context.pop();
          // Leaving the board is not leaving the game: the seat stays, and the board is a tap away.
          final game = shared ? coop.game : null;
          final rctx = rootNavigatorKey.currentContext;
          if (game == null || rctx == null || !rctx.mounted) return;
          showToast(rctx, 'The game goes on. Return to it any time.', icon: AppIcons.players, action: (
            label: 'Return',
            onTap: () {
              AppAnalytics.event('coop_returned', {'from': 'board', 'players': game.playerIds.length});
              router.push(game.route);
            },
          ));
        },
        // Discard and pick a board (owner, 2026-10-17): the way to throw a board away without
        // dealing the same one again, and to change its mode or size. The board picker opens with
        // nothing in progress, every mode and board free to pick.
        onChangeDifficulty: () async {
          final moves = ref.read(gameControllerProvider(_args!)).moves;
          final ok = await showAppAlert(
            context,
            title: 'Discard progress?',
            message: '${moves > 0 ? 'This board and its $moves ${moves == 1 ? 'move' : 'moves'} are' : 'This board is'} thrown away. Then pick any mode and board for this picture. Stars and records stay.',
            confirmLabel: 'Discard',
            destructive: true,
          );
          if (!ok || !mounted || !ctx.mounted) return;
          Navigator.pop(ctx);
          AppAnalytics.event('puzzle_discarded', {..._boardProps(), 'from': 'game', 'moves': moves});
          await ref.read(progressProvider.notifier).discard(widget.puzzleId);
          if (!mounted) return;
          context.pushReplacement('/play/${widget.puzzleId}');
          // The board picker's own Discard progress says the same.
          final rctx = rootNavigatorKey.currentContext;
          if (rctx != null && rctx.mounted) showToast(rctx, 'Progress discarded. Pick any mode or board.', icon: AppIcons.trash);
        },
      ),
    ).then((_) => _ctrl.resume());
  }

  /// Where the player stands in this puzzle's pack once this one counts as
  /// solved, and the next unsolved puzzle after it (wrapping round), or null
  /// when this was the last one left.
  _PackProgress _packProgress(Puzzle puzzle, GameState state) {
    final all = ref.watch(allPuzzlesProvider).value ?? const <Puzzle>[];
    final progress = ref.watch(progressProvider).value ?? const <String, PuzzleProgress>{};
    final packs = ref.watch(packsProvider).value ?? const <Pack>[];
    final list = all.where((p) => p.packId == puzzle.packId).toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    bool solved(Puzzle p) => p.id == puzzle.id || progress[p.id]?.completed == true;
    int stars(Puzzle p) => p.id == puzzle.id ? math.max(state.stars, progress[p.id]?.stars ?? 0) : (progress[p.id]?.stars ?? 0);
    final idx = list.indexWhere((p) => p.id == puzzle.id);
    Puzzle? next;
    for (var k = 1; k < list.length && idx >= 0; k++) {
      final candidate = list[(idx + k) % list.length];
      if (!solved(candidate) && !candidate.isLockedByDate) {
        next = candidate;
        break;
      }
    }
    final pack = packs.where((p) => p.id == puzzle.packId).firstOrNull;
    return _PackProgress(
      name: pack?.name,
      solved: list.where(solved).length,
      total: list.length,
      stars: list.fold<int>(0, (sum, p) => sum + stars(p)),
      next: next,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    _zoom.reduceMotion = A11y.reduceMotionOf(context);
    final puzzle = ref.watch(resolvedPuzzleProvider(widget.puzzleId));
    final settings = ref.watch(settingsProvider);
    final profile = ref.watch(profileProvider).value;
    if (puzzle == null) {
      return Scaffold(appBar: AppBar(leading: const BackButton()), body: const Loader());
    }
    // Giant pack pictures (or a giant board named by the route, before the
    // catalogue says so) are decoded at full size for zooming in.
    final giant = ref.watch(isGiantPuzzleProvider(widget.puzzleId)) || _spec.isGiant;
    final imageProvider = puzzleImageFor(puzzle.imageUrl, giant: giant);
    final image = ref.watch(imageProvider);
    if (image.hasValue) _fitToPicture(image.requireValue, giant: giant);
    final state = ref.watch(gameControllerProvider(_args!));
    // Twin cards (docs/twins.md), measured once the picture is decoded. A board dealt here waits
    // for them (a moment longer under "Dealing the cards"), so the deal can take them into account.
    final ctrl = ref.read(gameControllerProvider(_args!).notifier);
    final twins = image.hasValue ? ref.watch(boardTwinsProvider((puzzle.imageUrl, giant, _args!.spec))).value : null;
    if (twins != null && state.twins == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ctrl.useTwins(twins);
      });
    }
    final dealing = ctrl.awaitsTwins;
    final zoomable = state.board.spec.isGiant;
    if (zoomable && image.hasValue) _syncView(state);
    if (zoomable && image.hasValue && !identical(state.board, _gatherChecked) && !(_gatherCheck?.isActive ?? false)) _scheduleGatherCheck();
    final sel = state.selected;
    // Locate: while the map is on, the selected card's place shows on it.
    final locate = sel != null && sel < state.board.cells && !state.board.isLocked(sel) ? sel : null;
    final coaching = _coach != null && image.hasValue && state.status == GameStatus.playing;
    // A board dealt here opens on its picture: it shows from the first frame the cards are drawn,
    // and its time counts only while the player can see it (_inView): a picture that arrives late,
    // while the app is not in front or something covers the board, waits for the player.
    final previewShown = state.previewing && image.hasValue && !dealing;
    if (previewShown) {
      final inView = _inView(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        inView ? ctrl.startPreview() : ctrl.holdPreview();
      });
    }
    // Play together: the shared game, the other players' cards on the board, and the end of the game
    // for this board (the host goes on alone; a guest's screen is closed by CoopHost).
    final coopState = ref.watch(coopProvider);
    final shared = _coopGameId != null && coopState.playing && coopState.game?.id == _coopGameId;
    if (_coopGameId != null && !shared) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _coopGameId != null && !_inCoop) _detachCoop();
      });
    }
    final ownMarks = shared ? coopCardMarks(context, ref, coopState) : const <int, CoopCardMark>{};
    final heldSlots = <int, CoopCardMark>{
      for (final e in ownMarks.entries)
        if (e.value.held && state.board.slotOfCard(e.key) >= 0) state.board.slotOfCard(e.key): e.value,
    };
    final coopGuest = shared ? !coopState.isHost : _guestBoard;
    _playerMarks = shared ? coopPlayerMarks(context, ref, coopState) : const {};
    // Who has which card: their cards (and groups) cannot be taken here; a grab of this player's that
    // came second gives way.
    final claims = shared ? _claimsOn(state.board) : (holders: const <int, String>{}, beat: null);
    _holders = claims.holders;
    final symbols = A11y.symbolsOf(context);
    final marks = <int, CoopCardMark>{
      ...ownMarks,
      for (final e in claims.holders.entries)
        if (!(ownMarks[e.key]?.held ?? false))
          if (_playerMarks[e.value] case final m?) e.key: m.copyWith(badge: symbols),
    };
    final beat = claims.beat;
    if (beat != null) {
      final sel = state.selected;
      final selCard = sel == null || sel >= state.board.cells ? null : state.board.slots[sel];
      if (selCard != null && claims.holders.containsKey(selCard) && !_puttingDown) {
        // This player's pick came second: it is put down, with a word of who has it.
        _puttingDown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _puttingDown = false;
          if (!mounted) return;
          _ctrl.clearSelection();
          Haptics.light();
          showToast(context, '${_nameOf(beat.userId)} took it first', icon: AppIcons.players);
        });
      }
    }
    _lostTo = beat?.userId;
    // The finished picture's pack, for the completion overlay.
    final finishedPack = state.status == GameStatus.won && image.hasValue && !coopGuest ? _packProgress(puzzle, state) : null;

    return Scaffold(
      backgroundColor: c.canvas,
      // While Peek or the preview shows the picture, a touch anywhere ends it (owner, 2026-10-17):
      // the cards fly back at once. The touch goes on to what it hit (the pause button). Not while
      // the cards are being dealt: the picture has not shown yet.
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: state.peeking || previewShown ? (_) => ctrl.endPeek() : null,
        child: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _Hud(
                  state: state,
                  showTimer: settings.showTimer,
                  onPause: _openPause,
                  title: puzzle.title,
                  painting: _painting,
                  players: shared ? const CoopPlayersChip() : null,
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, cons) {
                      // The tiling decides the board's proportions: honeycombs
                      // and triangle strips keep regular cells and crop the
                      // picture; rectangular grids follow the picture within
                      // sane limits (a 900×21 handscroll must not become a strip).
                      final imageAspect = image.value == null ? 3 / 4 : image.value!.width / image.value!.height;
                      // Giant boards keep a strip above the board for their tools.
                      final bar = zoomable && image.hasValue ? GiantBoardBar.height : 0.0;
                      final fitted = state.board.tiling.fit(Size(cons.maxWidth - 24, cons.maxHeight - 16 - bar), imageAspect);
                      final w = fitted.width, h = fitted.height;
                      _boardSize = Size(w, h);
                      Widget loading() => SizedBox(
                            width: w,
                            height: h,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (puzzle.blurhash != null)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Opacity(opacity: 0.6, child: HashImage(hash: puzzle.blurhash!, color: c.boardBackground)),
                                  ),
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Loader(),
                                    const SizedBox(height: 12),
                                    Text('Dealing the cards', style: TextStyle(color: c.textSecondary, fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ],
                            ),
                          );
                      return Center(
                        child: image.when(
                          loading: loading,
                          error: (e, _) => EmptyState(
                            icon: AppIcons.image,
                            title: 'Picture did not load',
                            message: 'Check your connection and try again.',
                            action: BigButton(label: 'Try again', expand: false, onTap: () => ref.invalidate(imageProvider)),
                          ),
                          data: (img) => dealing ? loading() : Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (zoomable)
                                    GiantBoardBar(
                                      zoom: _zoom,
                                      width: w,
                                      showMap: _showMap,
                                      onMap: () {
                                        setState(() => _showMap = !_showMap);
                                        ref.read(giantViewsProvider).showMap = _showMap;
                                      },
                                      onGather: state.status == GameStatus.playing && !state.showingPicture && _canGather ? () => _gather(Size(w, h)) : null,
                                    ),
                                  if (!zoomable)
                                    IgnorePointer(
                                      // The host's next board waits until the game has it.
                                      ignoring: _coopStarting,
                                      child: BoardWidget(
                                        image: img,
                                        state: state,
                                        width: w,
                                        height: h,
                                        cardStyle: settings.cardStyle,
                                        painting: _painting,
                                        onTap: _tap,
                                        onDrop: _drop,
                                        marks: marks,
                                        ghosts: shared ? _ghosts : null,
                                        onDragMove: shared ? _dragMove : null,
                                        onDragEnd: shared ? _dragEnd : null,
                                        blocked: shared ? claims.holders.keys.toSet() : const {},
                                        onDragRefused: shared ? _onDragRefused : null,
                                        onDragLost: shared ? _onDragLost : null,
                                      ),
                                    )
                                  else
                                    SizedBox(
                                      width: w,
                                      height: h,
                                      child: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          BoardWidget(
                                            image: img,
                                            state: state,
                                            width: w,
                                            height: h,
                                            cardStyle: settings.cardStyle,
                                            painting: _painting,
                                            zoom: _zoom,
                                            onTap: _tap,
                                            onDrop: _drop,
                                            marks: marks,
                                            ghosts: shared ? _ghosts : null,
                                            onDragMove: shared ? _dragMove : null,
                                            onDragEnd: shared ? _dragEnd : null,
                                            blocked: shared ? claims.holders.keys.toSet() : const {},
                                            onDragRefused: shared ? _onDragRefused : null,
                                            onDragLost: shared ? _onDragLost : null,
                                          ),
                                          OffscreenSelection(zoom: _zoom, board: state.board, boardSize: Size(w, h), selected: state.selected),
                                          // Play together: where the others' held cards are, off screen.
                                          for (final e in heldSlots.entries)
                                            OffscreenSelection(zoom: _zoom, board: state.board, boardSize: Size(w, h), selected: e.key, color: e.value.color, onColor: e.value.onColor, label: e.value.initial),
                                          // ... and the cards they are dragging, where their finger is.
                                          if (shared)
                                            Positioned.fill(
                                              child: ValueListenableBuilder<Map<int, CoopGhost>>(
                                                valueListenable: _ghosts,
                                                builder: (context, ghosts, _) => Stack(
                                                  clipBehavior: Clip.none,
                                                  children: [
                                                    for (final g in ghosts.values)
                                                      OffscreenSelection(zoom: _zoom, board: state.board, boardSize: Size(w, h), selected: null, point: Offset(g.at.dx * w, g.at.dy * h), color: g.mark.color, onColor: g.mark.onColor, label: g.mark.initial),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          if (_showMap)
                                            Positioned(
                                              top: 8,
                                              right: 8,
                                              child: ListenableBuilder(
                                                listenable: _zoom,
                                                builder: (context, child) => IgnorePointer(
                                                  ignoring: !_zoom.zoomed,
                                                  child: AnimatedOpacity(opacity: _zoom.zoomed ? 1 : 0, duration: const Duration(milliseconds: 180), child: child),
                                                ),
                                                child: ValueListenableBuilder<Map<int, CoopGhost>>(
                                                  valueListenable: _ghosts,
                                                  builder: (context, ghosts, _) => GiantMinimap(
                                                    image: img,
                                                    board: state.board,
                                                    boardSize: Size(w, h),
                                                    zoom: _zoom,
                                                    // Small enough to cover only a few cards in the corner.
                                                    width: math.min(84.0, w * 0.22),
                                                    selected: state.selected,
                                                    painting: _painting,
                                                    locate: locate,
                                                    others: {for (final e in heldSlots.entries) e.key: e.value.color},
                                                    otherPoints: [for (final g in ghosts.values) (Offset(g.at.dx * w, g.at.dy * h), g.mark.color)],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          GiantMilestones(
                                            board: state.board,
                                            playing: state.status == GameStatus.playing,
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              if (_chainFlash > 0)
                                IgnorePointer(
                                  child: A11y.reduceMotionOf(context)
                                      // Reduce motion: the words fade in and out without the pop and drift.
                                      ? Text('×2 DOUBLE LOCK', key: ValueKey(_chainFlash), style: TextStyle(fontWeight: FontWeight.w700, fontSize: TypeSize.title2, letterSpacing: -0.3, color: Brand.star, shadows: [Shadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 12)]))
                                          .animate()
                                          .fadeIn(duration: 150.ms)
                                          .then(delay: 650.ms)
                                          .fadeOut(duration: 300.ms)
                                      : Text('×2 DOUBLE LOCK', key: ValueKey(_chainFlash), style: TextStyle(fontWeight: FontWeight.w700, fontSize: TypeSize.title2, letterSpacing: -0.3, color: Brand.star, shadows: [Shadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 12)]))
                                          .animate()
                                          .fadeIn(duration: 150.ms)
                                          .scale(begin: const Offset(0.6, 0.6), end: const Offset(1.1, 1.1), curve: Curves.easeOutBack)
                                          .then(delay: 500.ms)
                                          .fadeOut(duration: 300.ms)
                                          .slideY(end: -0.6),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (state.status != GameStatus.won)
                  // The first board's hints sit where the tools are; the tools come in after them.
                  // Both stay laid out, so the board keeps its size.
                  Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      IgnorePointer(
                        ignoring: coaching,
                        child: AnimatedOpacity(
                          opacity: coaching ? 0 : 1,
                          duration: const Duration(milliseconds: 350),
                          child: ExcludeSemantics(
                            excluding: coaching,
                            child: _BoosterBar(
                              hints: profile?.hints ?? 0,
                              peeks: profile?.peeks ?? 0,
                              magics: profile?.magics ?? 0,
                              playing: state.status == GameStatus.playing && !state.showingPicture,
                              onHint: _hint,
                              onMagic: _magic,
                              onPeek: _peek,
                              onShuffle: _shuffle,
                            ),
                          ),
                        ),
                      ),
                      // The first hint waits for the picture to be dealt.
                      if (coaching && !state.previewing) _Coach(step: _coach!, onClose: _finishCoach),
                    ],
                  )
                else
                  const SizedBox(height: 120),
              ],
            ),
          ),
          if (state.status == GameStatus.won && image.hasValue && coopGuest)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: PageWidth.sheet),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: SoftCard(
                        child: CoopGuestFinish(
                          // Over (ended, removed): no next board to wait for; the alert says why.
                          waiting: shared,
                          rewards: (shared && coopState.placedACard) || _coopReward != null
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _RewardStat(icon: const CoinIcon(size: 17), label: 'Coins', value: _coopReward == null ? '…' : '+${formatCount(_coopReward!.coins)}'),
                                    const SizedBox(width: 32),
                                    _RewardStat(icon: Icon(AppIcons.xp, size: 17, color: context.accent), label: 'XP', value: _coopReward == null ? '…' : '+${formatCount(_coopReward!.xp)}'),
                                  ],
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
          else if (finishedPack != null)
            _CompletionOverlay(
              puzzle: puzzle,
              image: image.requireValue,
              state: state,
              reward: _reward,
              questsReady: _questsReady,
              unlocked: _unlocked,
              first: widget.first,
              pack: finishedPack,
              packDone: _firstSolve && finishedPack.complete,
              onQuests: () => context.go('/events'),
              onReplay: () {
                AppAnalytics.event('puzzle_restarted', {..._boardProps(), 'from': 'replay'});
                _completionHandled = false;
                setState(() {
                  _reward = null;
                  _questsReady = const [];
                  _unlocked = const [];
                });
                if (shared) {
                  // The same picture again, dealt anew for everyone.
                  context.pushReplacement('/game/${widget.puzzleId}/${BoardCode.toPath(_spec.fullCode)}?coop=$_coopGameId&next=1${_painting ? '&painting=1' : ''}');
                  return;
                }
                _newPlay();
                _ctrl.restart(preview: GameScreen.dealPreview);
              },
              onNext: (next) async {
                if (shared && next != null) {
                  // The host picks the next board; the guests are moved onto it once it is dealt.
                  context.pushReplacement('/game/${next.id}/${BoardCode.toPath(_spec.fullCode)}?coop=$_coopGameId&next=1${_painting ? '&painting=1' : ''}');
                  return;
                }
                if (shared && !await _endBeforeLeaving()) return;
                if (!context.mounted) return;
                final offer = await maybeShowInterstitial(context, ref);
                if (!context.mounted) return;
                if (offer != null && leaveGameForCreative(context, ref, offer)) return;
                if (next != null) {
                  // Same mode, tier, Painting and Expand; the next picture settles its own size.
                  final query = [if (_painting) 'painting=1', if (_spec.expand) 'expand=1'];
                  context.pushReplacement('/game/${next.id}/${BoardCode.toPath(_spec.fullCode)}${query.isEmpty ? '' : '?${query.join('&')}'}');
                } else {
                  context.pop();
                }
              },
              onHome: () async {
                if (shared && !await _endBeforeLeaving()) return;
                if (!context.mounted) return;
                final offer = await maybeShowInterstitial(context, ref);
                if (!context.mounted) return;
                if (offer != null && leaveGameForCreative(context, ref, offer)) return;
                context.pop();
              },
            ),
          // Over the results: the panel is opaque.
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confetti,
              blastDirectionality: BlastDirectionality.explosive,
              numberOfParticles: 24,
              maxBlastForce: 24,
              minBlastForce: 8,
              gravity: 0.25,
              emissionFrequency: 0.04,
              colors: const [Brand.accent, Brand.star, Brand.ticket, Color(0xFF94A3B8), Colors.white],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _Hud extends StatelessWidget {
  const _Hud({required this.state, required this.showTimer, required this.onPause, required this.title, this.painting = false, this.players});
  final GameState state;

  /// Play together: the players chip, beside the title.
  final Widget? players;
  final bool showTimer;
  final VoidCallback onPause;
  final String title;
  final bool painting;

  @override
  // Chrome keeps its size above the text-size cap of the bars (see ChromeText).
  Widget build(BuildContext context) => ChromeText(child: Builder(builder: _build));

  /// Widest the HUD gets (a wide window, the web on a desktop): the board takes the room.
  static const double maxWidth = 760;

  Widget _build(BuildContext context) {
    final c = context.colors;
    final b = state.board;
    final hud = Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Column(
        children: [
          // One glass bar, the same material as the toolbar under the board.
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.pill),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: context.isDark ? 0.35 : 0.06), blurRadius: 14, offset: const Offset(0, 3))],
            ),
            child: GlassSurface(
              borderRadius: BorderRadius.circular(Radii.pill),
              opacity: context.isDark ? 0.7 : 0.82,
              hairline: Border.all(color: c.stroke, width: 0.5),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 18, 4),
                child: Row(
                  children: [
                    _PauseButton(onTap: onPause),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: TypeSize.body, letterSpacing: -0.2)),
                          Text('${b.spec.mode.label} · ${b.spec.size} · ${b.spec.label}${painting ? ' · Painting' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textSecondary, fontSize: TypeSize.caption)),
                        ],
                      ),
                    ),
                    if (players != null) ...[const SizedBox(width: 8), players!],
                    const SizedBox(width: 10),
                    // Moves against par ("14 / 18": three stars while within it), then time.
                    _HudStat(label: 'Moves', value: formatCount(state.moves), sub: '/${state.par}'),
                    if (showTimer) ...[
                      const SizedBox(width: 16),
                      _HudStat(label: 'Time', value: formatDuration(state.elapsed)),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: ProgressBar(value: b.lockedCount / b.playableCells, height: 6)),
              const SizedBox(width: 10),
              Text('${b.lockedCount}/${b.playableCells} locked${b.floatingGroups > 0 ? ' · ${b.floatingGroups} group${b.floatingGroups == 1 ? '' : 's'}' : ''}', style: TextStyle(fontSize: TypeSize.caption, fontWeight: FontWeight.w500, color: c.textSecondary)),
              const SizedBox(width: 10),
              Stars(count: state.stars, size: 14),
            ],
          ),
        ],
      ),
    );
    if (!context.isWide) return hud;
    return Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: maxWidth), child: hud));
  }
}

/// Pause, at the start of the HUD capsule: a tinted 40 pt circle, 44 pt to tap.
class _PauseButton extends StatelessWidget {
  const _PauseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Pause',
        child: Pressable(
          onTap: onTap,
          scale: 0.9,
          child: TapTarget(
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: context.colors.accentTint, shape: BoxShape.circle),
              child: Icon(AppIcons.pauseFill, size: 18, color: context.accent),
            ),
          ),
        ),
      );
}

/// A HUD figure without a box: the name small above, the number below
/// (tabular figures, so the timer does not jitter), an optional quiet suffix.
class _HudStat extends StatelessWidget {
  const _HudStat({required this.label, required this.value, this.sub});
  final String label;
  final String value;
  final String? sub;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: TextStyle(fontSize: TypeSize.micro, fontWeight: FontWeight.w600, color: c.textTertiary)),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: TypeSize.headline, letterSpacing: -0.3, fontFeatures: tabularFigures)),
            if (sub != null) Text(sub!, style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w600, color: c.textTertiary, fontFeatures: tabularFigures)),
          ],
        ),
      ],
    );
  }
}

class _BoosterBar extends StatelessWidget {
  const _BoosterBar({required this.hints, this.peeks = 0, this.magics = 0, required this.playing, required this.onHint, required this.onMagic, required this.onPeek, required this.onShuffle});
  final int hints;

  /// Peeks and Magic in stock: used before coins, shown as a count on the tool.
  final int peeks;
  final int magics;
  final bool playing;

  final VoidCallback onHint;
  final VoidCallback onMagic;
  final VoidCallback onPeek;
  final VoidCallback onShuffle;

  @override
  // Chrome keeps its size above the text-size cap of the bars (see ChromeText).
  Widget build(BuildContext context) => ChromeText(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final shuffle = _Booster(key: const ValueKey('booster-shuffle'), icon: AppIcons.shuffle, label: 'Shuffle', enabled: playing, onTap: onShuffle);
    final paid = [
      _Booster(key: const ValueKey('booster-peek'), icon: AppIcons.peek, label: 'Peek', stock: peeks, price: Economy.peekCostCoins, enabled: playing, onTap: onPeek),
      _Booster(key: const ValueKey('booster-magic'), icon: AppIcons.magic, label: 'Magic', stock: magics, price: Economy.magicLockCostCoins, enabled: playing, onTap: onMagic),
      _Booster(icon: AppIcons.hint, label: 'Hint', stock: hints, price: Economy.hintCostCoins, enabled: playing, onTap: onHint),
    ];
    // A floating glass capsule, the same material, shape and shadow as the tab bar.
    Widget capsule(Widget child, {EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 6)}) => DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.pill),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: context.isDark ? 0.4 : 0.09), blurRadius: 20, offset: const Offset(0, 6)),
              BoxShadow(color: Colors.black.withValues(alpha: context.isDark ? 0.2 : 0.04), blurRadius: 2, offset: const Offset(0, 1)),
            ],
          ),
          child: GlassSurface(
            borderRadius: BorderRadius.circular(Radii.pill),
            opacity: context.isDark ? 0.7 : 0.82,
            hairline: Border.all(color: context.isDark ? Colors.white.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.06), width: 0.5),
            child: SizedBox(height: _Booster.barHeight, child: Padding(padding: padding, child: child)),
          ),
        );
    // Shuffle, free and not a move, in its own glass capsule of the toolbar's height (owner,
    // 2026-10-17: it replaced Undo), as wide as its name needs with the room the tools have around
    // theirs, never narrower than a circle; the three helpers, which come from stock or cost coins,
    // together in the other capsule.
    final bar = Row(
      children: [
        capsule(
          ConstrainedBox(constraints: const BoxConstraints(minWidth: _Booster.barHeight - 2 * 14), child: shuffle),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        const SizedBox(width: 10),
        Expanded(child: capsule(Row(children: [for (final b in paid) Expanded(child: b)]))),
      ],
    );
    final padded = Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: bar);
    // A wide window keeps the tools at a phone's width under the board.
    if (!context.isWide) return padded;
    return Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: padded));
  }
}

/// One tool: its mark over its name, and one badge on the mark's corner that
/// says what using it takes: how many are in stock (ink count, "999+" above
/// that, as iOS badges do), or once the stock is out, its price (a coin and
/// the amount). Shuffle is free and has no badge. Every tool has the same two
/// lines, so marks and names align.
class _Booster extends StatelessWidget {
  const _Booster({super.key, required this.icon, required this.label, required this.enabled, required this.onTap, this.stock, this.price});
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  /// In stock (used before coins); null for free tools.
  final int? stock;

  /// Coins per use once the stock is out.
  final int? price;

  /// Height of the toolbar capsule.
  static const barHeight = 58.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final count = stock ?? 0;
    final buying = stock != null && count == 0 && price != null;
    // The badge cuts out of the glass with a ring of the surface colour.
    final ring = GlassSurface.tintColor(context);
    Widget? badge;
    if (count > 0) {
      badge = Container(
        constraints: const BoxConstraints(minWidth: 18),
        height: 18,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c.textPrimary, borderRadius: BorderRadius.circular(Radii.pill), border: Border.all(color: ring, width: 1.5)),
        child: Text(count > 999 ? '999+' : '$count', style: TextStyle(fontSize: TypeSize.micro, fontWeight: FontWeight.w700, color: ring, height: 1.1, fontFeatures: tabularFigures)),
      );
    } else if (buying) {
      badge = Container(
        height: 18,
        padding: const EdgeInsets.fromLTRB(3, 0, 6, 0),
        decoration: BoxDecoration(
          color: context.isDark ? c.cardElevated : Colors.white,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(color: c.stroke, width: 0.5),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: context.isDark ? 0.3 : 0.08), blurRadius: 3, offset: const Offset(0, 1))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CoinIcon(size: 12),
            const SizedBox(width: 2),
            Text(formatCount(price!), style: TextStyle(fontSize: TypeSize.micro, fontWeight: FontWeight.w700, color: c.textPrimary, height: 1.1, fontFeatures: tabularFigures)),
          ],
        ),
      );
    }
    return Semantics(
      button: true,
      enabled: enabled,
      label: count > 0 ? '$label, $count left' : (buying ? '$label, ${countOf(price!, 'coin')}' : label),
      child: Pressable(
        onTap: enabled ? onTap : null,
        scale: 0.9,
        child: Opacity(
          opacity: enabled ? 1 : 0.35,
          child: SizedBox(
            height: barHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 26,
                  height: 26,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(icon, size: 24, color: context.accent),
                      if (badge != null) Positioned(left: 14, top: -4, child: badge),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                Text(label, maxLines: 1, style: const TextStyle(fontSize: TypeSize.caption, fontWeight: FontWeight.w600, letterSpacing: -0.1)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Play together in the pause sheet: start a game on this board, or, during one, End game for
/// everyone (the host) or Leave game (a guest).
enum _Together { none, start, host, guest }

class _PauseSheet extends ConsumerWidget {
  const _PauseSheet({required this.onResume, required this.onRestart, required this.onQuit, required this.onChangeDifficulty, this.together = _Together.none, this.onTogether});
  final VoidCallback onChangeDifficulty;
  final VoidCallback onResume;
  final VoidCallback onRestart;
  final VoidCallback onQuit;
  final _Together together;
  final VoidCallback? onTogether;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHeader(title: 'Paused', center: true),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _PauseToggle(icon: AppIcons.musicNote2, label: 'Music', on: settings.music, onChanged: n.setMusic),
              _PauseToggle(icon: AppIcons.speaker2Fill, label: 'Sound', on: settings.sound, onChanged: n.setSound),
              _PauseToggle(icon: AppIcons.waveform, label: 'Haptics', on: settings.haptics, onChanged: n.setHaptics),
              _PauseToggle(icon: AppIcons.time, label: 'Timer', on: settings.showTimer, onChanged: n.setShowTimer),
            ],
          ),
          const SizedBox(height: 20),
          BigButton(label: 'Resume', icon: AppIcons.playFill, onTap: onResume),
          const SizedBox(height: 12),
          // The other ways out, under the one primary action: leaving keeps the
          // board; the two that throw it away are red, in their own group, and ask first.
          SoftCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                // A guest's board is the host's: nothing to save, and the seat stays theirs.
                _PauseAction(icon: AppIcons.squareArrowLeft, label: together == _Together.guest ? 'Quit' : 'Save & quit', onTap: onQuit),
                if (together == _Together.start) ...[
                  _PauseDivider(),
                  _PauseAction(key: const ValueKey('pause-play-together'), icon: AppIcons.players, label: 'Play together', onTap: onTogether!),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          SoftCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                // A shared board is never dealt again or changed: the others play it too.
                if (together == _Together.host)
                  _PauseAction(key: const ValueKey('pause-end-game'), icon: AppIcons.endGame, label: 'End game for everyone', destructive: true, onTap: onTogether!)
                else if (together == _Together.guest)
                  _PauseAction(key: const ValueKey('pause-leave-game'), icon: AppIcons.leaveGame, label: 'Leave game', destructive: true, onTap: onTogether!)
                else ...[
                  _PauseAction(icon: AppIcons.shuffle, label: 'Shuffle and restart', destructive: true, onTap: onRestart),
                  _PauseDivider(),
                  _PauseAction(key: const ValueKey('pause-discard'), icon: AppIcons.sliderHorizontal3, label: 'Discard and pick a board', destructive: true, onTap: onChangeDifficulty),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// An on/off switch as a round button, the way Control Center draws them:
/// filled cobalt with a white mark when on, grey when off, and the state
/// spelled out under the name.
class _PauseToggle extends StatelessWidget {
  const _PauseToggle({required this.icon, required this.label, required this.on, required this.onChanged});
  final IconData icon;
  final String label;
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      toggled: on,
      label: label,
      child: Pressable(
        onTap: () => onChanged(!on),
        scale: 0.92,
        child: SizedBox(
          width: 64,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: on ? context.accentFill : (context.isDark ? c.cardElevated : const Color(0xFFE6E6EB)), shape: BoxShape.circle),
                child: Icon(icon, size: 23, color: on ? context.onAccent : c.textSecondary),
              ),
              const SizedBox(height: 5),
              // A large text size shrinks the words to the button's width instead of breaking them.
              FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, style: const TextStyle(fontSize: TypeSize.caption, fontWeight: FontWeight.w600))),
              FittedBox(fit: BoxFit.scaleDown, child: Text(on ? 'On' : 'Off', maxLines: 1, style: TextStyle(fontSize: TypeSize.micro, fontWeight: FontWeight.w500, color: c.textTertiary))),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row in the pause sheet's grouped list. [destructive] rows (they throw
/// the board away, after asking) are red, the iOS destructive action.
class _PauseAction extends StatelessWidget {
  const _PauseAction({super.key, required this.icon, required this.label, required this.onTap, this.destructive = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final tone = destructive ? context.colors.danger : null;
    return Pressable(
      onTap: onTap,
      scale: 0.99,
      // 50 pt, taller when a large text size wraps the label.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 50),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          child: Row(
            children: [
              Icon(icon, size: 20, color: tone ?? context.accent),
              const SizedBox(width: 14),
              Expanded(child: Text(label, style: TextStyle(fontSize: TypeSize.callout, fontWeight: FontWeight.w500, color: tone))),
            ],
          ),
        ),
      ),
    );
  }
}

class _PauseDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Divider(height: 0.5, thickness: 0.5, indent: 50, color: context.colors.stroke);
}

/// First game: "How to play" in three short steps, each with its mark, and
/// one line about stars, in a card at the bottom over the tools (they wait
/// until it is read anyway). A light dim keeps the board in view above it.
/// "Got it", or a tap anywhere, closes it for good.
/// The first board's steps.
enum _CoachStep { pick, place, retry, locked, joined }

/// One hint per step on the first board, where the tools will be: what to do now, in a line.
/// It never covers the board and goes away with the first lock or join.
class _Coach extends StatelessWidget {
  const _Coach({required this.step, required this.onClose});
  final _CoachStep step;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (icon, text) = switch (step) {
      _CoachStep.pick => (AppIcons.tapCard, 'Tap a card to pick it up.'),
      _CoachStep.place => (AppIcons.tapToPlace, 'Now tap the outlined spot. That is where it belongs.'),
      _CoachStep.retry => (AppIcons.tapCard, 'Not its place yet. Tap a card, then tap its outlined spot.'),
      _CoachStep.locked => (AppIcons.lock, 'It locked in place. Cards that belong side by side also join and move together.'),
      _CoachStep.joined => (AppIcons.group, 'They joined and now move together. A card in its right spot locks in place.'),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: PageWidth.sheet),
        child: Semantics(
          liveRegion: true,
          child: Container(
            key: const ValueKey('coach'),
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(22),
              border: c.highContrast ? Border.all(color: c.stroke) : null,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: context.isDark ? 0.45 : 0.12), blurRadius: 24, offset: const Offset(0, 6))],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Row(
                key: ValueKey('coach-${step.name}'),
                children: [
                  IconTile(icon: icon, size: IconTile.medium),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(text, style: TextStyle(fontSize: TypeSize.body, height: 1.3, fontWeight: FontWeight.w500, color: c.textPrimary)),
                  ),
                  IconButton(
                    key: const ValueKey('coach-close'),
                    tooltip: 'Close the hints',
                    onPressed: onClose,
                    icon: Icon(AppIcons.xmark, size: 18, color: c.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: A11y.reduceMotionOf(context) ? 0 : 0.3, curve: Curves.easeOutCubic, duration: 350.ms);
  }
}

/// Standing in the pack shown on the completion screen.
class _PackProgress {
  const _PackProgress({required this.name, required this.solved, required this.total, required this.stars, required this.next});
  final String? name;
  final int solved;
  final int total;
  final int stars;

  /// Next unsolved puzzle in the pack, or null when every puzzle is solved.
  final Puzzle? next;

  bool get complete => total > 0 && solved >= total;
}

/// Completion: the picture is revealed with rewards and next actions. A
/// "View picture" pill swaps the results for the finished photo on its own,
/// with one way forward kept at the bottom so nobody gets stuck.
class _CompletionOverlay extends StatefulWidget {
  const _CompletionOverlay({
    required this.puzzle,
    required this.image,
    required this.state,
    required this.reward,
    required this.pack,
    required this.onReplay,
    required this.onNext,
    required this.onHome,
    this.questsReady = const [],
    this.unlocked = const [],
    this.onQuests,
    this.first = false,
    this.packDone = false,
  });
  final Puzzle puzzle;

  /// This picture finished its pack (its first solve, and the pack is complete now).
  final bool packDone;
  final ui.Image image;
  final GameState state;
  final ({int coins, int xp, bool levelUp, int level})? reward;

  /// Quests this solve finished; a tap opens the Quests tab to claim them.
  final List<Goal> questsReady;

  /// What the level-up opened (Squares, Painting...).
  final List<Unlock> unlocked;
  final VoidCallback? onQuests;

  /// The first board: "Home" instead of "Back to pack" (the board was opened over Home).
  final bool first;
  String get backLabel => first ? 'Home' : 'Back to pack';
  final _PackProgress pack;
  final VoidCallback onReplay;
  final void Function(Puzzle? next) onNext;
  final VoidCallback onHome;

  @override
  State<_CompletionOverlay> createState() => _CompletionOverlayState();
}

class _CompletionOverlayState extends State<_CompletionOverlay> {
  static const _swap = Duration(milliseconds: 250);

  /// The small celebration's touch (the win itself plays the success touch): a soft tick as each
  /// star pops in (they start 300 ms in, 150 ms apart, and are fullest about 200 ms later), and the
  /// success touch once more when the picture finished its pack.
  HapticRun? _ticks;
  bool _packTouched = false;
  static Duration _starAt(int i) => Duration(milliseconds: 300 + i * 150 + 200);
  static final _packAt = _starAt(3) + const Duration(milliseconds: 200);

  @override
  void initState() {
    super.initState();
    _packTouched = widget.packDone;
    _ticks = Haptics.run([for (var i = 0; i < widget.state.stars.clamp(0, 3); i++) _starAt(i)], lastAt: widget.packDone ? _packAt : null, last: HapticKind.success);
  }

  @override
  void didUpdateWidget(_CompletionOverlay old) {
    super.didUpdateWidget(old);
    // The pack's count can arrive a moment after the overlay.
    if (widget.packDone && !_packTouched) {
      _packTouched = true;
      _packTouch = Timer(const Duration(milliseconds: 300), Haptics.success);
    }
  }

  Timer? _packTouch;

  @override
  void dispose() {
    _ticks?.cancel();
    _packTouch?.cancel();
    super.dispose();
  }

  /// Target mode; the picture layer stays mounted until its fade-out ends.
  bool _viewing = false;
  bool _pictureMounted = false;

  void _view() {
    Haptics.selection();
    setState(() {
      _viewing = true;
      _pictureMounted = true;
    });
  }

  void _results() {
    Haptics.selection();
    setState(() => _viewing = false);
  }

  @override
  Widget build(BuildContext context) {
    final puzzle = widget.puzzle, state = widget.state, reward = widget.reward, pack = widget.pack;
    final c = context.colors;
    // The pack is finished (or nothing unsolved is playable): the primary
    // action returns to the pack instead of promising a next puzzle.
    final backIsPrimary = pack.next == null;
    final credit = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(AppIcons.credit, size: 12, color: _viewing ? Colors.white.withValues(alpha: 0.7) : c.textTertiary),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            '${puzzle.author} · ${puzzle.source}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: TypeSize.caption, color: _viewing ? Colors.white.withValues(alpha: 0.7) : c.textTertiary),
          ),
        ),
      ],
    );

    // The finished picture is the reward: it stays in full colour above a
    // results panel (no scrim over it). A tap on it shows it on its own.
    // Each figure shrinks a little when a large text size leaves the four too little room.
    Widget fit(Widget stat) => Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: stat));
    final stats = Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        fit(_RewardStat(icon: const CoinIcon(size: 17), label: 'Coins', value: reward == null ? '…' : '+${formatCount(reward.coins)}')),
        fit(_RewardStat(icon: Icon(AppIcons.xp, size: 17, color: context.accent), label: 'XP', value: reward == null ? '…' : '+${formatCount(reward.xp)}')),
        fit(_RewardStat(label: 'Moves', value: formatCount(state.moves))),
        fit(_RewardStat(label: 'Time', value: formatDuration(state.elapsed))),
      ],
    );
    // A wide window puts the results in a sidebar beside the picture (see _CompletionLayout).
    final side = context.isExpanded;
    final panel = Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: side ? null : const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: side ? null : [BoxShadow(color: Colors.black.withValues(alpha: context.isDark ? 0.4 : 0.1), blurRadius: 24, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Scrolls when a quest and a level-up make it taller than a small phone.
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < 3; i++)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 3),
                              child: Icon(
                                i < state.stars ? AppIcons.star : AppIcons.starOutline,
                                size: i == 1 ? 34 : 28,
                                color: i < state.stars ? context.star : (c.highContrast ? c.textTertiary : c.stroke),
                              ).animate().custom(
                                    delay: (300 + i * 150).ms,
                                    duration: 450.ms,
                                    curve: A11y.reduceMotionOf(context) ? Curves.easeOut : Curves.easeOutBack,
                                    // Reduce motion: each star fades in instead of popping.
                                    builder: (_, v, child) => A11y.reduceMotionOf(context)
                                        ? Opacity(opacity: v.clamp(0.0, 1.0), child: child)
                                        : Transform.scale(scale: v, child: child),
                                  ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Picture complete', style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 2),
                      Text(puzzle.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textSecondary, fontWeight: FontWeight.w600, fontSize: TypeSize.body)),
                      const SizedBox(height: 16),
                      stats,
                      if (pack.total > 0) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${formatCount(pack.solved)} of ${formatCount(pack.total)} solved${pack.name != null ? ' · ${pack.name}' : ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w600, color: c.textSecondary),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Icon(AppIcons.star, size: 13, color: context.star),
                            const SizedBox(width: 4),
                            Text('${formatCount(pack.stars)}/${formatCount(pack.total * 3)}', style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w700, color: c.textPrimary)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ProgressBar(value: pack.solved / pack.total, height: 4),
                      ],
                      if (reward?.levelUp == true) ...[
                        const SizedBox(height: 12),
                        _ResultLine(
                          key: const ValueKey('level-up-line'),
                          icon: AppIcons.crown,
                          text: widget.unlocked.isEmpty
                              ? 'Level ${reward!.level} reached'
                              : 'Level ${reward!.level} · ${widget.unlocked.map((u) => u == Unlock.painting ? 'Painting is open' : '${u.label} are open').join(' · ')}',
                          tinted: true,
                        ).animate().fadeIn(),
                      ],
                      if (widget.questsReady.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _ResultLine(
                          key: const ValueKey('quest-ready-line'),
                          icon: AppIcons.quests,
                          text: widget.questsReady.length == 1 ? 'Quest ready: ${widget.questsReady.first.title}' : '${widget.questsReady.length} quests ready to claim',
                          onTap: widget.onQuests,
                        ).animate().fadeIn(delay: 200.ms),
                      ],
                      const SizedBox(height: 12),
                      credit,
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  // Equal widths so neither label truncates on a 393 pt phone.
                  Expanded(child: BigButton(label: 'Replay', kind: ButtonKind.secondary, icon: AppIcons.arrowCounterclockwise, onTap: widget.onReplay)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: backIsPrimary
                        ? BigButton(label: widget.backLabel, icon: widget.first ? AppIcons.house : AppIcons.squareGrid2x2, onTap: widget.onHome)
                        : BigButton(label: 'Next puzzle', icon: AppIcons.arrowRight, onTap: () => widget.onNext(pack.next)),
                  ),
                ],
              ),
              if (backIsPrimary)
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(pack.complete ? 'Every picture in this pack is solved' : 'Nothing else to play here yet', style: TextStyle(color: c.textSecondary, fontWeight: FontWeight.w600)),
                )
              else
                Pressable(key: const ValueKey('completion-back'), onTap: widget.onHome, child: Padding(padding: const EdgeInsets.all(10), child: Text(widget.backLabel, style: TextStyle(color: context.accent, fontWeight: FontWeight.w600)))),
            ],
          ),
        ),
      ),
    ).animate().slideY(begin: A11y.reduceMotionOf(context) ? 0 : 0.25, duration: 350.ms, curve: Curves.easeOutCubic).fadeIn(duration: 200.ms);

    // The finished picture runs full-bleed from the very top of the screen
    // (under a light status bar and a glass back button, like a pack's cover)
    // down behind the results panel's rounded corners.
    final top = MediaQuery.paddingOf(context).top;
    final photo = GestureDetector(
      onTap: _view,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RawImage(image: widget.image, fit: BoxFit.cover, filterQuality: FilterQuality.medium),
          // A soft shade under the status bar and the back button, so both read on bright pictures.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: top + 72,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.36), Colors.transparent],
                ),
              ),
            ),
          ),
          Positioned(
            left: 10,
            top: top + 4,
            child: PhotoButton(key: const ValueKey('completion-back'), icon: AppIcons.back, size: 38, semanticLabel: 'Back to pack', onTap: widget.onHome),
          ),
          Positioned(
            right: 14,
            // Clear of the panel's rounded corners, which the photo runs behind.
            bottom: side ? 16 : _CompletionLayout.overlap + 12,
            child: _OverlayPill(icon: AppIcons.arrowUpLeftArrowDownRight, label: 'View picture', onTap: _view, small: true),
          ),
        ],
      ),
    );
    final results = AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: ColoredBox(
        color: c.card,
        child: CustomMultiChildLayout(
          delegate: _CompletionLayout(minPhoto: top + 120, side: side),
          children: [
            LayoutId(id: _CompletionLayout.photo, child: photo),
            LayoutId(id: _CompletionLayout.panel, child: panel),
          ],
        ),
      ),
    );

    // The photo on its own: no scrim, gutters or borders. A tap anywhere
    // brings the results back; the primary action stays within reach.
    // On black the status bar turns light (time and battery stay readable).
    final picture = AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _results,
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(child: RawImage(image: widget.image, fit: BoxFit.contain, filterQuality: FilterQuality.medium)),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Column(
                  children: [
                    _OverlayPill(icon: AppIcons.listBullet, label: 'Back to results', onTap: _results),
                    const Spacer(),
                    credit,
                    const SizedBox(height: 10),
                    backIsPrimary
                        ? _OverlayPill(icon: widget.first ? AppIcons.house : AppIcons.squareGrid2x2, label: widget.backLabel, primary: true, onTap: widget.onHome)
                        : _OverlayPill(icon: AppIcons.arrowRight, label: 'Next puzzle', primary: true, onTap: () => widget.onNext(pack.next)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );

    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            ignoring: _viewing,
            child: AnimatedOpacity(opacity: _viewing ? 0 : 1, duration: _swap, curve: Curves.easeOut, child: results),
          ),
          if (_pictureMounted)
            IgnorePointer(
              ignoring: !_viewing,
              child: AnimatedOpacity(
                opacity: _viewing ? 1 : 0,
                duration: _swap,
                curve: Curves.easeOut,
                onEnd: () {
                  if (!_viewing && mounted) setState(() => _pictureMounted = false);
                },
                child: AnimatedScale(scale: _viewing || A11y.reduceMotionOf(context) ? 1 : 0.96, duration: _swap, curve: Curves.easeOut, child: picture),
              ),
            ),
        ],
      ),
    );
  }
}

/// The completion page: the results panel at the bottom at its own height
/// (it scrolls inside when taller than the screen allows), the picture
/// filling everything above it and running [overlap] pt behind the panel's
/// rounded top corners.
class _CompletionLayout extends MultiChildLayoutDelegate {
  _CompletionLayout({required this.minPhoto, this.side = false});

  /// The picture never gets shorter than this (status bar and a strip of photo).
  final double minPhoto;

  /// A wide window: the picture on the left, the results in a [sideWidth] sidebar on the right
  /// at the window's height, their content in the middle.
  final bool side;
  static const sideWidth = 440.0;

  static const photo = 'photo';
  static const panel = 'panel';
  static const overlap = 28.0;

  @override
  void performLayout(Size size) {
    if (side) {
      final p = layoutChild(panel, BoxConstraints(minWidth: sideWidth, maxWidth: sideWidth, maxHeight: size.height));
      positionChild(panel, Offset(size.width - sideWidth, (size.height - p.height) / 2));
      layoutChild(photo, BoxConstraints.tight(Size(size.width - sideWidth, size.height)));
      positionChild(photo, Offset.zero);
      return;
    }
    final p = layoutChild(panel, BoxConstraints(minWidth: size.width, maxWidth: size.width, maxHeight: math.max(0, size.height - minPhoto)));
    positionChild(panel, Offset(0, size.height - p.height));
    layoutChild(photo, BoxConstraints.tight(Size(size.width, math.max(0, size.height - p.height + overlap))));
    positionChild(photo, Offset.zero);
  }

  @override
  bool shouldRelayout(_CompletionLayout old) => old.minPhoto != minPhoto || old.side != side;
}

/// Compact pill over the finished picture: frosted glass, or solid accent
/// for the one primary action.
class _OverlayPill extends StatelessWidget {
  const _OverlayPill({required this.icon, required this.label, required this.onTap, this.primary = false, this.small = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  /// Over the picture's corner: a smaller pill.
  final bool small;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? context.onAccent : Colors.white;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: small ? 13 : 17, color: fg),
        SizedBox(width: small ? 5 : 7),
        Text(label, style: TextStyle(color: fg, fontWeight: small ? FontWeight.w600 : FontWeight.w700, fontSize: small ? TypeSize.caption : TypeSize.body)),
      ],
    );
    final padding = small ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6) : const EdgeInsets.symmetric(horizontal: 16, vertical: 10);
    return Pressable(
      onTap: onTap,
      child: primary
          ? Container(
              padding: padding,
              decoration: BoxDecoration(color: context.accentFill, borderRadius: BorderRadius.circular(Radii.pill)),
              child: row,
            )
          : Glass(dark: true, radius: Radii.pill, padding: padding, opacity: 0.45, child: row),
    );
  }
}

class _RewardStat extends StatelessWidget {
  const _RewardStat({this.icon, required this.label, required this.value});

  /// Drawn before the value (the coin, the XP mark); counts go without one.
  final Widget? icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[icon!, const SizedBox(width: 4)],
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: TypeSize.headline)),
          ],
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: TypeSize.micro, fontWeight: FontWeight.w600, color: c.textTertiary)),
      ],
    );
  }
}

/// One extra result under the numbers (a level reached, a quest ready): an
/// icon and a line; tinted for news, outlined with a chevron when it opens something.
class _ResultLine extends StatelessWidget {
  const _ResultLine({super.key, required this.icon, required this.text, this.onTap, this.tinted = false});
  final IconData icon;
  final String text;
  final VoidCallback? onTap;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final row = Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: tinted ? c.accentTint : c.canvas,
        borderRadius: BorderRadius.circular(Radii.md),
        border: tinted ? null : Border.all(color: c.stroke),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: context.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: TypeSize.footnote, color: tinted ? context.accent : c.textPrimary)),
          ),
          if (onTap != null) Icon(AppIcons.chevronRight, size: 15, color: c.textTertiary),
        ],
      ),
    );
    return onTap == null ? row : Pressable(onTap: onTap, scale: 0.99, child: row);
  }
}

/// The board on screen as the shared game sees it ([CoopBridge]): the controller's board, and the
/// others' changes put on it without counting a move.
class _SharedBoard implements CoopBoardTarget {
  _SharedBoard(this._screen);
  final _GameScreenState _screen;

  @override
  List<int> get layout => _screen.ref.read(gameControllerProvider(_screen._args!)).board.slots;

  @override
  void showShared(CoopBoardUpdate update) => _screen._showShared(update);
}
