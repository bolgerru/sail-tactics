#!/usr/bin/env python3
"""Open TestFlight to anyone with a link: a "Public" external group with a public link.

    python3 godot/tools/ios/testflight_public.py --key-id … --issuer-id … --key-file AuthKey.p8 [--phone +353…]

Safe to rerun. Each run:
  - fills in TestFlight Test Information and the newest build's What to Test from APP_STORE_TEXT.md,
  - makes the external group "Public" if it's missing and adds the newest build to it,
  - sends that build to Beta App Review once a contact phone is on file (the app needs no sign-in),
  - turns the public link on (Apple may hold it back until a build is approved) and prints it.

Writes a summary to GITHUB_STEP_SUMMARY when that variable is set.
"""

import argparse
import json
import os
import pathlib
import ssl
import sys
import urllib.error
import urllib.request

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from app_profile import jwt_es256  # noqa: E402

BUNDLE_ID = "com.russell.sailtactics"
GROUP_NAME = "Public"
API = "https://api.appstoreconnect.apple.com/v1"
TEXT_FILE = pathlib.Path(__file__).resolve().parents[2] / "store" / "APP_STORE_TEXT.md"
FEEDBACK_EMAIL = "russellbolger06@gmail.com"
PRIVACY_URL = "https://bolgerru.github.io/sail-tactics/privacy.html"
CONTACT = {"contactFirstName": "Russell", "contactLastName": "Bolger", "contactEmail": FEEDBACK_EMAIL}

SUBMITTABLE = ("READY_FOR_BETA_SUBMISSION", "BETA_REJECTED")
IN_REVIEW = ("WAITING_FOR_BETA_REVIEW", "IN_BETA_REVIEW")
APPROVED = ("BETA_APPROVED", "IN_BETA_TESTING", "READY_FOR_BETA_TESTING")

TOKEN = ""
SUMMARY = []


class ApiError(Exception):
    def __init__(self, method, path, code, body):
        try:
            errors = json.loads(body).get("errors") or []
            parts = []
            for e in errors:
                parts.append(e.get("detail") or e.get("title") or "")
                # Apple lists the real reasons under meta.associatedErrors, keyed by resource.
                for resource, items in ((e.get("meta") or {}).get("associatedErrors") or {}).items():
                    for item in items:
                        parts.append("[%s] %s" % (resource, item.get("detail") or item.get("title") or item.get("code")))
            detail = "; ".join(p for p in parts if p) or body
        except ValueError:
            detail = body
        super().__init__("%s %s failed (%s): %s" % (method, path, code, detail))
        self.code = code


def note(line):
    print(line)
    SUMMARY.append(line)


def write_summary():
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path and SUMMARY:
        with open(path, "a", encoding="utf-8") as handle:
            handle.write("\n\n".join(SUMMARY) + "\n")


def fail(message):
    note("**Stopped:** " + message)
    write_summary()
    sys.exit("testflight_public: " + message)


def wait(message):
    """Not an error: something at Apple has to finish first, so the run ends green."""
    note("**Waiting for** " + message)
    write_summary()
    sys.exit(0)


def api(method, path, body=None):
    url = path if path.startswith("http") else API + path
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": "Bearer " + TOKEN,
        "Accept": "application/json",
        "Content-Type": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=60, context=ssl.create_default_context()) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        raise ApiError(method, path, error.code, error.read().decode("utf-8", "replace")) from None


def api_list(path):
    items = []
    url = path
    while url:
        payload = api("GET", url)
        items.extend(payload.get("data") or [])
        url = (payload.get("links") or {}).get("next")
    return items


def text_block(label):
    """The first ``` block after the line containing label in APP_STORE_TEXT.md."""
    lines = TEXT_FILE.read_text(encoding="utf-8").splitlines()
    try:
        at = next(i for i, line in enumerate(lines) if label in line)
        start = next(i for i in range(at + 1, len(lines)) if lines[i].startswith("```"))
        end = next(i for i in range(start + 1, len(lines)) if lines[i].startswith("```"))
    except StopIteration:
        fail("no ``` block after %r in %s" % (label, TEXT_FILE.name))
    return "\n".join(lines[start + 1:end]).strip()


def find_app():
    for app in api_list("/apps?filter[bundleId]=%s" % BUNDLE_ID):
        if app["attributes"].get("bundleId") == BUNDLE_ID:
            return app
    fail("no App Store Connect app with bundle ID %s" % BUNDLE_ID)


