#!/usr/bin/env python3
"""
Translate text via the MyMemory translation API.

Usage:
    translate_mymemory.py "<text>" <target_lang> [source_lang]
"""

from __future__ import annotations

import json
import sys
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


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
    query = urlencode({"q": text, "langpair": langpair})
    req = Request(
        f"{API_URL}?{query}",
        headers={"User-Agent": "PolyglotTranslator/1.0", "Accept": "application/json"},
    )

    data: dict[str, Any] | None = None
    try:
        with urlopen(req, timeout=15) as response:
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
        print("Error: Empty response from MyMemory.", file=sys.stderr)
        sys.exit(3)

    status = data.get("responseStatus")
    if status != 200:
        details = data.get("responseDetails") or "Unknown error."
        print(f"Error: {details}", file=sys.stderr)
        sys.exit(3)

    response_data = data.get("responseData")
    translation = (
        response_data.get("translatedText") if isinstance(response_data, dict) else None
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
