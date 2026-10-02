#!/usr/bin/env python3
"""iOS signing files for the TestFlight workflow, made without a Mac.

    python godot/tools/ios/signing.py csr       # private key + certificate signing request for Apple
    python godot/tools/ios/signing.py secrets   # after downloading the .cer and .mobileprovision into
                                          # the same folder: checks them, builds the .p12 and
                                          # writes the GitHub secret values

Files live in ~/ios-signing, outside the repo (--dir changes it). Keep that folder: the key in it
is the only one that works with the certificate. Needs OpenSSL, which Git for Windows includes.
The workflow calls `profile-env <file>` to read a profile you supply as secret IOS_PROFILE_BASE64
(optional: by default CI makes the profile itself with app_profile.py).
Sail Tactics reuses the Apple Distribution certificate made for First Not Last, so csr and secrets
are only needed if you ever want a separate certificate.
"""

import argparse
import base64
import hashlib
import os
import pathlib
import plistlib
import secrets
import shlex
import shutil
import subprocess
import sys
from datetime import datetime, timezone

BUNDLE_ID = "com.russell.sailtactics"


def fail(message):
    sys.exit("error: " + message)


def find_openssl():
    for candidate in (shutil.which("openssl"),
                      r"C:\Program Files\Git\usr\bin\openssl.exe",
                      r"C:\Program Files\Git\mingw64\bin\openssl.exe"):
        if candidate and pathlib.Path(candidate).exists():
            return candidate
    fail("OpenSSL not found. Install Git for Windows or put openssl on PATH.")


def openssl(*args, env=None):
    # Files only, never stdin: Git for Windows' OpenSSL can't read DER piped in from Python.
    result = subprocess.run([find_openssl(), *args], capture_output=True, env={**os.environ, **(env or {})})
    if result.returncode:
        fail("openssl %s failed: %s" % (args[0], result.stderr.decode(errors="replace").strip()))
    return result.stdout


def read_profile(path):
    """A .mobileprovision is a signed CMS blob with the plist inside in plain text."""
    raw = path.read_bytes()
    start, end = raw.find(b"<?xml"), raw.find(b"</plist>")
    if start < 0 or end < 0:
        fail("%s is not a provisioning profile" % path)
    return raw, plistlib.loads(raw[start:end + len(b"</plist>")])


def check_profile(path, profile):
    """Catch the profile mistakes that would otherwise fail deep inside the Xcode build."""
    team = profile["TeamIdentifier"][0]
    app_id = profile["Entitlements"]["application-identifier"]
    if app_id != "%s.%s" % (team, BUNDLE_ID):
        fail("%s is for %s, not %s.%s" % (path.name, app_id, team, BUNDLE_ID))
    if profile.get("ProvisionedDevices") or profile["Entitlements"].get("get-task-allow"):
        fail("%s is a development or ad hoc profile; make an App Store Connect one" % path.name)
    expires = profile["ExpirationDate"]
    if expires.replace(tzinfo=timezone.utc) < datetime.now(timezone.utc):
        fail("%s expired on %s" % (path.name, expires.date()))


def newest(folder, pattern):
    files = sorted(folder.glob(pattern), key=lambda p: p.stat().st_mtime)
    return files[-1] if files else None


def cmd_csr(folder):
    folder.mkdir(parents=True, exist_ok=True)
    key = folder / "distribution.key"
    if key.exists():
        print("Keeping the existing %s (a new key wouldn't match certificates made from it)." % key)
    else:
        openssl("genrsa", "-out", str(key), "2048")
    csr = folder / "distribution.csr"
    openssl("req", "-new", "-key", str(key), "-out", str(csr), "-subj", "/CN=Sail Tactics Distribution")
    print("Wrote %s" % csr)
    print("Next: developer.apple.com > Certificates > + > Apple Distribution, upload that file,")
    print("and download the certificate it gives you into %s" % folder)


