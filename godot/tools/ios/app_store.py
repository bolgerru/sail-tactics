#!/usr/bin/env python3
"""The App Store release of Sail Tactics, through the App Store Connect API.

    python godot/tools/ios/app_store.py --key-id … --issuer-id … --key-file AuthKey.p8 status
    python godot/tools/ios/app_store.py --key-id … --issuer-id … --key-file AuthKey.p8 prepare --build 19

status only reads: the app's info and categories, age rating, each App Store version with
its build, listing, screenshots and review details.

cancel withdraws a submission Apple is holding, which frees the version to be edited and sent
again; it gives up the place in the queue that submission had earned.

release is cancel, prepare and submit in one: it puts a build in front of Apple in place of
whatever it is already holding.

prepare fills in the version being prepared, and is safe to rerun: the listing from
APP_STORE_TEXT.md, the URLs and copyright, categories, the age rating ("none" throughout),
the content rights declaration, release as soon as approved, build `--build` (the version takes its
number), the screenshots in godot/store/iphone (replacing any there),
and the App Review contact and notes. It submits nothing.

Left for App Store Connect itself: App Privacy (not in Apple's API), and in App Review
Information the contact phone.
"""

import argparse
import hashlib
import pathlib
import ssl
import sys
import time
import urllib.request

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import testflight_public as asc  # noqa: E402  (API calls, token, app and build lookup)
from app_profile import jwt_es256  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[2]  # godot/
SUPPORT_URL = "https://bolgerru.github.io/sail-tactics/support.html"
COPYRIGHT = "2026 Russell Bolger"
CATEGORIES = {
    "primaryCategory": "GAMES",
    "primarySubcategoryOne": "GAMES_RACING",
    "primarySubcategoryTwo": "GAMES_SPORTS",
}
## By App Store display type. The 6.9" iPhone shots (1320x2868) go in the 6.7" set, which takes both
## sizes. The app is iPhone-only, so there is no iPad set.
SCREENSHOTS = {
    "APP_IPHONE_67": ROOT / "store" / "iphone",
}
## Age rating questions answered with a level; the rest are yes/no. Every one is answered
## "none" or "no": a single-player game with no user content, chat or purchases.
AGE_RATING_LEVELS = {
    "alcoholTobaccoOrDrugUseOrReferences",
    "contests",
    "gamblingSimulated",
    "gunsOrOtherWeapons",
    "horrorOrFearThemes",
    "matureOrSuggestiveThemes",
    "medicalOrTreatmentInformation",
    "profanityOrCrudeHumor",
    "sexualContentGraphicAndNudity",
    "sexualContentOrNudity",
    "violenceCartoonOrFantasy",
    "violenceRealistic",
    "violenceRealisticProlongedGraphicOrSadistic",
}
## Not questions about the app's content: a kids' age band, a page of the developer's own,
## and Apple's overrides stay unset.
AGE_RATING_SKIP = {
    "kidsAgeBand",
    "developerAgeRatingInfoUrl",
    "ageRatingOverride",
    "ageRatingOverrideV2",
    "koreaAgeRatingOverride",
    "gracRatingClassificationNumber",
}
## States in which a version's metadata can still be edited.
EDITABLE = ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED")


def attributes(item):
    return (item or {}).get("attributes") or {}


def show(label, value):
    missing = value is None or value == "" or value == [] or value == {}
    print("    %-24s %s" % (label, "(not set)" if missing else value))


def get_or_none(path):
    """The resource at `path`, or None where Apple has none yet (404)."""
    try:
        return asc.api("GET", path).get("data")
    except asc.ApiError as error:
        if error.code == 404:
            return None
        raise


def patch(kind, item_id, attrs=None, relationships=None):
    data = {"type": kind, "id": item_id}
    if attrs:
        data["attributes"] = attrs
    if relationships:
        data["relationships"] = relationships
    return asc.api("PATCH", "/%s/%s" % (kind, item_id), {"data": data})


def text_summary(text):
    text = (text or "").strip()
    if not text:
        return None
    first = text.splitlines()[0]
    return "%d chars: %s" % (len(text), first if len(first) <= 60 else first[:57] + "...")


# --- status -----------------------------------------------------------------------------

