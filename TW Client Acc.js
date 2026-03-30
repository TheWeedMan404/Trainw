// ── Supabase ──────────────────────────────────────────────
const Trainw = window.TrainwCore;
const sb = Trainw.createClient();
Trainw.installGlobalErrorHandlers();

let currentUserId      = null;
let currentClientProfileId = null;
let currentCoachUserId = null;
let currentGymId       = null;
let selectedSlot       = null;
let userInitials       = 'ME';
let currentLang        = localStorage.getItem('trainw_lang') || 'fr';
let sessionsCache      = [];
let coachState         = null;
let messagesCache      = [];
let uiBound            = false;

// ── i18n ──────────────────────────────────────────────────
const T = {
  en: {
    roleLabel:'Client', signOut:'Sign Out',
    navDash:'Dashboard', navProgress:'Progress', navNutrition:'Nutrition',
    navCoach:'My Coach', navBookings:'Bookings', navSettings:'Settings',
    dashSub:'Your fitness journey',
    statSessions:'Sessions This Month', statMembership:'Membership',
    statGoal:'Goal', statSince:'Member Since',
    thisMonth:'this month', plan:'plan', currentGoal:'current goal', joined:'joined',
    bookSession:'Book Next Session', scheduleCoach:'Schedule with your coach',
    msgCoach:'Message Coach', msgCoachDesc:'Ask questions or update progress',
    recentSessions:'Recent Sessions', loading:'Loading…',
    progressSub:'Track your transformation',
    sessionHistory:'Session History', bodyMeasurements:'Body Measurements',
    edit:'Edit', height:'Height (cm)', weight:'Weight (kg)',
    bodyFat:'Body Fat (%)', goalWeight:'Goal Weight (kg)',
    saveMeasurements:'Save Measurements',
    nutritionSub:'Personalized meal planning',
    aiDietTitle:'Guide Nutrition Personnalisé', aiDietSub:'Plan alimentaire adapté à vos objectifs et aux préférences tunisiennes',
    yourGoal:'Your Goal', bodyType:'Body Type', activityLevel:'Activity Level', workoutType:'Workout Type',
    generateDiet:'Generate My Diet',
    coachSub:'Stay connected with your trainer', loadingCoach:'Loading coach…',
    messages:'Messages', chatPlaceholder:'Chat coming soon. Book a session to connect.',
    typeMessage:'Type a message…', send:'Send',
    availableSlots:'Available Time Slots', confirmBooking:'Confirm Booking',
    upcomingSessions:'Upcoming Sessions',
    bookingsSub:'Schedule your next training',
    settingsSub:'Manage your account', personalInfo:'Personal Information',
    lName:'Name', lPhone:'Phone', lGoal:'Goal', saveChanges:'Save Changes',
    noSessions:'No sessions yet.',
    noCoach:'No coach assigned yet. Contact your gym.',
    savedOk:'Saved!', errorMsg:'Something went wrong.',
    bookingOk:'Session booked!', selectSlot:'Please select a time slot.',
  },
  fr: {
    roleLabel:'Client', signOut:'Se Déconnecter',
    navDash:'Tableau de Bord', navProgress:'Progrès', navNutrition:'Nutrition',
    navCoach:'Mon Coach', navBookings:'Réservations', navSettings:'Paramètres',
    dashSub:'Votre parcours fitness',
    statSessions:'Séances Ce Mois', statMembership:'Abonnement',
    statGoal:'Objectif', statSince:'Membre Depuis',
    thisMonth:'ce mois', plan:'plan', currentGoal:'objectif actuel', joined:'inscrit',
    bookSession:'Prochaine Séance', scheduleCoach:'Planifier avec votre coach',
    msgCoach:'Message Coach', msgCoachDesc:'Questions ou mise à jour de progression',
    recentSessions:'Séances Récentes', loading:'Chargement…',
    progressSub:'Suivez votre transformation',
    sessionHistory:'Historique des Séances', bodyMeasurements:'Mensurations',
    edit:'Modifier', height:'Taille (cm)', weight:'Poids (kg)',
    bodyFat:'Masse Grasse (%)', goalWeight:'Poids Cible (kg)',
    saveMeasurements:'Enregistrer Mensurations',
    nutritionSub:'Plan alimentaire personnalisé',
    aiDietTitle:'Générateur de Régime IA', aiDietSub:'Plan alimentaire selon vos objectifs et préférences tunisiennes',
    yourGoal:'Votre Objectif', bodyType:'Type de Corps', activityLevel:'Niveau d\'Activité', workoutType:'Type d\'Entraînement',
    generateDiet:'Générer Mon Régime',
    coachSub:'Restez connecté avec votre coach', loadingCoach:'Chargement du coach…',
    messages:'Messages', chatPlaceholder:'Chat bientôt disponible. Réservez une séance pour vous connecter.',
    typeMessage:'Écrire un message…', send:'Envoyer',
    availableSlots:'Créneaux Disponibles', confirmBooking:'Confirmer la Réservation',
    upcomingSessions:'Prochaines Séances',
    bookingsSub:'Planifiez votre prochain entraînement',
    settingsSub:'Gérez votre compte', personalInfo:'Informations Personnelles',
    lName:'Nom', lPhone:'Téléphone', lGoal:'Objectif', saveChanges:'Enregistrer',
    noSessions:'Aucune séance pour l\'instant.',
    noCoach:'Aucun coach assigné. Contactez votre salle.',
    savedOk:'Enregistré !', errorMsg:'Une erreur s\'est produite.',
    bookingOk:'Séance réservée !', selectSlot:'Veuillez sélectionner un créneau.',
  },
  ar: {
    roleLabel:'عميل', signOut:'تسجيل الخروج',
    navDash:'لوحة التحكم', navProgress:'التقدم', navNutrition:'التغذية',
    navCoach:'مدربي', navBookings:'الحجوزات', navSettings:'الإعدادات',
    dashSub:'رحلتك الرياضية',
    statSessions:'جلسات هذا الشهر', statMembership:'الاشتراك',
    statGoal:'الهدف', statSince:'عضو منذ',
    thisMonth:'هذا الشهر', plan:'خطة', currentGoal:'الهدف الحالي', joined:'انضم',
    bookSession:'احجز الجلسة القادمة', scheduleCoach:'حدد موعداً مع مدربك',
    msgCoach:'مراسلة المدرب', msgCoachDesc:'أسئلة أو تحديث التقدم',
    recentSessions:'الجلسات الأخيرة', loading:'جار التحميل…',
    progressSub:'تابع تحولك',
    sessionHistory:'سجل الجلسات', bodyMeasurements:'القياسات الجسمية',
    edit:'تعديل', height:'الطول (سم)', weight:'الوزن (كغ)',
    bodyFat:'نسبة الدهون (%)', goalWeight:'الوزن المستهدف (كغ)',
    saveMeasurements:'حفظ القياسات',
    nutritionSub:'خطة غذائية شخصية',
    aiDietTitle:'دليل التغذية الشخصي', aiDietSub:'خطة غذائية مناسبة لأهدافك والتفضيلات التونسية',
    yourGoal:'هدفك', bodyType:'نوع الجسم', activityLevel:'مستوى النشاط', workoutType:'نوع التمرين',
    generateDiet:'إنشاء خطتي الغذائية',
    coachSub:'ابق على تواصل مع مدربك', loadingCoach:'جار تحميل المدرب…',
    messages:'الرسائل', chatPlaceholder:'الدردشة قريباً. احجز جلسة للتواصل.',
    typeMessage:'اكتب رسالة…', send:'إرسال',
    availableSlots:'المواعيد المتاحة', confirmBooking:'تأكيد الحجز',
    upcomingSessions:'الجلسات القادمة',
    bookingsSub:'جدوِل تدريبك القادم',
    settingsSub:'إدارة حسابك', personalInfo:'المعلومات الشخصية',
    lName:'الاسم', lPhone:'الهاتف', lGoal:'الهدف', saveChanges:'حفظ التغييرات',
    noSessions:'لا توجد جلسات بعد.',
    noCoach:'لا يوجد مدرب معيّن بعد. تواصل مع صالتك.',
    savedOk:'تم الحفظ!', errorMsg:'حدث خطأ ما.',
    bookingOk:'تم الحجز!', selectSlot:'الرجاء اختيار موعد.',
  }
};
const t = k => T[currentLang]?.[k] || T.en[k] || k;

