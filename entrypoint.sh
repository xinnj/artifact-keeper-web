#!/bin/sh
set -e

BASE_PATH="${BASE_PATH:-}"
BASE_PATH="${BASE_PATH%/}"

echo "entrypoint: copying /app to /tmp/app"
rm -rf /tmp/app
mkdir -p /tmp/app
cp -r /app/. /tmp/app/
chmod -R u+w /tmp/app

cd /tmp/app

# Merge adjacent RSC flight frames before the sed pass below.
#
# Next.js emits a prerendered page's inline flight data as many
# `self.__next_f.push([1,"…"])` frames, chunked at arbitrary byte boundaries.
# A split can land *inside* the `__AK_BASE_PATH__` placeholder, leaving it split
# across two frames (`…"/__AK_B"` + `"ASE_PATH__/…`). sed only matches
# contiguous strings, so without this merge the split fragment survives and its
# chunk URL 404s at runtime (ChunkLoadError). The browser concatenates every
# frame, so dropping the inter-frame separator is lossless.
find . -name "*.html" -not -path "*/node_modules/*" \
  -exec node ./scripts/merge-flight-frames.mjs {} +

# Replace the placeholder everywhere it appears in the standalone output.
# Search the entire tree (not just .next/) because server.js and other root
# files also contain the compiled basePath.  Exclude node_modules since
# Next.js vendored code could have false matches.
#
# Next.js's Image component generates optimized image URLs with the path
# URL-encoded (e.g. %2F__AK_BASE_PATH__%2Flogo-48.png), so we must handle
# both literal-slash and percent-encoded forms of the placeholder.
FILES=$(find . -type f \
  -not -path "*/node_modules/*" \
  \( -name "*.js" \
  -o -name "*.mjs" \
  -o -name "*.json" \
  -o -name "*.html" \
  -o -name "*.css" \
  -o -name "*.map" \
  -o -name "*.rsc" \
  \))

if [ -n "$BASE_PATH" ]; then
  echo "entrypoint: setting base path to $BASE_PATH"

  # URL-encoded version of the base path (without leading slash)
  ENCODED_BP=$(printf '%s' "${BASE_PATH#/}" | sed 's|/|%2F|g')

  echo "$FILES" | while IFS= read -r f; do
    # Literal-slash form: /__AK_BASE_PATH__… → $BASE_PATH…
    sed "s|/__AK_BASE_PATH__|$BASE_PATH|g" "$f" > /tmp/ak_entrypoint_tmp \
      && cat /tmp/ak_entrypoint_tmp > "$f"
    # Percent-encoded form: %2F__AK_BASE_PATH__%2F… → %2F<encoded-bp>%2F…
    sed "s|%2F__AK_BASE_PATH__%2F|%2F${ENCODED_BP}%2F|g" "$f" > /tmp/ak_entrypoint_tmp \
      && cat /tmp/ak_entrypoint_tmp > "$f"
    # Edge case: percent-encoded prefix only (no trailing %2F)
    sed "s|%2F__AK_BASE_PATH__|%2F${ENCODED_BP}|g" "$f" > /tmp/ak_entrypoint_tmp \
      && cat /tmp/ak_entrypoint_tmp > "$f"
  done
else
  echo "entrypoint: no base path set, removing placeholder"
  echo "$FILES" | while IFS= read -r f; do
    # Literal-slash forms
    sed 's|/__AK_BASE_PATH__/|/|g' "$f" > /tmp/ak_entrypoint_tmp \
      && cat /tmp/ak_entrypoint_tmp > "$f"
    sed 's|/__AK_BASE_PATH__||g' "$f" > /tmp/ak_entrypoint_tmp \
      && cat /tmp/ak_entrypoint_tmp > "$f"
    # Percent-encoded forms
    sed 's|%2F__AK_BASE_PATH__%2F|%2F|g' "$f" > /tmp/ak_entrypoint_tmp \
      && cat /tmp/ak_entrypoint_tmp > "$f"
    sed 's|%2F__AK_BASE_PATH__||g' "$f" > /tmp/ak_entrypoint_tmp \
      && cat /tmp/ak_entrypoint_tmp > "$f"
  done
fi

# Fail loudly if the fix didn't fully apply. Two independent invariants:
#   1. No full `__AK_BASE_PATH__` placeholder may survive the sed pass.
#   2. No `.html` may still have >1 flight frame (i.e. the merge above must have
#      collapsed every page to a single `self.__next_f.push([1,…])` frame).
# A residual placeholder or unmerged frames become a runtime ChunkLoadError
# (404 on a chunk URL), far worse than failing the pod at startup.
echo "$FILES" | node -e '
  const fs = require("fs");
  const files = fs.readFileSync(0, "utf8").trim().split("\n").filter(Boolean);
  let bad = 0;
  for (const f of files) {
    const s = fs.readFileSync(f, "utf8");
    if (s.includes("__AK_BASE_PATH__")) {
      console.error("entrypoint: residual __AK_BASE_PATH__ in " + f);
      bad++;
    }
    if (f.endsWith(".html")) {
      const frames = s.split("self.__next_f.push([1,").length - 1;
      if (frames > 1) {
        console.error("entrypoint: unmerged flight frames (" + frames + ") in " + f);
        bad++;
      }
    }
  }
  process.exit(bad ? 1 : 0);
' || {
  echo "entrypoint: ERROR: residual placeholder or unmerged flight frames (see above)" >&2
  exit 1
}

rm -f /tmp/ak_entrypoint_tmp

SERVER_JS=$(find . -name server.js -not -path "*/node_modules/*" -print -quit)
if [ -z "$SERVER_JS" ]; then
  echo "entrypoint: ERROR: server.js not found" >&2
  exit 1
fi

echo "entrypoint: starting server ($SERVER_JS)"
exec node "$SERVER_JS"