def show_app_info(app_id):
    for info in asc.api_list("/apps/%s/appInfos" % app_id):
        state = attributes(info).get("appStoreState") or attributes(info).get("state")
        print("\nApp info (%s)" % state)
        for label, rel in [
            ("Primary category", "primaryCategory"),
            ("  subcategory", "primarySubcategoryOne"),
            ("  subcategory", "primarySubcategoryTwo"),
            ("Secondary category", "secondaryCategory"),
        ]:
            category = get_or_none("/appInfos/%s/%s" % (info["id"], rel))
            show(label, category["id"] if category else None)
        for loc in asc.api_list("/appInfos/%s/appInfoLocalizations" % info["id"]):
            a = attributes(loc)
            print("  %s" % a.get("locale"))
            show("Name", a.get("name"))
            show("Subtitle", a.get("subtitle"))
            show("Privacy policy URL", a.get("privacyPolicyUrl"))
        rating = get_or_none("/appInfos/%s/ageRatingDeclaration" % info["id"])
        answers = attributes(rating)
        unanswered = sorted(key for key, value in answers.items() if value is None)
        show("Age rating answers", "%d answered, %d not" % (len(answers) - len(unanswered), len(unanswered))
             if answers else None)
        if unanswered:
            show("  not answered", ", ".join(unanswered))


def show_version(version):
    a = attributes(version)
    print("\nApp Store version %s (%s)" % (a.get("versionString"), a.get("appStoreState")))
    show("Copyright", a.get("copyright"))
    show("Release", a.get("releaseType"))
    build = get_or_none("/appStoreVersions/%s/build" % version["id"])
    show("Build", attributes(build).get("version") if build else None)
    for loc in asc.api_list("/appStoreVersions/%s/appStoreVersionLocalizations" % version["id"]):
        la = attributes(loc)
        print("  %s" % la.get("locale"))
        show("Description", text_summary(la.get("description")))
        show("Keywords", la.get("keywords"))
        show("Promotional text", text_summary(la.get("promotionalText")))
        show("What's new", text_summary(la.get("whatsNew")))
        show("Support URL", la.get("supportUrl"))
        show("Marketing URL", la.get("marketingUrl"))
        sets = asc.api_list("/appStoreVersionLocalizations/%s/appScreenshotSets" % loc["id"])
        if not sets:
            show("Screenshots", None)
        for shot_set in sets:
            shots = asc.api_list("/appScreenshotSets/%s/appScreenshots" % shot_set["id"])
            show("Screenshots", "%s: %d" % (attributes(shot_set).get("screenshotDisplayType"), len(shots)))
    review = get_or_none("/appStoreVersions/%s/appStoreReviewDetail" % version["id"])
    ra = attributes(review)
    print("  App Review information")
    if not review:
        show("Details", None)
        return
    show("Contact", " ".join(filter(None, [ra.get("contactFirstName"), ra.get("contactLastName")])) or None)
    show("Contact email", ra.get("contactEmail"))
    show("Contact phone", "set" if ra.get("contactPhone") else None)
    show("Sign-in required", ra.get("demoAccountRequired"))
    show("Demo account", ra.get("demoAccountName"))
    show("Demo password", "set" if ra.get("demoAccountPassword") else None)
    show("Notes", text_summary(ra.get("notes")))


def status():
    app = asc.find_app()
    a = attributes(app)
    print("App: %s (%s), primary locale %s" % (a.get("name"), a.get("bundleId"), a.get("primaryLocale")))
    show("Content rights", a.get("contentRightsDeclaration"))
    show_app_info(app["id"])
    versions = asc.api_list("/apps/%s/appStoreVersions?filter[platform]=IOS" % app["id"])
    if not versions:
        print("\nNo App Store version yet.")
    for version in versions:
        show_version(version)
    prices = get_or_none("/apps/%s/appPriceSchedule" % app["id"])
    print("\nPricing")
    # Apple validates pricing through a newer API than this reads: it refused a submission for
    # "missing required pricing" while this said the schedule was set.
    show("Price schedule (v1)", "set" if prices else None)
    print("    Apple checks pricing and availability separately; confirm both in App Store Connect.")


# --- prepare ----------------------------------------------------------------------------

def editable_app_info(app_id):
    for info in asc.api_list("/apps/%s/appInfos" % app_id):
        state = attributes(info).get("state") or attributes(info).get("appStoreState")
        if state not in ("READY_FOR_DISTRIBUTION", "READY_FOR_SALE"):
            return info
    asc.fail("no editable app info: make a new App Store version in App Store Connect first")


