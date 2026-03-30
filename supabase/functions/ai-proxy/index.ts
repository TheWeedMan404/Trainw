import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });

  try {
    const { type, payload } = await req.json();
    const ANTHROPIC_KEY = Deno.env.get('ANTHROPIC_API_KEY');
    if (!ANTHROPIC_KEY) return new Response(JSON.stringify({ error: 'API key not configured' }), { status: 500, headers: { ...CORS, 'Content-Type': 'application/json' } });

    let systemPrompt = '';
    let userMessage  = '';

    if (type === 'session_notes') {
      const { clientName, sessionType, highlights } = payload;
      systemPrompt = `Tu es un coach professionnel qui rédige des notes de séance claires et structurées. Réponds en français. Format: sections courtes avec titres. Maximum 300 mots.`;
      userMessage  = `Client: ${clientName}\nType de séance: ${sessionType}\nPoints clés: ${highlights}\n\nRédige des notes de séance professionnelles.`;
    } else if (type === 'diet_plan') {
      const { goal, bodyType, activityLevel, workoutType, weightKg, heightCm } = payload;
      systemPrompt = `Tu es un nutritionniste expert en alimentation tunisienne et méditerranéenne. Génère un plan nutritionnel quotidien personnalisé avec des aliments tunisiens accessibles (couscous, brik, laben, zlabya, etc). Format JSON strict: { calories: number, protein_g: number, carbs_g: number, fats_g: number, meals: [{title, time, items:[{name, portion, calories}]}] }. Réponds UNIQUEMENT en JSON valide, aucun texte autour.`;
      userMessage  = `Objectif: ${goal}\nMorphologie: ${bodyType}\nActivité: ${activityLevel}\nEntraînement: ${workoutType}${weightKg?`\nPoids: ${weightKg}kg`:''}${heightCm?`\nTaille: ${heightCm}cm`:''}`;
    } else {
      return new Response(JSON.stringify({ error: 'Unknown type' }), { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } });
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

    const data = await resp.json();
    const text = data.content?.[0]?.text || '';
    return new Response(JSON.stringify({ result: text }), { headers: { ...CORS, 'Content-Type': 'application/json' } });

  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), { status: 500, headers: { ...CORS, 'Content-Type': 'application/json' } });
  }
});
