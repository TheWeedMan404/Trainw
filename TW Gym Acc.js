const sb = window.supabase.createClient(
  'https://bibqumevndfykmkssslb.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJpYnF1bWV2bmRmeWtta3Nzc2xiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMzNjM1NzAsImV4cCI6MjA4ODkzOTU3MH0.X51EBM0ERPiMmGE2kP18JRrqrF4O6ebA_c2oCdP6wEM'
);

let currentUser   = null;
let currentGymId  = null;
let currentLang   = localStorage.getItem('trainw_lang') || 'fr';
let scheduleFilter = 'all';
let clientFilter   = 'all';
let allSessions    = [];
let allClients     = [];
let gymCoaches     = [];

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
    comingSoon:'Bientôt disponible',
    topCoaches:'Meilleurs Coachs', recentSessions:'Séances Récentes',
    loading:'Chargement…',
    schedSub:'Toutes les séances de votre salle',
    filterAll:'Tout', filterConfirmed:'Confirmé', filterPending:'En attente', filterCompleted:'Terminé',
    filterPaid:'Payé',
    createSession:'+ Créer une Séance', createSessionTitle:'Créer une Séance',
    sessName:'Nom de la Séance', sessType:'Type de Séance', sessCategory:'Catégorie',
    sessDate:'Date', sessTime:'Heure', sessDuration:'Durée (min)', sessCapacity:'Capacité Max',
    sessCoach:'Coach Assigné', optional:'(optionnel)', noCoachOpt:'— Aucun coach —',
    groupClass:'Cours Collectif', groupActivity:'Activité de Groupe', individualTraining:'Entraînement Individuel',
    coachesSub:'Gérez votre équipe de coachs', addCoach:'+ Ajouter un Coach',
    clientsSub:'Tous les membres de votre salle', addClient:'+ Ajouter un Client',
    addClientTitle:'Ajouter un Client', clientName:'Nom Complet', clientAge:'Âge',
    clientPhone:'Téléphone', clientMembership:"Type d'Abonnement", clientTraining:"Type d'Entraînement",
    paymentStatus:'Statut Paiement', paid:'Payé', submitClient:'Ajouter le Client',
    monthly:'Mensuel', quarterly:'Trimestriel', annual:'Annuel', perSession:'À la séance',
    bizMetrics:'Métriques Générales', finMetrics:'Métriques Financières', opsMetrics:'Opérations',
    coachRevenue:'Revenus Coachs', monthlyRevenue:'Revenu Mensuel',
    popularClasses:'Cours Populaires', coachUtil:'Utilisation des Coachs',
    analyticsHint:'Connectez les paiements pour voir les revenus par coach',
    analyticsHint2:'Activez les paiements pour voir les revenus mensuels',
    settingsSub:'Configurez votre salle', gymInfo:'Informations de la Salle',
    gymNameLbl:'Nom de la Salle', addressLbl:'Adresse', phoneLbl:'Téléphone', descLbl:'Description',
    saveChanges:'Enregistrer',
    accountSettings:'Compte', currentEmail:'Email actuel', changePassword:'Changer le mot de passe',
    subscription:'Abonnement', freeTier:'Essai Gratuit',
    subDesc:'Passez au plan Pro pour débloquer toutes les fonctionnalités',
    upgradePro:'Passer au Pro →',
    langSettings:'Langue', support:'Support', contactSupport:'Contacter le Support',
    addCoachTitle:'Ajouter un Coach', coachName:'Nom Complet', coachEmail:'Email',
    coachPhone:'Téléphone', coachSpecialty:'Spécialité', coachRate:'Tarif Horaire (DT)',
    submitCoach:'Ajouter le Coach',
    noCoaches:'Aucun coach. Ajoutez votre premier coach !',
    noClients:'Aucun client. Ajoutez votre premier client !',
    noSessions:'Aucune séance trouvée.',
    savedOk:'Enregistré !', coachAdded:'Coach ajouté !', clientAdded:'Client ajouté !', sessionCreated:'Séance créée !',
    errorMsg:'Une erreur est survenue.',
    hourlyRate:'Tarif/h', avgRating:'Note',
    employedLbl:'Ancienneté', totalReviews:'Avis',
    emailMissing:'Veuillez saisir un email valide.',
    nameMissing:'Veuillez saisir un nom.',
    sessNameMissing:'Veuillez saisir un nom de séance.',
    sessDateMissing:'Veuillez choisir une date.',
    sessTimeMissing:'Veuillez choisir une heure.',
    memberSince:'Membre depuis', membership:'Abonnement', training:'Entraînement',
    payment:'Paiement', editClient:'Modifier', deleteClient:'Supprimer',
    pwReset:'Email de réinitialisation envoyé !',
  },
  en: {
    gymOwner:'Gym Owner', signOut:'Sign Out',
    navDashboard:'Dashboard', navSchedule:'Schedule', navCoaches:'Coaches',
    navClients:'Clients', navAnalytics:'Analytics', navSettings:'Settings',
    dashSub:'Your gym at a glance',
    statClients:'Active Clients', statCoaches:'Active Coaches',
    statSessions:'Sessions This Week', statRevenue:'Monthly Revenue',
    thisMonth:'this month', onStaff:'on staff', vsLastWeek:'this week',
    comingSoon:'Coming soon',
    topCoaches:'Top Coaches', recentSessions:'Recent Sessions',
    loading:'Loading…',
    schedSub:'All sessions across your gym',
    filterAll:'All', filterConfirmed:'Confirmed', filterPending:'Pending', filterCompleted:'Completed',
    filterPaid:'Paid',
    createSession:'+ Create Session', createSessionTitle:'Create Session',
    sessName:'Session Name', sessType:'Session Type', sessCategory:'Category',
    sessDate:'Date', sessTime:'Time', sessDuration:'Duration (min)', sessCapacity:'Max Capacity',
    sessCoach:'Assigned Coach', optional:'(optional)', noCoachOpt:'— No coach —',
    groupClass:'Group Class', groupActivity:'Group Activity', individualTraining:'Individual Training',
    coachesSub:'Manage your coaching staff', addCoach:'+ Add Coach',
    clientsSub:'All gym members', addClient:'+ Add Client',
    addClientTitle:'Add Client', clientName:'Full Name', clientAge:'Age',
    clientPhone:'Phone', clientMembership:'Membership Type', clientTraining:'Training Type',
    paymentStatus:'Payment Status', paid:'Paid', submitClient:'Add Client',
    monthly:'Monthly', quarterly:'Quarterly', annual:'Annual', perSession:'Per Session',
    bizMetrics:'General Metrics', finMetrics:'Financial Metrics', opsMetrics:'Operations',
    coachRevenue:'Coach Revenue', monthlyRevenue:'Monthly Revenue',
    popularClasses:'Popular Classes', coachUtil:'Coach Utilization',
    analyticsHint:'Connect payments to see revenue per coach',
    analyticsHint2:'Enable payments to see monthly revenue',
    settingsSub:'Configure your gym', gymInfo:'Gym Information',
    gymNameLbl:'Gym Name', addressLbl:'Address', phoneLbl:'Phone', descLbl:'Description',
    saveChanges:'Save Changes',
    accountSettings:'Account', currentEmail:'Current Email', changePassword:'Change Password',
    subscription:'Subscription', freeTier:'Free Trial',
    subDesc:'Upgrade to Pro to unlock all features',
    upgradePro:'Upgrade to Pro →',
    langSettings:'Language', support:'Support', contactSupport:'Contact Support',
    addCoachTitle:'Add New Coach', coachName:'Full Name', coachEmail:'Email',
    coachPhone:'Phone', coachSpecialty:'Specialty', coachRate:'Hourly Rate (DT)',
    submitCoach:'Add Coach',
    noCoaches:'No coaches yet. Add your first coach!',
    noClients:'No clients yet. Add your first client!',
    noSessions:'No sessions found.',
    savedOk:'Saved!', coachAdded:'Coach added!', clientAdded:'Client added!', sessionCreated:'Session created!',
    errorMsg:'Something went wrong.',
    hourlyRate:'Rate/h', avgRating:'Rating',
    employedLbl:'Employed', totalReviews:'Reviews',
    emailMissing:'Please enter a valid email.',
    nameMissing:'Please enter a name.',
    sessNameMissing:'Please enter a session name.',
    sessDateMissing:'Please choose a date.',
    sessTimeMissing:'Please choose a time.',
    memberSince:'Member since', membership:'Membership', training:'Training',
    payment:'Payment', editClient:'Edit', deleteClient:'Delete',
    pwReset:'Reset email sent!',
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
    filterAll:'الكل', filterConfirmed:'مؤكد', filterPending:'معلق', filterCompleted:'منتهي',
    filterPaid:'مدفوع',
    createSession:'+ إنشاء جلسة', createSessionTitle:'إنشاء جلسة',
    sessName:'اسم الجلسة', sessType:'نوع الجلسة', sessCategory:'الفئة',
    sessDate:'التاريخ', sessTime:'الوقت', sessDuration:'المدة (دقيقة)', sessCapacity:'الطاقة القصوى',
    sessCoach:'المدرب المعيّن', optional:'(اختياري)', noCoachOpt:'— بدون مدرب —',
    groupClass:'فصل جماعي', groupActivity:'نشاط جماعي', individualTraining:'تدريب فردي',
    coachesSub:'إدارة فريق المدربين', addCoach:'+ إضافة مدرب',
    clientsSub:'جميع أعضاء الصالة', addClient:'+ إضافة عميل',
    addClientTitle:'إضافة عميل', clientName:'الاسم الكامل', clientAge:'العمر',
    clientPhone:'الهاتف', clientMembership:'نوع الاشتراك', clientTraining:'نوع التدريب',
    paymentStatus:'حالة الدفع', paid:'مدفوع', submitClient:'إضافة العميل',
    monthly:'شهري', quarterly:'ربع سنوي', annual:'سنوي', perSession:'لكل جلسة',
    bizMetrics:'المقاييس العامة', finMetrics:'المقاييس المالية', opsMetrics:'العمليات',
    coachRevenue:'إيرادات المدربين', monthlyRevenue:'الإيرادات الشهرية',
    popularClasses:'الفصول الشائعة', coachUtil:'استخدام المدربين',
    analyticsHint:'ربط المدفوعات لعرض الإيرادات',
    analyticsHint2:'تفعيل المدفوعات لعرض الإيرادات الشهرية',
    settingsSub:'إعداد صالتك', gymInfo:'معلومات الصالة',
    gymNameLbl:'اسم الصالة', addressLbl:'العنوان', phoneLbl:'الهاتف', descLbl:'الوصف',
    saveChanges:'حفظ التغييرات',
    accountSettings:'الحساب', currentEmail:'البريد الحالي', changePassword:'تغيير كلمة المرور',
    subscription:'الاشتراك', freeTier:'تجربة مجانية',
    subDesc:'ترقية إلى Pro لفتح جميع الميزات',
    upgradePro:'الترقية إلى Pro ←',
    langSettings:'اللغة', support:'الدعم', contactSupport:'تواصل مع الدعم',
    addCoachTitle:'إضافة مدرب', coachName:'الاسم الكامل', coachEmail:'البريد الإلكتروني',
    coachPhone:'الهاتف', coachSpecialty:'التخصص', coachRate:'الأجر بالساعة (دت)',
    submitCoach:'إضافة المدرب',
    noCoaches:'لا يوجد مدربون بعد.',
    noClients:'لا يوجد عملاء بعد.',
    noSessions:'لا توجد جلسات.',
    savedOk:'تم الحفظ!', coachAdded:'تمت إضافة المدرب!', clientAdded:'تمت إضافة العميل!', sessionCreated:'تم إنشاء الجلسة!',
    errorMsg:'حدث خطأ ما.',
    hourlyRate:'الأجر/ساعة', avgRating:'التقييم',
    employedLbl:'مدة العمل', totalReviews:'التقييمات',
    emailMissing:'الرجاء إدخال بريد إلكتروني صحيح.',
    nameMissing:'الرجاء إدخال الاسم.',
    sessNameMissing:'الرجاء إدخال اسم الجلسة.',
    sessDateMissing:'الرجاء اختيار تاريخ.',
    sessTimeMissing:'الرجاء اختيار وقت.',
    memberSince:'عضو منذ', membership:'الاشتراك', training:'التدريب',
    payment:'الدفع', editClient:'تعديل', deleteClient:'حذف',
    pwReset:'تم إرسال رابط الاسترداد!',
  }
};
const t = k => T[currentLang]?.[k] || T.fr[k] || k;

