// ── Supabase ──────────────────────────────────────────────
const sb = window.supabase.createClient(
  'https://bibqumevndfykmkssslb.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJpYnF1bWV2bmRmeWtta3Nzc2xiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMzNjM1NzAsImV4cCI6MjA4ODkzOTU3MH0.X51EBM0ERPiMmGE2kP18JRrqrF4O6ebA_c2oCdP6wEM'
);

let currentUserId = null;
let currentCoachProfileId = null;
let currentLang = 'en';

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
    aiTitle:'AI Session Notes', aiSub:'Auto-generate professional post-session notes',
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
    aiTitle:'Notes IA', aiSub:'Générer des notes de séance professionnelles',
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
  }
};
const t = k => T[currentLang][k] || T.en[k] || k;

function applyTranslations() {
  document.querySelectorAll('[data-i18n]').forEach(el => {
    const k = el.getAttribute('data-i18n');
    if (T[currentLang][k]) el.textContent = T[currentLang][k];
  });
}

// ── Init ──────────────────────────────────────────────────
(async () => {
  const { data: { session } } = await sb.auth.getSession();
  if (!session) { window.location.href = 'TW Login.html?role=coach'; return; }
  currentUserId = session.user.id;

  // Load user info
  const { data: user } = await sb.from('users').select('name, phone').eq('id', currentUserId).single();
  if (user) {
    document.getElementById('sidebar-coach-name').textContent = user.name || 'Coach';
    document.getElementById('profile-name').value  = user.name  || '';
    document.getElementById('profile-phone').value = user.phone || '';
    document.getElementById('profile-email').value = session.user.email || '';
  }

  // Load coach_profiles row (FIXED: was querying 'coaches' — wrong table)
  const { data: coach } = await sb.from('coach_profiles')
    .select('id, specialty, hourly_rate, bio, rating, total_reviews')
    .eq('user_id', currentUserId).single();

  if (coach) {
    currentCoachProfileId = coach.id;
    document.getElementById('stat-rating').textContent  = coach.rating       || '—';
    document.getElementById('stat-reviews-count').textContent = (coach.total_reviews || 0) + ' reviews';
    document.getElementById('stat-rate').innerHTML = (coach.hourly_rate || '—') + '<span class="stat-unit">DT</span>';
    document.getElementById('profile-specialty').value = coach.specialty    || '';
    document.getElementById('profile-rate').value      = coach.hourly_rate  || '';
    document.getElementById('profile-bio').value       = coach.bio          || '';
    document.getElementById('rev-avg').textContent     = coach.rating       || '—';
    document.getElementById('rev-total').textContent   = coach.total_reviews || 0;
  }

  await loadSessions();
  await loadClients();
  await loadReviews();
  applyTranslations();
})();

// ── Sessions ──────────────────────────────────────────────
async function loadSessions() {
  const today = new Date().toISOString().split('T')[0];
  const { data: sessions } = await sb.from('sessions')
    .select('id, session_date, start_time, duration_minutes, type, status, client_id, users!sessions_client_id_fkey(name)')
    .eq('coach_id', currentUserId)
    .order('session_date', { ascending: true });

  if (!sessions || sessions.length === 0) {
    ['today-sessions','all-sessions'].forEach(id => {
      document.getElementById(id).innerHTML = `<p class="empty-state">${t('noSessions')}</p>`;
    });
    document.getElementById('stat-sessions').textContent = '0';
    document.getElementById('stat-clients').textContent  = '0';
    return;
  }

  // Week stats
  const now = new Date();
  const weekStart = new Date(now); weekStart.setDate(now.getDate() - now.getDay());
  const weekEnd   = new Date(weekStart); weekEnd.setDate(weekStart.getDate() + 6);
  const weekCount = sessions.filter(s => { const d = new Date(s.session_date); return d >= weekStart && d <= weekEnd; }).length;
  document.getElementById('stat-sessions').textContent = weekCount;

  // Render helper
  const renderSession = (s, showDate = false) => {
    const clientName = s.users?.name || 'Client';
    const time = s.start_time?.slice(0,5) || '—';
    const type = (s.type || 'Training').replace(/_/g,' ');
    const dateStr = showDate ? new Date(s.session_date).toLocaleDateString('en-GB', { weekday:'short', day:'numeric', month:'short' }) : '';
    return `<div class="session-item">
      <div class="session-time-col"><div class="session-time">${time}</div><div class="session-dur">${s.duration_minutes ?? 60}min</div></div>
      <div><div class="session-title">${clientName}</div><div class="session-meta">${type}${dateStr ? ' • ' + dateStr : ''}</div></div>
      <div class="session-status status-${s.status || 'confirmed'}">${s.status || 'confirmed'}</div>
    </div>`;
  };

  const todaySessions = sessions.filter(s => s.session_date === today);
  const displayToday  = todaySessions.length > 0 ? todaySessions : sessions.slice(0, 5);
  document.getElementById('today-sessions').innerHTML = displayToday.map(s => renderSession(s, todaySessions.length === 0)).join('') || `<p class="empty-state">${t('noSessions')}</p>`;
  document.getElementById('all-sessions').innerHTML   = sessions.map(s => renderSession(s, true)).join('');
}

