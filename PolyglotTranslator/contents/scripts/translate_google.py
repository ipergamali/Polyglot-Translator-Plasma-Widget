#!/usr/bin/env python3
"""
Translate text via the unofficial Google Translate HTTP endpoint.

Usage:
    translate_google.py "<text>" <target_lang> [source_lang]
"""

from __future__ import annotations

import json
import sys
from typing import Any, Iterable

try:
    import requests
except ImportError as exc:  # pragma: no cover
    print(f"Error: requests module is required ({exc})", file=sys.stderr)
    sys.exit(99)


GOOGLE_ENDPOINT = "https://translate.googleapis.com/translate_a/single"


def parse_args() -> tuple[str, str, str]:
    if len(sys.argv) < 3:
        print("Usage: translate_google.py <text> <target> [source]", file=sys.stderr)
        sys.exit(1)

    text = sys.argv[1]
    target = sys.argv[2]
    source = sys.argv[3] if len(sys.argv) > 3 else "auto"
    return text, target, source


def flatten_translation(chunks: Iterable[Any]) -> str:
    parts: list[str] = []
    for chunk in chunks:
        if isinstance(chunk, list) and chunk:
            segment = chunk[0]
            if isinstance(segment, str):
                parts.append(segment)
    return "".join(parts)


def request_translation(text: str, target: str, source: str) -> str:
    params = {
        "client": "gtx",
        "sl": source if source else "auto",
        "tl": target,
        "dt": "t",
        "q": text,
    }

    try:
        response = requests.get(GOOGLE_ENDPOINT, params=params, timeout=15)
        response.raise_for_status()
    except requests.RequestException as exc:
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(2)

    try:
        data = response.json()
    except json.JSONDecodeError as exc:
        print(f"Error: Failed to decode response ({exc}).", file=sys.stderr)
        sys.exit(3)

    if not data:
        print("Error: Empty response from Google Translate.", file=sys.stderr)
        sys.exit(4)

    translated = flatten_translation(data[0])
    if not translated:
        print("Error: No translation returned.", file=sys.stderr)
        sys.exit(5)
    return translated


def main() -> None:
    text, target, source = parse_args()
    translation = request_translation(text, target, source)
    sys.stdout.write(translation)


if __name__ == "__main__":
    main()
