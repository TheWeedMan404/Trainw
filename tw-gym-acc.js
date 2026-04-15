// ── Config ────────────────────────────────────────────────
const Trainw = window.TrainwCore;
const sb = Trainw.createClient();
Trainw.installGlobalErrorHandlers();

const GYM_LOGIN_HREF = '/tw-login.html?role=gym_owner';

let currentUser    = null;
let currentGymId   = null;
let currentGymName = '';
let currentMembership = null;
let currentPermissions = [];
let currentLang    = localStorage.getItem('trainw_lang') || 'fr';
let scheduleFilter = 'all';
let clientFilter   = 'all';
let checkInTab     = 'live';
let allSessions    = [];
let allClients     = [];
let gymCoaches     = [];
let accessDirectory = [];
let roleMatrix = [];
let permissionCatalog = [];
let checkInsList   = [];
let memberCredentialsList = [];
let gateAccessLogList = [];
let selectedCredentialClientId = null;
let conversationMap = {};
let activeConvId    = null;
let gateCheckInChannel = null;
let gymMessageChannel = null;
let gymSessionChannel = null;
let gymCheckInChannel = null;
let gymGateAccessChannel = null;
let gymRefreshTimer = null;
let activeRoleBuilderId = null;
let staffDirectory = [];
let staffAvatarUrlMap = new Map();
let activeStaffRoleEditMembershipId = null;
let activeStaffPanelUserId = null;
let activeSettingsStaffTab = 'team';
let pendingStaffAvatarFile = null;
let pendingStaffAvatarObjectUrl = null;

const GYM_RUNTIME_LOCALE = {
  fr: {
    text: {
      'Bookings Overview': 'Vue des réservations',
      'Coach Approval': 'Validation des coachs',
      'Coach Approval Queue': "File d'approbation des coachs",
      'Vue Réservations': 'Vue des réservations',
      'Smart Analytics': 'Smart Analytics',
      'Tarifs de la Salle': 'Tarifs de la salle',
      'Ces tarifs seront utilisés pour le suivi des revenus et les rapports.': 'Ces tarifs sont utilisés pour le suivi des revenus et les rapports.',
      'Mensuel (DT)': 'Mensuel (DT)',
      'Trimestriel (DT)': 'Trimestriel (DT)',
      'Annuel (DT)': 'Annuel (DT)',
      'Enregistrer les Tarifs': 'Enregistrer les tarifs',
      'Manuel': 'Manuel',
      'Badges & Biométrie': 'Badges & biométrie',
      "Journal d'accès": "Journal d'accès",
      '50 derniers passages du terminal': '50 derniers passages du terminal',
      'Terminal': 'Terminal',
      'URL du terminal': 'URL du terminal',
      "Copier l'URL": "Copier l'URL",
      'Ouvrir le terminal': 'Ouvrir le terminal',
      'Nouveau badge': 'Nouveau badge',
      'Sélectionnez un client': 'Sélectionnez un client',
      'Identifiant matériel': 'Identifiant matériel',
      'RFID Card': 'Carte RFID',
      'Fingerprint': 'Empreinte',
      'Face': 'Visage',
      'Individual Training': 'Entraînement individuel',
      'Group Class': 'Cours collectif',
      'Group Activity': 'Activité de groupe',
      'Badge principal': 'Badge principal',
    },
    placeholders: {
      'UID / Template ID': 'UID / identifiant du modèle',
    },
  },
  en: {
    text: {
      'Vue des réservations': 'Bookings overview',
      'Vue Réservations': 'Bookings overview',
      'Bookings Overview': 'Bookings overview',
      'Validation des coachs': 'Coach approval',
      'Coach Approval': 'Coach approval',
      "File d'approbation des coachs": 'Coach approval queue',
      'Coach Approval Queue': 'Coach approval queue',
      'Prévision Intelligente': 'Smart analytics',
      'Smart Analytics': 'Smart analytics',
      'Tarifs de la salle': 'Gym pricing',
      'Tarifs de la Salle': 'Gym pricing',
      'Ces tarifs sont utilisés pour le suivi des revenus et les rapports.': 'These prices are used for revenue tracking and reporting.',
      'Ces tarifs seront utilisés pour le suivi des revenus et les rapports.': 'These prices are used for revenue tracking and reporting.',
      'Mensuel (DT)': 'Monthly (DT)',
      'Trimestriel (DT)': 'Quarterly (DT)',
      'Annuel (DT)': 'Annual (DT)',
      'Enregistrer les tarifs': 'Save pricing',
      'Enregistrer les Tarifs': 'Save pricing',
      'Manuel': 'Manual',
      'Badges & biométrie': 'Badges & biometrics',
      'Badges & Biométrie': 'Badges & biometrics',
      "Journal d'accès": 'Access log',
      '50 derniers passages du terminal': 'Last 50 terminal events',
      'Terminal': 'Terminal',
      'URL du terminal': 'Terminal URL',
      "Copier l'URL": 'Copy URL',
      'Ouvrir le terminal': 'Open terminal',
      'Nouveau badge': 'New credential',
      'Sélectionnez un client': 'Select a client',
      'Identifiant matériel': 'Hardware identifier',
      'Carte RFID': 'RFID card',
      'RFID Card': 'RFID card',
      'Empreinte': 'Fingerprint',
      'Fingerprint': 'Fingerprint',
      'Visage': 'Face',
      'Face': 'Face',
      'Entraînement individuel': 'Individual training',
      'Individual Training': 'Individual training',
      'Cours collectif': 'Group class',
      'Group Class': 'Group class',
      'Activité de groupe': 'Group activity',
      'Group Activity': 'Group activity',
      'Badge principal': 'Primary badge',
    },
    placeholders: {
      'UID / identifiant du modèle': 'UID / template ID',
      'UID / Template ID': 'UID / template ID',
      'Badge principal': 'Primary badge',
    },
  },
  ar: {
    text: {
      'Vue des réservations': 'نظرة على الحجوزات',
      'Vue Réservations': 'نظرة على الحجوزات',
      'Bookings overview': 'نظرة على الحجوزات',
      'Bookings Overview': 'نظرة على الحجوزات',
      'Validation des coachs': 'موافقة المدربين',
      'Coach approval': 'موافقة المدربين',
      'Coach Approval': 'موافقة المدربين',
      "File d'approbation des coachs": 'قائمة موافقات المدربين',
      'Coach approval queue': 'قائمة موافقات المدربين',
      'Coach Approval Queue': 'قائمة موافقات المدربين',
      'Prévision Intelligente': 'تحليلات ذكية',
      'Smart analytics': 'تحليلات ذكية',
      'Smart Analytics': 'تحليلات ذكية',
      'Tarifs de la salle': 'أسعار القاعة',
      'Tarifs de la Salle': 'أسعار القاعة',
      'Gym pricing': 'أسعار القاعة',
      'Ces tarifs sont utilisés pour le suivi des revenus et les rapports.': 'تُستخدم هذه الأسعار لمتابعة الإيرادات والتقارير.',
      'Ces tarifs seront utilisés pour le suivi des revenus et les rapports.': 'تُستخدم هذه الأسعار لمتابعة الإيرادات والتقارير.',
      'These prices are used for revenue tracking and reporting.': 'تُستخدم هذه الأسعار لمتابعة الإيرادات والتقارير.',
      'Mensuel (DT)': 'شهري (د.ت)',
      'Monthly (DT)': 'شهري (د.ت)',
      'Trimestriel (DT)': 'ربع سنوي (د.ت)',
      'Quarterly (DT)': 'ربع سنوي (د.ت)',
      'Annuel (DT)': 'سنوي (د.ت)',
      'Annual (DT)': 'سنوي (د.ت)',
      'Enregistrer les tarifs': 'حفظ الأسعار',
      'Enregistrer les Tarifs': 'حفظ الأسعار',
      'Save pricing': 'حفظ الأسعار',
      'Manuel': 'يدوي',
      'Manual': 'يدوي',
      'Badges & biométrie': 'البطاقات والقياسات الحيوية',
      'Badges & Biométrie': 'البطاقات والقياسات الحيوية',
      'Badges & biometrics': 'البطاقات والقياسات الحيوية',
      "Journal d'accès": 'سجل الدخول',
      'Access log': 'سجل الدخول',
      '50 derniers passages du terminal': 'آخر 50 محاولة على الطرفية',
      'Last 50 terminal events': 'آخر 50 محاولة على الطرفية',
      'Terminal': 'الطرفية',
      'URL du terminal': 'رابط الطرفية',
      'Terminal URL': 'رابط الطرفية',
      "Copier l'URL": 'نسخ الرابط',
      'Copy URL': 'نسخ الرابط',
      'Ouvrir le terminal': 'فتح الطرفية',
      'Open terminal': 'فتح الطرفية',
      'Nouveau badge': 'اعتماد جديد',
      'New credential': 'اعتماد جديد',
      'Sélectionnez un client': 'اختر عميلاً',
      'Select a client': 'اختر عميلاً',
      'Identifiant matériel': 'معرف الجهاز',
      'Hardware identifier': 'معرف الجهاز',
      'Carte RFID': 'بطاقة RFID',
      'RFID card': 'بطاقة RFID',
      'RFID Card': 'بطاقة RFID',
      'Empreinte': 'بصمة',
      'Fingerprint': 'بصمة',
      'Visage': 'الوجه',
      'Face': 'الوجه',
      'Entraînement individuel': 'تدريب فردي',
      'Individual training': 'تدريب فردي',
      'Individual Training': 'تدريب فردي',
      'Cours collectif': 'حصة جماعية',
      'Group class': 'حصة جماعية',
      'Group Class': 'حصة جماعية',
      'Activité de groupe': 'نشاط جماعي',
      'Group activity': 'نشاط جماعي',
      'Group Activity': 'نشاط جماعي',
      'Badge principal': 'البطاقة الرئيسية',
      'Primary badge': 'البطاقة الرئيسية',
    },
    placeholders: {
      'UID / identifiant du modèle': 'UID / معرف القالب',
      'UID / template ID': 'UID / معرف القالب',
      'UID / Template ID': 'UID / معرف القالب',
      'Badge principal': 'البطاقة الرئيسية',
      'Primary badge': 'البطاقة الرئيسية',
    },
  },
};

