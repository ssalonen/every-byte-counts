#!/usr/bin/env python3
"""Entitlement helpers for the re-sign workaround.

Xcode 26 strips declared capabilities (e.g. App Groups) while packaging the
archive, even when the provisioning profile authorises them. The release build
re-asserts each target's declared entitlements onto the archived binary before
export; these helpers do the plist work.

  entitlements.py merge <signed.plist> <declared.entitlements> <out.plist>
      Merge the declared keys onto the entitlements already signed into the
      binary (declared wins) and write <out.plist>. Xcode-injected keys the
      declared file doesn't mention -- application-identifier,
      com.apple.developer.team-identifier, get-task-allow, beta-reports-active,
      keychain-access-groups -- are preserved.

  entitlements.py check <signed.plist> <declared.entitlements>
      Exit non-zero (with a message) if any key, or any value of an array key,
      declared in the target's .entitlements file is missing from the signed
      set. Gates the build so a future stripped capability fails loudly instead
      of shipping silently.

Zero third-party dependencies by design (this repo's supply-chain rule): the
standard library's plistlib only.
"""

import plistlib
import sys


def load(path):
    with open(path, "rb") as f:
        return plistlib.load(f)


def merge(signed_path, declared_path, out_path):
    merged = load(signed_path)
    merged.update(load(declared_path))
    with open(out_path, "wb") as f:
        plistlib.dump(merged, f)


def check(signed_path, declared_path):
    signed, declared = load(signed_path), load(declared_path)
    missing = []
    for key, value in declared.items():
        if key not in signed:
            missing.append(key)
        elif isinstance(value, list):
            present = signed[key] if isinstance(signed[key], list) else []
            missing += [f"{key}[{item!r}]" for item in value if item not in present]
    if missing:
        sys.exit("missing declared entitlements: " + ", ".join(missing))


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "merge":
        merge(*sys.argv[2:5])
    elif cmd == "check":
        check(*sys.argv[2:4])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
