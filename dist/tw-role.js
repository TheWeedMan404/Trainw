const Trainw = window.TrainwCore;
Trainw.installGlobalErrorHandlers();
let cachedSupabaseClient = null;

function getSupabaseClient() {
  if (cachedSupabaseClient) return cachedSupabaseClient;
  cachedSupabaseClient = Trainw.createClient();
  return cachedSupabaseClient;
}

const T = {
  fr: {
    backBtn: "Retour a l'accueil",
    cardTitle: 'Bienvenue',
    cardSub: 'Choisissez votre type de compte pour continuer.',
    roleLabel: 'Selectionnez votre role',
    gymTitle: 'Proprietaire de salle',
    gymDesc: 'Gerez votre salle, vos coachs, vos classes et vos revenus.',
    coachTitle: 'Coach',
    coachDesc: 'Suivez vos clients, vos programmes et vos seances.',
    clientTitle: 'Client',
    clientDesc: 'Suivez votre progression, vos seances et votre programme.',
    newHere: 'Nouveau sur Trainw ?',
    learnMore: 'En savoir plus',
  },
  en: {
    backBtn: 'Back to home',
    cardTitle: 'Welcome',
    cardSub: 'Choose your account type to continue.',
    roleLabel: 'Select your role',
    gymTitle: 'Gym owner',
    gymDesc: 'Manage your gym, coaches, classes, and revenue.',
    coachTitle: 'Coach',
    coachDesc: 'Track your clients, plans, and sessions.',
    clientTitle: 'Client',
    clientDesc: 'Follow your progress, sessions, and program.',
    newHere: 'New to Trainw?',
    learnMore: 'Learn more',
  },
  ar: {
    backBtn: 'العودة للرئيسية',
    cardTitle: 'مرحبا بك',
    cardSub: 'اختر نوع حسابك للمتابعة.',
    roleLabel: 'اختر دورك',
    gymTitle: 'مالك الصالة',
    gymDesc: 'ادارة الصالة والمدربين والحصص والايرادات.',
    coachTitle: 'مدرب',
    coachDesc: 'تابع عملاءك وبرامجك وحصصك.',
    clientTitle: 'عميل',
    clientDesc: 'تابع تقدمك وحصصك وبرنامجك.',
    newHere: 'جديد على Trainw؟',
    learnMore: 'اعرف المزيد',
  },
};

let lang = localStorage.getItem('trainw_lang') || 'fr';

function t(key) {
  return T[lang]?.[key] || T.fr[key] || T.en[key] || '...';
}

function syncLangButtons() {
  document.querySelectorAll('.lang-btn').forEach(function (button) {
    button.classList.toggle('active', button.dataset.lang === lang);
  });
}

function applyTranslations() {
  document.querySelectorAll('[data-i18n]').forEach(function (element) {
    const key = element.getAttribute('data-i18n');
    element.textContent = t(key);
  });
  Trainw.applyDocumentLanguage(lang, document.body);
  syncLangButtons();
}

async function redirectIfAuthenticated() {
  let sb;
  try {
    sb = getSupabaseClient();
  } catch (error) {
    console.error('[Trainw] role bootstrap skipped', error);
    return;
  }
  const sessionResult = await Trainw.auth.getSession(sb);
  if (!sessionResult.session) return;

  const profileResult = await Trainw.auth.getProfile(sb, sessionResult.session.user.id, true);
  if (profileResult.profile?.role) {
    window.location.href = Trainw.roleToPath(profileResult.profile.role);
  }
}

document.querySelectorAll('.lang-btn').forEach(function (button) {
  button.addEventListener('click', function () {
    lang = button.dataset.lang || 'fr';
    localStorage.setItem('trainw_lang', lang);
    applyTranslations();
  });
});

applyTranslations();
redirectIfAuthenticated();