def cmd_secrets(folder):
    key = folder / "distribution.key"
    if not key.exists():
        fail("no %s yet; run: python godot/tools/ios/signing.py csr" % key)
    cer = newest(folder, "*.cer")
    if not cer:
        fail("no .cer in %s; download the Apple Distribution certificate there" % folder)
    profile_path = newest(folder, "*.mobileprovision")
    if not profile_path:
        fail("no .mobileprovision in %s; download the App Store profile there" % folder)

    cert = cer.read_bytes()
    if cert.lstrip().startswith(b"-----BEGIN"):  # Apple sends DER, but take PEM too
        cert = base64.b64decode(b"".join(l.strip() for l in cert.splitlines() if l.strip() and not l.startswith(b"-----")))
    body = base64.b64encode(cert).decode()
    pem_path, p12 = folder / "distribution.pem", folder / "distribution.p12"
    pem_path.write_bytes(("-----BEGIN CERTIFICATE-----\n%s\n-----END CERTIFICATE-----\n"
                          % "\n".join(body[i:i + 64] for i in range(0, len(body), 64))).encode("ascii"))
    subject = openssl("x509", "-in", str(pem_path), "-noout", "-subject").decode(errors="replace").strip()
    if "Distribution" not in subject:
        fail("%s is not an Apple Distribution certificate (%s)" % (cer.name, subject))
    if openssl("x509", "-in", str(pem_path), "-noout", "-pubkey") != openssl("pkey", "-in", str(key), "-pubout"):
        fail("%s wasn't made from distribution.csr (it doesn't match distribution.key)" % cer.name)

    raw, profile = read_profile(profile_path)
    check_profile(profile_path, profile)
    if hashlib.sha1(cert).digest() not in {hashlib.sha1(c).digest() for c in profile["DeveloperCertificates"]}:
        fail("%s doesn't include %s; edit the profile, tick that certificate and download it again"
             % (profile_path.name, cer.name))

    password = secrets.token_hex(16)
    # SHA1 + 3DES is the PKCS#12 flavour macOS `security import` reads; OpenSSL 3's default isn't.
    openssl("pkcs12", "-export", "-inkey", str(key), "-in", str(pem_path), "-name", "Apple Distribution",
            "-certpbe", "PBE-SHA1-3DES", "-keypbe", "PBE-SHA1-3DES", "-macalg", "sha1",
            "-passout", "env:P12_PASSWORD", "-out", str(p12), env={"P12_PASSWORD": password})

    out = folder / "github-secrets"
    out.mkdir(exist_ok=True)
    values = {
        "IOS_DIST_CERT_P12_BASE64": base64.b64encode(p12.read_bytes()).decode(),
        "IOS_DIST_CERT_P12_PASSWORD": password,
        "IOS_PROFILE_BASE64": base64.b64encode(raw).decode(),
    }
    for name, value in values.items():
        (out / (name + ".txt")).write_text(value, encoding="ascii")  # no newline: pasted as-is

    print('Signing files check out: team %s, profile "%s", expires %s.'
          % (profile["TeamIdentifier"][0], profile["Name"], profile["ExpirationDate"].date()))
    print("Add these on GitHub (repo > Settings > Secrets and variables > Actions > New repository secret):")
    for name in values:
        print("  %-27s whole contents of %s" % (name, out / (name + ".txt")))
    print("  %-27s from App Store Connect > Users and Access > Integrations > App Store Connect API" % "ASC_KEY_ID, ASC_ISSUER_ID")
    print("  %-27s whole contents of the AuthKey_XXXXXXXXXX.p8 you downloaded there" % "ASC_API_KEY_P8")
    print('Copy a file in PowerShell with: Get-Content -Raw "<file>" | Set-Clipboard')


def cmd_profile_env(path):
    _, profile = read_profile(path)
    check_profile(path, profile)
    values = {
        "TEAM_ID": profile["TeamIdentifier"][0],
        "PROFILE_UUID": profile["UUID"],
        "PROFILE_NAME": profile["Name"],
        "PROFILE_EXPIRES": str(profile["ExpirationDate"].date()),
        "PROFILE_CERT_SHA1S": " ".join(hashlib.sha1(c).hexdigest().upper() for c in profile["DeveloperCertificates"]),
    }
    for name, value in values.items():
        print("%s=%s" % (name, shlex.quote(value)))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=("csr", "secrets", "profile-env"))
    parser.add_argument("profile", nargs="?", help="profile-env only: the .mobileprovision to read")
    parser.add_argument("--dir", type=pathlib.Path, default=pathlib.Path.home() / "ios-signing")
    args = parser.parse_args()
    if args.command == "csr":
        cmd_csr(args.dir)
    elif args.command == "secrets":
        cmd_secrets(args.dir)
    elif not args.profile:
        parser.error("profile-env needs the .mobileprovision path")
    else:
        cmd_profile_env(pathlib.Path(args.profile))


if __name__ == "__main__":
    main()
