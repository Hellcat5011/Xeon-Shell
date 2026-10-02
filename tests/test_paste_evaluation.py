#!/usr/bin/env python3
"""
tests/test_paste_evaluation.py — Real-Path Emoji Paste & Focus Restoration Test

Drives the real picker path:
  capture window -> show overlay -> debugSelect -> hideNow() -> paste-emoji.sh
against live scratch windows (Ghostty Wayland terminal and XTerm XWayland client).

Measures focus restoration polling durations and drop rates across floor delays:
  0 ms, 20 ms, 40 ms, 70 ms.

Requires --yes flag. Restores initial workspace and focus on exit.
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHELL_PATH = os.path.join(REPO_ROOT, "shell.qml")
STATE_DIR = os.path.expanduser("~/.local/state/quickshell-emoji")
LOG_PATH = os.path.join(STATE_DIR, "paste.log")

def get_hypr_active():
    try:
        ws_out = subprocess.check_output(["hyprctl", "activeworkspace", "-j"], text=True)
        ws_id = json.loads(ws_out).get("id", 1)
    except Exception:
        ws_id = 1
    try:
        win_out = subprocess.check_output(["hyprctl", "activewindow", "-j"], text=True)
        win_addr = json.loads(win_out).get("address", "")
    except Exception:
        win_addr = ""
    return ws_id, win_addr

def hypr_focus_window(addr):
    cmd = f"hl.dsp.focus({{ window = 'address:{addr}' }})"
    subprocess.run(["hyprctl", "dispatch", cmd], capture_output=True, text=True)

def hypr_focus_workspace(ws_id):
    cmd = f"hl.dsp.focus({{ workspace = {ws_id} }})"
    subprocess.run(["hyprctl", "dispatch", cmd], capture_output=True, text=True)

def wait_for_focus(addr, timeout=2.0):
    start = time.time()
    while time.time() - start < timeout:
        _, curr = get_hypr_active()
        if curr == addr:
            return True
        hypr_focus_window(addr)
        time.sleep(0.04)
    return False

def get_client_by_title(title):
    try:
        out = subprocess.check_output(["hyprctl", "clients", "-j"], text=True)
        clients = json.loads(out)
        for c in clients:
            if title in c.get("title", ""):
                return c
    except Exception:
        pass
    return None

def read_last_log_line():
    if not os.path.isfile(LOG_PATH):
        return ""
    try:
        with open(LOG_PATH, "r", encoding="utf-8", errors="replace") as f:
            lines = f.readlines()
            return lines[-1].strip() if lines else ""
    except Exception:
        return ""

def main():
    parser = argparse.ArgumentParser(description="Real-path emoji paste and focus restore evaluation")
    parser.add_argument("--yes", action="store_true", help="Confirm execution of real UI paste test")
    parser.add_argument("--floor-delays", default="0,20,40,70", help="Comma-separated floor delays in ms to test")
    parser.add_argument("--iterations", type=int, default=20, help="Iterations per target per delay (default: 20)")
    args = parser.parse_args()

    if not args.yes:
        print("""
=============================================================================
NOTICE: test_paste_evaluation.py requires explicit confirmation via --yes.
Usage: python3 tests/test_paste_evaluation.py --yes

What this test does:
  1. Captures your current workspace and active window for exact restoration.
  2. Spawns scratch test windows:
     - Ghostty (Wayland terminal) running an unbuffered reader
     - XTerm (XWayland client) running an unbuffered reader
  3. Launches a dedicated repo-path Quickshell instance (qs -p shell.qml) with
     XEON_EMOJI_DEBUG=1.
  4. Runs 20 real-path selections per window target across floor delays
     (0ms, 20ms, 40ms, 70ms) to evaluate drop rates and focus restoration timing.
  5. Tests rapid selections (5 consecutive), copy-only mode, and empty workspace.
  6. Terminates all scratch processes and restores your workspace and focus.
