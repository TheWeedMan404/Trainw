// ── Config ────────────────────────────────────────────────
const Trainw = window.TrainwCore;
const sb = Trainw.createClient();
Trainw.installGlobalErrorHandlers();

let currentUser    = null;
let currentGymId   = null;
let currentLang    = localStorage.getItem('trainw_lang') || 'fr';
let scheduleFilter = 'all';
let clientFilter   = 'all';
let allSessions    = [];
let allClients     = [];
let gymCoaches     = [];
let checkInsList   = [];
let conversationMap = {};
let activeConvId    = null;

// ── i18n ──────────────────────────────────────────────────
const T = {
  fr: {
    gymOwner:'Propriétaire', signOut:'Déconnexion',
    navDashboard:'Tableau de Bord', navSchedule:'Planning', navCoaches:'Coachs',
    navClients:'Clients', navAnalytics:'Analytiques', navSettings:'Paramètres',
    navCheckIn:'Check-In', navMessages:'Messages', navClasses:'Cours',
    dashSub:"Votre salle en un coup d'œil",
    statClients:'Clients Actifs', statCoaches:'Coachs Actifs',
    statSessions:'Séances Cette Semaine', statRevenue:'Revenu Mensuel', statCheckins:"Check-ins Aujourd'hui",
    thisMonth:'ce mois', onStaff:'en staff', vsLastWeek:'cette semaine', comingSoon:'Bientôt disponible',
    topCoaches:'Meilleurs Coachs', recentSessions:'Séances Récentes', loading:'Chargement…',
    schedSub:'Toutes les séances de votre salle',
    filterAll:'Tout', filterConfirmed:'Confirmé', filterPending:'En attente', filterCompleted:'Terminé', filterPaid:'Payé',
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
    bizMetrics:'Métriques Générales', opsMetrics:'Opérations',
    popularClasses:'Cours Populaires', coachUtil:'Utilisation des Coachs',
    predTitle:'Prévision Intelligente', predMonthly:'Revenu Estimé / Mois', predSessions:'Séances / Semaine', predRetention:'Taux Activité',
    settingsSub:'Configurez votre salle', gymInfo:'Informations de la Salle',
    gymNameLbl:'Nom de la Salle', addressLbl:'Adresse', phoneLbl:'Téléphone', descLbl:'Description',
    saveChanges:'Enregistrer',
    accountSettings:'Compte', currentEmail:'Email actuel', changePassword:'Changer le mot de passe',
    subscription:'Abonnement', freeTier:'Essai Gratuit',
    subDesc:'Passez au plan Pro pour débloquer toutes les fonctionnalités', upgradePro:'Passer au Pro →',
    langSettings:'Langue', support:'Support', contactSupport:'Contacter le Support',
    addCoachTitle:'Ajouter un Coach', coachName:'Nom Complet', coachEmail:'Email',
    coachPhone:'Téléphone', coachSpecialty:'Spécialité', coachRate:'Tarif / Séance (DT)', submitCoach:'Ajouter le Coach',
    noCoaches:'Aucun coach. Ajoutez votre premier coach !', noClients:'Aucun client. Ajoutez votre premier client !', noSessions:'Aucune séance trouvée.',
    savedOk:'Enregistré !', coachAdded:'Coach ajouté !', clientAdded:'Client ajouté !', sessionCreated:'Séance créée !', errorMsg:'Une erreur est survenue.',
    hourlyRate:'DT/séance', avgRating:'Note', employedLbl:'Ancienneté', totalReviews:'Avis',
    emailMissing:'Veuillez saisir un email valide.', nameMissing:'Veuillez saisir un nom.',
    sessNameMissing:'Veuillez saisir un nom de séance.', sessDateMissing:'Veuillez choisir une date.', sessTimeMissing:'Veuillez choisir une heure.',
    memberSince:'Membre depuis', membership:'Abonnement', training:'Entraînement',
    payment:'Paiement', editClient:'Modifier', deleteClient:'Supprimer', editCoach:'Modifier', deleteCoach:'Supprimer',
    pwReset:'Email de réinitialisation envoyé !',
    checkInTitle:'Check-In Clients', checkInSub:'Marquer la présence des clients',
    checkInNow:'Check-In Manuel', checkInToday:"Check-ins d'aujourd'hui",
    noCheckIns:"Aucun check-in aujourd'hui.", checkedIn:'Présent à',
    selectClient:'Sélectionner un client…', confirmCheckIn:'Confirmer le Check-In',
    checkInDone:'Check-in enregistré !', alreadyCheckedIn:"Déjà enregistré aujourd'hui.",
    messagesTitle:'Messages', messagesSub:'Conversations avec vos clients',
    typeMessage:'Écrivez un message…', sendMsg:'Envoyer',
    noMessages:'Aucune conversation. Sélectionnez un client pour commencer.', selectConv:'Sélectionnez une conversation',
    classesTitle:'Cours & Activités', classesSub:'Gérez les cours de votre salle',
    addClass:'+ Ajouter un Cours', addClassTitle:'Ajouter un Cours',
    className:'Nom du Cours', classDesc:'Description', classDay:'Jour', classTime:'Heure',
    classDuration:'Durée (min)', classCapacity:'Capacité', classCoach:'Coach',
    submitClass:'Ajouter le Cours', classAdded:'Cours ajouté !',
    noClasses:'Aucun cours. Créez votre premier cours !', deleteClass:'Supprimer',
    membershipStart:'Début Abonnement', membershipEnd:'Fin Abonnement', pricePaid:'Montant Payé (DT)',
    expiresIn:'Expire dans', expiredSince:'Expiré depuis', daysLeft:'jours', renewalNeeded:'Renouvellement requis',
    expiringLabel:'Expire bientôt', expiredLabel:'Expiré', activeLabel:'Actif',
    membersExpiring:'Membres à Renouveler', noExpiring:'Tous les abonnements sont à jour.',
    revenueReal:'Revenus Réels', revenueMonth:'Ce Mois',
    editSession:'Modifier', deleteSession:'Supprimer', editSessionTitle:'Modifier la Séance',
  },
  en: {
    gymOwner:'Gym Owner', signOut:'Sign Out',
    navDashboard:'Dashboard', navSchedule:'Schedule', navCoaches:'Coaches',
    navClients:'Clients', navAnalytics:'Analytics', navSettings:'Settings',
    navCheckIn:'Check-In', navMessages:'Messages', navClasses:'Classes',
    dashSub:'Your gym at a glance',
    statClients:'Active Clients', statCoaches:'Active Coaches',
    statSessions:'Sessions This Week', statRevenue:'Monthly Revenue', statCheckins:'Check-ins Today',
    thisMonth:'this month', onStaff:'on staff', vsLastWeek:'this week', comingSoon:'Coming soon',
    topCoaches:'Top Coaches', recentSessions:'Recent Sessions', loading:'Loading…',
    schedSub:'All sessions across your gym',
    filterAll:'All', filterConfirmed:'Confirmed', filterPending:'Pending', filterCompleted:'Completed', filterPaid:'Paid',
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
    bizMetrics:'General Metrics', opsMetrics:'Operations',
    popularClasses:'Popular Classes', coachUtil:'Coach Utilization',
    predTitle:'Smart Prediction', predMonthly:'Est. Revenue / Month', predSessions:'Sessions / Week', predRetention:'Activity Rate',
    settingsSub:'Configure your gym', gymInfo:'Gym Information',
    gymNameLbl:'Gym Name', addressLbl:'Address', phoneLbl:'Phone', descLbl:'Description', saveChanges:'Save Changes',
    accountSettings:'Account', currentEmail:'Current Email', changePassword:'Change Password',
    subscription:'Subscription', freeTier:'Free Trial',
    subDesc:'Upgrade to Pro to unlock all features', upgradePro:'Upgrade to Pro →',
    langSettings:'Language', support:'Support', contactSupport:'Contact Support',
    addCoachTitle:'Add New Coach', coachName:'Full Name', coachEmail:'Email',
    coachPhone:'Phone', coachSpecialty:'Specialty', coachRate:'Rate / Session (DT)', submitCoach:'Add Coach',
    noCoaches:'No coaches yet. Add your first coach!', noClients:'No clients yet. Add your first client!', noSessions:'No sessions found.',
    savedOk:'Saved!', coachAdded:'Coach added!', clientAdded:'Client added!', sessionCreated:'Session created!', errorMsg:'Something went wrong.',
    hourlyRate:'DT/session', avgRating:'Rating', employedLbl:'Employed', totalReviews:'Reviews',
    emailMissing:'Please enter a valid email.', nameMissing:'Please enter a name.',
    sessNameMissing:'Please enter a session name.', sessDateMissing:'Please choose a date.', sessTimeMissing:'Please choose a time.',
    memberSince:'Member since', membership:'Membership', training:'Training',
    payment:'Payment', editClient:'Edit', deleteClient:'Delete', editCoach:'Edit', deleteCoach:'Delete',
    pwReset:'Reset email sent!',
    checkInTitle:'Client Check-In', checkInSub:'Mark client attendance',
    checkInNow:'Manual Check-In', checkInToday:"Today's Check-ins",
    noCheckIns:'No check-ins today.', checkedIn:'Checked in at',
    selectClient:'Select a client…', confirmCheckIn:'Confirm Check-In',
    checkInDone:'Check-in recorded!', alreadyCheckedIn:'Already checked in today.',
    messagesTitle:'Messages', messagesSub:'Conversations with your clients',
    typeMessage:'Write a message…', sendMsg:'Send',
    noMessages:'No conversations. Select a client to start.', selectConv:'Select a conversation',
    classesTitle:'Classes & Activities', classesSub:'Manage your gym classes',
    addClass:'+ Add Class', addClassTitle:'Add Class',
    className:'Class Name', classDesc:'Description', classDay:'Day', classTime:'Time',
    classDuration:'Duration (min)', classCapacity:'Capacity', classCoach:'Coach',
    submitClass:'Add Class', classAdded:'Class added!',
    noClasses:'No classes yet. Create your first class!', deleteClass:'Delete',
    membershipStart:'Membership Start', membershipEnd:'Membership End', pricePaid:'Amount Paid (DT)',
    expiresIn:'Expires in', expiredSince:'Expired', daysLeft:'days', renewalNeeded:'Renewal needed',
    expiringLabel:'Expiring soon', expiredLabel:'Expired', activeLabel:'Active',
    membersExpiring:'Members to Renew', noExpiring:'All memberships are up to date.',
    revenueReal:'Real Revenue', revenueMonth:'This Month',
    editSession:'Edit', deleteSession:'Delete', editSessionTitle:'Edit Session',
  },
  ar: {
    gymOwner:'مالك الصالة', signOut:'تسجيل الخروج',
    navDashboard:'لوحة التحكم', navSchedule:'الجدول', navCoaches:'المدربون',
    navClients:'العملاء', navAnalytics:'التحليلات', navSettings:'الإعدادات',
    navCheckIn:'تسجيل الحضور', navMessages:'الرسائل', navClasses:'الدروس',
    dashSub:'صالتك في نظرة واحدة',
    statClients:'العملاء النشطون', statCoaches:'المدربون النشطون',
    statSessions:'جلسات هذا الأسبوع', statRevenue:'الإيرادات الشهرية', statCheckins:'حضور اليوم',
    thisMonth:'هذا الشهر', onStaff:'في الفريق', vsLastWeek:'هذا الأسبوع', comingSoon:'قريباً',
    topCoaches:'أفضل المدربين', recentSessions:'الجلسات الأخيرة', loading:'جار التحميل…',
    schedSub:'جميع جلسات صالتك',
    filterAll:'الكل', filterConfirmed:'مؤكد', filterPending:'معلق', filterCompleted:'منتهي', filterPaid:'مدفوع',
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
    bizMetrics:'المقاييس العامة', opsMetrics:'العمليات',
    popularClasses:'الفصول الشائعة', coachUtil:'استخدام المدربين',
    predTitle:'التوقع الذكي', predMonthly:'الإيراد المقدر / شهر', predSessions:'الجلسات / أسبوع', predRetention:'معدل النشاط',
    settingsSub:'إعداد صالتك', gymInfo:'معلومات الصالة',
    gymNameLbl:'اسم الصالة', addressLbl:'العنوان', phoneLbl:'الهاتف', descLbl:'الوصف', saveChanges:'حفظ التغييرات',
    accountSettings:'الحساب', currentEmail:'البريد الحالي', changePassword:'تغيير كلمة المرور',
    subscription:'الاشتراك', freeTier:'تجربة مجانية',
    subDesc:'ترقية إلى Pro لفتح جميع الميزات', upgradePro:'الترقية إلى Pro ←',
    langSettings:'اللغة', support:'الدعم', contactSupport:'تواصل مع الدعم',
    addCoachTitle:'إضافة مدرب', coachName:'الاسم الكامل', coachEmail:'البريد الإلكتروني',
    coachPhone:'الهاتف', coachSpecialty:'التخصص', coachRate:'الأجر / جلسة (دت)', submitCoach:'إضافة المدرب',
    noCoaches:'لا يوجد مدربون بعد.', noClients:'لا يوجد عملاء بعد.', noSessions:'لا توجد جلسات.',
    savedOk:'تم الحفظ!', coachAdded:'تمت إضافة المدرب!', clientAdded:'تمت إضافة العميل!', sessionCreated:'تم إنشاء الجلسة!', errorMsg:'حدث خطأ ما.',
    hourlyRate:'دت/جلسة', avgRating:'التقييم', employedLbl:'مدة العمل', totalReviews:'التقييمات',
    emailMissing:'الرجاء إدخال بريد إلكتروني صحيح.', nameMissing:'الرجاء إدخال الاسم.',
    sessNameMissing:'الرجاء إدخال اسم الجلسة.', sessDateMissing:'الرجاء اختيار تاريخ.', sessTimeMissing:'الرجاء اختيار وقت.',
    memberSince:'عضو منذ', membership:'الاشتراك', training:'التدريب',
    payment:'الدفع', editClient:'تعديل', deleteClient:'حذف', editCoach:'تعديل', deleteCoach:'حذف',
    pwReset:'تم إرسال رابط الاسترداد!',
    checkInTitle:'تسجيل الحضور', checkInSub:'تسجيل حضور العملاء',
    checkInNow:'تسجيل يدوي', checkInToday:'حضور اليوم',
    noCheckIns:'لا يوجد حضور اليوم.', checkedIn:'تسجيل في',
    selectClient:'اختر عميلاً…', confirmCheckIn:'تأكيد الحضور',
    checkInDone:'تم تسجيل الحضور!', alreadyCheckedIn:'تم التسجيل مسبقاً اليوم.',
    messagesTitle:'الرسائل', messagesSub:'المحادثات مع العملاء',
    typeMessage:'اكتب رسالة…', sendMsg:'إرسال',
    noMessages:'لا توجد محادثات. اختر عميلاً للبدء.', selectConv:'اختر محادثة',
    classesTitle:'الدروس والأنشطة', classesSub:'إدارة دروس صالتك',
    addClass:'+ إضافة درس', addClassTitle:'إضافة درس',
    className:'اسم الدرس', classDesc:'الوصف', classDay:'اليوم', classTime:'الوقت',
    classDuration:'المدة (دقيقة)', classCapacity:'السعة', classCoach:'المدرب',
    submitClass:'إضافة الدرس', classAdded:'تمت إضافة الدرس!',
    noClasses:'لا توجد دروس بعد. أنشئ أول درس!', deleteClass:'حذف',
    membershipStart:'بداية الاشتراك', membershipEnd:'نهاية الاشتراك', pricePaid:'المبلغ المدفوع (دت)',
    expiresIn:'ينتهي في', expiredSince:'منتهي منذ', daysLeft:'أيام', renewalNeeded:'يحتاج تجديد',
    expiringLabel:'ينتهي قريباً', expiredLabel:'منتهي', activeLabel:'نشط',
    membersExpiring:'أعضاء للتجديد', noExpiring:'جميع الاشتراكات سارية.',
    revenueReal:'الإيرادات الفعلية', revenueMonth:'هذا الشهر',
    editSession:'تعديل', deleteSession:'حذف', editSessionTitle:'تعديل الجلسة',
  }
};
const t = k => T[currentLang]?.[k] || T.fr[k] || k;