// ── i18n ──────────────────────────────────────────────────
const T = {
  fr: {
    gymOwner:'Propriétaire', gymAdmin:'Administrateur', gymStaff:'Réceptionniste', signOut:'Déconnexion',
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
    gymOwner:'Gym Owner', gymAdmin:'Administrator', gymStaff:'Receptionist', signOut:'Sign Out',
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
    gymOwner:'مالك الصالة', gymAdmin:'مدير', gymStaff:'موظف استقبال', signOut:'تسجيل الخروج',
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

Object.assign(T.fr, {
  staffAccessPanel:'Accès & Rôles',
  teamTab:'Équipe',
  rolesTab:'Rôles & Permissions',
  inviteMemberTitle:'Inviter un membre',
  inviteMemberSub:"Ajoutez un membre à l'équipe et préparez son profil dès l'invitation.",
  fullNameLbl:'Nom complet',
  emailLbl:'Email',
  roleLbl:'Rôle',
  jobTitleLbl:'Titre du poste',
  departmentLbl:'Département',
  employmentTypeLbl:'Type de contrat',
  employmentFullTime:'Temps plein',
  employmentPartTime:'Temps partiel',
  employmentFreelance:'Freelance',
  employmentIntern:'Stagiaire',
  hireDateLbl:"Date d'embauche",
  sendInviteBtn:"Envoyer l'invitation",
  staffDirectoryTitle:"Annuaire de l'équipe",
  staffDirectorySub:"Visualisez les profils, rôles et statuts de toute l'équipe de votre salle.",
  pendingInvitesTitle:'Invitations en attente',
  pendingInvitesSub:"Suivez les invitations non acceptées et relancez-les si besoin.",
  rolesLibraryTitle:'Bibliothèque des rôles',
  rolesLibrarySub:'Rôles système verrouillés et rôles personnalisés du tenant actif.',
  createRoleBtn:'Créer un rôle',
  roleEditorTitle:'Éditeur de rôle',
  roleEditorSub:'Configurez le portail, la description et la matrice de permissions.',
  roleNameLbl:'Nom du rôle',
  portalLbl:'Portail',
  descriptionLbl:'Description',
  permissionsTitle:'Permissions',
  permissionsSub:'Activez les permissions nécessaires pour ce rôle, groupées par domaine.',
  saveRoleBtn:'Enregistrer le rôle',
  scheduleTitle:'Planning hebdomadaire',
  emergencyContactNameLbl:"Contact d'urgence — nom",
  emergencyContactPhoneLbl:"Contact d'urgence — téléphone",
  internalNotesLbl:'Notes internes',
  saveStaffProfileBtn:'Enregistrer le profil',
  uploadAvatarBtn:"Préparer l'avatar",
  staffAvatarTitle:'Avatar',
  staffAvatarSub:'Ajoutez une photo pour personnaliser le profil du membre.',
  staffStatTotal:'Profils actifs',
  staffStatPending:'Invitations en attente',
  staffStatAdmin:'Admins',
  staffStatCoach:'Coachs',
  staffStatClient:'Clients',
  staffStatProfiles:'Profils complétés',
  staffProfileReady:'profils renseignés',
  teamEmptyTitle:'Aucun membre trouvé',
  teamEmptyBody:"Invitez votre premier membre pour démarrer l'organisation de l'équipe.",
  teamEmptyAction:'Inviter un membre',
  pendingEmptyTitle:"Aucune invitation en attente",
  pendingEmptyBody:'Toutes les invitations ont été traitées.',
  roleEmptyTitle:'Aucun rôle disponible',
  roleEmptyBody:'Créez un rôle personnalisé ou rechargez la matrice.',
  roleEmptyAction:'Créer un rôle',
  roleSystem:'Système',
  roleCustom:'Personnalisé',
  roleReadOnly:'Les rôles système sont verrouillés. Vous pouvez consulter leurs permissions mais pas les modifier.',
  roleEditable:'Les rôles personnalisés peuvent être modifiés et supprimés.',
  roleDelete:'Supprimer',
  roleEdit:'Modifier',
  roleChange:'Changer le rôle',
  revokeAccess:'Révoquer',
  editProfile:'Modifier le profil',
  resendInvite:"Renvoyer l'invitation",
  cancelInvite:'Annuler',
  inviteSentTo:'Invitation envoyée à {email}.',
  inviteResentTo:'Invitation renvoyée à {email}.',
  inviteMissingRole:'Veuillez sélectionner un rôle.',
  staffRoleUpdated:'Rôle mis à jour.',
  staffAccessRevoked:'Accès retiré.',
  staffProfileSaved:'Profil staff enregistré.',
  staffAvatarReady:'Avatar prêt à être enregistré.',
  staffAvatarMissing:"Sélectionnez un fichier d'avatar avant de continuer.",
  staffDeleteRoleConfirm:'Supprimer ce rôle personnalisé ?',
  staffRevokeConfirm:'Révoquer cet accès maintenant ?',
  roleDeleteBlocked:"Impossible de supprimer ce rôle tant qu'il est attribué à des membres.",
  inviteSendFailed:'Invitation impossible.',
  portalAdmin:'Admin',
  portalCoach:'Coach',
  portalClient:'Client',
  statusActive:'Actif',
  statusPending:'En attente',
  statusAccepted:'Accepté',
  statusSuspended:'Suspendu',
  statusRevoked:'Révoqué',
  hireDateEmpty:'Non défini',
  noRoleAssigned:'Aucun rôle',
  noJobTitle:'Sans titre',
  noDepartment:'Sans département',
  permissionDashboard:'Dashboard',
  permissionMembers:'Membres',
  permissionOperations:'Opérations',
  permissionFinance:'Finance',
  permissionMessages:'Messages',
  permissionAnalytics:'Analytiques',
  permissionAdmin:'Admin',
  permissionSelf:'Self',
  permissionAccess:'Accès',
  staffTableName:'Membre',
  staffTableDepartment:'Département',
  staffTablePortal:'Portail',
  staffTableRole:'Rôle',
  staffTableEmployment:'Contrat',
  staffTableStatus:'Statut',
  staffTableHireDate:"Date d'embauche",
  staffTableActions:'Actions',
  pendingInviteAt:'Invitée le',
  scheduleOff:'Repos',
  scheduleOn:'Actif',
  mondayShort:'Lun',
  tuesdayShort:'Mar',
  wednesdayShort:'Mer',
  thursdayShort:'Jeu',
  fridayShort:'Ven',
  saturdayShort:'Sam',
  sundayShort:'Dim',
});

Object.assign(T.en, {
  staffAccessPanel:'Team & Roles',
  teamTab:'Team',
  rolesTab:'Roles & Permissions',
  inviteMemberTitle:'Invite a member',
  inviteMemberSub:'Add a member to your team and prepare their staff profile during the invite flow.',
  fullNameLbl:'Full name',
  emailLbl:'Email',
  roleLbl:'Role',
  jobTitleLbl:'Job title',
  departmentLbl:'Department',
  employmentTypeLbl:'Employment type',
  employmentFullTime:'Full time',
  employmentPartTime:'Part time',
  employmentFreelance:'Freelance',
  employmentIntern:'Intern',
  hireDateLbl:'Hire date',
  sendInviteBtn:'Send invitation',
  staffDirectoryTitle:'Team directory',
  staffDirectorySub:'Review profiles, roles, and statuses across your gym team.',
  pendingInvitesTitle:'Pending invitations',
  pendingInvitesSub:'Track invitations that have not been accepted yet and resend them when needed.',
  rolesLibraryTitle:'Role library',
  rolesLibrarySub:'Locked system roles and custom roles for the active tenant.',
  createRoleBtn:'Create role',
  roleEditorTitle:'Role editor',
  roleEditorSub:'Configure the portal, description, and permission matrix.',
  roleNameLbl:'Role name',
  portalLbl:'Portal',
  descriptionLbl:'Description',
  permissionsTitle:'Permissions',
  permissionsSub:'Enable the capabilities needed for this role, grouped by area.',
  saveRoleBtn:'Save role',
  scheduleTitle:'Weekly schedule',
  emergencyContactNameLbl:'Emergency contact — name',
  emergencyContactPhoneLbl:'Emergency contact — phone',
  internalNotesLbl:'Internal notes',
  saveStaffProfileBtn:'Save profile',
  uploadAvatarBtn:'Prepare avatar',
  staffAvatarTitle:'Avatar',
  staffAvatarSub:'Add a photo to personalize the staff profile.',
  staffStatTotal:'Active profiles',
  staffStatPending:'Pending invites',
  staffStatAdmin:'Admins',
  staffStatCoach:'Coaches',
  staffStatClient:'Clients',
  staffStatProfiles:'Completed profiles',
  staffProfileReady:'profiles completed',
  teamEmptyTitle:'No members found',
  teamEmptyBody:'Invite your first member to start organizing the team.',
  teamEmptyAction:'Invite member',
  pendingEmptyTitle:'No pending invitations',
  pendingEmptyBody:'All invitations have already been handled.',
  roleEmptyTitle:'No roles available',
  roleEmptyBody:'Create a custom role or refresh the matrix.',
  roleEmptyAction:'Create role',
  roleSystem:'System',
  roleCustom:'Custom',
  roleReadOnly:'System roles are locked. You can review their permissions but not edit them.',
  roleEditable:'Custom roles can be edited and deleted.',
  roleDelete:'Delete',
  roleEdit:'Edit',
  roleChange:'Change role',
  revokeAccess:'Revoke',
  editProfile:'Edit profile',
  resendInvite:'Resend invitation',
  cancelInvite:'Cancel',
  inviteSentTo:'Invitation sent to {email}.',
  inviteResentTo:'Invitation resent to {email}.',
  inviteMissingRole:'Please select a role.',
  staffRoleUpdated:'Role updated.',
  staffAccessRevoked:'Access revoked.',
  staffProfileSaved:'Staff profile saved.',
  staffAvatarReady:'Avatar ready to be saved.',
  staffAvatarMissing:'Select an avatar file before continuing.',
  staffDeleteRoleConfirm:'Delete this custom role?',
  staffRevokeConfirm:'Revoke this access now?',
  roleDeleteBlocked:'This role cannot be deleted while it is assigned to members.',
  inviteSendFailed:'Unable to send invitation.',
  portalAdmin:'Admin',
  portalCoach:'Coach',
  portalClient:'Client',
  statusActive:'Active',
  statusPending:'Pending',
  statusAccepted:'Accepted',
  statusSuspended:'Suspended',
  statusRevoked:'Revoked',
  hireDateEmpty:'Not set',
  noRoleAssigned:'No role',
  noJobTitle:'No title',
  noDepartment:'No department',
  permissionDashboard:'Dashboard',
  permissionMembers:'Members',
  permissionOperations:'Operations',
  permissionFinance:'Finance',
  permissionMessages:'Messages',
  permissionAnalytics:'Analytics',
  permissionAdmin:'Admin',
  permissionSelf:'Self',
  permissionAccess:'Access',
  staffTableName:'Member',
  staffTableDepartment:'Department',
  staffTablePortal:'Portal',
  staffTableRole:'Role',
  staffTableEmployment:'Contract',
  staffTableStatus:'Status',
  staffTableHireDate:'Hire date',
  staffTableActions:'Actions',
  pendingInviteAt:'Invited on',
  scheduleOff:'Off',
  scheduleOn:'On',
  mondayShort:'Mon',
  tuesdayShort:'Tue',
  wednesdayShort:'Wed',
  thursdayShort:'Thu',
  fridayShort:'Fri',
  saturdayShort:'Sat',
  sundayShort:'Sun',
});

Object.assign(T.ar, Object.assign({}, T.fr, {
  staffAccessPanel:'Accès & Rôles',
  teamTab:'Équipe',
  rolesTab:'Rôles & Permissions',
  inviteMemberTitle:'Inviter un membre',
  inviteMemberSub:"Ajoutez un membre à l'équipe et préparez son profil dès l'invitation.",
}));
T.ar.staffTableStatus = T.fr.staffTableStatus;
const t = k => T[currentLang]?.[k] || T.fr[k] || k;

const STAFF_SCHEDULE_DAYS = [
  { code:'mon', labelKey:'mondayShort' },
  { code:'tue', labelKey:'tuesdayShort' },
  { code:'wed', labelKey:'wednesdayShort' },
  { code:'thu', labelKey:'thursdayShort' },
  { code:'fri', labelKey:'fridayShort' },
  { code:'sat', labelKey:'saturdayShort' },
  { code:'sun', labelKey:'sundayShort' },
];

const ROLE_PERMISSION_GROUPS = [
  { labelKey:'permissionDashboard', codes:['view_dashboard'] },
  { labelKey:'permissionMembers', codes:['view_clients', 'edit_clients', 'delete_clients', 'view_coaches', 'edit_coaches', 'view_staff_profiles', 'edit_staff_profiles'] },
  { labelKey:'permissionOperations', codes:['manage_sessions', 'manage_bookings', 'manage_checkins', 'manage_classes', 'manage_access_control'] },
  { labelKey:'permissionFinance', codes:['manage_payments'] },
  { labelKey:'permissionMessages', codes:['manage_messages'] },
  { labelKey:'permissionAnalytics', codes:['view_analytics'] },
  { labelKey:'permissionAdmin', codes:['manage_staff', 'manage_roles', 'manage_branding', 'manage_media'] },
  { labelKey:'permissionSelf', codes:['self_manage_profile'] },
  { labelKey:'permissionAccess', codes:['view_access_logs'] },
];

function applyTranslations() {
  document.querySelectorAll('[data-i18n]').forEach(el => {
    const k = el.getAttribute('data-i18n');
    if (T[currentLang]?.[k]) el.textContent = T[currentLang][k];
  });
  document.querySelectorAll('[data-i18n-ph]').forEach(el => {
    const k = el.getAttribute('data-i18n-ph');
    if (T[currentLang]?.[k]) el.setAttribute('placeholder', T[currentLang][k]);
  });
  Trainw.applyDocumentLanguage(currentLang, document.body);
  document.querySelectorAll('.lang-option-btn').forEach(b => b.classList.toggle('active', b.dataset.lang === currentLang));
  document.querySelectorAll('.lang-btn').forEach(b => b.classList.toggle('active', b.dataset.lang === currentLang));
  const frOption = document.querySelector('.lang-option-btn[data-lang="fr"]');
  const enOption = document.querySelector('.lang-option-btn[data-lang="en"]');
  const arOption = document.querySelector('.lang-option-btn[data-lang="ar"]');
  if (frOption) frOption.textContent = 'Français';
  if (enOption) enOption.textContent = 'English';
  if (arOption) arOption.textContent = 'العربية';
  Trainw.ui.localizeSurface(document.body, GYM_RUNTIME_LOCALE[currentLang] || {});
  Trainw.ui.repairTextSurface(document.body);
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

function hasPermission(code) {
  return currentPermissions.includes(code);
}

function hasStaffDirectoryAccess() {
  return hasPermission('view_staff_profiles')
    || hasPermission('edit_staff_profiles')
    || hasPermission('manage_staff')
    || hasPermission('manage_roles');
}

function canManageRolesUi() {
  return hasPermission('manage_roles');
}

function canManageMembershipUi() {
  return hasPermission('manage_staff') || canManageRolesUi();
}

function canManageStaffUi() {
  return hasStaffDirectoryAccess() || canManageRolesUi();
}

function canEditStaffProfilesUi(userId) {
  return hasPermission('edit_staff_profiles')
    || hasPermission('manage_staff')
    || (!!userId && userId === currentUser?.id);
}

function canOpenSettingsPage() {
  return hasPermission('manage_branding')
    || hasPermission('manage_payments')
    || hasStaffDirectoryAccess()
    || canManageRolesUi();
}

function switchSettingsStaffTab(nextTab) {
  const teamAllowed = hasStaffDirectoryAccess();
  const rolesAllowed = canManageRolesUi();
  const resolvedTab = nextTab === 'roles'
    ? (rolesAllowed ? 'roles' : 'team')
    : (teamAllowed ? 'team' : (rolesAllowed ? 'roles' : 'team'));

  activeSettingsStaffTab = resolvedTab;
  document.querySelectorAll('[data-settings-team-tab]').forEach(button => {
    button.classList.toggle('active', button.dataset.settingsTeamTab === resolvedTab);
  });
  document.getElementById('settings-staff-tab-team')?.classList.toggle('hidden', resolvedTab !== 'team');
  document.getElementById('settings-staff-tab-roles')?.classList.toggle('hidden', resolvedTab !== 'roles');
}

function syncPermissionVisibility() {
  const settingsAllowed = canOpenSettingsPage();
  const brandingAllowed = hasPermission('manage_branding');
  const paymentsAllowed = hasPermission('manage_payments');
  const teamAllowed = hasStaffDirectoryAccess();
  const manageStaffAllowed = hasPermission('manage_staff');
  const manageRolesAllowed = canManageRolesUi();

  document.querySelector('.nav-item[data-page="settings"]')?.classList.toggle('hidden', !settingsAllowed);
  document.getElementById('btn-save-settings')?.closest('.settings-section')?.classList.toggle('hidden', !brandingAllowed);
  document.getElementById('gym-logo-file')?.closest('.settings-section')?.classList.toggle('hidden', !brandingAllowed);
  document.getElementById('btn-save-pricing')?.closest('.settings-section')?.classList.toggle('hidden', !paymentsAllowed);
  document.getElementById('staff-management-section')?.classList.toggle('hidden', !(teamAllowed || manageRolesAllowed));
  document.getElementById('btn-settings-team-tab')?.classList.toggle('hidden', !teamAllowed);
  document.getElementById('btn-settings-roles-tab')?.classList.toggle('hidden', !manageRolesAllowed);
  document.getElementById('team-invite-card')?.classList.toggle('hidden', !manageStaffAllowed);
  document.getElementById('btn-new-role')?.classList.toggle('hidden', !manageRolesAllowed);
  document.getElementById('btn-save-edit-coach')?.classList.toggle('hidden', !hasPermission('edit_coaches'));
  document.getElementById('staff-panel-notes-wrap')?.classList.toggle('hidden', !manageStaffAllowed);

  document.querySelectorAll('.cc-btn-del').forEach(element => {
    element.classList.toggle('hidden', !hasPermission('delete_clients'));
  });
  document.querySelectorAll('.coach-edit-action, .coach-delete-action').forEach(element => {
    element.classList.toggle('hidden', !hasPermission('edit_coaches'));
  });
  document.querySelectorAll('[data-staff-edit-profile]').forEach(element => {
    element.classList.toggle('hidden', !canEditStaffProfilesUi(element.dataset.staffUserId || ''));
  });
  document.querySelectorAll('[data-staff-role-edit], [data-staff-role-select]').forEach(element => {
    element.classList.toggle('hidden', !canManageMembershipUi());
  });
  document.querySelectorAll('[data-staff-revoke], [data-pending-resend], [data-pending-cancel]').forEach(element => {
    element.classList.toggle('hidden', !manageStaffAllowed);
  });

  if (teamAllowed || manageRolesAllowed) {
    switchSettingsStaffTab(activeSettingsStaffTab);
  }

  // ── Staff role: restrict nav to dashboard + checkin only ─────────────────
  const isStaff = currentMembership?.role_code === 'staff';
  const staffAllowedPages = new Set(['dashboard', 'checkin']);
  document.querySelectorAll('.nav-item[data-page]').forEach(item => {
    const page = item.dataset.page;
    if (isStaff && !staffAllowedPages.has(page)) {
      item.classList.add('hidden');
    }
  });
  // ─────────────────────────────────────────────────────────────────────────

  // ── Sidebar role label: reflect actual role of logged-in user ────────────
  const roleCode = currentMembership?.role_code || 'gym_owner';
  const roleLabelKey = roleCode === 'staff' ? 'gymStaff'
    : roleCode === 'gym_admin' ? 'gymAdmin'
    : 'gymOwner';
  const gymLabelEl = document.querySelector('.gym-label[data-i18n]');
  if (gymLabelEl) {
    gymLabelEl.setAttribute('data-i18n', roleLabelKey);
    gymLabelEl.textContent = t(roleLabelKey);
  }
  // ─────────────────────────────────────────────────────────────────────────
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
    if (!session) { window.location.href = GYM_LOGIN_HREF; return; }
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
function activeDirectoryMembers(portal) {
  return accessDirectory.filter(item =>
    item.status === 'active' &&
    (!portal || item.portal === portal) &&
    item.user_id
  );
}

function directoryMembershipForUser(userId, portal) {
  return accessDirectory.find(item =>
    item.user_id === userId &&
    (!portal || item.portal === portal) &&
    item.status !== 'revoked'
  ) || null;
}

function highlightActiveRoleCard() {
  document.querySelectorAll('[data-role-builder-card]').forEach(card => {
    card.classList.toggle('active', card.dataset.roleBuilderCard === activeRoleBuilderId);
  });
}

function roleCodeFromName(name) {
  const raw = String(name || '')
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
  return raw || 'custom_role';
}

function replaceTextTokens(copy, tokens) {
  return Object.entries(tokens || {}).reduce((message, [key, value]) => {
    return message.replace(new RegExp('\\{' + key + '\\}', 'g'), String(value ?? ''));
  }, String(copy || ''));
}

function formatPortalLabel(portal) {
  if (portal === 'admin') return t('portalAdmin');
  if (portal === 'coach') return t('portalCoach');
  return t('portalClient');
}

function formatEmploymentType(value) {
  if (value === 'part_time') return t('employmentPartTime');
  if (value === 'freelance') return t('employmentFreelance');
  if (value === 'intern') return t('employmentIntern');
  return t('employmentFullTime');
}

function formatMembershipStatus(status) {
  if (status === 'active') return t('statusActive');
  if (status === 'accepted') return t('statusAccepted');
  if (status === 'suspended') return t('statusSuspended');
  if (status === 'revoked') return t('statusRevoked');
  return t('statusPending');
}

function formatStaffDate(value) {
  if (!value) return t('hireDateEmpty');
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return t('hireDateEmpty');
  return parsed.toLocaleDateString(locale(), { year:'numeric', month:'short', day:'numeric' });
}

function staffDisplayName(member) {
  return member?.name || member?.invited_name || member?.invite_email || member?.email || 'Member';
}

function staffDisplayInitials(member) {
  return String(staffDisplayName(member))
    .split(/\s+/)
    .filter(Boolean)
    .map(part => part[0] || '')
    .join('')
    .slice(0, 2)
    .toUpperCase() || 'ST';
}

function staffAvatarKey(member) {
  return member?.user_id || member?.membership_id || member?.staff_profile_id || null;
}

function staffAvatarUrl(member) {
  const key = staffAvatarKey(member);
  if (key && staffAvatarUrlMap.has(key)) return staffAvatarUrlMap.get(key);
  return member?.avatar_url || null;
}

function renderStaffAvatar(member, className='staff-member-avatar') {
  const avatarUrl = staffAvatarUrl(member);
  if (avatarUrl) {
    return `<div class="${className}"><img src="${Trainw.escapeHtml(avatarUrl)}" alt="${Trainw.escapeHtml(staffDisplayName(member))}"></div>`;
  }
  return `<div class="${className}">${Trainw.escapeHtml(staffDisplayInitials(member))}</div>`;
}

async function hydrateStaffAvatarUrls(directory) {
  const rows = Array.isArray(directory) ? directory : [];
  await Promise.allSettled(rows.map(async member => {
    const key = staffAvatarKey(member);
    if (!key) return;
    if (member.avatar_storage_bucket && member.avatar_storage_path) {
      const signed = await Trainw.media.createSignedMediaUrl(sb, member.avatar_storage_bucket, member.avatar_storage_path, 3600);
      if (signed.url) {
        staffAvatarUrlMap.set(key, signed.url);
        return;
      }
    }
    if (member.avatar_url) {
      staffAvatarUrlMap.set(key, member.avatar_url);
    }
  }));
}

function updateRoleBuilderPortalButtons(portal) {
  const value = portal || 'admin';
  const hiddenInput = document.getElementById('role-builder-portal');
  if (hiddenInput) hiddenInput.value = value;
  document.querySelectorAll('[data-role-portal]').forEach(button => {
    button.classList.toggle('active', button.dataset.rolePortal === value);
  });
}

function setRoleBuilderReadOnly(readOnly) {
  document.getElementById('role-builder-name')?.toggleAttribute('disabled', readOnly);
  document.getElementById('role-builder-description')?.toggleAttribute('disabled', readOnly);
  document.querySelectorAll('[data-role-portal]').forEach(button => {
    button.toggleAttribute('disabled', readOnly);
  });
  document.querySelectorAll('[data-role-permission]').forEach(input => {
    input.toggleAttribute('disabled', readOnly);
  });
  document.getElementById('btn-save-role-builder')?.classList.toggle('hidden', readOnly || !canManageRolesUi());
  Trainw.ui.setText('role-builder-readonly-note', readOnly ? t('roleReadOnly') : t('roleEditorSub'), '');
}

function refreshInviteRoleOptions() {
  const select = document.getElementById('invite-role-select');
  if (!select) return;
  const previous = select.value;
  select.innerHTML = ['<option value="">--</option>'].concat(
    roleMatrix.map(role => `<option value="${Trainw.escapeHtml(role.role_id)}">${Trainw.escapeHtml(role.name)} · ${Trainw.escapeHtml(formatPortalLabel(role.portal))}</option>`)
  ).join('');
  if (previous && roleMatrix.some(role => role.role_id === previous)) {
    select.value = previous;
  }
}

function renderRolePermissionsGrid(selectedCodes, options={}) {
  const selected = new Set(Array.isArray(selectedCodes) ? selectedCodes : []);
  const readOnly = !!options.readOnly;
  const target = document.getElementById('role-permissions-grid');
  if (!target) return;
  if (!permissionCatalog.length) {
    target.innerHTML = Trainw.ui.emptyState('TW', t('roleEmptyTitle'), t('roleEmptyBody'), canManageRolesUi() ? t('roleEmptyAction') : '', canManageRolesUi() ? 'data-empty-action="create-role"' : '');
    return;
  }
  const permissionMap = new Map(permissionCatalog.map(permission => [permission.code, permission]));
  target.innerHTML = ROLE_PERMISSION_GROUPS.map(group => {
    const permissions = group.codes.map(code => permissionMap.get(code)).filter(Boolean);
    if (!permissions.length) return '';
    return `
      <section class="permission-category">
        <div class="staff-team-card-title" style="font-size:20px;">${Trainw.escapeHtml(t(group.labelKey))}</div>
        <div class="permissions-grid">
          ${permissions.map(permission => `
            <label class="permission-option">
              <div class="permission-option-head">
                <input type="checkbox" data-role-permission="${Trainw.escapeHtml(permission.code)}"${selected.has(permission.code) ? ' checked' : ''}${readOnly ? ' disabled' : ''}>
                <span class="permission-option-code">${Trainw.escapeHtml(permission.code)}</span>
              </div>
              <div class="permission-option-copy">${Trainw.escapeHtml(permission.description || permission.name || permission.code)}</div>
            </label>
          `).join('')}
        </div>
      </section>
    `;
  }).filter(Boolean).join('');
}

function resetRoleBuilderForm() {
  activeRoleBuilderId = null;
  Trainw.ui.setValue('role-builder-id', '', '');
  Trainw.ui.setValue('role-builder-name', '', '');
  Trainw.ui.setValue('role-builder-code', '', '');
  Trainw.ui.setValue('role-builder-description', '', '');
  updateRoleBuilderPortalButtons('admin');
  renderRolePermissionsGrid([], { readOnly: false });
  setRoleBuilderReadOnly(false);
  Trainw.ui.setText('role-builder-status', '', '');
  highlightActiveRoleCard();
}

function openRoleBuilder(roleId) {
  switchSettingsStaffTab('roles');
  const role = roleMatrix.find(item => item.role_id === roleId) || null;
  if (!role) {
    resetRoleBuilderForm();
    return;
  }
  activeRoleBuilderId = role.role_id;
  Trainw.ui.setValue('role-builder-id', role.role_id, '');
  Trainw.ui.setValue('role-builder-name', role.name || '', '');
  Trainw.ui.setValue('role-builder-code', role.code || '', '');
  Trainw.ui.setValue('role-builder-description', role.description || '', '');
  updateRoleBuilderPortalButtons(role.portal || 'admin');
  renderRolePermissionsGrid(role.permissions || [], { readOnly: !!role.is_system });
  setRoleBuilderReadOnly(!!role.is_system);
  Trainw.ui.setText('role-builder-status', '', '');
  highlightActiveRoleCard();
}

function renderRoleBuilderList() {
  const target = document.getElementById('role-builder-list');
  if (!target) return;
  target.className = 'role-builder-list';
  target.innerHTML = roleMatrix.length
    ? roleMatrix.map(role => `
        <div class="role-builder-card${role.role_id === activeRoleBuilderId ? ' active' : ''}" data-role-builder-card="${Trainw.escapeHtml(role.role_id)}">
          <div class="role-card-content">
            <div class="role-builder-card-name">${Trainw.escapeHtml(role.name || role.code || 'Role')}</div>
            <div class="role-builder-card-meta">${Trainw.escapeHtml(formatPortalLabel(role.portal))} · ${Trainw.escapeHtml(role.description || role.code || '')}</div>
          </div>
          <div class="role-builder-card-actions">
            ${role.is_system ? `<span class="role-system-badge">&#128274; ${Trainw.escapeHtml(t('roleSystem'))}</span>` : `
              <button class="btn-secondary" type="button" data-role-edit="${Trainw.escapeHtml(role.role_id)}">${Trainw.escapeHtml(t('roleEdit'))}</button>
              <button class="btn-danger" type="button" data-role-delete="${Trainw.escapeHtml(role.role_id)}">${Trainw.escapeHtml(t('roleDelete'))}</button>
            `}
          </div>
        </div>
      `).join('')
    : Trainw.ui.emptyState('TW', t('roleEmptyTitle'), t('roleEmptyBody'), canManageRolesUi() ? t('roleEmptyAction') : '', canManageRolesUi() ? 'data-empty-action="create-role"' : '');
  highlightActiveRoleCard();
  syncPermissionVisibility();
}

function renderStaffStats() {
  const target = document.getElementById('staff-stats-row');
  if (!target) return;
  const activeProfiles = staffDirectory.filter(member => !!member.staff_profile_id && member.is_active).length;
  const activeMembers = staffDirectory.filter(member => ['active', 'accepted'].includes(member.status));
  const adminCount = activeMembers.filter(member => member.portal === 'admin').length;
  const coachCount = activeMembers.filter(member => member.portal === 'coach').length;
  const clientCount = activeMembers.filter(member => member.portal === 'client').length;
  const pendingCount = staffDirectory.filter(member => member.status === 'pending').length;
  const completedProfiles = staffDirectory.filter(member => !!member.staff_profile_id).length;
  target.innerHTML = `
    <div class="staff-stat-chip">
      <div class="staff-stat-label">${Trainw.escapeHtml(t('staffStatTotal'))}</div>
      <div class="staff-stat-value">${activeProfiles}</div>
      <div class="staff-stat-copy">${Trainw.escapeHtml(t('staffStatProfiles'))}</div>
    </div>
    <div class="staff-stat-chip">
      <div class="staff-stat-label">${Trainw.escapeHtml(t('staffStatProfiles'))}</div>
      <div class="staff-stat-breakdown">
        <div><strong>${adminCount}</strong><span class="staff-stat-mini">${Trainw.escapeHtml(t('staffStatAdmin'))}</span></div>
        <div><strong>${coachCount}</strong><span class="staff-stat-mini">${Trainw.escapeHtml(t('staffStatCoach'))}</span></div>
        <div><strong>${clientCount}</strong><span class="staff-stat-mini">${Trainw.escapeHtml(t('staffStatClient'))}</span></div>
      </div>
    </div>
    <div class="staff-stat-chip">
      <div class="staff-stat-label">${Trainw.escapeHtml(t('staffStatPending'))}</div>
      <div class="staff-stat-value">${pendingCount}</div>
      <div class="staff-stat-copy">${Trainw.escapeHtml(t('pendingInvitesTitle'))}</div>
    </div>
    <div class="staff-stat-chip">
      <div class="staff-stat-label">${Trainw.escapeHtml(t('staffStatProfiles'))}</div>
      <div class="staff-stat-value">${completedProfiles}</div>
      <div class="staff-stat-copy">${Trainw.escapeHtml(t('staffProfileReady'))}</div>
    </div>
  `;
}

function buildStaffScheduleGrid(schedule) {
  const normalized = schedule && typeof schedule === 'object' ? schedule : {};
  const target = document.getElementById('staff-schedule-grid');
  if (!target) return;
  target.innerHTML = STAFF_SCHEDULE_DAYS.map(day => {
    const shift = Array.isArray(normalized[day.code]) ? normalized[day.code] : null;
    const enabled = !!(shift && shift[0] && shift[1]);
    return `
      <div class="staff-schedule-row" data-staff-schedule-row="${Trainw.escapeHtml(day.code)}">
        <div class="staff-schedule-day">${Trainw.escapeHtml(t(day.labelKey))}</div>
        <label class="staff-schedule-toggle">
          <input type="checkbox" data-staff-schedule-enabled="${Trainw.escapeHtml(day.code)}"${enabled ? ' checked' : ''}>
          <span>${Trainw.escapeHtml(enabled ? t('scheduleOn') : t('scheduleOff'))}</span>
        </label>
        <input type="time" class="form-input" data-staff-schedule-start="${Trainw.escapeHtml(day.code)}" value="${Trainw.escapeHtml(enabled ? shift[0] : '09:00')}"${enabled ? '' : ' disabled'}>
        <input type="time" class="form-input" data-staff-schedule-end="${Trainw.escapeHtml(day.code)}" value="${Trainw.escapeHtml(enabled ? shift[1] : '17:00')}"${enabled ? '' : ' disabled'}>
      </div>
    `;
  }).join('');
}

function toggleStaffScheduleRow(dayCode, enabled) {
  const row = document.querySelector(`[data-staff-schedule-row="${dayCode}"]`);
  if (!row) return;
  row.querySelectorAll(`[data-staff-schedule-start="${dayCode}"], [data-staff-schedule-end="${dayCode}"]`).forEach(input => {
    input.disabled = !enabled;
  });
  const label = row.querySelector('.staff-schedule-toggle span');
  if (label) label.textContent = enabled ? t('scheduleOn') : t('scheduleOff');
}

function readStaffScheduleGrid() {
  return STAFF_SCHEDULE_DAYS.reduce((schedule, day) => {
    const enabled = document.querySelector(`[data-staff-schedule-enabled="${day.code}"]`)?.checked;
    const start = document.querySelector(`[data-staff-schedule-start="${day.code}"]`)?.value || '09:00';
    const end = document.querySelector(`[data-staff-schedule-end="${day.code}"]`)?.value || '17:00';
    schedule[day.code] = enabled ? [start, end] : null;
    return schedule;
  }, {});
}

function setStaffPanelAvatarPreview(url, initials) {
  const image = document.getElementById('staff-panel-avatar-image');
  const fallback = document.getElementById('staff-panel-avatar-fallback');
  if (!image || !fallback) return;
  if (url) {
    image.src = url;
    image.classList.remove('hidden');
    fallback.classList.add('hidden');
    return;
  }
  image.removeAttribute('src');
  image.classList.add('hidden');
  fallback.classList.remove('hidden');
  fallback.textContent = initials || 'ST';
}

function clearPendingStaffAvatarSelection() {
  if (pendingStaffAvatarObjectUrl) {
    URL.revokeObjectURL(pendingStaffAvatarObjectUrl);
    pendingStaffAvatarObjectUrl = null;
  }
  pendingStaffAvatarFile = null;
  const input = document.getElementById('staff-avatar-file');
  if (input) input.value = '';
}

function prepareStaffAvatarSelection() {
  const file = document.getElementById('staff-avatar-file')?.files?.[0] || null;
  if (!file) {
    Trainw.ui.showToast(t('staffAvatarMissing'), 'error');
    return;
  }
  if (pendingStaffAvatarObjectUrl) {
    URL.revokeObjectURL(pendingStaffAvatarObjectUrl);
  }
  pendingStaffAvatarFile = file;
  pendingStaffAvatarObjectUrl = URL.createObjectURL(file);
  setStaffPanelAvatarPreview(pendingStaffAvatarObjectUrl, document.getElementById('staff-panel-avatar-fallback')?.textContent || 'ST');
  Trainw.ui.setText('staff-avatar-status', t('staffAvatarReady'), '');
}

function renderStaffDirectory() {
  const target = document.getElementById('staff-directory-list');
  if (!target) return;
  const rows = staffDirectory.filter(member => member.status !== 'pending');
  if (!rows.length) {
    target.innerHTML = Trainw.ui.emptyState('TW', t('teamEmptyTitle'), t('teamEmptyBody'), hasPermission('manage_staff') ? t('teamEmptyAction') : '', hasPermission('manage_staff') ? 'data-empty-action="invite-member"' : '');
    syncPermissionVisibility();
    return;
  }
  target.innerHTML = `
    <div class="staff-directory-row staff-directory-header">
      <div>${Trainw.escapeHtml(t('staffTableName'))}</div>
      <div>${Trainw.escapeHtml(t('staffTableDepartment'))}</div>
      <div>${Trainw.escapeHtml(t('staffTablePortal'))}</div>
      <div>${Trainw.escapeHtml(t('staffTableRole'))}</div>
      <div>${Trainw.escapeHtml(t('staffTableEmployment'))}</div>
      <div>${Trainw.escapeHtml(t('staffTableStatus'))}</div>
      <div>${Trainw.escapeHtml(t('staffTableHireDate'))}</div>
      <div>${Trainw.escapeHtml(t('staffTableActions'))}</div>
    </div>
    ${rows.map(member => {
      const roleOptions = roleMatrix.filter(role => role.role_id === member.role_id || !member.portal || role.portal === member.portal).map(role => `<option value="${Trainw.escapeHtml(role.role_id)}"${role.role_id === member.role_id ? ' selected' : ''}>${Trainw.escapeHtml(role.name)}</option>`).join('');
      const showRoleSelect = activeStaffRoleEditMembershipId === member.membership_id && canManageMembershipUi();
      const actions = [];
      if (canEditStaffProfilesUi(member.user_id)) {
        actions.push(`<button class="btn-secondary" type="button" data-staff-edit-profile="${Trainw.escapeHtml(member.user_id || '')}" data-staff-user-id="${Trainw.escapeHtml(member.user_id || '')}">${Trainw.escapeHtml(t('editProfile'))}</button>`);
      }
      if (canManageMembershipUi() && member.membership_id) {
        actions.push(`<button class="btn-secondary" type="button" data-staff-role-edit="${Trainw.escapeHtml(member.membership_id)}">${Trainw.escapeHtml(t('roleChange'))}</button>`);
      }
      if (hasPermission('manage_staff') && member.membership_id) {
        actions.push(`<button class="btn-danger" type="button" data-staff-revoke="${Trainw.escapeHtml(member.membership_id)}">${Trainw.escapeHtml(t('revokeAccess'))}</button>`);
      }
      return `
        <div class="staff-directory-row">
          <div class="staff-member-main">
            ${renderStaffAvatar(member)}
            <div>
              <div class="staff-member-name">${Trainw.escapeHtml(staffDisplayName(member))}</div>
              <div class="staff-member-meta">${Trainw.escapeHtml(member.job_title || t('noJobTitle'))}</div>
              <div class="staff-member-subcopy">${Trainw.escapeHtml(member.email || member.invite_email || '')}</div>
            </div>
          </div>
          <div><span class="staff-pill">${Trainw.escapeHtml(member.department || t('noDepartment'))}</span></div>
          <div><span class="staff-pill portal-${Trainw.escapeHtml(member.portal || 'client')}">${Trainw.escapeHtml(formatPortalLabel(member.portal))}</span></div>
          <div>${showRoleSelect ? `<select class="form-input" data-staff-role-select="${Trainw.escapeHtml(member.membership_id || '')}">${roleOptions}</select>` : `<div class="staff-member-subcopy">${Trainw.escapeHtml(member.role_name || t('noRoleAssigned'))}</div>`}</div>
          <div><span class="staff-pill">${Trainw.escapeHtml(formatEmploymentType(member.employment_type))}</span></div>
          <div><span class="staff-pill status-${Trainw.escapeHtml(member.status || 'pending')}">${Trainw.escapeHtml(formatMembershipStatus(member.status))}</span></div>
          <div class="staff-member-subcopy">${Trainw.escapeHtml(formatStaffDate(member.hire_date))}</div>
          <div class="staff-actions">${actions.join('') || '<span class="staff-member-subcopy">--</span>'}</div>
        </div>
      `;
    }).join('')}
  `;
  syncPermissionVisibility();
}

function renderPendingInvites() {
  const target = document.getElementById('staff-pending-list');
  if (!target) return;
  const rows = staffDirectory.filter(member => member.status === 'pending');
  if (!rows.length) {
    target.innerHTML = Trainw.ui.emptyState('TW', t('pendingEmptyTitle'), t('pendingEmptyBody'));
    syncPermissionVisibility();
    return;
  }
  target.innerHTML = rows.map(member => `
    <div class="staff-pending-row">
      <div>
        <div class="staff-member-name">${Trainw.escapeHtml(member.invited_name || member.invite_email || '')}</div>
        <div class="staff-pending-meta">${Trainw.escapeHtml(member.invite_email || member.email || '')}</div>
        <div class="staff-pending-meta">${Trainw.escapeHtml(member.role_name || t('noRoleAssigned'))} · ${Trainw.escapeHtml(t('pendingInviteAt'))}: ${Trainw.escapeHtml(formatStaffDate(member.invited_at))}</div>
      </div>
      <div class="staff-pending-actions">
        <button class="btn-secondary" type="button" data-pending-resend="${Trainw.escapeHtml(member.membership_id || '')}" data-pending-email="${Trainw.escapeHtml(member.invite_email || member.email || '')}">${Trainw.escapeHtml(t('resendInvite'))}</button>
        <button class="btn-danger" type="button" data-pending-cancel="${Trainw.escapeHtml(member.membership_id || '')}">${Trainw.escapeHtml(t('cancelInvite'))}</button>
      </div>
    </div>
  `).join('');
  syncPermissionVisibility();
}

async function openStaffPanel(userId) {
  const member = staffDirectory.find(item => item.user_id === userId) || null;
  if (!member) {
    Trainw.ui.showToast(t('errorMsg'), 'error');
    return;
  }
  activeStaffPanelUserId = userId;
  clearPendingStaffAvatarSelection();
  Trainw.ui.setValue('staff-panel-user-id', userId, '');
  Trainw.ui.setText('staff-panel-title', staffDisplayName(member), '');
  Trainw.ui.setText('staff-panel-subtitle', `${formatPortalLabel(member.portal)} · ${member.role_name || t('noRoleAssigned')}`, '');
  Trainw.ui.setValue('staff-panel-name', member.name || '', '');
  Trainw.ui.setValue('staff-panel-email', member.email || member.invite_email || '', '');
  Trainw.ui.setValue('staff-panel-phone', member.phone || '', '');
  Trainw.ui.setValue('staff-panel-job-title', member.job_title || '', '');
  Trainw.ui.setValue('staff-panel-department', member.department || '', '');
  Trainw.ui.setValue('staff-panel-employment-type', member.employment_type || 'full_time', 'full_time');
  Trainw.ui.setValue('staff-panel-hire-date', member.hire_date || '', '');
  Trainw.ui.setValue('staff-panel-emergency-name', member.emergency_contact_name || '', '');
  Trainw.ui.setValue('staff-panel-emergency-phone', member.emergency_contact_phone || '', '');
  Trainw.ui.setValue('staff-panel-notes', member.notes || '', '');
  Trainw.ui.setText('staff-avatar-status', '', '');
  buildStaffScheduleGrid(member.work_schedule || {});
  setStaffPanelAvatarPreview(staffAvatarUrl(member), staffDisplayInitials(member));
  syncPermissionVisibility();
  Trainw.openPanel('staff-profile-panel', 'staff-panel-backdrop');
}

async function loadStaffDirectory() {
  const statsTarget = document.getElementById('staff-stats-row');
  const directoryTarget = document.getElementById('staff-directory-list');
  const pendingTarget = document.getElementById('staff-pending-list');
  if (statsTarget) statsTarget.innerHTML = skeletonCards(4);
  if (directoryTarget) directoryTarget.innerHTML = skeletonRows(4);
  if (pendingTarget) pendingTarget.innerHTML = skeletonRows(2);

  if (!currentGymId || !hasStaffDirectoryAccess()) {
    staffDirectory = [];
    renderStaffStats();
    renderStaffDirectory();
    renderPendingInvites();
    syncPermissionVisibility();
    return;
  }

  try {
    const result = await Trainw.api.run(sb.rpc('get_staff_directory', { p_gym_id: currentGymId }), { context: 'load staff directory', fallback: [] });
    if (result.error) throw result.error;
    staffDirectory = Array.isArray(result.data) ? result.data : [];
    await hydrateStaffAvatarUrls(staffDirectory);
    renderStaffStats();
    renderStaffDirectory();
    renderPendingInvites();
    syncPermissionVisibility();
  } catch (error) {
    staffDirectory = [];
    renderStaffStats();
    renderStaffDirectory();
    renderPendingInvites();
    Trainw.ui.showToast(error.message || t('errorMsg'), 'error');
  }
}

function setGymLogoPreview(url) {
  const image = document.getElementById('gym-logo-preview');
  const fallback = document.getElementById('gym-logo-fallback');
  const meta = document.getElementById('gym-logo-meta');
  if (!image || !fallback || !meta) return;
  if (url) {
    image.src = url;
    image.classList.remove('hidden');
    fallback.classList.add('hidden');
    meta.textContent = currentGymName || 'Logo de la salle';
    return;
  }
  image.removeAttribute('src');
  image.classList.add('hidden');
  fallback.classList.remove('hidden');
  fallback.textContent = (currentGymName || 'TW').slice(0, 2).toUpperCase();
  meta.textContent = 'Aucun logo importe';
}

async function refreshGymLogoPreview(gym) {
  if (!gym?.logo_storage_bucket || !gym?.logo_storage_path) {
    setGymLogoPreview(null);
    return;
  }
  const signed = await Trainw.media.createSignedMediaUrl(sb, gym.logo_storage_bucket, gym.logo_storage_path, 3600);
  setGymLogoPreview(signed.url || null);
}

async function loadAccessControlData(options={}) {
  const includeStaffDirectory = options.includeStaffDirectory !== false;
  const roleListTarget = document.getElementById('role-builder-list');
  const roleGridTarget = document.getElementById('role-permissions-grid');
  if (roleListTarget) roleListTarget.innerHTML = skeletonCards(3);
  if (roleGridTarget) roleGridTarget.innerHTML = skeletonCards(2);

  if (!currentGymId) {
    accessDirectory = [];
    roleMatrix = [];
    permissionCatalog = [];
    refreshInviteRoleOptions();
    resetRoleBuilderForm();
    renderRoleBuilderList();
    if (includeStaffDirectory) {
      staffDirectory = [];
      renderStaffStats();
      renderStaffDirectory();
      renderPendingInvites();
    }
    return;
  }

  try {
    const [directoryResult, roleResult, permissionResult] = await Promise.all([
      Trainw.api.run(sb.rpc('list_gym_member_directory', { p_gym_id: currentGymId }), { context: 'load gym directory', fallback: [] }),
      Trainw.api.run(sb.rpc('list_role_matrix', { p_gym_id: currentGymId }), { context: 'load role matrix', fallback: [] }),
      Trainw.api.run(sb.from('permissions').select('code,name,description,category').order('category').order('code'), { context: 'load permission catalog', fallback: [] }),
    ]);

    if (directoryResult.error) throw directoryResult.error;
    if (roleResult.error) throw roleResult.error;
    if (permissionResult.error) throw permissionResult.error;

    accessDirectory = Array.isArray(directoryResult.data) ? directoryResult.data : [];
    roleMatrix = Array.isArray(roleResult.data) ? roleResult.data : [];
    permissionCatalog = Array.isArray(permissionResult.data) ? permissionResult.data : [];
    refreshInviteRoleOptions();
    renderRoleBuilderList();

    if (activeRoleBuilderId && roleMatrix.some(role => role.role_id === activeRoleBuilderId)) {
      openRoleBuilder(activeRoleBuilderId);
    } else if (roleMatrix.length) {
      openRoleBuilder(roleMatrix[0].role_id);
    } else {
      resetRoleBuilderForm();
    }

    if (includeStaffDirectory) {
      await loadStaffDirectory();
    } else {
      syncPermissionVisibility();
    }
  } catch (error) {
    accessDirectory = [];
    roleMatrix = [];
    permissionCatalog = [];
    refreshInviteRoleOptions();
    resetRoleBuilderForm();
    renderRoleBuilderList();
    if (includeStaffDirectory) {
      staffDirectory = [];
      renderStaffStats();
      renderStaffDirectory();
      renderPendingInvites();
    }
    Trainw.ui.showToast(error.message || t('errorMsg'), 'error');
  }
}

async function saveRoleBuilder() {
  if (!currentGymId) return;
  const currentRole = roleMatrix.find(role => role.role_id === activeRoleBuilderId) || null;
  if (currentRole?.is_system) return;
  const name = document.getElementById('role-builder-name')?.value.trim() || '';
  if (!name) {
    Trainw.ui.showToast(t('errorMsg'), 'error');
    return;
  }

  try {
    const permissionCodes = Array.from(document.querySelectorAll('[data-role-permission]:checked')).map(input => input.dataset.rolePermission);
    const result = await Trainw.api.run(sb.rpc('save_role_definition', {
      p_gym_id: currentGymId,
      p_role_id: document.getElementById('role-builder-id')?.value || null,
      p_name: name,
      p_code: document.getElementById('role-builder-code')?.value.trim() || roleCodeFromName(name),
      p_portal: document.getElementById('role-builder-portal')?.value || 'admin',
      p_description: document.getElementById('role-builder-description')?.value.trim() || null,
      p_permission_codes: permissionCodes,
    }), { context: 'save role definition', fallback: null });
    if (result.error) throw result.error;
    activeRoleBuilderId = result.data || null;
    Trainw.ui.setText('role-builder-status', t('savedOk'), '');
    await loadAccessControlData();
    switchSettingsStaffTab('roles');
  } catch (error) {
    Trainw.ui.showToast(error.message || t('errorMsg'), 'error');
  }
}

async function inviteMember(payload) {
  try {
    const result = await Trainw.api.run(sb.rpc('invite_gym_member', {
      p_gym_id: currentGymId,
      p_email: payload.email,
      p_name: payload.name || null,
      p_role_id: payload.roleId,
      p_phone: payload.phone || null,
      p_metadata: payload.metadata || {},
    }), { context: 'invite member', fallback: [] });
    if (result.error) throw result.error;
    const invite = Array.isArray(result.data) ? result.data[0] : result.data;
    if (!invite) throw new Error(t('inviteSendFailed'));

    if (invite.membership_id) {
      const membershipResult = await Trainw.api.run(sb.from('gym_memberships').select('user_id').eq('id', invite.membership_id).maybeSingle(), { context: 'load invited membership', fallback: null, silent: true });
      const invitedUserId = membershipResult.data?.user_id || null;
      if (invitedUserId) {
        await Trainw.api.run(sb.rpc('upsert_staff_profile', {
          p_gym_id: currentGymId,
          p_user_id: invitedUserId,
          p_job_title: payload.jobTitle || null,
          p_department: payload.department || null,
          p_employment_type: payload.employmentType || 'full_time',
          p_hire_date: payload.hireDate || null,
          p_work_schedule: payload.workSchedule || {},
          p_emergency_contact_name: payload.emergencyContactName || null,
          p_emergency_contact_phone: payload.emergencyContactPhone || null,
          p_notes: payload.notes || null,
        }), { context: 'seed staff profile', fallback: null, silent: true });
      }
    }

    if (invite.invite_token) {
      const emailResult = await Trainw.auth.sendInvitationEmail(sb, {
        email: payload.email,
        inviteToken: invite.invite_token,
        gymName: currentGymName || invite.gym_name || 'Trainw',
        roleName: invite.role_name,
        name: payload.name,
      });
      if (emailResult.error) throw emailResult.error;
    }

    return { data: invite, error: null };
  } catch (error) {
    return { data: null, error };
  }
}

async function submitMemberInvite() {
  if (!currentGymId) return;
  const email = document.getElementById('invite-member-email')?.value.trim().toLowerCase() || '';
  const name = document.getElementById('invite-member-name')?.value.trim() || '';
  const phone = document.getElementById('invite-member-phone')?.value.trim() || '';
  const roleId = document.getElementById('invite-role-select')?.value || '';
  const jobTitle = document.getElementById('invite-member-job-title')?.value.trim() || '';
  const department = document.getElementById('invite-member-department')?.value.trim() || '';
  const employmentType = document.getElementById('invite-member-employment-type')?.value || 'full_time';
  const hireDate = document.getElementById('invite-member-hire-date')?.value || null;
  const btn = document.getElementById('btn-send-member-invite');
  if (!name || !email || !roleId) {
    Trainw.ui.showToast(t('inviteMissingRole'), 'error');
    return;
  }

  Trainw.ui.setBusy(btn, true);
  try {
    const result = await inviteMember({
      email, name, phone, roleId, jobTitle, department, employmentType, hireDate, workSchedule: {},
      metadata: { job_title: jobTitle || null, department: department || null, employment_type: employmentType || 'full_time', hire_date: hireDate || null },
    });
    if (result.error) throw result.error;

    ['invite-member-name', 'invite-member-email', 'invite-member-phone', 'invite-member-job-title', 'invite-member-department', 'invite-member-hire-date'].forEach(id => {
      const input = document.getElementById(id);
      if (input) input.value = '';
    });
    Trainw.ui.setValue('invite-member-employment-type', 'full_time', 'full_time');
    Trainw.ui.setValue('invite-role-select', '', '');
    Trainw.ui.setText('invite-member-status', replaceTextTokens(t('inviteSentTo'), { email }), '');
    Trainw.ui.showToast(replaceTextTokens(t('inviteSentTo'), { email }), 'success');
    await loadAccessControlData();
    switchSettingsStaffTab('team');
  } catch (error) {
    Trainw.ui.setText('invite-member-status', error.message || t('inviteSendFailed'), '');
    Trainw.ui.showToast(error.message || t('inviteSendFailed'), 'error');
  } finally {
    Trainw.ui.setBusy(btn, false);
  }
}

async function saveStaffProfile(userId) {
  if (!currentGymId || !userId) return;
  const btn = document.getElementById('btn-save-staff-profile');
  try {
    Trainw.ui.setBusy(btn, true);
    const name = document.getElementById('staff-panel-name')?.value.trim() || '';
    const phone = document.getElementById('staff-panel-phone')?.value.trim() || '';
    const profileResult = await Trainw.api.run(sb.rpc('upsert_staff_profile', {
      p_gym_id: currentGymId,
      p_user_id: userId,
      p_job_title: document.getElementById('staff-panel-job-title')?.value.trim() || null,
      p_department: document.getElementById('staff-panel-department')?.value.trim() || null,
      p_employment_type: document.getElementById('staff-panel-employment-type')?.value || 'full_time',
      p_hire_date: document.getElementById('staff-panel-hire-date')?.value || null,
      p_work_schedule: readStaffScheduleGrid(),
      p_emergency_contact_name: document.getElementById('staff-panel-emergency-name')?.value.trim() || null,
      p_emergency_contact_phone: document.getElementById('staff-panel-emergency-phone')?.value.trim() || null,
      p_notes: document.getElementById('staff-panel-notes')?.value.trim() || null,
    }), { context: 'save staff profile', fallback: null });
    if (profileResult.error) throw profileResult.error;

    const userResult = await Trainw.api.run(sb.from('users').update({ name: name || staffDisplayName(staffDirectory.find(item => item.user_id === userId) || {}), phone: phone || null }).eq('id', userId), { context: 'save staff user details', fallback: null });
    if (userResult.error) throw userResult.error;

    if (pendingStaffAvatarFile) {
      const safeExt = (String(pendingStaffAvatarFile.name || '').split('.').pop() || 'png').replace(/[^a-z0-9]/gi, '').toLowerCase() || 'png';
      const path = `profiles/${currentGymId}/${userId}/avatar-${Date.now()}.${safeExt}`;
      const uploadResult = await Trainw.api.run(sb.storage.from('trainw-media').upload(path, pendingStaffAvatarFile, { upsert: true }), { context: 'upload staff avatar', fallback: null });
      if (uploadResult.error) throw uploadResult.error;
      await Trainw.api.run(sb.from('media_assets').insert({ gym_id: currentGymId, owner_user_id: userId, entity_type: 'staff_profile', entity_id: profileResult.data, media_kind: 'avatar', storage_bucket: 'trainw-media', storage_path: path, mime_type: pendingStaffAvatarFile.type || null, file_size: pendingStaffAvatarFile.size || null, created_by: currentUser?.id || userId }), { context: 'save staff avatar asset', fallback: null, silent: true });
      const avatarUpdateResult = await Trainw.api.run(sb.from('staff_profiles').update({ avatar_storage_bucket: 'trainw-media', avatar_storage_path: path }).eq('gym_id', currentGymId).eq('user_id', userId), { context: 'attach staff avatar', fallback: null });
      if (avatarUpdateResult.error) throw avatarUpdateResult.error;
      const signed = await Trainw.media.createSignedMediaUrl(sb, 'trainw-media', path, 3600);
      if (signed.url) staffAvatarUrlMap.set(userId, signed.url);
    }

    Trainw.closePanel('staff-profile-panel', 'staff-panel-backdrop');
    clearPendingStaffAvatarSelection();
    Trainw.ui.showToast(t('staffProfileSaved'), 'success');
    await loadStaffDirectory();
  } catch (error) {
    Trainw.ui.showToast(error.message || t('errorMsg'), 'error');
  } finally {
    Trainw.ui.setBusy(btn, false);
  }
}

async function resendInvitation(membershipId, email) {
  const invite = staffDirectory.find(member => member.membership_id === membershipId) || null;
  if (!invite?.invite_token) {
    Trainw.ui.showToast(t('inviteSendFailed'), 'error');
    return;
  }
  try {
    const result = await Trainw.auth.sendInvitationEmail(sb, { email: email || invite.invite_email || invite.email, inviteToken: invite.invite_token, gymName: currentGymName || 'Trainw', roleName: invite.role_name, name: invite.invited_name || invite.name });
    if (result.error) throw result.error;
    Trainw.ui.showToast(replaceTextTokens(t('inviteResentTo'), { email: email || invite.invite_email || invite.email }), 'success');
  } catch (error) {
    Trainw.ui.showToast(error.message || t('inviteSendFailed'), 'error');
  }
}

async function deleteCustomRole(roleId) {
  if (!currentGymId || !roleId) return;
  if (!window.confirm(t('staffDeleteRoleConfirm'))) return;
  try {
    const result = await Trainw.api.run(sb.from('roles').delete().eq('id', roleId).eq('gym_id', currentGymId), { context: 'delete custom role', fallback: null });
    if (result.error) throw result.error;
    if (activeRoleBuilderId === roleId) activeRoleBuilderId = null;
    await loadAccessControlData();
  } catch (error) {
    const blocked = error?.code === '23503' || /violates foreign key/i.test(error?.message || '');
    Trainw.ui.showToast(blocked ? t('roleDeleteBlocked') : (error.message || t('errorMsg')), 'error');
  }
}

async function updateMembershipRole(membershipId, roleId) {
  try {
    const result = await Trainw.api.run(sb.rpc('set_membership_role', { p_membership_id: membershipId, p_role_id: roleId }), { context: 'update membership role', fallback: null });
    if (result.error) throw result.error;
    activeStaffRoleEditMembershipId = null;
    Trainw.ui.showToast(t('staffRoleUpdated'), 'success');
    await loadAccessControlData();
    await Promise.allSettled([loadClients(), loadCoaches(), loadGymCoaches(), loadDashboardStats(), loadAnalytics()]);
  } catch (error) {
    Trainw.ui.showToast(error.message || t('errorMsg'), 'error');
  }
}

async function revokeMembership(membershipId) {
  if (!window.confirm(t('staffRevokeConfirm'))) return;
  try {
    const result = await Trainw.api.run(sb.rpc('revoke_gym_membership', { p_membership_id: membershipId }), { context: 'revoke membership', fallback: null });
    if (result.error) throw result.error;
    Trainw.ui.showToast(t('staffAccessRevoked'), 'success');
    await loadAccessControlData();
    await Promise.allSettled([loadClients(), loadCoaches(), loadGymCoaches(), loadDashboardStats(), loadAnalytics()]);
  } catch (error) {
    Trainw.ui.showToast(error.message || t('errorMsg'), 'error');
  }
}

async function uploadGymLogo() {
  const file = document.getElementById('gym-logo-file')?.files?.[0] || null;
  if (!file || !currentGymId || !currentUser?.id) {
    Trainw.ui.showToast('Selectionnez un logo avant de continuer.', 'info');
    return;
  }
  const safeName = String(file.name || 'logo').replace(/[^a-zA-Z0-9._-]+/g, '-');
  const path = `gyms/${currentGymId}/logos/${Date.now()}-${safeName}`;
  const uploadResult = await Trainw.api.run(
    sb.storage.from('trainw-media').upload(path, file, { upsert: true }),
    { context: 'upload gym logo', fallback: null }
  );
  if (uploadResult.error) return;
  await Trainw.api.run(
    sb.from('media_assets').insert({
      gym_id: currentGymId,
      owner_user_id: currentUser.id,
      entity_type: 'gym',
      entity_id: currentGymId,
      media_kind: 'logo',
      storage_bucket: 'trainw-media',
      storage_path: path,
      mime_type: file.type || null,
      file_size: file.size || null,
      created_by: currentUser.id,
    }),
    { context: 'save gym logo asset', fallback: null, silent: true }
  );
  const updateResult = await Trainw.api.run(
    sb.from('gyms').update({
      logo_storage_bucket: 'trainw-media',
      logo_storage_path: path,
    }).eq('id', currentGymId),
    { context: 'attach gym logo', fallback: null }
  );
  if (updateResult.error) return;
  Trainw.ui.setText('gym-logo-status', 'Logo mis a jour.', '');
  await refreshGymLogoPreview({ logo_storage_bucket: 'trainw-media', logo_storage_path: path });
}

async function loadDashboardStats() {
  if (!currentGymId) return;
  const directoryResult = await Trainw.api.run(
    sb.rpc('list_gym_member_directory', { p_gym_id: currentGymId }),
    { context: 'load dashboard member directory', fallback: accessDirectory }
  );
  const directory = Array.isArray(directoryResult.data)
    ? directoryResult.data
    : (Array.isArray(accessDirectory) ? accessDirectory : []);
  if (!directoryResult.error && Array.isArray(directoryResult.data)) {
    accessDirectory = directoryResult.data;
  }
  const coachCount = directory.filter(item => item.portal === 'coach' && item.user_id && item.status === 'active').length;
  const clientCount = directory.filter(item => item.portal === 'client' && item.user_id && item.status === 'active').length;
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

  const { data: coaches } = await sb.from('coach_profiles').select('id, user_id, gym_id, specialty, hourly_rate, rating, total_reviews, users:users!coach_profiles_user_id_fkey(name, gym_id)').eq('gym_id', currentGymId).eq('approval_status','approved').eq('is_active', true).order('rating',{ascending:false}).limit(3);
  const topEl = document.getElementById('top-coaches-list');
  if (topEl) topEl.innerHTML = !coaches?.length ? `<p class="empty-state">${t('noCoaches')}</p>` :
    coaches.map(c => { const nm=c.users?.name||'Coach'; const ini=nm.split(' ').map(n=>n[0]).join('').slice(0,2).toUpperCase();
      return `<div class="person-card" onclick="openCoachModal('${c.id}')" style="cursor:pointer;margin-bottom:12px;"><div class="person-header"><div class="person-avatar">${ini}</div><div><div class="person-name">${nm}</div><div class="person-role">${c.specialty||'—'}</div></div></div><div class="person-stats"><div class="person-stat-item"><div class="person-stat-value">${c.hourly_rate??'—'}<span style="font-size:11px;color:var(--mt)"> DT</span></div><div class="person-stat-label">${t('hourlyRate')}</div></div><div class="person-stat-item"><div class="person-stat-value">\u2605 ${c.rating??'—'}</div><div class="person-stat-label">${t('avgRating')}</div></div></div></div>`; }).join('');

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
      renderCoreEmptyState(el, {
        icon: '📅',
        title: 'Aucune seance',
        body: 'Planifiez votre premiere seance.',
        actionLabel: '+ Creer une seance',
        actionId: 'open-create-session-modal',
        onAction: () => document.getElementById('create-session-modal')?.classList.add('show'),
      });
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
    renderCoreEmptyState(track, {
      icon: '🏋️',
      title: 'Aucun coach',
      body: 'Invitez votre equipe sur Trainw.',
      actionLabel: '+ Ajouter un coach',
      actionId: 'open-add-coach-modal',
      onAction: () => document.getElementById('add-coach-modal')?.classList.add('show'),
    });
    return;
  }
  track.innerHTML = `<div style="display:flex;gap:20px;padding:20px;">${[1,2,3].map(()=>`<div class="coach-carousel-card skeleton-card"><div class="skeleton skeleton-avatar" style="width:80px;height:80px;border-radius:50%;margin:0 auto 16px;"></div><div class="skeleton skeleton-line medium" style="margin:0 auto 8px;"></div><div class="skeleton skeleton-line short" style="margin:0 auto;"></div></div>`).join('')}</div>`;

  const {data:coaches} = await sb.from('coach_profiles')
    .select('id, user_id, gym_id, specialty, hourly_rate, rating, total_reviews, bio, users:users!coach_profiles_user_id_fkey(name, gym_id)')
    .eq('gym_id', currentGymId)
    .eq('approval_status', 'approved')
    .eq('is_active', true);

  if (!coaches?.length) {
    renderCoreEmptyState(track, {
      icon: '🏋️',
      title: 'Aucun coach',
      body: 'Invitez votre equipe sur Trainw.',
      actionLabel: '+ Ajouter un coach',
      actionId: 'open-add-coach-modal',
      onAction: () => document.getElementById('add-coach-modal')?.classList.add('show'),
    });
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
    const stars = c.rating ? '\u2605'.repeat(Math.round(c.rating)) + '\u2606'.repeat(5-Math.round(c.rating)) : '—';
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
  if (!currentGymId) return;
  const {data:c}=await sb.from('coach_profiles').select('id, user_id, specialty, hourly_rate, bio, rating, total_reviews, created_at, users:users!coach_profiles_user_id_fkey(name, phone)').eq('id',coachId).eq('gym_id', currentGymId).single();
  if(!c) return;
  const nm=c.users?.name||'Coach'; const ini=nm.split(' ').map(n=>n[0]).join('').slice(0,2).toUpperCase();
  const months=Math.floor((Date.now()-new Date(c.created_at))/(1000*60*60*24*30));
  const employed=months>=12?`${Math.floor(months/12)}a ${months%12}m`:`${months}m`;
  const modalBody=document.getElementById('coach-modal-body'); if(!modalBody) return;
  modalBody.innerHTML=`<div class="modal-header"><div class="modal-avatar-lg">${Trainw.escapeHtml(ini)}</div><div class="modal-info"><h2>${Trainw.escapeHtml(nm)}</h2><div class="modal-meta">${Trainw.escapeHtml(t('employedLbl'))}: ${Trainw.escapeHtml(employed)} · ${Trainw.escapeHtml(c.users?.phone||'—')}</div><span class="modal-badge">${Trainw.escapeHtml(c.specialty||'—')}</span></div></div><div class="modal-section"><div class="modal-stats-row"><div class="modal-stat-box"><div class="modal-stat-value">${Trainw.escapeHtml(String(c.hourly_rate??'—'))} DT</div><div class="modal-stat-label">${Trainw.escapeHtml(t('hourlyRate'))}</div></div><div class="modal-stat-box"><div class="modal-stat-value">${Trainw.escapeHtml(String(c.total_reviews??0))}</div><div class="modal-stat-label">${Trainw.escapeHtml(t('totalReviews'))}</div></div><div class="modal-stat-box"><div class="modal-stat-value">\u2605 ${Trainw.escapeHtml(String(c.rating??'—'))}</div><div class="modal-stat-label">${Trainw.escapeHtml(t('avgRating'))}</div></div></div>${c.bio?`<div style="background:var(--s2);border:1px solid var(--bd);border-radius:7px;padding:16px;margin-top:14px;font-size:14px;color:var(--mt);line-height:1.7;">${Trainw.escapeHtml(c.bio)}</div>`:''}</div><div class="modal-section" style="display:flex;gap:12px;margin-top:8px;"><button class="btn-primary coach-edit-action" style="flex:1;" type="button">✏ ${Trainw.escapeHtml(t('editCoach'))}</button><button class="btn-danger coach-delete-action" style="flex:0 0 auto;" type="button">✕ ${Trainw.escapeHtml(t('deleteCoach'))}</button></div>`;
  modalBody.querySelector('.coach-edit-action')?.addEventListener('click',()=>openEditCoachModal(c.id,nm,c.specialty||'',c.hourly_rate||0,c.bio||''));
  modalBody.querySelector('.coach-delete-action')?.addEventListener('click',()=>deleteCoach(c.user_id||c.id,c.id));
  modalBody.querySelectorAll('.coach-edit-action, .coach-delete-action').forEach(element => {
    element.classList.toggle('hidden', !hasPermission('edit_coaches'));
  });
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
  try{const{error}=await sb.from('coach_profiles').update({specialty:specialty||null,hourly_rate:rate,bio:bio||null}).eq('id',profileId).eq('gym_id', currentGymId);if(error)throw error;toast(t('savedOk'));document.getElementById('edit-coach-modal').classList.remove('show');await loadCoaches();await loadDashboardStats();}
  catch(e){toast(t('errorMsg'),'err');}finally{btn.textContent=t('saveChanges');btn.disabled=false;}
}
async function deleteCoach(userId,profileId){
  if(!confirm('Supprimer ce coach ?')) return;
  try{const{error:revokeError}=await sb.rpc('revoke_gym_membership_by_user',{p_user_id:userId,p_gym_id:currentGymId});if(revokeError)throw revokeError;await sb.from('coach_profiles').delete().eq('id',profileId).eq('gym_id', currentGymId);await sb.from('users').delete().eq('id',userId);document.getElementById('coach-modal').classList.remove('show');await loadCoaches();await loadDashboardStats();animateCounters();toast('Coach supprimé');}
  catch(e){toast(t('errorMsg'),'err');}
}

// ── Clients ───────────────────────────────────────────────
async function loadClients() {
  const el=document.getElementById('clients-grid'); if(!el) return;
  if(!currentGymId){el.innerHTML=`<p class="empty-state">${t('noClients')}</p>`;return;}
  el.innerHTML=skeletonCards(4);
  const directoryResult = await Trainw.api.run(
    sb.rpc('list_gym_member_directory', { p_gym_id: currentGymId }),
    { context: 'load client membership directory', fallback: [] }
  );
  const clients = (Array.isArray(directoryResult.data) ? directoryResult.data : [])
    .filter(item => item.portal === 'client' && item.user_id && item.status === 'active');
  if (!directoryResult.error) {
    accessDirectory = Array.isArray(directoryResult.data) ? directoryResult.data : accessDirectory;
  }
  let profileMap={};
  if(clients.length){
    const ids=[...new Set(clients.map(c=>c.user_id))];
    const profileResult = await Trainw.api.run(
      sb.from('client_profiles')
        .select('user_id, gym_id, membership_tier, fitness_goal, payment_status, age, training_type, membership_start_date, membership_end_date, price_paid')
        .eq('gym_id', currentGymId)
        .in('user_id', ids),
      { context: 'load client profiles', fallback: [] }
    );
    (profileResult.data||[]).forEach(p=>{profileMap[p.user_id]=p;});
  }
  allClients=clients.map(c=>({
    id:c.user_id,
    user_id:c.user_id,
    membership_id:c.membership_id,
    gym_id:c.gym_id||currentGymId,
    name:c.name||'Client',
    email:c.email||c.invite_email||'',
    phone:c.phone||'',
    created_at:c.invited_at||c.last_active_at||new Date().toISOString(),
    role:c.role_code||'client',
    portal:c.portal||'client',
    status:c.status||'active',
    permissions:Array.isArray(c.permissions)?c.permissions:[],
    avatar_storage_bucket:c.avatar_storage_bucket||null,
    avatar_storage_path:c.avatar_storage_path||null,
    profile:profileMap[c.user_id]||{},
  }));
  ensureSelectedCredentialClient();
  renderClients(); populateCheckInSelector(); populateMessagesList(); populateSessionClientSelector(); renderCredentialClientList(); renderGateAccessLog(); updateGateTerminalPreview();
  if (selectedCredentialClientId) void loadClientCredentials();
  if (directoryResult.error) toast(t('errorMsg'), 'err');
}
function renderClients(){
  const el=document.getElementById('clients-grid'); if(!el) return;
  const q=document.getElementById('clients-search')?.value.toLowerCase()||'';
  let list=allClients;
  if(clientFilter!=='all') list=list.filter(c=>(c.profile?.payment_status||'paid')===clientFilter);
  if(q) list=list.filter(c=>(c.name||'').toLowerCase().includes(q)||(c.phone||'').includes(q));
  if(!list.length){
    if(!allClients.length){
      renderCoreEmptyState(el, {
        icon: '👥',
        title: 'Aucun client',
        body: 'Ajoutez votre premier membre pour commencer.',
        actionLabel: '+ Ajouter un client',
        actionId: 'open-add-client-modal',
        onAction: () => document.getElementById('add-client-modal')?.classList.add('show'),
      });
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
  el.querySelectorAll('.cc-btn-del').forEach(element => {
    element.classList.toggle('hidden', !hasPermission('delete_clients'));
  });
  syncPermissionVisibility();
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

function renderCoreEmptyState(target, options) {
  if (!target) return;
  const actionId = options?.actionId || '';
  const actionAttr = actionId ? `data-empty-action="${actionId}"` : '';
  target.innerHTML = Trainw.ui.emptyState(
    options?.icon,
    options?.title,
    options?.body,
    options?.actionLabel || null,
    actionAttr
  );
  if (actionId && typeof options?.onAction === 'function') {
    target.querySelector(`[data-empty-action="${actionId}"]`)?.addEventListener('click', options.onAction);
  }
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
      .select('id, user_id, gym_id, specialty, users:users!coach_profiles_user_id_fkey(name, gym_id)')
      .eq('gym_id', currentGymId)
      .eq('approval_status', 'approved')
      .eq('is_active', true),
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
    sb.from('coach_profiles').select('id').eq('user_id', userId).eq('gym_id', currentGymId).maybeSingle(),
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
    if (!roleMatrix.length) {
      await loadAccessControlData();
    }
    const coachRole = roleMatrix.find(role =>
      String(role.code || '').toLowerCase() === 'coach' &&
      String(role.gym_id || currentGymId) === String(currentGymId)
    ) || null;
    const coachRoleId = coachRole?.role_id || null;
    if (!coachRoleId) {
      throw new Error('Coach role is not configured for this gym.');
    }

    const inviteResult = await Trainw.api.run(
      sb.rpc('invite_gym_member', {
        p_gym_id: currentGymId,
        p_email: email,
        p_name: name,
        p_phone: phone || null,
        p_role_id: coachRoleId,
        p_metadata: {
          specialty: specialty || null,
          hourly_rate: rate,
        },
      }),
      { context: 'create coach membership', fallback: [] }
    );
    if (inviteResult.error) throw inviteResult.error;

    const invite = Array.isArray(inviteResult.data) ? inviteResult.data[0] : inviteResult.data;
    if (!invite?.membership_id) {
      throw new Error('Coach membership could not be created.');
    }

    if (invite.invite_token) {
      const emailResult = await Trainw.auth.sendInvitationEmail(sb, {
        email,
        inviteToken: invite.invite_token,
        gymName: invite.gym_name,
        roleName: invite.role_name,
        name,
      });
      if (emailResult.error) throw emailResult.error;
    }

    toast(t('coachAdded'));
    document.getElementById('add-coach-modal')?.classList.remove('show');
    ['new-coach-name', 'new-coach-email', 'new-coach-phone', 'new-coach-specialty', 'new-coach-rate'].forEach(id => {
      const field = document.getElementById(id);
      if (field) field.value = '';
    });
    await loadAccessControlData();
    await Promise.allSettled([loadCoaches(), loadGymCoaches()]);
  } catch (error) {
    showInlineError(errEl, error.message || t('errorMsg'));
    toast(error.message || t('errorMsg'), 'err');
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
  try{const{error:revokeError}=await sb.rpc('revoke_gym_membership_by_user',{p_user_id:userId,p_gym_id:currentGymId});if(revokeError)throw revokeError;const{error:profileError}=await sb.from('client_profiles').delete().eq('user_id',userId);if(profileError)throw profileError;const{error:userError}=await sb.from('users').delete().eq('id',userId);if(userError)throw userError;allClients=allClients.filter(c=>c.id!==userId);renderClients();await loadDashboardStats();animateCounters();toast('Client supprimé');}
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
    if (!roleMatrix.length) {
      await loadAccessControlData();
    }
    const clientRole = roleMatrix.find(role =>
      String(role.code || '').toLowerCase() === 'client' &&
      String(role.gym_id || currentGymId) === String(currentGymId)
    ) || null;
    const clientRoleId = clientRole?.role_id || null;
    if (!clientRoleId) {
      throw new Error('Client role is not configured for this gym.');
    }

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

    const membershipInsert = await Trainw.api.run(
      sb.from('gym_memberships').insert({
        gym_id: currentGymId,
        user_id: newUserId,
        role_id: clientRoleId,
        status: 'active',
        invitation_status: 'accepted',
        is_default: true,
        activated_at: new Date().toISOString(),
      }),
      { context: 'create client membership' }
    );
    if (membershipInsert.error) {
      await Trainw.api.run(sb.from('users').delete().eq('id', newUserId), {
        context: 'rollback managed client',
        silent: true,
      });
      throw membershipInsert.error;
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
    renderCoreEmptyState(el, {
      icon: '👥',
      title: 'Aucun client',
      body: 'Ajoutez votre premier membre pour commencer.',
      actionLabel: '+ Ajouter un client',
      actionId: 'open-add-client-modal',
      onAction: () => document.getElementById('add-client-modal')?.classList.add('show'),
    });
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
      .eq('receiver_id', currentUser.id)
      .eq('is_read', false),
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

function flashCheckInNavItem() {
  const navItem = document.querySelector('.nav-item[data-page="checkin"]');
  if (!navItem) return;

  navItem.classList.remove('flash-green');
  void navItem.offsetWidth;
  navItem.classList.add('flash-green');
  window.setTimeout(() => {
    navItem.classList.remove('flash-green');
  }, 1200);
}

function incrementCheckInStat() {
  const statEl = document.getElementById('stat-checkins');
  if (!statEl) return;

  const currentCount = parseInt(statEl.textContent || '0', 10);
  const nextCount = Number.isFinite(currentCount) ? currentCount + 1 : 1;
  Trainw.ui.setText('stat-checkins', String(nextCount), '0');
}

function clearGymRealtimeSubscriptions() {
  [gateCheckInChannel, gymMessageChannel, gymSessionChannel, gymCheckInChannel, gymGateAccessChannel].forEach(channel => {
    if (!channel) return;
    try { sb.removeChannel(channel); } catch (error) {}
  });
  gateCheckInChannel = null;
  gymMessageChannel = null;
  gymSessionChannel = null;
  gymCheckInChannel = null;
  gymGateAccessChannel = null;
  if (gymRefreshTimer) {
    clearTimeout(gymRefreshTimer);
    gymRefreshTimer = null;
  }
}

function queueGymRefresh(kind, delay) {
  if (gymRefreshTimer) clearTimeout(gymRefreshTimer);
  gymRefreshTimer = window.setTimeout(async function () {
    if (!currentGymId) return;
    if (kind === 'messages') {
      if (activeConvId) await loadConversation(activeConvId);
      else populateMessagesList(document.getElementById('msg-contact-search')?.value || '');
      await updateMessageBadge();
      return;
    }
    if (kind === 'sessions') {
      await Promise.allSettled([loadDashboardStats(), loadSchedule()]);
      return;
    }
    if (kind === 'checkins') {
      await Promise.allSettled([loadCheckIns(), loadDashboardStats()]);
      return;
    }
    if (kind === 'accesslog') {
      await loadGateAccessLog();
      return;
    }
  }, delay || 240);
}

function subscribeToGateCheckIns() {
  if (!currentGymId) return;
  clearGymRealtimeSubscriptions();

  gateCheckInChannel = sb.channel(`gate-checkins-${currentGymId}`).on(
    'postgres_changes',
    {
      event: 'INSERT',
      schema: 'public',
      table: 'check_ins',
      filter: `gym_id=eq.${currentGymId}`,
    },
    async function () {
      incrementCheckInStat();
      flashCheckInNavItem();
      queueGymRefresh('checkins', 150);
    }
  ).subscribe();

  gymCheckInChannel = sb.channel(`gym-checkins-${currentGymId}`).on(
    'postgres_changes',
    {
      event: '*',
      schema: 'public',
      table: 'check_ins',
      filter: `gym_id=eq.${currentGymId}`,
    },
    function () {
      queueGymRefresh('checkins', 220);
    }
  ).subscribe();

  gymGateAccessChannel = sb.channel(`gym-gate-access-${currentGymId}`).on(
    'postgres_changes',
    {
      event: '*',
      schema: 'public',
      table: 'gate_access_log',
      filter: `gym_id=eq.${currentGymId}`,
    },
    function () {
      queueGymRefresh('accesslog', 180);
    }
  ).subscribe();

  gymSessionChannel = sb.channel(`gym-sessions-${currentGymId}`).on(
    'postgres_changes',
    {
      event: '*',
      schema: 'public',
      table: 'sessions',
      filter: `gym_id=eq.${currentGymId}`,
    },
    function () {
      queueGymRefresh('sessions', 220);
    }
  ).subscribe();

  gymMessageChannel = sb.channel(`gym-messages-${currentGymId}`).on(
    'postgres_changes',
    {
      event: '*',
      schema: 'public',
      table: 'messages',
      filter: `gym_id=eq.${currentGymId}`,
    },
    function (payload) {
      const row = payload?.new || payload?.old || {};
      if (!row.sender_id && !row.receiver_id) return;
      queueGymRefresh('messages', 160);
    }
  ).subscribe();
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

function getCredentialTypeMeta(type) {
  if (type === 'fingerprint') {
    return { icon: '👆', label: 'Fingerprint', hint: 'Template ID du capteur' };
  }
  if (type === 'face') {
    return { icon: '🙂', label: 'Face', hint: 'ID du profil visage' };
  }
  return { icon: '🏷️', label: 'RFID Card', hint: 'UID de la carte ou du badge' };
}

function getAccessTypeIcon(type) {
  if (type === 'fingerprint') return '👆';
  if (type === 'face') return '🙂';
  if (type === 'rfid_card') return '🏷️';
  if (type === 'manual') return '✍️';
  return '📱';
}

function getAccessReasonLabel(reason) {
  const map = {
    invalid_credential: 'Badge inconnu',
    membership_inactive: 'Abonnement inactif',
    membership_expired: 'Abonnement expiré',
    payment_unpaid: 'Paiement non confirmé',
    duplicate_recent_checkin: 'Passage déjà enregistré récemment',
    invalid_token: 'QR invalide',
    token_used: 'QR déjà utilisé',
    token_expired: 'QR expiré',
    gym_mismatch: 'Terminal non autorisé',
  };
  return map[reason] || reason || 'Accès refusé';
}

function getSelectedCredentialClient() {
  return allClients.find(client => client.id === selectedCredentialClientId) || null;
}

function ensureSelectedCredentialClient() {
  if (!allClients.length) {
    selectedCredentialClientId = null;
    return null;
  }
  if (!selectedCredentialClientId || !allClients.some(client => client.id === selectedCredentialClientId)) {
    selectedCredentialClientId = allClients[0].id;
  }
  return getSelectedCredentialClient();
}

function renderCheckInTabs() {
  document.querySelectorAll('[data-checkin-tab]').forEach(button => {
    button.classList.toggle('active', button.dataset.checkinTab === checkInTab);
  });
  document.querySelectorAll('.checkin-tab-panel').forEach(panel => {
    panel.classList.toggle('hidden', panel.id !== `checkin-tab-${checkInTab}`);
  });
}

function setCheckInTab(tab) {
  checkInTab = tab || 'live';
  renderCheckInTabs();
  if (checkInTab === 'credentials') {
    renderCredentialClientList();
    void loadClientCredentials();
  }
  if (checkInTab === 'journal') {
    renderGateAccessLog();
  }
  if (checkInTab === 'terminal') {
    updateGateTerminalPreview();
  }
}

function renderCredentialClientList() {
  const listEl = document.getElementById('credential-client-list');
  if (!listEl) return;

  const query = (document.getElementById('credential-client-search')?.value || '').trim().toLowerCase();
  const list = allClients.filter(client => {
    if (!query) return true;
    const haystack = [client.name, client.phone, client.profile?.membership_tier]
      .map(value => String(value || '').toLowerCase())
      .join(' ');
    return haystack.includes(query);
  });

  ensureSelectedCredentialClient();

  if (!list.length) {
    listEl.innerHTML = `<p class="empty-state">${Trainw.escapeHtml(t('noClients'))}</p>`;
    return;
  }

  listEl.innerHTML = list.map(client => {
    const membership = client.profile?.membership_tier || 'basic';
    const status = client.profile?.payment_status || 'paid';
    return `
      <button class="credential-client-item${selectedCredentialClientId === client.id ? ' active' : ''}" type="button" data-credential-client="${client.id}">
        <div class="credential-client-name">${Trainw.escapeHtml(client.name || 'Client')}</div>
        <div class="credential-client-sub">${Trainw.escapeHtml(String(membership).toUpperCase())} · ${Trainw.escapeHtml(status)}</div>
      </button>
    `;
  }).join('');
}

function updateCredentialModalHint() {
  const type = document.getElementById('credential-type')?.value || 'rfid_card';
  const meta = getCredentialTypeMeta(type);
  const input = document.getElementById('credential-data');
  if (input) input.placeholder = meta.hint;
}

async function loadClientCredentials() {
  const listEl = document.getElementById('credential-list');
  const selectedClient = ensureSelectedCredentialClient();
  if (!listEl) return;

  Trainw.ui.setText('credential-selected-client-name', selectedClient?.name || 'Sélectionnez un client', 'Sélectionnez un client');

  if (!currentGymId || !selectedClient) {
    memberCredentialsList = [];
    renderCredentialList();
    return;
  }

  listEl.innerHTML = skeletonRows(3);
  const result = await Trainw.api.run(
    sb.from('member_credentials')
      .select('id, type, credential_data, label, is_active, enrolled_at, last_used_at, created_at')
      .eq('gym_id', currentGymId)
      .eq('client_id', selectedClient.id)
      .order('created_at', { ascending: false }),
    { context: 'load member credentials', fallback: [] }
  );
  memberCredentialsList = Array.isArray(result.data) ? result.data : [];
  renderCredentialList();
  if (result.error) toast(result.error.message || t('errorMsg'), 'err');
}

function renderCredentialList() {
  const listEl = document.getElementById('credential-list');
  const selectedClient = getSelectedCredentialClient();
  if (!listEl) return;

  if (!selectedClient) {
    listEl.innerHTML = `<p class="empty-state">Sélectionnez un client pour gérer ses badges.</p>`;
    return;
  }

  if (!memberCredentialsList.length) {
    listEl.innerHTML = `<p class="empty-state">Aucun badge enregistré pour ${Trainw.escapeHtml(selectedClient.name || 'ce client')}.</p>`;
    return;
  }

  listEl.innerHTML = memberCredentialsList.map(credential => {
    const meta = getCredentialTypeMeta(credential.type);
    const lastUsed = credential.last_used_at
      ? new Date(credential.last_used_at).toLocaleString(locale(), { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })
      : 'Jamais utilisé';
    return `
      <article class="credential-card${credential.is_active ? '' : ' inactive'}">
        <div class="credential-card-top">
          <div>
            <div class="credential-type-pill">${Trainw.escapeHtml(`${meta.icon} ${meta.label}`)}</div>
          </div>
          <div class="credential-meta">${Trainw.escapeHtml(credential.is_active ? 'Actif' : 'Inactif')}</div>
        </div>
        <div>
          <div class="credential-label">${Trainw.escapeHtml(credential.label || credential.credential_data)}</div>
          <div class="credential-meta">${Trainw.escapeHtml(lastUsed)}</div>
        </div>
        <div class="credential-actions">
          <button class="credential-action-btn" type="button" data-credential-toggle="${credential.id}" data-next-active="${credential.is_active ? 'false' : 'true'}">
            ${Trainw.escapeHtml(credential.is_active ? 'Désactiver' : 'Activer')}
          </button>
          <button class="credential-action-btn danger" type="button" data-credential-delete="${credential.id}">
            Supprimer
          </button>
        </div>
      </article>
    `;
  }).join('');
}

async function saveMemberCredential() {
  const selectedClient = getSelectedCredentialClient();
  const errEl = document.getElementById('credential-modal-error');
  const btn = document.getElementById('btn-save-credential');
  const type = document.getElementById('credential-type')?.value || 'rfid_card';
  const credentialData = document.getElementById('credential-data')?.value.trim() || '';
  const label = document.getElementById('credential-label')?.value.trim() || null;

  clearInlineError(errEl);
  if (!currentGymId || !currentUser?.id || !selectedClient) {
    showInlineError(errEl, 'Sélectionnez un client avant de continuer.');
    return;
  }
  if (!credentialData) {
    showInlineError(errEl, 'L’identifiant matériel est requis.');
    return;
  }

  Trainw.ui.setBusy(btn, true);
  if (btn) btn.textContent = '...';
  try {
    const insertResult = await Trainw.api.run(
      sb.from('member_credentials').insert({
        gym_id: currentGymId,
        client_id: selectedClient.id,
        type,
        credential_data: credentialData,
        label,
        enrolled_by: currentUser.id,
      }),
      { context: 'save member credential', silent: true, fallback: null }
    );
    if (insertResult.error) throw insertResult.error;

    document.getElementById('credential-modal')?.classList.remove('show');
    Trainw.ui.setValue('credential-data', '', '');
    Trainw.ui.setValue('credential-label', '', '');
    toast('Badge enregistré');
    await loadClientCredentials();
  } catch (error) {
    if (error.code === '23505') {
      showInlineError(errEl, 'Ce badge est déjà enregistré');
    } else {
      showInlineError(errEl, error.message || t('errorMsg'));
    }
  } finally {
    if (btn) btn.textContent = 'Enregistrer';
    Trainw.ui.setBusy(btn, false);
  }
}

async function toggleMemberCredential(credentialId, nextActive) {
  if (!credentialId) return;
  const result = await Trainw.api.run(
    sb.from('member_credentials').update({ is_active: nextActive === 'true' }).eq('id', credentialId).eq('gym_id', currentGymId),
    { context: 'toggle member credential', fallback: null }
  );
  if (result.error) {
    toast(result.error.message || t('errorMsg'), 'err');
    return;
  }
  await loadClientCredentials();
}

async function deleteMemberCredential(credentialId) {
  if (!credentialId || !window.confirm('Supprimer ce badge ?')) return;
  const result = await Trainw.api.run(
    sb.from('member_credentials').delete().eq('id', credentialId).eq('gym_id', currentGymId),
    { context: 'delete member credential', fallback: null }
  );
  if (result.error) {
    toast(result.error.message || t('errorMsg'), 'err');
    return;
  }
  toast('Badge supprimé');
  await loadClientCredentials();
}

async function loadGateAccessLog() {
  const listEl = document.getElementById('access-log-list');
  if (!listEl || !currentGymId) return;
  listEl.innerHTML = skeletonRows(4);
  const result = await Trainw.api.run(
    sb.from('gate_access_log')
      .select('id, client_id, credential_type, access_granted, denial_reason, device_id, attempted_at')
      .eq('gym_id', currentGymId)
      .order('attempted_at', { ascending: false })
      .limit(50),
    { context: 'load access log', fallback: [] }
  );
  gateAccessLogList = Array.isArray(result.data) ? result.data : [];
  renderGateAccessLog();
  if (result.error) toast(result.error.message || t('errorMsg'), 'err');
}

function renderGateAccessLog() {
  const listEl = document.getElementById('access-log-list');
  if (!listEl) return;

  const filter = document.getElementById('access-log-filter')?.value || 'all';
  const clientMap = new Map(allClients.map(client => [client.id, client]));
  let list = gateAccessLogList.slice();
  if (filter === 'granted') list = list.filter(item => item.access_granted);
  if (filter === 'denied') list = list.filter(item => !item.access_granted);

  if (!list.length) {
    listEl.innerHTML = `<p class="empty-state">Aucun accès à afficher.</p>`;
    return;
  }

  listEl.innerHTML = list.map(item => {
    const client = clientMap.get(item.client_id);
    const clientName = client?.name || (item.access_granted ? 'Client' : 'Inconnu');
    const icon = getAccessTypeIcon(item.credential_type);
    const time = item.attempted_at
      ? new Date(item.attempted_at).toLocaleString(locale(), {
          day: '2-digit',
          month: 'short',
          hour: '2-digit',
          minute: '2-digit',
        })
      : '—';
    const reason = item.access_granted ? '' : getAccessReasonLabel(item.denial_reason);
    return `
      <article class="access-log-item">
        <div class="access-log-main">
          <div class="access-log-name">${Trainw.escapeHtml(`${icon} ${clientName}`)}</div>
          <div class="access-log-meta">${Trainw.escapeHtml(time)} · ${Trainw.escapeHtml(item.device_id || 'device inconnu')}</div>
          ${reason ? `<div class="access-log-reason">${Trainw.escapeHtml(reason)}</div>` : ''}
        </div>
        <div class="access-log-pill ${item.access_granted ? 'granted' : 'denied'}">${Trainw.escapeHtml(item.access_granted ? 'Granted' : 'Denied')}</div>
      </article>
    `;
  }).join('');
}

function buildGateTerminalUrl() {
  const url = new URL('/gate', window.location.origin);
  url.searchParams.set('gym_id', currentGymId || '');
  url.searchParams.set('gym_name', currentGymName || document.getElementById('sidebar-gym-name')?.textContent || 'TRAINW');
  url.searchParams.set('pin', document.getElementById('terminal-admin-pin')?.value.trim() || '');
  url.searchParams.set('device_id', document.getElementById('terminal-device-id')?.value.trim() || 'gate-1');
  return url.toString();
}

function updateGateTerminalPreview() {
  const preview = document.getElementById('terminal-url-preview');
  if (!preview) return;
  preview.textContent = buildGateTerminalUrl();
}

async function copyGateTerminalUrl() {
  const url = buildGateTerminalUrl();
  try {
    await navigator.clipboard.writeText(url);
    toast('URL copiée');
  } catch (error) {
    toast('Impossible de copier l’URL', 'err');
  }
}

function openGateTerminal() {
  window.open(buildGateTerminalUrl(), '_blank', 'noopener');
}

function renderCheckIns() {
  const el = document.getElementById('checkins-today-list');
  if (!el) return;

  if (!checkInsList.length) {
    renderCoreEmptyState(el, {
      icon: '📍',
      title: 'Aucun check-in',
      body: 'Les presences du jour apparaitront ici.',
    });
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
  conversationMap[clientId] = (conversationMap[clientId] || []).map(message => {
    if (message.receiver_id === currentUser.id && message.sender_id === clientId) return { ...message, is_read: true };
    return message;
  });

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
    if (error?.code === '23505') {
      toast(t('alreadyCheckedIn'), 'err');
      return;
    }
    toast(error.message || t('errorMsg'), 'err');
  } finally {
    if (btn) btn.textContent = t('confirmCheckIn');
    Trainw.ui.setBusy(btn, false);
  }
}

async function loadAnalytics() {
  if (!currentGymId) return;
  const ninetyDaysAgo = Trainw.dateOnly(Trainw.addDays(new Date(), -90));

  const [directoryResult, coachCountResult, sessionsResult] = await Promise.all([
    Trainw.api.run(sb.rpc('list_gym_member_directory', { p_gym_id: currentGymId }), { context: 'load analytics member directory', fallback: [] }),
    Trainw.api.run(sb.from('users').select('id', { count: 'exact', head: true }).eq('role', 'coach').eq('gym_id', currentGymId), { context: 'count gym coaches', fallback: null }),
    Trainw.api.run(sb.from('sessions').select('type,status,coach_id,session_date,users!sessions_coach_id_fkey(name)').eq('gym_id', currentGymId).gte('session_date', ninetyDaysAgo), { context: 'load analytics sessions', fallback: [] }),
  ]);

  const directory = Array.isArray(directoryResult.data) ? directoryResult.data : [];
  const activeClients = directory.filter(member => member.portal === 'client' && member.user_id && member.status === 'active');
  const totalClients = activeClients.length;
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
  const clientIds = activeClients.map(client => client.user_id);
  const profileResult = clientIds.length
    ? await Trainw.api.run(
        sb.from('client_profiles')
          .select('user_id, payment_status, membership_start_date, membership_end_date, price_paid')
          .eq('gym_id', currentGymId)
          .in('user_id', clientIds),
        { context: 'load analytics client profiles', fallback: [] }
      )
    : { data: [], error: null };
  const clientProfiles = Array.isArray(profileResult.data) ? profileResult.data : [];
  const profileMap = new Map(clientProfiles.map(profile => [profile.user_id, profile]));
  const realRevenue = clientProfiles
    .filter(profile => profile.payment_status === 'paid' && profile.membership_start_date >= monthStart)
    .reduce((sum, row) => sum + (Number(row.price_paid) || 0), 0);
  const retention = totalClients > 0 ? `${Math.min(100, Math.round((weekSessions / Math.max(1, totalClients)) * 100))}%` : '-';
  Trainw.ui.setText('pred-monthly', realRevenue > 0 ? `${realRevenue} DT` : '-', '-');
  Trainw.ui.setText('pred-sessions', String(weekSessions), '0');
  Trainw.ui.setText('pred-retention', retention, '-');

  const expiringMembers = activeClients.filter(client => {
    const end = profileMap.get(client.user_id)?.membership_end_date;
    if (!end) return false;
    const diff = Math.ceil((new Date(end) - now) / 86400000);
    return diff <= 14 && diff >= -30;
  });
  const expiringSoon = expiringMembers.filter(client => {
    const diff = Math.ceil((new Date(profileMap.get(client.user_id)?.membership_end_date) - now) / 86400000);
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
    currentGymName = name;
    Trainw.ui.setText('sidebar-gym-name', name, '-');
    updateGateTerminalPreview();
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
    if (!window.confirm('Send automated messages to ' + inactiveClients.length + ' inactive clients?')) return;

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
  // Staff role guard: hard redirect to dashboard if accessing restricted page
  const isStaff = currentMembership?.role_code === 'staff';
  const staffAllowedPages = new Set(['dashboard', 'checkin']);
  if (isStaff && !staffAllowedPages.has(page)) {
    page = 'dashboard';
  }
  const nextPage = page === 'settings' && !canOpenSettingsPage() ? 'dashboard' : page;
  document.querySelectorAll('.page').forEach(node => node.classList.add('hidden'));
  document.getElementById(nextPage + '-page')?.classList.remove('hidden');
  document.querySelectorAll('.nav-item').forEach(node => {
    if (node.dataset.page === 'settings') {
      node.classList.toggle('hidden', !canOpenSettingsPage());
    }
    node.classList.toggle('active', node.dataset.page === nextPage);
  });
  syncPermissionVisibility();

  if (nextPage === 'analytics') loadAnalytics();
  if (nextPage === 'messages') updateMessageBadge();
  if (nextPage === 'checkin') {
    renderCheckInTabs();
    renderCredentialClientList();
    renderGateAccessLog();
    updateGateTerminalPreview();
  }
  if (nextPage === 'coaches') startCarouselAutoplay();
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
  syncPermissionVisibility();

  document.querySelectorAll('.nav-item').forEach(item => {
    item.addEventListener('click', () => showPage(item.dataset.page));
  });

  document.getElementById('btn-logout')?.addEventListener('click', async () => {
    try {
      clearGymRealtimeSubscriptions();
      const result = await Trainw.api.run(sb.auth.signOut({ scope: 'global' }), { context: 'gym sign out' });
      if (result.error) throw result.error;
      localStorage.removeItem('trainw_active_gym');
      window.location.href = GYM_LOGIN_HREF;
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
  document.querySelectorAll('[data-checkin-tab]').forEach(button => {
    button.addEventListener('click', () => setCheckInTab(button.dataset.checkinTab || 'live'));
  });
  document.querySelectorAll('[data-settings-team-tab]').forEach(button => {
    button.addEventListener('click', () => switchSettingsStaffTab(button.dataset.settingsTeamTab || 'team'));
  });
  document.getElementById('credential-client-search')?.addEventListener('input', renderCredentialClientList);
  document.getElementById('credential-type')?.addEventListener('change', updateCredentialModalHint);
  document.getElementById('access-log-filter')?.addEventListener('change', renderGateAccessLog);
  document.getElementById('terminal-admin-pin')?.addEventListener('input', updateGateTerminalPreview);
  document.getElementById('terminal-device-id')?.addEventListener('input', updateGateTerminalPreview);
  document.getElementById('btn-copy-terminal-url')?.addEventListener('click', copyGateTerminalUrl);
  document.getElementById('btn-open-terminal')?.addEventListener('click', openGateTerminal);
  document.getElementById('btn-open-credential-modal')?.addEventListener('click', () => {
    clearInlineError(document.getElementById('credential-modal-error'));
    Trainw.ui.setValue('credential-data', '', '');
    Trainw.ui.setValue('credential-label', '', '');
    Trainw.ui.setValue('credential-type', 'rfid_card', 'rfid_card');
    updateCredentialModalHint();
    document.getElementById('credential-modal')?.classList.add('show');
  });
  document.getElementById('btn-save-credential')?.addEventListener('click', saveMemberCredential);
  document.getElementById('sess-type')?.addEventListener('change', updateSessionCategory);
  document.getElementById('btn-create-session')?.addEventListener('click', () => document.getElementById('create-session-modal')?.classList.add('show'));
  document.getElementById('btn-add-coach')?.addEventListener('click', () => document.getElementById('add-coach-modal')?.classList.add('show'));
  document.getElementById('btn-add-client')?.addEventListener('click', () => document.getElementById('add-client-modal')?.classList.add('show'));
  document.getElementById('btn-submit-session')?.addEventListener('click', submitNewSession);
  document.getElementById('btn-submit-coach')?.addEventListener('click', submitNewCoach);
  document.getElementById('btn-submit-client')?.addEventListener('click', submitNewClient);
  document.getElementById('btn-submit-checkin')?.addEventListener('click', submitManualCheckIn);
  document.getElementById('btn-save-settings')?.addEventListener('click', saveSettings);
  document.getElementById('btn-upload-logo')?.addEventListener('click', uploadGymLogo);
  document.getElementById('btn-save-pricing')?.addEventListener('click', savePricing);
  document.getElementById('btn-change-password')?.addEventListener('click', changePassword);
  document.getElementById('btn-trigger-auto-msg')?.addEventListener('click', triggerInactivityMessages);
  document.getElementById('btn-save-edit-session')?.addEventListener('click', saveEditSession);
  document.getElementById('btn-save-edit-coach')?.addEventListener('click', saveEditCoach);
  document.getElementById('btn-save-edit-client')?.addEventListener('click', saveEditClient);
  document.getElementById('btn-send-message')?.addEventListener('click', sendMessage);
  document.getElementById('btn-send-member-invite')?.addEventListener('click', submitMemberInvite);
  document.getElementById('btn-new-role')?.addEventListener('click', () => {
    resetRoleBuilderForm();
    switchSettingsStaffTab('roles');
  });
  document.querySelectorAll('[data-role-portal]').forEach(button => {
    button.addEventListener('click', () => {
      if (button.disabled) return;
      updateRoleBuilderPortalButtons(button.dataset.rolePortal || 'admin');
    });
  });
  document.getElementById('btn-save-role-builder')?.addEventListener('click', saveRoleBuilder);
  document.getElementById('btn-upload-staff-avatar')?.addEventListener('click', prepareStaffAvatarSelection);
  document.getElementById('staff-avatar-file')?.addEventListener('change', prepareStaffAvatarSelection);
  document.getElementById('btn-save-staff-profile')?.addEventListener('click', () => {
    void saveStaffProfile(document.getElementById('staff-panel-user-id')?.value || activeStaffPanelUserId);
  });
  document.getElementById('msg-input')?.addEventListener('keydown', event => {
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault();
      sendMessage();
    }
  });
  document.getElementById('credential-client-list')?.addEventListener('click', event => {
    const button = event.target.closest('[data-credential-client]');
    if (!button) return;
    selectedCredentialClientId = button.dataset.credentialClient || null;
    renderCredentialClientList();
    void loadClientCredentials();
  });
  document.getElementById('credential-list')?.addEventListener('click', event => {
    const toggleButton = event.target.closest('[data-credential-toggle]');
    if (toggleButton) {
      toggleMemberCredential(toggleButton.dataset.credentialToggle, toggleButton.dataset.nextActive);
      return;
    }
    const deleteButton = event.target.closest('[data-credential-delete]');
    if (deleteButton) {
      deleteMemberCredential(deleteButton.dataset.credentialDelete);
    }
  });
  document.getElementById('role-builder-list')?.addEventListener('click', event => {
    const emptyAction = event.target.closest('[data-empty-action="create-role"]');
    if (emptyAction) {
      resetRoleBuilderForm();
      switchSettingsStaffTab('roles');
      return;
    }
    const deleteButton = event.target.closest('[data-role-delete]');
    if (deleteButton) {
      void deleteCustomRole(deleteButton.dataset.roleDelete || '');
      return;
    }
    const editButton = event.target.closest('[data-role-edit]');
    if (editButton) {
      openRoleBuilder(editButton.dataset.roleEdit || '');
      return;
    }
    const card = event.target.closest('[data-role-builder-card]');
    if (card) {
      openRoleBuilder(card.dataset.roleBuilderCard || '');
    }
  });
  document.getElementById('staff-directory-list')?.addEventListener('click', event => {
    const emptyAction = event.target.closest('[data-empty-action="invite-member"]');
    if (emptyAction) {
      switchSettingsStaffTab('team');
      document.getElementById('invite-member-name')?.focus();
      return;
    }
    const editButton = event.target.closest('[data-staff-edit-profile]');
    if (editButton) {
      void openStaffPanel(editButton.dataset.staffEditProfile || '');
      return;
    }
    const roleButton = event.target.closest('[data-staff-role-edit]');
    if (roleButton) {
      activeStaffRoleEditMembershipId = roleButton.dataset.staffRoleEdit || null;
      renderStaffDirectory();
      return;
    }
    const revokeButton = event.target.closest('[data-staff-revoke]');
    if (revokeButton) {
      void revokeMembership(revokeButton.dataset.staffRevoke || '');
    }
  });
  document.getElementById('staff-directory-list')?.addEventListener('change', event => {
    const roleSelect = event.target.closest('[data-staff-role-select]');
    if (roleSelect) {
      void updateMembershipRole(roleSelect.dataset.staffRoleSelect || '', roleSelect.value || '');
    }
  });
  document.getElementById('staff-pending-list')?.addEventListener('click', event => {
    const resendButton = event.target.closest('[data-pending-resend]');
    if (resendButton) {
      void resendInvitation(resendButton.dataset.pendingResend || '', resendButton.dataset.pendingEmail || '');
      return;
    }
    const cancelButton = event.target.closest('[data-pending-cancel]');
    if (cancelButton) {
      void revokeMembership(cancelButton.dataset.pendingCancel || '');
    }
  });
  document.getElementById('staff-schedule-grid')?.addEventListener('change', event => {
    const toggle = event.target.closest('[data-staff-schedule-enabled]');
    if (toggle) {
      toggleStaffScheduleRow(toggle.dataset.staffScheduleEnabled || '', !!toggle.checked);
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
  const previousStaffTab = activeSettingsStaffTab;
  currentLang = lang;
  localStorage.setItem('trainw_lang', lang);
  applyTranslations();
  renderSchedule();
  renderClients();
  renderCheckIns();
  renderCredentialClientList();
  renderCredentialList();
  renderGateAccessLog();
  renderStaffStats();
  renderStaffDirectory();
  renderPendingInvites();
  renderRoleBuilderList();
  if (activeRoleBuilderId && roleMatrix.some(role => role.role_id === activeRoleBuilderId)) {
    openRoleBuilder(activeRoleBuilderId);
  } else if (roleMatrix.length) {
    openRoleBuilder(roleMatrix[0].role_id);
  } else {
    resetRoleBuilderForm();
  }
  if (activeStaffPanelUserId) {
    void openStaffPanel(activeStaffPanelUserId);
  }
  populateMessagesList(document.getElementById('msg-contact-search')?.value || '');
  if (activeConvId) renderConversation(activeConvId);
  activeSettingsStaffTab = previousStaffTab;
  switchSettingsStaffTab(previousStaffTab);
  syncPermissionVisibility();
}

async function initPage() {
  enhanceSidebarNavigation();
  ensureMobileSettingsShortcuts();
  bindUi();

  const context = await Trainw.auth.getContext(sb, {
    expectedRoles: ['gym_owner', 'gym', 'admin'],
    loginHref: GYM_LOGIN_HREF,
  });
  if (!context.session || !context.profile) return;

  currentUser = context.session.user;
  currentMembership = context.activeMembership || null;
  currentPermissions = Array.isArray(context.permissions) ? context.permissions : [];
  currentGymId = context.profile.gym_id || null;
  currentLang = localStorage.getItem('trainw_lang') || context.profile.language_preference || currentLang;
  syncPermissionVisibility();

  document.querySelector('.main-content')?.classList.add('page-loaded');
  Trainw.ui.setValue('account-email', currentUser.email || '', '');
  applyTranslations();
  renderCheckInTabs();
  updateCredentialModalHint();
  updateSessionCategory();
  setDefaultDates();
  Trainw.ui.setValue('terminal-device-id', document.getElementById('terminal-device-id')?.value || 'gate-1', 'gate-1');

  if (currentGymId) {
    const gymResult = await Trainw.api.run(sb.from('gyms').select('name, address, phone, description, subscription_tier, price_monthly, price_quarterly, price_annual, logo_storage_bucket, logo_storage_path').eq('id', currentGymId).maybeSingle(), { context: 'load gym profile', fallback: null });
    const gym = gymResult.data;
    if (gym) {
      currentGymName = gym.name || '';
      Trainw.ui.setText('sidebar-gym-name', gym.name || '-', '-');
      // ── Sidebar gym logo ─────────────────────────────────────────────────
      if (gym.logo_storage_bucket && gym.logo_storage_path) {
        try {
          const logoSigned = await Trainw.media.createSignedMediaUrl(sb, gym.logo_storage_bucket, gym.logo_storage_path, 3600);
          const logoUrl = (typeof logoSigned === 'string') ? logoSigned : (logoSigned?.url || null);
          if (logoUrl) {
            const sidebarLogo = document.getElementById('sidebar-gym-logo');
            const logoFallback = document.getElementById('sidebar-logo-fallback');
            if (sidebarLogo) { sidebarLogo.src = logoUrl; sidebarLogo.classList.remove('hidden'); }
            if (logoFallback) logoFallback.classList.add('hidden');
          }
        } catch (_) { /* graceful fallback to TRAINW text */ }
      }
      // ─────────────────────────────────────────────────────────────────────
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
    currentGymName = context.profile.name || '';
    Trainw.ui.setText('sidebar-gym-name', context.profile.name || '-', '-');
  }
  updateGateTerminalPreview();

  const startup = await Promise.allSettled([
    loadGymCoaches(),
    loadDashboardStats(),
    loadSchedule(),
    loadCoaches(),
    loadClients(),
    loadCheckIns(),
    loadGateAccessLog(),
    loadAccessControlData({ includeStaffDirectory: false }),
    loadStaffDirectory(),
  ]);
  subscribeToGateCheckIns();
  if (!window.__trainwGymUnloadBound) {
    window.__trainwGymUnloadBound = true;
    window.addEventListener('beforeunload', clearGymRealtimeSubscriptions);
  }
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
        clearGymRealtimeSubscriptions();
        localStorage.removeItem('trainw_active_gym');
        window.location.href = GYM_LOGIN_HREF;
      },
    });
  }
}

initPage();
