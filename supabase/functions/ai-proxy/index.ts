import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.119.0';

// P1-7 (GT-01): the ai-proxy used to be callable by anyone on the internet,
// with no authentication, wildcard CORS, no quota, and raw error messages.
// It now requires a signed-in user who belongs to the gym in the payload,
// enforces a per-user daily quota, and only answers origins the operator
// allows.
//
// Deploy-time setup (Supabase dashboard > Edge Functions > ai-proxy > Secrets):
//   ANTHROPIC_API_KEY  — unchanged, already required.
//   APP_ORIGINS        — comma-separated list of allowed browser origins, e.g.
//                        "https://trainw.vercel.app,https://app.trainw.tn".
//                        Local dev (http://localhost:3000, http://127.0.0.1:3000)
//                        is allowed by default. If APP_ORIGINS is unset, only
//                        local-dev origins are allowed and production browsers
//                        get no CORS headers (fail closed).
// The quota table + function live in migration
// 20261114030000_phase1_ai_proxy_quota.sql — apply it before deploying this.

const AI_PROXY_DAILY_LIMIT = 50;

const LOCAL_DEV_ORIGINS = new Set([
  'http://localhost:3000',
  'http://127.0.0.1:3000',
]);

function allowedOrigins(): Set<string> {
  const fromEnv = (Deno.env.get('APP_ORIGINS') || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
  return new Set([...LOCAL_DEV_ORIGINS, ...fromEnv]);
}

function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get('Origin') || '';
  const headers: Record<string, string> = {
    'Access-Control-Allow-Headers':
      'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    Vary: 'Origin',
  };
  // Only echo back origins on the allowlist. Any other origin gets no
  // Access-Control-Allow-Origin at all, so the browser refuses to read the
  // response. Requests with no Origin header (curl, server-to-server) are
  // unaffected by CORS and still go through the auth checks below.
  if (origin && allowedOrigins().has(origin)) {
    headers['Access-Control-Allow-Origin'] = origin;
  }
  return headers;
}

function jsonResponse(
  req: Request,
  status: number,
  body: Record<string, unknown>,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
  });
}

function asText(value: unknown, maxLength: number): string {
  if (typeof value !== 'string') return '';
  return value.slice(0, maxLength);
}

