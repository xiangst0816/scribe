#!/usr/bin/env bash
# Install repo-managed git hooks into .git/hooks/. Idempotent — re-running
# replaces stale symlinks. Each hook is a symlink so future edits to
# scripts/hooks/ take effect immediately without re-installing.

set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
src_dir="$repo_root/scripts/hooks"
dst_dir="$repo_root/.git/hooks"

mkdir -p "$dst_dir"

for src in "$src_dir"/*; do
    name=$(basename "$src")
    dst="$dst_dir/$name"
    chmod +x "$src"
    ln -sf "../../scripts/hooks/$name" "$dst"
    echo "✓ installed $name → $dst"
done

echo
echo "Hooks installed. Run 'git commit' on a change touching the polish prompt"
echo "or related files to trigger the eval; bypass with SKIP_POLISH_EVAL=1."
