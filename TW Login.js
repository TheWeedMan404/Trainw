// ── Supabase ──────────────────────────────────────────────
const Trainw = window.TrainwCore;
const sb = Trainw.createClient();
Trainw.installGlobalErrorHandlers();

// ── i18n ──────────────────────────────────────────────────
const T = {
  en: {
    navBack:'Back',
    tabLogin:'Sign In', tabSignup:'Create Account',
    loginTitle:'WELCOME BACK', loginSub:'Sign in to your Trainw dashboard',
    signupTitle:'JOIN TRAINW', signupSub:'Create your account in seconds',
    lEmail:'Email', lPw:'Password', lName:'Full Name',
    lConfirm:'Confirm Password', lRole:'I am a', lGymName:'Gym Name',
    btnLogin:'Sign In', btnSignup:'Create Account',
    forgotPw:'Forgot password?',
    eEmailReq:'Email is required',
    eEmailFmt:'Enter a valid email address',
    ePwReq:'Password is required',
    ePwShort:'At least 8 characters required',
    ePwMatch:'Passwords do not match',
    eNameReq:'Full name is required',
    eGymNameReq:'Gym name is required',
    eGeneric:'Something went wrong — try again',
    eBadCreds:'Incorrect email or password',
    eEmailTaken:'An account with this email already exists',
    eNoProfile:'Account not found. Please sign up first.',
    okForgot:'Reset email sent — check your inbox',
    okSignup:'Account created! Signing you in…',
    okLogin:'Signed in! Redirecting…',
  },
  fr: {
    navBack:'Retour',
    tabLogin:'Se Connecter', tabSignup:'Créer un Compte',
    loginTitle:'BON RETOUR', loginSub:'Accédez à votre tableau Trainw',
    signupTitle:'REJOINDRE TRAINW', signupSub:'Créez votre compte en quelques secondes',
    lEmail:'Email', lPw:'Mot de passe', lName:'Nom Complet',
    lConfirm:'Confirmer le mot de passe', lRole:'Je suis', lGymName:'Nom de la Salle',
    btnLogin:'Se Connecter', btnSignup:'Créer un Compte',
    forgotPw:'Mot de passe oublié ?',
    eEmailReq:"L'email est requis",
    eEmailFmt:'Entrez une adresse email valide',
    ePwReq:'Le mot de passe est requis',
    ePwShort:'Au moins 8 caractères requis',
    ePwMatch:'Les mots de passe ne correspondent pas',
    eNameReq:'Le nom complet est requis',
    eGymNameReq:'Le nom de la salle est requis',
    eGeneric:"Une erreur s'est produite — réessayez",
    eBadCreds:'Email ou mot de passe incorrect',
    eEmailTaken:'Un compte avec cet email existe déjà',
    eNoProfile:'Compte introuvable. Veuillez vous inscrire.',
    okForgot:'Email envoyé — vérifiez votre boîte',
    okSignup:'Compte créé ! Connexion en cours…',
    okLogin:'Connecté ! Redirection…',
  },
  ar: {
    navBack:'رجوع',
    tabLogin:'تسجيل الدخول', tabSignup:'إنشاء حساب',
    loginTitle:'مرحباً بعودتك', loginSub:'سجّل دخولك إلى لوحة Trainw',
    signupTitle:'انضم إلى Trainw', signupSub:'أنشئ حسابك في ثوانٍ',
    lEmail:'البريد الإلكتروني', lPw:'كلمة المرور', lName:'الاسم الكامل',
    lConfirm:'تأكيد كلمة المرور', lRole:'أنا', lGymName:'اسم الصالة',
    btnLogin:'تسجيل الدخول', btnSignup:'إنشاء حساب',
    forgotPw:'نسيت كلمة المرور؟',
    eEmailReq:'البريد الإلكتروني مطلوب',
    eEmailFmt:'أدخل بريداً إلكترونياً صحيحاً',
    ePwReq:'كلمة المرور مطلوبة',
    ePwShort:'8 أحرف على الأقل',
    ePwMatch:'كلمتا المرور غير متطابقتين',
    eNameReq:'الاسم مطلوب',
    eGymNameReq:'اسم الصالة مطلوب',
    eGeneric:'حدث خطأ — أعد المحاولة',
    eBadCreds:'بريد إلكتروني أو كلمة مرور غير صحيحة',
    eEmailTaken:'حساب بهذا البريد موجود مسبقاً',
    eNoProfile:'الحساب غير موجود. يرجى التسجيل أولاً.',
    okForgot:'تم إرسال رابط الاسترداد — تحقق من بريدك',
    okSignup:'تم إنشاء الحساب! جارٍ تسجيل الدخول…',
    okLogin:'تم تسجيل الدخول! جارٍ التوجيه…',
  }
};

let lang = localStorage.getItem('trainw_lang') || 'fr';
const t = k => T[lang][k] || T.en[k] || k;

