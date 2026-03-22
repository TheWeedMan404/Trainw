// ── Supabase ──────────────────────────────────────────────
const sb = window.supabase.createClient(
  'https://bibqumevndfykmkssslb.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJpYnF1bWV2bmRmeWtta3Nzc2xiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMzNjM1NzAsImV4cCI6MjA4ODkzOTU3MH0.X51EBM0ERPiMmGE2kP18JRrqrF4O6ebA_c2oCdP6wEM'
);

// ── State ─────────────────────────────────────────────────
let currentUser = null;
let currentGymId = null;
let currentLang = 'en';
let scheduleFilter = 'all';

// ── i18n ──────────────────────────────────────────────────
const T = {
  en: {
    gymOwner:'Gym Owner', signOut:'Sign Out',
    navDashboard:'Dashboard', navSchedule:'Schedule', navCoaches:'Coaches',
    navClients:'Clients', navAnalytics:'Analytics', navSettings:'Settings',
    dashSub:'Your gym at a glance',
    statRevenue:'Monthly Revenue', statClients:'Active Clients',
    statSessions:'Sessions This Week', statCoaches:'Active Coaches',
    vsLastMonth:'vs last month', thisMonth:'this month',
    vsLastWeek:'vs last week', onStaff:'on staff',
    forecastTitle:'Revenue Forecast', forecastSub:'Conservative projection based on current trends',
    nextMonth:'Next Month', nextQ:'Q2 2026', fullYear:'Full Year',
    topCoaches:'Top Coaches', quickStats:'Quick Stats', loading:'Loading…',
    schedSub:'All sessions across your gym', searchPh:'Search…',
    filterAll:'All', filterConfirmed:'Confirmed', filterPending:'Pending',
    coachesSub:'Manage your coaching staff', addCoach:'+ Add Coach',
    clientsSub:'All gym members',
    analyticsSub:'Key business metrics', avgRevClient:'Avg Rev / Client',
    retention:'3-Month Retention', peakHours:'Peak Hours', newClients30:'New Clients (30d)',
    revBreakdown:'Revenue Breakdown',
    settingsSub:'Configure your gym', gymInfo:'Gym Information',
    gymNameLbl:'Gym Name', addressLbl:'Address', phoneLbl:'Phone', descLbl:'Description',
    saveChanges:'Save Changes',
    addCoachTitle:'Add New Coach', coachName:'Full Name', coachEmail:'Email',
    coachPhone:'Phone', coachSpecialty:'Specialty', coachRate:'Hourly Rate (DT)',
    submitCoach:'Add Coach',
    noCoaches:'No coaches yet. Add your first coach!',
    noClients:'No clients yet.',
    noSessions:'No sessions found.',
    savedOk:'Settings saved!', coachAdded:'Coach added!',
    errorMsg:'Something went wrong.',
    performanceLbl:'Performance', reviewsLbl:'Reviews', bioLbl:'Bio',
    hourlyRate:'Hourly Rate', totalReviews:'Total Reviews', avgRating:'Avg Rating',
    employedLbl:'Employed',
    signupClient:'+ Sign Up Client', linkClient:'Link Existing',
    signupClientTitle:'Sign Up New Client', clientName:'Full Name',
    clientEmail:'Email', clientPassword:'Password', clientPhone:'Phone (optional)',
    createClient:'Create Client Account',
    linkClientTitle:'Add Existing Client',
    linkClientDesc:'Search by email or phone to link an existing Trainw account to your gym.',
    searchByEmail:'Email or Phone', search:'Search', linkToGym:'Link to My Gym',
  },
  fr: {
    gymOwner:'Propriétaire', signOut:'Se Déconnecter',
    navDashboard:'Tableau de Bord', navSchedule:'Planning', navCoaches:'Coachs',
    navClients:'Clients', navAnalytics:'Analytiques', navSettings:'Paramètres',
    dashSub:'Votre salle en un coup d\'œil',
    statRevenue:'Revenu Mensuel', statClients:'Clients Actifs',
    statSessions:'Séances Cette Semaine', statCoaches:'Coachs Actifs',
    vsLastMonth:'vs mois dernier', thisMonth:'ce mois',
    vsLastWeek:'vs semaine dernière', onStaff:'en staff',
    forecastTitle:'Prévision de Revenus', forecastSub:'Projection conservatrice selon les tendances actuelles',
    nextMonth:'Mois Prochain', nextQ:'T2 2026', fullYear:'Année Complète',
    topCoaches:'Meilleurs Coachs', quickStats:'Stats Rapides', loading:'Chargement…',
    schedSub:'Toutes les séances de votre salle', searchPh:'Rechercher…',
    filterAll:'Tout', filterConfirmed:'Confirmés', filterPending:'En Attente',
    coachesSub:'Gérez votre équipe', addCoach:'+ Ajouter Coach',
    clientsSub:'Tous les membres',
    analyticsSub:'Métriques clés', avgRevClient:'Revenu Moy. / Client',
    retention:'Rétention 3 Mois', peakHours:'Heure de Pointe', newClients30:'Nouveaux Clients (30j)',
    revBreakdown:'Répartition Revenus',
    settingsSub:'Configurez votre salle', gymInfo:'Infos de la Salle',
    gymNameLbl:'Nom de la Salle', addressLbl:'Adresse', phoneLbl:'Téléphone', descLbl:'Description',
    saveChanges:'Enregistrer',
    addCoachTitle:'Ajouter un Coach', coachName:'Nom Complet', coachEmail:'Email',
    coachPhone:'Téléphone', coachSpecialty:'Spécialité', coachRate:'Tarif Horaire (DT)',
    submitCoach:'Ajouter Coach',
    noCoaches:'Aucun coach. Ajoutez le premier !',
    noClients:'Aucun client pour l\'instant.',
    noSessions:'Aucune séance trouvée.',
    savedOk:'Paramètres enregistrés !', coachAdded:'Coach ajouté !',
    errorMsg:'Une erreur s\'est produite.',
    performanceLbl:'Performance', reviewsLbl:'Avis', bioLbl:'Bio',
    hourlyRate:'Tarif Horaire', totalReviews:'Total Avis', avgRating:'Note Moy.',
    employedLbl:'Ancienneté',
    signupClient:'+ Inscrire Client', linkClient:'Lier Existant',
    signupClientTitle:'Inscrire Nouveau Client', clientName:'Nom Complet',
    clientEmail:'Email', clientPassword:'Mot de passe', clientPhone:'Téléphone (optionnel)',
    createClient:'Créer le Compte Client',
    linkClientTitle:'Ajouter Client Existant',
    linkClientDesc:'Recherchez par email ou téléphone pour lier un compte Trainw existant à votre salle.',
    searchByEmail:'Email ou Téléphone', search:'Rechercher', linkToGym:'Lier à Ma Salle',
  }
};
const t = k => T[currentLang][k] || T.en[k] || k;