function applyTranslations() {
  document.querySelectorAll('[data-i18n]').forEach(el => {
    const k = el.getAttribute('data-i18n');
    if (T[currentLang]?.[k]) el.textContent = T[currentLang][k];
  });
  document.documentElement.setAttribute('dir', currentLang === 'ar' ? 'rtl' : 'ltr');
  // sync settings lang buttons
  document.querySelectorAll('.lang-option-btn').forEach(b => {
    b.classList.toggle('active', b.dataset.lang === currentLang);
  });
  document.querySelectorAll('.lang-btn').forEach(b => {
    b.classList.toggle('active', b.dataset.lang === currentLang);
  });
}

// ── Session categories ────────────────────────────────────
const SESSION_CATEGORIES = {
  group_class: ['Yoga','HIIT','Cardio','Pilates','CrossFit','Zumba','Musculation','Mobilité','Stretching','Fonctionnel','Spinning','Bootcamp'],
  group_activity: ['Piscine','Terrain de Football','Court de Tennis','Basketball','Volleyball','Sauna','Salle Libre','Piste de Course'],
  individual: ['Entraînement Personnel','Boxe Privée','Coaching Musculation','Coaching Perte de Poids','Conditionnement Athlétique','Rééducation']
};

function updateSessionCategory() {
  const type = document.getElementById('sess-type').value;
  const sel  = document.getElementById('sess-category');
  const cats = SESSION_CATEGORIES[type] || [];
  sel.innerHTML = cats.map(c => `<option value="${c}">${c}</option>`).join('');
  // coach optional only for group_activity
  const coachGroup = document.getElementById('sess-coach-group');
  const coachLabel = coachGroup?.querySelector('.form-label');
  if (type === 'group_activity') {
    if (coachLabel) coachLabel.innerHTML = t('sessCoach') + ` <span style="color:var(--mt);font-size:10px;">${t('optional')}</span>`;
  } else {
    if (coachLabel) coachLabel.textContent = t('sessCoach');
  }
}

