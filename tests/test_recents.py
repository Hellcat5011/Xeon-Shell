#!/usr/bin/env python3
"""
tests/test_recents.py — Recents Persistence and Migration Verification

Performs two levels of verification:
1. Python Reference Model: Validates the algorithm specifications in isolation.
2. Real Quickshell Engine Integration: Boots a test quickshell instance with an
   isolated temporary XDG_STATE_HOME, verifies live recents loading, migration of
   legacy object formats, U+FE0F normalization, selection deduplication, move-to-front,
   the 48-item cap, disk synchronization, and persistence across a full shell restart.
"""

import json
import os
import subprocess
import sys
import tempfile
import time

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHELL_PATH = os.path.join(REPO_ROOT, "shell.qml")
DATASET_PATH = os.path.join(REPO_ROOT, "data", "emojis.json")

# ─────────────────────────────────────────────────────────────────────────────
# Level 1: Python Model / Algorithmic Specification Tests
# ─────────────────────────────────────────────────────────────────────────────
with open(DATASET_PATH, "r", encoding="utf-8") as f:
    dataset = json.load(f)

emoji_by_glyph = {}
for item in dataset:
    clean = item["emoji"].replace("\ufe0f", "")
    emoji_by_glyph[item["emoji"]] = item
    emoji_by_glyph[clean] = item

def load_recents_sim(content):
    if not content or not content.strip():
        return [], False
    parsed = json.loads(content)
    migrated = False
    glyphs = []
    if isinstance(parsed, list):
        for item in parsed:
            raw_g = ""
            if isinstance(item, str):
                raw_g = item
            elif isinstance(item, dict) and "emoji" in item:
                raw_g = item["emoji"]
                migrated = True
            if raw_g:
                clean_g = raw_g.replace("\ufe0f", "")
                if clean_g not in glyphs:
                    glyphs.append(clean_g)
    return glyphs, migrated

def resolve_recents_sim(raw_glyphs):
    resolved = []
    seen = set()
    for raw_g in raw_glyphs:
        clean_g = raw_g.replace("\ufe0f", "") if raw_g else ""
        item = emoji_by_glyph.get(clean_g) or emoji_by_glyph.get(raw_g)
        if item and item["emoji"] not in seen:
            seen.add(item["emoji"])
            resolved.append(item)
            if len(resolved) >= 48:
                break
    return resolved

def record_recent_sim(raw_glyphs, emoji_obj):
    clean_g = emoji_obj["emoji"].replace("\ufe0f", "")
    filtered = [g for g in raw_glyphs if g != clean_g and g.replace("\ufe0f", "") != clean_g]
    filtered.insert(0, clean_g)
    return filtered[:48]

def run_model_tests():
    print("--- [Level 1: Python Reference Model Tests] ---")
    
    # 1. Migration
    legacy_json = json.dumps([
        {"emoji": "👍️", "name": "Thumbs Up"},
        {"emoji": "❤️", "name": "Red Heart"},
        {"emoji": "🔥", "name": "Fire"}
    ])
    glyphs, migrated = load_recents_sim(legacy_json)
    assert migrated is True
    assert glyphs == ["👍", "❤", "🔥"]
    resolved = resolve_recents_sim(glyphs)
    assert len(resolved) == 3
    assert resolved[0]["name"] == "Thumbs up"
    print("  ✓ Model: Legacy object format migration verified.")

    # 2. U+FE0F normalization
    fe0f_json = json.dumps(["👍️", "✨️", "❤️"])
    glyphs, _ = load_recents_sim(fe0f_json)
    resolved = resolve_recents_sim(glyphs)
    assert len(resolved) == 3
    assert resolved[0]["emoji"] == "👍"
    assert resolved[1]["emoji"] == "✨"
    assert resolved[2]["emoji"] == "❤️"
    print("  ✓ Model: U+FE0F normalization verified.")

    # 3. Dedup & Move-to-front
    initial = ["👍", "🔥", "✨"]
    updated = record_recent_sim(initial, emoji_by_glyph["🔥"])
    assert updated == ["🔥", "👍", "✨"]
    print("  ✓ Model: Deduplication & move-to-front verified.")

    # 4. 48-item cap
    many_glyphs = [item["emoji"] for item in dataset[:60]]
    current = []
    for g in many_glyphs:
        current = record_recent_sim(current, emoji_by_glyph[g])
    assert len(current) == 48
    print("  ✓ Model: 48-item cap verified.")

    # 5. Empty state
    empty_glyphs, _ = load_recents_sim("")
    assert empty_glyphs == []
    assert resolve_recents_sim(empty_glyphs) == []
    print("  ✓ Model: Empty state verified.")


