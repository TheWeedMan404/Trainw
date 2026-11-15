"use client";

import { useEffect, useMemo, useRef, useState } from "react";

import { Button } from "@/components/ui/button";

type GymOption = {
  id: string;
  name: string;
};

type ApiResponse = {
  gymName: string | null;
  message: string;
};

// NX-05: the CAPTCHA widget (hCaptcha, explicit render, no extra package).
// The site key is public by design; the secret is verified server-side.
// When NEXT_PUBLIC_HCAPTCHA_SITE_KEY is unset the widget is skipped and
// the server fails open with a warning (local dev only — see
// src/lib/captcha.ts; set both keys before launch).
declare global {
  interface Window {
    hcaptcha?: {
      render: (
        container: HTMLElement,
        options: { sitekey: string; callback: (token: string) => void },
      ) => string;
    };
  }
}

const HCAPTCHA_SITE_KEY = process.env.NEXT_PUBLIC_HCAPTCHA_SITE_KEY ?? "";

export function ClientRegistrationForm() {
  const [gyms, setGyms] = useState<GymOption[]>([]);
  const [gymQuery, setGymQuery] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [captchaToken, setCaptchaToken] = useState("");
  const [selectedGym, setSelectedGym] = useState<GymOption | null>(null);
  const [type, setType] = useState<"gym" | "individual">("gym");
  const [result, setResult] = useState<ApiResponse | null>(null);
  const captchaRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (!HCAPTCHA_SITE_KEY || !captchaRef.current) return;
    if (window.hcaptcha) {
      window.hcaptcha.render(captchaRef.current, {
        callback: (token: string) => setCaptchaToken(token),
        sitekey: HCAPTCHA_SITE_KEY,
      });
      return;
    }
    const script = document.createElement("script");
    script.src = "https://js.hcaptcha.com/1/api.js?render=explicit";
    script.async = true;
    script.onload = () => {
      if (captchaRef.current && window.hcaptcha) {
        window.hcaptcha.render(captchaRef.current, {
          callback: (token: string) => setCaptchaToken(token),
          sitekey: HCAPTCHA_SITE_KEY,
        });
      }
    };
    document.head.appendChild(script);
  }, []);

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
          captchaToken: captchaToken || undefined,
          email: email.trim() || undefined,
          gymId: type === "gym" ? selectedGym?.id ?? null : null,
          name,
          phone: phone.trim() || undefined,
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
      setEmail("");
      setPhone("");
      setCaptchaToken("");
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

      <div className="grid gap-4 sm:grid-cols-2">
        <div className="space-y-2">
          <label htmlFor="client-email">Email</label>
          <input
            id="client-email"
            onChange={(event) => setEmail(event.target.value)}
            placeholder="leila@example.tn"
            type="email"
            value={email}
          />
        </div>
        <div className="space-y-2">
          <label htmlFor="client-phone">Phone</label>
          <input
            id="client-phone"
            onChange={(event) => setPhone(event.target.value)}
            placeholder="+216 20 000 000"
            type="tel"
            value={phone}
          />
        </div>
      </div>
      <p className="text-sm text-slate-500">
        An email or a phone number is required — the gym uses it to reach you
        about your registration.
      </p>

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
          <p className="mt-1">Gym: {result.gymName ?? "Independent registration"}</p>
        </div>
      ) : null}

      {HCAPTCHA_SITE_KEY ? (
        <div>
          <div ref={captchaRef} />
        </div>
      ) : null}

      <Button
        disabled={
          isSubmitting ||
          !name ||
          (!email.trim() && !phone.trim()) ||
          (type === "gym" && !selectedGym)
        }
        type="submit"
      >
        {isSubmitting ? "Registering..." : "Register client"}
      </Button>
    </form>
  );
}