function applyTranslations() {
  document.querySelectorAll('[data-i18n]').forEach(el => {
    const k = el.getAttribute('data-i18n');
    if (T[currentLang]?.[k]) el.textContent = T[currentLang][k];
  });
  document.querySelectorAll('[data-i18n-ph]').forEach(el => {
    const k = el.getAttribute('data-i18n-ph');
    if (T[currentLang]?.[k]) el.placeholder = T[currentLang][k];
  });
  document.documentElement.setAttribute('dir', currentLang === 'ar' ? 'rtl' : 'ltr');
  document.querySelectorAll('.lang-btn').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.lang === currentLang);
  });
}

function locale() {
  return Trainw.localeForLang(currentLang);
}

function showPage(page) {
  document.querySelectorAll('.page').forEach(node => node.classList.add('hidden'));
  document.getElementById(page + '-page')?.classList.remove('hidden');
  document.querySelectorAll('.nav-item').forEach(node => {
    node.classList.toggle('active', node.dataset.page === page);
  });
}

function renderSessions() {
  const emptyState = `<p class="empty-state">${t('noSessions')}</p>`;
  if (!sessionsCache.length) {
    Trainw.ui.setText('stat-sessions', '0');
    Trainw.ui.setHtml('recent-sessions', emptyState);
    Trainw.ui.setHtml('all-sessions', emptyState);
    Trainw.ui.setHtml('upcoming-sessions', emptyState);
    return;
  }

  const now = new Date();
  const monthCount = sessionsCache.filter(session => {
    const date = new Date(session.session_date);
    return date.getMonth() === now.getMonth() && date.getFullYear() === now.getFullYear();
  }).length;
  Trainw.ui.setText('stat-sessions', String(monthCount));

  const renderItem = session => {
    const date = new Date(session.session_date);
    const dateLabel = Number.isNaN(date.getTime())
      ? Trainw.escapeHtml(session.session_date || '')
      : date.toLocaleDateString(locale(), { weekday: 'short', day: 'numeric', month: 'short' });
    const title = Trainw.escapeHtml((session.session_name || session.type || 'Session').replace(/_/g, ' '));
    const coachName = Trainw.escapeHtml(session.users?.name || 'Coach');
    const time = Trainw.escapeHtml((session.start_time || '').slice(0, 5));
    const status = Trainw.escapeHtml(session.status || 'confirmed');

    return `<div class="activity-item">
      <div class="activity-title">${title} - ${coachName}</div>
      <div class="activity-meta">${dateLabel} • ${time} • ${session.duration_minutes ?? 60}min • ${status}</div>
    </div>`;
  };

  const upcoming = sessionsCache.filter(session => {
    if (session.status === 'cancelled') return false;
    const date = new Date(session.session_date + 'T' + (session.start_time || '00:00:00'));
    return !Number.isNaN(date.getTime()) && date >= now;
  });

  Trainw.ui.setHtml('recent-sessions', sessionsCache.slice(0, 5).map(renderItem).join(''));
  Trainw.ui.setHtml('all-sessions', sessionsCache.map(renderItem).join(''));
  Trainw.ui.setHtml('upcoming-sessions', upcoming.length ? upcoming.map(renderItem).join('') : emptyState);
}