function applyTranslations() {
  document.querySelectorAll('[data-i18n]').forEach(el => {
    const k = el.getAttribute('data-i18n');
    if (T[currentLang]?.[k]) el.textContent = T[currentLang][k];
  });
  document.documentElement.setAttribute('dir', currentLang === 'ar' ? 'rtl' : 'ltr');
  document.querySelectorAll('.lang-option-btn').forEach(b => b.classList.toggle('active', b.dataset.lang === currentLang));
  document.querySelectorAll('.lang-btn').forEach(b => b.classList.toggle('active', b.dataset.lang === currentLang));
}

function locale() {
  return Trainw.localeForLang(currentLang);
}

// ── Session categories — FIX: key 'individual_training' ──
const SESSION_CATEGORIES = {
  group_class:        ['Yoga','HIIT','Cardio','Pilates','CrossFit','Zumba','Musculation','Mobilité','Stretching','Fonctionnel','Spinning','Bootcamp'],
  group_activity:     ['Piscine','Terrain de Football','Court de Tennis','Basketball','Volleyball','Sauna','Salle Libre','Piste de Course'],
  individual_training:['Entraînement Personnel','Boxe Privée','Coaching Musculation','Coaching Perte de Poids','Conditionnement Athlétique','Rééducation']
};
function updateSessionCategory() {
  const typeVal = document.getElementById('sess-type').value;
  const key     = typeVal === 'individual' ? 'individual_training' : typeVal;
  const sel     = document.getElementById('sess-category');
  const cats    = SESSION_CATEGORIES[key] || SESSION_CATEGORIES['group_class'];
  sel.innerHTML = cats.map(c => `<option value="${c}">${c}</option>`).join('');
  const coachGroup = document.getElementById('sess-coach-group');
  const coachLabel = coachGroup?.querySelector('.form-label');
  if (typeVal === 'group_activity') {
    if (coachLabel) coachLabel.innerHTML = t('sessCoach') + ` <span style="color:var(--mt);font-size:10px;">${t('optional')}</span>`;
  } else {
    if (coachLabel) coachLabel.textContent = t('sessCoach');
  }
}

// ── Toast ─────────────────────────────────────────────────
function toast(msg, type='ok') {
  Trainw.ui.showToast(msg, type);
}


// ── Skeleton loaders ─────────────────────────────────────
function skeletonCards(n=3) {
  return Array.from({length:n}, () => `
    <div class="skeleton-card">
      <div class="skeleton-row">
        <div class="skeleton skeleton-avatar"></div>
        <div style="flex:1"><div class="skeleton skeleton-line medium"></div><div class="skeleton skeleton-line short" style="margin-top:6px;"></div></div>
      </div>
      <div class="skeleton skeleton-line full"></div>
    </div>`).join('');
}
function skeletonRows(n=4) {
  return Array.from({length:n}, () => `
    <div class="skeleton-row" style="padding:12px 0;border-bottom:1px solid var(--bd);">
      <div class="skeleton skeleton-line short" style="width:60px;"></div>
      <div style="flex:1;margin:0 12px;"><div class="skeleton skeleton-line medium"></div></div>
      <div class="skeleton skeleton-line short" style="width:70px;"></div>
    </div>`).join('');
}

// ── Init ──────────────────────────────────────────────────
async function legacyInitDisabled() {
  try {
    const { data: { session } } = await sb.auth.getSession();
    if (!session) { window.location.href = 'login.html?role=gym_owner'; return; }
    currentUser = session.user;
    const emailEl = document.getElementById('account-email');
    if (emailEl) emailEl.value = currentUser.email || '';

    const { data: profile } = await sb.from('users').select('gym_id, name').eq('id', currentUser.id).single();
    if (profile?.gym_id) {
      currentGymId = profile.gym_id;
      const { data: gym } = await sb.from('gyms').select('name, address, phone, description, subscription_tier, price_monthly, price_quarterly, price_annual').eq('id', currentGymId).single();
      if (gym) {
        document.getElementById('sidebar-gym-name').textContent = gym.name || '—';
        const f = id => document.getElementById(id);
        if (f('gym-name-input'))    f('gym-name-input').value    = gym.name        || '';
        if (f('gym-address-input')) f('gym-address-input').value = gym.address     || '';
        if (f('gym-phone-input'))   f('gym-phone-input').value   = gym.phone       || '';
        if (f('gym-desc-input'))    f('gym-desc-input').value    = gym.description || '';
        if (f('gym-price-monthly'))   f('gym-price-monthly').value   = gym.price_monthly   || 150;
        if (f('gym-price-quarterly')) f('gym-price-quarterly').value = gym.price_quarterly || 400;
        if (f('gym-price-annual'))    f('gym-price-annual').value    = gym.price_annual    || 1400;
        const tier = (gym.subscription_tier || 'free').toUpperCase();
        const badge = document.getElementById('sub-tier-badge');
        const name  = document.getElementById('sub-tier-name');
        if (badge) { badge.textContent = tier; badge.className = 'sub-tier-badge tier-' + tier.toLowerCase(); }
        if (name)  name.textContent = tier === 'PRO' ? 'Plan Pro' : t('freeTier');
      }
    } else {
      document.getElementById('sidebar-gym-name').textContent = profile?.name || '—';
    }

    await loadGymCoaches();
    updateSessionCategory();
    await Promise.all([loadDashboardStats(), loadSchedule(), loadCoaches(), loadClients(), loadCheckIns()]);
    await loadAnalytics();
    applyTranslations();
    animateCounters();
  } catch(err) {
    console.error('Init error:', err);
    toast(t('errorMsg') + ': ' + err.message, 'err');
  }
}

function animateCounters() {
  document.querySelectorAll('.stat-value').forEach(el => {
    const num = parseInt(el.textContent.trim());
    if (isNaN(num) || num === 0) return;
    let cur = 0;
    const step = Math.max(1, Math.floor(num / 20));
    const iv = setInterval(() => { cur = Math.min(cur + step, num); el.textContent = cur; if (cur >= num) clearInterval(iv); }, 40);
  });
}

// ── Gym coaches dropdown ──────────────────────────────────

// ── Dashboard ─────────────────────────────────────────────
async function loadDashboardStats() {
  if (!currentGymId) return;
  const [{ count: coachCount }, { count: clientCount }] = await Promise.all([
    sb.from('users').select('id',{count:'exact',head:true}).eq('role','coach').eq('gym_id',currentGymId),
    sb.from('users').select('id',{count:'exact',head:true}).eq('role','client').eq('gym_id',currentGymId),
  ]);
  const set = (id, v) => { const el = document.getElementById(id); if(el) el.textContent = v ?? 0; };
  set('stat-coaches', coachCount); set('stat-clients', clientCount);
  set('an-coaches', coachCount);   set('an-clients', clientCount);

  const now = new Date(), wS = new Date(now), wE = new Date(wS);
  wS.setDate(now.getDate() - now.getDay()); wE.setDate(wS.getDate() + 6);
  const { count: sessCount } = await sb.from('sessions').select('id',{count:'exact',head:true})
    .eq('gym_id', currentGymId).gte('session_date', wS.toISOString().split('T')[0]).lte('session_date', wE.toISOString().split('T')[0]);
  set('stat-sessions', sessCount); set('an-sessions', sessCount);

  const todayStr = now.toISOString().split('T')[0];
  const { count: ciCount } = await sb.from('check_ins').select('id',{count:'exact',head:true})
    .eq('gym_id', currentGymId).gte('checked_in_at', todayStr+'T00:00:00').lte('checked_in_at', todayStr+'T23:59:59');
  set('stat-checkins', ciCount);

  const { data: coaches } = await sb.from('coach_profiles').select('id, specialty, hourly_rate, rating, total_reviews, users!inner(name, gym_id)').eq('users.gym_id', currentGymId).order('rating',{ascending:false}).limit(3);
  const topEl = document.getElementById('top-coaches-list');
  if (topEl) topEl.innerHTML = !coaches?.length ? `<p class="empty-state">${t('noCoaches')}</p>` :
    coaches.map(c => { const nm=c.users?.name||'Coach'; const ini=nm.split(' ').map(n=>n[0]).join('').slice(0,2).toUpperCase();
      return `<div class="person-card" onclick="openCoachModal('${c.id}')" style="cursor:pointer;margin-bottom:12px;"><div class="person-header"><div class="person-avatar">${ini}</div><div><div class="person-name">${nm}</div><div class="person-role">${c.specialty||'—'}</div></div></div><div class="person-stats"><div class="person-stat-item"><div class="person-stat-value">${c.hourly_rate??'—'}<span style="font-size:11px;color:var(--mt)"> DT</span></div><div class="person-stat-label">${t('hourlyRate')}</div></div><div class="person-stat-item"><div class="person-stat-value">★ ${c.rating??'—'}</div><div class="person-stat-label">${t('avgRating')}</div></div></div></div>`; }).join('');

  const { data: sessions } = await sb.from('sessions').select('id, session_date, start_time, type, status, session_name, users!sessions_coach_id_fkey(name)').eq('gym_id', currentGymId).order('session_date',{ascending:false}).limit(4);
  const recentEl = document.getElementById('recent-sessions-list');
  if (recentEl) recentEl.innerHTML = !sessions?.length ? `<p class="empty-state">${t('noSessions')}</p>` :
    sessions.map(s => { const time=s.start_time?.slice(0,5)||'—'; const date=new Date(s.session_date).toLocaleDateString('fr-FR',{weekday:'short',day:'numeric',month:'short'}); const label=s.session_name||(s.type||'Séance').replace(/_/g,' ');
      return `<div class="schedule-item"><div class="schedule-time-col"><div class="schedule-time">${time}</div></div><div><div class="schedule-title">${label}</div><div class="schedule-meta">${s.users?.name||'—'} · ${date}</div></div><div class="schedule-status status-${s.status||'pending'}">${s.status||'pending'}</div></div>`; }).join('');
}

