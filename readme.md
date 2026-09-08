# Limelight

Stage Manager's focus model without the strip, the animations or the layout
shifts. The app you are working in stays lit along with anything grouped with
it; everything else fades.

## How it works

One black click-through scrim per screen sits at the normal window level.
Bright means "above the scrim". The lit set is the **stage** — the app you are
working in — plus its **group**. On every focus change Limelight raises the lit
windows that are out of position, stage last so clicking an app still brings it
fully forward, then slides each screen's scrim just below the lowest lit window
on that display.

Groups are symmetric and remembered. Group Zed with Ghostty and either one
brings the other; switch to an app in no group and it is lit alone.

```
group: Zed + Ghostty

focus Zed     -> Zed, Ghostty lit
focus Ghostty -> Ghostty, Zed lit
focus Linear  -> Linear only
```

- **App-level, current Space only.** Minimised and off-Space windows untouched.
- Menu bar and Dock are left alone; wallpaper dims.

Two platform hazards shape the implementation. Raising is IPC that the target
app services on its own runloop, so the z-order read back in the same tick is
pre-commit -- hence the settle loop in `Engine.startSettle`. And raising
perturbs the very state the AX observers watch, so raises are fenced
(`fenceUntil`) or they feed themselves into a flicker loop.

## Install

Limelight is distributed as source and built locally. There is no download,
deliberately: a downloaded app is quarantined, and Gatekeeper rejects anything
not signed with a paid Apple Developer ID — it would put a "the developer cannot
be verified" dialog in front of you, and then Limelight would immediately ask
for Accessibility on top of that. An app you build yourself is never
quarantined, so this route has no such dialog at all.

Requires macOS 14 or later and the Swift toolchain. Full Xcode is **not**
needed — the Command Line Tools are enough:

```
xcode-select --install
```

Then:

```
git clone git@github.com:nilobarp/limelight.git && cd limelight
make cert        # once — creates a local signing identity
make install     # build, bundle, sign, copy to /Applications
open /Applications/Limelight.app
```

`make cert` creates a self-signed **Limelight Dev** certificate in your login
keychain and trusts it for code signing. It is worth running before the first
install. macOS pins an app's Accessibility grant to its code signature, and an
ad-hoc signature changes on every build — so without a stable identity you
re-grant the permission after every `make install`, while System Settings still
shows the toggle as enabled. The certificate never leaves your machine, and
`make cert` is safe to re-run: it does nothing if the identity already exists.

If it fails — a managed keychain policy, say — `make cert-help` prints the
equivalent steps for Keychain Access, and the build falls back to ad-hoc
signing regardless.

`make uninstall` removes the app and prints how to clear its settings and
revoke the permission.

Not on the Mac App Store, and it cannot be: the sandbox forbids controlling
other applications through the Accessibility API and forbids event taps, both
of which are the entire mechanism.

### Accessibility is optional

Dimming behind the app you are working in needs **no** permission at all -- the
window server raises the frontmost app on activation and Limelight just slides
the scrim underneath it. If one lit app at a time is all you want, you never
have to visit System Settings.

Accessibility is required only to raise a **group's** other members above the
scrim, and Limelight asks for it the first time you group something. Two lesser
things also depend on it: auto-suspend in native fullscreen, and instant
reaction to windows opening or minimising (the 1s poll covers that otherwise,
just with lag). Shift-click grouping needs it too, since the event tap cannot
be created without it.

While the permission is missing, groups are ignored outright rather than
applied half-way -- anchoring the scrim to an unraised companion would leave
every window above it undimmed, which is worse than no grouping at all.

## Keys

| Gesture            | Action                                      |
| ------------------ | ------------------------------------------- |
| `⇧`-click a window | add it to the stage's group, or remove it   |
| `⌥⌘P`              | break up the stage's group, leaving it solo |
| `⌥⌘D`              | toggle dimming                              |

Shift-click never fires on the app you are working in -- that is the stage, and
shift-click there means extend-selection. Clicking elsewhere is swallowed, so
grouping a window does not cost you your focus. Turn it off from the menu.

Every one of these shows a brief HUD naming what changed. Grouping has no
visible effect until you switch away, so without that confirmation there is no
way to tell the gesture registered at all.

## Diagnostics

```
defaults write dev.nilobarp.limelight verbose -bool true
/Applications/Limelight.app/Contents/MacOS/Limelight
```

Logs each reconcile to stderr: what was raised, and which window is keeping the
band from settling. A healthy app switch prints one `raised N window(s)`
followed by `settled`. Repeated `raised` / `unsettled` pairs while nothing moves
means something is fighting the z-order, and the log names the window.

## Tests

```
make test
```

`LimelightCore` holds everything; the executable target is six lines of
bootstrap, because an executable target's symbols cannot be imported by tests.

The band algebra lives in `Band.swift` as pure functions over plain values — a
list of windows, the screen frames, the lit set, the scrim ids. No AppKit, no
globals, no window server. That is deliberate: every visual bug this app has
had was in those three functions, so they are the part worth being able to
exercise. `Engine` keeps the timers, Accessibility calls and observers and
calls into it.

Covered: the band algebra, the group model, `Settings` decoding, and screen
mapping. Not covered, and not sensibly coverable in-process: raising windows
over Accessibility, the event tap, scrim ordering in the window server, TCC.
Those need the diagnostics above and a real screen.

The tests encode specific regressions rather than restating the
implementation — a global scrim anchor on a two-monitor setup, raising every
window of a multi-window app instead of only the stranded ones, and a stored
settings blob missing a key it was written before. Each was a real bug.

## Known limits

- **Capture detection is a watchlist, not a detector.** macOS has no public API
  to ask "is my screen being recorded". Limelight suspends when an app from
  `captureWatchlist` has a window on screen. Tune it:
  `defaults read dev.nilobarp.limelight settings`. Use `⌥⌘D` before presenting if in doubt.
- **Focus-stealing apps** get three strikes, then Limelight stops raising them
  and they dim like anything else. The menu shows them with a Retry.
- Native fullscreen suspends dimming — there's nothing to dim in its own Space.
- Window targeting uses `_AXUIElementGetWindow`, a private HIServices symbol,
  resolved at runtime. If it ever disappears Limelight falls back to raising whole
  apps, which works but reorders more windows than necessary.

## Licence

MIT — see [LICENSE](LICENSE).