function renderCoachState() {
  if (!coachState) {
    Trainw.ui.setText('coach-avatar', '?');
    Trainw.ui.setText('coach-name', t('noCoach'));
    Trainw.ui.setText('coach-specialty', '');
    Trainw.ui.setText('coach-rating', '');
    Trainw.ui.setText('quick-book-desc', t('scheduleCoach'));
    Trainw.ui.setHtml('slots-grid', `<p class="empty-state">${t('noCoach')}</p>`);
    return;
  }

  const initials = coachState.name.split(' ').map(part => part[0] || '').join('').slice(0, 2).toUpperCase();
  Trainw.ui.setText('coach-avatar', initials || '?');
  Trainw.ui.setText('coach-name', coachState.name);
  Trainw.ui.setText('coach-specialty', coachState.specialty || '');
  Trainw.ui.setText('coach-rating', coachState.rating ? '★ ' + coachState.rating : '');
  Trainw.ui.setText('quick-book-desc', t('scheduleCoach'));

  const slots = ['08:00', '10:00', '14:00', '17:00', '18:00', '19:00'];
  Trainw.ui.setHtml(
    'slots-grid',
    slots.map(slot => {
      const selectedClass = selectedSlot === slot ? ' selected' : '';
      return `<div class="slot${selectedClass}" data-time="${slot}">
        <div class="slot-time">${slot}</div>
        <div class="slot-status">Available</div>
      </div>`;
    }).join('')
  );

  document.querySelectorAll('.slot').forEach(slotElement => {
    slotElement.addEventListener('click', () => {
      selectedSlot = slotElement.dataset.time;
      renderCoachState();
    });
  });
}