// ── Init ──────────────────────────────────────────────────
(async () => {
  const { data: { session } } = await sb.auth.getSession();
  if (!session) { window.location.href = 'TW Login.html?role=gym_owner'; return; }
  currentUser = session.user;

  // populate account email in settings
  const emailEl = document.getElementById('account-email');
  if (emailEl) emailEl.value = currentUser.email || '';

  const { data: profile } = await sb.from('users').select('gym_id, name').eq('id', currentUser.id).single();
  if (profile?.gym_id) {
    currentGymId = profile.gym_id;
    const { data: gym } = await sb.from('gyms').select('name, address, phone, description, subscription_tier').eq('id', currentGymId).single();
    if (gym) {
      document.getElementById('sidebar-gym-name').textContent = gym.name || '—';
      const f = id => document.getElementById(id);
      if (f('gym-name-input'))    f('gym-name-input').value    = gym.name        || '';
      if (f('gym-address-input')) f('gym-address-input').value = gym.address     || '';
      if (f('gym-phone-input'))   f('gym-phone-input').value   = gym.phone       || '';
      if (f('gym-desc-input'))    f('gym-desc-input').value    = gym.description || '';
      // subscription badge
      const tier = (gym.subscription_tier || 'free').toUpperCase();
      const badge = document.getElementById('sub-tier-badge');
      const name  = document.getElementById('sub-tier-name');
      if (badge) { badge.textContent = tier; badge.className = 'sub-tier-badge tier-' + tier.toLowerCase(); }
      if (name)  name.textContent = tier === 'PRO' ? 'Plan Pro' : t('freeTier');
    }
  } else {
    document.getElementById('sidebar-gym-name').textContent = profile?.name || '—';
  }

  // populate session coach dropdown
  await loadGymCoaches();
  updateSessionCategory();

  await loadDashboardStats();
  await loadSchedule();
  await loadCoaches();
  await loadClients();
  await loadAnalytics();
  applyTranslations();

  // animated counters on dashboard
  animateCounters();
})();

// ── Animated counters ─────────────────────────────────────
function animateCounters() {
  document.querySelectorAll('.stat-value').forEach(el => {
    const raw = el.textContent.trim();
    const num = parseInt(raw);
    if (isNaN(num) || num === 0) return;
    let current = 0;
    const step = Math.max(1, Math.floor(num / 20));
    const interval = setInterval(() => {
      current = Math.min(current + step, num);
      el.textContent = current;
      if (current >= num) clearInterval(interval);
    }, 40);
  });
}