function applyTranslations() {
  document.querySelectorAll('[data-i18n]').forEach(el => {
    const k = el.getAttribute('data-i18n');
    if (T[currentLang][k]) el.textContent = T[currentLang][k];
  });
  document.querySelectorAll('[data-i18n-ph]').forEach(el => {
    const k = el.getAttribute('data-i18n-ph');
    if (T[currentLang][k]) el.placeholder = T[currentLang][k];
  });
}

// ── Init ──────────────────────────────────────────────────
(async () => {
  const { data: { session } } = await sb.auth.getSession();
  if (!session) { window.location.href = 'TW Login.html?role=gym_owner'; return; }
  currentUser = session.user;

  const { data: profile } = await sb.from('users').select('gym_id, name').eq('id', currentUser.id).single();

  // Primary: gym_id set on users row by trigger
  if (profile?.gym_id) {
    currentGymId = profile.gym_id;
  } else {
    // Fallback: look up gyms table by owner_id (in case trigger didn't patch users.gym_id)
    const { data: ownedGym } = await sb.from('gyms').select('id').eq('owner_id', currentUser.id).maybeSingle();
    if (ownedGym) {
      currentGymId = ownedGym.id;
      // Patch the users row so the next load is instant
      await sb.from('users').update({ gym_id: currentGymId }).eq('id', currentUser.id);
    }
  }

  if (currentGymId) {
    const { data: gym } = await sb.from('gyms').select('name, address, phone').eq('id', currentGymId).single();
    if (gym) {
      document.getElementById('sidebar-gym-name').textContent  = gym.name || '—';
      document.getElementById('dashboard-gym-name').textContent = gym.name || '—';
      const nameInput  = document.getElementById('gym-name-input');
      const addrInput  = document.getElementById('gym-address-input');
      const phoneInput = document.getElementById('gym-phone-input');
      if (nameInput)  nameInput.value  = gym.name    || '';
      if (addrInput)  addrInput.value  = gym.address || '';
      if (phoneInput) phoneInput.value = gym.phone   || '';
    }
  }

  await loadDashboardStats();
  renderQuickStats();
  renderRevBreakdown();
  await loadSchedule();
  await loadCoaches();
  await loadClients();
  applyTranslations();
})();

