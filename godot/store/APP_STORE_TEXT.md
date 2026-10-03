# App Store Connect text

Copy each block into the field named above it. Apple's character limits are in brackets.
The blocks are sent to App Store Connect by the **TestFlight public link** and **App Store**
workflows (`godot/tools/ios/testflight_public.py`, `app_store.py`), so edit them here and rerun.

## TestFlight: Test Information

**Beta App Description** [4,000]

```
Tack Tack is a one-tap upwind sailing race against AI boats. Every tap is a tack, so the whole game is about when to tack.

- Time the start: tap before the gun and you get the black flag.
- Sail into the gusts and stay out of other boats' wind shadow.
- Race by the rules: port gives way to starboard (Rule 10), don't tack too close (Rule 13), and give room to tack at an obstruction (Rule 20). Break a rule and you're disqualified.
- Six AI levels from Beginner to Master, 2 to 10 boats, adjustable wind speed.

Please tell us if a race ever feels unfair, if the rules fire when they shouldn't, or if the controls don't respond.
```

- **Feedback Email:** `russellbolger06@gmail.com`
- **Privacy Policy URL:** `https://bolgerru.github.io/sail-tactics/privacy.html`

### Beta App Review Information

- **Contact:** your own name, phone number and email.
- **Sign-in required:** no. The app has no accounts and no network access.

**Review Notes** [4,000]

```
Tack Tack is a single-player sailing game. There is no account, no sign-in, no network access, no user-generated content and no in-app purchases. A screen recording from a physical iPhone (launch to finish) is attached in the App Review reply.

1. PURPOSE AND AUDIENCE
A one-tap upwind sailing race against AI boats for casual players and sailing fans. Each tap tacks the boat, so the game is about timing: reading wind shifts and gusts, staying out of other boats' wind shadow, and following the racing rules (port gives way to starboard, don't tack too close, give room to tack). Break a rule and you are disqualified. It teaches basic racing tactics in a short, playful race.

2. HOW TO USE IT (no login or sample files needed)
- Launch: the Settings dialog opens first. Tap "Save & Restart" (or "Cancel") to begin.
- Tap anywhere to start the 3-2-1 countdown. Tapping during the countdown gives a black flag (a deliberate game rule); tap again to restart.
- Tap after "GO!" to start sailing, then tap to tack. Reach the red finish line first to win a medal. Tap after the result to restart.
- Settings (top right): wind speed, number of boats (2-10), difficulty (Beginner to Master), sound.
- Disclosure: holding the Settings button for one second opens an advanced menu (custom speed, boat count and size, Chaos Mode, God Mode). These are optional tuning options; they do not unlock any content.

3. EXTERNAL SERVICES
None. The app makes no network requests and uses no third-party SDKs, data providers, authentication, payment or AI services. All physics, rules and AI run on the device. Sound effects are generated in code. Built with the Godot Engine (MIT licence).

4. REGIONAL DIFFERENCES
None. The app works identically in every region. The interface is in English.

5. REGULATED INDUSTRY / THIRD-PARTY MATERIAL
Not applicable. The app has no regulated content and no protected third-party material; the icon, artwork and sounds are original or generated in code.
```

## TestFlight: each build, What to Test [4,000]

```
Play a few races. Check that:
- the countdown, the start and tacking all respond to taps (including starting a second or two late);
- the rules (port/starboard, tacking too close, room at an obstruction) feel fair;
- the Settings dialog opens, changes apply, and Cancel closes it;
- the game looks right near the notch / Dynamic Island and the home bar.
```

## App Store listing

**Subtitle** [30]

```
One-tap upwind sailing race
```

**Promotional Text** [170]

```
Time your tacks, catch the gusts, stay out of dirty air, and don't break the racing rules.
```

**Description** [4,000]

```
Tack Tack is a one-tap upwind sailing race. Every tap is a tack, so the whole game is about when to tack.

TIME THE START
The countdown runs 3, 2, 1. Tap before the gun and you get the black flag. Tap at GO and you're racing.

READ THE WIND
Gusts roll down the course and make boats faster. Sail into them. Every boat blankets the air behind it, so stay out of other boats' wind shadow. The wind shifts, and so should you.

RACE BY THE RULES
The racing rules are enforced live:
- Rule 10: port gives way to starboard
- Rule 13: don't tack too close to another boat
- Rule 20: give room to tack at an obstruction, including chains of boats passing the hail along
Break a rule and you're disqualified.

SIX DIFFICULTY LEVELS
From Beginner to Master. The AI picks its tacks, reads the wind shifts and follows the rules, including forced tacks under Rule 20.

MAKE IT YOURS
Choose 2 to 10 boats, adjust the wind speed, and turn the sound on or off.

Simple to learn, hard to master. Built by a sailor.
```

**Keywords** [100, comma-separated]

```
sailing,sail,boat,regatta,yacht,race,tactics,wind,tack,racing,sailboat
```