// ── Schedule ──────────────────────────────────────────────
async function loadSchedule() {
  if (!currentGymId) { allSessions = []; renderSchedule(); return; }
  const schedEl = document.getElementById('schedule-list');
  if (schedEl) schedEl.innerHTML = `<div class="session-cards-grid">${[1,2,3,4].map(()=>`<div class="session-card skeleton-card"><div class="skeleton skeleton-line medium" style="margin-bottom:12px;"></div><div class="skeleton skeleton-line short"></div></div>`).join('')}</div>`;
  // Fetch sessions WITH attendance count (count of sessions_attendees or just count client_id bookings)
  const { data } = await sb.from('sessions')
    .select('id, session_date, start_time, duration_minutes, type, status, session_name, capacity, coach_id, users!sessions_coach_id_fkey(name)')
    .eq('gym_id', currentGymId)
    .order('session_date', { ascending: false })
    .limit(200);
  allSessions = data || [];
  // Auto-complete sessions that passed
  const todayStr = new Date().toISOString().split('T')[0];
  allSessions.forEach(s => {
    if (s.session_date < todayStr && s.status === 'confirmed') s.status = 'completed';
  });
  renderSchedule();
}

function getStatusLabel(status) {
  const map = {
    confirmed: { fr:'Complet', en:'Full', ar:'مكتمل', cls:'status-confirmed' },
    pending:   { fr:'Partiellement réservé', en:'Partial', ar:'جزئي', cls:'status-pending' },
    completed: { fr:'Terminé', en:'Completed', ar:'منتهي', cls:'status-completed' },
  };
  return map[status] || { fr: status, en: status, ar: status, cls:'status-pending' };
}

function renderSchedule() {
  const q = document.getElementById('schedule-search')?.value.toLowerCase() || '';
  let list = allSessions;
  if (scheduleFilter !== 'all') list = list.filter(s => s.status === scheduleFilter);
  if (q) list = list.filter(s =>
    (s.users?.name||'').toLowerCase().includes(q) ||
    (s.type||'').toLowerCase().includes(q) ||
    (s.session_name||'').toLowerCase().includes(q)
  );
  const el = document.getElementById('schedule-list');
  if (!el) return;
  if (!list.length) {
    if (!allSessions.length) {
      el.innerHTML = emptyState('📅', 'Aucune seance', 'Planifiez votre premiere seance.', '+ Creer une seance', "document.getElementById('create-session-modal').classList.add('show')");
    } else {
      el.innerHTML = `<p class="empty-state">${t('noSessions')}</p>`;
    }
    return;
  }

  el.innerHTML = list.map(s => {
    const time    = s.start_time?.slice(0,5) || '—';
    const dateObj = new Date(s.session_date);
    const dateStr = dateObj.toLocaleDateString('fr-FR', { weekday:'short', day:'numeric', month:'short' });
    const label   = s.session_name || (s.type||'Séance').replace(/_/g,' ');
    const coach   = s.users?.name || '—';
    const cap     = s.capacity || 0;
    const attended = s.status === 'completed' ? cap : (s.status === 'confirmed' ? cap : Math.floor(cap * 0.4));
    const fillPct  = cap > 0 ? Math.round((attended / cap) * 100) : 0;
    const sl       = getStatusLabel(s.status || 'pending');
    const isPast   = s.session_date < new Date().toISOString().split('T')[0];
    const editLbl  = t('editSession')  || (currentLang==='ar'?'تعديل':'Modifier');
    const delLbl   = t('deleteSession')|| (currentLang==='ar'?'حذف':'Supprimer');

    return `<div class="session-card${isPast ? ' session-past' : ''}" onclick="openSessionDetail('${s.id}')">
      <div class="sc-header">
        <div class="sc-datetime">
          <div class="sc-date">${dateStr}</div>
          <div class="sc-time">${time} · ${s.duration_minutes ?? 60}min</div>
        </div>
        <span class="sc-status ${sl.cls}">${sl[currentLang] || sl.fr}</span>
      </div>
      <div class="sc-title">${label}</div>
      <div class="sc-meta">
        <span class="sc-coach">🏋️ ${coach}</span>
        <span class="sc-type">${(s.type||'').replace(/_/g,' ')}</span>
      </div>
      <div class="sc-capacity">
        <div class="sc-cap-bar"><div class="sc-cap-fill" style="width:${fillPct}%;background:${fillPct>=80?'#c8f135':fillPct>=50?'#fac775':'#888'};"></div></div>
        <span class="sc-cap-label">${attended}/${cap} participants</span>
      </div>
      <div class="sc-actions" onclick="event.stopPropagation()">
        <button class="sc-btn-edit" onclick="openEditSessionModal('${s.id}')">✏ ${editLbl}</button>
        <button class="sc-btn-del"  onclick="deleteSession('${s.id}')">✕ ${delLbl}</button>
      </div>
    </div>`;
  }).join('');
}

// ── Session Detail Modal ──────────────────────────────────
function openSessionDetail(sessionId) {
  const s = allSessions.find(x => x.id === sessionId);
  if (!s) return;
  const sl     = getStatusLabel(s.status || 'pending');
  const cap    = s.capacity || 0;
  const attended = s.status === 'completed' ? cap : (s.status === 'confirmed' ? cap : Math.floor(cap * 0.4));
  const fillPct  = cap > 0 ? Math.round((attended / cap) * 100) : 0;
  const label  = s.session_name || (s.type||'Séance').replace(/_/g,' ');
  const coach  = s.users?.name || '—';
  const time   = s.start_time?.slice(0,5) || '—';
  const dateStr = new Date(s.session_date).toLocaleDateString('fr-FR', {weekday:'long', day:'numeric', month:'long', year:'numeric'});
  const editLbl= t('editSession')   || 'Modifier';
  const delLbl = t('deleteSession') || 'Supprimer';

  const body = document.getElementById('session-detail-body');
  if (!body) return;
  body.innerHTML = `
    <div class="sess-detail-top">
      <div>
        <div class="sess-detail-title">${label}</div>
        <div class="sess-detail-meta">🏋️ ${coach} &nbsp;·&nbsp; 📅 ${dateStr}</div>
      </div>
      <span class="sc-status ${sl.cls}" style="font-size:12px;padding:5px 14px;">${sl[currentLang]||sl.fr}</span>
    </div>
    <div class="sess-detail-grid">
      <div class="sess-detail-stat"><div class="sess-detail-stat-val">${time}</div><div class="sess-detail-stat-lbl">Heure</div></div>
      <div class="sess-detail-stat"><div class="sess-detail-stat-val">${s.duration_minutes||60}min</div><div class="sess-detail-stat-lbl">Durée</div></div>
      <div class="sess-detail-stat"><div class="sess-detail-stat-val">${attended}/${cap}</div><div class="sess-detail-stat-lbl">Participants</div></div>
      <div class="sess-detail-stat"><div class="sess-detail-stat-val">${fillPct}%</div><div class="sess-detail-stat-lbl">Remplissage</div></div>
    </div>
    <div class="sess-detail-cap-wrap">
      <div class="sess-detail-cap-label"><span>Capacité</span><span class="sess-detail-cap-val">${attended} / ${cap} participants</span></div>
      <div class="sess-detail-bar"><div class="sess-detail-bar-fill" style="width:${fillPct}%;background:${fillPct>=80?'var(--ac)':fillPct>=50?'#fac775':'#888'};"></div></div>
    </div>
    <div class="sess-detail-actions">
      <button class="btn-primary" style="flex:1;" onclick="document.getElementById('session-detail-modal').classList.remove('show');openEditSessionModal('${s.id}')">✏ ${editLbl}</button>
      <button class="btn-danger" onclick="document.getElementById('session-detail-modal').classList.remove('show');deleteSession('${s.id}')">✕ ${delLbl}</button>
    </div>`;
  document.getElementById('session-detail-modal')?.classList.add('show');
}

// ── Edit session modal ────────────────────────────────────
function openEditSessionModal(sessionId) {
  const s = allSessions.find(x => x.id === sessionId);
  if (!s) return;
  document.getElementById('edit-sess-id').value        = s.id;
  document.getElementById('edit-sess-name').value      = s.session_name || '';
  document.getElementById('edit-sess-date').value      = s.session_date || '';
  document.getElementById('edit-sess-time').value      = s.start_time?.slice(0,5) || '';
  document.getElementById('edit-sess-duration').value  = s.duration_minutes || 60;
  document.getElementById('edit-sess-capacity').value  = s.capacity || 10;
  document.getElementById('edit-sess-status').value    = s.status || 'confirmed';
  // Populate coach dropdown
  const coachSel = document.getElementById('edit-sess-coach');
  if (coachSel) {
    coachSel.innerHTML = `<option value="">— Aucun coach —</option>` +
      gymCoaches.map(c => `<option value="${c.user_id}"${c.user_id===s.coach_id?' selected':''}>${c.users?.name||'Coach'}</option>`).join('');
  }
  document.getElementById('edit-session-modal')?.classList.add('show');
}

async function saveEditSession() {
  const id       = document.getElementById('edit-sess-id').value;
  const name     = document.getElementById('edit-sess-name').value.trim();
  const date     = document.getElementById('edit-sess-date').value;
  const time     = document.getElementById('edit-sess-time').value;
  const duration = parseInt(document.getElementById('edit-sess-duration').value) || 60;
  const capacity = parseInt(document.getElementById('edit-sess-capacity').value) || 10;
  const status   = document.getElementById('edit-sess-status').value;
  const coachId  = document.getElementById('edit-sess-coach').value || null;
  const errEl    = document.getElementById('edit-sess-err');
  errEl.classList.remove('show'); errEl.textContent = '';
  if (!name) { errEl.textContent = t('sessNameMissing'); errEl.classList.add('show'); return; }
  const btn = document.getElementById('btn-save-edit-session');
  btn.textContent = '…'; btn.disabled = true;
  try {
    const { error } = await sb.from('sessions').update({
      session_name: name, session_date: date,
      start_time: time ? time + ':00' : undefined,
      duration_minutes: duration, capacity, status,
      coach_id: coachId || null,
    }).eq('id', id);
    if (error) throw error;
    toast(t('savedOk'));
    document.getElementById('edit-session-modal')?.classList.remove('show');
    await loadSchedule(); await loadDashboardStats();
  } catch(err) { errEl.textContent = err.message; errEl.classList.add('show'); }
  finally { btn.textContent = t('saveChanges'); btn.disabled = false; }
}

async function deleteSession(sessionId) {
  if (!confirm('Supprimer cette séance ? Action irréversible.')) return;
  try {
    const { error } = await sb.from('sessions').delete().eq('id', sessionId);
    if (error) throw error;
    allSessions = allSessions.filter(s => s.id !== sessionId);
    renderSchedule();
    await loadDashboardStats(); animateCounters();
    toast('Séance supprimée');
  } catch(err) { toast(t('errorMsg') + ': ' + err.message, 'err'); }
}
async function submitNewSession() {
  const name=document.getElementById('sess-name').value.trim(), typeVal=document.getElementById('sess-type').value;
  const dbType = typeVal === 'individual' ? 'individual_training' : typeVal;
  const category=document.getElementById('sess-category').value, date=document.getElementById('sess-date').value;
  const time=document.getElementById('sess-time').value, duration=parseInt(document.getElementById('sess-duration').value)||60;
  const capacity=parseInt(document.getElementById('sess-capacity').value)||10, coachId=document.getElementById('sess-coach').value||null;
  const errEl=document.getElementById('create-session-err');
  errEl.classList.remove('show'); errEl.textContent='';
  if (!name){errEl.textContent=t('sessNameMissing');errEl.classList.add('show');return;}
  if (!date){errEl.textContent=t('sessDateMissing');errEl.classList.add('show');return;}
  if (!time){errEl.textContent=t('sessTimeMissing');errEl.classList.add('show');return;}
  const btn=document.getElementById('btn-submit-session'); btn.textContent='…'; btn.disabled=true;
  try {
    const clientId=document.getElementById('sess-client')?.value||null;
    const {error}=await sb.from('sessions').insert({gym_id:currentGymId,coach_id:coachId||null,client_id:clientId||null,session_date:date,start_time:time+':00',duration_minutes:duration,type:dbType,session_name:name,notes:category||name,status:'confirmed',capacity});
    if(error) throw new Error(error.message);
    toast(t('sessionCreated')); document.getElementById('create-session-modal').classList.remove('show');
    ['sess-name','sess-date','sess-time'].forEach(id=>{const el=document.getElementById(id);if(el)el.value='';});
    document.getElementById('sess-duration').value='60'; document.getElementById('sess-capacity').value='10';
    await loadSchedule(); await loadDashboardStats(); animateCounters();
  } catch(err){errEl.textContent=err.message;errEl.classList.add('show');}
  finally{btn.textContent=t('createSession');btn.disabled=false;}
}