// ── Dashboard stats ───────────────────────────────────────
async function loadDashboardStats() {
  // coach count
  const { count: coachCount } = await sb.from('coaches').select('id', { count: 'exact', head: true });
  document.getElementById('stat-coaches').textContent = coachCount ?? '—';

  // client count
  let clientQ = sb.from('clients').select('id', { count: 'exact', head: true });
  if (currentGymId) clientQ = sb.from('users').select('id', { count: 'exact', head: true }).eq('role','client').eq('gym_id', currentGymId);
  const { count: clientCount } = await clientQ;
  document.getElementById('stat-clients').textContent = clientCount ?? '—';

  // top coaches
  const { data: coaches } = await sb.from('coaches')
    .select('id, specialty, hourly_rate, rating, total_reviews, users(name)')
    .order('rating', { ascending: false }).limit(3);

  const topEl = document.getElementById('top-coaches-list');
  if (!coaches || coaches.length === 0) {
    topEl.innerHTML = `<p class="empty-state">${t('noCoaches')}</p>`;
    return;
  }
  topEl.innerHTML = coaches.map(c => {
    const name = c.users?.name || 'Coach';
    const initials = name.split(' ').map(n => n[0]).join('');
    return `<div class="person-card" onclick="openCoachModal('${c.id}')">
      <div class="person-header">
        <div class="person-avatar">${initials}</div>
        <div><div class="person-name">${name}</div><div class="person-role">${c.specialty || '—'}</div></div>
      </div>
      <div class="person-stats">
        <div class="person-stat-item"><div class="person-stat-value">${c.hourly_rate ?? '—'}<span style="font-size:13px;color:var(--mt)"> DT</span></div><div class="person-stat-label">Hourly</div></div>
        <div class="person-stat-item"><div class="person-stat-value">★ ${c.rating ?? '—'}</div><div class="person-stat-label">Rating</div></div>
      </div>
    </div>`;
  }).join('');
}

function renderQuickStats() {
  document.getElementById('quick-stats-list').innerHTML = [
    { label: t('avgRating') || 'Avg Rating', val: '4.8' },
    { label: t('statSessions'), val: '87' },
    { label: t('retention') || '3-Mo Retention', val: '76%' },
  ].map(s => `<div class="qs-item"><span class="qs-label">${s.label}</span><span class="qs-value">${s.val}</span></div>`).join('');
}

function renderRevBreakdown() {
  const rows = [
    { source: 'Personal Training', amount: '5,240 DT', pct: '63%' },
    { source: 'Memberships',       amount: '2,180 DT', pct: '26%' },
    { source: 'Group Classes',     amount: '920 DT',   pct: '11%' },
  ];
  document.getElementById('revenue-breakdown').innerHTML = rows.map(r =>
    `<div class="rev-row">
      <div><div class="rev-source">${r.source}</div><div class="rev-pct">${r.pct} of total</div></div>
      <div class="rev-amount">${r.amount}</div>
    </div>`
  ).join('');
}

// ── Schedule ──────────────────────────────────────────────
let allSessions = [];

