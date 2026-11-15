// NX-12: list pagination for the dashboard pages. One page is 50 rows;
// the queries fetch one extra row (PAGE_SIZE + 1) so hasMore is known
// without a separate count query.

export const PAGE_SIZE = 50;

// Parses the ?page=N query param. Anything missing, non-numeric, or
// below 1 becomes page 1; decimals are floored. There is no upper cap —
// a page past the end simply renders an empty list with no next link.
export function parsePageParam(value: string | string[] | number | null | undefined): number {
  const raw = Array.isArray(value) ? value[0] : value;
  const parsed = typeof raw === "number" ? raw : Number.parseInt(String(raw ?? ""), 10);
  if (!Number.isFinite(parsed) || parsed < 1) return 1;
  return Math.floor(parsed);
}

// PostgREST .range() bounds are inclusive, so fetching PAGE_SIZE + 1
// rows means to = from + PAGE_SIZE.
export function rangeForPage(page: number, pageSize: number = PAGE_SIZE): { from: number; to: number } {
  const safePage = parsePageParam(page);
  const from = (safePage - 1) * pageSize;
  return { from, to: from + pageSize };
}
