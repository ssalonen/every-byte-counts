#!/usr/bin/env python3
"""Create and install App Store provisioning profiles via the ASC API.

Why this exists: `xcodebuild -exportArchive` with automatic signing insists
on Apple's cloud-signing service to mint missing App Store profiles, and
that path requires an Admin-role API key ("Cloud signing permission error"
with anything less). Creating the profiles through the official App Store
Connect API needs only App Manager, so this script (re)creates one
IOS_APP_STORE profile per bundle ID against the team's local distribution
certificate and installs them where Xcode looks. Profiles are keyed by a
fixed name and deleted before recreation, so runs are idempotent and a
rotated certificate self-heals on the next release.

Zero third-party dependencies by design (this repo's supply-chain rule):
the ES256 JWT is signed by shelling out to the system openssl and
converting the DER signature to the raw r||s form JWTs use.
"""

import argparse
import base64
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com"
PROFILE_DIRS = [
    # Classic location, still honored by xcodebuild.
    "~/Library/MobileDevice/Provisioning Profiles",
    # Xcode 16+ location.
    "~/Library/Developer/Xcode/UserData/Provisioning Profiles",
]


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_sig_to_raw(der: bytes) -> bytes:
    """Convert an ASN.1 DER ECDSA signature to the raw 64-byte r||s form."""

    def read_len(buf, i):
        length = buf[i]
        if length & 0x80:
            n = length & 0x7F
            return int.from_bytes(buf[i + 1 : i + 1 + n], "big"), i + 1 + n
        return length, i + 1

    if der[0] != 0x30:
        raise ValueError("not a DER sequence")
    _, i = read_len(der, 1)
    if der[i] != 0x02:
        raise ValueError("expected INTEGER for r")
    length, i = read_len(der, i + 1)
    r, i = der[i : i + length], i + length
    if der[i] != 0x02:
        raise ValueError("expected INTEGER for s")
    length, i = read_len(der, i + 1)
    s = der[i : i + length]
    pad = lambda v: v.lstrip(b"\x00").rjust(32, b"\x00")
    return pad(r) + pad(s)


def make_token(key_path: str, key_id: str, issuer_id: str) -> str:
    now = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {"iss": issuer_id, "iat": now - 60, "exp": now + 15 * 60,
               "aud": "appstoreconnect-v1"}
    signing_input = (
        f"{b64url(json.dumps(header).encode())}.{b64url(json.dumps(payload).encode())}"
    )
    der = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", key_path],
        input=signing_input.encode(), capture_output=True, check=True,
    ).stdout
    return f"{signing_input}.{b64url(der_sig_to_raw(der))}"


def api(token: str, method: str, path: str, body=None):
    req = urllib.request.Request(
        API + path,
        method=method,
        headers={"Authorization": f"Bearer {token}",
                 "Content-Type": "application/json"},
        data=json.dumps(body).encode() if body is not None else None,
    )
    try:
        with urllib.request.urlopen(req) as resp:
            data = resp.read()
            return json.loads(data) if data else None
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        sys.exit(f"error: {method} {path} -> HTTP {e.code}\n{detail}")


def local_distribution_serial(pem_bundle_path: str) -> str:
    """Serial of the first 'Apple Distribution' cert in a PEM bundle.

    The keychain dump may contain the WWDR intermediate alongside the
    signing cert, so filter by subject rather than assuming a single entry.
    """
    blocks, current = [], []
    for line in open(pem_bundle_path):
        current.append(line)
        if "END CERTIFICATE" in line:
            blocks.append("".join(current))
            current = []
    for block in blocks:
        with tempfile.NamedTemporaryFile("w", suffix=".pem") as tmp:
            tmp.write(block)
            tmp.flush()
            subject = subprocess.run(
                ["openssl", "x509", "-in", tmp.name, "-noout", "-subject"],
                capture_output=True, check=True, text=True,
            ).stdout
            if "Apple Distribution" not in subject:
                continue
            serial = subprocess.run(
                ["openssl", "x509", "-in", tmp.name, "-noout", "-serial"],
                capture_output=True, check=True, text=True,
            ).stdout
            return serial.strip().split("=", 1)[1].lstrip("0").upper()
    sys.exit(f"error: no 'Apple Distribution' certificate found in {pem_bundle_path}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--key-path", required=True, help="ASC API .p8 private key")
    ap.add_argument("--key-id", required=True)
    ap.add_argument("--issuer-id", required=True)
    ap.add_argument("--cert-pem", required=True,
                    help="PEM bundle holding the local Apple Distribution cert")
    ap.add_argument("--bundle-id", action="append", required=True,
                    help="repeatable; one profile is created per bundle ID")
    args = ap.parse_args()

    token = make_token(args.key_path, args.key_id, args.issuer_id)
    serial = local_distribution_serial(args.cert_pem)

    certs = api(token, "GET", "/v1/certificates?limit=200")["data"]
    matching = [
        c for c in certs
        if c["attributes"]["certificateType"] in ("DISTRIBUTION", "IOS_DISTRIBUTION")
        and c["attributes"]["serialNumber"].lstrip("0").upper() == serial
    ]
    if not matching:
        sys.exit(
            f"error: the team has no distribution certificate with serial {serial}; "
            "the local .p12 does not match any certificate registered in the portal"
        )
    cert_id = matching[0]["id"]

    for bundle_id in args.bundle_id:
        quoted = urllib.parse.quote(bundle_id)
        records = api(token, "GET",
                      f"/v1/bundleIds?filter[identifier]={quoted}&limit=200")["data"]
        record = next(
            (b for b in records if b["attributes"]["identifier"] == bundle_id), None)
        if record is None:
            sys.exit(f"error: bundle ID {bundle_id} is not registered in the portal")

        name = f"CI AppStore {bundle_id}"
        existing = api(token, "GET",
                       f"/v1/profiles?filter[name]={urllib.parse.quote(name)}")["data"]
        for profile in existing:
            api(token, "DELETE", f"/v1/profiles/{profile['id']}")

        created = api(token, "POST", "/v1/profiles", {
            "data": {
                "type": "profiles",
                "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
                "relationships": {
                    "bundleId": {"data": {"type": "bundleIds", "id": record["id"]}},
                    "certificates": {
                        "data": [{"type": "certificates", "id": cert_id}]},
                },
            }
        })["data"]

        content = base64.b64decode(created["attributes"]["profileContent"])
        uuid = created["attributes"]["uuid"]
        for directory in PROFILE_DIRS:
            directory = os.path.expanduser(directory)
            os.makedirs(directory, exist_ok=True)
            with open(os.path.join(directory, f"{uuid}.mobileprovision"), "wb") as f:
                f.write(content)
        print(f"{bundle_id} -> '{name}' ({uuid})")


if __name__ == "__main__":
    main()
