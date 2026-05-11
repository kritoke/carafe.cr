#!/bin/bash
# safe-spec: Global detached, non-blocking spec runner for Crystal
# Prevents AI provider hangs during long compilations.
# Usage: safe-spec [spec_file_pattern]

set -e

AIWORKFLOW_DIR="/Users/kritoke/code/projects/aiworkflow"
SAFE_SPEC_SRC="$AIWORKFLOW_DIR/safe-spec.sh"

# Find project root (look for shard.yml, spec_helper.cr, or src/)
find_project_root() {
    local current_dir="$PWD"
    while [ "$current_dir" != "/" ]; do
        if [ -f "$current_dir/shard.yml" ] || [ -f "$current_dir/spec_helper.cr" ] || [ -f "$current_dir/src" ]; then
            echo "$current_dir"
            return 0
        fi
        current_dir="$(dirname "$current_dir")"
    done
    echo "$PWD"  # Fallback to current directory
}

PROJECT_DIR="$(find_project_root)"
cd "$PROJECT_DIR"

echo "=== Safe Spec (Global) ==="
echo "Project: $PROJECT_DIR"
echo ""

# 1. Cleanup old zombie processes
echo "[CLEANUP] Cleaning up old crystal processes..."
pkill -9 -f crystal > /dev/null 2>&1 || true
rm -f spec_out.txt

# 2. Fast Checks (Foreground)
echo "[FORMAT] Running Crystal format..."
crystal tool format

echo "[LINT] Running Ameba..."
ameba --format progress

# 3. Heavy Lift (Detached)
echo "[SPEC] Compiling and Running Specs (Detached)..."
(nohup crystal spec --no-color "$@" > spec_out.txt 2>&1 &)

# 4. The Wait & Peek
echo "[WAIT] Waiting 10s for LLVM optimization..."
sleep 10
echo "------------------------------------------------"
cat spec_out.txt
echo "------------------------------------------------"
echo "[HINT] If results are missing, run 'cat spec_out.txt' in 5 seconds."
