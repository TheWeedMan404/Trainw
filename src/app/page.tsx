import Link from "next/link";
import { ArrowRight, Building2, CalendarCheck2, ShieldCheck, Users } from "lucide-react";

import { Card } from "@/components/ui/card";

const featureCards = [
  {
    description: "Spin up a new gym workspace with isolated roles, people, and class operations.",
    icon: Building2,
    title: "Gym onboarding",
  },
  {
    description: "Create clients, coaches, classes, enrollments, and manual attendance without breaking tenancy.",
    icon: Users,
    title: "Operational workflows",
  },
  {
    description: "Protect data with per-gym roles and permission-aware navigation for staff users.",
    icon: ShieldCheck,
    title: "Simple RBAC",
  },
  {
    description: "Run front-desk check-ins and class operations from one modern dashboard.",
    icon: CalendarCheck2,
    title: "Day-to-day control",
  },
];

export default function HomePage() {
  return (
    <main className="min-h-screen bg-slate-950 px-4 py-12 text-white">
      <div className="mx-auto max-w-6xl">
        <div className="grid gap-10 lg:grid-cols-[1.1fr_0.9fr] lg:items-center">
          <div>
            <p className="text-sm font-medium uppercase tracking-[0.2em] text-brand-300">
              Trainw Gym OS
            </p>
            <h1 className="mt-4 max-w-3xl text-4xl font-semibold tracking-tight sm:text-5xl">
              Multi-tenant gym operations that owners can actually run tomorrow.
            </h1>
            <p className="mt-5 max-w-2xl text-lg leading-8 text-slate-300">
              Launch a gym workspace, create staff roles, register clients, assign
              coaches, manage classes, and record attendance from a production-ready
              Next.js + Supabase stack.
            </p>

            <div className="mt-8 flex flex-wrap gap-3">
              <Link
                className="inline-flex items-center justify-center gap-2 rounded-xl bg-brand-600 px-4 py-2.5 text-sm font-medium text-white transition hover:bg-brand-700"
                href="/signup"
              >
                Create a gym workspace
                <ArrowRight className="h-4 w-4" />
              </Link>
              <Link
                className="inline-flex items-center justify-center rounded-xl px-4 py-2.5 text-sm font-medium text-slate-200 transition hover:bg-slate-900"
                href="/login"
              >
                Sign in
              </Link>
              <Link
                className="inline-flex items-center justify-center rounded-xl px-4 py-2.5 text-sm font-medium text-slate-200 transition hover:bg-slate-900"
                href="/register-client"
              >
                Register a client
              </Link>
            </div>
          </div>

          <Card className="border-slate-800 bg-slate-900 text-slate-100">
            <h2 className="text-lg font-semibold">MVP scope included</h2>
            <div className="mt-5 grid gap-4">
              {featureCards.map((feature) => {
                const Icon = feature.icon;

                return (
                  <div
                    className="rounded-2xl border border-slate-800 bg-slate-950/50 p-4"
                    key={feature.title}
                  >
                    <div className="flex items-start gap-4">
                      <div className="rounded-2xl bg-brand-500/10 p-3 text-brand-300">
                        <Icon className="h-5 w-5" />
                      </div>
                      <div>
                        <h3 className="font-semibold text-white">{feature.title}</h3>
                        <p className="mt-1 text-sm text-slate-400">
                          {feature.description}
                        </p>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          </Card>
        </div>
      </div>
    </main>
  );
}
