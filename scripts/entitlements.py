#!/usr/bin/env python3
"""Verify a signed binary carries the entitlements its target declares.

  entitlements.py check <signed.plist> <declared.entitlements>
      Exit non-zero (with a message) if any key, or any value of an array key,
      declared in the target's .entitlements file is missing from the signed
      set. Also exits non-zero if the declared file is empty or unparseable —
      an empty declared set would otherwise make every check trivially pass.

That last guard is not hypothetical. XcodeGen's `entitlements:` project.yml key
*generates* the plist at the given path, and with no `properties:` it overwrote
both checked-in .entitlements files with an empty dict on every
`xcodegen generate`. Releases were signed without the App Group for weeks while
this check reported OK, because it was comparing the build against the same
emptied file. The declared set is now required to be non-empty.

Zero third-party dependencies by design (this repo's supply-chain rule): the
standard library's plistlib only.
"""

import plistlib
import sys


def load(path):
    with open(path, "rb") as f:
        return plistlib.load(f)


def check(signed_path, declared_path):
    try:
        declared = load(declared_path)
    except Exception as exc:  # missing, truncated, not a plist
        sys.exit(f"cannot read declared entitlements {declared_path}: {exc}")

    # A declared set with no keys makes every comparison below vacuously true.
    # Treat it as a build-breaking error, not a pass.
    if not declared:
        sys.exit(
            f"declared entitlements {declared_path} are EMPTY — nothing to verify. "
            "Something overwrote the file (XcodeGen's `entitlements:` key generates "
            "over it; use CODE_SIGN_ENTITLEMENTS in an xcconfig instead)."
        )

    signed = load(signed_path)
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
    if cmd == "check":
        check(*sys.argv[2:4])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
