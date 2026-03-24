const sb = window.supabase.createClient(
  'https://bibqumevndfykmkssslb.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJpYnF1bWV2bmRmeWtta3Nzc2xiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMzNjM1NzAsImV4cCI6MjA4ODkzOTU3MH0.X51EBM0ERPiMmGE2kP18JRrqrF4O6ebA_c2oCdP6wEM'
);

let currentUser = null;
let currentGymId = null;
let currentLang = localStorage.getItem('trainw_lang') || 'fr';
let scheduleFilter = 'all';

// ── i18n ──────────────────────────────────────────────────
const T = {
  fr: {
    gymOwner:'Propriétaire', signOut:'Déconnexion',
    navDashboard:'Tableau de Bord', navSchedule:'Planning', navCoaches:'Coachs',
    navClients:'Clients', navAnalytics:'Analytiques', navSettings:'Paramètres',
    dashSub:"Votre salle en un coup d'œil",
    statClients:'Clients Actifs', statCoaches:'Coachs Actifs',
    statSessions:'Séances Cette Semaine', statRevenue:'Revenu Mensuel',
    thisMonth:'ce mois', onStaff:'en staff', vsLastWeek:'cette semaine',
    comingSoon:'bientôt disponible',
    topCoaches:'Meilleurs Coachs', recentSessions:'Séances Récentes',
    loading:'Chargement…',
    schedSub:'Toutes les séances de votre salle',
    filterAll:'Tout', filterConfirmed:'Confirmé', filterPending:'En attente',
    coachesSub:'Gérez votre équipe de coachs', addCoach:'+ Ajouter un Coach',
    clientsSub:'Tous les membres de votre salle',
    analyticsSub:'Métriques clés de votre activité',
    analyticsComingSoon:'Analytiques Avancées',
    analyticsDesc:'Les rapports de revenus, rétention et heures de pointe seront disponibles dans la prochaine mise à jour.',
    settingsSub:'Configurez votre salle', gymInfo:'Informations de la Salle',
    gymNameLbl:'Nom de la Salle', addressLbl:'Adresse', phoneLbl:'Téléphone', descLbl:'Description',
    saveChanges:'Enregistrer',
    addCoachTitle:'Ajouter un Coach', coachName:'Nom Complet', coachEmail:'Email',
    coachPhone:'Téléphone', coachSpecialty:'Spécialité', coachRate:'Tarif Horaire (DT)',
    submitCoach:'Ajouter le Coach',
    noCoaches:'Aucun coach pour le moment. Ajoutez votre premier coach !',
    noClients:'Aucun client pour le moment.',
    noSessions:'Aucune séance trouvée.',
    savedOk:'Paramètres enregistrés !', coachAdded:'Coach ajouté avec succès !',
    errorMsg:'Une erreur est survenue.',
    hourlyRate:'Tarif Horaire', avgRating:'Note Moy.',
    performanceLbl:'Performance', reviewsLbl:'Avis',
    employedLbl:'Ancienneté', totalReviews:'Total Avis',
    emailMissing:'Veuillez saisir un email valide.',
    nameMissing:'Veuillez saisir un nom.',
  },
  en: {
    gymOwner:'Gym Owner', signOut:'Sign Out',
    navDashboard:'Dashboard', navSchedule:'Schedule', navCoaches:'Coaches',
    navClients:'Clients', navAnalytics:'Analytics', navSettings:'Settings',
    dashSub:'Your gym at a glance',
    statClients:'Active Clients', statCoaches:'Active Coaches',
    statSessions:'Sessions This Week', statRevenue:'Monthly Revenue',
    thisMonth:'this month', onStaff:'on staff', vsLastWeek:'this week',
    comingSoon:'coming soon',
    topCoaches:'Top Coaches', recentSessions:'Recent Sessions',
    loading:'Loading…',
    schedSub:'All sessions across your gym',
    filterAll:'All', filterConfirmed:'Confirmed', filterPending:'Pending',
    coachesSub:'Manage your coaching staff', addCoach:'+ Add Coach',
    clientsSub:'All gym members',
    analyticsSub:'Key business metrics',
    analyticsComingSoon:'Advanced Analytics',
    analyticsDesc:'Revenue reports, client retention and peak hours coming in the next update.',
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
    hourlyRate:'Hourly Rate', avgRating:'Avg Rating',
    performanceLbl:'Performance', reviewsLbl:'Reviews',
    employedLbl:'Employed', totalReviews:'Total Reviews',
    emailMissing:'Please enter a valid email.',
    nameMissing:'Please enter a name.',
  },
  ar: {
    gymOwner:'مالك الصالة', signOut:'تسجيل الخروج',
    navDashboard:'لوحة التحكم', navSchedule:'الجدول', navCoaches:'المدربون',
    navClients:'العملاء', navAnalytics:'التحليلات', navSettings:'الإعدادات',
    dashSub:'صالتك في نظرة واحدة',
    statClients:'العملاء النشطون', statCoaches:'المدربون النشطون',
    statSessions:'جلسات هذا الأسبوع', statRevenue:'الإيرادات الشهرية',
    thisMonth:'هذا الشهر', onStaff:'في الفريق', vsLastWeek:'هذا الأسبوع',
    comingSoon:'قريباً',
    topCoaches:'أفضل المدربين', recentSessions:'الجلسات الأخيرة',
    loading:'جار التحميل…',
    schedSub:'جميع جلسات صالتك',
    filterAll:'الكل', filterConfirmed:'مؤكد', filterPending:'معلق',
    coachesSub:'إدارة فريق المدربين', addCoach:'+ إضافة مدرب',
    clientsSub:'جميع أعضاء الصالة',
    analyticsSub:'المقاييس الرئيسية',
    analyticsComingSoon:'التحليلات المتقدمة',
    analyticsDesc:'تقارير الإيرادات والاحتفاظ بالعملاء وأوقات الذروة ستكون متاحة في التحديث القادم.',
    settingsSub:'إعداد صالتك', gymInfo:'معلومات الصالة',
    gymNameLbl:'اسم الصالة', addressLbl:'العنوان', phoneLbl:'الهاتف', descLbl:'الوصف',
    saveChanges:'حفظ التغييرات',
    addCoachTitle:'إضافة مدرب', coachName:'الاسم الكامل', coachEmail:'البريد الإلكتروني',
    coachPhone:'الهاتف', coachSpecialty:'التخصص', coachRate:'الأجر بالساعة (دت)',
    submitCoach:'إضافة المدرب',
    noCoaches:'لا يوجد مدربون بعد. أضف أول مدرب!',
    noClients:'لا يوجد عملاء بعد.',
    noSessions:'لا توجد جلسات.',
    savedOk:'تم الحفظ!', coachAdded:'تمت إضافة المدرب!',
    errorMsg:'حدث خطأ ما.',
    hourlyRate:'الأجر بالساعة', avgRating:'متوسط التقييم',
    performanceLbl:'الأداء', reviewsLbl:'التقييمات',
    employedLbl:'مدة العمل', totalReviews:'إجمالي التقييمات',
    emailMissing:'الرجاء إدخال بريد إلكتروني صحيح.',
    nameMissing:'الرجاء إدخال الاسم.',
  }
};
const t = k => T[currentLang]?.[k] || T.fr[k] || k;

