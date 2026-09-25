#!/usr/bin/env python3
"""Build a compact, offline emoji catalog from official Unicode data files."""

import json
import re
import sys
from pathlib import Path


def annotations(path):
    payload = json.loads(Path(path).read_text(encoding="utf-8"))
    table = (payload.get("annotations") or payload["annotationsDerived"])["annotations"]
    # CLDR keys drop the U+FE0F variation selector that fully-qualified
    # emoji carry (❤ vs ❤️, ❤‍🔥 vs ❤️‍🔥); normalize both sides.
    return {strip_variation(key): value for key, value in table.items()}


def strip_variation(emoji):
    return emoji.replace("\ufe0f", "")


def main():
    if len(sys.argv) not in (5, 7):
        raise SystemExit(
            "usage: generate_emoji_catalog.py emoji-test.txt ja.json en.json output.json"
            " [ja-derived.json en-derived.json]"
        )

    emoji_test, japanese_path, english_path, output_path = sys.argv[1:5]
    japanese = annotations(japanese_path)
    english = annotations(english_path)
    # Derived annotations cover skin-tone and gendered sequences (🙅‍♀️).
    if len(sys.argv) == 7:
        japanese = {**annotations(sys.argv[5]), **japanese}
        english = {**annotations(sys.argv[6]), **english}
    catalog = []
    seen = set()
    expression = re.compile(r"^([0-9A-F ]+)\s*;\s*fully-qualified\s*#\s*(\S+)\s+E[0-9.]+\s+(.+)$")

    for line in Path(emoji_test).read_text(encoding="utf-8").splitlines():
        match = expression.match(line)
        if not match:
            continue
        emoji = match.group(2)
        if emoji in seen:
            continue
        seen.add(emoji)
        japanese_entry = japanese.get(strip_variation(emoji), {})
        english_entry = english.get(strip_variation(emoji), {})
        japanese_name = (japanese_entry.get("tts") or [""])[0]
        english_name = (english_entry.get("tts") or [match.group(3)])[0]
        japanese_keywords = japanese_entry.get("default") or []
        english_keywords = english_entry.get("default") or []
        catalog.append({
            "emoji": emoji,
            "name": japanese_name or english_name,
            "englishName": english_name,
            "keywords": list(dict.fromkeys(japanese_keywords + english_keywords)),
        })

    output = Path(output_path)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(catalog, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"Wrote {len(catalog)} emoji to {output}")


if __name__ == "__main__":
    main()