function renderMessages() {
  const container = document.getElementById('chat-messages');
  if (!container) return;

  if (!messagesCache.length) {
    container.innerHTML = `<p class="empty-state" style="padding:20px;">${t('chatPlaceholder')}</p>`;
    return;
  }

  container.innerHTML = messagesCache.map(message => {
    const isMine = message.sender_id === currentUserId;
    const time = new Date(message.created_at).toLocaleTimeString(locale(), {
      hour: '2-digit',
      minute: '2-digit',
    });
    return `<div class="message ${isMine ? 'sent' : 'received'}">
      <div class="msg-avatar">${isMine ? Trainw.escapeHtml(userInitials) : 'ðŸ‹ï¸'}</div>
      <div class="msg-inner">
        <div class="msg-text">${Trainw.escapeHtml(message.content || '')}</div>
        <div class="msg-time">${Trainw.escapeHtml(time)}</div>
      </div>
    </div>`;
  }).join('');

  container.scrollTop = container.scrollHeight;
}

function toggleMeasurementsEditor(forceEditing) {
  const view = document.getElementById('measurements-view');
  const edit = document.getElementById('measurements-edit');
  const button = document.getElementById('btn-toggle-measurements');
  if (!view || !edit || !button) return;

  const editing = typeof forceEditing === 'boolean' ? forceEditing : edit.classList.contains('hidden');
  view.classList.toggle('hidden', editing);
  edit.classList.toggle('hidden', !editing);
  button.textContent = editing
    ? (currentLang === 'ar' ? 'إلغاء' : currentLang === 'en' ? 'Cancel' : 'Annuler')
    : t('edit');
}

// ── Init ──────────────────────────────────────────────────
async function legacyInitDisabled() {
  try {
    const { data: { session } } = await sb.auth.getSession();
    if (!session) { window.location.href = 'login.html?role=client'; return; }
    currentUserId = session.user.id;

    const { data: user } = await sb.from('users').select('name, phone, gym_id').eq('id', currentUserId).single();
    if (user) {
      if(user.name) {
        const sn = document.getElementById('sidebar-client-name'); if(sn) sn.textContent = user.name;
        userInitials = user.name.split(' ').map(n => n[0]).join('').slice(0,2).toUpperCase();
        const nm = document.getElementById('settings-name');  if(nm) nm.value = user.name  || '';
        const ph = document.getElementById('settings-phone'); if(ph) ph.value = user.phone || '';
      }
      if(user.gym_id) currentGymId = user.gym_id;
    }

    const { data: client } = await sb.from('client_profiles')
      .select('id, membership_tier, fitness_goal, created_at, height_cm, weight_kg, body_fat_pct, goal_weight_kg')
      .eq('user_id', currentUserId).single();

    if (client) {
      currentClientProfileId = client.id;
      const set = (id, v) => { const el = document.getElementById(id); if(el) el.textContent = v ?? '—'; };
      set('stat-tier', (client.membership_tier || 'basic').toUpperCase());
      set('stat-goal', client.fitness_goal || '—');
      const sg = document.getElementById('settings-goal'); if(sg) sg.value = client.fitness_goal || '';
      if (client.created_at) {
        set('stat-since', new Date(client.created_at).toLocaleDateString('fr-FR', { month:'short', year:'numeric' }));
      }
      set('m-height',    client.height_cm     || '—');
      set('m-weight',    client.weight_kg     || '—');
      set('m-bodyfat',   client.body_fat_pct  || '—');
      set('m-goalweight', client.goal_weight_kg || '—');
      const vals = [['inp-height', client.height_cm],['inp-weight', client.weight_kg],['inp-bodyfat', client.body_fat_pct],['inp-goalweight', client.goal_weight_kg]];
      vals.forEach(([id, v]) => { const el = document.getElementById(id); if(el) el.value = v || ''; });
    }

    await loadSessions();
    await loadCoach();
    applyTranslations();
  } catch(err) {
    console.error('Client init error:', err);
    const te = document.getElementById('toast'); const tm = document.getElementById('toast-msg');
    if(te && tm) { tm.textContent = 'Erreur de chargement — rechargez la page'; te.classList.add('show','toast-err'); }
  }
}