function applyTranslations() {
  document.querySelectorAll('[data-i18n]').forEach(el => {
    const k = el.getAttribute('data-i18n');
    if (T[lang]?.[k]) el.textContent = T[lang][k];
  });
  document.documentElement.setAttribute('dir', lang === 'ar' ? 'rtl' : 'ltr');
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

// ── Tabs ──────────────────────────────────────────────────
document.querySelectorAll('.tab').forEach(btn => {
  btn.addEventListener('click', () => switchTab(btn.dataset.tab));
});

function switchTab(tab) {
  document.querySelectorAll('.tab').forEach(b => b.classList.remove('active'));
  document.querySelectorAll('.panel').forEach(p => p.classList.remove('active'));
  document.getElementById('tab-' + tab).classList.add('active');
  document.getElementById('panel-' + tab).classList.add('active');
  clearAll();
}

// ── Role badge + gym name reveal ──────────────────────────
document.getElementById('s-role').addEventListener('change', onRoleChange);

function onRoleChange() {
  const role = document.getElementById('s-role').value;
  const wrap = document.getElementById('gym-name-wrap');
  wrap.classList.toggle('visible', role === 'gym_owner');
  if (role !== 'gym_owner') clearF('s-gym-name');
}

// Pre-select role from URL ?role=
(function () {
  const role = new URLSearchParams(location.search).get('role');
  if (role) {
    const roleLabels = { gym_owner: { fr:'Propriétaire de Salle', en:'Gym Owner', ar:'مالك الصالة' }, coach: { fr:'Coach', en:'Coach', ar:'مدرب' }, client: { fr:'Client', en:'Client', ar:'عميل' } };
    document.getElementById('rbadge').textContent = '↳ ' + (roleLabels[role]?.[lang] || role.replace('_',' ').toUpperCase());
    const sel = document.getElementById('s-role');
    for (const o of sel.options) if (o.value === role) { o.selected = true; break; }
    onRoleChange();
  }
})();

// ── Routing ───────────────────────────────────────────────
function route(role) {
  const map = {
    gym_owner: 'dashboard.html',
    gym:       'dashboard.html',
    admin:     'dashboard.html',
    coach:     'coach.html',
    client:    'client.html',
  };
  const dest = map[role];
  if (dest) window.location.href = dest;
  else showErr('l-err', 'Unknown role: ' + role);
}

// ── Validation ────────────────────────────────────────────
const emailRe = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

function valEmail(id) {
  const v = document.getElementById(id).value.trim();
  if (!v)               return showFerr(id, t('eEmailReq')), false;
  if (!emailRe.test(v)) return showFerr(id, t('eEmailFmt')), false;
  clearF(id); return true;
}

function showFerr(id, msg) {
  const e = document.getElementById(id + '-e');
  const i = document.getElementById(id);
  if (e) { e.textContent = msg; e.classList.add('show'); }
  if (i) { i.classList.add('err'); i.classList.remove('ok'); }
}
function clearF(id) {
  const e = document.getElementById(id + '-e');
  const i = document.getElementById(id);
  if (e) { e.textContent = ''; e.classList.remove('show'); }
  if (i) i.classList.remove('err');
}
function clearAll() {
  document.querySelectorAll('.ferr').forEach(e => { e.textContent=''; e.classList.remove('show'); });
  document.querySelectorAll('.input').forEach(i => i.classList.remove('err','ok'));
  document.querySelectorAll('.alert').forEach(a => a.classList.remove('show'));
}
function showErr(id, msg) { const el = document.getElementById(id); el.textContent = msg; el.classList.add('show'); }
function showOk(id, msg)  { const el = document.getElementById(id); el.textContent = msg; el.classList.add('show'); }
function busy(id, on) { const b = document.getElementById(id); b.classList.toggle('loading', on); b.disabled = on; }

// ── Password eye toggle ───────────────────────────────────
document.querySelectorAll('.eye').forEach(btn => {
  btn.addEventListener('click', () => {
    const input = document.getElementById(btn.dataset.target);
    input.type = input.type === 'password' ? 'text' : 'password';
    btn.textContent = input.type === 'password' ? 'ðŸ‘' : 'ðŸ™ˆ';
  });
});

// Password strength indicator
document.getElementById('s-pw').addEventListener('input', function () {
  clearF('s-pw');
  this.classList.toggle('ok', this.value.length >= 8);
});

// ── LOGIN ─────────────────────────────────────────────────
async function doLogin() {
  clearAll();
  const email = document.getElementById('l-email').value.trim();
  const pw    = document.getElementById('l-pw').value;

  let ok = true;
  if (!email)               { showFerr('l-email', t('eEmailReq')); ok = false; }
  else if (!emailRe.test(email)) { showFerr('l-email', t('eEmailFmt')); ok = false; }
  if (!pw)                  { showFerr('l-pw', t('ePwReq')); ok = false; }
  if (!ok) return;

  busy('btn-login', true);
  try {
    const { data, error } = await sb.auth.signInWithPassword({ email, password: pw });

    if (error) {
      const msg = error.message.toLowerCase();
      showErr('l-err', (msg.includes('invalid') || msg.includes('credentials')) ? t('eBadCreds') : error.message);
      return;
    }

    // ── FIX: fetch role then redirect ──
    const { profile, error: pErr } = await Trainw.auth.getProfile(sb, data.user.id, false);

    if (pErr || !profile) {
      await sb.auth.signOut();
      showErr('l-err', t('eNoProfile'));
      return;
    }

    showOk('l-ok', t('okLogin'));
    setTimeout(() => route(profile.role), 800);

  } catch (e) {
    showErr('l-err', t('eGeneric'));
    console.error(e);
  } finally {
    busy('btn-login', false);
  }
}

// ── SIGNUP ────────────────────────────────────────────────
async function doSignup() {
  clearAll();
  const name    = document.getElementById('s-name').value.trim();
  const email   = document.getElementById('s-email').value.trim();
  const pw      = document.getElementById('s-pw').value;
  const pw2     = document.getElementById('s-pw2').value;
  const role    = document.getElementById('s-role').value;
  const gymName = document.getElementById('s-gym-name').value.trim();

  let ok = true;
  if (!name)                    { showFerr('s-name',    t('eNameReq'));    ok = false; }
  if (!email)                   { showFerr('s-email',   t('eEmailReq'));   ok = false; }
  else if (!emailRe.test(email)){ showFerr('s-email',   t('eEmailFmt'));   ok = false; }
  if (!pw)                      { showFerr('s-pw',      t('ePwReq'));      ok = false; }
  else if (pw.length < 8)       { showFerr('s-pw',      t('ePwShort'));    ok = false; }
  if (pw !== pw2)               { showFerr('s-pw2',     t('ePwMatch'));    ok = false; }
  if (role === 'gym_owner' && !gymName) { showFerr('s-gym-name', t('eGymNameReq')); ok = false; }
  if (!ok) return;

  busy('btn-signup', true);
  try {
    const metadata = { name, role };
    if (role === 'gym_owner') metadata.gym_name = gymName;

    const { data, error } = await sb.auth.signUp({
      email,
      password: pw,
      options: { data: metadata }
    });

    if (error) {
      showErr('s-err', error.message.toLowerCase().includes('already') ? t('eEmailTaken') : error.message);
      return;
    }

    const uid = data.user?.id;
    if (!uid) { showErr('s-err', t('eGeneric')); return; }

    showOk('s-ok', t('okSignup'));

    setTimeout(async () => {
      const { data: signIn, error: signInErr } = await sb.auth.signInWithPassword({ email, password: pw });
      if (signInErr || !signIn?.user) {
        switchTab('login');
        document.getElementById('l-email').value = email;
        showOk('l-ok', t('okSignup'));
        return;
      }
      // Give trigger 500ms to finish writing rows
      await new Promise(r => setTimeout(r, 500));
      const { profile } = await Trainw.auth.getProfile(sb, signIn.user.id, true);
      route(profile?.role || role);
    }, 800);

  } catch (e) {
    showErr('s-err', t('eGeneric'));
    console.error(e);
  } finally {
    busy('btn-signup', false);
  }
}

// ── FORGOT ────────────────────────────────────────────────
document.getElementById('forgot-link').addEventListener('click', async () => {
  const email = document.getElementById('l-email').value.trim();
  if (!email || !emailRe.test(email)) {
    showFerr('l-email', t('eEmailFmt'));
    document.getElementById('l-email').focus();
    return;
  }

  try {
    const { error } = await sb.auth.resetPasswordForEmail(email);
    if (error) throw error;
    showOk('l-ok', t('okForgot'));
  } catch (error) {
    console.error('Forgot password error:', error);
    showErr('l-err', t('eGeneric'));
  }
});

// ── Enter key ─────────────────────────────────────────────
document.addEventListener('keydown', e => {
  if (e.key !== 'Enter') return;
  document.getElementById('panel-login').classList.contains('active') ? doLogin() : doSignup();
});

// ── Login button ──────────────────────────────────────────
document.getElementById('btn-login').addEventListener('click', doLogin);
document.getElementById('btn-signup').addEventListener('click', doSignup);

document.querySelectorAll('.lang-btn').forEach(b => b.classList.remove('active'));
document.querySelector(`.lang-btn[data-lang="${lang}"]`)?.classList.add('active');
applyTranslations();

(async function restoreExistingSession() {
  const { session, profile } = await Trainw.auth.getContext(sb, {
    loginHref: null,
    redirectOnMissing: false,
    redirectOnMismatch: false,
  });

  if (session && profile?.role) {
    route(profile.role);
  }
})();

