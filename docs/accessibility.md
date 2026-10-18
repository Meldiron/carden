# Accessibility

Settings > Accessibility (owner, 2026-10-16) holds four options. All are off until the player turns
them on there, so the usual game looks and moves exactly as before. The iPhone's own accessibility
switches (Reduce Motion, Increase Contrast, Differentiate Without Color) do not turn them on; Flutter's
own widgets still follow those switches as before. Apple accepts an in-app setting for each of these
App Store Accessibility Nutrition Labels.

| Option | Apple label | What changes |
| --- | --- | --- |
| Text size: Default / Large / Largest | Larger Text (at least 200%) | Default keeps the iPhone's text size within the app's usual range (0.9 to 1.35). Large is 150%, Largest 200%, whatever the iPhone is set to. Bars keep their own cap (`ChromeText`), as iOS tab and navigation bars do. |
| Reduce motion | Reduced Motion | No spinning, zooming, sliding or looping: fades instead. See "Motion" below. |
| Increase contrast | Sufficient Contrast | The Contrast palettes (`AppColors.lightContrast`, `darkContrast`, `darkElevatedContrast`): every text colour at 4.5:1 or better, control outlines at 3:1; glass becomes solid with an outline; darker scrims and overlays on photos; deeper gold, teal and amber for stars, coins, tickets and hints in light mode; coins and hints become silhouettes on filled buttons. |
| Differentiate without colour | Differentiate Without Color Alone | A symbol, outline or text wherever colour alone shows a state. See "Symbols" below. Switches show their I/O labels. |

Dark Interface is supported as before (Settings > Theme).

## Code

- `lib/state/settings.dart`: `Accessibility` and `TextSize`, stored as the JSON entry `accessibility` on the
  device (`SettingsNotifier.setAccessibility`).
- `lib/app.dart`: applies the text size (`MediaQuery.textScaler`), picks the Contrast themes, and puts `A11y`
  above the Navigator so pages, sheets and alerts all see the options.
- `lib/core/a11y.dart`: `A11y.reduceMotionOf`, `increaseContrastOf`, `symbolsOf`, and `A11y.motion(context, d)`
  (zero duration when motion is reduced). App code reads the options only from here.
- Colours: `context.colors` (`highContrast`, `controlStroke`, `track`, `elevated`), `context.accent`,
  `context.accentFill` and `context.star` in `lib/core/theme/tokens.dart`; `Brand.scrim(contrast:)` for text on
  photos. Use them instead of fixed `Brand.*` colours on light surfaces.
- `test/accessibility_test.dart` checks the defaults, the stored options and every Contrast text and outline ratio.
- `test/largest_text_test.dart` checks, at Largest on the SE frame, that the pack card's price and progress row, the
  chips over photos (`PhotoChip`: 24 pt, taller when the text needs it) and Home's greeting (wraps instead of
  truncating) show their words whole.

## Motion

Reduce motion changes, by place:
- Shared widgets: buttons dim without shrinking (`Pressable`), loading skeletons stand still, the segmented
  control's thumb jumps without spring, stretch or lift, alerts, action sheets and toasts fade without zoom or
  slide, wide-window panels fade, the Store, Wheel and Account sheets fade in (a full-height `GlassSheetRoute`)
  instead of the sheet sliding up while the page behind shrinks, content sheets fade in and out instead of sliding
  (a drag still moves them with the finger; one let go before the close point jumps back), the tab pill and glass
  bars snap, shelves jump.
- Board: cards and Peek jump to their places (the lock flash still marks a change), the picture before the deal
  fades into the dealt cards, no lock pop, a steady hint
  outline instead of the pulse, no lift scale, zoom buttons, map and Locate move the view at once (`BoardZoom.reduceMotion`).
- Game screen: no confetti, "×2 DOUBLE LOCK" fades without pop and drift, completion stars fade in, panels fade
  without sliding, the finished picture does not zoom.
- Lucky Wheel: the wheel does not spin; it turns to the prize at once and the prize fades in. The jackpot glow
  fades once without growing; no confetti.
- Elsewhere: pack covers do not drift or zoom (parallax, stretch), onboarding pages and texts change without
  sliding, programmatic scrolls jump, the daily gift mark fades instead of popping and a claimed gift plays no
  confetti.
- Kept: spinners (iOS keeps them too), the player's own drags, pinches and scrolls, fades and colour changes.

## Symbols

Differentiate without colour adds:
- Total Completion legend: a check and a star instead of two coloured dots; a gap where the starred part of the
  bar ends.
- Achievements: unclaimed tiers are rings.
- Difficulty screen: a check on the selected mode and board size; unlit ladder steps are outlines.
- Store: a rosette on the best deal's price.
- Daily months: today's disc gets a white ring. Pack header: a star after the bar when it counts stars.
- Giant boards: the map button fills in while the map is on. Streak card: a dot in the next gift's ring.
- Board: a no-entry sign on a blocked drop target, the hint glyph on the hint's target.
- Web top tabs: the selected one is underlined. Library filters: a check on the chosen chip. An event pack that
  is over says "Ended".

Already without colour alone (no change needed): stars (filled and outline glyphs), quests (text and Claim),
the wheel (glyph and amount per slice), pack badges (check and star), chips (words), toasts (icon and text).

## QA

The design QA harness (`integration_test/design_qa/harness_main.dart`) takes the options as a scene pref:
`"prefs": {"accessibility": "{\"textSize\":\"largest\",\"reduceMotion\":true}"}`. Check new screens at Largest on
the SE frame (no layout errors, no clipped text) and with Increase contrast in light and dark mode.
