// ── Supabase ──────────────────────────────────────────────
const Trainw = window.TrainwCore;
const sb = Trainw.createClient();
Trainw.installGlobalErrorHandlers();

let currentUserId = null;
let currentCoachProfileId = null;
let currentGymId = null;
let currentLang = localStorage.getItem('trainw_lang') || 'fr';

// ── i18n ──────────────────────────────────────────────────
const T = {
  en: {
    roleLabel:'Coach', signOut:'Sign Out',
    navDash:'Dashboard', navSessions:'Sessions', navClients:'Clients',
    navReviews:'Reviews', navProfile:'Profile',
    dashSub:'Your coaching overview',
    statSessions:'Sessions This Week', statClients:'Active Clients',
    statRating:'Avg Rating', statRate:'Hourly Rate',
    upcoming:'upcoming', total:'total', perSession:'per session',
    notesTitle:'Session Note Generator', notesSub:'Generate professional post-session notes quickly',
    aiClientName:'Client Name', aiSessionType:'Session Type',
    aiHighlights:'Key Highlights', aiGenerate:'Generate Notes',
    todaySessions:"Today's Sessions", loading:'Loading…',
    sessionsSub:'Your full training schedule',
    clientsSub:'Track your client progress',
    reviewsSub:'Client feedback',
    avgRating:'Average Rating', totalReviews:'Total Reviews', fiveStars:'5-Star Reviews',
    profileSub:'Manage your coaching profile',
    personalInfo:'Personal Information',
    lName:'Name', lEmail:'Email', lPhone:'Phone',
    lSpecialty:'Specialty', lRate:'Hourly Rate (DT)', lBio:'Bio',
    saveChanges:'Save Changes',
    noSessions:'No sessions yet.',
    noClients:'No clients yet.',
    noReviews:'No reviews yet.',
    savedOk:'Profile saved!', errorMsg:'Something went wrong.',
  },
  fr: {
    roleLabel:'Coach', signOut:'Se Déconnecter',
    navDash:'Tableau de Bord', navSessions:'Séances', navClients:'Clients',
    navReviews:'Avis', navProfile:'Profil',
    dashSub:'Vue d\'ensemble de votre coaching',
    statSessions:'Séances Cette Semaine', statClients:'Clients Actifs',
    statRating:'Note Moyenne', statRate:'Tarif Horaire',
    upcoming:'à venir', total:'total', perSession:'par séance',
    notesTitle:'Générateur de Notes de Séance', notesSub:'Créez des notes professionnelles rapidement',
    aiClientName:'Nom du Client', aiSessionType:'Type de Séance',
    aiHighlights:'Points Clés', aiGenerate:'Générer les Notes',
    todaySessions:'Séances du Jour', loading:'Chargement…',
    sessionsSub:'Votre planning complet',
    clientsSub:'Suivez vos clients',
    reviewsSub:'Avis de vos clients',
    avgRating:'Note Moyenne', totalReviews:'Total Avis', fiveStars:'Avis 5 Étoiles',
    profileSub:'Gérez votre profil de coach',
    personalInfo:'Informations Personnelles',
    lName:'Nom', lEmail:'Email', lPhone:'Téléphone',
    lSpecialty:'Spécialité', lRate:'Tarif Horaire (DT)', lBio:'Bio',
    saveChanges:'Enregistrer',
    noSessions:'Aucune séance pour l\'instant.',
    noClients:'Aucun client pour l\'instant.',
    noReviews:'Aucun avis pour l\'instant.',
    savedOk:'Profil enregistré !', errorMsg:'Une erreur s\'est produite.',
  },
  ar: {
    roleLabel:'مدرب', signOut:'تسجيل الخروج',
    navDash:'لوحة التحكم', navSessions:'الجلسات', navClients:'العملاء',
    navReviews:'التقييمات', navProfile:'الملف الشخصي',
    dashSub:'نظرة عامة على تدريبك',
    statSessions:'جلسات هذا الأسبوع', statClients:'العملاء النشطون',
    statRating:'متوسط التقييم', statRate:'الأجر بالساعة',
    upcoming:'قادمة', total:'إجمالي', perSession:'لكل جلسة',
    notesTitle:'مولّد ملاحظات الجلسات', notesSub:'أنشئ ملاحظات احترافية بسرعة',
    aiClientName:'اسم العميل', aiSessionType:'نوع الجلسة',
    aiHighlights:'النقاط الرئيسية', aiGenerate:'إنشاء الملاحظات',
    todaySessions:'جلسات اليوم', loading:'جار التحميل…',
    sessionsSub:'جدولك الكامل',
    clientsSub:'تابع عملاءك',
    reviewsSub:'آراء عملائك',
    avgRating:'متوسط التقييم', totalReviews:'إجمالي التقييمات', fiveStars:'تقييمات 5 نجوم',
    profileSub:'إدارة ملفك الشخصي',
    personalInfo:'المعلومات الشخصية',
    lName:'الاسم', lEmail:'البريد الإلكتروني', lPhone:'الهاتف',
    lSpecialty:'التخصص', lRate:'الأجر بالساعة (دت)', lBio:'نبذة',
    saveChanges:'حفظ التغييرات',
    noSessions:'لا توجد جلسات بعد.',
    noClients:'لا يوجد عملاء بعد.',
    noReviews:'لا توجد تقييمات بعد.',
    savedOk:'تم الحفظ!', errorMsg:'حدث خطأ ما.',
  }
};
const t = k => T[currentLang][k] || T.en[k] || k;

