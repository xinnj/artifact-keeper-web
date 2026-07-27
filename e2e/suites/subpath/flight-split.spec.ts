import { test, expect } from "@playwright/test";

/**
 * Regression tests for the split-placeholder ChunkLoadError on the runtime
 * sub-path deployment.
 *
 * The build bakes `basePath=/__AK_BASE_PATH__`; entrypoint.sh (mirrored by
 * e2e/scripts/start-subpath-server.sh) merges adjacent RSC flight frames so the
 * placeholder is contiguous, then sed-replaces it with `/ak`. If a future
 * flight-chunker change re-splits the placeholder, the invariant test below
 * fails, and the navigation test catches the runtime ChunkLoadError.
 *
 * Note: since the nonce-based CSP reads `headers()` in the root layout (#674),
 * page routes are dynamically rendered (no prerendered flight), so the original
 * "single merged frame" assertion no longer applies — the invariant is now
 * "join every flight frame and assert the placeholder never reassembles".
 */

test("served HTML contains no residual __AK_BASE_PATH__ placeholder", async ({
  request,
}) => {
  // /ak/migration is the route that originally hit the split (its inline RSC
  // flight split the placeholder for chunk 0r-7gmjwv2m~_.js across two frames).
  for (const path of ["/ak/migration", "/ak/login"]) {
    const resp = await request.get(path);
    expect(resp.status(), `${path} should return 200`).toBe(200);
    const html = await resp.text();
    expect(
      html,
      `${path} must not serve the __AK_BASE_PATH__ placeholder`,
    ).not.toContain("__AK_BASE_PATH__");

    // A placeholder split across flight frames survives as partial fragments
    // (`"/__AK_B` + `ASE_PATH__/`), invisible to the check above. Concatenate
    // every `self.__next_f.push([1,"…"])` frame exactly as the browser's RSC
    // stream reader does, then look for the reassembled token. Dynamic routes
    // (the current default — the nonce CSP reads `headers()`, which opts every
    // route out of prerendering) emit several frames, so this no longer asserts
    // a single merged frame; joining them must still never reveal a placeholder.
    const flight = [
      ...html.matchAll(/self\.__next_f\.push\(\[1,"([\s\S]*?)"\]\)/g),
    ]
      .map((m) => m[1])
      .join("");
    expect(
      flight,
      `${path} must not contain a split __AK_BASE_PATH__ placeholder`,
    ).not.toContain("__AK_BASE_PATH__");
  }
});

test("chunks load under /ak/_next and the page mounts without ChunkLoadError", async ({
  page,
}) => {
  const badChunkUrls: string[] = [];
  const errors: string[] = [];

  page.on("request", (req) => {
    const url = req.url();
    // A chunk requested from outside /ak/_next means a placeholder survived sed.
    if (url.includes("/_next/static/") && !url.includes("/ak/_next/")) {
      badChunkUrls.push(url);
    }
  });
  page.on("pageerror", (err) => errors.push(err.message));
  page.on("console", (msg) => {
    if (msg.type() === "error") errors.push(msg.text());
  });

  await page.goto("/ak/login", { waitUntil: "networkidle" });

  expect(badChunkUrls, "all chunks must be requested under /ak/_next").toEqual(
    [],
  );

  const fatal = errors.filter((e) =>
    /ChunkLoadError|Failed to load chunk|Connection closed/.test(e),
  );
  expect(fatal, "no ChunkLoadError / failed-chunk / connection-closed").toEqual(
    [],
  );

  // The login page actually mounted (client hydration completed).
  await expect(page.getByPlaceholder("Enter your username")).toBeVisible();
});
