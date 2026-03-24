const T = {
  en: {
    backBtn: 'Back to Home',
    cardTitle: 'Bienvenue',
    cardSub: 'Choisissez votre type de compte',
    roleLabel: 'Select Your Role',
    gymTitle: 'Gym Owner',
    gymDesc: 'Manage your gym, coaches, and revenue',
    coachTitle: 'Coach',
    coachDesc: 'Track clients, sessions, and earnings',
    clientTitle: 'Client',
    clientDesc: 'Book sessions and track your progress',
    newHere: 'New to Trainw?',
    learnMore: 'Learn more',
  },
  fr: {
    backBtn: "Retour à l'Accueil",
    cardTitle: 'Bienvenue',
    cardSub: 'Choisissez votre type de compte pour continuer',
    roleLabel: 'Sélectionnez Votre Rôle',
    gymTitle: 'Propriétaire de Salle',
    gymDesc: 'Gérez votre salle, coachs et revenus',
    coachTitle: 'Coach',
    coachDesc: 'Suivez clients, séances et revenus',
    clientTitle: 'Client',
    clientDesc: 'Réservez séances et suivez vos progrès',
    newHere: 'Nouveau sur Trainw ?',
    learnMore: 'En savoir plus',
  },
  ar: {
    backBtn: 'العودة للرئيسية',
    cardTitle: 'مرحباً بك',
    cardSub: 'اختر نوع حسابك للمتابعة',
    roleLabel: 'اختر دورك',
    gymTitle: 'مالك الصالة',
    gymDesc: 'إدارة الصالة والمدربين والإيرادات',
    coachTitle: 'مدرب',
    coachDesc: 'تتبع العملاء والجلسات والأرباح',
    clientTitle: 'عميل',
    clientDesc: 'احجز الجلسات وتابع تقدمك',
    newHere: 'جديد على Trainw؟',
    learnMore: 'اعرف المزيد',
  }
};

let lang = localStorage.getItem('trainw_lang') || 'fr';

function applyTranslations() {
  document.querySelectorAll('[data-i18n]').forEach(el => {
    const key = el.getAttribute('data-i18n');
    if (T[lang]?.[key] !== undefined) el.textContent = T[lang][key];
  });
  document.documentElement.setAttribute('dir', lang === 'ar' ? 'rtl' : 'ltr');
  document.documentElement.setAttribute('lang', lang);
}

document.querySelectorAll('.lang-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    lang = btn.dataset.lang;
    localStorage.setItem('trainw_lang', lang);
    document.querySelectorAll('.lang-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    document.querySelectorAll('.lang-btn').forEach(b => b.classList.remove('active'));
document.querySelector(`.lang-btn[data-lang="${lang}"]`)?.classList.add('active');
applyTranslations();
  });
});

document.querySelectorAll('.lang-btn').forEach(b => b.classList.remove('active'));
document.querySelector(`.lang-btn[data-lang="${lang}"]`)?.classList.add('active');
applyTranslations();
