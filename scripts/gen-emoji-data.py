#!/usr/bin/env python3
"""
gen-emoji-data.py
Builds data/emojis.json from pinned emojibase-data 16.0.0 (Unicode 16.0 + CLDR annotations).

Requirements:
  - Python 3.9+
  - fontTools (pip install fontTools or pacman -S python-fonttools)
  - Network access on first run to download pinned emojibase dataset (cached locally afterwards)

Canonical U+FE0F Normalization Rule:
  In Unicode UTS #51, characters have either emoji-default or text-default presentation:
  1. Single codepoint characters with Emoji_Presentation=False (emojibase type: 0,
     such as red heart ❤ U+2764, smiling face ☺ U+263A, airplane ✈ U+2708):
     These REQUIRE U+FE0F (Variation Selector-16) to ensure emoji presentation
     and avoid rendering as black-and-white text glyphs in standard fonts.
  2. Single codepoint characters with Emoji_Presentation=True (emojibase type: 1,
     such as thumbs up 👍 U+1F44D, sparkles ✨ U+2728, fire 🔥 U+1F525):
     These DROP trailing U+FE0F because their default presentation is already
     emoji. Dropping redundant U+FE0F ensures canonical clipboard payloads,
     consistent recents lookup, and uniform search matching.
  3. Multi-codepoint sequences (e.g. ZWJ sequences like ❤️‍🔥 and keycaps like #️⃣):
     These are constructed directly from hexcode, preserving necessary internal
     variation selectors and joiners.

Features:
  - Pinned SHA-256 validation for reproducible, deterministic builds.
  - Caches raw downloads locally in scripts/.cache/ to allow offline regeneration.
  - Filters for base emojis only (drops Group 2 Component, drops skin-tone variants U+1F3FB..U+1F3FF).
  - Validates all component codepoints against NotoColorEmoji.ttf cmap.
  - Generates proper sentence-cased display names (avoiding title() contractions like "Woman'S Hat").
  - Merges GitHub shortcodes into keywordsLc and hand-curated colloquial aliases into aliasesLc.
  - Normalizes alias keys and asserts 100% key resolution against dataset entries.
  - Outputs compact JSON with precomputed lowercase search fields.
"""

import hashlib
import json
import os
import sys
import urllib.request
from fontTools.ttLib import TTFont

EMOJIBASE_DATA_URL = "https://unpkg.com/emojibase-data@16.0.0/en/data.json"
EMOJIBASE_DATA_SHA256 = "8cbf636f6b28476065e847360691ca8a6767ed328d3223f9eead4e5c09e61f04"

EMOJIBASE_GITHUB_URL = "https://unpkg.com/emojibase-data@16.0.0/en/shortcodes/github.json"
EMOJIBASE_GITHUB_SHA256 = "d6bb7101e7bab1e52b30f4b3562da2319b484a6266352a1119f0d1ba52db23db"

FONT_PATH = "/usr/share/fonts/noto/NotoColorEmoji.ttf"

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT_PATH = os.path.join(REPO_ROOT, "data", "emojis.json")
ALIASES_PATH = os.path.join(REPO_ROOT, "data", "emoji-aliases.json")
CACHE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".cache")

GROUP_NAMES = {
    0: "Smileys & Emotion",
    1: "People & Body",
    3: "Animals & Nature",
    4: "Food & Drink",
    5: "Travel & Places",
    6: "Activities",
    7: "Objects",
    8: "Symbols",
    9: "Flags",
}

SKIN_MODIFIERS = {"1F3FB", "1F3FC", "1F3FD", "1F3FE", "1F3FF"}
IGNORED_COMPONENTS = {0x200D, 0xFE0F, 0x20E3}  # ZWJ, variation selector, enclosing keycap

def fetch_cached(url, expected_sha256, filename):
    os.makedirs(CACHE_DIR, exist_ok=True)
    cache_file = os.path.join(CACHE_DIR, filename)

    if os.path.exists(cache_file):
        with open(cache_file, "rb") as f:
            content = f.read()
        digest = hashlib.sha256(content).hexdigest()
        if digest == expected_sha256:
            print(f"Using cached {filename} (SHA-256 verified).")
            return json.loads(content.decode("utf-8"))
        print(f"Cached {filename} hash mismatch, re-downloading...")

    print(f"Downloading {url}...")
    req = urllib.request.Request(url, headers={"User-Agent": "XeonShell/1.0"})
    with urllib.request.urlopen(req, timeout=15) as resp:
        content = resp.read()

    digest = hashlib.sha256(content).hexdigest()
    if digest != expected_sha256:
        raise ValueError(f"Checksum mismatch for {url}! Expected {expected_sha256}, got {digest}")

    with open(cache_file, "wb") as f:
        f.write(content)

    print(f"Downloaded and cached {filename} successfully.")
    return json.loads(content.decode("utf-8"))

def sentence_case(text):
    if not text:
        return ""
    text = text.strip()
    return text[0].upper() + text[1:]