def find_build(app_id, number):
    """Build `number`, or the newest processed one when number is blank."""
    query = "/builds?filter[app]=%s&filter[expired]=false&sort=-uploadedDate&limit=1&include=preReleaseVersion" % app_id
    query += "&filter[version]=%s" % number if number else "&filter[processingState]=VALID"
    payload = api("GET", query)
    builds = payload.get("data") or []
    if not builds:
        if number:
            wait("build %s: it isn't in App Store Connect yet, so it isn't ready yet. Run again in a few minutes."
                 % number)
        fail("no processed, unexpired build yet. Run the iOS TestFlight workflow and wait for Apple's processing email.")
    state = builds[0]["attributes"].get("processingState")
    if state != "VALID":
        wait("build %s to process: Apple has it as %s, so it isn't ready yet. Run again once it has processed."
             % (number, state))
    version = next((item["attributes"].get("version") for item in payload.get("included") or []
                    if item.get("type") == "preReleaseVersions"), "?")
    return builds[0], version


def external_state(build_id):
    detail = api("GET", "/builds/%s/buildBetaDetail" % build_id).get("data") or {}
    return (detail.get("attributes") or {}).get("externalBuildState") or "UNKNOWN"


def set_encryption(build):
    if build["attributes"].get("usesNonExemptEncryption") is None:
        api("PATCH", "/builds/%s" % build["id"], {"data": {
            "type": "builds", "id": build["id"], "attributes": {"usesNonExemptEncryption": False}}})
        note("Answered export compliance: no non-exempt encryption.")


