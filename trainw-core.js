(function () {
  const SUPABASE_URL = window.__TRAINW_URL__ || 'https://bibqumevndfykmkssslb.supabase.co';
  const SUPABASE_ANON =
    window.__TRAINW_KEY__ ||
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJpYnF1bWV2bmRmeWtta3Nzc2xiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMzNjM1NzAsImV4cCI6MjA4ODkzOTU3MH0.X51EBM0ERPiMmGE2kP18JRrqrF4O6ebA_c2oCdP6wEM';

  const ROLE_ROUTES = {
    gym_owner: 'dashboard.html',
    gym: 'dashboard.html',
    admin: 'dashboard.html',
    coach: 'coach.html',
    client: 'client.html',
  };

  function createClient() {
    if (!window.supabase || typeof window.supabase.createClient !== 'function') {
      throw new Error('Supabase client is not available on this page.');
    }
    return window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON);
  }

  function isNoRowsError(error) {
    return Boolean(
      error &&
      (error.code === 'PGRST116' ||
        error.code === '406' ||
        /0 rows/i.test(error.message || '') ||
        /no rows/i.test(error.message || ''))
    );
  }

  function normalizeError(error, fallbackMessage) {
    if (error instanceof Error) return error;

    const message =
      (typeof error === 'string' && error) ||
      error?.message ||
      fallbackMessage ||
      'Unknown error';

    const normalized = new Error(message);
    if (error?.code) normalized.code = error.code;
    if (error?.details) normalized.details = error.details;
    if (error?.hint) normalized.hint = error.hint;
    return normalized;
  }

  async function run(operation, options) {
    const config = {
      context: 'request',
      allowMissing: false,
      fallback: null,
      silent: false,
      ...(options || {}),
    };

    try {
      const response = await operation;
      if (response && Object.prototype.hasOwnProperty.call(response, 'error') && response.error) {
        if (config.allowMissing && isNoRowsError(response.error)) {
          return {
            data: config.fallback,
            error: null,
            count: response.count ?? null,
            missing: true,
          };
        }
        throw response.error;
      }

      return {
        data:
          response && Object.prototype.hasOwnProperty.call(response, 'data')
            ? response.data
            : response,
        error: null,
        count: response?.count ?? null,
        missing: false,
      };
    } catch (error) {
      if (config.allowMissing && isNoRowsError(error)) {
        return {
          data: config.fallback,
          error: null,
          count: null,
          missing: true,
        };
      }

      const normalized = normalizeError(error, config.context + ' failed');
      if (!config.silent) {
        console.error('[Trainw]', config.context, normalized);
      }
      return {
        data: config.fallback,
        error: normalized,
        count: null,
        missing: false,
      };
    }
  }

  function escapeHtml(value) {
    return String(value ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function localeForLang(lang) {
    if (lang === 'ar') return 'ar-TN';
    if (lang === 'en') return 'en-GB';
    return 'fr-FR';
  }

  function dateOnly(value) {
    const date = value instanceof Date ? new Date(value.getTime()) : new Date(value);
    if (Number.isNaN(date.getTime())) return '';
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return year + '-' + month + '-' + day;
  }

  function addDays(value, days) {
    const date = value instanceof Date ? new Date(value.getTime()) : new Date(value || Date.now());
    date.setDate(date.getDate() + days);
    return date;
  }

  function showToast(message, type) {
    const toast = document.getElementById('toast');
    const toastMessage = document.getElementById('toast-msg');
    if (!toast || !toastMessage) {
      if (type === 'err') {
        console.error('[Trainw]', message);
      } else {
        console.log('[Trainw]', message);
      }
      return;
    }

    toastMessage.textContent = String(message || '');
    toast.classList.remove('toast-err');
    if (type === 'err') {
      toast.classList.add('toast-err');
    }
    toast.classList.add('show');

    if (toast.__hideTimer) {
      window.clearTimeout(toast.__hideTimer);
    }
    toast.__hideTimer = window.setTimeout(function () {
      toast.classList.remove('show');
    }, 3500);
  }

  function setText(id, value, fallback) {
    const element = document.getElementById(id);
    if (element) {
      element.textContent = value ?? (fallback ?? '');
    }
    return element;
  }

  function setValue(id, value, fallback) {
    const element = document.getElementById(id);
    if (element) {
      element.value = value ?? (fallback ?? '');
    }
    return element;
  }

  function setHtml(id, value) {
    const element = document.getElementById(id);
    if (element) {
      element.innerHTML = value ?? '';
    }
    return element;
  }

  function setBusy(target, busy) {
    const element = typeof target === 'string' ? document.getElementById(target) : target;
    if (!element) return;
    element.disabled = Boolean(busy);
    element.classList.toggle('loading', Boolean(busy));
    element.setAttribute('aria-busy', busy ? 'true' : 'false');
  }

  function roleToPath(role) {
    return ROLE_ROUTES[role] || 'role.html';
  }

  function redirectToRole(role) {
    window.location.href = roleToPath(role);
  }

  async function getSession(client) {
    const result = await run(client.auth.getSession(), {
      context: 'get session',
      fallback: null,
    });
    return {
      session: result.data?.session || null,
      error: result.error,
    };
  }

  async function getProfile(client, userId, allowMissing) {
    const result = await run(
      client
        .from('users')
        .select('id, name, email, phone, role, gym_id, language_preference')
        .eq('id', userId)
        .maybeSingle(),
      {
        context: 'load user profile',
        allowMissing: Boolean(allowMissing),
        fallback: null,
      }
    );

    return {
      profile: result.data,
      error: result.error,
      missing: result.missing,
    };
  }

  async function getContext(client, options) {
    const config = {
      expectedRoles: null,
      loginHref: null,
      redirectOnMissing: true,
      redirectOnMismatch: true,
      ...(options || {}),
    };

    const sessionResult = await getSession(client);
    if (sessionResult.error) {
      return { session: null, profile: null, error: sessionResult.error };
    }

    if (!sessionResult.session) {
      if (config.redirectOnMissing && config.loginHref) {
        window.location.href = config.loginHref;
      }
      return {
        session: null,
        profile: null,
        error: new Error('No active session'),
      };
    }

    const profileResult = await getProfile(client, sessionResult.session.user.id, true);
    if (!profileResult.profile) {
      if (config.redirectOnMissing && config.loginHref) {
        try {
          await client.auth.signOut();
        } catch (signOutError) {
          console.error('[Trainw] sign out after missing profile', signOutError);
        }
        window.location.href = config.loginHref;
      }
      return {
        session: sessionResult.session,
        profile: null,
        error: profileResult.error || new Error('User profile not found'),
      };
    }

    if (
      Array.isArray(config.expectedRoles) &&
      config.expectedRoles.length &&
      !config.expectedRoles.includes(profileResult.profile.role)
    ) {
      if (config.redirectOnMismatch) {
        redirectToRole(profileResult.profile.role);
      }
      return {
        session: sessionResult.session,
        profile: profileResult.profile,
        error: new Error('Role mismatch'),
      };
    }

    return {
      session: sessionResult.session,
      profile: profileResult.profile,
      error: null,
    };
  }

  function watchAuth(client, callbacks) {
    const config = callbacks || {};
    return client.auth.onAuthStateChange(function (event, session) {
      if (!session && typeof config.onSignedOut === 'function') {
        config.onSignedOut(event);
      }
      if (session && typeof config.onSignedIn === 'function') {
        config.onSignedIn(event, session);
      }
    });
  }

  async function callEdge(client, type, payload) {
    const sessionResult = await getSession(client);
    const headers = {
      'Content-Type': 'application/json',
      apikey: SUPABASE_ANON,
    };

    if (sessionResult.session?.access_token) {
      headers.Authorization = 'Bearer ' + sessionResult.session.access_token;
    }

    const response = await fetch(SUPABASE_URL + '/functions/v1/ai-proxy', {
      method: 'POST',
      headers,
      body: JSON.stringify({ type, payload }),
    });

    const rawText = await response.text();
    let parsed = null;
    try {
      parsed = rawText ? JSON.parse(rawText) : {};
    } catch (parseError) {
      parsed = { error: rawText || 'Invalid response payload' };
    }

    if (!response.ok || parsed?.error) {
      throw normalizeError(
        parsed?.error || response.statusText || 'Edge function call failed',
        'Edge function call failed'
      );
    }

    return parsed;
  }

  function installGlobalErrorHandlers() {
    if (window.__trainwGlobalErrorHandlersInstalled) return;
    window.__trainwGlobalErrorHandlersInstalled = true;

    window.addEventListener('error', function (event) {
      console.error('[Trainw] Unhandled error', event.error || event.message);
    });

    window.addEventListener('unhandledrejection', function (event) {
      console.error('[Trainw] Unhandled rejection', event.reason);
      showToast('Unexpected error. Please try again.', 'err');
    });
  }

  window.TrainwCore = {
    SUPABASE_URL,
    SUPABASE_ANON,
    createClient,
    escapeHtml,
    localeForLang,
    dateOnly,
    addDays,
    roleToPath,
    redirectToRole,
    installGlobalErrorHandlers,
    api: {
      run,
      edge: callEdge,
    },
    auth: {
      getSession,
      getProfile,
      getContext,
      watchAuth,
    },
    ui: {
      showToast,
      setText,
      setValue,
      setHtml,
      setBusy,
    },
  };
})();
