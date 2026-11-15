"use client";

import { useMemo, useRef, useState } from "react";

// SearchableSelect — a dependency-free combobox for the long option lists
// (clients, coaches, classes, roles). A plain <select> forces the gym
// staff to scroll through hundreds of members; this filters as they type
// and still submits as a normal form field (a hidden input carries the
// selected value, so the server actions are unchanged). Short lists
// (status, type) stay native <select>s — a combobox there adds nothing.
export type SearchableSelectOption = {
  label: string;
  value: string;
};

export function SearchableSelect({
  defaultValue = "",
  id,
  name,
  options,
  placeholder = "Type to search…",
}: {
  defaultValue?: string;
  id: string;
  name: string;
  options: SearchableSelectOption[];
  placeholder?: string;
}) {
  const selectedOption =
    options.find((option) => option.value === defaultValue) ?? null;
  const [query, setQuery] = useState(selectedOption?.label ?? "");
  const [selectedValue, setSelectedValue] = useState<string | null>(
    selectedOption?.value ?? null,
  );
  const [open, setOpen] = useState(false);
  const [highlighted, setHighlighted] = useState(-1);
  const inputRef = useRef<HTMLInputElement>(null);
  const closeTimer = useRef<number | null>(null);
  const currentSelected =
    options.find((option) => option.value === selectedValue) ?? null;

  const filtered = useMemo(() => {
    const needle = query.trim().toLowerCase();
    if (!needle) return options;
    return options.filter((option) =>
      option.label.toLowerCase().includes(needle),
    );
  }, [options, query]);

  function choose(option: SearchableSelectOption) {
    setSelectedValue(option.value);
    setQuery(option.label);
    setOpen(false);
    setHighlighted(-1);
  }

  function handleKeyDown(event: React.KeyboardEvent<HTMLInputElement>) {
    if (event.key === "ArrowDown") {
      event.preventDefault();
      if (!open) {
        setOpen(true);
        return;
      }
      setHighlighted((current) =>
        filtered.length === 0 ? -1 : (current + 1) % filtered.length,
      );
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      if (!open) return;
      setHighlighted((current) =>
        filtered.length === 0
          ? -1
          : (current - 1 + filtered.length) % filtered.length,
      );
    } else if (event.key === "Enter") {
      if (open && highlighted >= 0 && filtered[highlighted]) {
        event.preventDefault();
        choose(filtered[highlighted]);
      }
    } else if (event.key === "Escape") {
      setOpen(false);
      setQuery(currentSelected?.label ?? "");
      setHighlighted(-1);
    }
  }

  return (
    <div className="relative">
      <input
        aria-autocomplete="list"
        aria-controls={`${id}-listbox`}
        aria-expanded={open}
        autoComplete="off"
        id={id}
        onBlur={() => {
          // The option's onMouseDown (with preventDefault) lands before
          // blur when picking, so this only fires for clicks elsewhere.
          closeTimer.current = window.setTimeout(() => setOpen(false), 120);
        }}
        onChange={(event) => {
          // Typing invalidates the previous selection until an option is
          // picked again — the hidden input goes back to "" so a stale
          // id can never be submitted.
          setQuery(event.target.value);
          setSelectedValue(null);
          setHighlighted(-1);
          setOpen(true);
        }}
        onFocus={() => {
          if (closeTimer.current !== null) {
            window.clearTimeout(closeTimer.current);
            closeTimer.current = null;
          }
          setOpen(true);
        }}
        onKeyDown={handleKeyDown}
        placeholder={placeholder}
        ref={inputRef}
        role="combobox"
        type="text"
        value={query}
      />
      <input name={name} type="hidden" value={selectedValue ?? ""} />
      {open ? (
        <ul
          className="absolute z-20 mt-1 max-h-60 w-full overflow-auto rounded-xl border border-slate-200 bg-white py-1 shadow-lg"
          id={`${id}-listbox`}
          role="listbox"
        >
          {filtered.length === 0 ? (
            <li className="px-4 py-2.5 text-sm text-slate-500">
              No matches — try a different search.
            </li>
          ) : (
            filtered.map((option, index) => (
              <li
                aria-selected={option.value === selectedValue}
                className={`cursor-pointer px-4 py-2.5 text-sm ${
                  index === highlighted
                    ? "bg-brand-50 text-slate-900"
                    : option.value === selectedValue
                      ? "bg-slate-50 text-slate-900"
                      : "text-slate-700"
                }`}
                key={option.value || `empty-${index}`}
                onMouseDown={(event) => {
                  // MouseDown fires before the input's blur, so the pick
                  // lands before the list closes.
                  event.preventDefault();
                  choose(option);
                }}
                role="option"
              >
                {option.label}
              </li>
            ))
          )}
        </ul>
      ) : null}
    </div>
  );
}