// ── Clients ───────────────────────────────────────────────
async function loadClients() {
  const { data: sessionData } = await sb.from('sessions')
    .select('client_id, users!sessions_client_id_fkey(name)')
    .eq('coach_id', currentUserId);

  if (!sessionData || sessionData.length === 0) {
    document.getElementById('clients-grid').innerHTML = `<p class="empty-state">${t('noClients')}</p>`;
    document.getElementById('stat-clients').textContent = '0';
    return;
  }

  // Deduplicate clients
  const map = {};
  sessionData.forEach(s => {
    const id = s.client_id;
    if (!map[id]) map[id] = { name: s.users?.name || 'Client', count: 0 };
    map[id].count++;
  });

  const clients = Object.values(map);
  document.getElementById('stat-clients').textContent = clients.length;
  document.getElementById('clients-grid').innerHTML = clients.map(c => {
    const initials = c.name.split(' ').map(n => n[0]).join('').slice(0,2);
    return `<div class="person-card">
      <div class="person-header">
        <div class="person-avatar">${initials}</div>
        <div><div class="person-name">${c.name}</div><div class="person-role">Client</div></div>
      </div>
      <div class="person-stats">
        <div class="person-stat-item"><div class="person-stat-value">${c.count}</div><div class="person-stat-label">Sessions</div></div>
      </div>
    </div>`;
  }).join('');
}

// ── Reviews ───────────────────────────────────────────────
async function loadReviews() {
  if (!currentCoachProfileId) return;
  const { data: reviews } = await sb.from('reviews')
    .select('rating, comment, created_at, client_profiles(users(name))')
    .eq('coach_id', currentCoachProfileId)
    .order('created_at', { ascending: false });

  if (!reviews || reviews.length === 0) {
    document.getElementById('reviews-list').innerHTML = `<p class="empty-state">${t('noReviews')}</p>`;
    return;
  }

  const fiveStar = reviews.filter(r => r.rating === 5).length;
  document.getElementById('rev-five').textContent = fiveStar;

  document.getElementById('reviews-list').innerHTML = reviews.map(r => {
    const days = Math.floor((Date.now() - new Date(r.created_at)) / 86400000);
    const when = days === 0 ? 'Today' : days === 1 ? 'Yesterday' : `${days} days ago`;
    const name = r.client_profiles?.users?.name || 'Client';
    return `<div class="review-item">
      <div class="review-header"><span class="review-client">${name}</span><span class="review-rating">★ ${r.rating}</span></div>
      <div class="review-text">${r.comment || ''}</div>
      <div class="review-date">${when}</div>
    </div>`;
  }).join('');
}

// ── Save Profile ──────────────────────────────────────────
async function saveProfile() {
  const name      = document.getElementById('profile-name').value.trim();
  const phone     = document.getElementById('profile-phone').value.trim();
  const specialty = document.getElementById('profile-specialty').value.trim();
  const rate      = parseFloat(document.getElementById('profile-rate').value);
  const bio       = document.getElementById('profile-bio').value.trim();

  const btn = document.getElementById('btn-save-profile');
  btn.textContent = '…'; btn.disabled = true;
  try {
    await sb.from('users').update({ name, phone }).eq('id', currentUserId);
    if (currentCoachProfileId) {
      await sb.from('coach_profiles').update({ specialty, hourly_rate: rate, bio }).eq('id', currentCoachProfileId);
    }
    document.getElementById('sidebar-coach-name').textContent = name;
    toast(t('savedOk'));
  } catch (err) {
    toast('Error: ' + err.message);
  } finally {
    btn.textContent = t('saveChanges'); btn.disabled = false;
  }
}

// ── AI Session Notes ──────────────────────────────────────
function generateNotes() {
  const client  = document.getElementById('ai-client-name').value.trim();
  const type    = document.getElementById('ai-session-type').value;
  const highlights = document.getElementById('ai-highlights').value.trim();
  if (!client || !highlights) { toast(t('errorMsg')); return; }

  const notes = `SESSION NOTES — ${new Date().toLocaleDateString()}

Client: ${client}
Session Type: ${type}
Duration: 60 minutes

PERFORMANCE SUMMARY:
${highlights}

OBSERVATIONS:
- Client demonstrated strong commitment throughout the session
- Form and technique monitored with real-time corrections
- Energy levels remained consistent

RECOMMENDATIONS:
- Continue current training intensity
- Monitor any mentioned discomfort and adjust accordingly
- Follow-up assessment in 2 weeks

NEXT SESSION FOCUS:
- Progressive overload on primary lifts
- Address form weaknesses identified today
- Add mobility work for injury prevention`;

  document.getElementById('ai-output-text').textContent = notes;
  document.getElementById('ai-output').classList.remove('hidden');
  toast('Notes generated!');
}

// ── Sign Out ──────────────────────────────────────────────
document.getElementById('btn-logout').addEventListener('click', async () => {
  await sb.auth.signOut();
  window.location.href = 'TW Login.html';
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
    document.querySelectorAll('.lang-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    applyTranslations();
  });
});

// ── Wire buttons ──────────────────────────────────────────
document.getElementById('btn-gen-notes').addEventListener('click', generateNotes);
document.getElementById('btn-save-profile').addEventListener('click', saveProfile);

// ── Toast ─────────────────────────────────────────────────
function toast(msg) {
  const el = document.getElementById('toast');
  document.getElementById('toast-msg').textContent = msg;
  el.classList.add('show');
  setTimeout(() => el.classList.remove('show'), 3000);
}

applyTranslations();
