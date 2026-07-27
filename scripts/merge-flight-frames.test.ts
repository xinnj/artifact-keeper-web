import { describe, it, expect } from "vitest";
import { mergeFlightFrames } from "./merge-flight-frames.mjs";

describe("mergeFlightFrames", () => {
  it("joins a placeholder split across two frames (tight separator)", () => {
    const html =
      '<script>self.__next_f.push([1,"foo/__AK_B"])</script><script>self.__next_f.push([1,"ASE_PATH__/bar"])</script>';
    expect(mergeFlightFrames(html)).toBe(
      '<script>self.__next_f.push([1,"foo/__AK_BASE_PATH__/bar"])</script>',
    );
  });

  it("joins when the separator has whitespace/newlines between the tags", () => {
    const html =
      '<script>self.__next_f.push([1,"a/__AK_B"])\n</script>\n<script>\nself.__next_f.push([1,"ASE_PATH__/b"])</script>';
    expect(mergeFlightFrames(html)).toBe(
      '<script>self.__next_f.push([1,"a/__AK_BASE_PATH__/b"])</script>',
    );
  });

  it("leaves non-flight HTML untouched", () => {
    const html =
      '<link rel="preload" href="/__AK_BASE_PATH__/_next/static/x.js"/>';
    expect(mergeFlightFrames(html)).toBe(html);
  });

  it("is a no-op for a single (already-merged) frame", () => {
    const html =
      '<script>self.__next_f.push([1,"only/__AK_BASE_PATH__/one"])</script>';
    expect(mergeFlightFrames(html)).toBe(html);
  });

  it("merges multiple consecutive frames into one", () => {
    const html =
      '<script>self.__next_f.push([1,"A"])</script><script>self.__next_f.push([1,"/__AK_B"])</script><script>self.__next_f.push([1,"ASE_PATH__"])</script>';
    expect(mergeFlightFrames(html)).toBe(
      '<script>self.__next_f.push([1,"A/__AK_BASE_PATH__"])</script>',
    );
  });
});
