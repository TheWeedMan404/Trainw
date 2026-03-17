// ── Supabase ──────────────────────────────────────────────
const sb = window.supabase.createClient(
  'https://bibqumevndfykmkssslb.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJpYnF1bWV2bmRmeWtta3Nzc2xiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMzNjM1NzAsImV4cCI6MjA4ODkzOTU3MH0.X51EBM0ERPiMmGE2kP18JRrqrF4O6ebA_c2oCdP6wEM'
);

let currentUserId      = null;
let currentClientProfileId = null;
let currentCoachUserId = null;
let selectedSlot       = null;
let userInitials       = 'ME';
let currentLang        = 'en';

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
    aiDietTitle:'AI Diet Generator', aiDietSub:'Smart meal planning based on your goals and Tunisian food preferences',
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
  if (!session) { window.location.href = 'TW Login.html?role=client'; return; }
  currentUserId = session.user.id;

  const { data: user } = await sb.from('users').select('name, phone').eq('id', currentUserId).single();
  if (user?.name) {
    document.getElementById('sidebar-client-name').textContent = user.name;
    userInitials = user.name.split(' ').map(n => n[0]).join('').slice(0,2).toUpperCase();
    document.getElementById('settings-name').value  = user.name  || '';
    document.getElementById('settings-phone').value = user.phone || '';
  }

  const { data: client } = await sb.from('client_profiles')
    .select('id, membership_tier, fitness_goal, created_at, height_cm, weight_kg, body_fat_pct, goal_weight_kg')
    .eq('user_id', currentUserId).single();

  if (client) {
    currentClientProfileId = client.id;
    document.getElementById('stat-tier').textContent  = (client.membership_tier || 'basic').toUpperCase();
    document.getElementById('stat-goal').textContent  = client.fitness_goal || '—';
    document.getElementById('settings-goal').value   = client.fitness_goal || '';
    if (client.created_at) {
      document.getElementById('stat-since').textContent = new Date(client.created_at).toLocaleDateString('en-GB', { month:'short', year:'numeric' });
    }
    // Measurements
    document.getElementById('m-height').textContent    = client.height_cm    || '—';
    document.getElementById('m-weight').textContent    = client.weight_kg    || '—';
    document.getElementById('m-bodyfat').textContent   = client.body_fat_pct || '—';
    document.getElementById('m-goalweight').textContent = client.goal_weight_kg || '—';
    document.getElementById('inp-height').value    = client.height_cm    || '';
    document.getElementById('inp-weight').value    = client.weight_kg    || '';
    document.getElementById('inp-bodyfat').value   = client.body_fat_pct || '';
    document.getElementById('inp-goalweight').value = client.goal_weight_kg || '';
  }

  await loadSessions();
  await loadCoach();
  applyTranslations();
})();

// ── Sessions ──────────────────────────────────────────────
async function loadSessions() {
  const { data: sessions } = await sb.from('sessions')
    .select('id, session_date, start_time, duration_minutes, type, status, coach_id, users!sessions_coach_id_fkey(name)')
    .eq('client_id', currentUserId)
    .order('session_date', { ascending: false });

  if (!sessions || sessions.length === 0) {
    document.getElementById('stat-sessions').textContent = '0';
    const noMsg = `<p class="empty-state">${t('noSessions')}</p>`;
    ['recent-sessions','all-sessions','upcoming-sessions'].forEach(id => {
      document.getElementById(id).innerHTML = noMsg;
    });
    return;
  }

  const now = new Date();
  const mo = now.getMonth(), yr = now.getFullYear();
  const monthCount = sessions.filter(s => {
    const d = new Date(s.session_date);
    return d.getMonth() === mo && d.getFullYear() === yr;
  }).length;
  document.getElementById('stat-sessions').textContent = monthCount;

  const renderItem = s => {
    const coachName = s.users?.name || 'Coach';
    const days = Math.floor((Date.now() - new Date(s.session_date)) / 86400000);
    const when = days < 0 ? 'Upcoming' : days === 0 ? 'Today' : days === 1 ? 'Yesterday' : `${days}d ago`;
    const type = (s.type || 'Session').replace(/_/g,' ');
    const statusColor = s.status === 'completed' ? 'var(--ac)' : s.status === 'cancelled' ? 'var(--rd)' : 'var(--gd)';
    return `<div class="activity-item">
      <div class="activity-title">${type} with ${coachName}</div>
      <div class="activity-meta">${when} • ${s.start_time?.slice(0,5) || ''} • ${s.duration_minutes ?? 60}min • <span style="color:${statusColor}">${s.status || 'confirmed'}</span></div>
    </div>`;
  };

  document.getElementById('recent-sessions').innerHTML = sessions.slice(0,5).map(renderItem).join('');
  document.getElementById('all-sessions').innerHTML    = sessions.map(renderItem).join('');
  const upcoming = sessions.filter(s => new Date(s.session_date) >= now && s.status !== 'cancelled');
  document.getElementById('upcoming-sessions').innerHTML = upcoming.length
    ? upcoming.map(renderItem).join('')
    : `<p class="empty-state">${t('noSessions')}</p>`;
}

