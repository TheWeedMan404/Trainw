(function () {
  const SUPABASE_URL = window.__TRAINW_URL__;
  const SUPABASE_ANON = window.__TRAINW_KEY__;

  if (!SUPABASE_URL || !SUPABASE_ANON) {
    throw new Error('Trainw: missing Supabase config');
  }

  const ROLE_ROUTES = {
    gym_owner: '/dashboard/gym',
    gym: '/dashboard/gym',
    admin: '/dashboard/gym',
    coach: '/dashboard/coach',
    client: '/dashboard/client',
  };

  const FONT_STACKS = {
    display: "'Bebas Neue', Impact, serif",
    body: "'DM Sans', 'Helvetica Neue', Arial, sans-serif",
    mono: "'DM Mono', 'Courier New', monospace",
  };

  function createClient() {
    if (!window.supabase || typeof window.supabase.createClient !== 'function') {
      throw new Error('Supabase client is not available on this page.');
    }
    return window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON);
  }

  function resolveElement(target) {
    if (!target) return null;
    if (typeof target !== 'string') return target;
    return document.getElementById(target) || document.querySelector(target);
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
    if (error?.status) normalized.status = error.status;
    return normalized;
  }

  function safeVal(value, fallback) {
    if (value === null || value === undefined || value === '') {
      return fallback === undefined ? '—' : fallback;
    }
    return value;
  }

  async function run(operation, options) {
    const config = {
      context: 'request',
      allowMissing: false,
      fallback: null,
      silent: false,
      toastOnError: true,
      throwOnError: false,
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
      console.error('[Trainw]', config.context, normalized);
      if (!config.silent && config.toastOnError) {
        showToast(normalized.message || 'Unexpected error', 'error');
      }
      if (config.throwOnError) {
        throw normalized;
      }
      return {
        data: config.fallback,
        error: normalized,
        count: null,
        missing: false,
      };
    }
  }

  function escapeHTML(value) {
    return String(value ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function escapeHtml(value) {
    return escapeHTML(value);
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

  function formatDate(value, lang, options) {
    if (!value) return safeVal(null);
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return safeVal(null);
    return date.toLocaleDateString(localeForLang(lang || 'fr'), options || {
      day: '2-digit',
      month: 'short',
      year: 'numeric',
    });
  }

  function formatTime(value, lang, options) {
    if (!value) return safeVal(null);
    const date = value instanceof Date ? value : new Date(value);
    if (Number.isNaN(date.getTime())) {
      if (typeof value === 'string' && /^\d{2}:\d{2}/.test(value)) {
        return value.slice(0, 5);
      }
      return safeVal(null);
    }
    return date.toLocaleTimeString(localeForLang(lang || 'fr'), options || {
      hour: '2-digit',
      minute: '2-digit',
    });
  }

  function formatCurrencyDT(value) {
    const numeric = Number(value || 0);
    return Number.isFinite(numeric) ? numeric.toLocaleString('fr-TN') + ' DT' : '0 DT';
  }

  function ensureToastRoot() {
    let root = document.getElementById('trainw-toast-root');
    if (root) return root;
    root = document.createElement('div');
    root.id = 'trainw-toast-root';
    root.className = 'trainw-toast-root';
    document.body.appendChild(root);
    return root;
  }

  function shouldSkipToast(message, type) {
    const normalizedMessage = String(safeVal(message, '')).trim();
    const key = String(type || 'info') + '::' + normalizedMessage;
    const now = Date.now();
    const recent = window.__trainwRecentToast;
    if (recent && recent.key === key && now - recent.at < 2400) {
      return true;
    }
    window.__trainwRecentToast = { key, at: now };
    return false;
  }

  function showToast(message, type) {
    const legacyToast = document.getElementById('toast');
    const legacyMessage = document.getElementById('toast-msg');
    const normalizedType =
      type === 'ok' ? 'success' :
      type === 'err' ? 'error' :
      type === 'success' || type === 'error' || type === 'info' ? type :
      'info';

    if (shouldSkipToast(message, normalizedType)) {
      return;
    }

    if (legacyToast && legacyMessage) {
      legacyMessage.textContent = String(safeVal(message, ''));
      legacyToast.classList.remove('toast-err');
      if (normalizedType === 'error') {
        legacyToast.classList.add('toast-err');
      }
      legacyToast.classList.add('show');
      if (legacyToast.__hideTimer) {
        window.clearTimeout(legacyToast.__hideTimer);
      }
      legacyToast.__hideTimer = window.setTimeout(function () {
        legacyToast.classList.remove('show');
      }, 3200);
      return;
    }

    const root = ensureToastRoot();
    const toast = document.createElement('article');
    toast.className = 'trainw-toast trainw-toast-' + normalizedType;
    toast.innerHTML =
      '<div class="trainw-toast-body">' +
      '<div class="trainw-toast-title">' + escapeHTML(
        normalizedType === 'success' ? 'Succès' :
        normalizedType === 'error' ? 'Erreur' :
        'Info'
      ) + '</div>' +
      '<div class="trainw-toast-text">' + escapeHTML(safeVal(message, '—')) + '</div>' +
      '</div>' +
      '<button class="trainw-toast-close" type="button" aria-label="Close">&times;</button>';

    const close = function () {
      toast.classList.add('closing');
      window.setTimeout(function () {
        if (toast.parentNode) toast.parentNode.removeChild(toast);
      }, 220);
    };

    toast.querySelector('.trainw-toast-close')?.addEventListener('click', close);
    root.appendChild(toast);
    window.requestAnimationFrame(function () {
      toast.classList.add('show');
    });
    window.setTimeout(close, 3200);
  }

  function setText(id, value, fallback) {
    const element = resolveElement(id);
    if (element) {
      element.textContent = safeVal(value, fallback);
    }
    return element;
  }

  function setValue(id, value, fallback) {
    const element = resolveElement(id);
    if (element) {
      element.value = safeVal(value, fallback === undefined ? '' : fallback);
    }
    return element;
  }

  function setHtml(id, value) {
    const element = resolveElement(id);
    if (element) {
      element.innerHTML = value ?? '';
    }
    return element;
  }

  function setBusy(target, busy) {
    const element = resolveElement(target);
    if (!element) return;
    element.disabled = Boolean(busy);
    element.classList.toggle('loading', Boolean(busy));
    element.setAttribute('aria-busy', busy ? 'true' : 'false');
  }

  function renderEffortBar(score) {
    const safeScore = Math.max(0, Math.min(10, Number(score || 0)));
    return Array.from({ length: 10 }, function (_, index) {
      return '<span class="tw-effort-dot' + (index < safeScore ? ' filled' : '') + '"></span>';
    }).join('');
  }

  function skeletonLines(count) {
    const total = Math.max(1, Number(count || 3));
    return Array.from({ length: total }, function (_, index) {
      return '<div class="tw-skeleton-line" style="width:' + (100 - index * 11) + '%"></div>';
    }).join('');
  }

  function emptyState(icon, title, body, actionLabel, actionAttr) {
    const action = actionLabel
      ? '<button class="tw-empty-btn" type="button" ' + (actionAttr || '') + '>' + escapeHTML(actionLabel) + '</button>'
      : '';
    return (
      '<div class="tw-empty-state">' +
      '<div class="tw-empty-icon">' + escapeHTML(icon || '•') + '</div>' +
      '<div class="tw-empty-title">' + escapeHTML(safeVal(title, 'Aucune donnée')) + '</div>' +
      '<div class="tw-empty-copy">' + escapeHTML(safeVal(body, '')) + '</div>' +
      action +
      '</div>'
    );
  }

  function roleToPath(role) {
    return ROLE_ROUTES[role] || '/role';
  }

  function redirectToRole(role) {
    window.location.href = roleToPath(role);
  }

  function applyDocumentLanguage(lang, wrapperTarget) {
    const nextLang = lang || 'fr';
    const isRtl = nextLang === 'ar';
    const wrapper = resolveElement(wrapperTarget) || document.querySelector('.app-container') || document.body;
    document.documentElement.lang = nextLang;
    document.documentElement.setAttribute('dir', isRtl ? 'rtl' : 'ltr');
    document.body.classList.toggle('rtl-active', isRtl);
    if (wrapper) {
      if (isRtl) {
        wrapper.setAttribute('dir', 'rtl');
        wrapper.classList.add('is-rtl');
        wrapper.style.fontFamily = FONT_STACKS.body;
      } else {
        wrapper.removeAttribute('dir');
        wrapper.classList.remove('is-rtl');
        wrapper.style.fontFamily = '';
      }
    }
    return isRtl;
  }

  function openPanel(panelTarget, backdropTarget) {
    const panel = resolveElement(panelTarget);
    const backdrop = resolveElement(backdropTarget);
    if (!panel) return;
    if (backdrop) backdrop.classList.add('open');
    panel.classList.add('open');
    document.body.classList.add('trainw-panel-open');
  }

  function closePanel(panelTarget, backdropTarget) {
    const panel = resolveElement(panelTarget);
    const backdrop = resolveElement(backdropTarget);
    if (panel) panel.classList.remove('open');
    if (backdrop) backdrop.classList.remove('open');
    if (!document.querySelector('.trainw-slide-panel.open')) {
      document.body.classList.remove('trainw-panel-open');
    }
  }

  function normalizeTextValue(value) {
    return String(value || '').replace(/\s+/g, ' ').trim();
  }

  function repairMojibakeString(value) {
    const text = String(value ?? '');
    if (!/[ÃÂØÙ]/.test(text)) {
      return text;
    }

    try {
      const bytes = Uint8Array.from(Array.from(text).map(function (char) {
        return char.charCodeAt(0) & 0xff;
      }));
      const decoded = new TextDecoder('utf-8').decode(bytes);
      return decoded.includes('�') ? text : decoded;
    } catch (error) {
      return text;
    }
  }

  function repairTextSurface(rootTarget) {
    const root = resolveElement(rootTarget) || document.body;
    if (!root) return;

    root.querySelectorAll('*').forEach(function (node) {
      if (['SCRIPT', 'STYLE', 'TEMPLATE'].includes(node.tagName)) return;

      if (node.hasAttribute('placeholder')) {
        const placeholder = node.getAttribute('placeholder');
        const repairedPlaceholder = repairMojibakeString(placeholder);
        if (repairedPlaceholder !== placeholder) {
          node.setAttribute('placeholder', repairedPlaceholder);
        }
      }

      if ('value' in node && typeof node.value === 'string' && node.value) {
        const repairedValue = repairMojibakeString(node.value);
        if (repairedValue !== node.value) {
          node.value = repairedValue;
        }
      }

      const hasElementChildren = Array.from(node.childNodes).some(function (child) {
        return child.nodeType === Node.ELEMENT_NODE;
      });
      if (hasElementChildren) return;

      const repairedText = repairMojibakeString(node.textContent);
      if (repairedText !== node.textContent) {
        node.textContent = repairedText;
      }
    });
  }

  function installTextRepairObserver(rootTarget) {
    const root = resolveElement(rootTarget) || document.body;
    if (!root || root.__trainwTextRepairObserver) return;

    let repairTimer = null;
    const scheduleRepair = function () {
      if (repairTimer) {
        window.clearTimeout(repairTimer);
      }
      repairTimer = window.setTimeout(function () {
        repairTextSurface(root);
      }, 0);
    };

    repairTextSurface(root);
    const observer = new MutationObserver(scheduleRepair);
    observer.observe(root, {
      subtree: true,
      childList: true,
      characterData: true,
      attributes: true,
      attributeFilter: ['placeholder', 'value'],
    });
    root.__trainwTextRepairObserver = observer;
  }

  function localizeSurface(rootTarget, dictionary) {
    const root = resolveElement(rootTarget) || document.body;
    const config = dictionary || {};
    const textMap = config.text || {};
    const placeholderMap = config.placeholders || {};
    const valueMap = config.values || {};
    if (!root || (!Object.keys(textMap).length && !Object.keys(placeholderMap).length && !Object.keys(valueMap).length)) {
      return;
    }

    root.querySelectorAll('*').forEach(function (node) {
      if (node.hasAttribute('placeholder')) {
        const placeholderKey = normalizeTextValue(node.getAttribute('placeholder'));
        if (Object.prototype.hasOwnProperty.call(placeholderMap, placeholderKey)) {
          node.setAttribute('placeholder', placeholderMap[placeholderKey]);
        }
      }

      if ('value' in node && typeof node.value === 'string') {
        const valueKey = normalizeTextValue(node.value);
        if (Object.prototype.hasOwnProperty.call(valueMap, valueKey)) {
          node.value = valueMap[valueKey];
        }
      }

      const hasElementChildren = Array.from(node.childNodes).some(function (child) {
        return child.nodeType === Node.ELEMENT_NODE;
      });
      if (hasElementChildren) return;

      const textKey = normalizeTextValue(node.textContent);
      if (textKey && Object.prototype.hasOwnProperty.call(textMap, textKey)) {
        node.textContent = textMap[textKey];
      }
    });
  }

  function bindPanelControls() {
    if (window.__trainwPanelControlsBound) return;
    window.__trainwPanelControlsBound = true;

    document.addEventListener('click', function (event) {
      const closeButton = event.target.closest('[data-panel-close]');
      if (closeButton) {
        const panel = closeButton.getAttribute('data-panel-close');
        const backdrop = closeButton.getAttribute('data-panel-backdrop');
        closePanel(panel, backdrop);
        return;
      }

      const backdrop = event.target.closest('.trainw-panel-backdrop[data-panel-target]');
      if (backdrop) {
        closePanel(backdrop.getAttribute('data-panel-target'), backdrop);
      }
    });

    document.addEventListener('keydown', function (event) {
      if (event.key !== 'Escape') return;
      document.querySelectorAll('.trainw-slide-panel.open').forEach(function (panel) {
        panel.classList.remove('open');
      });
      document.querySelectorAll('.trainw-panel-backdrop.open').forEach(function (backdrop) {
        backdrop.classList.remove('open');
      });
      document.body.classList.remove('trainw-panel-open');
    });
  }

  async function getSession(client) {
    const result = await run(client.auth.getSession(), {
      context: 'get session',
      fallback: null,
      toastOnError: false,
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
        toastOnError: false,
      }
    );

    return {
      profile: result.data,
      error: result.error,
      missing: result.missing,
    };
  }

  async function ensureProfile(client, options) {
    const config = {
      role: null,
      name: null,
      email: null,
      gymName: null,
      ...(options || {}),
    };

    const sessionResult = await getSession(client);
    const sessionUser = sessionResult.session?.user || null;
    if (!sessionUser?.id) {
      return {
        profile: null,
        error: sessionResult.error || new Error('No active session'),
        missing: true,
        recovered: false,
      };
    }

    const currentProfile = await getProfile(client, sessionUser.id, true);
    const effectiveRole = currentProfile.profile?.role || config.role || null;
    const needsGym =
      effectiveRole && ['gym_owner', 'gym', 'admin', 'coach', 'client'].includes(effectiveRole);

    if (currentProfile.profile && (!needsGym || currentProfile.profile.gym_id)) {
      return {
        profile: currentProfile.profile,
        error: null,
        missing: false,
        recovered: false,
      };
    }

    const repaired = await run(
      client.rpc('bootstrap_authenticated_user', {
        p_role: config.role || null,
        p_name: config.name || sessionUser.user_metadata?.name || null,
        p_email: config.email || sessionUser.email || null,
        p_gym_name: config.gymName || sessionUser.user_metadata?.gym_name || null,
      }),
      {
        context: 'repair authenticated profile',
        fallback: null,
        toastOnError: false,
        silent: true,
      }
    );

    if (repaired.data?.id) {
      return {
        profile: repaired.data,
        error: null,
        missing: false,
        recovered: true,
      };
    }

    const refreshed = await getProfile(client, sessionUser.id, true);
    return {
      profile: refreshed.profile,
      error: repaired.error || refreshed.error || null,
      missing: !refreshed.profile,
      recovered: Boolean(refreshed.profile),
    };
  }

  async function getContext(client, options) {
    const config = {
      expectedRoles: null,
      loginHref: null,
      redirectOnMissing: true,
      redirectOnMismatch: true,
      recoveryRole: null,
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

    const expectedRecoveryRole =
      config.recoveryRole ||
      (Array.isArray(config.expectedRoles) && config.expectedRoles.length === 1
        ? config.expectedRoles[0]
        : null);

    const profileResult = await ensureProfile(client, {
      role: expectedRecoveryRole,
      name: sessionResult.session.user.user_metadata?.name || null,
      email: sessionResult.session.user.email || null,
      gymName: sessionResult.session.user.user_metadata?.gym_name || null,
    });

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

  async function callEdge(client, type, payload, options) {
    const config = {
      functionName: 'ai-proxy',
      rawBody: null,
      ...(options || {}),
    };
    const sessionResult = await getSession(client);
    const headers = {
      'Content-Type': 'application/json',
      apikey: SUPABASE_ANON,
    };

    if (sessionResult.session?.access_token) {
      headers.Authorization = 'Bearer ' + sessionResult.session.access_token;
    }

    const response = await fetch(SUPABASE_URL + '/functions/v1/' + config.functionName, {
      method: 'POST',
      headers,
      body: JSON.stringify(config.rawBody || { type, payload }),
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
    bindPanelControls();
    installTextRepairObserver(document.body);

    window.addEventListener('error', function (event) {
      console.error('[Trainw] Unhandled error', event.error || event.message);
    });

    window.addEventListener('unhandledrejection', function (event) {
      console.error('[Trainw] Unhandled rejection', event.reason);
      showToast('Unexpected error. Please try again.', 'error');
    });
  }

  window.TrainwCore = {
    SUPABASE_URL,
    SUPABASE_ANON,
    FONT_STACKS,
    createClient,
    safeVal,
    escapeHTML,
    escapeHtml,
    localeForLang,
    dateOnly,
    addDays,
    formatDate,
    formatTime,
    formatCurrencyDT,
    renderEffortBar,
    roleToPath,
    redirectToRole,
    installGlobalErrorHandlers,
    applyDocumentLanguage,
    openPanel,
    closePanel,
    emptyState,
    skeletonLines,
    localizeSurface,
    repairTextSurface,
    installTextRepairObserver,
    api: {
      run,
      edge: callEdge,
    },
    auth: {
      getSession,
      getProfile,
      ensureProfile,
      getContext,
      watchAuth,
    },
    ui: {
      showToast,
      setText,
      setValue,
      setHtml,
      setBusy,
      renderEffortBar,
      emptyState,
      skeletonLines,
      localizeSurface,
      repairTextSurface,
      installTextRepairObserver,
      openPanel,
      closePanel,
    },
  };
})();
