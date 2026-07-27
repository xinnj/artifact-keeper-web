/**
 * Returns the configured UI base path prefix.
 *
 * At container startup, entrypoint.sh replaces the build-time placeholder
 * (/__AK_BASE_PATH__) with the runtime BASE_PATH env var value in all
 * compiled .next/ output files.
 *
 * When no base path is configured, returns "" (app serves at root).
 */
export function getBasePath(): string {
  return process.env.NEXT_PUBLIC_BASE_PATH || "";
}
