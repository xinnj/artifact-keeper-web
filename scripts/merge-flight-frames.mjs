/**
 * Merge adjacent RSC flight frames in a prerendered HTML file.
 *
 * Next.js emits the inline flight data for a statically prerendered page as a
 * sequence of `self.__next_f.push([1,"…"])` script frames. The flight chunker
 * splits the JSON string at arbitrary byte boundaries, which can land *inside*
 * a token like `/__AK_BASE_PATH__`, leaving it split across two frames:
 *
 *     …"/__AK_B"])</script><script>self.__next_f.push([1,"ASE_PATH__/…
 *
 * The entrypoint's sed pass only does contiguous matches, so a split token is
 * never rewritten and its chunk URL 404s at runtime (ChunkLoadError).
 *
 * The browser concatenates every `__next_f.push` frame, so removing the
 * inter-frame separator is lossless: the token becomes contiguous and sed can
 * then rewrite it. Only the inline `[1,…]` (flight-data) frames are joined; the
 * `<script>`/`</script>` wrapper of the first frame is preserved, so the merged
 * result remains valid, executable JS.
 */

export const SEPARATOR =
  /"]\)\s*<\/script>\s*<script>\s*self\.__next_f\.push\(\[1,"/g;

export function mergeFlightFrames(html) {
  return html.replace(SEPARATOR, "");
}

// CLI: merge one or more files in place (no-op when unchanged).
import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const isMain =
  process.argv[1] &&
  import.meta.url === pathToFileURL(resolve(process.argv[1])).href;

if (isMain) {
  let exitCode = 0;
  for (const file of process.argv.slice(2)) {
    try {
      const before = readFileSync(file, "utf8");
      const after = mergeFlightFrames(before);
      if (after !== before) {
        writeFileSync(file, after);
      }
    } catch (err) {
      process.stderr.write(`merge-flight-frames: ${file}: ${err.message}\n`);
      exitCode = 1;
    }
  }
  process.exit(exitCode);
}