// ── Coach ─────────────────────────────────────────────────
async function loadCoach() {
  const { data: last } = await sb.from('sessions')
    .select('coach_id, users!sessions_coach_id_fkey(name), coach_profiles!sessions_coach_id_fkey(id, specialty, rating)')
    .eq('client_id', currentUserId)
    .order('session_date', { ascending: false })
    .limit(1).maybeSingle();

  if (!last) {
    document.getElementById('coach-name').textContent = t('noCoach');
    document.getElementById('slots-grid').innerHTML = `<p class="empty-state">${t('noCoach')}</p>`;
    return;
  }

  currentCoachUserId = last.coach_id;
  const name      = last.users?.name || 'Coach';
  const specialty = last.coach_profiles?.specialty || '';
  const rating    = last.coach_profiles?.rating;
  const initials  = name.split(' ').map(n => n[0]).join('').slice(0,2);

  document.getElementById('coach-avatar').textContent   = initials;
  document.getElementById('coach-name').textContent     = name;
  document.getElementById('coach-specialty').textContent = specialty;
  document.getElementById('coach-rating').textContent   = rating ? '★ ' + rating : '';
  document.getElementById('quick-book-desc').textContent = 'Schedule with ' + name.split(' ')[0];

  // Static slots — replace with real availability query when ready
  document.getElementById('slots-grid').innerHTML = ['08:00','10:00','14:00','17:00','18:00','19:00']
    .map(h => `<div class="slot" data-time="${h}"><div class="slot-time">${h}</div><div class="slot-status">Available</div></div>`)
    .join('');

  document.querySelectorAll('.slot').forEach(slot => {
    slot.addEventListener('click', () => {
      if (slot.classList.contains('booked')) return;
      document.querySelectorAll('.slot').forEach(s => s.classList.remove('selected'));
      slot.classList.add('selected');
      selectedSlot = slot.dataset.time;
    });
  });
}

// ── Book Session ──────────────────────────────────────────
async function confirmBooking() {
  if (!selectedSlot) { toast(t('selectSlot')); return; }
  if (!currentCoachUserId) { toast(t('noCoach')); return; }

  const btn = document.getElementById('btn-confirm-booking');
  btn.textContent = '…'; btn.disabled = true;
  try {
    const tomorrow = new Date(); tomorrow.setDate(tomorrow.getDate() + 1);
    const sessionDate = tomorrow.toISOString().split('T')[0];

    const { error } = await sb.from('sessions').insert({
      coach_id:         currentCoachUserId,
      client_id:        currentUserId,
      session_date:     sessionDate,
      start_time:       selectedSlot + ':00',
      duration_minutes: 60,
      type:             'personal_training',
      status:           'pending',
    });
    if (error) throw new Error(error.message);

    toast(t('bookingOk'));
    selectedSlot = null;
    document.querySelectorAll('.slot').forEach(s => s.classList.remove('selected'));
    await loadSessions();
  } catch (err) {
    toast('Error: ' + err.message);
  } finally {
    btn.textContent = t('confirmBooking'); btn.disabled = false;
  }
}