function applyTranslations() {
  document.querySelectorAll('[data-i18n]').forEach(el => {
    const k = el.getAttribute('data-i18n');
    if (T[currentLang]?.[k]) el.textContent = T[currentLang][k];
  });
  if (currentLang === 'ar') {
    document.documentElement.setAttribute('dir', 'rtl');
  } else {
    document.documentElement.setAttribute('dir', 'ltr');
  }
}

// ── Init ──────────────────────────────────────────────────
(async () => {
  const { data: { session } } = await sb.auth.getSession();
  if (!session) { window.location.href = 'TW Login.html?role=gym_owner'; return; }
  currentUser = session.user;

  const { data: profile } = await sb.from('users').select('gym_id, name').eq('id', currentUser.id).single();
  if (profile?.gym_id) {
    currentGymId = profile.gym_id;
    const { data: gym } = await sb.from('gyms').select('name, address, phone, description').eq('id', currentGymId).single();
    if (gym) {
      document.getElementById('sidebar-gym-name').textContent = gym.name || '—';
      const f = id => document.getElementById(id);
      if (f('gym-name-input'))  f('gym-name-input').value  = gym.name        || '';
      if (f('gym-address-input')) f('gym-address-input').value = gym.address || '';
      if (f('gym-phone-input'))   f('gym-phone-input').value  = gym.phone    || '';
      if (f('gym-desc-input'))    f('gym-desc-input').value   = gym.description || '';
    }
  } else {
    document.getElementById('sidebar-gym-name').textContent = profile?.name || '—';
  }

  await loadDashboardStats();
  await loadSchedule();
  await loadCoaches();
  await loadClients();
  applyTranslations();
})();

