#!/usr/bin/env python3
"""Print the next App Store Connect build number for On Cue.

One counter, derived from what Apple has already accepted, so local uploads
and Xcode Cloud builds can never hand out the same number or appear to go
backwards. Needs ASC_KEY_ID and ASC_ISSUER_ID in the environment and
AuthKey_<ASC_KEY_ID>.p8 in ~/.appstoreconnect/private_keys/.
"""
import json
import os
import sys
import time
import urllib.request
from pathlib import Path

import jwt

APP_ID = "6796989022"

key_id = os.environ["ASC_KEY_ID"]
issuer_id = os.environ["ASC_ISSUER_ID"]
key_path = Path.home() / ".appstoreconnect" / "private_keys" / f"AuthKey_{key_id}.p8"
if not key_path.exists():
    sys.exit(f"No API key at {key_path}")

token = jwt.encode(
    {"iss": issuer_id, "iat": int(time.time()), "exp": int(time.time()) + 900,
     "aud": "appstoreconnect-v1"},
    key_path.read_text(), algorithm="ES256", headers={"kid": key_id, "typ": "JWT"},
)
request = urllib.request.Request(
    f"https://api.appstoreconnect.apple.com/v1/builds?filter[app]={APP_ID}&limit=200",
    headers={"Authorization": f"Bearer {token}"},
)
try:
    data = json.load(urllib.request.urlopen(request))
except urllib.error.HTTPError as error:
    sys.exit(f"App Store Connect returned {error.code}: {error.read().decode()[:200]}")

numbers = []
for build in data.get("data", []):
    version = build["attributes"].get("version")
    try:
        numbers.append(int(version))
    except (TypeError, ValueError):
        continue  # a non-numeric build string from some earlier scheme

print(max(numbers, default=0) + 1)