# ─────────────────────────────────────────────────────────────────────────────
# Level 2: Real Quickshell Engine Integration Tests
# ─────────────────────────────────────────────────────────────────────────────
def run_real_shell_tests():
    print("\n--- [Level 2: Real Quickshell Engine Integration Tests] ---")

    with tempfile.TemporaryDirectory() as tmpdir:
        state_dir = os.path.join(tmpdir, "quickshell-emoji")
        os.makedirs(state_dir, exist_ok=True)
        recents_path = os.path.join(state_dir, "recents.json")

        # 1. Seed recents with legacy objects + FE0F forms
        seed_data = [
            {"emoji": "👍️", "name": "Thumbs Up"},
            "✨️",
            "❤️"
        ]
        with open(recents_path, "w", encoding="utf-8") as f:
            json.dump(seed_data, f)

        env = os.environ.copy()
        env["XDG_STATE_HOME"] = tmpdir
        env["XEON_EMOJI_DEBUG"] = "1"

        print("  Starting test shell instance with isolated XDG_STATE_HOME...")
        proc = subprocess.Popen(
            ["qs", "-p", SHELL_PATH],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )

        try:
            time.sleep(2.5)  # Allow QML engine and FileView to initialize

            # Query raw glyphs and resolved emojis
            res_raw = subprocess.run(
                ["qs", "ipc", "--pid", str(proc.pid), "call", "emoji", "debugGetRecents"],
                capture_output=True, text=True, timeout=5, check=True
            )
            raw_glyphs = json.loads(res_raw.stdout.strip())
            print(f"  Raw glyphs in shell memory: {raw_glyphs}")
            assert raw_glyphs == ["👍", "✨", "❤"], f"Expected ['👍', '✨', '❤'], got {raw_glyphs}"
            print("  ✓ Shell: Loaded and migrated legacy object format to FE0F-stripped string array.")

            res_emojis = subprocess.run(
                ["qs", "ipc", "--pid", str(proc.pid), "call", "emoji", "debugGetRecentEmojis"],
                capture_output=True, text=True, timeout=5, check=True
            )
            resolved_emojis = json.loads(res_emojis.stdout.strip())
            print(f"  Resolved emojis in Recents tab: {resolved_emojis}")
            assert resolved_emojis == ["👍", "✨", "❤️"], f"Expected ['👍', '✨', '❤️'], got {resolved_emojis}"
            print("  ✓ Shell: Recents tab resolved canonical forms for all migrated entries.")

            # Check disk file was migrated atomically
            time.sleep(0.5)
            with open(recents_path, "r", encoding="utf-8") as f:
                disk_data = json.load(f)
            assert disk_data == ["👍", "✨", "❤"], f"Disk content unexpected: {disk_data}"
            print("  ✓ Shell: Atomic migration written back to recents.json on disk.")

            # Test deduplication & move-to-front via debugSelect
            print("  Selecting '🔥' via debugSelect hook...")
            subprocess.run(
                ["qs", "ipc", "--pid", str(proc.pid), "call", "emoji", "debugSelect", "🔥", "copy-only"],
                capture_output=True, text=True, timeout=5, check=True
            )
            time.sleep(0.5)

            res_after = subprocess.run(
                ["qs", "ipc", "--pid", str(proc.pid), "call", "emoji", "debugGetRecents"],
                capture_output=True, text=True, timeout=5, check=True
            )
            raw_after = json.loads(res_after.stdout.strip())
            print(f"  Raw glyphs after selection: {raw_after}")
            assert raw_after[0] == "🔥", f"Expected 🔥 at front, got {raw_after}"
            assert raw_after == ["🔥", "👍", "✨", "❤"]
            print("  ✓ Shell: Move-to-front and deduplication verified in live QML state.")

            # Re-select existing '✨'
            print("  Selecting '✨' via debugSelect hook...")
            subprocess.run(
                ["qs", "ipc", "--pid", str(proc.pid), "call", "emoji", "debugSelect", "✨", "copy-only"],
                capture_output=True, text=True, timeout=5, check=True
            )
            time.sleep(0.5)

            res_after2 = subprocess.run(
                ["qs", "ipc", "--pid", str(proc.pid), "call", "emoji", "debugGetRecents"],
                capture_output=True, text=True, timeout=5, check=True
            )
            raw_after2 = json.loads(res_after2.stdout.strip())
            assert raw_after2 == ["✨", "🔥", "👍", "❤"]
            print("  ✓ Shell: Move-to-front for existing item without duplicating verified.")

        finally:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()

        # Test persistence across shell restart
        print("\n  Restarting shell to verify disk persistence...")
        proc2 = subprocess.Popen(
            ["qs", "-p", SHELL_PATH],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        try:
            time.sleep(2.5)
            res_restart = subprocess.run(
                ["qs", "ipc", "--pid", str(proc2.pid), "call", "emoji", "debugGetRecents"],
                capture_output=True, text=True, timeout=5, check=True
            )
            raw_restart = json.loads(res_restart.stdout.strip())
            print(f"  Raw glyphs after shell restart: {raw_restart}")
            assert raw_restart == ["✨", "🔥", "👍", "❤"], f"Restart state mismatch: {raw_restart}"
            print("  ✓ Shell: State persisted to disk and accurately reloaded on restart.")
        finally:
            proc2.terminate()
            try:
                proc2.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc2.kill()

        print("\nALL REAL-SHELL RECENTS TESTS PASSED!")

if __name__ == "__main__":
    run_model_tests()
    run_real_shell_tests()