function locale() {
  return Trainw.localeForLang(currentLang);
}

function applyTranslations() {
  document.querySelectorAll('[data-i18n]').forEach(el => {
    const k = el.getAttribute('data-i18n');
    if (T[currentLang]?.[k]) el.textContent = T[currentLang][k];
  });
  document.documentElement.setAttribute('dir', currentLang === 'ar' ? 'rtl' : 'ltr');
  document.querySelectorAll('.lang-btn').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.lang === currentLang);
  });
}

function enhanceSidebarNavigation() {
  if (window.__trainwCoachNavEnhanced) {
    window.lucide?.createIcons();
    return;
  }
  window.__trainwCoachNavEnhanced = true;

  const iconMap = {
    dashboard: 'layout-dashboard',
    sessions: 'calendar',
    clients: 'user-check',
    reviews: 'bar-chart-2',
    profile: 'settings',
  };

  document.querySelectorAll('.nav-item').forEach(item => {
    const page = item.dataset.page || '';
    const iconEl = item.querySelector('.nav-icon');
    if (iconEl) iconEl.innerHTML = `<i data-lucide="${iconMap[page] || 'circle'}"></i>`;

    const label = Array.from(item.children).find(node => !node.classList?.contains('nav-icon'));
    if (label) label.classList.add('nav-label');
  });

  window.lucide?.createIcons();
}

