#!/usr/bin/env bash
set -euo pipefail

# Boot the standalone server on a runtime sub-path, mirroring what entrypoint.sh
# does in the production image (merge RSC flight frames, then sed-replace the
# __AK_BASE_PATH__ placeholder). Used by playwright-subpath.config.ts.

SUBPATH_BASE_PATH="${SUBPATH_BASE_PATH:-/ak}"
PORT="${SUBPATH_WEB_PORT:-3010}"
HOSTNAME="${SUBPATH_HOSTNAME:-127.0.0.1}"
BACKEND_URL="${BACKEND_URL:-http://127.0.0.1:9999}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_DIR"

echo "subpath-server: building with NEXT_PUBLIC_BASE_PATH=/__AK_BASE_PATH__"
NEXT_PUBLIC_BASE_PATH=/__AK_BASE_PATH__ npm run build

# The standalone output does not include public/ or .next/static; the Dockerfile
# copies them in separately, so mirror that here.
cp -r .next/static .next/standalone/.next/static
cp -r public .next/standalone/public
cp -r scripts .next/standalone/scripts

cd .next/standalone

# 1. Merge adjacent RSC flight frames so a placeholder split across a frame
#    boundary becomes contiguous (mirrors entrypoint.sh).
find . -name "*.html" -not -path "*/node_modules/*" \
  -exec node ./scripts/merge-flight-frames.mjs {} +

# 2. sed-replace the placeholder everywhere (mirrors entrypoint.sh's BASE_PATH
#    branch, including the URL-encoded `%2F__AK_BASE_PATH__` forms).
BASE_PATH="${SUBPATH_BASE_PATH%/}"
FILES=$(find . -type f -not -path "*/node_modules/*" \
  \( -name "*.js" \
  -o -name "*.mjs" \
  -o -name "*.json" \
  -o -name "*.html" \
  -o -name "*.css" \
  -o -name "*.map" \
  -o -name "*.rsc" \
  \))
ENCODED_BP=$(printf '%s' "${BASE_PATH#/}" | sed 's|/|%2F|g')

echo "$FILES" | while IFS= read -r f; do
  sed "s|/__AK_BASE_PATH__|$BASE_PATH|g" "$f" > /tmp/subpath_tmp \
    && cat /tmp/subpath_tmp > "$f"
  sed "s|%2F__AK_BASE_PATH__%2F|%2F${ENCODED_BP}%2F|g" "$f" > /tmp/subpath_tmp \
    && cat /tmp/subpath_tmp > "$f"
  sed "s|%2F__AK_BASE_PATH__|%2F${ENCODED_BP}|g" "$f" > /tmp/subpath_tmp \
    && cat /tmp/subpath_tmp > "$f"
done
rm -f /tmp/subpath_tmp

# 3. Fail loudly if the fix didn't fully apply (mirrors entrypoint.sh): no
#    full placeholder may survive, and every page must have a single merged
#    flight frame (a split placeholder hides in the residual frames otherwise).
echo "$FILES" | node -e '
  const fs = require("fs");
  const files = fs.readFileSync(0, "utf8").trim().split("\n").filter(Boolean);
  let bad = 0;
  for (const f of files) {
    const s = fs.readFileSync(f, "utf8");
    if (s.includes("__AK_BASE_PATH__")) {
      console.error("subpath-server: residual __AK_BASE_PATH__ in " + f);
      bad++;
    }
    if (f.endsWith(".html")) {
      const frames = s.split("self.__next_f.push([1,").length - 1;
      if (frames > 1) {
        console.error("subpath-server: unmerged flight frames (" + frames + ") in " + f);
        bad++;
      }
    }
  }
  process.exit(bad ? 1 : 0);
'

echo "subpath-server: starting on http://${HOSTNAME}:${PORT} at base path ${BASE_PATH}"
HOSTNAME="$HOSTNAME" PORT="$PORT" BACKEND_URL="$BACKEND_URL" exec node server.js