// ── Dashboard stats ───────────────────────────────────────
async function loadDashboardStats() {
  // Coach count — scoped to gym
  let coachCount = 0;
  if (currentGymId) {
    const { count } = await sb.from('users')
      .select('id', { count: 'exact', head: true })
      .eq('role', 'coach')
      .eq('gym_id', currentGymId);
    coachCount = count ?? 0;
  }
  document.getElementById('stat-coaches').textContent = coachCount;

  // Client count — scoped to gym
  let clientCount = 0;
  if (currentGymId) {
    const { count } = await sb.from('users')
      .select('id', { count: 'exact', head: true })
      .eq('role', 'client')
      .eq('gym_id', currentGymId);
    clientCount = count ?? 0;
  }
  document.getElementById('stat-clients').textContent = clientCount;

  // Session count this week — scoped to gym
  const now = new Date();
  const weekStart = new Date(now); weekStart.setDate(now.getDate() - now.getDay());
  const weekEnd   = new Date(weekStart); weekEnd.setDate(weekStart.getDate() + 6);
  const ws = weekStart.toISOString().split('T')[0];
  const we = weekEnd.toISOString().split('T')[0];

  let sessionCount = 0;
  if (currentGymId) {
    const { count } = await sb.from('sessions')
      .select('id', { count: 'exact', head: true })
      .eq('gym_id', currentGymId)
      .gte('session_date', ws)
      .lte('session_date', we);
    sessionCount = count ?? 0;
  }
  document.getElementById('stat-sessions').textContent = sessionCount;

  // Top coaches — scoped to gym via users table
  let coaches = [];
  if (currentGymId) {
    const { data } = await sb.from('coach_profiles')
      .select('id, specialty, hourly_rate, rating, total_reviews, users!inner(name, gym_id)')
      .eq('users.gym_id', currentGymId)
      .order('rating', { ascending: false })
      .limit(3);
    coaches = data || [];
  }

  const topEl = document.getElementById('top-coaches-list');
  if (!coaches || coaches.length === 0) {
    topEl.innerHTML = `<p class="empty-state">${t('noCoaches')}</p>`;
  } else {
    topEl.innerHTML = coaches.map(c => {
      const name = c.users?.name || 'Coach';
      const initials = name.split(' ').map(n => n[0]).join('').slice(0,2).toUpperCase();
      return `<div class="person-card" onclick="openCoachModal('${c.id}')" style="cursor:pointer;">
        <div class="person-header">
          <div class="person-avatar">${initials}</div>
          <div><div class="person-name">${name}</div><div class="person-role">${c.specialty || '—'}</div></div>
        </div>
        <div class="person-stats">
          <div class="person-stat-item"><div class="person-stat-value">${c.hourly_rate ?? '—'}<span style="font-size:13px;color:var(--mt)"> DT</span></div><div class="person-stat-label">${t('hourlyRate')}</div></div>
          <div class="person-stat-item"><div class="person-stat-value">★ ${c.rating ?? '—'}</div><div class="person-stat-label">${t('avgRating')}</div></div>
        </div>
      </div>`;
    }).join('');
  }

  // Recent sessions
  const recentEl = document.getElementById('recent-sessions-list');
  if (currentGymId) {
    const { data: sessions } = await sb.from('sessions')
      .select('id, session_date, start_time, type, status, users!sessions_coach_id_fkey(name)')
      .eq('gym_id', currentGymId)
      .order('session_date', { ascending: false })
      .limit(4);
    if (!sessions || sessions.length === 0) {
      recentEl.innerHTML = `<p class="empty-state">${t('noSessions')}</p>`;
    } else {
      recentEl.innerHTML = sessions.map(s => {
        const coachName = s.users?.name || '—';
        const time = s.start_time?.slice(0,5) || '—';
        const date = new Date(s.session_date).toLocaleDateString('fr-FR', { weekday:'short', day:'numeric', month:'short' });
        return `<div class="schedule-item">
          <div class="schedule-time-col"><div class="schedule-time">${time}</div></div>
          <div><div class="schedule-title">${(s.type || 'Séance').replace(/_/g,' ')}</div><div class="schedule-meta">${coachName} · ${date}</div></div>
          <div class="schedule-status status-${s.status || 'pending'}">${s.status || 'pending'}</div>
        </div>`;
      }).join('');
    }
  } else {
    recentEl.innerHTML = `<p class="empty-state">${t('noSessions')}</p>`;
  }
}

// ── Schedule ──────────────────────────────────────────────
let allSessions = [];