// ── Load coaches for session dropdown ────────────────────
async function loadGymCoaches() {
  if (!currentGymId) return;
  const { data } = await sb.from('coach_profiles')
    .select('id, user_id, specialty, hourly_rate, users!inner(name, gym_id)')
    .eq('users.gym_id', currentGymId);
  gymCoaches = data || [];
  const sel = document.getElementById('sess-coach');
  if (!sel) return;
  sel.innerHTML = `<option value="">${t('noCoachOpt')}</option>` +
    gymCoaches.map(c => `<option value="${c.user_id}">${c.users?.name || 'Coach'}</option>`).join('');
}

// ── Dashboard stats ───────────────────────────────────────
async function loadDashboardStats() {
  if (!currentGymId) return;

  const [{ count: coachCount }, { count: clientCount }] = await Promise.all([
    sb.from('users').select('id',{count:'exact',head:true}).eq('role','coach').eq('gym_id',currentGymId),
    sb.from('users').select('id',{count:'exact',head:true}).eq('role','client').eq('gym_id',currentGymId),
  ]);
  document.getElementById('stat-coaches').textContent = coachCount ?? 0;
  document.getElementById('stat-clients').textContent = clientCount ?? 0;
  const anC = document.getElementById('an-coaches');
  const anCl = document.getElementById('an-clients');
  if (anC) anC.textContent = coachCount ?? 0;
  if (anCl) anCl.textContent = clientCount ?? 0;

  const now = new Date();
  const weekStart = new Date(now); weekStart.setDate(now.getDate() - now.getDay());
  const weekEnd   = new Date(weekStart); weekEnd.setDate(weekStart.getDate() + 6);
  const { count: sessCount } = await sb.from('sessions')
    .select('id',{count:'exact',head:true})
    .eq('gym_id', currentGymId)
    .gte('session_date', weekStart.toISOString().split('T')[0])
    .lte('session_date', weekEnd.toISOString().split('T')[0]);
  document.getElementById('stat-sessions').textContent = sessCount ?? 0;
  const anS = document.getElementById('an-sessions');
  if (anS) anS.textContent = sessCount ?? 0;

  // Top coaches
  const { data: coaches } = await sb.from('coach_profiles')
    .select('id, specialty, hourly_rate, rating, total_reviews, users!inner(name, gym_id)')
    .eq('users.gym_id', currentGymId)
    .order('rating', { ascending: false })
    .limit(3);
  const topEl = document.getElementById('top-coaches-list');
  if (!coaches?.length) {
    topEl.innerHTML = `<p class="empty-state">${t('noCoaches')}</p>`;
  } else {
    topEl.innerHTML = coaches.map(c => {
      const name = c.users?.name || 'Coach';
      const ini  = name.split(' ').map(n=>n[0]).join('').slice(0,2).toUpperCase();
      return `<div class="person-card" onclick="openCoachModal('${c.id}')" style="cursor:pointer;margin-bottom:12px;">
        <div class="person-header">
          <div class="person-avatar">${ini}</div>
          <div><div class="person-name">${name}</div><div class="person-role">${c.specialty||'—'}</div></div>
        </div>
        <div class="person-stats">
          <div class="person-stat-item"><div class="person-stat-value">${c.hourly_rate??'—'}<span style="font-size:11px;color:var(--mt)"> DT</span></div><div class="person-stat-label">${t('hourlyRate')}</div></div>
          <div class="person-stat-item"><div class="person-stat-value">★ ${c.rating??'—'}</div><div class="person-stat-label">${t('avgRating')}</div></div>
        </div>
      </div>`;
    }).join('');
  }

  // Recent sessions
  const { data: sessions } = await sb.from('sessions')
    .select('id, session_date, start_time, type, status, users!sessions_coach_id_fkey(name)')
    .eq('gym_id', currentGymId)
    .order('session_date', { ascending: false })
    .limit(4);
  const recentEl = document.getElementById('recent-sessions-list');
  if (!sessions?.length) {
    recentEl.innerHTML = `<p class="empty-state">${t('noSessions')}</p>`;
  } else {
    recentEl.innerHTML = sessions.map(s => {
      const time = s.start_time?.slice(0,5) || '—';
      const date = new Date(s.session_date).toLocaleDateString('fr-FR', {weekday:'short',day:'numeric',month:'short'});
      return `<div class="schedule-item">
        <div class="schedule-time-col"><div class="schedule-time">${time}</div></div>
        <div><div class="schedule-title">${(s.type||'Séance').replace(/_/g,' ')}</div><div class="schedule-meta">${s.users?.name||'—'} · ${date}</div></div>
        <div class="schedule-status status-${s.status||'pending'}">${s.status||'pending'}</div>
      </div>`;
    }).join('');
  }
}

// ── Schedule ──────────────────────────────────────────────
async function loadSchedule() {
  if (!currentGymId) { allSessions = []; renderSchedule(); return; }
  const { data } = await sb.from('sessions')
    .select('id, session_date, start_time, duration_minutes, type, status, coach_id, users!sessions_coach_id_fkey(name)')
    .eq('gym_id', currentGymId)
    .order('session_date', { ascending: false })
    .limit(100);
  allSessions = data || [];
  renderSchedule();
}