async function loadSchedule() {
  const { data } = await sb.from('sessions')
    .select('id, session_date, start_time, duration_minutes, type, status, coach_id, client_id, users!sessions_coach_id_fkey(name)')
    .order('session_date', { ascending: true }).limit(60);
  allSessions = data || [];
  renderSchedule();
}

function renderSchedule() {
  const search = document.getElementById('schedule-search')?.value.toLowerCase() || '';
  let list = allSessions;
  if (scheduleFilter !== 'all') list = list.filter(s => s.status === scheduleFilter);
  if (search) list = list.filter(s =>
    (s.users?.name || '').toLowerCase().includes(search) ||
    (s.type || '').toLowerCase().includes(search)
  );

  const el = document.getElementById('schedule-list');
  if (!list.length) { el.innerHTML = `<p class="empty-state">${t('noSessions')}</p>`; return; }
  el.innerHTML = list.map(s => {
    const coachName = s.users?.name || '—';
    const time = s.start_time?.slice(0,5) || '—';
    const date = new Date(s.session_date).toLocaleDateString('en-GB', { weekday:'short', day:'numeric', month:'short' });
    return `<div class="schedule-item">
      <div class="schedule-time-col"><div class="schedule-time">${time}</div><div class="schedule-dur">${s.duration_minutes ?? 60}min</div></div>
      <div><div class="schedule-title">${(s.type || 'Session').replace('_',' ')}</div><div class="schedule-meta">${coachName} • ${date}</div></div>
      <div class="schedule-status status-${s.status || 'confirmed'}">${s.status || 'confirmed'}</div>
    </div>`;
  }).join('');
}

// ── Coaches ───────────────────────────────────────────────
async function loadCoaches() {
  const { data: coaches } = await sb.from('coaches')
    .select('id, specialty, hourly_rate, rating, total_reviews, users(name)');
  const el = document.getElementById('coaches-grid');
  if (!coaches || coaches.length === 0) { el.innerHTML = `<p class="empty-state">${t('noCoaches')}</p>`; return; }
  el.innerHTML = coaches.map(c => {
    const name = c.users?.name || 'Coach';
    const initials = name.split(' ').map(n => n[0]).join('');
    return `<div class="person-card" onclick="openCoachModal('${c.id}')">
      <div class="person-header">
        <div class="person-avatar">${initials}</div>
        <div><div class="person-name">${name}</div><div class="person-role">${c.specialty || 'Coach'}</div></div>
      </div>
      <div class="person-stats">
        <div class="person-stat-item"><div class="person-stat-value">${c.hourly_rate ?? '—'}<span style="font-size:13px;color:var(--mt)"> DT</span></div><div class="person-stat-label">${t('hourlyRate')}</div></div>
        <div class="person-stat-item"><div class="person-stat-value">★ ${c.rating ?? '—'}</div><div class="person-stat-label">${t('avgRating')}</div></div>
      </div>
    </div>`;
  }).join('');
}

// ── Clients ───────────────────────────────────────────────
async function loadClients() {
  let q = sb.from('clients').select('id, membership_tier, goal, created_at, users(name, gym_id)');
  if (currentGymId) q = sb.from('clients').select('id, membership_tier, goal, created_at, users!inner(name, gym_id)').eq('users.gym_id', currentGymId);
  const { data: clients } = await q;
  const el = document.getElementById('clients-grid');
  if (!clients || clients.length === 0) { el.innerHTML = `<p class="empty-state">${t('noClients')}</p>`; return; }
  el.innerHTML = clients.map(c => {
    const name = c.users?.name || 'Client';
    const initials = name.split(' ').map(n => n[0]).join('');
    const since = new Date(c.created_at).toLocaleDateString('en-GB', { month:'short', year:'numeric' });
    return `<div class="person-card">
      <div class="person-header">
        <div class="person-avatar">${initials}</div>
        <div><div class="person-name">${name}</div><div class="person-role">${c.membership_tier || 'Client'}</div></div>
      </div>
      <div class="person-stats">
        <div class="person-stat-item"><div class="person-stat-value" style="font-size:14px;padding-top:4px;">${c.goal || '—'}</div><div class="person-stat-label">Goal</div></div>
        <div class="person-stat-item"><div class="person-stat-value" style="font-size:14px;padding-top:4px;">${since}</div><div class="person-stat-label">Since</div></div>
      </div>
    </div>`;
  }).join('');
}