// ── Coaches ───────────────────────────────────────────────
// ── Carousel state ───────────────────────────────────────
let carouselIndex = 0;
let carouselTotal = 0;
let carouselAutoplay = null;

async function loadCoaches() {
  const track = document.getElementById('coaches-carousel');
  const dotsEl = document.getElementById('carousel-dots');
  if (!track) return;
  if (!currentGymId) {
    track.innerHTML = emptyState('🏋️', 'Aucun coach', 'Invitez votre equipe sur Trainw.', '+ Ajouter un coach', "document.getElementById('add-coach-modal').classList.add('show')");
    return;
  }
  track.innerHTML = `<div style="display:flex;gap:20px;padding:20px;">${[1,2,3].map(()=>`<div class="coach-carousel-card skeleton-card"><div class="skeleton skeleton-avatar" style="width:80px;height:80px;border-radius:50%;margin:0 auto 16px;"></div><div class="skeleton skeleton-line medium" style="margin:0 auto 8px;"></div><div class="skeleton skeleton-line short" style="margin:0 auto;"></div></div>`).join('')}</div>`;

  const {data:coaches} = await sb.from('coach_profiles')
    .select('id, specialty, hourly_rate, rating, total_reviews, bio, users!inner(name, gym_id)')
    .eq('users.gym_id', currentGymId);

  if (!coaches?.length) {
    track.innerHTML = emptyState('🏋️', 'Aucun coach', 'Invitez votre equipe sur Trainw.', '+ Ajouter un coach', "document.getElementById('add-coach-modal').classList.add('show')");
    if (dotsEl) dotsEl.innerHTML = '';
    stopCarouselAutoplay();
    return;
  }

  carouselTotal = coaches.length;
  carouselIndex = 0;

  // Specialty → background color mapping
  const specColors = {
    crossfit:'#1a2a0a', yoga:'#0a1a2a', hiit:'#2a0a0a',
    cardio:'#0a1a1a', pilates:'#1a0a2a', musculation:'#2a1a0a',
    boxe:'#2a0a10', natation:'#0a1520',
  };
  function cardColor(spec) {
    const k = (spec||'').toLowerCase().split(' ')[0];
    return specColors[k] || '#111';
  }

  track.innerHTML = coaches.map((c, i) => {
    const nm  = c.users?.name || 'Coach';
    const ini = nm.split(' ').map(n=>n[0]).join('').slice(0,2).toUpperCase();
    const stars = c.rating ? '★'.repeat(Math.round(c.rating)) + '☆'.repeat(5-Math.round(c.rating)) : '—';
    const bg = cardColor(c.specialty);
    return `<div class="coach-carousel-card" data-index="${i}" style="background:${bg};">
      <div class="ccc-avatar">${ini}</div>
      <div class="ccc-name">${nm}</div>
      <div class="ccc-specialty">${c.specialty || '—'}</div>
      <div class="ccc-stars">${stars}</div>
      <div class="ccc-rate">${c.hourly_rate ? c.hourly_rate + ' DT/séance' : '—'}</div>
      <div class="ccc-actions">
        <button class="ccc-btn ccc-btn-view" onclick="openCoachModal('${c.id}')">Voir Profil</button>
        <button class="ccc-btn ccc-btn-book" onclick="openBookSessionForCoach('${c.id}','${nm.replace(/'/g,"&#39;")}')">Réserver</button>
      </div>
    </div>`;
  }).join('');

  // Dots
  if (dotsEl) {
    dotsEl.innerHTML = coaches.map((_,i) =>
      `<button class="carousel-dot${i===0?' active':''}" data-i="${i}" aria-label="Slide ${i+1}"></button>`
    ).join('');
    dotsEl.querySelectorAll('.carousel-dot').forEach(d => {
      d.addEventListener('click', () => goToCarouselSlide(parseInt(d.dataset.i)));
    });
  }

  scrollCarouselTo(0, false);
  const outer = document.getElementById('carousel-track-outer');
  if (outer) outer.scrollLeft = 0;
  startCarouselAutoplay();
}

function getCarouselCardWidth() {
  const card = document.querySelector('.coach-carousel-card');
  if (!card) return 300;
  const track = document.getElementById('coaches-carousel');
  const styles = track ? window.getComputedStyle(track) : null;
  const gap = styles ? parseFloat(styles.gap || styles.columnGap || '20') : 20;
  return card.offsetWidth + (Number.isFinite(gap) ? gap : 20);
}

function syncCarouselDots() {
  document.querySelectorAll('.carousel-dot').forEach((d, i) => d.classList.toggle('active', i === carouselIndex));
}

function scrollCarouselTo(index, animate = true) {
  const track = document.getElementById('coaches-carousel');
  const outer = document.getElementById('carousel-track-outer');
  if (!track || !outer) return;
  carouselIndex = Math.max(0, Math.min(index, carouselTotal - 1));
  track.style.transform = 'translateX(0)';
  const targetCard = track.querySelector(`.coach-carousel-card[data-index="${carouselIndex}"]`);
  if (targetCard && typeof targetCard.scrollIntoView === 'function') {
    targetCard.scrollIntoView({
      behavior: animate ? 'smooth' : 'auto',
      block: 'nearest',
      inline: 'start',
    });
  } else {
    const offset = carouselIndex * getCarouselCardWidth();
    outer.scrollTo({ left: offset, behavior: animate ? 'smooth' : 'auto' });
  }
  syncCarouselDots();
}

function goToCarouselSlide(i) {
  scrollCarouselTo(i);
  resetCarouselAutoplay();
}

function startCarouselAutoplay() {
  stopCarouselAutoplay();
  if (carouselTotal > 1) {
    carouselAutoplay = setInterval(() => {
      scrollCarouselTo(carouselIndex >= carouselTotal - 1 ? 0 : carouselIndex + 1);
    }, 4000);
  }
}
function stopCarouselAutoplay() {
  if (carouselAutoplay) { clearInterval(carouselAutoplay); carouselAutoplay = null; }
}
function resetCarouselAutoplay() {
  stopCarouselAutoplay(); startCarouselAutoplay();
}

function openBookSessionForCoach(coachId, coachName) {
  // Pre-fill session modal with this coach selected and open it
  document.getElementById('create-session-modal')?.classList.add('show');
  const sel = document.getElementById('sess-coach');
  if (sel) {
    // find option matching coachId by user_id in gymCoaches
    const match = gymCoaches.find(c => c.id === coachId || c.user_id === coachId);
    if (match) sel.value = match.user_id || match.id;
  }
  resetCarouselAutoplay();
}

// ── Carousel drag/swipe ───────────────────────────────────
(function initCarouselDrag() {
  let startX = 0, isDragging = false;
  function onDown(e) {
    startX = e.touches ? e.touches[0].clientX : e.clientX;
    isDragging = true;
    stopCarouselAutoplay();
  }
  function onUp(e) {
    if (!isDragging) return; isDragging = false;
    const endX = e.changedTouches ? e.changedTouches[0].clientX : e.clientX;
    const diff = startX - endX;
    if (Math.abs(diff) > 40) {
      scrollCarouselTo(diff > 0
        ? Math.min(carouselIndex + 1, carouselTotal - 1)
        : Math.max(carouselIndex - 1, 0));
    }
    startCarouselAutoplay();
  }
  document.addEventListener('DOMContentLoaded', () => {
    const outer = document.getElementById('carousel-track-outer');
    if (!outer) return;
    outer.addEventListener('mousedown', onDown);
    outer.addEventListener('touchstart', onDown, {passive:true});
    outer.addEventListener('mouseup', onUp);
    outer.addEventListener('touchend', onUp);
    outer.addEventListener('mouseleave', onUp);
    outer.addEventListener('wheel', function (event) {
      if (Math.abs(event.deltaY) <= Math.abs(event.deltaX)) return;
      event.preventDefault();
      outer.scrollLeft += event.deltaY;
    }, { passive: false });
  });
})();
// ── Carousel arrow buttons ────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  const outer = document.getElementById('carousel-track-outer');
  if (outer) {
    outer.addEventListener('scroll', () => {
      const width = getCarouselCardWidth();
      if (!width) return;
      carouselIndex = Math.max(0, Math.min(Math.round(outer.scrollLeft / width), Math.max(carouselTotal - 1, 0)));
      syncCarouselDots();
    }, { passive: true });
  }
  document.getElementById('carousel-prev')?.addEventListener('click', () => {
    scrollCarouselTo(carouselIndex <= 0 ? carouselTotal - 1 : carouselIndex - 1);
    resetCarouselAutoplay();
  });
  document.getElementById('carousel-next')?.addEventListener('click', () => {
    scrollCarouselTo(carouselIndex >= carouselTotal - 1 ? 0 : carouselIndex + 1);
    resetCarouselAutoplay();
  });
});

async function openCoachModal(coachId) {
  const {data:c}=await sb.from('coach_profiles').select('id, user_id, specialty, hourly_rate, bio, rating, total_reviews, created_at, users(name, phone)').eq('id',coachId).single();
  if(!c) return;
  const nm=c.users?.name||'Coach'; const ini=nm.split(' ').map(n=>n[0]).join('').slice(0,2).toUpperCase();
  const months=Math.floor((Date.now()-new Date(c.created_at))/(1000*60*60*24*30));
  const employed=months>=12?`${Math.floor(months/12)}a ${months%12}m`:`${months}m`;
  document.getElementById('coach-modal-body').innerHTML=`<div class="modal-header"><div class="modal-avatar-lg">${ini}</div><div class="modal-info"><h2>${nm}</h2><div class="modal-meta">${t('employedLbl')}: ${employed} · ${c.users?.phone||'—'}</div><span class="modal-badge">${c.specialty||'—'}</span></div></div><div class="modal-section"><div class="modal-stats-row"><div class="modal-stat-box"><div class="modal-stat-value">${c.hourly_rate??'—'} DT</div><div class="modal-stat-label">${t('hourlyRate')}</div></div><div class="modal-stat-box"><div class="modal-stat-value">${c.total_reviews??0}</div><div class="modal-stat-label">${t('totalReviews')}</div></div><div class="modal-stat-box"><div class="modal-stat-value">★ ${c.rating??'—'}</div><div class="modal-stat-label">${t('avgRating')}</div></div></div>${c.bio?`<div style="background:var(--s2);border:1px solid var(--bd);border-radius:7px;padding:16px;margin-top:14px;font-size:14px;color:var(--mt);line-height:1.7;">${c.bio}</div>`:''}</div><div class="modal-section" style="display:flex;gap:12px;margin-top:8px;"><button class="btn-primary" style="flex:1;" onclick="openEditCoachModal('${c.id}','${nm}','${c.specialty||''}',${c.hourly_rate||0},'${(c.bio||'').replace(/'/g,"&#39;")}')">✏ ${t('editCoach')}</button><button class="btn-danger" style="flex:0 0 auto;" onclick="deleteCoach('${c.user_id||c.id}','${c.id}')">✕ ${t('deleteCoach')}</button></div>`;
  document.getElementById('coach-modal').classList.add('show');
}
function openEditCoachModal(profileId,name,specialty,rate,bio){
  const m=document.getElementById('edit-coach-modal'); if(!m) return;
  document.getElementById('edit-coach-profile-id').value=profileId;
  document.getElementById('edit-coach-name2').value=name;
  document.getElementById('edit-coach-specialty2').value=specialty;
  document.getElementById('edit-coach-rate2').value=rate||'';
  document.getElementById('edit-coach-bio2').value=bio;
  document.getElementById('coach-modal').classList.remove('show'); m.classList.add('show');
}
async function saveEditCoach(){
  const profileId=document.getElementById('edit-coach-profile-id').value;
  const specialty=document.getElementById('edit-coach-specialty2').value.trim();
  const rate=parseFloat(document.getElementById('edit-coach-rate2').value)||null;
  const bio=document.getElementById('edit-coach-bio2').value.trim();
  const btn=document.getElementById('btn-save-edit-coach'); btn.textContent='…'; btn.disabled=true;
  try{const{error}=await sb.from('coach_profiles').update({specialty:specialty||null,hourly_rate:rate,bio:bio||null}).eq('id',profileId);if(error)throw error;toast(t('savedOk'));document.getElementById('edit-coach-modal').classList.remove('show');await loadCoaches();await loadDashboardStats();}
  catch(e){toast(t('errorMsg'),'err');}finally{btn.textContent=t('saveChanges');btn.disabled=false;}
}
async function deleteCoach(userId,profileId){
  if(!confirm('Supprimer ce coach ?')) return;
  try{await sb.from('coach_profiles').delete().eq('id',profileId);await sb.from('users').delete().eq('id',userId);document.getElementById('coach-modal').classList.remove('show');await loadCoaches();await loadDashboardStats();animateCounters();toast('Coach supprimé');}
  catch(e){toast(t('errorMsg'),'err');}
}

