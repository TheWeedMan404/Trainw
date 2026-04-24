const VALID_TYPES = new Set(['qr', 'rfid_card', 'fingerprint', 'face']);

function buildCorsHeaders(options) {
  return {
    'Access-Control-Allow-Origin': safeString(options?.getEnv?.('ALLOWED_ORIGIN')) || 'null',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  };
}

function json(body, status = 200, corsHeaders = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
    },
  });
}

function safeString(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function parseMembershipEnd(dateValue) {
  if (!dateValue) return null;
  const parsed = new Date(`${dateValue}T23:59:59.999Z`);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function truncateCredentialRef(value) {
  const trimmed = safeString(value);
  if (!trimmed) return null;
  if (trimmed.length <= 18) return trimmed;
  return `${trimmed.slice(0, 8)}...${trimmed.slice(-4)}`;
}

function normalizeAccessBody(body) {
  if (body && typeof body === 'object' && !Array.isArray(body)) {
    return body;
  }

  return {
    access: false,
    reason: 'invalid_access_response',
  };
}

async function emitAccessEvent(admin, payload) {
  if (!admin?.channel || !payload?.gym_id) return;

  const channel = admin.channel(`gate-terminal:${payload.gym_id}`, {
    config: {
      broadcast: {
        ack: false,
        self: false,
      },
    },
  });
  try {
    await channel.send({
      type: 'broadcast',
      event: 'access_result',
      payload,
    });
  } catch (error) {
    console.warn('[gate-checkin] broadcast failed', error);
  } finally {
    try {
      admin.removeChannel(channel);
    } catch (error) {
      console.warn('[gate-checkin] failed to remove realtime channel', error);
    }
  }
}

async function recordAccessLog(admin, entry) {
  if (!admin || !entry?.gym_id) return;

  const insertPayload = {
    gym_id: entry.gym_id,
    client_id: entry.client_id || null,
    credential_type: entry.credential_type,
    credential_ref: truncateCredentialRef(entry.credential_ref),
    access_granted: Boolean(entry.access_granted),
    denial_reason: entry.access_granted ? null : safeString(entry.denial_reason) || 'unknown_denial',
    device_id: safeString(entry.device_id) || null,
    attempted_at: entry.attempted_at || new Date().toISOString(),
  };

  const { error } = await admin.from('gate_access_log').insert(insertPayload);
  if (error) {
    console.warn('[gate-checkin] access log insert failed', error);
  }
}

function createAdminClientOrNull(options, corsHeaders) {
  const supabaseUrl = safeString(options?.getEnv?.('SUPABASE_URL'));
  const serviceRoleKey = safeString(options?.getEnv?.('SERVICE_ROLE_KEY'));

  if (!supabaseUrl || !serviceRoleKey) {
    return {
      client: null,
      errorResponse: json({ access: false, reason: 'server_not_configured' }, 500, corsHeaders),
    };
  }

  return {
    client: options.createAdminClient(supabaseUrl, serviceRoleKey),
    errorResponse: null,
  };
}

export function createGateCheckinHandler(options) {
  const corsHeaders = buildCorsHeaders(options);
  return async function handleGateCheckinRequest(req) {
    if (req.method === 'OPTIONS') {
      return new Response('ok', { headers: corsHeaders });
    }

    try {
      if (req.method !== 'POST') {
        return json({ access: false, reason: 'method_not_allowed' }, 405, corsHeaders);
      }

      const payload = await req.json();
      const type = safeString(payload?.type || 'qr').toLowerCase() || 'qr';
      const requestedGymId = safeString(payload?.gym_id);
      const deviceId = safeString(payload?.device_id);

      if (!VALID_TYPES.has(type)) {
        return json({ access: false, reason: 'invalid_type' }, 400, corsHeaders);
      }

      const adminState = createAdminClientOrNull(options, corsHeaders);
      if (adminState.errorResponse) {
        return adminState.errorResponse;
      }
      const admin = adminState.client;

      if (type !== 'qr') {
        const credentialData = safeString(payload?.credential_data || payload?.credential_value);
        if (!requestedGymId) {
          return json({ access: false, reason: 'missing_gym_id' }, 400, corsHeaders);
        }
        if (!credentialData) {
          return json({ access: false, reason: 'missing_credential_data' }, 400, corsHeaders);
        }

        const { data: rpcResult, error: rpcError } = await admin.rpc('validate_member_credential', {
          p_gym_id: requestedGymId,
          p_credential_type: type,
          p_credential_data: credentialData,
          p_device_id: deviceId || null,
        });

        if (rpcError) throw rpcError;

        const responseBody = normalizeAccessBody(rpcResult);
        await emitAccessEvent(admin, {
          gym_id: requestedGymId,
          device_id: deviceId || null,
          access: Boolean(responseBody.access),
          reason: responseBody.reason || null,
          credential_type: type,
          client_id: responseBody.client_id || null,
          client_name: responseBody.client_name || null,
          days_left: responseBody.days_left ?? null,
          attempted_at: new Date().toISOString(),
        });

        return json(responseBody, responseBody.access ? 200 : 403, corsHeaders);
      }

      const token = safeString(payload?.token);

      if (!token) {
        return json({ access: false, reason: 'missing_token' }, 400, corsHeaders);
      }

      const denyQr = async (status, reason, details = {}) => {
        const attemptedAt = details.attempted_at || new Date().toISOString();
        await recordAccessLog(admin, {
          gym_id: details.gym_id || requestedGymId || null,
          client_id: details.client_id || null,
          credential_type: 'qr',
          credential_ref: token,
          access_granted: false,
          denial_reason: reason,
          device_id: deviceId || null,
          attempted_at: attemptedAt,
        });
        await emitAccessEvent(admin, {
          gym_id: details.gym_id || requestedGymId || null,
          device_id: deviceId || null,
          access: false,
          reason,
          credential_type: 'qr',
          client_id: details.client_id || null,
          client_name: details.client_name || null,
          days_left: details.days_left ?? null,
          attempted_at: attemptedAt,
        });
        return json({ access: false, reason }, status, corsHeaders);
      };

      const { data: gateSession, error: gateSessionError } = await admin
        .from('gate_sessions')
        .select('id, client_id, gym_id, token, expires_at, used')
        .eq('token', token)
        .maybeSingle();

      if (gateSessionError) throw gateSessionError;
      if (!gateSession) {
        return denyQr(404, 'invalid_token');
      }

      const tokenParts = token.split('.');
      if (tokenParts.length < 4) {
        return denyQr(400, 'invalid_token', { gym_id: gateSession.gym_id });
      }

      const tokenClientId = tokenParts[0];
      const tokenGymId = tokenParts[1];

      if (tokenClientId !== gateSession.client_id) {
        return denyQr(403, 'invalid_token', { gym_id: gateSession.gym_id, client_id: gateSession.client_id });
      }
      if (tokenGymId !== gateSession.gym_id) {
        return denyQr(403, 'gym_mismatch', { gym_id: gateSession.gym_id, client_id: gateSession.client_id });
      }
      if (requestedGymId && requestedGymId !== gateSession.gym_id) {
        return denyQr(403, 'gym_mismatch', { gym_id: gateSession.gym_id, client_id: gateSession.client_id });
      }
      if (gateSession.used) {
        return denyQr(409, 'token_used', { gym_id: gateSession.gym_id, client_id: gateSession.client_id });
      }

      const expiresAt = new Date(gateSession.expires_at);
      if (Number.isNaN(expiresAt.getTime()) || expiresAt.getTime() <= Date.now()) {
        return denyQr(410, 'token_expired', { gym_id: gateSession.gym_id, client_id: gateSession.client_id });
      }

      const [
        { data: clientProfile, error: clientProfileError },
        { data: clientUser, error: clientUserError },
      ] = await Promise.all([
        admin
          .from('client_profiles')
          .select('payment_status, membership_end_date')
          .eq('user_id', gateSession.client_id)
          .maybeSingle(),
        admin
          .from('users')
          .select('name')
          .eq('id', gateSession.client_id)
          .maybeSingle(),
      ]);

      if (clientProfileError) throw clientProfileError;
      if (clientUserError) throw clientUserError;

      const membershipEnd = parseMembershipEnd(clientProfile?.membership_end_date ?? null);
      if (!clientProfile || !membershipEnd || membershipEnd.getTime() < Date.now()) {
        return denyQr(403, 'membership_inactive', {
          gym_id: gateSession.gym_id,
          client_id: gateSession.client_id,
          client_name: clientUser?.name || null,
        });
      }
      if ((clientProfile.payment_status || '').toLowerCase() !== 'paid') {
        return denyQr(403, 'payment_unpaid', {
          gym_id: gateSession.gym_id,
          client_id: gateSession.client_id,
          client_name: clientUser?.name || null,
        });
      }

      const twoHoursAgo = new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString();
      const { data: recentCheckIns, error: recentCheckInsError } = await admin
        .from('check_ins')
        .select('id')
        .eq('gym_id', gateSession.gym_id)
        .eq('client_id', gateSession.client_id)
        .gte('checked_in_at', twoHoursAgo)
        .limit(1);

      if (recentCheckInsError) throw recentCheckInsError;
      if (Array.isArray(recentCheckIns) && recentCheckIns.length > 0) {
        return denyQr(409, 'duplicate_recent_checkin', {
          gym_id: gateSession.gym_id,
          client_id: gateSession.client_id,
          client_name: clientUser?.name || null,
        });
      }

      const { data: consumedSession, error: consumeError } = await admin
        .from('gate_sessions')
        .update({
          used: true,
          used_at: new Date().toISOString(),
          device_id: deviceId || null,
        })
        .eq('id', gateSession.id)
        .eq('used', false)
        .select('id')
        .maybeSingle();

      if (consumeError) throw consumeError;
      if (!consumedSession) {
        return denyQr(409, 'token_used', { gym_id: gateSession.gym_id, client_id: gateSession.client_id });
      }

      const daysLeft = Math.max(0, Math.ceil((membershipEnd.getTime() - Date.now()) / 86400000));

      const { error: insertCheckInError } = await admin
        .from('check_ins')
        .insert({
          gym_id: gateSession.gym_id,
          client_id: gateSession.client_id,
          method: 'qr_gate',
          notes: JSON.stringify({
            source: 'turnstile_qr',
            device_id: deviceId || null,
            client_name: clientUser?.name || 'Client',
            days_left: daysLeft,
          }),
        });

      if (insertCheckInError) {
        if (insertCheckInError.code === '23505') {
          return denyQr(409, 'duplicate_recent_checkin', {
            gym_id: gateSession.gym_id,
            client_id: gateSession.client_id,
            client_name: clientUser?.name || null,
            days_left: daysLeft,
          });
        }
        throw insertCheckInError;
      }

      const attemptedAt = new Date().toISOString();
      await recordAccessLog(admin, {
        gym_id: gateSession.gym_id,
        client_id: gateSession.client_id,
        credential_type: 'qr',
        credential_ref: token,
        access_granted: true,
        device_id: deviceId || null,
        attempted_at: attemptedAt,
      });
      await emitAccessEvent(admin, {
        gym_id: gateSession.gym_id,
        device_id: deviceId || null,
        access: true,
        reason: null,
        credential_type: 'qr',
        client_id: gateSession.client_id,
        client_name: clientUser?.name || 'Client',
        days_left: daysLeft,
        attempted_at: attemptedAt,
      });

      return json({
        access: true,
        client_name: clientUser?.name || 'Client',
        days_left: daysLeft,
      }, 200, corsHeaders);
    } catch (error) {
      const reason = error instanceof Error ? error.message : 'server_error';
      return json({ access: false, reason }, 500, corsHeaders);
    }
  };
}