// ── Coach modal ───────────────────────────────────────────
async function openCoachModal(coachId) {
  const { data: c } = await sb.from('coaches')
    .select('id, specialty, hourly_rate, bio, rating, total_reviews, created_at, users(name, phone)')
    .eq('id', coachId).single();
  if (!c) return;

  const { data: reviews } = await sb.from('reviews')
    .select('rating, comment, created_at, clients(users(name))')
    .eq('coach_id', coachId).order('created_at', { ascending: false }).limit(5);

  const name = c.users?.name || 'Coach';
  const initials = name.split(' ').map(n => n[0]).join('');
  const months = Math.floor((Date.now() - new Date(c.created_at)) / (1000*60*60*24*30));
  const employed = months >= 12 ? `${Math.floor(months/12)}y ${months%12}mo` : `${months}mo`;

  const reviewsHTML = reviews?.length
    ? reviews.map(r => `<div class="review-item">
        <div class="review-header"><span class="review-client">${r.clients?.users?.name || 'Client'}</span><span class="review-rating">★ ${r.rating}</span></div>
        <div class="review-text">${r.comment || ''}</div>
      </div>`).join('')
    : `<p class="empty-state" style="padding:16px 0;">${t('noReviews') || 'No reviews yet.'}</p>`;

  document.getElementById('coach-modal-body').innerHTML = `
    <div class="modal-header">
      <div class="modal-avatar-lg">${initials}</div>
      <div class="modal-info">
        <h2>${name}</h2>
        <div class="modal-meta">${t('employedLbl')}: ${employed} • ${c.users?.phone || '—'}</div>
        <span class="modal-badge">${c.specialty || '—'}</span>
      </div>
    </div>
    <div class="modal-section">
      <div class="modal-section-title">${t('performanceLbl')}</div>
      <div class="modal-stats-row">
        <div class="modal-stat-box"><div class="modal-stat-value">${c.hourly_rate ?? '—'} DT</div><div class="modal-stat-label">${t('hourlyRate')}</div></div>
        <div class="modal-stat-box"><div class="modal-stat-value">${c.total_reviews ?? 0}</div><div class="modal-stat-label">${t('totalReviews')}</div></div>
        <div class="modal-stat-box"><div class="modal-stat-value">${c.rating ?? '—'}</div><div class="modal-stat-label">${t('avgRating')}</div></div>
      </div>
      ${c.bio ? `<div style="background:var(--s2);border:1px solid var(--bd);border-radius:7px;padding:16px;margin-top:14px;font-size:14px;color:var(--mt);line-height:1.7;">${c.bio}</div>` : ''}
    </div>
    <div class="modal-section">
      <div class="modal-section-title">${t('reviewsLbl')}</div>
      ${reviewsHTML}
    </div>`;
  document.getElementById('coach-modal').classList.add('show');
}