function renderSchedule() {
  const q = document.getElementById('schedule-search')?.value.toLowerCase() || '';
  let list = allSessions;
  if (scheduleFilter !== 'all') list = list.filter(s => s.status === scheduleFilter);
  if (q) list = list.filter(s =>
    (s.users?.name||'').toLowerCase().includes(q) || (s.type||'').toLowerCase().includes(q)
  );
  const el = document.getElementById('schedule-list');
  if (!list.length) { el.innerHTML = `<p class="empty-state">${t('noSessions')}</p>`; return; }
  el.innerHTML = list.map(s => {
    const time = s.start_time?.slice(0,5)||'—';
    const date = new Date(s.session_date).toLocaleDateString('fr-FR',{weekday:'short',day:'numeric',month:'short'});
    return `<div class="schedule-item">
      <div class="schedule-time-col"><div class="schedule-time">${time}</div><div class="schedule-dur">${s.duration_minutes??60}min</div></div>
      <div><div class="schedule-title">${(s.type||'Séance').replace(/_/g,' ')}</div><div class="schedule-meta">${s.users?.name||'—'} · ${date}</div></div>
      <div class="schedule-status status-${s.status||'pending'}">${s.status||'pending'}</div>
    </div>`;
  }).join('');
}

// ── Create session ────────────────────────────────────────
async function submitNewSession() {
  const name     = document.getElementById('sess-name').value.trim();
  const type     = document.getElementById('sess-type').value;
  const category = document.getElementById('sess-category').value;
  const date     = document.getElementById('sess-date').value;
  const time     = document.getElementById('sess-time').value;
  const duration = parseInt(document.getElementById('sess-duration').value) || 60;
  const capacity = parseInt(document.getElementById('sess-capacity').value) || 10;
  const coachId  = document.getElementById('sess-coach').value || null;
  const errEl    = document.getElementById('create-session-err');

  errEl.classList.remove('show'); errEl.textContent = '';
  if (!name)  { errEl.textContent = t('sessNameMissing'); errEl.classList.add('show'); return; }
  if (!date)  { errEl.textContent = t('sessDateMissing'); errEl.classList.add('show'); return; }
  if (!time)  { errEl.textContent = t('sessTimeMissing'); errEl.classList.add('show'); return; }

  const btn = document.getElementById('btn-submit-session');
  btn.textContent = '…'; btn.disabled = true;
  try {
    const { error } = await sb.from('sessions').insert({
      gym_id:          currentGymId,
      coach_id:        coachId,
      session_date:    date,
      start_time:      time + ':00',
      duration_minutes: duration,
      type:            category || type,
      status:          'confirmed',
      notes:           name,
    });
    if (error) throw new Error(error.message);
    toast(t('sessionCreated'));
    document.getElementById('create-session-modal').classList.remove('show');
    ['sess-name','sess-date','sess-time'].forEach(id => { document.getElementById(id).value = ''; });
    document.getElementById('sess-duration').value = '60';
    document.getElementById('sess-capacity').value = '10';
    await loadSchedule();
    await loadDashboardStats();
    animateCounters();
  } catch(err) {
    errEl.textContent = err.message; errEl.classList.add('show');
  } finally {
    btn.textContent = t('createSession'); btn.disabled = false;
  }
}

// ── Coaches ───────────────────────────────────────────────
async function loadCoaches() {
  const el = document.getElementById('coaches-grid');
  if (!currentGymId) { el.innerHTML = `<p class="empty-state">${t('noCoaches')}</p>`; return; }
  const { data: coaches } = await sb.from('coach_profiles')
    .select('id, specialty, hourly_rate, rating, total_reviews, users!inner(name, gym_id)')
    .eq('users.gym_id', currentGymId);
  if (!coaches?.length) { el.innerHTML = `<p class="empty-state">${t('noCoaches')}</p>`; return; }
  el.innerHTML = coaches.map(c => {
    const name = c.users?.name || 'Coach';
    const ini  = name.split(' ').map(n=>n[0]).join('').slice(0,2).toUpperCase();
    return `<div class="person-card" onclick="openCoachModal('${c.id}')" style="cursor:pointer;">
      <div class="person-header">
        <div class="person-avatar">${ini}</div>
        <div><div class="person-name">${name}</div><div class="person-role">${c.specialty||'Coach'}</div></div>
      </div>
      <div class="person-stats">
        <div class="person-stat-item"><div class="person-stat-value">${c.hourly_rate??'—'}<span style="font-size:11px;color:var(--mt)"> DT</span></div><div class="person-stat-label">${t('hourlyRate')}</div></div>
        <div class="person-stat-item"><div class="person-stat-value">★ ${c.rating??'—'}</div><div class="person-stat-label">${t('avgRating')}</div></div>
      </div>
    </div>`;
  }).join('');
}

