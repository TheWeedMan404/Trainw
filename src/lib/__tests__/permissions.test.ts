// NX-26 smoke tests for the permission gate (NX-17): only a real JSON
// boolean `true` grants a permission. A truthy non-boolean — the string
// "false", the number 1 — must NOT.
import { describe, expect, it } from "vitest";

import {
  hasPermission,
  normalisePermissions,
  PERMISSIONS,
} from "@/lib/permissions";

describe("hasPermission", () => {
  it("grants a permission set to boolean true", () => {
    expect(
      hasPermission({ [PERMISSIONS.dashboardView]: true }, PERMISSIONS.dashboardView),
    ).toBe(true);
  });

  it("denies a permission set to the string 'false'", () => {
    // Boolean("false") is true — this is the NX-17 bug.
    expect(
      hasPermission(
        { [PERMISSIONS.dashboardView]: "false" as unknown as boolean },
        PERMISSIONS.dashboardView,
      ),
    ).toBe(false);
  });

  it("denies a permission set to the number 1", () => {
    expect(
      hasPermission(
        { [PERMISSIONS.dashboardView]: 1 as unknown as boolean },
        PERMISSIONS.dashboardView,
      ),
    ).toBe(false);
  });

  it("denies a missing permission and null/undefined maps", () => {
    expect(hasPermission({}, PERMISSIONS.dashboardView)).toBe(false);
    expect(hasPermission(null, PERMISSIONS.dashboardView)).toBe(false);
    expect(hasPermission(undefined, PERMISSIONS.dashboardView)).toBe(false);
  });
});

describe("normalisePermissions", () => {
  it("keeps real booleans and drops truthy non-booleans to false", () => {
    expect(
      normalisePermissions({
        "dashboard.view": true,
        "roles.manage": "false",
        "clients.manage": 1,
      }),
    ).toEqual({
      "dashboard.view": true,
      "roles.manage": false,
      "clients.manage": false,
    });
  });

  it("returns {} for null, undefined, arrays, and non-objects", () => {
    expect(normalisePermissions(null)).toEqual({});
    expect(normalisePermissions(undefined)).toEqual({});
    expect(normalisePermissions([])).toEqual({});
    expect(normalisePermissions("yes")).toEqual({});
  });
});