// ── Add Coach ─────────────────────────────────────────────
async function submitNewCoach() {
  const name      = document.getElementById('new-coach-name').value.trim();
  const email     = document.getElementById('new-coach-email').value.trim();
  const phone     = document.getElementById('new-coach-phone').value.trim();
  const specialty = document.getElementById('new-coach-specialty').value;
  const rate      = parseFloat(document.getElementById('new-coach-rate').value);

  if (!name || !email || !phone || !rate) { toast(t('errorMsg')); return; }

  const btn = document.getElementById('btn-submit-coach');
  btn.textContent = '…'; btn.disabled = true;

  try {
    // Save gym owner session before signup changes it
    const { data: { session: ownerSession } } = await sb.auth.getSession();
    const tempPw = 'Trainw!' + Math.random().toString(36).slice(2, 10);

    const { data: signUpData, error: signUpErr } = await sb.auth.signUp({
      email, password: tempPw,
      options: { data: { name, role: 'coach', phone, gym_id: currentGymId || null } }
    });
    if (signUpErr) throw new Error(signUpErr.message);

    const newUserId = signUpData.user?.id;
    if (!newUserId) throw new Error('No user ID returned');

    // Restore gym owner session
    if (ownerSession) {
      await sb.auth.setSession({ access_token: ownerSession.access_token, refresh_token: ownerSession.refresh_token });
    }

    // Wait for DB trigger
    await new Promise(r => setTimeout(r, 700));

    // Patch gym_id and phone on users row
    if (currentGymId) await sb.from('users').update({ gym_id: currentGymId, phone }).eq('id', newUserId);

    // Patch specialty + rate on coaches table
    await sb.from('coaches').update({ specialty, hourly_rate: rate }).eq('user_id', newUserId);

    toast(t('coachAdded'));
    document.getElementById('add-coach-modal').classList.remove('show');
    ['new-coach-name','new-coach-email','new-coach-phone','new-coach-rate'].forEach(id => { document.getElementById(id).value = ''; });
    await loadCoaches();
    await loadDashboardStats();
  } catch (err) {
    toast('Error: ' + err.message);
  } finally {
    btn.textContent = t('submitCoach'); btn.disabled = false;
  }
}

// ── Save Settings ─────────────────────────────────────────
async function saveSettings() {
  const name = document.getElementById('gym-name-input').value.trim();
  if (!name) { toast('Gym name cannot be empty'); return; }

  const address = document.getElementById('gym-address-input').value.trim() || null;
  const phone   = document.getElementById('gym-phone-input').value.trim()   || null;

  const btn = document.getElementById('btn-save-settings');
  btn.textContent = '…'; btn.disabled = true;

  try {
    if (currentGymId) {
      const { error } = await sb.from('gyms')
        .update({ name, address, phone })
        .eq('id', currentGymId);
      if (error) throw new Error(error.message);
    } else {
      const { data: newGym, error: insertErr } = await sb.from('gyms')
        .insert({ name, address, phone, owner_id: currentUser.id })
        .select('id').single();
      if (insertErr) throw new Error(insertErr.message);

      currentGymId = newGym.id;
      const { error: linkErr } = await sb.from('users')
        .update({ gym_id: currentGymId })
        .eq('id', currentUser.id);
      if (linkErr) throw new Error(linkErr.message);
    }

    document.getElementById('sidebar-gym-name').textContent   = name;
    document.getElementById('dashboard-gym-name').textContent = name;
    toast(t('savedOk'));
  } catch (err) {
    toast('Error: ' + err.message);
  } finally {
    btn.textContent = t('saveChanges'); btn.disabled = false;
  }
}

// ── Sign Up New Client ────────────────────────────────────
let foundClientId = null; // for link existing flow

async function submitSignupClient() {
  const name     = document.getElementById('new-client-name').value.trim();
  const email    = document.getElementById('new-client-email').value.trim();
  const password = document.getElementById('new-client-password').value;
  const phone    = document.getElementById('new-client-phone').value.trim();
  const errEl    = document.getElementById('signup-client-err');

  errEl.classList.add('hidden');

  if (!name || !email || !password) {
    errEl.textContent = 'Name, email and password are required.';
    errEl.classList.remove('hidden'); return;
  }
  if (password.length < 8) {
    errEl.textContent = 'Password must be at least 8 characters.';
    errEl.classList.remove('hidden'); return;
  }

  const btn = document.getElementById('btn-submit-signup-client');
  btn.textContent = '…'; btn.disabled = true;

  try {
    const { data: { session: ownerSession } } = await sb.auth.getSession();
    const { data: signUpData, error: signUpErr } = await sb.auth.signUp({
      email, password,
      options: { data: { name, role: 'client', phone: phone || null, gym_id: currentGymId || null } }
    });

    if (signUpErr) {
      const msg = signUpErr.message.toLowerCase();
      errEl.textContent = msg.includes('already') ? 'An account with this email already exists.' : signUpErr.message;
      errEl.classList.remove('hidden'); return;
    }

    const newUserId = signUpData.user?.id;
    if (!newUserId) throw new Error('No user ID returned.');

    // Restore gym owner session
    if (ownerSession) {
      await sb.auth.setSession({ access_token: ownerSession.access_token, refresh_token: ownerSession.refresh_token });
    }

    // Wait for trigger
    await new Promise(r => setTimeout(r, 700));

    // Patch gym_id and phone
    if (currentGymId) {
      await sb.from('users').update({ gym_id: currentGymId, phone: phone || null }).eq('id', newUserId);
    }

    toast('Client account created!');
    document.getElementById('signup-client-modal').classList.remove('show');
    ['new-client-name','new-client-email','new-client-password','new-client-phone'].forEach(id => {
      document.getElementById(id).value = '';
    });
    await loadClients();
    await loadDashboardStats();

  } catch (err) {
    errEl.textContent = 'Error: ' + err.message;
    errEl.classList.remove('hidden');
  } finally {
    btn.textContent = t('createClient') || 'Create Client Account';
    btn.disabled = false;
  }
}

