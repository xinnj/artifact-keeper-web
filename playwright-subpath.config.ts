import { defineConfig } from "@playwright/test";

/**
 * Dedicated config for the runtime sub-path deployment (commit c1a55987).
 *
 * Builds the app with the `__AK_BASE_PATH__` placeholder, then boots the
 * standalone server through `e2e/scripts/start-subpath-server.sh`, which mirrors
 * `entrypoint.sh` (merge RSC flight frames + sed-replace the placeholder) so the
 * app is served at `/ak`.
 *
 * Kept separate from playwright.config.ts because that config targets the
 * docker-compose stack (real backend) at the root path; this suite needs a
 * placeholder build on a sub-path and intentionally has no backend.
 */

const WEB_PORT = Number(process.env.SUBPATH_WEB_PORT ?? 3010);
const BASE_URL = `http://127.0.0.1:${WEB_PORT}`;

export default defineConfig({
  testDir: "./e2e/suites/subpath",
  fullyParallel: false,
  workers: 1,
  retries: process.env.CI ? 1 : 0,
  forbidOnly: !!process.env.CI,
  reporter: [["list"]],
  expect: { timeout: 10_000 },
  timeout: 30_000,
  use: {
    baseURL: BASE_URL,
    trace: "on-first-retry",
  },
  webServer: {
    command: "bash e2e/scripts/start-subpath-server.sh",
    url: `${BASE_URL}/ak/login`,
    reuseExistingServer: !process.env.CI,
    timeout: 240_000,
    env: {
      SUBPATH_BASE_PATH: "/ak",
      SUBPATH_WEB_PORT: String(WEB_PORT),
      SUBPATH_HOSTNAME: "127.0.0.1",
      NODE_ENV: "production",
    },
  },
});
