import { test, expect } from "@playwright/test";

/**
 * Regression tests for the empty-body trailing-slash root bug.
 *
 * With `skipTrailingSlashRedirect: true` (required so the Docker `GET /v2/`
 * reaches the middleware without a 308 — see next.config.ts), Next.js serves
 * the root route at `<basePath>/` (e.g. `/ak/`) with an empty 200 body once the
 * root layout opts into dynamic rendering via `headers()` (nonce-based CSP,
 * #674). The middleware now normalizes `<basePath>/` → `<basePath>` before
 * routing (see src/middleware.ts). These tests lock in that redirect so a
 * future upstream bump re-breaking the interaction fails loudly instead of
 * silently serving a blank page.
 */

test("GET /ak/ redirects to /ak and serves the dashboard HTML", async ({
  request,
}) => {
  const resp = await request.get("/ak/");

  // The trailing-slash root must be normalized to /ak (307 → /ak), not left at
  // /ak/ serving an empty body. `request` follows redirects, so the final URL
  // is /ak on success and stays /ak/ if the redirect regresses.
  expect(resp.url().endsWith("/ak")).toBe(true);

  const html = await resp.text();
  expect(html).toContain("<!DOCTYPE html>");
  expect(html.length).toBeGreaterThan(1000);
});

test("browser navigation to /ak/ lands on the dashboard", async ({ page }) => {
  await page.goto("/ak/");

  // The dashboard mounted (the empty body has no DOM to find). "Recent
  // Repositories" is the dashboard's always-rendered card title and does not
  // appear on the login page.
  await expect(page.getByText("Recent Repositories")).toBeVisible();
});
