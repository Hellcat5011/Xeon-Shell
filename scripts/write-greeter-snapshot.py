#!/usr/bin/env python3
import sys
import os
import json
import argparse

STATE_DIR = os.environ.get("GREETER_STATE_DIR", "/var/lib/greetd/quickshell-greeter")
CONF_FILE = os.path.join(STATE_DIR, "config-snapshot.json")
LAST_USER_FILE = os.path.join(STATE_DIR, "last-user")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--alignment", required=True, choices=["left", "right"])
    parser.add_argument("--remember", required=True, type=lambda x: x.lower() == "true")
    args = parser.parse_args()

    if not os.path.isdir(STATE_DIR) or not os.access(STATE_DIR, os.W_OK):
        print(f"ERROR: Cannot write to {STATE_DIR}. Are you in the greeter-sync group?", file=sys.stderr)
        sys.exit(1)

    config = {
        "lockscreenAlignment": args.alignment,
        "rememberLastUser": args.remember
    }

    try:
        temp_file = CONF_FILE + ".tmp"
        with open(temp_file, "w") as f:
            json.dump(config, f, indent=2)
            f.write("\n")
        os.chmod(temp_file, 0o664)
        os.rename(temp_file, CONF_FILE)
    except Exception as e:
        print(f"ERROR: failed to write {CONF_FILE}: {e}", file=sys.stderr)
        sys.exit(1)

    if not args.remember:
        if os.path.exists(LAST_USER_FILE):
            try:
                os.remove(LAST_USER_FILE)
            except Exception as e:
                print(f"ERROR: failed to delete {LAST_USER_FILE}: {e}", file=sys.stderr)
                sys.exit(1)

if __name__ == "__main__":
    main()