// ── Sessions ──────────────────────────────────────────────
async function loadSessions() {
  const result = await Trainw.api.run(
    sb
      .from('sessions')
      .select('id, gym_id, session_date, start_time, duration_minutes, type, status, coach_id, session_name, users!sessions_coach_id_fkey(name)')
      .eq('client_id', currentUserId)
      .order('session_date', { ascending: false }),
    {
      context: 'load client sessions',
      fallback: [],
    }
  );

  sessionsCache = Array.isArray(result.data) ? result.data : [];
  if (!currentGymId) {
    currentGymId = sessionsCache.find(session => Boolean(session.gym_id))?.gym_id || currentGymId;
  }
  renderSessions();
}

async function loadCoach() {
  let coachUserId = null;
  let coachName = '';
  let specialty = '';
  let rating = null;

  const latestSession = await Trainw.api.run(
    sb
      .from('sessions')
      .select('coach_id, gym_id, users!sessions_coach_id_fkey(name)')
      .eq('client_id', currentUserId)
      .not('coach_id', 'is', null)
      .order('session_date', { ascending: false })
      .limit(1)
      .maybeSingle(),
    {
      context: 'load latest coach session',
      allowMissing: true,
      fallback: null,
    }
  );

  if (latestSession.data?.coach_id) {
    coachUserId = latestSession.data.coach_id;
    coachName = latestSession.data.users?.name || '';
    if (!currentGymId && latestSession.data.gym_id) {
      currentGymId = latestSession.data.gym_id;
    }
  }

  if (!coachUserId && currentGymId) {
    const fallbackCoach = await Trainw.api.run(
      sb
        .from('coach_profiles')
        .select('user_id, specialty, rating, users!inner(name, gym_id)')
        .eq('users.gym_id', currentGymId)
        .order('rating', { ascending: false })
        .limit(1)
        .maybeSingle(),
      {
        context: 'load fallback coach',
        allowMissing: true,
        fallback: null,
      }
    );

    if (fallbackCoach.data?.user_id) {
      coachUserId = fallbackCoach.data.user_id;
      coachName = fallbackCoach.data.users?.name || '';
      specialty = fallbackCoach.data.specialty || '';
      rating = fallbackCoach.data.rating ?? null;
    }
  }

  if (coachUserId && (!specialty || rating == null)) {
    const coachProfile = await Trainw.api.run(
      sb
        .from('coach_profiles')
        .select('specialty, rating')
        .eq('user_id', coachUserId)
        .maybeSingle(),
      {
        context: 'load coach profile',
        allowMissing: true,
        fallback: null,
      }
    );

    specialty = specialty || coachProfile.data?.specialty || '';
    rating = rating ?? coachProfile.data?.rating ?? null;
  }

  currentCoachUserId = coachUserId;
  coachState = coachUserId
    ? { userId: coachUserId, name: coachName || 'Coach', specialty, rating }
    : null;

  renderCoachState();
  await loadMessageHistory();
}

async function loadMessageHistory() {
  if (!currentCoachUserId || !currentGymId) {
    messagesCache = [];
    renderMessages();
    return;
  }

  const result = await Trainw.api.run(
    sb
      .from('messages')
      .select('id, content, sender_id, created_at')
      .eq('gym_id', currentGymId)
      .or(`and(sender_id.eq.${currentUserId},receiver_id.eq.${currentCoachUserId}),and(sender_id.eq.${currentCoachUserId},receiver_id.eq.${currentUserId})`)
      .order('created_at', { ascending: true }),
    {
      context: 'load client messages',
      fallback: [],
    }
  );

  messagesCache = Array.isArray(result.data) ? result.data : [];
  renderMessages();

  await Trainw.api.run(
    sb
      .from('messages')
      .update({ is_read: true })
      .eq('gym_id', currentGymId)
      .eq('receiver_id', currentUserId)
      .eq('sender_id', currentCoachUserId),
    {
      context: 'mark client messages as read',
      fallback: null,
      silent: true,
    }
  );
}

