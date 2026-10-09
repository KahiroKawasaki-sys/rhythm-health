"""Print the latest App Store Connect builds and their TestFlight state (read-only)."""
import json
import os
import textwrap
import time
import urllib.request

import jwt

key = os.environ["ASC_PRIVATE_KEY"].strip()
if "BEGIN PRIVATE KEY" not in key:
    key = "-----BEGIN PRIVATE KEY-----\n" + textwrap.fill("".join(key.split()), 64) + "\n-----END PRIVATE KEY-----\n"
now = int(time.time())
token = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"].strip(), "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
                   key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"].strip()})


def get(path):
    request = urllib.request.Request("https://api.appstoreconnect.apple.com" + path, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(request) as response:
        return json.load(response)


app = get("/v1/apps?filter[bundleId]=com.kawakahi.rhythm")["data"][0]["id"]
builds = get(f"/v1/builds?filter[app]={app}&sort=-uploadedDate&limit=6&include=buildBetaDetail,betaGroups")
details = {i["id"]: i["attributes"] for i in builds.get("included", []) if i["type"] == "buildBetaDetails"}
groups = {i["id"]: i["attributes"].get("name") for i in builds.get("included", []) if i["type"] == "betaGroups"}
for build in builds["data"]:
    a = build["attributes"]
    rel = build.get("relationships", {})
    detail = details.get((rel.get("buildBetaDetail", {}).get("data") or {}).get("id"), {})
    names = [groups.get(g["id"]) for g in (rel.get("betaGroups", {}).get("data") or [])]
    print("BUILD", a.get("version"), a.get("uploadedDate"), "processing:", a.get("processingState"),
          "expired:", a.get("expired"), "encryption:", a.get("usesNonExemptEncryption"),
          "internal:", detail.get("internalBuildState"), "external:", detail.get("externalBuildState"), "groups:", names)
