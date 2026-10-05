"""Run only on a disposable GitHub-hosted Mac after owner approval."""
import base64
import binascii
import datetime as dt
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import textwrap

BUNDLES = {"Rhythm.app": "com.kawakahi.rhythm",
           "Rhythm.app/PlugIns/RhythmScreenTime.appex": "com.kawakahi.rhythm.ScreenTimeReport"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def normalize_private_key(text):
    # Reconstruct only transport formatting; OpenSSL validates the actual private key before Apple access.
    text = text.strip().lstrip("\ufeff").strip().replace("\r\n", "\n")
    begin, end = "-----BEGIN PRIVATE KEY-----", "-----END PRIVATE KEY-----"
    if text.startswith(begin) and text.endswith(end):
        body = text[len(begin):-len(end)]
    else:
        body = text
    compact = "".join(body.split())
    try:
        der = base64.b64decode(compact, validate=True)
    except (binascii.Error, ValueError):
        raise ValueError("ASC_PRIVATE_KEY is neither a PEM private key nor a base64 key body. "
                         "No contents logged. Copy the downloaded .p8 file text, not setup instructions.") from None
    require(der.startswith(b"\x30") and len(der) > 2, "ASC_PRIVATE_KEY is not DER key data; no contents logged.")
    return begin + "\n" + textwrap.fill(compact, 64) + "\n" + end + "\n"


def check_distribution(info, signed, profile, bundle, team, build, now):
    require(info.get("CFBundleIdentifier") == bundle, "Unexpected bundle ID")
    require(info.get("CFBundleVersion") == build, "Build number mismatch")
    require(info.get("DTPlatformName") == "iphoneos", "Not an iPhone build")
    require(profile.get("ExpirationDate", dt.datetime.min) > now, "Expired profile")
    require(team in profile.get("TeamIdentifier", []), "Profile team mismatch")
    require(not profile.get("ProvisionedDevices") and not profile.get("ProvisionsAllDevices"),
            "Not an App Store distribution profile")
    allowed = profile.get("Entitlements", {})
    for ent in (signed, allowed):
        require(ent.get("application-identifier") == f"{team}.{bundle}", "Application identifier mismatch")
        require(ent.get("com.apple.developer.team-identifier") == team, "Signing team mismatch")
        require(ent.get("get-task-allow") is not True, "Debugging entitlement present")
        require(ent.get("com.apple.developer.family-controls") is True, "Family Controls missing")
    if bundle == "com.kawakahi.rhythm":
        for ent in (signed, allowed):
            require(ent.get("com.apple.developer.healthkit") is True, "HealthKit missing")
        require(signed.get("com.apple.developer.default-data-protection") == "NSFileProtectionComplete",
                "Complete data protection missing")


def run(args, *, cwd=None, capture=False):
    return subprocess.run([str(x) for x in args], cwd=cwd, check=True,
                          stdout=subprocess.PIPE if capture else None, stdin=subprocess.DEVNULL)


def main():
    require(sys.platform == "darwin" and os.environ.get("GITHUB_ACTIONS") == "true",
            "Use the manual workflow on a disposable GitHub-hosted Mac")
    require(os.environ.get("GITHUB_REF") == "refs/heads/main", "Only main is supported")
    names = ("ASC_PRIVATE_KEY", "ASC_KEY_ID", "ASC_ISSUER_ID", "APPLE_TEAM_ID")
    require(all(os.environ.get(n) for n in names), "Required signing secrets are missing")
    key_text = os.environ.pop("ASC_PRIVATE_KEY")
    key_id, issuer, team = [os.environ[n].strip() for n in names[1:]]
    require(re.fullmatch(r"[A-Z0-9]{10}", key_id) is not None, "Invalid key ID")
    require(re.fullmatch(r"[A-Z0-9]{10}", team) is not None, "Invalid team ID")
    require(re.fullmatch(r"[0-9a-fA-F-]{36}", issuer) is not None, "Invalid issuer ID")
    key_text = normalize_private_key(key_text)
    upload = os.environ.get("RHYTHM_UPLOAD", "false")
    require(upload in ("true", "false"), "Invalid upload selection")
    sequence, attempt = os.environ["GITHUB_RUN_NUMBER"], os.environ["GITHUB_RUN_ATTEMPT"]
    require(sequence.isdecimal() and attempt.isdecimal(), "Invalid run number")
    build = f"1.{sequence}.{attempt}"
    root = Path(__file__).resolve().parent.parent
    with tempfile.TemporaryDirectory(prefix="rhythm-sign-", dir=os.environ["RUNNER_TEMP"]) as folder:
        work = Path(folder)
        keys = work / "private_keys"
        keys.mkdir(mode=0o700)
        key = keys / f"AuthKey_{key_id}.p8"
        with key.open("x", encoding="utf-8", newline="\n") as f:
            f.write(key_text.strip() + "\n")
        key.chmod(0o600)
        del key_text
        run(["openssl", "pkey", "-in", key, "-check", "-noout", "-passin", "stdin"], capture=True)
        auth = ["-allowProvisioningUpdates", "-authenticationKeyPath", key,
                "-authenticationKeyID", key_id, "-authenticationKeyIssuerID", issuer]
        archive, exported = work / "Rhythm.xcarchive", work / "export"
        print("Building and signing Rhythm and its report extension.", flush=True)
        run(["xcodebuild", "-quiet", "-project", root / "Rhythm.xcodeproj", "-scheme", "Rhythm",
             "-configuration", "Release", "-destination", "generic/platform=iOS",
             "-archivePath", archive, "-derivedDataPath", work / "DerivedData", *auth,
             f"DEVELOPMENT_TEAM={team}", f"CURRENT_PROJECT_VERSION={build}",
             "CODE_SIGN_STYLE=Automatic", "archive"], cwd=root)
        options = work / "ExportOptions.plist"
        with options.open("wb") as f:
            plistlib.dump({"method": "app-store-connect", "destination": "export", "teamID": team,
                          "signingStyle": "automatic", "manageAppVersionAndBuildNumber": False,
                          "uploadSymbols": True, "testFlightInternalTestingOnly": True}, f)
        run(["xcodebuild", "-quiet", "-exportArchive", "-archivePath", archive,
             "-exportOptionsPlist", options, "-exportPath", exported, *auth])
        ipas = list(exported.glob("*.ipa"))
        require(len(ipas) == 1, "Expected exactly one IPA")
        unpacked = work / "verified"
        run(["ditto", "-x", "-k", ipas[0], unpacked])
        versions = set()
        for relative, bundle in BUNDLES.items():
            app = unpacked / "Payload" / relative
            run(["codesign", "--verify", "--deep", "--strict", app])
            info = plistlib.loads((app / "Info.plist").read_bytes())
            signed = plistlib.loads(run(["codesign", "-d", "--entitlements", ":-", app], capture=True).stdout)
            profile = plistlib.loads(run(["security", "cms", "-D", "-i", app / "embedded.mobileprovision"], capture=True).stdout)
            check_distribution(info, signed, profile, bundle, team, build, dt.datetime.now(dt.UTC).replace(tzinfo=None))
            versions.add(info["CFBundleShortVersionString"])
        require(len(versions) == 1, "App and extension version mismatch")
        print("Signature, distribution profiles and app capabilities verified.", flush=True)
        if upload == "true":
            # altool finds ./private_keys here; private key contents never enter command arguments.
            common = ["-f", ipas[0], "-t", "ios", "--apiKey", key_id, "--apiIssuer", issuer]
            run(["xcrun", "altool", "--validate-app", *common], cwd=work)
            run(["xcrun", "altool", "--upload-app", *common], cwd=work)
            print("Upload command succeeded. Apple processing/TestFlight availability still require confirmation.")
        else:
            print("Verified only; no upload requested. No IPA or signing credentials retained as artifacts.")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write(f"Rhythm build {build}: signature and capability checks passed. Upload requested: {upload}.\n")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, subprocess.CalledProcessError) as error:
        # Do not dump environment variables, keys or command arguments.
        print(str(error) if isinstance(error, ValueError) else "Apple tool failed; inspect its preceding diagnostic.", file=sys.stderr)
        sys.exit(1)