def editable_version(app_id):
    for version in asc.api_list("/apps/%s/appStoreVersions?filter[platform]=IOS" % app_id):
        if attributes(version).get("appStoreState") in EDITABLE:
            return version
    asc.fail("no App Store version being prepared: make one in App Store Connect first")


def set_app_info(info, locale):
    patch("appInfos", info["id"], relationships={
        rel: {"data": {"type": "appCategories", "id": category}} for rel, category in CATEGORIES.items()})
    for loc in asc.api_list("/appInfos/%s/appInfoLocalizations" % info["id"]):
        if attributes(loc).get("locale") == locale:
            patch("appInfoLocalizations", loc["id"], {
                "subtitle": asc.text_block("**Subtitle**"),
                "privacyPolicyUrl": asc.PRIVACY_URL,
            })
    asc.note("App information: Games (Racing, Sports), subtitle and privacy policy URL.")


def answer_age_rating(info):
    rating = get_or_none("/appInfos/%s/ageRatingDeclaration" % info["id"])
    if rating is None:
        asc.fail("no age rating declaration on the app info")
    answers = {}
    for key, value in attributes(rating).items():
        if value is None and key not in AGE_RATING_SKIP:
            answers[key] = "NONE" if key in AGE_RATING_LEVELS else False
    if answers:
        patch("ageRatingDeclarations", rating["id"], answers)
    asc.note("Age rating: %d questions answered \"none\" or \"no\"." % len(answers))


def set_version(version, build):
    number = attributes(build).get("version")
    pre_release = get_or_none("/builds/%s/preReleaseVersion" % build["id"])
    version_string = attributes(pre_release).get("version")
    if not version_string:
        asc.fail("build %s has no version number" % number)
    patch("appStoreVersions", version["id"], {
        "versionString": version_string,
        "copyright": COPYRIGHT,
        "releaseType": "AFTER_APPROVAL",
    })
    asc.api("PATCH", "/appStoreVersions/%s/relationships/build" % version["id"], {
        "data": {"type": "builds", "id": build["id"]}})
    asc.note("Version %s with build %s, released as soon as Apple approves it." % (version_string, number))


def set_listing(version, locale):
    for loc in asc.api_list("/appStoreVersions/%s/appStoreVersionLocalizations" % version["id"]):
        if attributes(loc).get("locale") == locale:
            patch("appStoreVersionLocalizations", loc["id"], {
                "description": asc.text_block("**Description**"),
                "keywords": asc.text_block("**Keywords**"),
                "promotionalText": asc.text_block("**Promotional Text**"),
                "supportUrl": SUPPORT_URL,
            })
            asc.note("Listing: description, keywords, promotional text and support URL.")
            return loc
    asc.fail("the version has no %s localization" % locale)


def upload_screenshots(localization):
    sets = {
        attributes(s).get("screenshotDisplayType"): s
        for s in asc.api_list("/appStoreVersionLocalizations/%s/appScreenshotSets" % localization["id"])
    }
    for display_type, folder in SCREENSHOTS.items():
        files = sorted(folder.glob("*.png"))
        if not files:
            asc.fail("no screenshots in %s: render them with godot/tests/store_shots.gd first" % folder)
        shot_set = sets.get(display_type) or asc.api("POST", "/appScreenshotSets", {"data": {
            "type": "appScreenshotSets",
            "attributes": {"screenshotDisplayType": display_type},
            "relationships": {"appStoreVersionLocalization": {"data": {
                "type": "appStoreVersionLocalizations", "id": localization["id"]}}}}})["data"]
        existing = asc.api_list("/appScreenshotSets/%s/appScreenshots" % shot_set["id"])
        # A rerun with the same images leaves Apple's copies alone.
        have = [(attributes(s).get("fileName"), attributes(s).get("sourceFileChecksum")) for s in existing]
        want = [(path.name, hashlib.md5(path.read_bytes()).hexdigest()) for path in files]
        if have == want:
            asc.note("Screenshots: %d in %s, already up to date." % (len(files), display_type))
            continue
        for old in existing:
            asc.api("DELETE", "/appScreenshots/%s" % old["id"])
        for path in files:
            upload_screenshot(shot_set["id"], path)
        asc.note("Screenshots: %d in %s." % (len(files), display_type))