// ── Init ──────────────────────────────────────────────────
async function legacyInitDisabled() {
  try {
    const { data: { session } } = await sb.auth.getSession();
    if (!session) { window.location.href = 'login.html?role=coach'; return; }
    currentUserId = session.user.id;

    const { data: user } = await sb.from('users').select('name, phone, gym_id').eq('id', currentUserId).single();
    if (user) {
      const sn = document.getElementById('sidebar-coach-name'); if(sn) sn.textContent = user.name || 'Coach';
      const pn = document.getElementById('profile-name');  if(pn) pn.value = user.name  || '';
      const pp = document.getElementById('profile-phone'); if(pp) pp.value = user.phone || '';
      const pe = document.getElementById('profile-email'); if(pe) pe.value = session.user.email || '';
      if (user.gym_id) currentGymId = user.gym_id;
    }

    const { data: coach } = await sb.from('coach_profiles')
      .select('id, specialty, hourly_rate, bio, rating, total_reviews')
      .eq('user_id', currentUserId).single();

    if (coach) {
      currentCoachProfileId = coach.id;
      const set = (id, v) => { const el = document.getElementById(id); if(el) el.textContent = v ?? '—'; };
      set('stat-rating', coach.rating || '—');
      set('stat-reviews-count', (coach.total_reviews || 0) + ' avis');
      const sr = document.getElementById('stat-rate'); if(sr) sr.innerHTML = (coach.hourly_rate || '—') + '<span class="stat-unit">DT</span>';
      const sp = document.getElementById('profile-specialty'); if(sp) sp.value = coach.specialty || '';
      const rp = document.getElementById('profile-rate');      if(rp) rp.value = coach.hourly_rate || '';
      const bp = document.getElementById('profile-bio');       if(bp) bp.value = coach.bio || '';
      set('rev-avg', coach.rating || '—');
      set('rev-total', coach.total_reviews || 0);
    }

    await loadSessions();
    await loadClients();
    await loadReviews();
    applyTranslations();
  } catch(err) {
    console.error('Coach init error:', err);
    const toast_el = document.getElementById('toast');
    const toast_msg = document.getElementById('toast-msg');
    if(toast_el && toast_msg) { toast_msg.textContent = 'Erreur de chargement — rechargez la page'; toast_el.classList.add('show','toast-err'); }
  }
}

// ── Sessions ──────────────────────────────────────────────

// ── Sign Out ──────────────────────────────────────────────
document.getElementById('btn-logout').addEventListener('click', async () => {
  try {
    const result = await Trainw.api.run(sb.auth.signOut(), { context: 'coach sign out' });
    if (result.error) throw result.error;
    window.location.href = 'login.html';
  } catch (error) {
    toast(error.message || t('errorMsg'), 'err');
  }
});

// ── Nav ───────────────────────────────────────────────────
document.querySelectorAll('.nav-item').forEach(item => {
  item.addEventListener('click', () => {
    const page = item.dataset.page;
    document.querySelectorAll('.page').forEach(p => p.classList.add('hidden'));
    document.getElementById(page + '-page').classList.remove('hidden');
    document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
    item.classList.add('active');
  });
});

// ── Lang ──────────────────────────────────────────────────
document.querySelectorAll('.lang-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    currentLang = btn.dataset.lang;
    localStorage.setItem('trainw_lang', currentLang);
    document.querySelectorAll('.lang-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    applyTranslations();
    loadSessions();
    loadClients();
    loadReviews();
  });
});
document.querySelectorAll('.lang-btn').forEach(b => b.classList.remove('active'));
document.querySelector(`.lang-btn[data-lang="${currentLang}"]`)?.classList.add('active');

// ── Wire buttons ──────────────────────────────────────────
document.getElementById('btn-gen-notes').addEventListener('click', generateNotes);
document.getElementById('btn-save-profile').addEventListener('click', saveProfile);

// ── Toast ─────────────────────────────────────────────────
function toast(msg, type) {
  Trainw.ui.showToast(msg, type);
}

