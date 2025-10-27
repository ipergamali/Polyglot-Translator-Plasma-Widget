#!/usr/bin/env python3
"""
Translate text using the DeepL REST API.

Usage:
    translate_deepl.py "<text>" <target_lang> [source_lang]

Requires the DEEPL_API_KEY environment variable.
Optionally set DEEPL_API_URL (defaults to https://api-free.deepl.com/v2/translate).
"""

from __future__ import annotations

import os
import sys
from typing import Any

try:
    import requests
except ImportError as exc:  # pragma: no cover
    print(f"Error: requests module is required ({exc})", file=sys.stderr)
    sys.exit(99)


def parse_args() -> tuple[str, str, str]:
    if len(sys.argv) < 3:
        print("Usage: translate_deepl.py <text> <target> [source]", file=sys.stderr)
        sys.exit(1)

    text = sys.argv[1]
    target = sys.argv[2]
    source = sys.argv[3] if len(sys.argv) > 3 else "auto"
    return text, target, source


def request_translation(text: str, target: str, source: str) -> str:
    api_key = os.getenv("DEEPL_API_KEY")
    if not api_key:
        print("Error: DEEPL_API_KEY environment variable is not set.", file=sys.stderr)
        sys.exit(2)

    api_url = os.getenv("DEEPL_API_URL", "https://api-free.deepl.com/v2/translate")
    target_lang = target.upper()
    payload: dict[str, Any] = {
        "auth_key": api_key,
        "text": text,
        "target_lang": target_lang,
    }
    if source and source.lower() != "auto":
        payload["source_lang"] = source.upper()

    try:
        response = requests.post(api_url, data=payload, timeout=20)
        response.raise_for_status()
    except requests.RequestException as exc:
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(3)

    data = response.json()
    translations = data.get("translations")
    if not translations:
        print("Error: No translations returned by DeepL.", file=sys.stderr)
        sys.exit(4)

    translated = translations[0].get("text")
    if not translated:
        print("Error: Empty translation from DeepL.", file=sys.stderr)
        sys.exit(5)

    return translated


def main() -> None:
    text, target, source = parse_args()
    translated = request_translation(text, target, source)
    sys.stdout.write(translated)


if __name__ == "__main__":
    main()