def set_beta_app_localizations(app_id, locale):
    attrs = {
        "description": text_block("**Beta App Description**"),
        "feedbackEmail": FEEDBACK_EMAIL,
        "privacyPolicyUrl": PRIVACY_URL,
    }
    existing = api_list("/apps/%s/betaAppLocalizations" % app_id)
    for loc in existing:
        api("PATCH", "/betaAppLocalizations/%s" % loc["id"], {"data": {
            "type": "betaAppLocalizations", "id": loc["id"], "attributes": attrs}})
    if not existing:
        api("POST", "/betaAppLocalizations", {"data": {
            "type": "betaAppLocalizations",
            "attributes": dict(attrs, locale=locale),
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
    note("Test Information: beta app description, feedback email and privacy policy URL are set.")


def set_what_to_test(build_id, locale):
    whats_new = text_block("What to Test [")
    existing = api_list("/builds/%s/betaBuildLocalizations" % build_id)
    for loc in existing:
        api("PATCH", "/betaBuildLocalizations/%s" % loc["id"], {"data": {
            "type": "betaBuildLocalizations", "id": loc["id"], "attributes": {"whatsNew": whats_new}}})
    if not existing:
        api("POST", "/betaBuildLocalizations", {"data": {
            "type": "betaBuildLocalizations",
            "attributes": {"whatsNew": whats_new, "locale": locale},
            "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}})
    note("What to Test is set for this build.")


def review_detail(app_id):
    return api("GET", "/apps/%s/betaAppReviewDetail" % app_id)["data"]


def set_review_details(app_id, phone):
    detail = review_detail(app_id)
    attrs = dict(CONTACT, notes=text_block("**Review Notes**"), demoAccountRequired=False)
    if phone:
        attrs["contactPhone"] = phone
    elif not detail["attributes"].get("contactPhone"):
        note("No contact phone yet: rerun with one, or type it into Test Information.")
    api("PATCH", "/betaAppReviewDetails/%s" % detail["id"], {"data": {
        "type": "betaAppReviewDetails", "id": detail["id"], "attributes": attrs}})
    note("Beta App Review Information: contact and review notes are set.")


def ensure_group(app_id):
    for group in api_list("/betaGroups?filter[app]=%s&limit=200" % app_id):
        attrs = group["attributes"]
        if attrs.get("name") == GROUP_NAME and not attrs.get("isInternalGroup"):
            return group
    base = {"name": GROUP_NAME, "feedbackEnabled": True}
    link = {"publicLinkEnabled": True, "publicLinkLimitEnabled": False}
    for attrs in (dict(base, **link), base):
        try:
            created = api("POST", "/betaGroups", {"data": {
                "type": "betaGroups", "attributes": attrs,
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
            note("Made the external group %r." % GROUP_NAME)
            return created["data"]
        except ApiError as error:
            if attrs is base:
                raise
            print("Group with a public link refused (%s); making it without one." % error)


def add_build(group_id, build_id):
    try:
        api("POST", "/betaGroups/%s/relationships/builds" % group_id, {"data": [{"type": "builds", "id": build_id}]})
    except ApiError as error:
        if error.code != 409:
            raise


def submit(build_id):
    api("POST", "/betaAppReviewSubmissions", {"data": {
        "type": "betaAppReviewSubmissions",
        "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}})


def enable_public_link(group):
    attrs = group["attributes"]
    if attrs.get("publicLinkEnabled") and attrs.get("publicLink"):
        return group
    try:
        return api("PATCH", "/betaGroups/%s" % group["id"], {"data": {
            "type": "betaGroups", "id": group["id"],
            "attributes": {"publicLinkEnabled": True, "publicLinkLimitEnabled": False}}})["data"]
    except ApiError as error:
        print("Public link not turned on yet: %s" % error)
        return group


def run(phone, number):
    app = find_app()
    app_id = app["id"]
    locale = app["attributes"].get("primaryLocale") or "en-US"
    build, version = find_build(app_id, number)
    label = "%s (%s)" % (version, build["attributes"].get("version"))
    state = external_state(build["id"])
    note("Newest build: **%s**, external state `%s`." % (label, state))

    if state in IN_REVIEW or state in APPROVED:
        note("Test Information is left as it is while the build is in or past review.")
    else:
        set_encryption(build)
        set_beta_app_localizations(app_id, locale)
        set_what_to_test(build["id"], locale)
        set_review_details(app_id, phone)
        state = external_state(build["id"])

    group = ensure_group(app_id)
    add_build(group["id"], build["id"])
    note("Build %s is in the %r group." % (label, GROUP_NAME))

    if state in SUBMITTABLE:
        attrs = review_detail(app_id)["attributes"]
        if not attrs.get("contactPhone"):
            note("**Next:** Beta App Review needs a contact phone. Run this workflow again with the "
                 "contact_phone box filled in (country code, e.g. +353...).")
        elif not attrs.get("demoAccountRequired") or attrs.get("demoAccountName"):
            try:
                submit(build["id"])
            except ApiError as error:
                # Only one build of a version can be in Beta App Review at a time.
                if "already in beta review" not in str(error):
                    raise
                note("**Waiting for** the other %s build's review to finish: Apple says another build in "
                     "the same train is already in beta review. Run again once it's approved." % version)
            else:
                state = external_state(build["id"])
                note("Sent build %s to Beta App Review (now `%s`)." % (label, state))
        else:
            note("**Next:** App Store Connect > the app > TestFlight > Test Information > Beta App Review "
                 "Information: untick *Sign-in required*, Save, then run this workflow again.")

    group = enable_public_link(group)
    link = group["attributes"].get("publicLink")
    if link and group["attributes"].get("publicLinkEnabled"):
        note("**Public link:** %s" % link)
    else:
        note("The public link isn't on yet. Apple turns it on once a build has passed Beta App Review; "
             "run this workflow again after the approval email.")

    if state in IN_REVIEW:
        note("Waiting for Beta App Review (usually under a day). Apple emails when it's done. "
             "Testers can use the link after approval.")
    elif state in APPROVED:
        note("Approved: anyone with the link can install it with the TestFlight app (up to 10,000 testers).")
    elif state == "BETA_REJECTED":
        note("Apple rejected the last submission: read App Store Connect → TestFlight for the reason.")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--issuer-id", required=True)
    parser.add_argument("--key-file", type=pathlib.Path, required=True)
    parser.add_argument("--phone", default="", help="reviewer contact phone; blank keeps the current one")
    parser.add_argument("--build", default="", help="build number to use; blank takes the newest processed one")
    args = parser.parse_args()
    if not args.key_file.is_file():
        fail("no API key file at %s" % args.key_file)
    global TOKEN
    TOKEN = jwt_es256(args.key_file, args.key_id.strip(), args.issuer_id.strip())
    try:
        run(args.phone.strip(), args.build.strip())
    except ApiError as error:
        fail(str(error))
    write_summary()


if __name__ == "__main__":
    main()