// ── Search Existing Client ────────────────────────────────
async function searchExistingClient() {
  const query  = document.getElementById('link-client-search').value.trim();
  const errEl  = document.getElementById('link-client-err');
  const result = document.getElementById('link-client-result');
  errEl.classList.add('hidden');
  result.classList.add('hidden');
  foundClientId = null;

  if (!query) { errEl.textContent = 'Enter an email or phone number.'; errEl.classList.remove('hidden'); return; }

  const btn = document.getElementById('btn-search-client');
  btn.textContent = '…'; btn.disabled = true;

  try {
    // Search by email or phone in users table
    const { data: users } = await sb.from('users')
      .select('id, name, email, phone, gym_id, role')
      .or(`email.eq.${query},phone.eq.${query}`)
      .eq('role', 'client')
      .limit(1);

    if (!users || users.length === 0) {
      errEl.textContent = 'No Trainw client account found with that email or phone.';
      errEl.classList.remove('hidden'); return;
    }

    const u = users[0];

    if (u.gym_id && u.gym_id === currentGymId) {
      errEl.textContent = 'This client is already linked to your gym.';
      errEl.classList.remove('hidden'); return;
    }

    foundClientId = u.id;
    const initials = (u.name || 'C').split(' ').map(n => n[0]).join('').slice(0,2).toUpperCase();

    document.getElementById('link-result-card').innerHTML = `
      <div class="lrc-avatar">${initials}</div>
      <div>
        <div class="lrc-name">${u.name || '—'}</div>
        <div class="lrc-meta">${u.email || ''} ${u.phone ? '• ' + u.phone : ''}</div>
      </div>`;
    result.classList.remove('hidden');

  } catch (err) {
    errEl.textContent = 'Error: ' + err.message;
    errEl.classList.remove('hidden');
  } finally {
    btn.textContent = t('search') || 'Search';
    btn.disabled = false;
  }
}

// ── Link Existing Client to Gym ───────────────────────────
async function confirmLinkClient() {
  if (!foundClientId) return;
  if (!currentGymId) { toast(t('errorMsg')); return; }

  const btn = document.getElementById('btn-confirm-link');
  btn.textContent = '…'; btn.disabled = true;

  try {
    const { error } = await sb.from('users')
      .update({ gym_id: currentGymId })
      .eq('id', foundClientId);
    if (error) throw new Error(error.message);

    toast('Client linked to your gym!');
    document.getElementById('link-client-modal').classList.remove('show');
    document.getElementById('link-client-search').value = '';
    document.getElementById('link-client-result').classList.add('hidden');
    foundClientId = null;
    await loadClients();
    await loadDashboardStats();

  } catch (err) {
    const errEl = document.getElementById('link-client-err');
    errEl.textContent = 'Error: ' + err.message;
    errEl.classList.remove('hidden');
  } finally {
    btn.textContent = t('linkToGym') || 'Link to My Gym';
    btn.disabled = false;
  }
}

