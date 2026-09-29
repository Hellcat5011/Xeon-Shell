#!/usr/bin/env python3
import json
import urllib.request
import sys

def main():
    try:
        req = urllib.request.Request(
            'http://ip-api.com/json/',
            headers={'User-Agent': 'Mozilla/5.0'}
        )
        with urllib.request.urlopen(req, timeout=5) as r:
            data = json.loads(r.read())
            if 'lat' in data and 'lon' in data:
                print(f"{data['lat']},{data['lon']}")
            else:
                print("Error: Invalid response format", file=sys.stderr)
                sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
