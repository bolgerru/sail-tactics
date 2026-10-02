# Sail Tactics: iOS release checklist

TestFlight and the App Store work without a Mac, exactly like First Not Last: GitHub builds the
game on a hosted Mac, signs it and uploads it. This reuses First Not Last's signing certificate
and App Store Connect API key, so setup is short.

## Already done in the project

- **The game**: a Godot 4.7.2 project in `godot/`, tested headless (`godot/tests/`).
- **iOS export preset** in `godot/tools/ios/ios_preset.cfg`: bundle ID `com.russell.sailtactics`,
  version 1.0.0, iPhone only, portrait. `make_ios_preset.py` merges it in at build time.
- **App icon** (`godot/icon.png`, no alpha) and **launch screen** (boat on ocean blue).
- **Listing text** in `godot/store/APP_STORE_TEXT.md` and **screenshots** (1320x2868) in
  `godot/store/iphone/`, uploaded by the App Store workflow.
- **Privacy policy** `privacy.html` and **support page** `support.html` (served by GitHub Pages).
- **Four workflows** (`.github/workflows/`), all run by hand from the Actions tab:

  | Workflow | What it does |
  | --- | --- |
  | iOS register App ID | creates the App ID `com.russell.sailtactics` in your developer account |
  | iOS TestFlight | builds, signs (the profile is made automatically) and uploads to TestFlight |
  | TestFlight public link | fills in Test Information, makes a public group, sends the build to Beta App Review and prints the join link |
  | App Store | `status` / `prepare` / `submit` / `release`: fills in the listing, age rating and screenshots, and sends the version to App Review |

## What only you can do

### One-time setup (about 10 minutes)

1. **Push to GitHub.** This also publishes the web version, `privacy.html` and `support.html`.

   ```bash
   git push
   ```

2. **Copy the signing secrets** from the files First Not Last already uses. In PowerShell, from the
   repo folder:

   ```powershell
   cd "C:\Tack Tack\sail-tactics"
   .\godot\tools\ios\set_secrets.ps1
   ```

   It lists the API key files in `C:\Users\russe\ios-signing` and asks for two values. Type the real
   values, not placeholders (PowerShell rejects `<` and `>`):
   - **Key ID**: the Key ID of your App Store Connect API key, the same one as First Not Last's
     `ASC_KEY_ID` secret. Check which keys are active at
     [App Store Connect > Users and Access > Integrations > App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api).
   - **Issuer ID**: the UUID shown above the keys table on that same page.

   It pipes your certificate, its password and the API key straight into this repo's GitHub secrets.
   Nothing is printed.

3. **GitHub > Actions > "iOS register App ID" > Run workflow.** About 20 seconds. If it fails with a
   403, the API key's role is too low: either give it **Admin** in App Store Connect, or create the
   App ID by hand (developer.apple.com > Certificates, IDs & Profiles > Identifiers > + > App IDs >
   App, Explicit, `com.russell.sailtactics`, no capabilities).

4. **[App Store Connect](https://appstoreconnect.apple.com) > Apps > + > New App**: iOS, name
   "Sail Tactics" (it must be free on the store; if taken, use a variant), your language, Bundle ID
   `com.russell.sailtactics` (pick it from the list), SKU `sailtactics`, Full Access.

### First TestFlight build

5. **Actions > "iOS TestFlight" > Run workflow.** About 5 minutes (the first run also downloads
   Godot; later runs reuse it). A failed run explains itself in the log, and its logs are kept as a
   download.
6. When App Store Connect emails that the build has processed (5-30 minutes): open the app >
   **TestFlight** > Internal Testing > **+** to make a group > add yourself. On your iPhone, install
   Apple's **TestFlight** app with the same Apple ID and accept the invite. Play it.
7. Optional, a public link anyone can use: **Actions > "TestFlight public link"** > Run workflow,
   with your phone number (country code, e.g. `+353...`) in the box. Rerun it after Apple approves
   the beta review (usually under a day) to get the `testflight.apple.com/join/...` link.

### Releasing to the App Store

8. In App Store Connect, the things Apple's API can't do:
   - **App Privacy**: Get Started > **Data Not Collected** > Publish.
   - **Pricing and Availability**: Free (or choose a price; paid apps also need the Paid Apps
     agreement and bank details).
   - **App Review Information**: your contact phone (Sign-in required stays **off**).
9. **Actions > "App Store"** > command `prepare`, `build_number` = the build you tested, type
   `confirm`. It fills in the listing, categories, age rating (all "None"), screenshots and review
   notes. Then run `status` and check that nothing says "(not set)".
10. When you're happy, run `submit` (same build number, type `confirm`). That sends it to App
    Review. `release` does cancel + prepare + submit in one.

## Every later build

Run **iOS TestFlight** again. The build number is the run number, so it rises on its own. Type a new
*version* (e.g. `1.0.1`) when you start a new release.

## Things to know

- **Cost:** this repo is public, so GitHub Actions minutes are free (they are not on your private
  First Not Last repo, where Mac minutes count ten times).
- **Hidden advanced menu.** Holding the Settings button for one second opens custom values, Chaos Mode
  and God Mode. Apple's guideline 2.3.1 bans hidden features, so the Review Notes disclose it. Setting
  `ENABLE_ADVANCED_MENU := false` in `godot/scripts/hud.gd` removes it entirely, which is the safest choice.
- **Yearly renewal:** the distribution certificate expires after a year. Renew it for First Not Last
  as usual, then rerun `set_secrets.ps1`.
- **iPhone only.** It still runs on iPad in compatibility mode. For a native iPad app, set
  `application/targeted_device_family=2` in `ios_preset.cfg` and add iPad screenshots.
- **Not tested on a Mac.** The workflows were adapted from First Not Last's, which ships, but this
  copy has not run yet. If the first run fails, send me the log.

## Working on the game

- Open `godot/project.godot` in Godot 4.7.2 and press F5.
- `godot --headless --path godot -s res://tests/sim_test.gd` plays 28 full races.
- `godot --headless --path godot -s res://tests/late_start_test.gd` checks late starts.
- `godot --path godot -s res://tests/store_shots.gd -- <dir>` re-renders the App Store screenshots.
- `python godot/tools/make_icon.py` and `make_launch.py` regenerate the icon and launch logo (Pillow).
