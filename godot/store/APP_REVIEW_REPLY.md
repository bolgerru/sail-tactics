# Reply to App Review (Guideline 2.1(a), unresponsive on iPad)

Rejection of 1.0.0 (3), October 14, 2026, on an iPad Air 11-inch (M3) running iPadOS 27.0: "app
launched to unresponsive screen".

**Most likely cause** (not reproduced on an iPad; it matches the symptom and the build has no other
launch problem). Godot turns touches into the clicks that the game's buttons and taps listen for, and it
follows one finger at a time. If iOS never reports that finger's release (this can happen when a
touch is cancelled, for example by a system gesture or by taps while the app is still launching),
Godot ignores every touch after it. The settings dialog still worked, but the game ignored all
taps, so it sat on "Tap to Start Sequence". This is a known Godot iOS bug
([godotengine/godot#102393](https://github.com/godotengine/godot/issues/102393)), still open.

**Fix.** `scripts/touch_guard.gd` detects a touch that produced no click, frees the stuck finger and
replays the touch. `tests/touch_test.gd` reproduces the bug (4 failures without the guard) and
passes with it. Upload a new build (any build number above 3), then select it in App Store
Connect for version 1.0.0 before replying.

Paste this into the reply box in App Store Connect (App Review > the message > Reply):

```
Hello,

Thank you for testing Tack Tack on iPad and for the details.

We found the cause: in some cases iOS did not report a finger being lifted (for example after taps during launch or a system gesture), and the game engine then ignored all later touches. This made the app look frozen after launch.

Build 1.0.0 (NEW_BUILD_NUMBER) fixes this. The app now recovers from a missing touch release, so every tap is registered. We have added an automated test for this case.

To use the app: on launch, tap "Save & Restart" in the Settings dialog. Tap once to start the countdown, tap again after "GO!" to start sailing, then tap to tack.

Best regards,
Russell Bolger
```

Replace `NEW_BUILD_NUMBER` with the uploaded build's number.

## Before resubmitting

1. Install the new build from TestFlight (delete the old app first).
2. Launch it and tap the screen several times with two or three fingers while it is still on the
   blue launch screen. Then tap Save & Restart and play a race. Every tap should respond.
3. If you can borrow an iPad, repeat it there: the app runs in iPhone mode on iPad, which is how
   App Review tested it.