// ── Sign Out ──────────────────────────────────────────────
document.getElementById('btn-logout').addEventListener('click', async () => {
  await sb.auth.signOut();
  window.location.href = 'TW Login.html';
});

// ── Page navigation ───────────────────────────────────────
document.querySelectorAll('.nav-item').forEach(item => {
  item.addEventListener('click', () => {
    const page = item.dataset.page;
    document.querySelectorAll('.page').forEach(p => p.classList.add('hidden'));
    document.getElementById(page + '-page').classList.remove('hidden');
    document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
    item.classList.add('active');
  });
});

// ── Lang toggle ───────────────────────────────────────────
document.querySelectorAll('.lang-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    currentLang = btn.dataset.lang;
    document.querySelectorAll('.lang-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    applyTranslations();
    renderQuickStats();
    renderRevBreakdown();
    renderSchedule();
  });
});

// ── Schedule filters ──────────────────────────────────────
document.querySelectorAll('.filter-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    scheduleFilter = btn.dataset.filter;
    document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    renderSchedule();
  });
});
document.getElementById('schedule-search')?.addEventListener('input', renderSchedule);

// ── Coach search filter ───────────────────────────────────
document.getElementById('coaches-search')?.addEventListener('input', function () {
  const q = this.value.toLowerCase();
  document.querySelectorAll('#coaches-grid .person-card').forEach(card => {
    card.style.display = card.textContent.toLowerCase().includes(q) ? '' : 'none';
  });
});

// ── Client search filter ──────────────────────────────────
document.getElementById('clients-search')?.addEventListener('input', function () {
  const q = this.value.toLowerCase();
  document.querySelectorAll('#clients-grid .person-card').forEach(card => {
    card.style.display = card.textContent.toLowerCase().includes(q) ? '' : 'none';
  });
});

// ── Modals ────────────────────────────────────────────────
document.getElementById('btn-add-coach')?.addEventListener('click', () => document.getElementById('add-coach-modal').classList.add('show'));
document.getElementById('close-coach-modal').addEventListener('click', () => document.getElementById('coach-modal').classList.remove('show'));
document.getElementById('close-add-coach-modal').addEventListener('click', () => document.getElementById('add-coach-modal').classList.remove('show'));
document.getElementById('coach-modal').addEventListener('click', e => { if (e.target.id === 'coach-modal') e.target.classList.remove('show'); });
document.getElementById('add-coach-modal').addEventListener('click', e => { if (e.target.id === 'add-coach-modal') e.target.classList.remove('show'); });
document.getElementById('btn-submit-coach').addEventListener('click', submitNewCoach);
document.getElementById('btn-save-settings').addEventListener('click', saveSettings);

// Client modals
document.getElementById('btn-signup-client')?.addEventListener('click', () => document.getElementById('signup-client-modal').classList.add('show'));
document.getElementById('btn-link-client')?.addEventListener('click', () => document.getElementById('link-client-modal').classList.add('show'));
document.getElementById('close-signup-client-modal').addEventListener('click', () => document.getElementById('signup-client-modal').classList.remove('show'));
document.getElementById('close-link-client-modal').addEventListener('click', () => document.getElementById('link-client-modal').classList.remove('show'));
document.getElementById('signup-client-modal').addEventListener('click', e => { if (e.target.id === 'signup-client-modal') e.target.classList.remove('show'); });
document.getElementById('link-client-modal').addEventListener('click', e => { if (e.target.id === 'link-client-modal') e.target.classList.remove('show'); });
document.getElementById('btn-submit-signup-client').addEventListener('click', submitSignupClient);
document.getElementById('btn-search-client').addEventListener('click', searchExistingClient);
document.getElementById('btn-confirm-link').addEventListener('click', confirmLinkClient);
document.getElementById('link-client-search').addEventListener('keypress', e => { if (e.key === 'Enter') searchExistingClient(); });

// ── Toast ─────────────────────────────────────────────────
function toast(msg) {
  const el = document.getElementById('toast');
  document.getElementById('toast-msg').textContent = msg;
  el.classList.add('show');
  setTimeout(() => el.classList.remove('show'), 3000);
}

applyTranslations();