async function loadSessions() {
  const today = Trainw.dateOnly(new Date());
  const todayEl = document.getElementById('today-sessions');
  const allEl = document.getElementById('all-sessions');
  if (!todayEl || !allEl || !currentUserId) return;

  let query = sb.from('sessions')
    .select('id, session_date, start_time, duration_minutes, type, status, client_id, session_name, users!sessions_client_id_fkey(name)')
    .eq('coach_id', currentUserId)
    .order('session_date', { ascending: true });
  if (currentGymId) {
    query = query.eq('gym_id', currentGymId);
  }

  const result = await Trainw.api.run(query, {
    context: 'load coach sessions',
    fallback: [],
  });
  const sessions = Array.isArray(result.data) ? result.data : [];

  if (!sessions.length) {
    todayEl.innerHTML = `<p class="empty-state">${t('noSessions')}</p>`;
    allEl.innerHTML = `<p class="empty-state">${t('noSessions')}</p>`;
    Trainw.ui.setText('stat-sessions', '0', '0');
    if (!document.getElementById('stat-clients')?.textContent?.trim()) {
      Trainw.ui.setText('stat-clients', '0', '0');
    }
    if (result.error) toast(t('errorMsg'), 'err');
    return;
  }

  const now = new Date();
  const weekStart = new Date(now);
  weekStart.setHours(0, 0, 0, 0);
  weekStart.setDate(now.getDate() - now.getDay());
  const weekEnd = new Date(weekStart);
  weekEnd.setDate(weekStart.getDate() + 6);
  const weekCount = sessions.filter(session => {
    const date = new Date(session.session_date);
    return !Number.isNaN(date.getTime()) && date >= weekStart && date <= weekEnd;
  }).length;
  Trainw.ui.setText('stat-sessions', String(weekCount), '0');

  const renderSession = function (session, showDate) {
    const clientName = Trainw.escapeHtml(session.users?.name || 'Client');
    const time = Trainw.escapeHtml(session.start_time?.slice(0, 5) || '—');
    const typeLabel = Trainw.escapeHtml((session.session_name || session.type || 'Training').replace(/_/g, ' '));
    const dateLabel = showDate
      ? new Date(session.session_date).toLocaleDateString(locale(), { weekday: 'short', day: 'numeric', month: 'short' })
      : '';
    const status = Trainw.escapeHtml(session.status || 'confirmed');

    return `<div class="session-item">
      <div class="session-time-col"><div class="session-time">${time}</div><div class="session-dur">${session.duration_minutes ?? 60}min</div></div>
      <div><div class="session-title">${clientName}</div><div class="session-meta">${typeLabel}${dateLabel ? ' • ' + Trainw.escapeHtml(dateLabel) : ''}</div></div>
      <div class="session-status status-${status}">${status}</div>
    </div>`;
  };

  const todaySessions = sessions.filter(session => session.session_date === today);
  const displayToday = todaySessions.length ? todaySessions : sessions.slice(0, 5);
  todayEl.innerHTML = displayToday.length
    ? displayToday.map(session => renderSession(session, todaySessions.length === 0)).join('')
    : `<p class="empty-state">${t('noSessions')}</p>`;
  allEl.innerHTML = sessions.map(session => renderSession(session, true)).join('');

  if (result.error) {
    toast(t('errorMsg'), 'err');
  }
}

async function loadClients() {
  const grid = document.getElementById('clients-grid');
  if (!grid || !currentUserId) return;

  const result = await Trainw.api.run(
    sb.from('sessions')
      .select('client_id, users!sessions_client_id_fkey(name)')
      .eq('coach_id', currentUserId),
    {
      context: 'load coach clients',
      fallback: [],
    }
  );
  const sessionData = Array.isArray(result.data) ? result.data : [];

  if (!sessionData.length) {
    grid.innerHTML = `<p class="empty-state">${t('noClients')}</p>`;
    Trainw.ui.setText('stat-clients', '0', '0');
    if (result.error) toast(t('errorMsg'), 'err');
    return;
  }

  const map = new Map();
  sessionData.forEach(session => {
    if (!session?.client_id) return;
    if (!map.has(session.client_id)) {
      map.set(session.client_id, {
        name: session.users?.name || 'Client',
        count: 0,
      });
    }
    map.get(session.client_id).count += 1;
  });

  const clients = Array.from(map.values());
  Trainw.ui.setText('stat-clients', String(clients.length), '0');
  grid.innerHTML = clients.map(client => {
    const safeName = Trainw.escapeHtml(client.name || 'Client');
    const initials = Trainw.escapeHtml((client.name || 'C').split(' ').map(part => part[0]).join('').slice(0, 2).toUpperCase());
    return `<div class="person-card">
      <div class="person-header">
        <div class="person-avatar">${initials}</div>
        <div><div class="person-name">${safeName}</div><div class="person-role">Client</div></div>
      </div>
      <div class="person-stats">
        <div class="person-stat-item"><div class="person-stat-value">${client.count}</div><div class="person-stat-label">Sessions</div></div>
      </div>
    </div>`;
  }).join('');

  if (result.error) {
    toast(t('errorMsg'), 'err');
  }
}