async function confirmBooking() {
  if (!selectedSlot) { toast(t('selectSlot'), 'err'); return; }
  if (!currentCoachUserId) { toast(t('noCoach'), 'err'); return; }

  if (!currentGymId) {
    const coachUser = await Trainw.api.run(
      sb.from('users').select('gym_id').eq('id', currentCoachUserId).maybeSingle(),
      {
        context: 'load coach gym before booking',
        allowMissing: true,
        fallback: null,
      }
    );
    currentGymId = coachUser.data?.gym_id || currentGymId;
  }

  if (!currentGymId) { toast(t('errorMsg'), 'err'); return; }

  const btn = document.getElementById('btn-confirm-booking');
  const originalLabel = btn.textContent;
  btn.textContent = '...';
  Trainw.ui.setBusy(btn, true);

  try {
    const sessionDate = Trainw.dateOnly(Trainw.addDays(new Date(), 1));
    const mutation = await Trainw.api.run(
      sb.from('sessions').insert({
        gym_id: currentGymId,
        coach_id: currentCoachUserId,
        client_id: currentUserId,
        session_date: sessionDate,
        start_time: selectedSlot + ':00',
        duration_minutes: 60,
        type: 'personal_training',
        status: 'pending',
      }),
      {
        context: 'create booking',
        fallback: null,
      }
    );

    if (mutation.error) throw mutation.error;
    selectedSlot = null;
    toast(t('bookingOk'));
    await loadSessions();
    renderCoachState();
    showPage('bookings');
  } catch (err) {
    console.error('Booking error:', err);
    toast(err.message || t('errorMsg'), 'err');
  } finally {
    btn.textContent = originalLabel;
    Trainw.ui.setBusy(btn, false);
  }
}
async function saveMeasurements() {
  if (!currentClientProfileId) { toast(t('errorMsg'), 'err'); return; }

  const readNumber = (id, min, max) => {
    const raw = document.getElementById(id)?.value?.trim();
    if (!raw) return null;
    const parsed = Number(raw);
    if (!Number.isFinite(parsed) || parsed < min || parsed > max) {
      throw new Error(t('errorMsg'));
    }
    return parsed;
  };

  const btn = document.getElementById('btn-save-measurements');
  const originalLabel = btn.textContent;
  btn.textContent = '...';
  Trainw.ui.setBusy(btn, true);

  try {
    const payload = {
      height_cm: readNumber('inp-height', 50, 280),
      weight_kg: readNumber('inp-weight', 20, 400),
      body_fat_pct: readNumber('inp-bodyfat', 1, 80),
      goal_weight_kg: readNumber('inp-goalweight', 20, 400),
    };

    const mutation = await Trainw.api.run(
      sb.from('client_profiles').update(payload).eq('id', currentClientProfileId),
      {
        context: 'save measurements',
        fallback: null,
      }
    );

    if (mutation.error) throw mutation.error;
    Trainw.ui.setText('m-height', payload.height_cm ?? '—');
    Trainw.ui.setText('m-weight', payload.weight_kg ?? '—');
    Trainw.ui.setText('m-bodyfat', payload.body_fat_pct ?? '—');
    Trainw.ui.setText('m-goalweight', payload.goal_weight_kg ?? '—');
    toggleMeasurementsEditor(false);
    toast(t('savedOk'));
  } catch (err) {
    console.error('Measurements error:', err);
    toast(err.message || t('errorMsg'), 'err');
  } finally {
    btn.textContent = originalLabel;
    Trainw.ui.setBusy(btn, false);
  }
}

async function saveSettings() {
  const name = document.getElementById('settings-name').value.trim();
  const phone = document.getElementById('settings-phone').value.trim();
  const goal = document.getElementById('settings-goal').value || null;

  if (!name) { toast(t('errorMsg'), 'err'); return; }

  const btn = document.getElementById('btn-save-settings');
  const originalLabel = btn.textContent;
  btn.textContent = '...';
  Trainw.ui.setBusy(btn, true);

  try {
    const userMutation = await Trainw.api.run(
      sb.from('users').update({ name, phone: phone || null }).eq('id', currentUserId),
      {
        context: 'update client settings',
        fallback: null,
      }
    );
    if (userMutation.error) throw userMutation.error;

    if (currentClientProfileId) {
      const profileMutation = await Trainw.api.run(
        sb.from('client_profiles').update({ fitness_goal: goal || null }).eq('id', currentClientProfileId),
        {
          context: 'update client goal',
          fallback: null,
        }
      );
      if (profileMutation.error) throw profileMutation.error;
    }

    userInitials = name.split(' ').map(part => part[0] || '').join('').slice(0, 2).toUpperCase();
    Trainw.ui.setText('sidebar-client-name', name);
    Trainw.ui.setText('stat-goal', goal || '—');
    toast(t('savedOk'));
  } catch (err) {
    console.error('Save settings error:', err);
    toast(err.message || t('errorMsg'), 'err');
  } finally {
    btn.textContent = originalLabel;
    Trainw.ui.setBusy(btn, false);
  }
}

