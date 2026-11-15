import { describe, expect, it } from "vitest";
import { PAGE_SIZE, parsePageParam, rangeForPage } from "../pagination";

describe("parsePageParam", () => {
  it("defaults to 1 for missing or empty values", () => {
    expect(parsePageParam(undefined)).toBe(1);
    expect(parsePageParam(null)).toBe(1);
    expect(parsePageParam("")).toBe(1);
  });

  it("parses a plain page number", () => {
    expect(parsePageParam("3")).toBe(3);
    expect(parsePageParam(2)).toBe(2);
  });

  it("clamps below-1 and non-numeric values to 1", () => {
    expect(parsePageParam("0")).toBe(1);
    expect(parsePageParam("-5")).toBe(1);
    expect(parsePageParam("abc")).toBe(1);
    expect(parsePageParam("1.9")).toBe(1);
  });

  it("floors decimals and takes the first of a repeated param", () => {
    expect(parsePageParam("2.9")).toBe(2);
    expect(parsePageParam(["4", "9"])).toBe(4);
  });
});

describe("rangeForPage", () => {
  it("starts at 0 and fetches one extra row for the hasMore check", () => {
    expect(rangeForPage(1)).toEqual({ from: 0, to: PAGE_SIZE });
    expect(rangeForPage(2)).toEqual({ from: PAGE_SIZE, to: PAGE_SIZE * 2 });
  });

  it("clamps an invalid page to page 1", () => {
    expect(rangeForPage(0)).toEqual({ from: 0, to: PAGE_SIZE });
  });
});