async function loadReviews() {
  const el = document.getElementById('reviews-list');
  if (!el) return;

  const revFive = document.getElementById('rev-five');
  if (!currentCoachProfileId) {
    if (revFive) revFive.textContent = '0';
    el.innerHTML = `<p class="empty-state">${t('noReviews')}</p>`;
    return;
  }

  const result = await Trainw.api.run(
    sb.from('reviews')
      .select('rating, comment, created_at')
      .eq('coach_id', currentCoachProfileId)
      .order('created_at', { ascending: false }),
    {
      context: 'load coach reviews',
      fallback: [],
      silent: true,
    }
  );
  const reviews = Array.isArray(result.data) ? result.data : [];

  if (!reviews.length) {
    if (revFive) revFive.textContent = '0';
    el.innerHTML = `<p class="empty-state">${t('noReviews')}</p>`;
    return;
  }

  const fiveStar = reviews.filter(review => Number(review.rating) === 5).length;
  if (revFive) revFive.textContent = String(fiveStar);
  el.innerHTML = reviews.map(review => {
    const createdAt = new Date(review.created_at);
    const diffDays = Number.isNaN(createdAt.getTime())
      ? null
      : Math.floor((Date.now() - createdAt.getTime()) / 86400000);
    const when = diffDays === null
      ? '—'
      : diffDays === 0
        ? 'Aujourd\'hui'
        : diffDays === 1
          ? 'Hier'
          : `${diffDays} jours`;
    return `<div class="review-item">
      <div class="review-header"><span class="review-rating">★ ${Number(review.rating) || 0}</span></div>
      <div class="review-text">${Trainw.escapeHtml(review.comment || '')}</div>
      <div class="review-date">${Trainw.escapeHtml(when)}</div>
    </div>`;
  }).join('');
}

async function saveProfile() {
  const name = document.getElementById('profile-name')?.value.trim() || '';
  const phone = document.getElementById('profile-phone')?.value.trim() || '';
  const specialty = document.getElementById('profile-specialty')?.value.trim() || '';
  const rateRaw = document.getElementById('profile-rate')?.value;
  const rate = rateRaw && !Number.isNaN(parseFloat(rateRaw)) ? parseFloat(rateRaw) : null;
  const bio = document.getElementById('profile-bio')?.value.trim() || '';
  const btn = document.getElementById('btn-save-profile');
  const status = document.getElementById('coach-save-status');

  if (!name) {
    toast(t('errorMsg'), 'err');
    return;
  }

  Trainw.ui.setBusy(btn, true);
  if (btn) btn.textContent = '…';
  if (status) status.textContent = '';

  try {
    const userResult = await Trainw.api.run(
      sb.from('users').update({ name, phone: phone || null }).eq('id', currentUserId),
      {
        context: 'save coach user profile',
      }
    );
    if (userResult.error) throw userResult.error;

    if (currentCoachProfileId) {
      const coachResult = await Trainw.api.run(
        sb.from('coach_profiles').update({
          specialty: specialty || null,
          hourly_rate: rate,
          bio: bio || null,
        }).eq('id', currentCoachProfileId),
        {
          context: 'save coach profile details',
        }
      );
      if (coachResult.error) throw coachResult.error;
    }

    Trainw.ui.setText('sidebar-coach-name', name, 'Coach');
    toast(t('savedOk'));
    if (status) {
      status.textContent = t('savedOk');
      status.style.color = 'var(--ac)';
      window.setTimeout(() => {
        status.textContent = '';
      }, 3000);
    }
  } catch (error) {
    toast(error.message || t('errorMsg'), 'err');
  } finally {
    if (btn) btn.textContent = t('saveChanges');
    Trainw.ui.setBusy(btn, false);
  }
}

