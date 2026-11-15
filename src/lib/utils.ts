import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function formatDateTime(value: string | null | undefined) {
  if (!value) return "N/A";

  // NX-19: all dashboard dates render in Africa/Tunis. Without an
  // explicit timeZone the server's locale decides, and a server in a
  // different zone shifts every displayed time by hours.
  return new Intl.DateTimeFormat("en", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: "Africa/Tunis",
  }).format(new Date(value));
}

// NX-23: formatDate and slugFromGymName were never imported anywhere
// (verified by grep) and have been deleted.
