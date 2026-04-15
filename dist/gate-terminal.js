(function () {
  const Trainw = window.TrainwCore;
  const sb = Trainw.createClient();
  Trainw.installGlobalErrorHandlers();

  const params = new URLSearchParams(window.location.search);
  const gymId = params.get('gym_id') || '';
  const gymName = params.get('gym_name') || 'TRAINW';
  const adminPin = params.get('pin') || '';
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
    invalid_token: 'QR code invalide',
    token_used: 'QR code déjà utilisé',
    token_expired: 'QR code expiré',
    gym_mismatch: 'Terminal non autorisé pour cette salle',
    missing_token: 'QR code manquant',
    camera_error: 'Caméra indisponible',
    missing_gym_id: 'Gym ID manquant',
    missing_credential_data: 'Identifiant de badge manquant',
    invalid_type: 'Type de lecture invalide',
    server_not_configured: 'Configuration Supabase absente',
    method_not_allowed: 'Méthode non autorisée',
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

  function setOnlineStatus(isOnline) {
    const status = document.getElementById('terminal-status');
    if (status) status.classList.toggle('online', Boolean(isOnline));
    setText('status-text', isOnline ? 'Realtime connectée' : 'Realtime hors ligne');
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

  async function handleQrScan(token) {
    try {
      const response = await fetch(`${Trainw.SUPABASE_URL}/functions/v1/gate-checkin`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          apikey: Trainw.SUPABASE_ANON,
        },
        body: JSON.stringify({
          token,
          gym_id: gymId,
          device_id: deviceId,
          type: 'qr',
        }),
      });
      const body = await response.json();
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
    return REASON_LABELS[key] ? key : 'camera_error';
  }

  function openAdminModal() {
    adminBuffer = '';
    setText('admin-error', '');
    refreshAdminDisplay();
    document.getElementById('admin-modal')?.classList.remove('hidden');
  }

  function closeAdminModal() {
    document.getElementById('admin-modal')?.classList.add('hidden');
  }

  function refreshAdminDisplay() {
    const masked = adminBuffer.padEnd(Math.max(adminPin.length, 4), '•').slice(0, Math.max(adminPin.length, 4));
    setText('admin-display', masked);
  }

  function handleAdminKey(key) {
    if (key === 'clear') {
      adminBuffer = '';
      setText('admin-error', '');
      refreshAdminDisplay();
      return;
    }

    if (key === 'enter') {
      if (adminBuffer === adminPin) {
        window.open('/dashboard/gym', '_blank', 'noopener');
        closeAdminModal();
      } else {
        adminBuffer = '';
        setText('admin-error', 'Code incorrect');
        refreshAdminDisplay();
      }
      return;
    }

    if (/^\d$/.test(key)) {
      adminBuffer = (adminBuffer + key).slice(0, Math.max(adminPin.length || 4, 4));
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
    document.querySelectorAll('[data-mode]').forEach(button => {
      button.addEventListener('click', () => {
        void setMode(button.getAttribute('data-mode'));
      });
    });

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
    renderIdleState();
    updateClock();
    window.setInterval(updateClock, 1000);
    bindUi();
    bindRealtime();
    void setMode('qr');
  }

  init();
})();