// ── Add coach ─────────────────────────────────────────────
async function submitNewCoach() {
  const name      = document.getElementById('new-coach-name').value.trim();
  const email     = document.getElementById('new-coach-email').value.trim();
  const phone     = document.getElementById('new-coach-phone').value.trim();
  const specialty = document.getElementById('new-coach-specialty').value.trim();
  const rate      = parseFloat(document.getElementById('new-coach-rate').value) || null;
  const errEl     = document.getElementById('add-coach-err');
  errEl.classList.remove('show'); errEl.textContent = '';

  if (!name) { errEl.textContent = t('nameMissing'); errEl.classList.add('show'); return; }
  const emailRe = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
  if (!email || !emailRe.test(email)) { errEl.textContent = t('emailMissing'); errEl.classList.add('show'); return; }

  const btn = document.getElementById('btn-submit-coach');
  btn.textContent = '…'; btn.disabled = true;
  try {
    const { data: { session: ownerSession } } = await sb.auth.getSession();
    const tempPw = 'Trainw!' + Math.random().toString(36).slice(2,10);
    const { data: signUpData, error: signUpErr } = await sb.auth.signUp({
      email, password: tempPw,
      options: { data: { name, role:'coach', phone: phone||null, gym_id: currentGymId||null } }
    });
    if (signUpErr) throw new Error(signUpErr.message);
    const newId = signUpData.user?.id;
    if (!newId) throw new Error('No user ID');
    if (ownerSession) await sb.auth.setSession({ access_token: ownerSession.access_token, refresh_token: ownerSession.refresh_token });
    await new Promise(r => setTimeout(r, 800));
    if (currentGymId) await sb.from('users').update({ gym_id: currentGymId, phone: phone||null }).eq('id', newId);
    if (specialty || rate) await sb.from('coach_profiles').update({ specialty: specialty||null, hourly_rate: rate }).eq('user_id', newId);
    toast(t('coachAdded'));
    document.getElementById('add-coach-modal').classList.remove('show');
    ['new-coach-name','new-coach-email','new-coach-phone','new-coach-specialty','new-coach-rate'].forEach(id => { document.getElementById(id).value = ''; });
    await loadCoaches();
    await loadGymCoaches();
    await loadDashboardStats();
    animateCounters();
  } catch(err) {
    errEl.textContent = err.message; errEl.classList.add('show');
  } finally {
    btn.textContent = t('submitCoach'); btn.disabled = false;
  }
}

// ── Coach modal ───────────────────────────────────────────
async function openCoachModal(coachId) {
  const { data: c } = await sb.from('coach_profiles')
    .select('id, specialty, hourly_rate, bio, rating, total_reviews, created_at, users(name, phone)')
    .eq('id', coachId).single();
  if (!c) return;
  const name = c.users?.name || 'Coach';
  const ini  = name.split(' ').map(n=>n[0]).join('').slice(0,2).toUpperCase();
  const months = Math.floor((Date.now() - new Date(c.created_at)) / (1000*60*60*24*30));
  const employed = months >= 12 ? `${Math.floor(months/12)}a ${months%12}m` : `${months}m`;
  document.getElementById('coach-modal-body').innerHTML = `
    <div class="modal-header">
      <div class="modal-avatar-lg">${ini}</div>
      <div class="modal-info">
        <h2>${name}</h2>
        <div class="modal-meta">${t('employedLbl')}: ${employed} · ${c.users?.phone||'—'}</div>
        <span class="modal-badge">${c.specialty||'—'}</span>
      </div>
    </div>
    <div class="modal-section">
      <div class="modal-section-title">${t('avgRating')}</div>
      <div class="modal-stats-row">
        <div class="modal-stat-box"><div class="modal-stat-value">${c.hourly_rate??'—'} DT</div><div class="modal-stat-label">${t('hourlyRate')}</div></div>
        <div class="modal-stat-box"><div class="modal-stat-value">${c.total_reviews??0}</div><div class="modal-stat-label">${t('totalReviews')}</div></div>
        <div class="modal-stat-box"><div class="modal-stat-value">${c.rating??'—'}</div><div class="modal-stat-label">${t('avgRating')}</div></div>
      </div>
      ${c.bio ? `<div style="background:var(--s2);border:1px solid var(--bd);border-radius:7px;padding:16px;margin-top:14px;font-size:14px;color:var(--mt);line-height:1.7;">${c.bio}</div>` : ''}
    </div>`;
  document.getElementById('coach-modal').classList.add('show');
}

// ── Clients ───────────────────────────────────────────────
async function loadClients() {
  const el = document.getElementById('clients-grid');
  if (!currentGymId) { el.innerHTML = `<p class="empty-state">${t('noClients')}</p>`; return; }
  const { data: clients } = await sb.from('users')
    .select('id, name, created_at, phone')
    .eq('role','client')
    .eq('gym_id', currentGymId);
  // also try to get client_profiles data
  let profileMap = {};
  if (clients?.length) {
    const ids = clients.map(c=>c.id);
    const { data: profiles } = await sb.from('client_profiles')
      .select('user_id, membership_tier, fitness_goal')
      .in('user_id', ids);
    (profiles||[]).forEach(p => { profileMap[p.user_id] = p; });
  }
  allClients = (clients||[]).map(c => ({ ...c, profile: profileMap[c.id]||{} }));
  renderClients();
}

function renderClients() {
  const el = document.getElementById('clients-grid');
  const q  = document.getElementById('clients-search')?.value.toLowerCase() || '';
  let list = allClients;
  if (clientFilter !== 'all') {
    // filter by payment status stored locally (no payment column in users table yet)
    list = list.filter(c => (c.payment_status||'paid') === clientFilter);
  }
  if (q) list = list.filter(c => (c.name||'').toLowerCase().includes(q) || (c.phone||'').includes(q));
  if (!list.length) { el.innerHTML = `<p class="empty-state">${t('noClients')}</p>`; return; }
  el.innerHTML = list.map(c => {
    const ini   = (c.name||'C').split(' ').map(n=>n[0]).join('').slice(0,2).toUpperCase();
    const since = new Date(c.created_at).toLocaleDateString('fr-FR',{month:'short',year:'numeric'});
    const tier  = c.profile?.membership_tier || 'basic';
    const goal  = c.profile?.fitness_goal || '—';
    return `<div class="person-card client-card">
      <div class="person-header">
        <div class="person-avatar">${ini}</div>
        <div>
          <div class="person-name">${c.name||'Client'}</div>
          <div class="person-role">${c.phone||'—'}</div>
        </div>
        <div style="margin-left:auto;display:flex;gap:8px;">
          <button class="icon-btn btn-del" onclick="deleteClient('${c.id}')" title="${t('deleteClient')}">✕</button>
        </div>
      </div>
      <div class="person-stats">
        <div class="person-stat-item"><div class="person-stat-value" style="font-size:13px;padding-top:2px;">${tier.toUpperCase()}</div><div class="person-stat-label">${t('membership')}</div></div>
        <div class="person-stat-item"><div class="person-stat-value" style="font-size:13px;padding-top:2px;">${since}</div><div class="person-stat-label">${t('memberSince')}</div></div>
      </div>
    </div>`;
  }).join('');
}