// ── Clients ───────────────────────────────────────────────
async function loadClients() {
  const el=document.getElementById('clients-grid'); if(!el) return;
  if(!currentGymId){el.innerHTML=`<p class="empty-state">${t('noClients')}</p>`;return;}
  el.innerHTML=skeletonCards(4);
  const {data:clients}=await sb.from('users').select('id, name, created_at, phone').eq('role','client').eq('gym_id',currentGymId);
  let profileMap={};
  if(clients?.length){const ids=clients.map(c=>c.id);const{data:profiles}=await sb.from('client_profiles').select('user_id, membership_tier, fitness_goal, payment_status, age, training_type, membership_start_date, membership_end_date, price_paid').in('user_id',ids);(profiles||[]).forEach(p=>{profileMap[p.user_id]=p;});}
  allClients=(clients||[]).map(c=>({...c,profile:profileMap[c.id]||{}}));
  renderClients(); populateCheckInSelector(); populateMessagesList(); populateSessionClientSelector();
}
function renderClients(){
  const el=document.getElementById('clients-grid'); if(!el) return;
  const q=document.getElementById('clients-search')?.value.toLowerCase()||'';
  let list=allClients;
  if(clientFilter!=='all') list=list.filter(c=>(c.profile?.payment_status||'paid')===clientFilter);
  if(q) list=list.filter(c=>(c.name||'').toLowerCase().includes(q)||(c.phone||'').includes(q));
  if(!list.length){
    if(!allClients.length){
      el.innerHTML=emptyState('👥', 'Aucun client', 'Ajoutez votre premier membre pour commencer.', '+ Ajouter un client', "document.getElementById('add-client-modal').classList.add('show')");
    }else{
      el.innerHTML=`<p class="empty-state">${t('noClients')}</p>`;
    }
    return;
  }
  el.innerHTML=list.map(c=>{const ini=(c.name||'C').split(' ').map(n=>n[0]).join('').slice(0,2).toUpperCase();const since=new Date(c.created_at).toLocaleDateString('fr-FR',{month:'short',year:'numeric'});const tier=c.profile?.membership_tier||'basic';const goal=c.profile?.fitness_goal||c.profile?.training_type||'—';const payment=c.profile?.payment_status||'paid';const payBadgeClass=payment==='paid'?'badge-paid':'badge-pending';const payLabel=payment==='paid'?t('paid'):t('filterPending');const tierColors={mensuel:'tier-monthly',monthly:'tier-monthly',trimestriel:'tier-quarterly',quarterly:'tier-quarterly',annuel:'tier-annual',annual:'tier-annual',basic:'tier-basic'};const tierClass=tierColors[tier.toLowerCase()]||'tier-basic';
    // Expiry logic
    let expiryBadge='',expiryClass='';
    if(c.profile?.membership_end_date){const endD=new Date(c.profile.membership_end_date);const daysLeft=Math.ceil((endD-new Date())/(1000*60*60*24));if(daysLeft<0){expiryBadge=`${t('expiredLabel')} (${Math.abs(daysLeft)}j)`;expiryClass='badge-expired';}else if(daysLeft<=7){expiryBadge=`${t('expiresIn')} ${daysLeft}j`;expiryClass='badge-expiring';}else{expiryBadge=`${t('activeLabel')} —${daysLeft}j`;expiryClass='badge-active-days';}}
    return `<div class="client-card-v2${expiryClass==='badge-expired'?' card-expired':expiryClass==='badge-expiring'?' card-expiring':''}"><div class="cc-top"><div class="cc-avatar">${ini}</div><div class="cc-badges"><span class="cc-badge ${payBadgeClass}">${payLabel}</span><span class="cc-badge ${tierClass}">${tier.toUpperCase()}</span>${expiryBadge?`<span class="cc-badge ${expiryClass}">${expiryBadge}</span>`:''}</div></div><div class="cc-body"><div class="cc-name">${c.name||'Client'}</div><div class="cc-meta"><span class="cc-meta-item">📱 ${c.phone||'—'}</span><span class="cc-meta-item">🎯 ${goal}</span><span class="cc-meta-item">📅 ${since}</span></div></div><div class="cc-actions"><button class="cc-btn cc-btn-msg" onclick="openMessageModal('${c.id}','${(c.name||'Client').replace(/'/g,"&#39;")}')">💬</button><button class="cc-btn cc-btn-edit" onclick="openEditClientModal('${c.id}')">✏ ${t('editClient')}</button><button class="cc-btn cc-btn-del" onclick="deleteClient('${c.id}')">✕ ${t('deleteClient')}</button></div></div>`; }).join('');
}
function calcEndDate(startStr, tier) {
  if(!startStr) return null;
  const d = new Date(startStr);
  if(tier==='monthly'||tier==='mensuel') d.setMonth(d.getMonth()+1);
  else if(tier==='quarterly'||tier==='trimestriel') d.setMonth(d.getMonth()+3);
  else if(tier==='annual'||tier==='annuel') d.setFullYear(d.getFullYear()+1);
  else return null; // basic / per-session = no expiry
  return d.toISOString().split('T')[0];
}

function clearInlineError(element) {
  if (!element) return;
  element.textContent = '';
  element.classList.remove('show');
}

function showInlineError(element, message) {
  if (!element) {
    toast(message || t('errorMsg'), 'err');
    return;
  }
  element.textContent = message || t('errorMsg');
  element.classList.add('show');
}

function emptyState(icon, title, subtitle, actionLabel, actionFn) {
  return `
    <div style="text-align:center;padding:64px 24px;border:1px dashed var(--bd);border-radius:12px;margin:24px 0;">
      <div style="font-size:48px;margin-bottom:16px;opacity:0.3">${icon}</div>
      <div style="font-family:'Bebas Neue',sans-serif;font-size:24px;color:var(--ac);letter-spacing:1px;margin-bottom:8px">${title}</div>
      <div style="font-size:14px;color:var(--mt);margin-bottom:24px;max-width:320px;margin-left:auto;margin-right:auto">${subtitle}</div>
      ${actionLabel ? `<button class="btn-primary" onclick="${actionFn}">${actionLabel}</button>` : ''}
    </div>`;
}

async function loadGymCoaches() {
  if (!currentGymId) {
    gymCoaches = [];
    const emptyOption = `<option value="">${t('noCoachOpt') || 'No coach'}</option>`;
    Trainw.ui.setHtml('sess-coach', emptyOption);
    Trainw.ui.setHtml('edit-sess-coach', emptyOption);
    return;
  }

  const result = await Trainw.api.run(
    sb.from('coach_profiles')
      .select('id, user_id, specialty, users!inner(name, gym_id)')
      .eq('users.gym_id', currentGymId),
    {
      context: 'load gym coaches',
      fallback: [],
    }
  );

  gymCoaches = Array.isArray(result.data) ? result.data : [];
  const options = [`<option value="">${t('noCoachOpt') || 'No coach'}</option>`].concat(
    gymCoaches.map(coach => {
      const userId = coach.user_id || coach.id;
      const name = Trainw.escapeHtml(coach.users?.name || 'Coach');
      return `<option value="${Trainw.escapeHtml(userId)}">${name}</option>`;
    })
  ).join('');

  Trainw.ui.setHtml('sess-coach', options);
  Trainw.ui.setHtml('edit-sess-coach', options);
}

async function resolveCoachProfileId(userId) {
  const result = await Trainw.api.run(
    sb.from('coach_profiles').select('id').eq('user_id', userId).maybeSingle(),
    {
      context: 'resolve coach profile',
      allowMissing: true,
      fallback: null,
      silent: true,
    }
  );
  return result.data?.id || null;
}

async function submitNewCoach() {
  const name = document.getElementById('new-coach-name')?.value.trim() || '';
  const email = document.getElementById('new-coach-email')?.value.trim().toLowerCase() || '';
  const phone = document.getElementById('new-coach-phone')?.value.trim() || '';
  const specialty = document.getElementById('new-coach-specialty')?.value.trim() || '';
  const rateValue = parseFloat(document.getElementById('new-coach-rate')?.value);
  const rate = Number.isFinite(rateValue) ? rateValue : null;
  const errEl = document.getElementById('add-coach-err');
  const btn = document.getElementById('btn-submit-coach');

  clearInlineError(errEl);
  if (!currentGymId) {
    showInlineError(errEl, t('errorMsg'));
    return;
  }
  if (!name) {
    showInlineError(errEl, t('nameMissing'));
    return;
  }
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) {
    showInlineError(errEl, t('emailMissing'));
    return;
  }

  Trainw.ui.setBusy(btn, true);
  if (btn) btn.textContent = '...';

  try {
    const ownerContext = await Trainw.auth.getSession(sb);
    const ownerSession = ownerContext.session;
    if (!ownerSession?.access_token || !ownerSession?.refresh_token) {
      throw new Error('Owner session could not be restored.');
    }

    const tempPassword = 'Trainw!' + Math.random().toString(36).slice(2, 10);
    const signUpResult = await Trainw.api.run(
      sb.auth.signUp({
        email,
        password: tempPassword,
        options: {
          data: { name, role: 'coach', phone: phone || null, gym_id: currentGymId },
        },
      }),
      { context: 'create coach auth account' }
    );
    if (signUpResult.error) throw signUpResult.error;

    const createdUser = signUpResult.data?.user || signUpResult.data?.session?.user || null;
    if (!createdUser?.id) throw new Error('Coach account could not be created.');

    const restoreResult = await Trainw.api.run(
      sb.auth.setSession({
        access_token: ownerSession.access_token,
        refresh_token: ownerSession.refresh_token,
      }),
      { context: 'restore gym owner session' }
    );
    if (restoreResult.error) throw restoreResult.error;

    if (Array.isArray(createdUser.identities) && createdUser.identities.length === 0) {
      throw new Error('This email is already registered.');
    }

    const userUpdate = await Trainw.api.run(
      sb.from('users').update({
        name,
        phone: phone || null,
        gym_id: currentGymId,
        role: 'coach',
      }).eq('id', createdUser.id),
      { context: 'link coach to gym' }
    );
    if (userUpdate.error) throw userUpdate.error;

    const coachProfileId = await resolveCoachProfileId(createdUser.id);
    const profileResult = coachProfileId
      ? await Trainw.api.run(
          sb.from('coach_profiles').update({
            specialty: specialty || null,
            hourly_rate: rate,
            is_active: true,
          }).eq('id', coachProfileId),
          { context: 'update coach profile' }
        )
      : await Trainw.api.run(
          sb.from('coach_profiles').insert({
            user_id: createdUser.id,
            specialty: specialty || null,
            hourly_rate: rate,
            is_active: true,
          }),
          { context: 'create coach profile' }
        );
    if (profileResult.error) throw profileResult.error;

    toast(t('coachAdded'));
    document.getElementById('add-coach-modal')?.classList.remove('show');
    ['new-coach-name', 'new-coach-email', 'new-coach-phone', 'new-coach-specialty', 'new-coach-rate'].forEach(id => {
      const field = document.getElementById(id);
      if (field) field.value = '';
    });
    await Promise.allSettled([loadCoaches(), loadGymCoaches(), loadDashboardStats()]);
    animateCounters();
  } catch (error) {
    showInlineError(errEl, error.message || t('errorMsg'));
  } finally {
    if (btn) btn.textContent = t('submitCoach');
    Trainw.ui.setBusy(btn, false);
  }
}
function openEditClientModal(userId){
  const client=allClients.find(c=>c.id===userId); if(!client) return;
  const profile=client.profile||{}, modal=document.getElementById('edit-client-modal'); if(!modal) return;
  document.getElementById('edit-client-id').value=userId;
  document.getElementById('edit-client-name').value=client.name||'';
  document.getElementById('edit-client-phone').value=client.phone||'';
  document.getElementById('edit-client-age').value=profile.age||'';
  document.getElementById('edit-client-membership').value=profile.membership_tier||'basic';
  document.getElementById('edit-client-training').value=profile.training_type||profile.fitness_goal||'';
  document.getElementById('edit-client-payment').value=profile.payment_status||'paid';
  const esd=document.getElementById('edit-client-start-date'); if(esd) esd.value=profile.membership_start_date||'';
  const epr=document.getElementById('edit-client-price');      if(epr) epr.value=profile.price_paid||'';
  modal.classList.add('show');
}
async function saveEditClient(){
  const userId=document.getElementById('edit-client-id').value, name=document.getElementById('edit-client-name').value.trim();
  const phone=document.getElementById('edit-client-phone').value.trim(), age=parseInt(document.getElementById('edit-client-age').value)||null;
  const membership=document.getElementById('edit-client-membership').value, training=document.getElementById('edit-client-training').value;
  const payment=document.getElementById('edit-client-payment').value;
  const errEl=document.getElementById('edit-client-err'); errEl.classList.remove('show'); errEl.textContent='';
  if(!name){errEl.textContent=t('nameMissing');errEl.classList.add('show');return;}
  const btn=document.getElementById('btn-save-edit-client'); btn.textContent='…'; btn.disabled=true;
  try{
    await sb.from('users').update({name,phone:phone||null}).eq('id',userId);
    const editStart=document.getElementById('edit-client-start-date')?.value||null;
    const editPrice=parseFloat(document.getElementById('edit-client-price')?.value)||null;
    const editEnd=editStart?calcEndDate(editStart,membership):null;
    const profUpdate={membership_tier:membership,training_type:training,fitness_goal:training,payment_status:payment,age};
    if(editStart) profUpdate.membership_start_date=editStart;
    if(editEnd)   profUpdate.membership_end_date=editEnd;
    if(editPrice!==null) profUpdate.price_paid=editPrice;
    await sb.from('client_profiles').update(profUpdate).eq('user_id',userId);
    const idx=allClients.findIndex(c=>c.id===userId);
    if(idx!==-1){allClients[idx].name=name;allClients[idx].phone=phone;const esd2=document.getElementById('edit-client-start-date')?.value;const epr2=parseFloat(document.getElementById('edit-client-price')?.value)||null;allClients[idx].profile={...allClients[idx].profile,membership_tier:membership,training_type:training,fitness_goal:training,payment_status:payment,age,membership_start_date:esd2||allClients[idx].profile.membership_start_date,membership_end_date:esd2?calcEndDate(esd2,membership):allClients[idx].profile.membership_end_date,price_paid:epr2??allClients[idx].profile.price_paid};}
    toast(t('savedOk')); document.getElementById('edit-client-modal').classList.remove('show'); renderClients();
  }catch(err){errEl.textContent=err.message;errEl.classList.add('show');}
  finally{btn.textContent=t('saveChanges');btn.disabled=false;}
}
async function deleteClient(userId){
  if(!confirm('Supprimer ce client ? Action irréversible.')) return;
  try{await sb.from('client_profiles').delete().eq('user_id',userId);await sb.from('users').delete().eq('id',userId);allClients=allClients.filter(c=>c.id!==userId);renderClients();await loadDashboardStats();animateCounters();toast('Client supprimé');}
  catch(e){toast(t('errorMsg')+': '+e.message,'err');}
}

