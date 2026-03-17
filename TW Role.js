const T = {
  en: {
    backBtn: 'Back to Home',
    cardTitle: 'Welcome Back',
    cardSub: 'Choose your account type to continue',
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
    cardTitle: 'Bon Retour',
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
  }
};

let lang = 'en';

function applyTranslations() {
  document.querySelectorAll('[data-i18n]').forEach(el => {
    const key = el.getAttribute('data-i18n');
    if (T[lang][key] !== undefined) el.textContent = T[lang][key];
  });
}

document.querySelectorAll('.lang-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    lang = btn.dataset.lang;
    document.querySelectorAll('.lang-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    applyTranslations();
  });
});

applyTranslations();
