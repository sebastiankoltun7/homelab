#!/usr/bin/env bash
set -euo pipefail

ITEM_NAME="$1"
JQ_FILTER="$2"

command -v bw >/dev/null 2>&1 || { echo "Bitwarden CLI (bw) not found. Run 'mise install' first." >&2; exit 1; }

if [ -z "${BW_SESSION:-}" ]; then
    export BW_SESSION="$(bw unlock --raw)"
fi

VAL=$(bw list items --search "$ITEM_NAME" | jq -r "if type == \"array\" then .[0] else . end | $JQ_FILTER // empty")

if [ -z "$VAL" ] || [ "$VAL" = "null" ]; then
    echo "Error: Failed to fetch '$ITEM_NAME' from Bitwarden or requested field is empty." >&2
    exit 1
fi

echo "$VAL"