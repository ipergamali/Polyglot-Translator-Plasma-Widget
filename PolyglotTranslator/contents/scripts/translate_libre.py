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
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


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
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "User-Agent": "PolyglotTranslator/1.0",
    }

    req = Request(url, data=json.dumps(payload).encode("utf-8"), headers=headers, method="POST")

    data: Any = None
    try:
        with urlopen(req, timeout=20) as response:
            try:
                data = json.load(response)
            except json.JSONDecodeError as exc:
                print(f"Error: Failed to decode response ({exc}).", file=sys.stderr)
                sys.exit(3)
    except HTTPError as exc:
        print(f"Error: HTTP {exc.code} {exc.reason}", file=sys.stderr)
        sys.exit(2)
    except URLError as exc:
        print(f"Error: {exc.reason}", file=sys.stderr)
        sys.exit(2)

    if not data:
        print("Error: Translation service returned no data.", file=sys.stderr)
        sys.exit(3)

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