async function generateDiet() {
  const goal = document.getElementById('diet-goal').value;
  const bodyType = document.getElementById('diet-body').value;
  const activity = document.getElementById('diet-activity').value;
  const workout = document.getElementById('diet-workout').value;
  const weightRaw = document.getElementById('inp-weight')?.value?.trim();
  const heightRaw = document.getElementById('inp-height')?.value?.trim();
  const weightKg = weightRaw ? Number(weightRaw) : null;
  const heightCm = heightRaw ? Number(heightRaw) : null;

  const btn = document.getElementById('btn-gen-diet');
  const originalLabel = btn.textContent;
  const outWrap = document.getElementById('diet-output');
  const mealsEl = document.getElementById('diet-meals');

  btn.textContent = '...';
  Trainw.ui.setBusy(btn, true);
  outWrap?.classList.remove('hidden');
  if (mealsEl) mealsEl.innerHTML = '<p style="color:var(--mt);padding:16px;">Loading...</p>';

  try {
    const data = await Trainw.api.edge(sb, 'diet_plan', {
      goal,
      bodyType,
      activityLevel: activity,
      workoutType: workout,
      weightKg,
      heightCm,
    });

    const plan = JSON.parse(data.result || '{}');
    Trainw.ui.setText('mac-cal', plan.calories || '—');
    Trainw.ui.setText('mac-p', (plan.protein_g || '—') + 'g');
    Trainw.ui.setText('mac-c', (plan.carbs_g || '—') + 'g');
    Trainw.ui.setText('mac-f', (plan.fats_g || '—') + 'g');

    if (mealsEl) {
      mealsEl.innerHTML = Array.isArray(plan.meals) && plan.meals.length
        ? plan.meals.map(meal => {
            const items = Array.isArray(meal.items) ? meal.items : [];
            return `<div class="meal-section">
              <div class="meal-title">${Trainw.escapeHtml(meal.title || '')}</div>
              <div class="meal-time">${Trainw.escapeHtml(meal.time || '')}</div>
              ${items.map(item => `<div class="meal-item">
                <div class="meal-item-name">${Trainw.escapeHtml(item.name || '')}${item.portion ? ' - ' + Trainw.escapeHtml(item.portion) : ''}</div>
                <div class="meal-item-details">${item.calories ? Trainw.escapeHtml(String(item.calories)) + ' cal' : ''}</div>
              </div>`).join('')}
            </div>`;
          }).join('')
        : '<p style="color:var(--mt);padding:8px;">Unable to build a plan.</p>';
    }
  } catch (err) {
    console.error('Diet generation error:', err);
    toast('Plan generated in local mode');
  } finally {
    btn.textContent = originalLabel;
    Trainw.ui.setBusy(btn, false);
  }
}

async function sendMessage() {
  if (!currentCoachUserId || !currentGymId) { toast(t('noCoach'), 'err'); return; }
  const input = document.getElementById('chat-input');
  const msg = input?.value.trim();
  if (!msg) return;
  input.value = '';

  const mutation = await Trainw.api.run(
    sb.from('messages').insert({
      gym_id: currentGymId,
      sender_id: currentUserId,
      receiver_id: currentCoachUserId,
      content: msg,
      is_automated: false,
    }),
    {
      context: 'send client message',
      fallback: null,
    }
  );

  if (mutation.error) {
    toast(mutation.error.message || t('errorMsg'), 'err');
    return;
  }

  messagesCache.push({
    id: 'local-' + Date.now(),
    content: msg,
    sender_id: currentUserId,
    created_at: new Date().toISOString(),
  });
  renderMessages();
}

