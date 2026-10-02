#!/usr/bin/env python3
"""App Store signing profile for Sail Tactics, made through the App Store Connect API.

The Apple Distribution certificate (the same one First Not Last uses; a certificate belongs to the
whole developer account) is already in the CI keychain. This finds or registers the App ID, finds or
creates an App Store provisioning profile that includes that certificate, installs it for Xcode, and
prints the values the workflow needs.

    python3 app_profile.py register --key-id ... --issuer-id ... --key-file AuthKey.p8
    python3 app_profile.py profile  --key-id ... --issuer-id ... --key-file AuthKey.p8 --cert-sha1 ...

`register` only makes sure the App ID exists, so you can pick it in App Store Connect's New App dialog.
`profile` prints shell assignments (TEAM_ID, PROFILE_UUID, ...) for `eval`.
"""

import argparse
import base64
import hashlib
import json
import os
import pathlib
import plistlib
import shlex
import shutil
import ssl
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

BUNDLE_ID = "com.russell.sailtactics"
BUNDLE_NAME = "Sail Tactics"
PROFILE_NAME = "Sail Tactics App Store"
API = "https://api.appstoreconnect.apple.com/v1"
CERT_TYPES = ("DISTRIBUTION", "IOS_DISTRIBUTION")


def fail(message):
    sys.exit("app_profile: " + message)


def b64url(data):
    if isinstance(data, str):
        data = data.encode("ascii")
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def read_len(buf, i):
    first = buf[i]
    if first < 0x80:
        return first, i + 1
    n = first & 0x7F
    return int.from_bytes(buf[i + 1:i + 1 + n], "big"), i + 1 + n


def der_p256_to_rs(der):
    if not der or der[0] != 0x30:
        fail("openssl ECDSA signature was not a DER SEQUENCE")
    _, i = read_len(der, 1)

    def read_int():
        nonlocal i
        if der[i] != 0x02:
            fail("openssl ECDSA signature was missing an INTEGER")
        length, i = read_len(der, i + 1)
        value = der[i:i + length]
        i += length
        value = value.lstrip(b"\x00")
        if len(value) > 32:
            fail("ECDSA integer was %d bytes, not P-256" % len(value))
        return value.rjust(32, b"\x00")

    return read_int() + read_int()


def jwt_es256(key_path, key_id, issuer_id):
    now = int(time.time())
    header = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}, separators=(",", ":")))
    payload = b64url(json.dumps(
        {"iss": issuer_id, "iat": now, "exp": now + 19 * 60, "aud": "appstoreconnect-v1"},
        separators=(",", ":"),
    ))
    signing_input = ("%s.%s" % (header, payload)).encode("ascii")
    openssl = shutil.which("openssl")
    if not openssl:
        fail("openssl not found (needed to sign the App Store Connect JWT)")
    with tempfile.TemporaryDirectory() as tmp:
        message = pathlib.Path(tmp) / "jwt.bin"
        signature = pathlib.Path(tmp) / "jwt.sig"
        message.write_bytes(signing_input)
        result = subprocess.run(
            [openssl, "dgst", "-sha256", "-sign", str(key_path), "-out", str(signature), str(message)],
            capture_output=True,
        )
        if result.returncode:
            fail("openssl could not sign with %s: %s" % (key_path, result.stderr.decode(errors="replace").strip()))
        der = signature.read_bytes()
    return "%s.%s.%s" % (header, payload, b64url(der_p256_to_rs(der)))


def api(method, url, token, body=None):
    if url.startswith("/"):
        url = API + url
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": "Bearer " + token,
        "Accept": "application/json",
        "Content-Type": "application/json",
    })
    context = ssl.create_default_context()
    try:
        with urllib.request.urlopen(req, timeout=60, context=context) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", "replace")
        if error.code == 403:
            fail("App Store Connect API key cannot manage App IDs or profiles (%s). Give the key the Admin role, or "
                 "make the App ID and an App Store profile by hand on developer.apple.com and add the profile "
                 "as GitHub secret IOS_PROFILE_BASE64 (see godot/IOS_RELEASE.md). %s" % (error.code, detail))
        fail("App Store Connect %s %s failed (%s): %s" % (method, url, error.code, detail))


def api_list(path, token):
    items = []
    url = path
    while url:
        payload = api("GET", url, token)
        items.extend(payload.get("data") or [])
        url = (payload.get("links") or {}).get("next")
    return items


def read_profile(path):
    raw = path.read_bytes()
    start, end = raw.find(b"<?xml"), raw.find(b"</plist>")
    if start < 0 or end < 0:
        fail("%s is not a provisioning profile" % path)
    return raw, plistlib.loads(raw[start:end + len(b"</plist>")])


def check_app_profile(path, profile):
    app_id = str(profile.get("Entitlements", {}).get("application-identifier", ""))
    if not app_id.endswith("." + BUNDLE_ID):
        fail("%s is for %s, not %s" % (path.name, app_id, BUNDLE_ID))
    if profile.get("ProvisionedDevices") or profile.get("Entitlements", {}).get("get-task-allow"):
        fail("%s is a development or ad hoc profile; make an App Store Connect one" % path.name)


def install_profile(raw, uuid):
    homes = (
        pathlib.Path.home() / "Library/MobileDevice/Provisioning Profiles",
        pathlib.Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
    )
    dest = None
    for folder in homes:
        folder.mkdir(parents=True, exist_ok=True)
        dest = folder / ("%s.mobileprovision" % uuid)
        dest.write_bytes(raw)
    return dest


