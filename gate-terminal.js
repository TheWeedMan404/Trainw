(function () {
  const Trainw = window.TrainwCore;
  const sb = Trainw.createClient();
  Trainw.installGlobalErrorHandlers();

  const params = new URLSearchParams(window.location.search);
  const gymId = params.get('gym_id') || '';
  const gymName = params.get('gym_name') || 'TRAINW';
  // FE-04: the PIN is NEVER in the URL any more. The terminal asks for it
  // on screen (the admin modal) and verifies it server-side via
  // gate-terminal-auth, which issues a short-lived session token.
  const deviceId = params.get('device_id') || 'gate-1';

  const MODE_LABELS = {
    qr: 'Mode QR',
    rfid_card: 'Mode Badge RFID',
    fingerprint: 'Mode Empreinte',
    face: 'Mode Visage',
    admin: 'Mode Admin',
  };

  const REASON_LABELS = {
    invalid_credential: 'Badge inconnu',
    membership_inactive: 'Abonnement inactif',
    membership_expired: 'Abonnement expiré',
    payment_unpaid: 'Paiement non validé',
    duplicate_recent_checkin: 'Passage déjà enregistré récemment',
    duplicate_checkin_today: 'Passage déjà enregistré aujourd’hui',
    already_inside: 'Déjà à l’intérieur',
    invalid_token: 'QR code invalide',
    token_used: 'QR code déjà utilisé',
    token_expired: 'QR code expiré',
    gym_mismatch: 'Terminal non autorisé pour cette salle',
    missing_token: 'QR code manquant',
    camera_error: 'Caméra indisponible',
    network_error: 'Réseau indisponible — vérifiez la connexion',
    missing_gym_id: 'Gym ID manquant',
    missing_credential_data: 'Identifiant de badge manquant',
    invalid_type: 'Type de lecture invalide',
    server_not_configured: 'Configuration Supabase absente',
    method_not_allowed: 'Méthode non autorisée',
    turnstiles_disabled: 'Tourniquets désactivés',
    invalid_terminal_session: 'Session du terminal expirée — saisissez le PIN',
    server_error: 'Erreur serveur — réessayez',
    rate_limited: 'Trop de tentatives — réessayez dans une minute',
    credential_locked: 'Badge verrouillé — réessayez dans 15 minutes',
  };

  const TYPE_LABELS = {
    qr: 'QR',
    rfid_card: 'Badge',
    fingerprint: 'Empreinte',
    face: 'Visage',
  };

  let currentMode = 'qr';
  let realtimeChannel = null;
  let qrScanner = null;
  let qrRunning = false;
  let adminBuffer = '';
  let resetTimer = null;
  let audioContext = null;
  let lastQrScanMap = new Map();
  let recentFeed = [];
  let recentEventKeys = new Map();

  function escape(value) {
    return Trainw.escapeHTML(value);
  }

  function setText(id, value) {
    const node = document.getElementById(id);
    if (node) node.textContent = String(value ?? '');
  }

  function formatClock() {
    return new Date().toLocaleTimeString('fr-FR', {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    });
  }

  function reasonLabel(reason) {
    return REASON_LABELS[reason] || 'Accès refusé';
  }

  function modeLabel(mode) {
    return MODE_LABELS[mode] || 'Mode Terminal';
  }

  function typeLabel(type) {
    return TYPE_LABELS[type] || 'Accès';
  }

  function cleanRecentEventKeys() {
    const threshold = Date.now() - 4000;
    for (const [key, stamp] of recentEventKeys.entries()) {
      if (stamp < threshold) recentEventKeys.delete(key);
    }
  }

  function buildEventKey(payload) {
    return [
      payload.credential_type || '',
      payload.access ? '1' : '0',
      payload.client_id || '',
      payload.reason || '',
      payload.device_id || '',
      payload.attempted_at || '',
    ].join('|');
  }

  function shouldHandleEvent(payload) {
    if (!payload || payload.gym_id !== gymId) return false;
    if (payload.device_id && payload.device_id !== deviceId) return false;

    cleanRecentEventKeys();
    const key = buildEventKey(payload);
    if (recentEventKeys.has(key)) return false;
    recentEventKeys.set(key, Date.now());
    return true;
  }

  function ensureAudio() {
    if (!audioContext) {
      const Ctor = window.AudioContext || window.webkitAudioContext;
      if (Ctor) audioContext = new Ctor();
    }
    return audioContext;
  }

  function beep(kind) {
    const ctx = ensureAudio();
    if (!ctx) return;

    const oscillator = ctx.createOscillator();
    const gain = ctx.createGain();
    oscillator.type = kind === 'grant' ? 'triangle' : 'sawtooth';
    oscillator.frequency.value = kind === 'grant' ? 880 : 220;
    gain.gain.value = 0.0001;

    oscillator.connect(gain);
    gain.connect(ctx.destination);
    oscillator.start();
    gain.gain.exponentialRampToValueAtTime(0.12, ctx.currentTime + 0.01);
    gain.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + 0.18);
    oscillator.stop(ctx.currentTime + 0.22);
  }

  function updateClock() {
    setText('terminal-clock', formatClock());
  }

  // FE-29: the indicator used to reflect only the Realtime subscribe
  // state, so an offline terminal still showed 'Realtime connectée'
  // until the socket noticed. Online now means the browser has a
  // network connection AND the Realtime channel is subscribed.
  let realtimeSubscribed = false;
  function renderOnlineStatus() {
    const networkOnline = navigator.onLine !== false;
    const isOnline = networkOnline && realtimeSubscribed;
    const status = document.getElementById('terminal-status');
    if (status) status.classList.toggle('online', Boolean(isOnline));
    setText('status-text', !networkOnline ? 'Hors ligne — pas de connexion' : isOnline ? 'Realtime connectée' : 'Realtime hors ligne');
  }
  function setOnlineStatus(isOnline) {
    realtimeSubscribed = Boolean(isOnline);
    renderOnlineStatus();
  }

  function scheduleIdleReset() {
    if (resetTimer) window.clearTimeout(resetTimer);
    resetTimer = window.setTimeout(() => {
      renderIdleState();
    }, 4000);
  }

  function renderIdleState() {
    const card = document.getElementById('result-card');
    if (!card) return;
    card.className = 'result-card state-idle';
    setText('result-mode-label', modeLabel(currentMode));
    setText('result-icon', currentMode === 'qr' ? 'SCAN' : typeLabel(currentMode).toUpperCase());
    setText(
      'result-title',
      currentMode === 'qr'
        ? 'Présentez un QR code'
        : `En attente d'un ${typeLabel(currentMode).toLowerCase()}`
    );
    setText(
      'result-subtitle',
      currentMode === 'qr'
        ? 'Le terminal scanne le code d’entrée client.'
        : 'Le matériel peut envoyer les validations directement à la borne.'
    );
    setText('result-meta', `Gym ${gymName} · Device ${deviceId}`);
  }

  function renderResultState(payload) {
    const card = document.getElementById('result-card');
    if (!card) return;

    const granted = Boolean(payload.access);
    card.className = `result-card ${granted ? 'state-granted' : 'state-denied'}`;
    setText('result-mode-label', modeLabel(payload.credential_type || currentMode));
    setText('result-icon', granted ? 'OPEN' : 'STOP');
    setText(
      'result-title',
      granted ? (payload.client_name || 'Accès autorisé') : reasonLabel(payload.reason)
    );
    setText(
      'result-subtitle',
      granted
        ? payload.client_name || 'Accès autorisé'
        : payload.client_name
          ? `${payload.client_name} · ${reasonLabel(payload.reason)}`
          : reasonLabel(payload.reason)
    );
    setText(
      'result-meta',
      granted
        ? payload.days_left === null || payload.days_left === undefined
          ? 'Abonnement actif'
          : `${payload.days_left} jour(s) restants`
        : `Refus · ${typeLabel(payload.credential_type || currentMode)}`
    );
    beep(granted ? 'grant' : 'deny');
    scheduleIdleReset();
  }

  function pushFeed(payload) {
    recentFeed.unshift({
      access: Boolean(payload.access),
      client_name: payload.client_name || (payload.access ? 'Client' : 'Inconnu'),
      reason: payload.reason || null,
      credential_type: payload.credential_type || currentMode,
      attempted_at: payload.attempted_at || new Date().toISOString(),
      days_left: payload.days_left ?? null,
    });
    recentFeed = recentFeed.slice(0, 8);
    renderFeed();
  }

  function renderFeed() {
    const node = document.getElementById('access-feed');
    if (!node) return;

    if (!recentFeed.length) {
      node.innerHTML = `<div class="feed-empty">${escape('Aucun passage récent sur cette session.')}</div>`;
      return;
    }

    node.innerHTML = recentFeed.map(item => {
      const stamp = new Date(item.attempted_at);
      const time = Number.isNaN(stamp.getTime())
        ? '--:--'
        : stamp.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
      const reason = item.access
        ? (item.days_left === null || item.days_left === undefined
            ? 'Abonnement actif'
            : `${item.days_left} jour(s) restants`)
        : reasonLabel(item.reason);
      return `
        <article class="feed-item ${item.access ? 'granted' : 'denied'}">
          <div class="feed-row">
            <div class="feed-name">${escape(item.client_name)}</div>
            <div class="feed-badge">${escape(item.access ? 'Granted' : 'Denied')}</div>
          </div>
          <div class="feed-meta">${escape(typeLabel(item.credential_type))} · ${escape(time)}</div>
          <div class="feed-reason">${escape(reason)}</div>
        </article>
      `;
    }).join('');
  }

  async function stopQrScanner() {
    if (!qrScanner || !qrRunning) return;
    try {
      await qrScanner.stop();
      qrRunning = false;
    } catch (error) {
      console.warn('Failed to stop QR scanner', error);
    }
  }

  async function startQrScanner() {
    const qrPanel = document.getElementById('qr-panel');
    if (qrPanel) qrPanel.classList.remove('hidden');

    if (!window.Html5Qrcode) {
      renderResultState({
        access: false,
        reason: 'camera_error',
        credential_type: 'qr',
      });
      return;
    }

    if (!qrScanner) {
      qrScanner = new window.Html5Qrcode('qr-reader');
    }

    if (qrRunning) return;

    try {
      await qrScanner.start(
        { facingMode: 'environment' },
        { fps: 10, qrbox: { width: 280, height: 280 } },
        async decodedText => {
          const now = Date.now();
          const lastSeen = lastQrScanMap.get(decodedText) || 0;
          if (now - lastSeen < 3000) return;
          lastQrScanMap.set(decodedText, now);
          await handleQrScan(decodedText);
        },
        () => {}
      );
      qrRunning = true;
    } catch (error) {
      console.error('QR camera start failed', error);
      renderResultState({
        access: false,
        reason: 'camera_error',
        credential_type: 'qr',
      });
    }
  }

  // FE-04: the terminal session token issued by gate-terminal-auth after
  // the PIN is verified. Kept in sessionStorage (cleared when the tab
  // closes) and sent as the x-terminal-token header to gate-checkin.
  const TERMINAL_SESSION_KEY = 'trainw_terminal_session';

  function getStoredSession() {
    try {
      const raw = window.sessionStorage.getItem(TERMINAL_SESSION_KEY);
      if (!raw) return null;
      const parsed = JSON.parse(raw);
      if (!parsed?.token || parsed.gym_id !== gymId) return null;
      if (!parsed.expires_at || new Date(parsed.expires_at).getTime() <= Date.now()) return null;
      return parsed;
    } catch (_error) {
      return null;
    }
  }

  function storeTerminalSession(token, expiresAt) {
    try {
      window.sessionStorage.setItem(TERMINAL_SESSION_KEY, JSON.stringify({
        token,
        expires_at: expiresAt,
        gym_id: gymId,
      }));
    } catch (_error) {
      // sessionStorage unavailable — the terminal re-prompts for the PIN.
    }
  }

  function clearStoredSession() {
    try {
      window.sessionStorage.removeItem(TERMINAL_SESSION_KEY);
    } catch (_error) {
      // Ignore.
    }
  }

  async function authenticateTerminal(pin) {
    const response = await fetch(`${Trainw.SUPABASE_URL}/functions/v1/gate-terminal-auth`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: Trainw.SUPABASE_ANON,
      },
      body: JSON.stringify({ action: 'auth', gym_id: gymId, pin, device_id: deviceId }),
    });
    const body = await response.json().catch(() => ({}));
    if (!response.ok || !body.ok || !body.token) {
      return { ok: false, error: body.error || 'server_error' };
    }
    return { ok: true, token: body.token, expires_at: body.expires_at };
  }

  async function handleQrScan(token) {
    try {
      const response = await fetch(`${Trainw.SUPABASE_URL}/functions/v1/gate-checkin`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          apikey: Trainw.SUPABASE_ANON,
          'x-terminal-token': getStoredSession()?.token || '',
        },
        body: JSON.stringify({
          token,
          gym_id: gymId,
          device_id: deviceId,
          type: 'qr',
        }),
      });
      const body = await response.json();
      // The session expired or was revoked server-side: clear it and
      // re-prompt for the PIN instead of failing every scan.
      if (response.status === 401 && body.reason === 'invalid_terminal_session') {
        clearStoredSession();
        renderResultState({
          access: false,
          reason: 'invalid_terminal_session',
          credential_type: 'qr',
          gym_id: gymId,
          device_id: deviceId,
          attempted_at: new Date().toISOString(),
        });
        openAdminModal();
        return;
      }
      const payload = {
        access: Boolean(body.access),
        reason: body.reason || null,
        credential_type: 'qr',
        client_id: body.client_id || null,
        client_name: body.client_name || null,
        days_left: body.days_left ?? null,
        gym_id: gymId,
        device_id: deviceId,
        attempted_at: new Date().toISOString(),
      };
      renderResultState(payload);
      pushFeed(payload);
    } catch (error) {
      const payload = {
        access: false,
        reason: safeReason(error?.message),
        credential_type: 'qr',
        gym_id: gymId,
        device_id: deviceId,
        attempted_at: new Date().toISOString(),
      };
      renderResultState(payload);
      pushFeed(payload);
    }
  }

  function safeReason(message) {
    if (!message) return 'camera_error';
    const key = String(message).trim();
    if (REASON_LABELS[key]) return key;
    // FE-29: a fetch/network failure is not a camera failure. fetch()
    // throws a TypeError whose message is 'Failed to fetch' (Chrome),
    // 'NetworkError when attempting to fetch resource.' (Firefox) or
    // 'Load failed' (Safari) — none of those is the camera.
    if (/failed to fetch|networkerror|network request failed|load failed/i.test(key)) return 'network_error';
    return 'camera_error';
  }

  // FE-28: the admin modal traps keyboard focus while open (it is the
  // PIN prompt, so Tab must not escape to the scanner behind it) and
  // restores focus to the element that opened it.
  let adminModalReturnFocus = null;
  function adminModalKeydown(event) {
    if (event.key === 'Escape') { closeAdminModal(); return; }
    if (event.key !== 'Tab') return;
    const modal = document.getElementById('admin-modal');
    const focusables = Array.from(modal?.querySelectorAll('button:not([disabled])') || []);
    if (!focusables.length) return;
    const first = focusables[0];
    const last = focusables[focusables.length - 1];
    if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
    else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
  }
  function openAdminModal() {
    adminBuffer = '';
    setText('admin-error', '');
    refreshAdminDisplay();
    const modal = document.getElementById('admin-modal');
    if (!modal) return;
    adminModalReturnFocus = document.activeElement;
    modal.classList.remove('hidden');
    modal.setAttribute('aria-hidden', 'false');
    modal.addEventListener('keydown', adminModalKeydown);
    modal.querySelector('.admin-pad [data-key]')?.focus();
  }

  function closeAdminModal() {
    const modal = document.getElementById('admin-modal');
    if (!modal) return;
    modal.classList.add('hidden');
    modal.setAttribute('aria-hidden', 'true');
    modal.removeEventListener('keydown', adminModalKeydown);
    adminModalReturnFocus?.focus?.();
    adminModalReturnFocus = null;
  }

  function refreshAdminDisplay() {
    // Mask by the typed length only — the PIN itself is never held in the
    // page (it is verified server-side by gate-terminal-auth).
    setText('admin-display', '•'.repeat(Math.max(adminBuffer.length, 4)));
  }

  async function handleAdminKey(key) {
    if (key === 'clear') {
      adminBuffer = '';
      setText('admin-error', '');
      refreshAdminDisplay();
      return;
    }

    if (key === 'enter') {
      // FE-04: no local comparison any more (the old code compared against
      // the PIN from the URL, and a blank PIN passed: '' === ''). The PIN
      // is verified server-side; a wrong or empty PIN is rejected there.
      if (!adminBuffer) {
        setText('admin-error', 'Saisissez le PIN');
        return;
      }
      const pin = adminBuffer;
      adminBuffer = '';
      refreshAdminDisplay();
      setText('admin-error', 'Vérification…');
      const result = await authenticateTerminal(pin);
      if (!result.ok) {
        setText('admin-error', result.error === 'invalid_pin' ? 'Code incorrect' : reasonLabel(result.error));
        refreshAdminDisplay();
        return;
      }
      storeTerminalSession(result.token, result.expires_at);
      closeAdminModal();
      bindRealtime();
      renderIdleState();
      await setMode('qr');
      return;
    }

    if (/^\d$/.test(key)) {
      adminBuffer = (adminBuffer + key).slice(0, 8);
      refreshAdminDisplay();
    }
  }

  async function setMode(mode) {
    if (mode === 'admin') {
      openAdminModal();
      return;
    }

    currentMode = mode;
    document.querySelectorAll('[data-mode]').forEach(button => {
      button.classList.toggle('active', button.getAttribute('data-mode') === mode);
    });

    if (mode === 'qr') {
      await startQrScanner();
    } else {
      await stopQrScanner();
      document.getElementById('qr-panel')?.classList.add('hidden');
    }

    renderIdleState();
  }

  function handleRealtimeEvent(payload) {
    if (!shouldHandleEvent(payload)) return;
    renderResultState(payload);
    pushFeed(payload);
  }

  function bindRealtime() {
    if (!gymId) {
      setOnlineStatus(false);
      return;
    }

    // Re-auth (Admin button) must not stack a second channel on the old one.
    if (realtimeChannel) {
      try {
        sb.removeChannel(realtimeChannel);
      } catch (_error) {
        // Ignore.
      }
      realtimeChannel = null;
    }

    realtimeChannel = sb.channel(`gate-terminal:${gymId}`);
    realtimeChannel
      .on('broadcast', { event: 'access_result' }, payload => {
        handleRealtimeEvent(payload?.payload || {});
      })
      .subscribe(status => {
        setOnlineStatus(status === 'SUBSCRIBED');
      });
  }

  function bindUi() {
    // FE-29: the RFID/fingerprint/face buttons have no local handler —
    // setMode only stops the QR scanner for them, and those modes only
    // work if external hardware pushes access events. Until a reader is
    // configured they are disabled rather than implying they scan.
    document.querySelectorAll('[data-mode]').forEach(button => {
      const mode = button.getAttribute('data-mode');
      if (mode && mode !== 'qr' && mode !== 'admin') {
        button.disabled = true;
        button.title = 'Nécessite un lecteur externe — non configuré';
      }
      button.addEventListener('click', () => {
        void setMode(button.getAttribute('data-mode'));
      });
    });
    window.addEventListener('online', renderOnlineStatus);
    window.addEventListener('offline', renderOnlineStatus);

    document.getElementById('admin-close')?.addEventListener('click', closeAdminModal);
    document.getElementById('admin-modal')?.addEventListener('click', event => {
      if (event.target?.id === 'admin-modal') closeAdminModal();
    });
    document.querySelectorAll('.admin-pad [data-key]').forEach(button => {
      button.addEventListener('click', () => {
        handleAdminKey(button.getAttribute('data-key'));
      });
    });
  }

  function init() {
    setText('terminal-gym-name', gymName);
    renderFeed();
    updateClock();
    window.setInterval(updateClock, 1000);
    bindUi();

    // Turnstile flag OFF: show the disabled screen and stop here — no
    // scanner, no realtime, no PIN prompt.
    if (Trainw.TURNSTILES_ENABLED !== true) {
      document.getElementById('terminal-disabled')?.classList.remove('hidden');
      document.querySelector('.terminal-layout')?.classList.add('hidden');
      document.querySelector('.terminal-bottombar')?.classList.add('hidden');
      setOnlineStatus(false);
      return;
    }

    if (!gymId) {
      renderResultState({
        access: false,
        reason: 'missing_gym_id',
        credential_type: 'qr',
      });
      return;
    }

    if (getStoredSession()) {
      // Already unlocked with a valid session token — start normally.
      bindRealtime();
      renderIdleState();
      void setMode('qr');
    } else {
      // No terminal session yet — the admin modal doubles as the PIN
      // prompt. The scanner starts only after the PIN is verified
      // server-side (see handleAdminKey).
      renderIdleState();
      openAdminModal();
    }
  }

  init();
})();