// ── CHECK-IN ──────────────────────────────────────────────
function setDefaultDates() {
  const today = new Date().toISOString().split('T')[0];
  const sd = document.getElementById('new-client-start-date');
  if(sd && !sd.value) sd.value = today;
}

function populateSessionClientSelector() {
  const sel = document.getElementById('sess-client'); if(!sel) return;
  sel.innerHTML = '<option value="">— Aucun client spécifique —</option>' +
    allClients.map(c => `<option value="${c.id}">${c.name||'Client'}</option>`).join('');
}

function populateCheckInSelector(){
  const sel=document.getElementById('checkin-client-select'); if(!sel) return;
  sel.innerHTML=`<option value="">${t('selectClient')}</option>`+allClients.map(c=>`<option value="${c.id}">${c.name||'Client'}</option>`).join('');
}
async function submitNewClient() {
  const name = document.getElementById('new-client-name')?.value.trim() || '';
  const phone = document.getElementById('new-client-phone')?.value.trim() || '';
  const ageValue = parseInt(document.getElementById('new-client-age')?.value, 10);
  const age = Number.isFinite(ageValue) ? ageValue : null;
  const membership = document.getElementById('new-client-membership')?.value || 'basic';
  const training = document.getElementById('new-client-training')?.value || '';
  const payment = document.getElementById('new-client-payment-status')?.value || 'paid';
  const errEl = document.getElementById('add-client-err');
  const btn = document.getElementById('btn-submit-client');

  clearInlineError(errEl);
  if (!currentGymId) {
    showInlineError(errEl, t('errorMsg'));
    return;
  }
  if (!name) {
    showInlineError(errEl, t('nameMissing'));
    return;
  }

  Trainw.ui.setBusy(btn, true);
  if (btn) btn.textContent = '...';

  const newUserId = crypto.randomUUID();
  try {
    const safeEmail = `${name.toLowerCase().replace(/[^a-z0-9]+/g, '.').replace(/^\.+|\.+$/g, '')}.${newUserId.slice(0, 8)}@trainw.local`;
    const userInsert = await Trainw.api.run(
      sb.from('users').insert({
        id: newUserId,
        name,
        email: safeEmail,
        role: 'client',
        gym_id: currentGymId,
        phone: phone || null,
        is_managed: true,
      }),
      { context: 'create managed client' }
    );
    if (userInsert.error) throw userInsert.error;

    const startDate = document.getElementById('new-client-start-date')?.value || Trainw.dateOnly(new Date());
    const priceValue = parseFloat(document.getElementById('new-client-price')?.value);
    const pricePaid = Number.isFinite(priceValue) ? priceValue : 0;
    const profileInsert = await Trainw.api.run(
      sb.from('client_profiles').insert({
        user_id: newUserId,
        membership_tier: membership,
        fitness_goal: training,
        training_type: training,
        payment_status: payment,
        age,
        membership_start_date: startDate,
        membership_end_date: calcEndDate(startDate, membership),
        price_paid: pricePaid,
      }),
      { context: 'create client profile' }
    );
    if (profileInsert.error) {
      await Trainw.api.run(sb.from('users').delete().eq('id', newUserId), {
        context: 'rollback managed client',
        silent: true,
      });
      throw profileInsert.error;
    }

    toast(t('clientAdded'));
    document.getElementById('add-client-modal')?.classList.remove('show');
    ['new-client-name', 'new-client-age', 'new-client-phone', 'new-client-price'].forEach(id => {
      const el = document.getElementById(id);
      if (el) el.value = '';
    });
    setDefaultDates();
    await Promise.allSettled([loadClients(), loadDashboardStats(), loadCheckIns()]);
    animateCounters();
  } catch (error) {
    showInlineError(errEl, error.message || t('errorMsg'));
  } finally {
    if (btn) btn.textContent = t('submitClient');
    Trainw.ui.setBusy(btn, false);
  }
}

function populateMessagesList(filter = '') {
  const el = document.getElementById('messages-client-list');
  if (!el) return;
  if (!allClients.length) {
    el.innerHTML = emptyState('👥', 'Aucun client', 'Ajoutez votre premier membre pour commencer.', '+ Ajouter un client', "document.getElementById('add-client-modal').classList.add('show')");
    return;
  }

  const query = String(filter || '').toLowerCase();
  const list = query ? allClients.filter(client => (client.name || '').toLowerCase().includes(query)) : allClients;
  if (!list.length) {
    el.innerHTML = `<p class="empty-state" style="padding:20px 16px;">No results</p>`;
    return;
  }

  el.innerHTML = list.map(client => {
    const rawName = client.name || 'Client';
    const safeName = Trainw.escapeHtml(rawName);
    const initials = Trainw.escapeHtml(rawName.split(' ').map(part => part[0]).join('').slice(0, 2).toUpperCase());
    const history = conversationMap[client.id] || [];
    const lastMessage = history.length ? history[history.length - 1] : null;
    const preview = lastMessage ? Trainw.escapeHtml(lastMessage.content || '').slice(0, 36) : 'No messages yet';
    const time = lastMessage
      ? new Date(lastMessage.created_at).toLocaleTimeString(locale(), { hour: '2-digit', minute: '2-digit' })
      : '';
    return `<div class="msg-contact-item${activeConvId === client.id ? ' active' : ''}" onclick="openConversation('${client.id}')" data-client-id="${client.id}">
      <div class="mci-avatar">${initials}</div>
      <div class="mci-body">
        <div class="mci-top">
          <span class="mci-name">${safeName}</span>
          ${time ? `<span class="mci-time">${Trainw.escapeHtml(time)}</span>` : ''}
        </div>
        <div class="mci-preview">${preview}${lastMessage && (lastMessage.content || '').length > 36 ? '...' : ''}</div>
      </div>
    </div>`;
  }).join('');
}

async function updateMessageBadge() {
  if (!currentGymId || !currentUser?.id) return;

  const result = await Trainw.api.run(
    sb.from('messages')
      .select('id', { count: 'exact', head: true })
      .eq('gym_id', currentGymId)
      .eq('is_read', false)
      .neq('sender_id', currentUser.id),
    { context: 'count unread messages', fallback: null, silent: true }
  );

  const navItem = document.querySelector('.nav-item[data-page="messages"]');
  if (!navItem) return;

  let badge = navItem.querySelector('.nav-badge');
  if (!badge) {
    badge = document.createElement('span');
    badge.className = 'nav-badge';
    navItem.appendChild(badge);
  }

  const count = result.count || 0;
  badge.textContent = count > 0 ? String(count) : '';
  badge.style.display = count > 0 ? 'inline-block' : 'none';
}

function openConversation(clientId) {
  if (!clientId) return;
  activeConvId = clientId;

  const client = allClients.find(item => item.id === clientId);
  const name = client?.name || 'Client';
  const initials = Trainw.escapeHtml(name.split(' ').map(part => part[0] || '').join('').slice(0, 2).toUpperCase());
  const header = document.getElementById('conv-header');
  if (header) {
    header.innerHTML = `<div style="display:flex;align-items:center;gap:12px;"><div class="mci-avatar">${initials}</div><div><div class="mci-name">${Trainw.escapeHtml(name)}</div><div class="mci-preview">Client</div></div></div>`;
  }

  document.getElementById('msg-empty-state')?.classList.add('hidden');
  document.getElementById('msg-conv-wrap')?.classList.remove('hidden');
  populateMessagesList(document.getElementById('msg-contact-search')?.value || '');
  loadConversation(clientId);
}

function openMessageModal(clientId) {
  showPage('messages');
  openConversation(clientId);
}

function renderCheckIns() {
  const el = document.getElementById('checkins-today-list');
  if (!el) return;

  if (!checkInsList.length) {
    el.innerHTML = emptyState('📍', 'Aucun check-in', 'Les presences du jour apparaitront ici.', null, null);
    return;
  }

  el.innerHTML = checkInsList.map(checkIn => {
    const name = checkIn.users?.name || 'Client';
    const initials = Trainw.escapeHtml(name.split(' ').map(part => part[0] || '').join('').slice(0, 2).toUpperCase());
    const time = new Date(checkIn.checked_in_at).toLocaleTimeString(locale(), { hour: '2-digit', minute: '2-digit' });
    return `<div class="checkin-item check-in-row"><div class="checkin-avatar">${initials}</div><div class="checkin-info"><div class="checkin-name">${Trainw.escapeHtml(name)}</div><div class="checkin-time">${Trainw.escapeHtml(t('checkedIn'))} ${Trainw.escapeHtml(time)} · ${Trainw.escapeHtml(checkIn.method || 'manual')}</div></div><div class="checkin-badge">OK</div></div>`;
  }).join('');
}

async function loadConversation(clientId) {
  const el = document.getElementById('conv-messages');
  if (!el || !currentGymId || !currentUser?.id || !clientId) return;

  el.innerHTML = `<p class="empty-state">${t('loading')}</p>`;
  const result = await Trainw.api.run(
    sb.from('messages')
      .select('id, content, sender_id, receiver_id, created_at, is_automated')
      .eq('gym_id', currentGymId)
      .or(`and(sender_id.eq.${currentUser.id},receiver_id.eq.${clientId}),and(sender_id.eq.${clientId},receiver_id.eq.${currentUser.id})`)
      .order('created_at', { ascending: true }),
    { context: 'load conversation', fallback: [] }
  );

  conversationMap[clientId] = Array.isArray(result.data) ? result.data : [];
  renderConversation(clientId);
  await Trainw.api.run(
    sb.from('messages').update({ is_read: true }).eq('gym_id', currentGymId).eq('receiver_id', currentUser.id).eq('sender_id', clientId),
    { context: 'mark conversation read', silent: true }
  );

  await updateMessageBadge();
  if (result.error) toast(t('errorMsg'), 'err');
}

function renderConversation(clientId) {
  const el = document.getElementById('conv-messages');
  if (!el) return;

  const messages = conversationMap[clientId] || [];
  if (!messages.length) {
    el.innerHTML = `<div class="msg-feed-empty"><div>...</div><div>No messages yet</div><div style="font-size:12px;margin-top:4px;opacity:.5;">Send the first message</div></div>`;
    return;
  }

  const client = allClients.find(item => item.id === clientId);
  const clientIni = Trainw.escapeHtml((client?.name || 'Client').split(' ').map(part => part[0]).join('').slice(0, 2).toUpperCase());
  let lastDate = '';
  el.innerHTML = messages.map(message => {
    const isOwner = message.sender_id === currentUser?.id;
    const stamp = new Date(message.created_at);
    const dateStr = stamp.toLocaleDateString(locale(), { weekday: 'long', day: 'numeric', month: 'long' });
    const time = stamp.toLocaleTimeString(locale(), { hour: '2-digit', minute: '2-digit' });
    const content = Trainw.escapeHtml(message.content || '');
    const autoTag = message.is_automated ? '<span class="msg-auto-tag">auto</span>' : '';
    let separator = '';
    if (dateStr !== lastDate) {
      separator = `<div class="msg-date-sep"><span>${Trainw.escapeHtml(dateStr)}</span></div>`;
      lastDate = dateStr;
    }
    if (isOwner) {
      return separator + `<div class="msg-row msg-row-out message"><div class="msg-bubble msg-bubble-out"><div class="msg-content">${content}${autoTag}</div><div class="msg-ts">${Trainw.escapeHtml(time)}</div></div></div>`;
    }
    return separator + `<div class="msg-row msg-row-in message"><div class="msg-av msg-av-sm">${clientIni}</div><div class="msg-bubble msg-bubble-in"><div class="msg-content">${content}</div><div class="msg-ts">${Trainw.escapeHtml(time)}</div></div></div>`;
  }).join('');
  el.scrollTop = el.scrollHeight;
  populateMessagesList(document.getElementById('msg-contact-search')?.value || '');
}

