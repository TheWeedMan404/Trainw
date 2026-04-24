import { cn } from "@/lib/utils";

const STATUS_STYLES: Record<string, string> = {
  admin: "bg-brand-100 text-brand-800",
  checked_in: "bg-emerald-100 text-emerald-800",
  excused: "bg-sky-100 text-sky-800",
  finance: "bg-indigo-100 text-indigo-800",
  frontdesk: "bg-orange-100 text-orange-800",
  group: "bg-cyan-100 text-cyan-800",
  gym: "bg-brand-100 text-brand-800",
  individual: "bg-slate-100 text-slate-700",
  late: "bg-amber-100 text-amber-800",
  manager: "bg-violet-100 text-violet-800",
  missed: "bg-rose-100 text-rose-800",
  private: "bg-fuchsia-100 text-fuchsia-800",
  supervising: "bg-teal-100 text-teal-800",
};

export function StatusBadge({
  label,
  tone,
}: {
  label: string;
  tone?: string;
}) {
  return (
    <span
      className={cn(
        "inline-flex rounded-full px-2.5 py-1 text-xs font-medium",
        STATUS_STYLES[tone ?? label.toLowerCase()] ?? "bg-slate-100 text-slate-700",
      )}
    >
      {label}
    </span>
  );
}
