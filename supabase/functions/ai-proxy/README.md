# Trainw AI Proxy — Edge Function

## Deploy
```bash
supabase functions deploy ai-proxy --project-ref bibqumevndfykmkssslb
```

## Set the secret (ONE TIME)
```bash
supabase secrets set ANTHROPIC_API_KEY=sk-ant-... --project-ref bibqumevndfykmkssslb
```

## Supports
- POST body: `{ type: 'session_notes', payload: { clientName, sessionType, highlights } }`
- POST body: `{ type: 'diet_plan', payload: { goal, bodyType, activityLevel, workoutType, weightKg?, heightCm? } }`

## Response
`{ result: "..." }` — text for session_notes, JSON string for diet_plan

The Anthropic API key NEVER leaves the server. The anon key is fine in the browser.
