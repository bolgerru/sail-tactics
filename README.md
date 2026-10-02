# Sail Tactics

**[Play it in your browser →](https://bolgerru.github.io/sail-tactics/)** (works on phone and desktop)

A one-tap upwind sailing race against AI boats. Every tap is a tack, so the whole game is about when to tack: time the start, sail into the gusts, stay out of other boats' wind shadow, and avoid breaking the racing rules. Break a rule and you're disqualified.

## How to play

- Tap (or click) to start. The countdown runs 3, 2, 1. Tap before the gun and you get a **black flag**.
- After the start, each tap tacks your boat onto the other side of the wind.
- Get to the windward line first and win a medal.

## What's simulated

- **Wind**: a base wind speed plus moving **gusts** that make boats go faster in proportion to their strength. You can see them on the water.
- **Wind shadow**: every boat blankets the air downwind of it, so you slow down if you're sitting in someone's dirty air.
- **Racing Rules of Sailing**, enforced live:
  - Rule 10: port gives way to starboard
  - Rule 13: don't tack too close to someone else
  - Rule 20: room to tack at an obstruction, including chains of boats passing the hail along
- **AI opponents** at six difficulty levels (Beginner to Master). They pick their tacks and follow the rules, including forced tacks under Rule 20.
- Wakes, ripples, sound effects, and confetti when you win.

## Settings

The settings button lets you set the wind speed, the number of boats (2–10), difficulty and sound. Hold it for a second to open a hidden advanced menu with custom values, chaos mode and god mode.

## Tech

**Web version:** vanilla JavaScript and the HTML5 Canvas 2D API, in a single `index.html`. No frameworks, no build step and no assets. All the physics, the rules engine and the AI run in the browser. To run it locally, just open `index.html`.

**iOS app:** a Godot 4.7 port of the same game lives in [`godot/`](godot/) (GDScript, custom 2D drawing, procedurally generated sound). See [`godot/IOS_RELEASE.md`](godot/IOS_RELEASE.md) for how it is built and shipped to the App Store.

---

Built by [Russell Bolger](https://bolgerru.github.io). See also [RaceFlow](https://teamracing.xyz), the team-racing event platform I run.