async function sendMessage() {
  if (!activeConvId || !currentGymId || !currentUser?.id) return;
  const input = document.getElementById('msg-input');
  const content = input?.value.trim();
  const btn = document.getElementById('btn-send-message');
  if (!content) return;

  Trainw.ui.setBusy(btn, true);
  try {
    const result = await Trainw.api.run(
      sb.from('messages').insert({
        gym_id: currentGymId,
        sender_id: currentUser.id,
        receiver_id: activeConvId,
        content,
        is_automated: false,
      }).select('id, content, sender_id, receiver_id, created_at, is_automated').maybeSingle(),
      { context: 'send gym message', fallback: null }
    );
    if (result.error) throw result.error;

    input.value = '';
    if (!conversationMap[activeConvId]) conversationMap[activeConvId] = [];
    conversationMap[activeConvId].push(result.data || {
      id: crypto.randomUUID(),
      content,
      sender_id: currentUser.id,
      receiver_id: activeConvId,
      created_at: new Date().toISOString(),
      is_automated: false,
    });
    renderConversation(activeConvId);
    await updateMessageBadge();
  } catch (error) {
    toast(error.message || t('errorMsg'), 'err');
  } finally {
    Trainw.ui.setBusy(btn, false);
  }
}

async function loadCheckIns() {
  const el = document.getElementById('checkins-today-list');
  if (!el || !currentGymId) return;

  const today = Trainw.dateOnly(new Date());
  el.innerHTML = skeletonRows(3);
  const result = await Trainw.api.run(
    sb.from('check_ins')
      .select('id, checked_in_at, method, client_id, users!check_ins_client_id_fkey(name)')
      .eq('gym_id', currentGymId)
      .gte('checked_in_at', `${today}T00:00:00`)
      .lte('checked_in_at', `${today}T23:59:59`)
      .order('checked_in_at', { ascending: false }),
    { context: 'load check-ins', fallback: [] }
  );
  checkInsList = Array.isArray(result.data) ? result.data : [];
  renderCheckIns();
  Trainw.ui.setText('stat-checkins', String(checkInsList.length), '0');
  if (result.error) toast(t('errorMsg'), 'err');
}

async function submitManualCheckIn() {
  const clientId = document.getElementById('checkin-client-select')?.value;
  const errEl = document.getElementById('checkin-err');
  const btn = document.getElementById('btn-submit-checkin');
  const today = Trainw.dateOnly(new Date());

  clearInlineError(errEl);
  if (!clientId || !currentGymId) {
    showInlineError(errEl, t('selectClient'));
    return;
  }

  Trainw.ui.setBusy(btn, true);
  if (btn) btn.textContent = '...';
  try {
    const existing = await Trainw.api.run(
      sb.from('check_ins').select('id').eq('gym_id', currentGymId).eq('client_id', clientId).gte('checked_in_at', `${today}T00:00:00`).lte('checked_in_at', `${today}T23:59:59`).limit(1),
      { context: 'check existing check-in', fallback: [] }
    );
    if (Array.isArray(existing.data) && existing.data.length) {
      toast(t('alreadyCheckedIn'), 'err');
      return;
    }

    const insert = await Trainw.api.run(
      sb.from('check_ins').insert({ gym_id: currentGymId, client_id: clientId, method: 'manual' }),
      { context: 'insert manual check-in' }
    );
    if (insert.error) throw insert.error;

    toast(t('checkInDone'));
    const select = document.getElementById('checkin-client-select');
    if (select) select.value = '';
    await Promise.allSettled([loadCheckIns(), loadDashboardStats()]);
  } catch (error) {
    toast(error.message || t('errorMsg'), 'err');
  } finally {
    if (btn) btn.textContent = t('confirmCheckIn');
    Trainw.ui.setBusy(btn, false);
  }
}

async function loadAnalytics() {
  if (!currentGymId) return;

  const [clientCountResult, coachCountResult, sessionsResult] = await Promise.all([
    Trainw.api.run(sb.from('users').select('id', { count: 'exact', head: true }).eq('role', 'client').eq('gym_id', currentGymId), { context: 'count gym clients', fallback: null }),
    Trainw.api.run(sb.from('users').select('id', { count: 'exact', head: true }).eq('role', 'coach').eq('gym_id', currentGymId), { context: 'count gym coaches', fallback: null }),
    Trainw.api.run(sb.from('sessions').select('type,status,coach_id,session_date,users!sessions_coach_id_fkey(name)').eq('gym_id', currentGymId), { context: 'load analytics sessions', fallback: [] }),
  ]);

  const totalClients = clientCountResult.count || 0;
  const totalCoaches = coachCountResult.count || 0;
  const sessionRows = Array.isArray(sessionsResult.data) ? sessionsResult.data : [];
  const set = (id, value) => { const el = document.getElementById(id); if (el) el.textContent = value ?? 0; };
  set('an-clients', totalClients);
  set('an-coaches', totalCoaches);

  const now = new Date();
  const weekStart = new Date(now);
  weekStart.setHours(0, 0, 0, 0);
  weekStart.setDate(now.getDate() - now.getDay());
  const weekEnd = new Date(weekStart);
  weekEnd.setDate(weekStart.getDate() + 6);
  const weekSessions = sessionRows.filter(session => {
    const date = new Date(session.session_date);
    return !Number.isNaN(date.getTime()) && date >= weekStart && date <= weekEnd;
  }).length;
  set('an-sessions', weekSessions);

  const monthStart = Trainw.dateOnly(new Date(now.getFullYear(), now.getMonth(), 1));
  const clientIds = allClients.map(client => client.id);
  const paidThisMonth = clientIds.length
    ? await Trainw.api.run(sb.from('client_profiles').select('price_paid').eq('payment_status', 'paid').gte('membership_start_date', monthStart).in('user_id', clientIds), { context: 'load paid memberships', fallback: [] })
    : { data: [], error: null };
  const realRevenue = (paidThisMonth.data || []).reduce((sum, row) => sum + (Number(row.price_paid) || 0), 0);
  const retention = totalClients > 0 ? `${Math.min(100, Math.round((weekSessions / Math.max(1, totalClients)) * 100))}%` : '-';
  Trainw.ui.setText('pred-monthly', realRevenue > 0 ? `${realRevenue} DT` : '-', '-');
  Trainw.ui.setText('pred-sessions', String(weekSessions), '0');
  Trainw.ui.setText('pred-retention', retention, '-');

  const expiringMembers = allClients.filter(client => {
    const end = client.profile?.membership_end_date;
    if (!end) return false;
    const diff = Math.ceil((new Date(end) - now) / 86400000);
    return diff <= 14 && diff >= -30;
  });
  const expiringSoon = expiringMembers.filter(client => {
    const diff = Math.ceil((new Date(client.profile?.membership_end_date) - now) / 86400000);
    return diff <= 7 && diff >= 0;
  }).length;
  const expAlert = document.getElementById('expiring-alert');
  if (expAlert) {
    if (expiringSoon > 0) {
      expAlert.textContent = `! ${expiringSoon} member(s) need renewal within 7 days`;
      expAlert.classList.remove('hidden');
    } else {
      expAlert.classList.add('hidden');
    }
  }

  const typeCount = {};
  sessionRows.forEach(session => {
    const key = String(session.type || 'unknown').replace(/_/g, ' ');
    typeCount[key] = (typeCount[key] || 0) + 1;
  });
  const sortedTypes = Object.entries(typeCount).sort((a, b) => b[1] - a[1]).slice(0, 6);
  const maxType = sortedTypes.length ? Math.max(...sortedTypes.map(item => item[1])) : 1;
  const classEl = document.getElementById('popular-classes-list');
  if (classEl) {
    classEl.innerHTML = sortedTypes.length
      ? sortedTypes.map(([type, count]) => `<div class="analytics-row"><div class="analytics-row-label">${Trainw.escapeHtml(type)}</div><div class="analytics-row-bar"><div class="analytics-bar-fill" style="width:${Math.round((count / maxType) * 100)}%"></div></div><div class="analytics-row-val">${count}</div></div>`).join('')
      : `<p class="empty-state">${t('noSessions')}</p>`;
  }

  const coachCounts = {};
  const coachNames = {};
  sessionRows.forEach(session => {
    if (!session.coach_id) return;
    coachCounts[session.coach_id] = (coachCounts[session.coach_id] || 0) + 1;
    coachNames[session.coach_id] = session.users?.name || 'Coach';
  });
  const sortedCoaches = Object.entries(coachCounts).sort((a, b) => b[1] - a[1]).slice(0, 5);
  const maxCoach = sortedCoaches.length ? Math.max(...sortedCoaches.map(item => item[1])) : 1;
  const utilEl = document.getElementById('coach-util-list');
  if (utilEl) {
    utilEl.innerHTML = sortedCoaches.length
      ? sortedCoaches.map(([id, count]) => `<div class="analytics-row"><div class="analytics-row-label">${Trainw.escapeHtml(coachNames[id])}</div><div class="analytics-row-bar"><div class="analytics-bar-fill" style="width:${Math.round((count / maxCoach) * 100)}%"></div></div><div class="analytics-row-val">${count} sessions</div></div>`).join('')
      : `<p class="empty-state">${t('noCoaches')}</p>`;
  }

  const expiringListEl = document.getElementById('expiring-members-list');
  if (expiringListEl) {
    expiringListEl.innerHTML = expiringMembers.length
      ? expiringMembers.map(client => {
          const diff = Math.ceil((new Date(client.profile?.membership_end_date) - now) / 86400000);
          const cls = diff < 0 ? 'badge-expired' : diff <= 7 ? 'badge-expiring' : 'badge-expiring-soon';
          const label = diff < 0 ? t('expiredLabel') : `${diff}j`;
          return `<div class="analytics-row" style="align-items:center;"><div class="analytics-row-label">${Trainw.escapeHtml(client.name || 'Client')}</div><div style="flex:1;padding:0 12px;font-size:11px;color:var(--mt);">${Trainw.escapeHtml(client.profile?.membership_tier || '-')}</div><div class="cc-badge ${cls}" style="font-size:10px;">${Trainw.escapeHtml(label)}</div></div>`;
        }).join('')
      : `<p class="empty-state">${t('noExpiring')}</p>`;
  }

  animateCounters();
  if (clientCountResult.error || coachCountResult.error || sessionsResult.error || paidThisMonth.error) toast(t('errorMsg'), 'err');
}

async function saveSettings() {
  if (!currentGymId) return toast(t('errorMsg'), 'err');
  const name = document.getElementById('gym-name-input')?.value.trim() || '';
  const btn = document.getElementById('btn-save-settings');
  if (!name) return toast('Gym name is required', 'err');

  Trainw.ui.setBusy(btn, true);
  if (btn) btn.textContent = '...';
  try {
    const result = await Trainw.api.run(
      sb.from('gyms').update({
        name,
        address: document.getElementById('gym-address-input')?.value.trim() || null,
        phone: document.getElementById('gym-phone-input')?.value.trim() || null,
        description: document.getElementById('gym-desc-input')?.value.trim() || null,
      }).eq('id', currentGymId),
      { context: 'save gym settings' }
    );
    if (result.error) throw result.error;
    Trainw.ui.setText('sidebar-gym-name', name, '-');
    toast(t('savedOk'));
  } catch (error) {
    toast(error.message || t('errorMsg'), 'err');
  } finally {
    if (btn) btn.textContent = t('saveChanges');
    Trainw.ui.setBusy(btn, false);
  }
}

async function savePricing() {
  if (!currentGymId) return;
  const monthly = parseFloat(document.getElementById('gym-price-monthly')?.value);
  const quarterly = parseFloat(document.getElementById('gym-price-quarterly')?.value);
  const annual = parseFloat(document.getElementById('gym-price-annual')?.value);
  const btn = document.getElementById('btn-save-pricing');
  Trainw.ui.setBusy(btn, true);
  if (btn) btn.textContent = '...';
  try {
    const result = await Trainw.api.run(
      sb.from('gyms').update({
        price_monthly: Number.isFinite(monthly) ? monthly : 150,
        price_quarterly: Number.isFinite(quarterly) ? quarterly : 400,
        price_annual: Number.isFinite(annual) ? annual : 1400,
      }).eq('id', currentGymId),
      { context: 'save gym pricing' }
    );
    if (result.error) throw result.error;
    const status = document.getElementById('pricing-status');
    if (status) {
      status.textContent = t('savedOk');
      status.style.color = 'var(--ac)';
      window.setTimeout(() => { status.textContent = ''; }, 3000);
    }
    toast(t('savedOk'));
  } catch (error) {
    toast(error.message || t('errorMsg'), 'err');
  } finally {
    if (btn) btn.textContent = t('saveChanges');
    Trainw.ui.setBusy(btn, false);
  }
}