function enhanceSidebarNavigation() {
  if (window.__trainwClientNavEnhanced) {
    window.lucide?.createIcons();
    return;
  }
  window.__trainwClientNavEnhanced = true;

  const iconMap = {
    dashboard: 'layout-dashboard',
    progress: 'bar-chart-2',
    nutrition: 'zap',
    coach: 'user-check',
    bookings: 'calendar',
    settings: 'settings',
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

function bindUi() {
  if (uiBound) return;
  uiBound = true;
  enhanceSidebarNavigation();

  document.querySelectorAll('.nav-item').forEach(item => {
    item.addEventListener('click', () => showPage(item.dataset.page));
  });
  document.querySelectorAll('.quick-card').forEach(card => {
    card.addEventListener('click', () => {
      if (card.dataset.goto) showPage(card.dataset.goto);
    });
  });
  document.querySelectorAll('.lang-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      currentLang = btn.dataset.lang || 'fr';
      localStorage.setItem('trainw_lang', currentLang);
      applyTranslations();
      renderSessions();
      renderCoachState();
      renderMessages();
    });
  });
  document.getElementById('btn-logout')?.addEventListener('click', async () => {
    try {
      const result = await Trainw.api.run(sb.auth.signOut(), { context: 'client sign out' });
      if (result.error) throw result.error;
      window.location.href = 'login.html?role=client';
    } catch (error) {
      toast(error.message || t('errorMsg'), 'err');
    }
  });
  document.getElementById('btn-save-measurements')?.addEventListener('click', saveMeasurements);
  document.getElementById('btn-save-settings')?.addEventListener('click', saveSettings);
  document.getElementById('btn-gen-diet')?.addEventListener('click', generateDiet);
  document.getElementById('btn-confirm-booking')?.addEventListener('click', confirmBooking);
  Trainw.auth.watchAuth(sb, {
    onSignedOut: () => { window.location.href = 'login.html?role=client'; },
  });
}

async function initPage() {
  bindUi();

  const context = await Trainw.auth.getContext(sb, {
    expectedRoles: ['client'],
    loginHref: 'login.html?role=client',
  });

  if (!context.session || !context.profile || context.error) return;

  currentUserId = context.session.user.id;
  currentGymId = context.profile.gym_id || null;
  currentLang = localStorage.getItem('trainw_lang') || context.profile.language_preference || currentLang;
  document.querySelector('.main-content')?.classList.add('page-loaded');

  const displayName = context.profile.name || context.session.user.email || 'Client';
  userInitials = displayName.split(' ').map(part => part[0] || '').join('').slice(0, 2).toUpperCase();
  Trainw.ui.setText('sidebar-client-name', displayName);
  Trainw.ui.setValue('settings-name', context.profile.name || '');
  Trainw.ui.setValue('settings-phone', context.profile.phone || '');

  const profileResult = await Trainw.api.run(
    sb
      .from('client_profiles')
      .select('id, membership_tier, fitness_goal, created_at, height_cm, weight_kg, body_fat_pct, goal_weight_kg')
      .eq('user_id', currentUserId)
      .maybeSingle(),
    {
      context: 'load client profile details',
      allowMissing: true,
      fallback: null,
    }
  );

  if (profileResult.data) {
    currentClientProfileId = profileResult.data.id;
    Trainw.ui.setText('stat-tier', (profileResult.data.membership_tier || 'basic').toUpperCase());
    Trainw.ui.setText('stat-goal', profileResult.data.fitness_goal || '—');
    Trainw.ui.setValue('settings-goal', profileResult.data.fitness_goal || '');

    if (profileResult.data.created_at) {
      const createdAt = new Date(profileResult.data.created_at);
      Trainw.ui.setText(
        'stat-since',
        Number.isNaN(createdAt.getTime()) ? '—' : createdAt.toLocaleDateString(locale(), { month: 'short', year: 'numeric' })
      );
    }

    Trainw.ui.setText('m-height', profileResult.data.height_cm ?? '—');
    Trainw.ui.setText('m-weight', profileResult.data.weight_kg ?? '—');
    Trainw.ui.setText('m-bodyfat', profileResult.data.body_fat_pct ?? '—');
    Trainw.ui.setText('m-goalweight', profileResult.data.goal_weight_kg ?? '—');
    Trainw.ui.setValue('inp-height', profileResult.data.height_cm ?? '');
    Trainw.ui.setValue('inp-weight', profileResult.data.weight_kg ?? '');
    Trainw.ui.setValue('inp-bodyfat', profileResult.data.body_fat_pct ?? '');
    Trainw.ui.setValue('inp-goalweight', profileResult.data.goal_weight_kg ?? '');
  } else {
    Trainw.ui.setText('stat-tier', 'BASIC');
    Trainw.ui.setText('stat-goal', '—');
    Trainw.ui.setText('stat-since', '—');
  }

  applyTranslations();
  toggleMeasurementsEditor(false);
  await loadSessions();
  await loadCoach();
}
document.getElementById('btn-send-msg').addEventListener('click', sendMessage);
document.getElementById('chat-input').addEventListener('keypress', e => { if (e.key === 'Enter') sendMessage(); });

// ── Toast ─────────────────────────────────────────────────
function toast(msg, type) {
  Trainw.ui.showToast(msg, type);
}

initPage();