async function generateNotes() {
  const client = document.getElementById('ai-client-name')?.value.trim() || '';
  const type = document.getElementById('ai-session-type')?.value || '';
  const highlights = document.getElementById('ai-highlights')?.value.trim() || '';
  const btn = document.getElementById('btn-gen-notes');
  const outEl = document.getElementById('ai-output-text');
  const outWrap = document.getElementById('ai-output');

  if (!client || !highlights) {
    toast(t('errorMsg'), 'err');
    return;
  }

  Trainw.ui.setBusy(btn, true);
  if (btn) btn.textContent = '…';
  if (outEl) outEl.textContent = 'Génération en cours…';
  if (outWrap) outWrap.classList.remove('hidden');

  try {
    const data = await Trainw.api.edge(sb, 'session_notes', {
      clientName: client,
      sessionType: type,
      highlights,
    });
    if (!data?.result) {
      throw new Error('Empty notes response');
    }
    if (outEl) outEl.textContent = data.result;
    toast(t('savedOk'));
  } catch (error) {
    const fallback = `NOTES DE SÉANCE — ${new Date().toLocaleDateString(locale())}\n\nClient: ${client}\nType: ${type}\n\nPoints clés:\n${highlights}\n\nÀ surveiller lors de la prochaine séance.`;
    if (outEl) outEl.textContent = fallback;
    toast(error.message ? `Notes générées (${error.message})` : 'Notes générées (mode local)');
  } finally {
    if (btn) btn.textContent = t('aiGenerate');
    Trainw.ui.setBusy(btn, false);
  }
}

async function initPage() {
  enhanceSidebarNavigation();

  const context = await Trainw.auth.getContext(sb, {
    expectedRoles: ['coach'],
    loginHref: 'login.html?role=coach',
  });
  if (!context.session || !context.profile) {
    return;
  }

  currentUserId = context.session.user.id;
  currentGymId = context.profile.gym_id || null;
  document.querySelector('.main-content')?.classList.add('page-loaded');

  Trainw.ui.setText('sidebar-coach-name', context.profile.name || 'Coach', 'Coach');
  Trainw.ui.setValue('profile-name', context.profile.name || '', '');
  Trainw.ui.setValue('profile-phone', context.profile.phone || '', '');
  Trainw.ui.setValue('profile-email', context.session.user.email || context.profile.email || '', '');

  const coachResult = await Trainw.api.run(
    sb.from('coach_profiles')
      .select('id, specialty, hourly_rate, bio, rating, total_reviews')
      .eq('user_id', currentUserId)
      .maybeSingle(),
    {
      context: 'load coach profile',
      fallback: null,
    }
  );
  const coach = coachResult.data;

  if (coach) {
    currentCoachProfileId = coach.id;
    Trainw.ui.setText('stat-rating', coach.rating || '—', '—');
    Trainw.ui.setText('stat-reviews-count', `${coach.total_reviews || 0} avis`, '0 avis');
    const statRate = document.getElementById('stat-rate');
    if (statRate) statRate.innerHTML = `${coach.hourly_rate || '—'}<span class="stat-unit">DT</span>`;
    Trainw.ui.setValue('profile-specialty', coach.specialty || '', '');
    Trainw.ui.setValue('profile-rate', coach.hourly_rate || '', '');
    Trainw.ui.setValue('profile-bio', coach.bio || '', '');
    Trainw.ui.setText('rev-avg', coach.rating || '—', '—');
    Trainw.ui.setText('rev-total', coach.total_reviews || 0, '0');
  } else {
    currentCoachProfileId = null;
    Trainw.ui.setText('rev-avg', '—', '—');
    Trainw.ui.setText('rev-total', '0', '0');
    Trainw.ui.setText('rev-five', '0', '0');
  }

  applyTranslations();
  await Promise.all([loadSessions(), loadClients(), loadReviews()]);

  if (!window.__trainwCoachAuthBound) {
    window.__trainwCoachAuthBound = true;
    Trainw.auth.watchAuth(sb, {
      onSignedOut: function () {
        window.location.href = 'login.html?role=coach';
      },
    });
  }
}

initPage();