// ── Measurements ──────────────────────────────────────────
document.getElementById('btn-toggle-measurements').addEventListener('click', () => {
  const view = document.getElementById('measurements-view');
  const edit = document.getElementById('measurements-edit');
  const isEditing = !edit.classList.contains('hidden');
  view.classList.toggle('hidden', !isEditing);
  edit.classList.toggle('hidden', isEditing);
  document.getElementById('btn-toggle-measurements').textContent = isEditing ? t('edit') : 'Cancel';
});

async function saveMeasurements() {
  if (!currentClientProfileId) { toast(t('errorMsg')); return; }
  const height    = parseFloat(document.getElementById('inp-height').value)    || null;
  const weight    = parseFloat(document.getElementById('inp-weight').value)    || null;
  const bodyfat   = parseFloat(document.getElementById('inp-bodyfat').value)   || null;
  const goalweight = parseFloat(document.getElementById('inp-goalweight').value) || null;

  const btn = document.getElementById('btn-save-measurements');
  btn.textContent = '…'; btn.disabled = true;
  try {
    const { error } = await sb.from('client_profiles').update({
      height_cm:      height,
      weight_kg:      weight,
      body_fat_pct:   bodyfat,
      goal_weight_kg: goalweight,
    }).eq('id', currentClientProfileId);
    if (error) throw new Error(error.message);

    // Update display
    document.getElementById('m-height').textContent    = height    ?? '—';
    document.getElementById('m-weight').textContent    = weight    ?? '—';
    document.getElementById('m-bodyfat').textContent   = bodyfat   ?? '—';
    document.getElementById('m-goalweight').textContent = goalweight ?? '—';

    document.getElementById('measurements-view').classList.remove('hidden');
    document.getElementById('measurements-edit').classList.add('hidden');
    document.getElementById('btn-toggle-measurements').textContent = t('edit');
    toast(t('savedOk'));
  } catch (err) {
    toast('Error: ' + err.message);
  } finally {
    btn.textContent = t('saveMeasurements'); btn.disabled = false;
  }
}

// ── Settings ──────────────────────────────────────────────
async function saveSettings() {
  const name  = document.getElementById('settings-name').value.trim();
  const phone = document.getElementById('settings-phone').value.trim();
  const goal  = document.getElementById('settings-goal').value;

  const btn = document.getElementById('btn-save-settings');
  btn.textContent = '…'; btn.disabled = true;
  try {
    await sb.from('users').update({ name, phone }).eq('id', currentUserId);
    if (currentClientProfileId && goal) {
      await sb.from('client_profiles').update({ fitness_goal: goal }).eq('id', currentClientProfileId);
    }
    document.getElementById('sidebar-client-name').textContent = name;
    document.getElementById('stat-goal').textContent = goal || '—';
    toast(t('savedOk'));
  } catch (err) {
    toast('Error: ' + err.message);
  } finally {
    btn.textContent = t('saveChanges'); btn.disabled = false;
  }
}

