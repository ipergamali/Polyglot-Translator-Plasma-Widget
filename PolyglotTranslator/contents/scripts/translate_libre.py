#!/usr/bin/env python3
"""
Translate text using a LibreTranslate-compatible API endpoint.

Usage:
    translate_libre.py "<text>" <target_lang> [source_lang]

Environment variables:
    LIBRETRANSLATE_URL  Override the default LibreTranslate endpoint.
"""

from __future__ import annotations

import json
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
        print("Usage: translate_libre.py <text> <target> [source]", file=sys.stderr)
        sys.exit(1)

    text = sys.argv[1]
    target = sys.argv[2]
    source = sys.argv[3] if len(sys.argv) > 3 else "auto"
    return text, target, source


def request_translation(text: str, target: str, source: str) -> str:
    url = os.getenv("LIBRETRANSLATE_URL", "https://libretranslate.de/translate")
    payload: dict[str, Any] = {"q": text, "source": source, "target": target}
    headers = {"Content-Type": "application/json"}

    try:
        response = requests.post(
            url,
            headers=headers,
            data=json.dumps(payload),
            timeout=20,
        )
        response.raise_for_status()
    except requests.RequestException as exc:
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(2)

    data = response.json()
    translated = data.get("translatedText")
    if not translated:
        print("Error: Translation service returned no data.", file=sys.stderr)
        sys.exit(3)
    return translated


def main() -> None:
    text, target, source = parse_args()
    translated = request_translation(text, target, source)
    sys.stdout.write(translated)


if __name__ == "__main__":
    main()
