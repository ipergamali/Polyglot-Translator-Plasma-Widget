#!/usr/bin/env python3
"""
Translate text via the MyMemory translation API.

Usage:
    translate_mymemory.py "<text>" <target_lang> [source_lang]
"""

from __future__ import annotations

import sys
from typing import Any

try:
    import requests
except ImportError as exc:  # pragma: no cover
    print(f"Error: requests module is required ({exc})", file=sys.stderr)
    sys.exit(99)


API_URL = "https://api.mymemory.translated.net/get"


def parse_args() -> tuple[str, str, str]:
    if len(sys.argv) < 3:
        print("Usage: translate_mymemory.py <text> <target> [source]", file=sys.stderr)
        sys.exit(1)

    text = sys.argv[1]
    target = sys.argv[2]
    source = sys.argv[3] if len(sys.argv) > 3 else "auto"
    return text, target, source


def request_translation(text: str, target: str, source: str) -> str:
    langpair = f"{source or 'auto'}|{target}"
    params = {"q": text, "langpair": langpair}

    try:
        response = requests.get(API_URL, params=params, timeout=15)
        response.raise_for_status()
    except requests.RequestException as exc:
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(2)

    data: dict[str, Any] = response.json()
    status = data.get("responseStatus")
    if status != 200:
        details = data.get("responseDetails") or "Unknown error."
        print(f"Error: {details}", file=sys.stderr)
        sys.exit(3)

    translation = (
        data.get("responseData", {}).get("translatedText") if isinstance(data.get("responseData"), dict) else None
    )
    if not translation:
        print("Error: No translation returned by MyMemory.", file=sys.stderr)
        sys.exit(4)

    return translation


def main() -> None:
    text, target, source = parse_args()
    translated = request_translation(text, target, source)
    sys.stdout.write(translated)


if __name__ == "__main__":
    main()
