"use client";

import { useEffect, useMemo, useState } from "react";

import { Button } from "@/components/ui/button";

type GymOption = {
  id: string;
  name: string;
};

type ApiResponse = {
  clientCode: string;
  gymName: string | null;
  message: string;
};

export function ClientRegistrationForm() {
  const [gyms, setGyms] = useState<GymOption[]>([]);
  const [gymQuery, setGymQuery] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [name, setName] = useState("");
  const [selectedGym, setSelectedGym] = useState<GymOption | null>(null);
  const [type, setType] = useState<"gym" | "individual">("gym");
  const [result, setResult] = useState<ApiResponse | null>(null);

  useEffect(() => {
    const controller = new AbortController();

    const timeout = window.setTimeout(async () => {
      if (!gymQuery.trim() || type !== "gym") {
        setGyms([]);
        return;
      }

      const response = await fetch(`/api/gyms/search?q=${encodeURIComponent(gymQuery)}`, {
        signal: controller.signal,
      });

      if (!response.ok) {
        return;
      }

      const payload = (await response.json()) as { gyms: GymOption[] };
      setGyms(payload.gyms);
    }, 250);

    return () => {
      controller.abort();
      window.clearTimeout(timeout);
    };
  }, [gymQuery, type]);

  const helperCopy = useMemo(() => {
    if (type === "gym") {
      return "Pick the gym workspace you want to register under.";
    }

    return "Individual clients can register without selecting a gym.";
  }, [type]);

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setIsSubmitting(true);
    setMessage(null);
    setResult(null);

    try {
      const response = await fetch("/api/public/clients", {
        body: JSON.stringify({
          gymId: type === "gym" ? selectedGym?.id ?? null : null,
          name,
          type,
        }),
        headers: {
          "Content-Type": "application/json",
        },
        method: "POST",
      });

      const payload = (await response.json()) as ApiResponse & { error?: string };

      if (!response.ok) {
        setMessage(payload.error || "Unable to create the client registration.");
        return;
      }

      setResult(payload);
      setName("");
      setGymQuery("");
      setSelectedGym(null);
    } catch {
      setMessage("Unable to create the client registration right now.");
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <form className="space-y-5" onSubmit={handleSubmit}>
      <div className="space-y-2">
        <label htmlFor="client-name">Client full name</label>
        <input
          id="client-name"
          onChange={(event) => setName(event.target.value)}
          placeholder="Leila Mansour"
          required
          value={name}
        />
      </div>

      <div className="space-y-3">
        <label>Client type</label>
        <div className="grid gap-3 sm:grid-cols-2">
          <button
            className={`rounded-2xl border px-4 py-4 text-left ${
              type === "gym"
                ? "border-brand-500 bg-brand-50"
                : "border-slate-200 bg-white hover:border-slate-300"
            }`}
            onClick={() => setType("gym")}
            type="button"
          >
            <p className="font-medium text-slate-900">Gym-linked</p>
            <p className="mt-1 text-sm text-slate-600">
              Assign the client to a gym workspace and generate a gym-based client code.
            </p>
          </button>
          <button
            className={`rounded-2xl border px-4 py-4 text-left ${
              type === "individual"
                ? "border-brand-500 bg-brand-50"
                : "border-slate-200 bg-white hover:border-slate-300"
            }`}
            onClick={() => setType("individual")}
            type="button"
          >
            <p className="font-medium text-slate-900">Individual</p>
            <p className="mt-1 text-sm text-slate-600">
              Keep the client independent and generate a standalone client code.
            </p>
          </button>
        </div>
        <p className="text-sm text-slate-500">{helperCopy}</p>
      </div>

      {type === "gym" ? (
        <div className="space-y-3">
          <label htmlFor="gym-search">Search a gym by name</label>
          <input
            id="gym-search"
            onChange={(event) => {
              setGymQuery(event.target.value);
              setSelectedGym(null);
            }}
            placeholder="Search gyms..."
            value={gymQuery}
          />

          {selectedGym ? (
            <div className="rounded-2xl bg-brand-50 px-4 py-3 text-sm text-brand-800">
              Selected gym: <span className="font-semibold">{selectedGym.name}</span>
            </div>
          ) : null}

          {gyms.length ? (
            <div className="max-h-56 space-y-2 overflow-y-auto rounded-2xl border border-slate-200 bg-white p-2">
              {gyms.map((gym) => (
                <button
                  className="flex w-full items-center justify-between rounded-xl px-3 py-3 text-left text-sm text-slate-700 hover:bg-slate-50"
                  key={gym.id}
                  onClick={() => {
                    setSelectedGym(gym);
                    setGymQuery(gym.name);
                    setGyms([]);
                  }}
                  type="button"
                >
                  <span>{gym.name}</span>
                  <span className="text-xs uppercase tracking-wide text-slate-400">
                    Select
                  </span>
                </button>
              ))}
            </div>
          ) : null}
        </div>
      ) : null}

      {message ? (
        <p className="rounded-xl bg-rose-50 px-4 py-3 text-sm text-rose-700">{message}</p>
      ) : null}

      {result ? (
        <div className="rounded-2xl bg-emerald-50 px-4 py-4 text-sm text-emerald-800">
          <p className="font-semibold">{result.message}</p>
          <p className="mt-2">Client code: {result.clientCode}</p>
          <p className="mt-1">Gym: {result.gymName ?? "Independent registration"}</p>
        </div>
      ) : null}

      <Button disabled={isSubmitting || !name || (type === "gym" && !selectedGym)} type="submit">
        {isSubmitting ? "Registering..." : "Register client"}
      </Button>
    </form>
  );
}