// ── Diet Generator ────────────────────────────────────────
function generateDiet() {
  const goal     = document.getElementById('diet-goal').value;
  const bodyType = document.getElementById('diet-body').value;
  const activity = document.getElementById('diet-activity').value;
  const workout  = document.getElementById('diet-workout').value;

  let cals = 1600;
  if (bodyType === 'ectomorph') cals += 200;
  if (bodyType === 'endomorph') cals -= 150;
  if (activity === 'moderate')  cals += 200;
  if (activity === 'active')    cals += 350;
  if (activity === 'very-active') cals += 500;
  if (goal === 'muscle-gain')   cals += 300;
  if (goal === 'fat-loss')      cals -= 300;

  const pR = (workout === 'strength' || goal === 'muscle-gain') ? 0.35 : 0.28;
  const cR = workout === 'cardio' ? 0.50 : 0.40;
  const fR = 1 - pR - cR;
  const protein = Math.round((cals * pR) / 4);
  const carbs   = Math.round((cals * cR) / 4);
  const fats    = Math.round((cals * fR) / 9);

  const meals = [
    { title:'Breakfast',         time:'7:30 AM',  items:[{name:'Whole wheat msemmen',portion:'2 pieces',cal:280,p:'10g',c:'48g',f:'6g'},{name:'Lben (low-fat)',portion:'200ml',cal:90,p:'8g',c:'12g',f:'1g'},{name:'Olive oil + zaatar',portion:'1 tbsp',cal:120,p:'0g',c:'1g',f:'14g'}]},
    { title:'Mid-Morning Snack', time:'10:30 AM', items:[{name:'Deglet nour dates',portion:'4 pieces',cal:120,p:'1g',c:'30g',f:'0g'},{name:'Almonds',portion:'15g',cal:90,p:'3g',c:'3g',f:'8g'}]},
    { title:'Lunch',             time:'1:00 PM',  items:[{name:'Grilled chicken breast',portion:'150g',cal:240,p:'45g',c:'0g',f:'5g'},{name:'Couscous with vegetables',portion:'1 cup',cal:210,p:'7g',c:'42g',f:'1g'},{name:'Mechouia salad',portion:'1 serving',cal:80,p:'2g',c:'8g',f:'5g'}]},
    { title:'Pre-Workout Snack', time:'4:30 PM',  items:[{name:'Harissa chickpeas',portion:'50g',cal:140,p:'7g',c:'20g',f:'4g'},{name:'Orange',portion:'1 medium',cal:60,p:'1g',c:'15g',f:'0g'}]},
    { title:'Dinner',            time:'7:30 PM',  items:[{name:'Grilled sea bass',portion:'180g',cal:200,p:'40g',c:'0g',f:'4g'},{name:'Slata mechouia',portion:'1 serving',cal:90,p:'3g',c:'10g',f:'5g'},{name:'Artichoke hearts',portion:'1 cup',cal:60,p:'4g',c:'13g',f:'0g'}]},
  ];

  document.getElementById('diet-meals').innerHTML = meals.map(m => `
    <div class="meal-section">
      <div class="meal-title">${m.title}</div>
      <div class="meal-time">${m.time}</div>
      ${m.items.map(i => `<div class="meal-item">
        <div class="meal-item-name">${i.name} — ${i.portion}</div>
        <div class="meal-item-details">${i.cal} cal • P: ${i.p} • C: ${i.c} • F: ${i.f}</div>
      </div>`).join('')}
    </div>`).join('');

  document.getElementById('mac-cal').textContent = cals;
  document.getElementById('mac-p').textContent   = protein + 'g';
  document.getElementById('mac-c').textContent   = carbs   + 'g';
  document.getElementById('mac-f').textContent   = fats    + 'g';
  document.getElementById('diet-output').classList.remove('hidden');
  toast('Diet generated!');
}

// ── Chat ──────────────────────────────────────────────────
function sendMessage() {
  const input = document.getElementById('chat-input');
  const msg   = input.value.trim();
  if (!msg) return;
  const time = new Date().toLocaleTimeString([], { hour:'2-digit', minute:'2-digit' });
  document.getElementById('chat-messages').innerHTML += `
    <div class="message sent">
      <div class="msg-avatar">${userInitials}</div>
      <div><div class="msg-bubble">${msg}</div><div class="msg-time">${time}</div></div>
    </div>`;
  input.value = '';
  document.getElementById('chat-messages').scrollTop = 99999;
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

// Quick cards nav
document.querySelectorAll('.quick-card[data-goto]').forEach(card => {
  card.addEventListener('click', () => {
    const target = card.dataset.goto;
    document.querySelectorAll('.page').forEach(p => p.classList.add('hidden'));
    document.getElementById(target + '-page').classList.remove('hidden');
    document.querySelectorAll('.nav-item').forEach(n => {
      n.classList.toggle('active', n.dataset.page === target);
    });
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
document.getElementById('btn-confirm-booking').addEventListener('click', confirmBooking);
document.getElementById('btn-save-measurements').addEventListener('click', saveMeasurements);
document.getElementById('btn-save-settings').addEventListener('click', saveSettings);
document.getElementById('btn-gen-diet').addEventListener('click', generateDiet);
document.getElementById('btn-send-msg').addEventListener('click', sendMessage);
document.getElementById('chat-input').addEventListener('keypress', e => { if (e.key === 'Enter') sendMessage(); });

// ── Toast ─────────────────────────────────────────────────
function toast(msg) {
  const el = document.getElementById('toast');
  document.getElementById('toast-msg').textContent = msg;
  el.classList.add('show');
  setTimeout(() => el.classList.remove('show'), 3000);
}

applyTranslations();
