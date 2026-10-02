#!/usr/bin/env python3
"""
test_applauncher_regression.py — Regression test for Fuzzy.scoreLegacy

Executes the actual Fuzzy.scoreLegacy function from services/Fuzzy.qml via the
Qt 6 QML runtime (qml6), mirroring AppLauncher.qml's exact field weighting:
  - app.name: 1.0x
  - app.genericName: 0.8x
  - app.keywords: 0.5x

Compares top 5 results across 18 benchmark queries against the committed baseline
in tests/fixtures/applauncher_baseline.json (derived from the original fuzzyScore
implementation before the refactor).
"""

import json
import os
import subprocess
import sys
import tempfile

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FUZZY_PATH = os.path.join(REPO_ROOT, "services", "Fuzzy.qml")
FIXTURE_PATH = os.path.join(REPO_ROOT, "tests", "fixtures", "apps.json")
BASELINE_PATH = os.path.join(REPO_ROOT, "tests", "fixtures", "applauncher_baseline.json")

def main():
    print("=== AppLauncher Regression Test (Real QML Engine via qml6) ===")
    
    if not os.path.isfile(FUZZY_PATH):
        print(f"ERROR: Fuzzy.qml not found at {FUZZY_PATH}", file=sys.stderr)
        sys.exit(1)
    if not os.path.isfile(FIXTURE_PATH):
        print(f"ERROR: Fixture apps.json not found at {FIXTURE_PATH}", file=sys.stderr)
        sys.exit(1)
    if not os.path.isfile(BASELINE_PATH):
        print(f"ERROR: Baseline not found at {BASELINE_PATH}", file=sys.stderr)
        sys.exit(1)

    with open(BASELINE_PATH, "r", encoding="utf-8") as f:
        baseline = json.load(f)

    with open(FUZZY_PATH, "r", encoding="utf-8") as f:
        fuzzy_content = f.read()

    # Strip 'pragma Singleton' so qml6 can instantiate it directly
    fuzzy_no_singleton = fuzzy_content.replace("pragma Singleton", "// pragma Singleton")

    with tempfile.TemporaryDirectory() as tmpdir:
        fuzzy_tmp_file = os.path.join(tmpdir, "FuzzyTest.qml")
        with open(fuzzy_tmp_file, "w", encoding="utf-8") as f:
            f.write(fuzzy_no_singleton)

        harness_file = os.path.join(tmpdir, "harness.qml")
        harness_content = f"""import QtQuick

Item {{
    id: root

    FuzzyTest {{
        id: fuzzy
    }}

    function scoreApp(q, app) {{
        let maxScore = -1;
        const nameScore = fuzzy.scoreLegacy(q, app.name);
        if (nameScore > maxScore) maxScore = nameScore;
        if (app.genericName) {{
            const gScore = fuzzy.scoreLegacy(q, app.genericName);
            if (gScore !== -1 && (gScore * 0.8) > maxScore) {{
                maxScore = gScore * 0.8;
            }}
        }}
        if (app.keywords) {{
            for (let k = 0; k < app.keywords.length; k++) {{
                const kScore = fuzzy.scoreLegacy(q, app.keywords[k]);
                if (kScore !== -1 && (kScore * 0.5) > maxScore) {{
                    maxScore = kScore * 0.5;
                }}
            }}
        }}
        return maxScore;
    }}

    Component.onCompleted: {{
        const xhr = new XMLHttpRequest();
        xhr.open("GET", "file://{FIXTURE_PATH}", false);
        xhr.send();
        const apps = JSON.parse(xhr.responseText);

        const queries = {json.dumps(list(baseline.keys()))};

        for (let qi = 0; qi < queries.length; qi++) {{
            const q = queries[qi];
            const scored = [];
            for (let i = 0; i < apps.length; i++) {{
                const s = scoreApp(q, apps[i]);
                if (s !== -1) {{
                    scored.push({{ name: apps[i].name, score: s }});
                }}
            }}
            scored.sort((a, b) => b.score - a.score);
            const top5 = scored.slice(0, 5);
            console.log("RESULT_ITEM:" + q + ":" + JSON.stringify(top5));
        }}

        Qt.quit();
    }}
}}
"""
        with open(harness_file, "w", encoding="utf-8") as f:
            f.write(harness_content)

        env = dict(os.environ)
        env["QML_XHR_ALLOW_FILE_READ"] = "1"
        env["QT_QPA_PLATFORM"] = "offscreen"

        try:
            res = subprocess.run(
                ["qml6", harness_file],
                cwd=tmpdir,
                env=env,
                capture_output=True,
                text=True,
                timeout=10,
                check=True
            )
        except Exception as e:
            print(f"ERROR: Failed to run qml6 harness: {e}", file=sys.stderr)
            sys.exit(1)

        output = res.stdout + res.stderr
        test_results = {}
        for line in output.splitlines():
            if "RESULT_ITEM:" in line:
                part = line[line.find("RESULT_ITEM:") + len("RESULT_ITEM:"):].strip()
                q, json_part = part.split(":", 1)
                test_results[q] = json.loads(json_part)

    # Compare against baseline
    mismatches = 0
    total_queries = len(baseline)

    print(f"Comparing {total_queries} queries against baseline...")
    for q, expected in baseline.items():
        actual = test_results.get(q, [])
        query_mismatch = False

        if len(expected) != len(actual):
            query_mismatch = True
        else:
            for exp_item, act_item in zip(expected, actual):
                if exp_item["name"] != act_item["name"] or abs(exp_item["score"] - act_item["score"]) > 1e-4:
                    query_mismatch = True
                    break

        if query_mismatch:
            mismatches += 1
            print(f"  [FAIL] Query: '{q}'")
            print(f"         Expected: {expected}")
            print(f"         Actual:   {actual}")
        else:
            top_names = [item["name"] for item in actual]
            print(f"  [PASS] Query: '{q:5s}' -> {top_names}")

    print("-" * 60)
    if mismatches == 0:
        print(f"SUCCESS: All {total_queries}/{total_queries} queries produced 100% identical top 5 rankings and scores!")
        sys.exit(0)
    else:
        print(f"FAILURE: {mismatches}/{total_queries} queries differed from baseline.", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