def main():
    print(f"Loading font cmap from {FONT_PATH}...")
    if not os.path.exists(FONT_PATH):
        raise FileNotFoundError(f"Font file not found: {FONT_PATH}")
    font = TTFont(FONT_PATH)
    cmap = font.getBestCmap()

    raw_data = fetch_cached(EMOJIBASE_DATA_URL, EMOJIBASE_DATA_SHA256, "emojibase_data_16.0.0.json")
    github_shortcodes = fetch_cached(EMOJIBASE_GITHUB_URL, EMOJIBASE_GITHUB_SHA256, "emojibase_github_16.0.0.json")

    # Load manual aliases and normalize keys by stripping U+FE0F
    aliases = {}
    if os.path.exists(ALIASES_PATH):
        with open(ALIASES_PATH, "r", encoding="utf-8") as f:
            raw_aliases = json.load(f)
        for k, v in raw_aliases.items():
            clean_k = k.replace("\ufe0f", "")
            aliases[clean_k] = v
        print(f"Loaded {len(aliases)} manual emoji alias sets (normalized keys).")

    print(f"Processing {len(raw_data)} raw entries...")

    emojis = []
    dropped_component = 0
    dropped_skin = 0
    dropped_missing_glyph = 0
    matched_alias_keys = set()
    normalized_glyph_count = 0

    for item in raw_data:
        group_id = item.get("group")
        if group_id not in GROUP_NAMES:
            dropped_component += 1
            continue

        hexcode = item.get("hexcode", "")
        hex_parts = hexcode.split("-")

        # Exclude skin-tone modifiers explicitly
        if any(p in SKIN_MODIFIERS for p in hex_parts):
            dropped_skin += 1
            continue

        # Validate component codepoints against font cmap
        missing_component = False
        for p in hex_parts:
            cp = int(p, 16)
            if cp not in IGNORED_COMPONENTS and cp not in cmap:
                missing_component = True
                break

        if missing_component:
            dropped_missing_glyph += 1
            continue

        category = GROUP_NAMES[group_id]
        raw_label = item.get("label", "")
        name = sentence_case(raw_label)
        raw_emoji = item.get("emoji", "")
        raw_type = item.get("type", 1)

        # Decide canonical glyph according to presentation default rule
        if len(hex_parts) == 1:
            cp = int(hex_parts[0], 16)
            if raw_type == 0:
                # Text-default presentation requires U+FE0F for emoji presentation
                canonical_emoji = chr(cp) + "\ufe0f"
            else:
                # Emoji-default presentation drops trailing U+FE0F
                canonical_emoji = chr(cp)
        else:
            # Multi-codepoint sequences retain required internal variation selectors
            canonical_emoji = "".join(chr(int(h, 16)) for h in hex_parts)

        if canonical_emoji != raw_emoji:
            normalized_glyph_count += 1

        tags = item.get("tags", [])
        keywords_lc = []
        for t in tags:
            t_lc = t.strip().lower()
            if t_lc and t_lc not in keywords_lc:
                keywords_lc.append(t_lc)

        # Merge GitHub shortcodes (string or list of strings) into keywordsLc
        gh_codes = github_shortcodes.get(hexcode)
        if gh_codes:
            if isinstance(gh_codes, str):
                gh_codes = [gh_codes]
            for code in gh_codes:
                clean_code = code.replace("_", " ").strip().lower()
                if clean_code and clean_code not in keywords_lc:
                    keywords_lc.append(clean_code)

        # Separate manual aliases into dedicated aliasesLc field
        clean_glyph = canonical_emoji.replace("\ufe0f", "")
        aliases_lc = []
        if clean_glyph in aliases:
            matched_alias_keys.add(clean_glyph)
            for alias in aliases[clean_glyph]:
                alias_lc = alias.strip().lower()
                if alias_lc and alias_lc not in aliases_lc:
                    aliases_lc.append(alias_lc)

        entry = {
            "emoji": canonical_emoji,
            "name": name,
            "category": category,
            "nameLc": raw_label.lower(),
            "keywordsLc": keywords_lc,
            "aliasesLc": aliases_lc,
            "categoryLc": category.lower(),
        }
        emojis.append(entry)

    # Assert that all alias keys in data/emoji-aliases.json matched an entry
    unmatched_aliases = [k for k in aliases if k not in matched_alias_keys]
    if unmatched_aliases:
        print(f"ERROR: {len(unmatched_aliases)} alias keys did not match any emoji entry: {unmatched_aliases}", file=sys.stderr)
        sys.exit(1)
    else:
        print(f"Assert passed: All {len(aliases)} alias keys matched entries in dataset.")

    print(f"Filtering complete:")
    print(f" - Dropped components/unknown: {dropped_component}")
    print(f" - Dropped skin variants: {dropped_skin}")
    print(f" - Dropped missing glyphs: {dropped_missing_glyph}")
    print(f" - Normalized canonical glyphs (FE0F adjusted): {normalized_glyph_count}")
    print(f" - Total curated emojis: {len(emojis)}")

    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
    # Output compact JSON without indent
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(emojis, f, ensure_ascii=False, separators=(",", ":"))

    size_kb = os.path.getsize(OUTPUT_PATH) / 1024
    print(f"Successfully wrote {len(emojis)} emojis to {OUTPUT_PATH} ({size_kb:.1f} KB)")

if __name__ == "__main__":
    main()