async function loadSchedule() {
  if (!currentGymId) { allSessions = []; renderSchedule(); return; }
  const { data } = await sb.from('sessions')
    .select('id, session_date, start_time, duration_minutes, type, status, coach_id, users!sessions_coach_id_fkey(name)')
    .eq('gym_id', currentGymId)
    .order('session_date', { ascending: true })
    .limit(60);
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
    const date = new Date(s.session_date).toLocaleDateString('fr-FR', { weekday:'short', day:'numeric', month:'short' });
    return `<div class="schedule-item">
      <div class="schedule-time-col"><div class="schedule-time">${time}</div><div class="schedule-dur">${s.duration_minutes ?? 60}min</div></div>
      <div><div class="schedule-title">${(s.type || 'Séance').replace(/_/g,' ')}</div><div class="schedule-meta">${coachName} · ${date}</div></div>
      <div class="schedule-status status-${s.status || 'confirmed'}">${s.status || 'confirmed'}</div>
    </div>`;
  }).join('');
}

// ── Coaches ───────────────────────────────────────────────
async function loadCoaches() {
  const el = document.getElementById('coaches-grid');
  if (!currentGymId) { el.innerHTML = `<p class="empty-state">${t('noCoaches')}</p>`; return; }

  const { data: coaches } = await sb.from('coach_profiles')
    .select('id, specialty, hourly_rate, rating, total_reviews, users!inner(name, gym_id)')
    .eq('users.gym_id', currentGymId);

  if (!coaches || coaches.length === 0) {
    el.innerHTML = `<p class="empty-state">${t('noCoaches')}</p>`;
    return;
  }
  el.innerHTML = coaches.map(c => {
    const name = c.users?.name || 'Coach';
    const initials = name.split(' ').map(n => n[0]).join('').slice(0,2).toUpperCase();
    return `<div class="person-card" onclick="openCoachModal('${c.id}')" style="cursor:pointer;">
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
  const el = document.getElementById('clients-grid');
  if (!currentGymId) { el.innerHTML = `<p class="empty-state">${t('noClients')}</p>`; return; }

  const { data: clients } = await sb.from('users')
    .select('id, name, created_at')
    .eq('role', 'client')
    .eq('gym_id', currentGymId);

  if (!clients || clients.length === 0) {
    el.innerHTML = `<p class="empty-state">${t('noClients')}</p>`;
    return;
  }
  el.innerHTML = clients.map(c => {
    const initials = (c.name || 'C').split(' ').map(n => n[0]).join('').slice(0,2).toUpperCase();
    const since = new Date(c.created_at).toLocaleDateString('fr-FR', { month:'short', year:'numeric' });
    return `<div class="person-card">
      <div class="person-header">
        <div class="person-avatar">${initials}</div>
        <div><div class="person-name">${c.name || 'Client'}</div><div class="person-role">Client</div></div>
      </div>
      <div class="person-stats">
        <div class="person-stat-item"><div class="person-stat-value" style="font-size:14px;padding-top:4px;">${since}</div><div class="person-stat-label">Depuis</div></div>
      </div>
    </div>`;
  }).join('');
}

// ── Coach modal ───────────────────────────────────────────
async function openCoachModal(coachId) {
  const { data: c } = await sb.from('coach_profiles')
    .select('id, specialty, hourly_rate, bio, rating, total_reviews, created_at, users(name, phone)')
    .eq('id', coachId).single();
  if (!c) return;

  const name = c.users?.name || 'Coach';
  const initials = name.split(' ').map(n => n[0]).join('').slice(0,2).toUpperCase();
  const months = Math.floor((Date.now() - new Date(c.created_at)) / (1000*60*60*24*30));
  const employed = months >= 12 ? `${Math.floor(months/12)}a ${months%12}m` : `${months}m`;

  document.getElementById('coach-modal-body').innerHTML = `
    <div class="modal-header">
      <div class="modal-avatar-lg">${initials}</div>
      <div class="modal-info">
        <h2>${name}</h2>
        <div class="modal-meta">${t('employedLbl')}: ${employed} · ${c.users?.phone || '—'}</div>
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
    </div>`;
  document.getElementById('coach-modal').classList.add('show');
}

// ── Add Coach ─────────────────────────────────────────────
async function submitNewCoach() {
  const name      = document.getElementById('new-coach-name').value.trim();
  const email     = document.getElementById('new-coach-email').value.trim();
  const phone     = document.getElementById('new-coach-phone').value.trim();
  const specialty = document.getElementById('new-coach-specialty').value.trim();
  const rateVal   = document.getElementById('new-coach-rate').value;
  const rate      = rateVal ? parseFloat(rateVal) : null;
  const errEl     = document.getElementById('add-coach-err');

  errEl.classList.remove('show'); errEl.textContent = '';

  if (!name) { errEl.textContent = t('nameMissing'); errEl.classList.add('show'); return; }
  const emailRe = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
  if (!email || !emailRe.test(email)) { errEl.textContent = t('emailMissing'); errEl.classList.add('show'); return; }

  const btn = document.getElementById('btn-submit-coach');
  btn.textContent = '…'; btn.disabled = true;

  try {
    const { data: { session: ownerSession } } = await sb.auth.getSession();
    const tempPw = 'Trainw!' + Math.random().toString(36).slice(2, 10);

    const { data: signUpData, error: signUpErr } = await sb.auth.signUp({
      email, password: tempPw,
      options: { data: { name, role: 'coach', phone: phone || null, gym_id: currentGymId || null } }
    });
    if (signUpErr) throw new Error(signUpErr.message);

    const newUserId = signUpData.user?.id;
    if (!newUserId) throw new Error('No user ID returned');

    // Restore gym owner session
    if (ownerSession) {
      await sb.auth.setSession({
        access_token: ownerSession.access_token,
        refresh_token: ownerSession.refresh_token
      });
    }

    await new Promise(r => setTimeout(r, 800));

    if (currentGymId) {
      await sb.from('users').update({ gym_id: currentGymId, phone: phone || null }).eq('id', newUserId);
    }
    if (specialty || rate) {
      await sb.from('coach_profiles').update({
        specialty: specialty || null,
        hourly_rate: rate
      }).eq('user_id', newUserId);
    }

    toast(t('coachAdded'));
    document.getElementById('add-coach-modal').classList.remove('show');
    ['new-coach-name','new-coach-email','new-coach-phone','new-coach-specialty','new-coach-rate'].forEach(id => {
      document.getElementById(id).value = '';
    });
    await loadCoaches();
    await loadDashboardStats();
  } catch (err) {
    errEl.textContent = err.message;
    errEl.classList.add('show');
  } finally {
    btn.textContent = t('submitCoach'); btn.disabled = false;
  }
}

// ── Save Settings ─────────────────────────────────────────
async function saveSettings() {
  if (!currentGymId) { toast(t('errorMsg')); return; }
  const name = document.getElementById('gym-name-input').value.trim();
  if (!name) { toast('Le nom de la salle est obligatoire'); return; }

  const btn = document.getElementById('btn-save-settings');
  btn.textContent = '…'; btn.disabled = true;
  try {
    const updates = {
      name,
      address:     document.getElementById('gym-address-input').value.trim() || null,
      phone:       document.getElementById('gym-phone-input').value.trim()   || null,
      description: document.getElementById('gym-desc-input').value.trim()   || null,
    };
    const { error } = await sb.from('gyms').update(updates).eq('id', currentGymId);
    if (error) throw new Error(error.message);
    document.getElementById('sidebar-gym-name').textContent = name;
    const ss = document.getElementById('save-status');
    if (ss) { ss.textContent = t('savedOk'); ss.style.color = 'var(--ac)'; setTimeout(() => { ss.textContent = ''; }, 3000); }
    toast(t('savedOk'));
  } catch (err) {
    toast(t('errorMsg') + ' ' + err.message);
  } finally {
    btn.textContent = t('saveChanges'); btn.disabled = false;
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
    localStorage.setItem('trainw_lang', currentLang);
    document.querySelectorAll('.lang-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    applyTranslations();
    renderSchedule();
  });
});

// Set active lang button on load
document.querySelectorAll('.lang-btn').forEach(b => b.classList.remove('active'));
document.querySelector(`.lang-btn[data-lang="${currentLang}"]`)?.classList.add('active');

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

// ── Coach search ──────────────────────────────────────────
document.getElementById('coaches-search')?.addEventListener('input', function () {
  const q = this.value.toLowerCase();
  document.querySelectorAll('#coaches-grid .person-card').forEach(card => {
    card.style.display = card.textContent.toLowerCase().includes(q) ? '' : 'none';
  });
});

// ── Client search ─────────────────────────────────────────
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

// ── Toast ─────────────────────────────────────────────────
function toast(msg, type = 'ok') {
  const el = document.getElementById('toast');
  document.getElementById('toast-msg').textContent = msg;
  el.classList.remove('show', 'toast-err');
  if (type === 'err') el.classList.add('toast-err');
  el.classList.add('show');
  setTimeout(() => el.classList.remove('show'), 3500);
}

applyTranslations();
