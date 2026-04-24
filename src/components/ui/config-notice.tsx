import { AlertTriangle } from "lucide-react";

import { Card } from "@/components/ui/card";

export function ConfigNotice() {
  return (
    <Card className="mx-auto max-w-2xl border-amber-200 bg-amber-50">
      <div className="flex gap-4">
        <div className="rounded-full bg-amber-100 p-3 text-amber-700">
          <AlertTriangle className="h-5 w-5" />
        </div>
        <div>
          <h2 className="text-lg font-semibold text-amber-950">Supabase setup required</h2>
          <p className="mt-2 text-sm text-amber-800">
            Add the values from <code>.env.example</code> before using Trainw Gym
            OS. Owner signup, public client registration, and staff-user creation
            also require <code>SUPABASE_SERVICE_ROLE_KEY</code>.
          </p>
        </div>
      </div>
    </Card>
  );
}