=============================================================================
""")
        sys.exit(1)

    print("=== Real-Path Emoji Paste & Focus Restoration Test ===")
    initial_ws, initial_win = get_hypr_active()
    print(f"Initial State: Workspace {initial_ws}, Window {initial_win}")

    delays = [int(d.strip()) for d in args.floor_delays.split(",") if d.strip().isdigit()]
    iterations = args.iterations
    scratch_procs = []
    shell_proc = None

    # Helper script for scratch terminals to write unbuffered stdin to file
    with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as tf:
        tf.write("""
import sys, tty, termios
out_path = sys.argv[1]
fd = sys.stdin.fileno()
old = termios.tcgetattr(fd)
f = open(out_path, "a", encoding="utf-8", buffering=1)
try:
    tty.setcbreak(fd)
    while True:
        ch = sys.stdin.read(1)
        if not ch: break
        f.write(ch)
        f.flush()
finally:
    termios.tcsetattr(fd, termios.TCSADRAIN, old)
    f.close()
""")
        reader_script = tf.name

    ghostty_out_file = "/tmp/emoji_test_ghostty.txt"
    xterm_out_file = "/tmp/emoji_test_xterm.txt"
    for p in [ghostty_out_file, xterm_out_file]:
        if os.path.exists(p):
            os.remove(p)

    matrix_results = {}
    wayland_failures = False

    try:
        # 1. Launch scratch Ghostty window
        print("Launching scratch Ghostty window...")
        g_proc = subprocess.Popen(
            ["ghostty", "--title=EmojiGhosttyScratch", "-e", "python3", reader_script, ghostty_out_file],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        scratch_procs.append(g_proc)

        # 2. Launch scratch XTerm window (if xterm available)
        x_proc = None
        if subprocess.run(["which", "xterm"], capture_output=True).returncode == 0:
            print("Launching scratch XTerm window (XWayland)...")
            x_proc = subprocess.Popen(
                ["xterm", "-title", "EmojiXTermScratch", "-e", "python3", reader_script, xterm_out_file],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
            scratch_procs.append(x_proc)

        # Wait for scratch windows to appear in Hyprland
        time.sleep(2.0)
        ghostty_client = None
        xterm_client = None
        for _ in range(25):
            if not ghostty_client:
                ghostty_client = get_client_by_title("EmojiGhosttyScratch")
            if x_proc and not xterm_client:
                xterm_client = get_client_by_title("EmojiXTermScratch")
            if ghostty_client and (not x_proc or xterm_client):
                break
            time.sleep(0.3)

        if not ghostty_client:
            print("ERROR: Scratch Ghostty window failed to map in Hyprland.", file=sys.stderr)
            sys.exit(1)
        print(f"  Ghostty mapped: {ghostty_client['address']} ({ghostty_client['class']})")
        if xterm_client:
            print(f"  XTerm mapped:   {xterm_client['address']} ({xterm_client['class']})")

        targets = [("Ghostty (Wayland)", ghostty_client, ghostty_out_file, True)]
        if xterm_client:
            targets.append(("XTerm (XWayland)", xterm_client, xterm_out_file, False))

        # 3. Test across floor delays
        for delay in delays:
            print(f"\n=======================================================")
            print(f"  Evaluating Floor Delay: {delay} ms ({iterations} iterations per target)")
            print(f"=======================================================")

            # Kill any existing repo shell instance
            subprocess.run(["pkill", "-f", f"qs -p {SHELL_PATH}"], capture_output=True)
            time.sleep(1.0)

            # Start shell with this floor delay
            shell_env = os.environ.copy()
            shell_env["XEON_EMOJI_DEBUG"] = "1"
            shell_env["FOCUS_FLOOR_DELAY_MS"] = str(delay)
            shell_proc = subprocess.Popen(
                ["qs", "-p", SHELL_PATH],
                env=shell_env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
            time.sleep(2.5)  # Wait for shell QML init

            for target_name, client, out_file, expects_stdin_readback in targets:
                target_addr = client["address"]
                target_class = client["class"]
                polls = []
                drops = 0

                print(f"\n  Target: {target_name} [{target_addr}]")
                for it in range(1, iterations + 1):
                    # Clear target file before paste
                    with open(out_file, "w") as f:
                        f.write("")

                    # 1. Ensure target window is genuinely focused before opening picker
                    if not wait_for_focus(target_addr):
                        print(f"    WARNING: Focus timeout for {target_name} on iter {it}")

                    # 2. Open picker (drives deterministic window capture before show)
                    subprocess.run(["qs", "ipc", "--pid", str(shell_proc.pid), "call", "emoji", "open"], capture_output=True, check=True)
                    time.sleep(0.12)

                    # 3. Debug select (drives hideNow -> paste-emoji.sh)
                    emoji_test_glyph = "✨"
                    subprocess.run(["qs", "ipc", "--pid", str(shell_proc.pid), "call", "emoji", "debugSelect", emoji_test_glyph, "paste"], capture_output=True, check=True)

                    # Wait for paste script to finish
                    time.sleep(0.15 + (delay / 1000.0))

                    # Verify log line
                    log_line = read_last_log_line()
                    success_log = ("Successfully pasted" in log_line) and ("source=qml" in log_line) and (target_addr in log_line)

                    # Verify character landed on target stdin if supported by client
                    received = True
                    if expects_stdin_readback:
                        time.sleep(0.05)
                        try:
                            with open(out_file, "r", encoding="utf-8", errors="replace") as f:
                                content = f.read()
                        except Exception:
                            content = ""
                        received = emoji_test_glyph in content

                    # Extract poll duration
                    poll_ms = 0
                    if "poll=" in log_line:
                        try:
                            poll_part = log_line.split("poll=")[1].split("ms")[0]
                            poll_ms = int(poll_part)
                        except Exception:
                            pass

                    if success_log and received:
                        polls.append(poll_ms)
                    else:
                        drops += 1
                        print(f"    [DROP #{it}] log_ok={success_log}, char_received={received} | log: {log_line}")

                min_p = min(polls) if polls else 0
                avg_p = (sum(polls) / len(polls)) if polls else 0
                max_p = max(polls) if polls else 0
                drop_rate = (drops / iterations) * 100.0

                print(f"    Summary ({target_name} @ {delay}ms delay):")
                print(f"      Delivered: {len(polls)}/{iterations} (Drop Rate: {drop_rate:.1f}%)")
                print(f"      Poll Duration: min={min_p}ms, avg={avg_p:.1f}ms, max={max_p}ms")

                matrix_results[(target_name, delay)] = {
                    "delivered": len(polls),
                    "total": iterations,
                    "drops": drops,
                    "drop_rate": drop_rate,
                    "min_poll": min_p,
                    "avg_poll": avg_p,
                    "max_poll": max_p
                }

                if expects_stdin_readback and delay == 40 and drops > 0:
                    wayland_failures = True

            # Terminate shell for next delay
            shell_proc.terminate()
            try:
                shell_proc.wait(timeout=3)
            except Exception:
                shell_proc.kill()
            shell_proc = None

        # 4. Special cases verification using delay=40ms
        print("\n=======================================================")
        print("  Evaluating Special Edge Cases (Floor Delay: 40ms)")
        print("=======================================================")
        shell_env = os.environ.copy()
        shell_env["XEON_EMOJI_DEBUG"] = "1"
        shell_env["FOCUS_FLOOR_DELAY_MS"] = "40"
        shell_proc = subprocess.Popen(
            ["qs", "-p", SHELL_PATH],
            env=shell_env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        time.sleep(2.5)

        # A. Rapid consecutive selections (5 in under 1 second)
        print("  Case 1: Rapid Consecutive Selections (5 in under 1s)...")
        target_addr = ghostty_client["address"]
        wait_for_focus(target_addr)
        subprocess.run(["qs", "ipc", "--pid", str(shell_proc.pid), "call", "emoji", "open"], capture_output=True, check=True)
        time.sleep(0.08)
        rapid_glyphs = ["1️⃣", "2️⃣", "3️⃣", "4️⃣", "5️⃣"]
        for g in rapid_glyphs:
            subprocess.run(["qs", "ipc", "--pid", str(shell_proc.pid), "call", "emoji", "debugSelect", g, "paste"], capture_output=True, check=True)
            time.sleep(0.08)
        time.sleep(0.5)
        with open(ghostty_out_file, "r", encoding="utf-8", errors="replace") as f:
            rapid_content = f.read()
        print(f"    Rapid output received in Ghostty: {repr(rapid_content)}")
        assert all(g in rapid_content for g in rapid_glyphs), "Expected all rapid glyphs in Ghostty"
        print("    ✓ Rapid selections processed without deadlock.")

        # B. Copy-only mode
        print("  Case 2: Copy-Only Mode...")
        subprocess.run(["qs", "ipc", "--pid", str(shell_proc.pid), "call", "emoji", "debugSelect", "📋", "copy-only"], capture_output=True, check=True)
        time.sleep(0.1)
        log_copy = read_last_log_line()
        assert "copy-only mode requested" in log_copy
        print(f"    ✓ Log: {log_copy}")

        # C. Empty workspace case (sentinel 'none' / source=qml no-target)
        print("  Case 3: Empty Workspace (source=qml no-target)...")
        hypr_focus_workspace(99)
        time.sleep(0.2)
        subprocess.run(["qs", "ipc", "--pid", str(shell_proc.pid), "call", "emoji", "open"], capture_output=True, check=True)
        time.sleep(0.15)
        subprocess.run(["qs", "ipc", "--pid", str(shell_proc.pid), "call", "emoji", "debugSelect", "🛑", "paste"], capture_output=True, check=True)
        time.sleep(0.1)
        log_empty = read_last_log_line()
        print(f"    ✓ Empty Workspace Log: {log_empty}")
        assert ("source=qml no-target" in log_empty), f"Expected 'source=qml no-target' in log, got: {log_empty}"

    finally:
        # Clean up scratch processes
        print("\nCleaning up scratch processes...")
        if shell_proc:
            shell_proc.terminate()
            try:
                shell_proc.wait(timeout=2)
            except Exception:
                shell_proc.kill()
        for p in scratch_procs:
            p.terminate()
            try:
                p.wait(timeout=2)
            except Exception:
                p.kill()

        if os.path.exists(reader_script):
            os.remove(reader_script)

        # Restore initial workspace and window
        print(f"Restoring initial state: Workspace {initial_ws}, Window {initial_win}...")
        hypr_focus_workspace(initial_ws)
        if initial_win:
            hypr_focus_window(initial_win)

    # Print Full Comparative Results Table
    print("\n" + "=" * 78)
    print("              REAL-PATH PASTE & FLOOR DELAY EVALUATION RESULTS")
    print("=" * 78)
    print(f"{'Target Window':<20} | {'Delay':<7} | {'Delivered':<11} | {'Drop Rate':<10} | {'Poll (min/avg/max)':<20}")
    print("-" * 78)
    for (target_name, delay), res in matrix_results.items():
        poll_str = f"{res['min_poll']}ms / {res['avg_poll']:.1f}ms / {res['max_poll']}ms"
        print(f"{target_name:<20} | {delay:>4} ms | {res['delivered']}/{res['total']:<8} | {res['drop_rate']:>6.1f} %  | {poll_str:<20}")
    print("=" * 78)

    if wayland_failures:
        print("FAILURE: Pastes were dropped in Ghostty at the 40ms default floor delay.", file=sys.stderr)
        sys.exit(1)
    else:
        print("SUCCESS: Full real-path test passed!")
        sys.exit(0)

if __name__ == "__main__":
    main()
