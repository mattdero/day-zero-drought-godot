#!/usr/bin/env bash
# export_and_serve.sh — Export the Godot Web build and start the test server.
#
# Usage:
#   ./export_and_serve.sh            # export + HTTP server
#   ./export_and_serve.sh --https    # export + HTTPS (for mobile testing)
#   ./export_and_serve.sh --no-export --https  # skip export, just (re)start server
#
# Any extra flags after the first argument are forwarded to serve.py.

set -euo pipefail

GODOT="/c/Users/mpder/Downloads/Godot_v4.6.1-stable_win64.exe/Godot_v4.6.1-stable_win64.exe"
PRESET="Web"
OUT_DIR="export/web"
OUT_FILE="$OUT_DIR/index.html"
SKIP_EXPORT=false
SERVE_ARGS=()

# Parse args — pull out --no-export, pass the rest to serve.py
for arg in "$@"; do
    if [[ "$arg" == "--no-export" ]]; then
        SKIP_EXPORT=true
    else
        SERVE_ARGS+=("$arg")
    fi
done

# Move to the project root (directory containing this script)
cd "$(dirname "$0")"

if [[ "$SKIP_EXPORT" == false ]]; then
    echo ""
    echo "==> Checking Godot executable..."
    if [[ ! -f "$GODOT" ]]; then
        echo "    ERROR: Godot not found at: $GODOT"
        echo "    Edit GODOT= in this script to point to your Godot 4 executable."
        exit 1
    fi

    echo "==> Checking Web export templates..."
    TEMPLATES_BASE="$HOME/AppData/Roaming/Godot/export_templates"
    TEMPLATES_DIR=$(ls -d "$TEMPLATES_BASE/4.6"* 2>/dev/null | sort -V | tail -1 || true)
    if [[ -z "$TEMPLATES_DIR" || ! -d "$TEMPLATES_DIR" ]]; then
        echo ""
        echo "    ERROR: Godot Web export templates not found."
        echo ""
        echo "    Install them inside the Godot editor:"
        echo "      Editor → Export → Manage Export Templates → Download and Install"
        echo ""
        echo "    Or download 'Godot_v4.6.x_export_templates.tpz' from"
        echo "    https://godotengine.org/download and install via the editor."
        exit 1
    fi
    echo "    Found templates: $TEMPLATES_DIR"

    echo "==> Creating output directory: $OUT_DIR"
    mkdir -p "$OUT_DIR"

    echo "==> Exporting preset '$PRESET'..."
    "$GODOT" --headless --export-release "$PRESET" "$OUT_FILE"
    echo "    Export complete: $OUT_DIR/"
fi

echo ""
echo "==> Starting web server..."
python3 serve.py "${SERVE_ARGS[@]}"
