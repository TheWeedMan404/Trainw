import Link from "next/link";

// NX-12: prev/next pager for the dashboard lists. Page 1 has no previous
// link; the next link appears only while the query reports more rows.
// These pages carry no other query params, so ?page=N is the whole URL.
export function Pagination({ hasMore, page }: { hasMore: boolean; page: number }) {
  return (
    <div className="mt-4 flex items-center justify-between gap-4">
      {page > 1 ? (
        <Link
          className="rounded-xl border border-slate-200 px-4 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50"
          href={`?page=${page - 1}`}
        >
          ← Previous
        </Link>
      ) : (
        <span />
      )}
      <span className="text-sm text-slate-500">Page {page}</span>
      {hasMore ? (
        <Link
          className="rounded-xl border border-slate-200 px-4 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50"
          href={`?page=${page + 1}`}
        >
          Next →
        </Link>
      ) : (
        <span />
      )}
    </div>
  );
}