// ── Add client ────────────────────────────────────────────
async function submitNewClient() {
  const name       = document.getElementById('new-client-name').value.trim();
  const phone      = document.getElementById('new-client-phone').value.trim();
  const membership = document.getElementById('new-client-membership').value;
  const training   = document.getElementById('new-client-training').value;
  const errEl      = document.getElementById('add-client-err');
  errEl.classList.remove('show'); errEl.textContent = '';

  if (!name) { errEl.textContent = t('nameMissing'); errEl.classList.add('show'); return; }

  const btn = document.getElementById('btn-submit-client');
  btn.textContent = '…'; btn.disabled = true;
  try {
    const { data: { session: ownerSession } } = await sb.auth.getSession();
    const fakeEmail = name.toLowerCase().replace(/\s+/g,'.') + '.' + Date.now() + '@trainw.client';
    const tempPw = 'Trainw!' + Math.random().toString(36).slice(2,10);
    const { data: signUpData, error: signUpErr } = await sb.auth.signUp({
      email: fakeEmail, password: tempPw,
      options: { data: { name, role:'client', phone: phone||null, gym_id: currentGymId||null } }
    });
    if (signUpErr) throw new Error(signUpErr.message);
    const newId = signUpData.user?.id;
    if (!newId) throw new Error('No user ID');
    if (ownerSession) await sb.auth.setSession({ access_token: ownerSession.access_token, refresh_token: ownerSession.refresh_token });
    await new Promise(r => setTimeout(r, 800));
    if (currentGymId) await sb.from('users').update({ gym_id: currentGymId, phone: phone||null }).eq('id', newId);
    await sb.from('client_profiles').update({ membership_tier: membership, fitness_goal: training }).eq('user_id', newId);
    toast(t('clientAdded'));
    document.getElementById('add-client-modal').classList.remove('show');
    ['new-client-name','new-client-age','new-client-phone'].forEach(id => { document.getElementById(id).value = ''; });
    await loadClients();
    await loadDashboardStats();
    animateCounters();
  } catch(err) {
    errEl.textContent = err.message; errEl.classList.add('show');
  } finally {
    btn.textContent = t('submitClient'); btn.disabled = false;
  }
}

// ── Delete client ─────────────────────────────────────────
async function deleteClient(userId) {
  if (!confirm('Supprimer ce client ?')) return;
  try {
    await sb.from('users').delete().eq('id', userId);
    allClients = allClients.filter(c => c.id !== userId);
    renderClients();
    await loadDashboardStats();
    animateCounters();
    toast('Client supprimé');
  } catch(e) {
    toast(t('errorMsg'));
  }
}

// ── Analytics ─────────────────────────────────────────────
async function loadAnalytics() {
  if (!currentGymId) return;

  // Popular session types
  const { data: sessions } = await sb.from('sessions')
    .select('type').eq('gym_id', currentGymId);
  const typeCount = {};
  (sessions||[]).forEach(s => { const k = s.type||'unknown'; typeCount[k] = (typeCount[k]||0)+1; });
  const sorted = Object.entries(typeCount).sort((a,b)=>b[1]-a[1]).slice(0,5);
  const classEl = document.getElementById('popular-classes-list');
  if (classEl) {
    classEl.innerHTML = sorted.length
      ? sorted.map(([type, count]) => `
          <div class="analytics-row">
            <div class="analytics-row-label">${type.replace(/_/g,' ')}</div>
            <div class="analytics-row-bar"><div class="analytics-bar-fill" style="width:${Math.round((count/Math.max(...Object.values(typeCount)))*100)}%"></div></div>
            <div class="analytics-row-val">${count}</div>
          </div>`).join('')
      : `<p class="empty-state">${t('noSessions')}</p>`;
  }

  // Coach utilization
  const { data: coachSessions } = await sb.from('sessions')
    .select('coach_id, users!sessions_coach_id_fkey(name)').eq('gym_id', currentGymId);
  const coachCount = {};
  const coachNames = {};
  (coachSessions||[]).forEach(s => {
    if (!s.coach_id) return;
    coachCount[s.coach_id] = (coachCount[s.coach_id]||0)+1;
    coachNames[s.coach_id] = s.users?.name || 'Coach';
  });
  const coachSorted = Object.entries(coachCount).sort((a,b)=>b[1]-a[1]).slice(0,5);
  const utilEl = document.getElementById('coach-util-list');
  if (utilEl) {
    utilEl.innerHTML = coachSorted.length
      ? coachSorted.map(([id, count]) => `
          <div class="analytics-row">
            <div class="analytics-row-label">${coachNames[id]}</div>
            <div class="analytics-row-bar"><div class="analytics-bar-fill" style="width:${Math.round((count/Math.max(...Object.values(coachCount)))*100)}%"></div></div>
            <div class="analytics-row-val">${count} séances</div>
          </div>`).join('')
      : `<p class="empty-state">${t('noCoaches')}</p>`;
  }
}