function isUuid(value: unknown): value is string {
  return (
    typeof value === 'string' &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)
  );
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders(req) });
  }
  if (req.method !== 'POST') {
    return jsonResponse(req, 405, { error: 'Method not allowed' });
  }

  try {
    // --- 1. Authenticate: a signed-in user's JWT is required. -------------
    const authHeader = req.headers.get('Authorization') || '';
    if (!authHeader.startsWith('Bearer ') || authHeader.length < 10) {
      return jsonResponse(req, 401, { error: 'Authentication required' });
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY');
    if (!supabaseUrl || !supabaseAnonKey) {
      console.error('ai-proxy: SUPABASE_URL / SUPABASE_ANON_KEY not configured');
      return jsonResponse(req, 500, { error: 'AI service is not configured' });
    }

    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const {
      data: { user },
      error: userError,
    } = await supabase.auth.getUser();
    if (userError || !user) {
      return jsonResponse(req, 401, { error: 'Authentication required' });
    }

    // --- 2. Parse + validate the body. ------------------------------------
    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return jsonResponse(req, 400, { error: 'Invalid request body' });
    }
    const { type, payload } = (body || {}) as {
      type?: unknown;
      payload?: Record<string, unknown> | null;
    };
    if (type !== 'session_notes' && type !== 'diet_plan') {
      return jsonResponse(req, 400, { error: 'Unknown type' });
    }
    if (!payload || typeof payload !== 'object') {
      return jsonResponse(req, 400, { error: 'Missing payload' });
    }

    // --- 3. Gym membership: the caller must belong to the gym in the payload.
    // The frontend (trainw-core.js callEdge) must send payload.gymId.
    const gymId = payload.gymId;
    if (!isUuid(gymId)) {
      return jsonResponse(req, 400, { error: 'A valid gymId is required' });
    }

    const [{ data: me }, { data: perm }, { data: manages }] =
      await Promise.all([
        supabase
          .from('users')
          .select('gym_id, default_gym_id')
          .eq('id', user.id)
          .maybeSingle(),
        supabase
          .from('user_permissions')
          .select('gym_id')
          .eq('user_id', user.id)
          .eq('gym_id', gymId)
          .maybeSingle(),
        supabase.rpc('manages_gym', { p_gym_id: gymId }),
      ]);

    const isMember =
      me?.gym_id === gymId ||
      me?.default_gym_id === gymId ||
      perm?.gym_id === gymId ||
      manages === true;
    if (!isMember) {
      return jsonResponse(req, 403, {
        error: 'You do not belong to this gym',
      });
    }

    // --- 4. Per-user daily quota (atomic, server-side). --------------------
    const { data: quotaAllowed, error: quotaError } = await supabase.rpc(
      'trainw_ai_proxy_consume_quota',
      { p_limit: AI_PROXY_DAILY_LIMIT },
    );
    if (quotaError || quotaAllowed !== true) {
      if (quotaError) console.error('ai-proxy quota check failed:', quotaError);
      return jsonResponse(req, 429, {
        error: 'Daily AI quota reached. Try again tomorrow.',
      });
    }

    // --- 5. Build the prompt (same two types as before, inputs capped). ----
    const ANTHROPIC_KEY = Deno.env.get('ANTHROPIC_API_KEY');
    if (!ANTHROPIC_KEY) {
      return jsonResponse(req, 500, { error: 'AI service is not configured' });
    }

    let systemPrompt = '';
    let userMessage = '';

    if (type === 'session_notes') {
      const clientName = asText(payload.clientName, 120);
      const sessionType = asText(payload.sessionType, 120);
      const highlights = asText(payload.highlights, 2000);
      systemPrompt = `Tu es un coach professionnel qui rédige des notes de séance claires et structurées. Réponds en français. Format: sections courtes avec titres. Maximum 300 mots.`;
      userMessage = `Client: ${clientName}\nType de séance: ${sessionType}\nPoints clés: ${highlights}\n\nRédige des notes de séance professionnelles.`;
    } else {
      const goal = asText(payload.goal, 200);
      const bodyType = asText(payload.bodyType, 200);
      const activityLevel = asText(payload.activityLevel, 200);
      const workoutType = asText(payload.workoutType, 200);
      const weightKg = typeof payload.weightKg === 'number' ? payload.weightKg : null;
      const heightCm = typeof payload.heightCm === 'number' ? payload.heightCm : null;
      systemPrompt = `Tu es un nutritionniste expert en alimentation tunisienne et méditerranéenne. Génère un plan nutritionnel quotidien personnalisé avec des aliments tunisiens accessibles (couscous, brik, laben, zlabya, etc). Format JSON strict: { calories: number, protein_g: number, carbs_g: number, fats_g: number, meals: [{title, time, items:[{name, portion, calories}]}] }. Réponds UNIQUEMENT en JSON valide, aucun texte autour.`;
      userMessage = `Objectif: ${goal}\nMorphologie: ${bodyType}\nActivité: ${activityLevel}\nEntraînement: ${workoutType}${weightKg !== null ? `\nPoids: ${weightKg}kg` : ''}${heightCm !== null ? `\nTaille: ${heightCm}cm` : ''}`;
    }

    const resp = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': ANTHROPIC_KEY,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model: 'claude-haiku-4-5-20251001',
        max_tokens: 1024,
        system: systemPrompt,
        messages: [{ role: 'user', content: userMessage }],
      }),
    });

    if (!resp.ok) {
      // Never leak the upstream error body — it can contain key details.
      console.error('ai-proxy: Anthropic request failed with status', resp.status);
      return jsonResponse(req, 502, { error: 'AI service is unavailable' });
    }

    const data = await resp.json();
    const text = data.content?.[0]?.text || '';
    return jsonResponse(req, 200, { result: text });
  } catch (err) {
    // Never return raw err.message — it can leak internals.
    console.error('ai-proxy: unexpected error', err);
    return jsonResponse(req, 500, { error: 'AI service failed' });
  }
});