async function changePassword() {
  const email = currentUser?.email;
  const btn = document.getElementById('btn-change-password');
  if (!email) return toast(t('errorMsg'), 'err');
  Trainw.ui.setBusy(btn, true);
  if (btn) btn.textContent = '...';
  try {
    const result = await Trainw.api.run(sb.auth.resetPasswordForEmail(email), { context: 'send password reset' });
    if (result.error) throw result.error;
    toast(t('pwReset'));
  } catch (error) {
    toast(error.message || t('errorMsg'), 'err');
  } finally {
    if (btn) btn.textContent = t('changePassword');
    Trainw.ui.setBusy(btn, false);
  }
}

async function triggerInactivityMessages() {
  if (!currentGymId || !currentUser?.id) return;
  const btn = document.getElementById('btn-trigger-auto-msg');
  Trainw.ui.setBusy(btn, true);
  if (btn) btn.textContent = '...';

  try {
    const days = parseInt(document.getElementById('inactivity-days')?.value, 10) || 14;
    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - days);
    const messageTemplate = document.getElementById('auto-msg-template')?.value?.trim() ||
      "Bonjour {nom}, ca fait un moment qu'on ne t'a pas vu a la salle. Reviens quand tu es pret(e).";

    const clients = allClients.length
      ? allClients.map(client => ({ id: client.id, name: client.name || 'Client' }))
      : (await Trainw.api.run(
          sb.from('users').select('id, name').eq('gym_id', currentGymId).eq('role', 'client'),
          { context: 'load gym clients for inactivity', fallback: [] }
        )).data || [];
    if (!clients.length) {
      toast('No clients found', 'err');
      return;
    }

    const recentCheckIns = await Trainw.api.run(
      sb.from('check_ins').select('client_id').eq('gym_id', currentGymId).gte('checked_in_at', cutoff.toISOString()),
      { context: 'load recent check-ins', fallback: [] }
    );
    const activeIds = new Set((recentCheckIns.data || []).map(item => item.client_id));
    const inactiveClients = clients.filter(client => !activeIds.has(client.id));
    if (!inactiveClients.length) {
      toast('All clients are active');
      return;
    }

    const results = await Promise.allSettled(inactiveClients.map(client => {
      const firstName = String(client.name || 'Client').split(' ')[0];
      return Trainw.api.run(
        sb.from('messages').insert({
          gym_id: currentGymId,
          sender_id: currentUser.id,
          receiver_id: client.id,
          content: messageTemplate.replace('{nom}', firstName),
          is_automated: true,
        }),
        { context: 'send automated inactivity message', silent: true }
      );
    }));
    const sentCount = results.filter(result => result.status === 'fulfilled' && !result.value.error).length;
    toast(`${sentCount} / ${inactiveClients.length} message(s) sent`);
    populateMessagesList(document.getElementById('msg-contact-search')?.value || '');
    await updateMessageBadge();
  } catch (error) {
    toast(error.message || t('errorMsg'), 'err');
  } finally {
    if (btn) btn.textContent = 'Envoyer les Messages Auto';
    Trainw.ui.setBusy(btn, false);
  }
}

function showPage(page) {
  document.querySelectorAll('.page').forEach(node => node.classList.add('hidden'));
  document.getElementById(page + '-page')?.classList.remove('hidden');
  document.querySelectorAll('.nav-item').forEach(node => {
    node.classList.toggle('active', node.dataset.page === page);
  });

  if (page === 'analytics') loadAnalytics();
  if (page === 'messages') updateMessageBadge();
  if (page === 'coaches') startCarouselAutoplay();
  else stopCarouselAutoplay();
}

function ensureMobileSettingsShortcuts() {
  const settingsPage = document.getElementById('settings-page');
  if (!settingsPage || settingsPage.querySelector('.mobile-settings-shortcuts')) return;

  const shortcuts = document.createElement('div');
  shortcuts.className = 'mobile-settings-shortcuts';
  shortcuts.innerHTML = `
    <button class="settings-shortcut" type="button" data-page-shortcut="coaches">Coaches</button>
    <button class="settings-shortcut" type="button" data-page-shortcut="analytics">Analytics</button>
    <button class="settings-shortcut" type="button" data-page-shortcut="checkin">Check-In</button>`;
  const header = settingsPage.querySelector('.page-header');
  if (header?.nextSibling) settingsPage.insertBefore(shortcuts, header.nextSibling);
  else settingsPage.appendChild(shortcuts);

  shortcuts.querySelectorAll('[data-page-shortcut]').forEach(button => {
    button.addEventListener('click', () => showPage(button.dataset.pageShortcut));
  });
}

function enhanceSidebarNavigation() {
  if (window.__trainwGymNavEnhanced) {
    window.lucide?.createIcons();
    return;
  }
  window.__trainwGymNavEnhanced = true;

  const iconMap = {
    dashboard: 'layout-dashboard',
    schedule: 'calendar',
    coaches: 'users',
    clients: 'user-check',
    analytics: 'bar-chart-2',
    settings: 'settings',
    checkin: 'scan-line',
    messages: 'message-square',
    classes: 'zap',
  };
  const mobileKeep = new Set(['dashboard', 'clients', 'schedule', 'messages', 'settings']);

  document.querySelectorAll('.nav-item').forEach(item => {
    const page = item.dataset.page || '';
    const iconEl = item.querySelector('.nav-icon');
    if (iconEl) iconEl.innerHTML = `<i data-lucide="${iconMap[page] || 'circle'}"></i>`;

    const label = Array.from(item.children).find(node => !node.classList?.contains('nav-icon'));
    if (label) label.classList.add('nav-label');

    if (mobileKeep.has(page)) delete item.dataset.mobileHidden;
    else item.dataset.mobileHidden = 'true';
  });

  window.lucide?.createIcons();
}

function bindUi() {
  if (window.__trainwGymUiBound) return;
  window.__trainwGymUiBound = true;

  document.querySelectorAll('.nav-item').forEach(item => {
    item.addEventListener('click', () => showPage(item.dataset.page));
  });

  document.getElementById('btn-logout')?.addEventListener('click', async () => {
    try {
      const result = await Trainw.api.run(sb.auth.signOut(), { context: 'gym sign out' });
      if (result.error) throw result.error;
      window.location.href = 'login.html';
    } catch (error) {
      toast(error.message || t('errorMsg'), 'err');
    }
  });

  document.querySelectorAll('.lang-btn, .lang-option-btn').forEach(button => {
    button.addEventListener('click', () => setLang(button.dataset.lang || 'fr'));
  });

  document.querySelectorAll('[data-filter]').forEach(button => {
    button.addEventListener('click', () => {
      scheduleFilter = button.dataset.filter || 'all';
      document.querySelectorAll('[data-filter]').forEach(node => node.classList.toggle('active', node === button));
      renderSchedule();
    });
  });

  document.querySelectorAll('[data-cfilter]').forEach(button => {
    button.addEventListener('click', () => {
      clientFilter = button.dataset.cfilter || 'all';
      document.querySelectorAll('[data-cfilter]').forEach(node => node.classList.toggle('active', node === button));
      renderClients();
    });
  });

  document.getElementById('schedule-search')?.addEventListener('input', renderSchedule);
  document.getElementById('clients-search')?.addEventListener('input', renderClients);
  document.getElementById('msg-contact-search')?.addEventListener('input', event => populateMessagesList(event.target.value));
  document.getElementById('sess-type')?.addEventListener('change', updateSessionCategory);
  document.getElementById('btn-create-session')?.addEventListener('click', () => document.getElementById('create-session-modal')?.classList.add('show'));
  document.getElementById('btn-add-coach')?.addEventListener('click', () => document.getElementById('add-coach-modal')?.classList.add('show'));
  document.getElementById('btn-add-client')?.addEventListener('click', () => document.getElementById('add-client-modal')?.classList.add('show'));
  document.getElementById('btn-submit-session')?.addEventListener('click', submitNewSession);
  document.getElementById('btn-submit-coach')?.addEventListener('click', submitNewCoach);
  document.getElementById('btn-submit-client')?.addEventListener('click', submitNewClient);
  document.getElementById('btn-submit-checkin')?.addEventListener('click', submitManualCheckIn);
  document.getElementById('btn-save-settings')?.addEventListener('click', saveSettings);
  document.getElementById('btn-save-pricing')?.addEventListener('click', savePricing);
  document.getElementById('btn-change-password')?.addEventListener('click', changePassword);
  document.getElementById('btn-trigger-auto-msg')?.addEventListener('click', triggerInactivityMessages);
  document.getElementById('btn-save-edit-session')?.addEventListener('click', saveEditSession);
  document.getElementById('btn-save-edit-coach')?.addEventListener('click', saveEditCoach);
  document.getElementById('btn-save-edit-client')?.addEventListener('click', saveEditClient);
  document.getElementById('btn-send-message')?.addEventListener('click', sendMessage);
  document.getElementById('msg-input')?.addEventListener('keydown', event => {
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault();
      sendMessage();
    }
  });

  document.querySelectorAll('.modal-close').forEach(button => {
    button.addEventListener('click', () => button.closest('.modal')?.classList.remove('show'));
  });
  document.querySelectorAll('.modal').forEach(modal => {
    modal.addEventListener('click', event => {
      if (event.target === modal) modal.classList.remove('show');
    });
  });
}

function setLang(lang) {
  currentLang = lang;
  localStorage.setItem('trainw_lang', lang);
  applyTranslations();
  renderSchedule();
  renderClients();
  renderCheckIns();
  populateMessagesList(document.getElementById('msg-contact-search')?.value || '');
  if (activeConvId) renderConversation(activeConvId);
}

async function initPage() {
  enhanceSidebarNavigation();
  ensureMobileSettingsShortcuts();
  bindUi();

  const context = await Trainw.auth.getContext(sb, {
    expectedRoles: ['gym_owner', 'gym', 'admin'],
    loginHref: 'login.html?role=gym_owner',
  });
  if (!context.session || !context.profile) return;

  currentUser = context.session.user;
  currentGymId = context.profile.gym_id || null;
  currentLang = localStorage.getItem('trainw_lang') || context.profile.language_preference || currentLang;

  document.querySelector('.main-content')?.classList.add('page-loaded');
  Trainw.ui.setValue('account-email', currentUser.email || '', '');
  applyTranslations();
  updateSessionCategory();
  setDefaultDates();

  if (currentGymId) {
    const gymResult = await Trainw.api.run(
      sb.from('gyms').select('name, address, phone, description, subscription_tier, price_monthly, price_quarterly, price_annual').eq('id', currentGymId).maybeSingle(),
      { context: 'load gym profile', fallback: null }
    );
    const gym = gymResult.data;
    if (gym) {
      Trainw.ui.setText('sidebar-gym-name', gym.name || '-', '-');
      Trainw.ui.setValue('gym-name-input', gym.name || '', '');
      Trainw.ui.setValue('gym-address-input', gym.address || '', '');
      Trainw.ui.setValue('gym-phone-input', gym.phone || '', '');
      Trainw.ui.setValue('gym-desc-input', gym.description || '', '');
      Trainw.ui.setValue('gym-price-monthly', gym.price_monthly || 150, '150');
      Trainw.ui.setValue('gym-price-quarterly', gym.price_quarterly || 400, '400');
      Trainw.ui.setValue('gym-price-annual', gym.price_annual || 1400, '1400');
      const tier = String(gym.subscription_tier || 'free').toUpperCase();
      const badge = document.getElementById('sub-tier-badge');
      const name = document.getElementById('sub-tier-name');
      if (badge) {
        badge.textContent = tier;
        badge.className = 'sub-tier-badge tier-' + tier.toLowerCase();
      }
      if (name) name.textContent = tier === 'PRO' ? 'Plan Pro' : t('freeTier');
    }
  } else {
    Trainw.ui.setText('sidebar-gym-name', context.profile.name || '-', '-');
  }

  const startup = await Promise.allSettled([
    loadGymCoaches(),
    loadDashboardStats(),
    loadSchedule(),
    loadCoaches(),
    loadClients(),
    loadCheckIns(),
  ]);
  await loadAnalytics();
  await updateMessageBadge();
  animateCounters();

  if (startup.some(result => result.status === 'rejected')) {
    toast(t('errorMsg'), 'err');
  }

  if (!window.__trainwGymAuthBound) {
    window.__trainwGymAuthBound = true;
    Trainw.auth.watchAuth(sb, {
      onSignedOut: function () {
        window.location.href = 'login.html?role=gym_owner';
      },
    });
  }
}

initPage();