// ── Save settings ─────────────────────────────────────────
async function saveSettings() {
  if (!currentGymId) { toast(t('errorMsg')); return; }
  const name = document.getElementById('gym-name-input').value.trim();
  if (!name) { toast('Le nom de la salle est obligatoire'); return; }
  const btn = document.getElementById('btn-save-settings');
  btn.textContent = '…'; btn.disabled = true;
  try {
    const { error } = await sb.from('gyms').update({
      name,
      address:     document.getElementById('gym-address-input').value.trim()||null,
      phone:       document.getElementById('gym-phone-input').value.trim()||null,
      description: document.getElementById('gym-desc-input').value.trim()||null,
    }).eq('id', currentGymId);
    if (error) throw new Error(error.message);
    document.getElementById('sidebar-gym-name').textContent = name;
    const ss = document.getElementById('save-status');
    if (ss) { ss.textContent = t('savedOk'); ss.style.color='var(--ac)'; setTimeout(()=>ss.textContent='',3000); }
    toast(t('savedOk'));
  } catch(err) {
    toast(t('errorMsg') + ' ' + err.message);
  } finally {
    btn.textContent = t('saveChanges'); btn.disabled = false;
  }
}

// ── Change password ───────────────────────────────────────
async function changePassword() {
  const email = currentUser?.email;
  if (!email) return;
  const btn = document.getElementById('btn-change-password');
  btn.textContent = '…'; btn.disabled = true;
  try {
    await sb.auth.resetPasswordForEmail(email);
    const ss = document.getElementById('pw-status');
    if (ss) { ss.textContent = t('pwReset'); ss.style.color='var(--ac)'; setTimeout(()=>ss.textContent='',4000); }
    toast(t('pwReset'));
  } catch(e) {
    toast(t('errorMsg'));
  } finally {
    btn.textContent = t('changePassword'); btn.disabled = false;
  }
}

// ── Sign out ──────────────────────────────────────────────
document.getElementById('btn-logout').addEventListener('click', async () => {
  await sb.auth.signOut();
  window.location.href = 'TW Login.html';
});

// ── Page nav ──────────────────────────────────────────────
document.querySelectorAll('.nav-item').forEach(item => {
  item.addEventListener('click', () => {
    const page = item.dataset.page;
    document.querySelectorAll('.page').forEach(p => p.classList.add('hidden'));
    document.getElementById(page + '-page').classList.remove('hidden');
    document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
    item.classList.add('active');
    if (page === 'analytics') loadAnalytics();
  });
});

// ── Lang toggle ───────────────────────────────────────────
function setLang(lang) {
  currentLang = lang;
  localStorage.setItem('trainw_lang', lang);
  applyTranslations();
  renderSchedule();
  renderClients();
}
document.querySelectorAll('.lang-btn').forEach(btn => {
  btn.addEventListener('click', () => setLang(btn.dataset.lang));
});
document.querySelectorAll('.lang-option-btn').forEach(btn => {
  btn.addEventListener('click', () => setLang(btn.dataset.lang));
});

// ── Filters ───────────────────────────────────────────────
document.querySelectorAll('.filter-btn[data-filter]').forEach(btn => {
  btn.addEventListener('click', () => {
    scheduleFilter = btn.dataset.filter;
    btn.closest('.filter-row').querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    renderSchedule();
  });
});
document.querySelectorAll('.filter-btn[data-cfilter]').forEach(btn => {
  btn.addEventListener('click', () => {
    clientFilter = btn.dataset.cfilter;
    btn.closest('.filter-row').querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    renderClients();
  });
});

document.getElementById('schedule-search')?.addEventListener('input', renderSchedule);
document.getElementById('coaches-search')?.addEventListener('input', function() {
  const q = this.value.toLowerCase();
  document.querySelectorAll('#coaches-grid .person-card').forEach(card => {
    card.style.display = card.textContent.toLowerCase().includes(q) ? '' : 'none';
  });
});
document.getElementById('clients-search')?.addEventListener('input', renderClients);

// ── Modals ────────────────────────────────────────────────
document.getElementById('btn-add-coach')?.addEventListener('click', () => document.getElementById('add-coach-modal').classList.add('show'));
document.getElementById('btn-add-client')?.addEventListener('click', () => document.getElementById('add-client-modal').classList.add('show'));
document.getElementById('btn-create-session')?.addEventListener('click', () => document.getElementById('create-session-modal').classList.add('show'));
document.getElementById('close-coach-modal').addEventListener('click', () => document.getElementById('coach-modal').classList.remove('show'));
document.getElementById('close-add-coach-modal').addEventListener('click', () => document.getElementById('add-coach-modal').classList.remove('show'));
document.getElementById('close-add-client-modal').addEventListener('click', () => document.getElementById('add-client-modal').classList.remove('show'));
document.getElementById('close-session-modal').addEventListener('click', () => document.getElementById('create-session-modal').classList.remove('show'));
document.getElementById('close-client-modal').addEventListener('click', () => document.getElementById('client-modal').classList.remove('show'));
['coach-modal','add-coach-modal','add-client-modal','create-session-modal','client-modal'].forEach(id => {
  document.getElementById(id)?.addEventListener('click', e => { if (e.target.id === id) e.target.classList.remove('show'); });
});

// ── Button wiring ─────────────────────────────────────────
document.getElementById('btn-submit-coach').addEventListener('click', submitNewCoach);
document.getElementById('btn-submit-client').addEventListener('click', submitNewClient);
document.getElementById('btn-submit-session').addEventListener('click', submitNewSession);
document.getElementById('btn-save-settings').addEventListener('click', saveSettings);
document.getElementById('btn-change-password')?.addEventListener('click', changePassword);

// ── Toast ─────────────────────────────────────────────────
function toast(msg, type='ok') {
  const el = document.getElementById('toast');
  document.getElementById('toast-msg').textContent = msg;
  el.classList.remove('show','toast-err');
  if (type==='err') el.classList.add('toast-err');
  el.classList.add('show');
  setTimeout(() => el.classList.remove('show'), 3500);
}

applyTranslations();