def finish(raw, profile):
    install_profile(raw, profile["UUID"])
    values = {
        "TEAM_ID": profile["TeamIdentifier"][0],
        "PROFILE_UUID": profile["UUID"],
        "PROFILE_NAME": profile.get("Name") or profile["UUID"],
        "PROFILE_EXPIRES": str(profile["ExpirationDate"].date()),
        "PROFILE_CERT_SHA1S": " ".join(hashlib.sha1(c).hexdigest().upper() for c in profile["DeveloperCertificates"]),
    }
    for name, value in values.items():
        print("%s=%s" % (name, shlex.quote(str(value))))


def cert_der(content_b64):
    raw = base64.b64decode(content_b64)
    if raw.lstrip().startswith(b"-----BEGIN"):
        body = b"".join(line.strip() for line in raw.splitlines() if line.strip() and not line.startswith(b"-----"))
        return base64.b64decode(body)
    return raw


def cert_sha1(content_b64):
    return hashlib.sha1(cert_der(content_b64)).hexdigest().upper()


def find_distribution_cert(token, want_sha1):
    want = want_sha1.replace(":", "").upper()
    found = api_list("/certificates?limit=200", token)
    for cert in found:
        attrs = cert.get("attributes") or {}
        if attrs.get("certificateType") not in CERT_TYPES:
            continue
        content = attrs.get("certificateContent")
        if content and cert_sha1(content) == want:
            return cert
    names = []
    for cert in found:
        attrs = cert.get("attributes") or {}
        names.append("%s %s" % (attrs.get("certificateType"), attrs.get("displayName") or cert.get("id")))
    fail("No App Store Connect Distribution certificate matched SHA-1 %s (saw: %s)"
         % (want, names or "none"))


def find_or_create_bundle_id(token):
    matches = api_list(
        "/bundleIds?filter[identifier]=%s&limit=200" % urllib.parse.quote(BUNDLE_ID, safe="."),
        token,
    )
    for item in matches:
        if (item.get("attributes") or {}).get("identifier") == BUNDLE_ID:
            return item
    created = api("POST", "/bundleIds", token, {
        "data": {
            "type": "bundleIds",
            "attributes": {
                "identifier": BUNDLE_ID,
                "name": BUNDLE_NAME,
                "platform": "IOS",
            },
        }
    })
    data = created.get("data")
    if not data:
        fail("creating bundle ID %s returned no data" % BUNDLE_ID)
    print("Created App ID %s" % BUNDLE_ID, file=sys.stderr)
    return data


def profile_has_cert(token, profile_id, cert_id):
    certs = api_list("/profiles/%s/certificates?limit=200" % profile_id, token)
    return any(item.get("id") == cert_id for item in certs)


def find_or_create_profile(token, bundle, cert):
    profiles = api_list("/bundleIds/%s/profiles?limit=200" % bundle["id"], token)
    named = None
    reusable = []
    for profile in profiles:
        attrs = profile.get("attributes") or {}
        if attrs.get("profileType") != "IOS_APP_STORE":
            continue
        if attrs.get("profileState") not in (None, "ACTIVE"):
            continue
        if not profile_has_cert(token, profile["id"], cert["id"]):
            continue
        reusable.append(profile)
        if attrs.get("name") == PROFILE_NAME:
            named = profile
    if named:
        return named
    if reusable:
        return reusable[0]
    created = api("POST", "/profiles", token, {
        "data": {
            "type": "profiles",
            "attributes": {
                "name": PROFILE_NAME,
                "profileType": "IOS_APP_STORE",
            },
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle["id"]}},
                "certificates": {"data": [{"type": "certificates", "id": cert["id"]}]},
            },
        }
    })
    data = created.get("data")
    if not data:
        fail("creating profile %r returned no data" % PROFILE_NAME)
    print("Created App Store profile %r" % PROFILE_NAME, file=sys.stderr)
    return data


def download_profile(token, profile):
    content = (profile.get("attributes") or {}).get("profileContent")
    if not content:
        profile = api("GET", "/profiles/%s" % profile["id"], token).get("data") or {}
        content = (profile.get("attributes") or {}).get("profileContent")
    if not content:
        fail("App Store Connect profile %s has no profileContent" % profile.get("id"))
    raw = base64.b64decode(content)
    start, end = raw.find(b"<?xml"), raw.find(b"</plist>")
    if start < 0 or end < 0:
        fail("downloaded profile was not a .mobileprovision")
    parsed = plistlib.loads(raw[start:end + len(b"</plist>")])
    check_app_profile(pathlib.Path("SailTactics.mobileprovision"), parsed)
    return raw, parsed


def from_asc(key_id, issuer_id, key_file, cert_sha1_hex):
    token = jwt_es256(key_file, key_id, issuer_id)
    cert = find_distribution_cert(token, cert_sha1_hex)
    bundle = find_or_create_bundle_id(token)
    profile = find_or_create_profile(token, bundle, cert)
    raw, parsed = download_profile(token, profile)
    finish(raw, parsed)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=("register", "profile"))
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--issuer-id", required=True)
    parser.add_argument("--key-file", type=pathlib.Path, required=True)
    parser.add_argument("--cert-sha1", help="profile only: SHA-1 of the Apple Distribution certificate in the keychain")
    args = parser.parse_args()
    if not args.key_file.is_file():
        fail("no API key file at %s" % args.key_file)
    key_id, issuer_id = args.key_id.strip(), args.issuer_id.strip()
    if args.command == "register":
        token = jwt_es256(args.key_file, key_id, issuer_id)
        bundle = find_or_create_bundle_id(token)
        print("App ID %s is registered (%s). Next: App Store Connect > Apps > + New App, and pick it as the "
              "Bundle ID." % (BUNDLE_ID, bundle.get("id")))
        return
    if not args.cert_sha1:
        fail("profile needs --cert-sha1")
    from_asc(key_id, issuer_id, args.key_file, args.cert_sha1.strip())


if __name__ == "__main__":
    main()