def upload_screenshot(set_id, path):
    data = path.read_bytes()
    shot = asc.api("POST", "/appScreenshots", {"data": {
        "type": "appScreenshots",
        "attributes": {"fileName": path.name, "fileSize": len(data)},
        "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}})["data"]
    for op in attributes(shot).get("uploadOperations") or []:
        chunk = data[op["offset"]:op["offset"] + op["length"]]
        headers = {header["name"]: header["value"] for header in op.get("requestHeaders") or []}
        request = urllib.request.Request(op["url"], data=chunk, method=op["method"], headers=headers)
        with urllib.request.urlopen(request, timeout=120, context=ssl.create_default_context()):
            pass
    patch("appScreenshots", shot["id"], {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()})
    for _ in range(90):
        delivery = attributes(asc.api("GET", "/appScreenshots/%s" % shot["id"])["data"]).get("assetDeliveryState")
        state = (delivery or {}).get("state")
        if state == "COMPLETE":
            print("  uploaded %s" % path.name)
            return
        if state == "FAILED":
            asc.fail("Apple refused %s: %s" % (path.name, (delivery or {}).get("errors")))
        time.sleep(2)
    asc.fail("Apple was still processing %s after three minutes: run prepare again" % path.name)


def set_review_contact(version):
    """Contact name, email and notes. Apple makes the App Review details only with a contact
    phone, which this never enters: until they exist, it leaves them for App Store Connect."""
    detail = get_or_none("/appStoreVersions/%s/appStoreReviewDetail" % version["id"])
    if not detail:
        asc.note("App Review information isn't there yet: enter the contact phone in App Store Connect, "
                 "then run prepare again to add the contact name, email and notes.")
        return
    patch("appStoreReviewDetails", detail["id"], dict(asc.CONTACT, notes=asc.text_block("**Review Notes**"), demoAccountRequired=False))
    asc.note("App Review information: contact name, email and notes.")


def prepare(build_number, screenshots=True):
    app = asc.find_app()
    app_id = app["id"]
    locale = attributes(app).get("primaryLocale") or "en-GB"
    build, _ = asc.find_build(app_id, build_number)
    patch("apps", app_id, {"contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"})
    asc.note("Content rights: no third-party content.")
    info = editable_app_info(app_id)
    set_app_info(info, locale)
    answer_age_rating(info)
    version = editable_version(app_id)
    set_version(version, build)
    localization = set_listing(version, locale)
    if screenshots:
        upload_screenshots(localization)
    else:
        asc.note("Screenshots left as they are (--no-screenshots).")
    set_review_contact(version)
    todo = []
    detail = attributes(get_or_none("/appStoreVersions/%s/appStoreReviewDetail" % version["id"]))
    if not detail.get("contactPhone"):
        todo.append("the App Review contact phone")
    if detail.get("demoAccountRequired"):
        todo.append("untick App Review *Sign-in required* (the app has no sign-in)")
    if todo:
        asc.note("**Still to do in App Store Connect:** %s." % "; ".join(todo))
    # App Privacy is in no version of Apple's API: it can neither be filled in nor read here.
    asc.note("Check in App Store Connect that App Privacy is published; the API cannot see it.")


# --- submit -----------------------------------------------------------------------------

## A submission Apple already has in hand; a new one can't be made while one of these stands.
OPEN_SUBMISSION = ("READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW", "UNRESOLVED_ISSUES")


def cancel_open(app_id):
    """Withdraws any submission Apple is holding, so the version can be edited and sent again.

    A submission that holds nothing is one a refused run left behind: submit reuses it, so it is
    left alone. Cancelling gives up the queue place the submission had already earned.
    """
    cancelled = 0
    for existing in asc.api_list("/apps/%s/reviewSubmissions?filter[platform]=IOS" % app_id):
        state = attributes(existing).get("state")
        if state not in OPEN_SUBMISSION:
            continue
        if not asc.api_list("/reviewSubmissions/%s/items" % existing["id"]):
            continue
        try:
            patch("reviewSubmissions", existing["id"], {"canceled": True})
        except asc.ApiError as error:
            asc.fail("could not cancel the submission that was %s: %s" % (state, error))
        asc.note("Cancelled the submission that was `%s`; it loses its place in Apple's queue." % state)
        cancelled += 1
    return cancelled


def wait_editable(app_id, seconds=120):
    """Apple takes a moment to hand a cancelled version back, and until it does it can't be edited."""
    for waited in range(0, seconds, 5):
        for version in asc.api_list("/apps/%s/appStoreVersions?filter[platform]=IOS" % app_id):
            if attributes(version).get("appStoreState") in EDITABLE:
                return version
        time.sleep(5)
    asc.fail("the version is still not editable %d s after cancelling: look at App Store Connect" % seconds)


def submit(build_number):
    """Hands the prepared version to App Review. This is the irreversible step."""
    app = asc.find_app()
    app_id = app["id"]
    version = editable_version(app_id)
    a = attributes(version)
    build = get_or_none("/appStoreVersions/%s/build" % version["id"])
    if attributes(build).get("version") != build_number:
        asc.fail("version %s has build %s attached, not %s: run prepare first"
                 % (a.get("versionString"), attributes(build).get("version"), build_number))
    # An open submission holding nothing is one a refused run left behind: use that one again
    # rather than pile up another.
    submission = None
    for existing in asc.api_list("/apps/%s/reviewSubmissions?filter[platform]=IOS" % app_id):
        state = attributes(existing).get("state")
        if state not in OPEN_SUBMISSION:
            continue
        if asc.api_list("/reviewSubmissions/%s/items" % existing["id"]):
            asc.fail("a submission is already %s: look at App Store Connect before sending another" % state)
        submission = existing
    if submission is None:
        submission = asc.api("POST", "/reviewSubmissions", {"data": {
            "type": "reviewSubmissions",
            "attributes": {"platform": "IOS"},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
    asc.api("POST", "/reviewSubmissionItems", {"data": {
        "type": "reviewSubmissionItems",
        "relationships": {
            "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": submission["id"]}},
            "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version["id"]}}}}})
    done = patch("reviewSubmissions", submission["id"], {"submitted": True})["data"]
    asc.note("Submitted %s (build %s) for App Review: state `%s`. Apple emails when it changes, and the "
             "release follows as soon as Apple approves it." % (
                 a.get("versionString"), build_number, attributes(done).get("state")))


def release(build_number, screenshots=True):
    """Puts this build in front of Apple, in place of anything it is already holding."""
    app_id = asc.find_app()["id"]
    if cancel_open(app_id):
        wait_editable(app_id)
    prepare(build_number, screenshots)
    submit(build_number)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--issuer-id", required=True)
    parser.add_argument("--key-file", type=pathlib.Path, required=True)
    parser.add_argument("--build", default="", help="prepare / submit / release: the build number (e.g. 19)")
    parser.add_argument("--confirm", action="store_true",
                        help="submit / release / cancel: actually change what Apple holds")
    parser.add_argument("--no-screenshots", action="store_true",
                        help="prepare / release: leave the screenshots Apple already has (CI has no renders)")
    parser.add_argument("command", choices=["status", "prepare", "submit", "cancel", "release"])
    args = parser.parse_args()
    if not args.key_file.is_file():
        sys.exit("app_store: no API key file at %s" % args.key_file)
    if args.command in ("prepare", "submit", "release") and not args.build.strip():
        sys.exit("app_store: %s needs --build (the build number)" % args.command)
    if args.command in ("submit", "release", "cancel") and not args.confirm:
        sys.exit("app_store: %s changes what Apple holds; pass --confirm to mean it" % args.command)
    asc.TOKEN = jwt_es256(args.key_file, args.key_id.strip(), args.issuer_id.strip())
    try:
        if args.command == "status":
            status()
        elif args.command == "prepare":
            prepare(args.build.strip(), not args.no_screenshots)
        elif args.command == "cancel":
            if not cancel_open(asc.find_app()["id"]):
                asc.note("Nothing to cancel: Apple is holding no submission.")
        elif args.command == "release":
            release(args.build.strip(), not args.no_screenshots)
        else:
            submit(args.build.strip())
    except asc.ApiError as error:
        sys.exit("app_store: %s" % error)
    # Now that this runs from Actions, the notes belong in the run's summary, not only its log.
    asc.write_summary()


if __name__ == "__main__":
    main()
