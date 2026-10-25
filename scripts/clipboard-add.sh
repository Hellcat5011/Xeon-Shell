#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# clipboard-add.sh — Adds a clipboard entry to history with security filters
# ─────────────────────────────────────────────────────────────────────────────
TYPE=$1
CACHE_DIR="$HOME/.cache/quickshell-clipboard"
IMAGE_DIR="$CACHE_DIR/images"
HISTORY_FILE="$CACHE_DIR/history.json"
MAX_ITEMS=50
ID=$(date +%s%N)
TIMESTAMP=$(date +%s)   # epoch seconds for expiry checks
LOCK_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/qs-clipboard-self.lock"

# ── Lock-file check ──────────────────────────────────────────────────────────
# If the lock file exists, this clipboard event was self-initiated by the shell
# (e.g. clipboard manager copy, emoji paste, screenshot copy). Consume the
# lock and exit without adding a duplicate entry to history.
if [ -f "$LOCK_FILE" ]; then
    rm -f "$LOCK_FILE"
    exit 0
fi

# Ensure directories exist
mkdir -p "$IMAGE_DIR"

# Initialize JSON if not exists
if [ ! -s "$HISTORY_FILE" ]; then
    echo "[]" > "$HISTORY_FILE"
fi

# ── Sensitive-content heuristics ─────────────────────────────────────────────
# Returns 0 (true) if the content appears to be sensitive and should be skipped.
is_sensitive() {
    local content="$1"

    # SSH / PGP private keys
    if echo "$content" | grep -qE '-----BEGIN[[:space:]]+(RSA|DSA|EC|OPENSSH|PGP|GPG|ENCRYPTED)?[[:space:]]*PRIVATE KEY-----'; then
        echo "clipboard-add.sh: skipped sensitive content (private key)" >&2
        return 0
    fi

    # Password-like key=value patterns (case-insensitive)
    if echo "$content" | grep -qiE '(^|[&?; ])(password|passwd|pass|pwd|secret|token|api_key|apikey|api_secret|auth_token|access_token|refresh_token)[[:space:]]*[=:][[:space:]]*\S'; then
        echo "clipboard-add.sh: skipped sensitive content (password/token pattern)" >&2
        return 0
    fi

    # Bearer tokens
    if echo "$content" | grep -qE 'Bearer[[:space:]]+[A-Za-z0-9_.\-]+'; then
        echo "clipboard-add.sh: skipped sensitive content (bearer token)" >&2
        return 0
    fi

    # Well-known API key prefixes
    # AWS access key IDs (AKIA...), GitHub PATs (ghp_, gho_, ghs_, ghr_),
    # GitLab PATs (glpat-), Slack tokens (xox[bpas]-), Stripe keys (sk_live_, pk_live_),
    # OpenAI keys (sk-...)
    if echo "$content" | grep -qE '(AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36}|gho_[A-Za-z0-9]{36}|ghs_[A-Za-z0-9]{36}|ghr_[A-Za-z0-9]{36}|glpat-[A-Za-z0-9\-]{20,}|xox[bpas]-[A-Za-z0-9\-]+|sk_live_[A-Za-z0-9]+|pk_live_[A-Za-z0-9]+|sk-[A-Za-z0-9]{20,})'; then
        echo "clipboard-add.sh: skipped sensitive content (API key)" >&2
        return 0
    fi

    # Credit/debit card numbers: 13-19 digit sequences (with optional spaces/dashes)
    # Strip separators, then check for 13-19 digit string and Luhn validity
    local stripped
    stripped=$(echo "$content" | tr -d ' \t\n-')
    if echo "$stripped" | grep -qE '^[0-9]{13,19}$'; then
        if luhn_check "$stripped"; then
            echo "clipboard-add.sh: skipped sensitive content (card number)" >&2
            return 0
        fi
    fi

    # Also check for card numbers embedded in longer text
    local card_candidate
    card_candidate=$(echo "$content" | grep -oE '[0-9][ 0-9\-]{11,22}[0-9]' | head -1)
    if [ -n "$card_candidate" ]; then
        stripped=$(echo "$card_candidate" | tr -d ' \t\n-')
        if echo "$stripped" | grep -qE '^[0-9]{13,19}$'; then
            if luhn_check "$stripped"; then
                echo "clipboard-add.sh: skipped sensitive content (embedded card number)" >&2
                return 0
            fi
        fi
    fi

    # High-entropy hex strings (≥40 chars of hex, no spaces — likely hashes/secrets)
    if echo "$content" | grep -qE '^[0-9a-fA-F]{40,}$'; then
        echo "clipboard-add.sh: skipped sensitive content (high-entropy hex)" >&2
        return 0
    fi

    # Connection strings with credentials
    if echo "$content" | grep -qiE '(mysql|postgres|postgresql|mongodb|redis|amqp|smtp|ftp)://[^:]+:[^@]+@'; then
        echo "clipboard-add.sh: skipped sensitive content (connection string with credentials)" >&2
        return 0
    fi

    return 1
}

# Luhn checksum validation for card numbers
luhn_check() {
    local num="$1"
    local len=${#num}
    local sum=0
    local alt=0
    local i digit

    for (( i = len - 1; i >= 0; i-- )); do
        digit=${num:$i:1}
        if (( alt == 1 )); then
            digit=$(( digit * 2 ))
            if (( digit > 9 )); then
                digit=$(( digit - 9 ))
            fi
        fi
        sum=$(( sum + digit ))
        alt=$(( 1 - alt ))
    done

    (( sum % 10 == 0 ))
}

if [ "$TYPE" = "text" ]; then
    CONTENT=$(cat)
    
    # Ignore empty strings
    if [ -z "$CONTENT" ]; then
        exit 0
    fi

    # ── Sensitive content filter ──────────────────────────────────────────
    if is_sensitive "$CONTENT"; then
        exit 0
    fi

    # Deduplication logic
    # Get the most recent text item's content
    LAST_CONTENT=$(jq -r 'map(select(.isImage == false)) | .[0].content // empty' "$HISTORY_FILE")
    
    # If the new content is exactly the same as the last content, don't add it
    if [ "$CONTENT" == "$LAST_CONTENT" ]; then
        exit 0
    fi
    
    JSON_ITEM=$(jq -n --arg id "$ID" --arg content "$CONTENT" --argjson ts "$TIMESTAMP" '{id: $id, isImage: false, content: $content, timestamp: $ts}')
    
elif [ "$TYPE" = "image" ]; then
    IMAGE_PATH="$IMAGE_DIR/clip-$ID.png"
    cat > "$IMAGE_PATH"
    
    # Check if the image is valid
    if [ ! -s "$IMAGE_PATH" ]; then
        rm -f "$IMAGE_PATH"
        exit 0
    fi
    
    JSON_ITEM=$(jq -n --arg id "$ID" --arg path "file://$IMAGE_PATH" --argjson ts "$TIMESTAMP" '{id: $id, isImage: true, content: "", imagePath: $path, timestamp: $ts}')
else
    exit 1
fi

# Prepend and limit to MAX_ITEMS
jq --argjson item "$JSON_ITEM" --arg max "$MAX_ITEMS" '([$item] + .) | .[0:($max|tonumber)]' "$HISTORY_FILE" > "${HISTORY_FILE}.tmp" && mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
