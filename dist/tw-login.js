const Trainw = window.TrainwCore;
Trainw.installGlobalErrorHandlers();

let cachedSupabaseClient = null;
let lang = localStorage.getItem('trainw_lang') || 'fr';

function getSupabaseClient() {
  if (cachedSupabaseClient) return cachedSupabaseClient;
  cachedSupabaseClient = Trainw.createClient();
  return cachedSupabaseClient;
}

const sb = new Proxy({}, {
  get: function (_target, property) {
    return Reflect.get(getSupabaseClient(), property);
  },
});

const ROUTES = {
  role: '/role',
};

const T = {
  fr: {
    navBack: 'Retour',
    tabLogin: 'Connexion',
    tabSignup: 'Creer un compte',
    loginTitle: 'Bon retour',
    loginSub: 'Connectez-vous a votre espace Trainw',
    signupTitle: 'Rejoindre Trainw',
    signupSub: 'Creez votre compte en quelques secondes',
    lEmail: 'Email',
    lPw: 'Mot de passe',
    lName: 'Nom complet',
    lConfirm: 'Confirmer le mot de passe',
    lRole: 'Je suis',
    lGymName: 'Nom de la salle',
    btnLogin: 'Connexion',
    btnSignup: 'Creer un compte',
    forgotPw: 'Mot de passe oublie ?',
    phEmail: 'vous@exemple.com',
    phPassword: 'Votre mot de passe',
    phName: 'Ahmed Ben Ali',
    phMinPassword: 'Minimum 8 caracteres',
    phRepeatPassword: 'Repetez le mot de passe',
    phGymName: 'Ex: Trainw Ariana',
    roleGym: 'Proprietaire de salle',
    roleCoach: 'Coach',
    roleClient: 'Client',
    roleBadge: 'Role selectionne',
    eEmailReq: "L'email est requis.",
    eEmailFmt: 'Entrez une adresse email valide.',
    ePwReq: 'Le mot de passe est requis.',
    ePwShort: 'Le mot de passe doit contenir au moins 8 caracteres.',
    ePwMatch: 'Les mots de passe ne correspondent pas.',
    eNameReq: 'Le nom complet est requis.',
    eGymNameReq: 'Le nom de la salle est requis.',
    eGeneric: "Une erreur s'est produite. Reessayez.",
    eBadCreds: 'Email ou mot de passe incorrect.',
    eEmailTaken: 'Un compte avec cet email existe deja.',
    eNoProfile: 'Compte introuvable. Veuillez vous inscrire.',
    eEmailNotConfirmed: 'Votre email doit etre confirme avant la connexion.',
    eUserNotFound: 'Aucun compte trouve avec cet email.',
    eSignupDisabled: "L'inscription est temporairement indisponible.",
    okForgot: 'Email de reinitialisation envoye.',
    okSignup: 'Compte cree. Redirection en cours...',
    okLogin: 'Connexion reussie. Redirection...',
    eyeShow: 'Voir',
    eyeHide: 'Masquer',
  },
  en: {
    navBack: 'Back',
    tabLogin: 'Sign in',
    tabSignup: 'Create account',
    loginTitle: 'Welcome back',
    loginSub: 'Sign in to your Trainw workspace',
    signupTitle: 'Join Trainw',
    signupSub: 'Create your account in seconds',
    lEmail: 'Email',
    lPw: 'Password',
    lName: 'Full name',
    lConfirm: 'Confirm password',
    lRole: 'I am',
    lGymName: 'Gym name',
    btnLogin: 'Sign in',
    btnSignup: 'Create account',
    forgotPw: 'Forgot password?',
    phEmail: 'you@example.com',
    phPassword: 'Your password',
    phName: 'Ahmed Ben Ali',
    phMinPassword: 'Minimum 8 characters',
    phRepeatPassword: 'Repeat password',
    phGymName: 'Ex: Trainw Ariana',
    roleGym: 'Gym owner',
    roleCoach: 'Coach',
    roleClient: 'Client',
    roleBadge: 'Selected role',
    eEmailReq: 'Email is required.',
    eEmailFmt: 'Enter a valid email address.',
    ePwReq: 'Password is required.',
    ePwShort: 'Password must be at least 8 characters.',
    ePwMatch: 'Passwords do not match.',
    eNameReq: 'Full name is required.',
    eGymNameReq: 'Gym name is required.',
    eGeneric: 'Something went wrong. Please try again.',
    eBadCreds: 'Incorrect email or password.',
    eEmailTaken: 'An account with this email already exists.',
    eNoProfile: 'Account not found. Please sign up first.',
    eEmailNotConfirmed: 'Please confirm your email before signing in.',
    eUserNotFound: 'No account found with this email.',
    eSignupDisabled: 'Sign up is currently unavailable.',
    okForgot: 'Reset email sent.',
    okSignup: 'Account created. Redirecting...',
    okLogin: 'Signed in. Redirecting...',
    eyeShow: 'Show',
    eyeHide: 'Hide',
  },
  ar: {
    navBack: 'رجوع',
    tabLogin: 'تسجيل الدخول',
    tabSignup: 'انشاء حساب',
    loginTitle: 'اهلا بعودتك',
    loginSub: 'سجل دخولك الى مساحة Trainw',
    signupTitle: 'انضم الى Trainw',
    signupSub: 'انشئ حسابك في ثوان',
    lEmail: 'البريد الالكتروني',
    lPw: 'كلمة المرور',
    lName: 'الاسم الكامل',
    lConfirm: 'تأكيد كلمة المرور',
    lRole: 'انا',
    lGymName: 'اسم الصالة',
    btnLogin: 'تسجيل الدخول',
    btnSignup: 'انشاء حساب',
    forgotPw: 'نسيت كلمة المرور؟',
    phEmail: 'you@example.com',
    phPassword: 'كلمة المرور',
    phName: 'احمد بن علي',
    phMinPassword: '8 احرف على الاقل',
    phRepeatPassword: 'اعد كلمة المرور',
    phGymName: 'مثال: Trainw Ariana',
    roleGym: 'مالك الصالة',
    roleCoach: 'مدرب',
    roleClient: 'عميل',
    roleBadge: 'الدور المحدد',
    eEmailReq: 'البريد الالكتروني مطلوب.',
    eEmailFmt: 'ادخل بريدا الكترونيا صحيحا.',
    ePwReq: 'كلمة المرور مطلوبة.',
    ePwShort: 'يجب ان تكون كلمة المرور 8 احرف على الاقل.',
    ePwMatch: 'كلمتا المرور غير متطابقتين.',
    eNameReq: 'الاسم الكامل مطلوب.',
    eGymNameReq: 'اسم الصالة مطلوب.',
    eGeneric: 'حدث خطأ. حاول مرة اخرى.',
    eBadCreds: 'البريد الالكتروني او كلمة المرور غير صحيحة.',
    eEmailTaken: 'يوجد حساب بهذا البريد مسبقا.',
    eNoProfile: 'الحساب غير موجود. يرجى التسجيل اولا.',
    eEmailNotConfirmed: 'يرجى تأكيد بريدك الالكتروني قبل تسجيل الدخول.',
    eUserNotFound: 'لا يوجد حساب بهذا البريد.',
    eSignupDisabled: 'التسجيل غير متاح حاليا.',
    okForgot: 'تم ارسال بريد اعادة التعيين.',
    okSignup: 'تم انشاء الحساب. جار التحويل...',
    okLogin: 'تم تسجيل الدخول. جار التحويل...',
    eyeShow: 'اظهار',
    eyeHide: 'اخفاء',
  },
};

const ROLE_LABELS = {
  gym_owner: { fr: 'Proprietaire de salle', en: 'Gym owner', ar: 'مالك الصالة' },
  coach: { fr: 'Coach', en: 'Coach', ar: 'مدرب' },
  client: { fr: 'Client', en: 'Client', ar: 'عميل' },
};

const emailRe = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

function t(key) {
  return T[lang]?.[key] || T.fr[key] || T.en[key] || key;
}

function field(id) {
  return document.getElementById(id);
}

function currentRole() {
  return new URLSearchParams(window.location.search).get('role') || field('s-role')?.value || 'client';
}

function inviteToken() {
  return new URLSearchParams(window.location.search).get('invite') || '';
}

function portalForRole(role) {
  const safeRole = String(role || '').trim().toLowerCase();
  if (safeRole === 'coach') return 'coach';
  if (safeRole === 'client') return 'client';
  if (['gym_owner', 'gym', 'gym_admin', 'admin', 'staff'].includes(safeRole)) return 'admin';
  return '';
}

function syncLangButtons() {
  document.querySelectorAll('.lang-btn').forEach(function (button) {
    button.classList.toggle('active', button.dataset.lang === lang);
  });
}

function populateRoleOptions() {
  const select = field('s-role');
  if (!select) return;
  const selected = select.value || currentRole();
  select.innerHTML = '' +
    '<option value="client">' + t('roleClient') + '</option>' +
    '<option value="coach">' + t('roleCoach') + '</option>' +
    '<option value="gym_owner">' + t('roleGym') + '</option>';
  select.value = selected;
}

function updateRoleBadge() {
  const badge = field('rbadge');
  if (!badge) return;
  const role = currentRole();
  const label = ROLE_LABELS[role]?.[lang] || ROLE_LABELS[role]?.fr || role;
  badge.textContent = t('roleBadge') + ' - ' + label;
}

function applyTranslations() {
  document.querySelectorAll('[data-i18n]').forEach(function (element) {
    element.textContent = t(element.getAttribute('data-i18n'));
  });
  document.querySelectorAll('[data-i18n-ph]').forEach(function (element) {
    element.setAttribute('placeholder', t(element.getAttribute('data-i18n-ph')));
  });
  document.querySelectorAll('.eye').forEach(function (button) {
    button.textContent = button.dataset.visible === 'true' ? t('eyeHide') : t('eyeShow');
  });
  populateRoleOptions();
  updateRoleBadge();
  syncLangButtons();
  Trainw.applyDocumentLanguage(lang, document.body);
}

function setTab(tab) {
  document.querySelectorAll('.tab').forEach(function (button) {
    button.classList.toggle('active', button.dataset.tab === tab);
  });
  document.querySelectorAll('.panel').forEach(function (panel) {
    panel.classList.toggle('active', panel.id === 'panel-' + tab);
  });
  clearAll();
}

function onRoleChange() {
  const wrap = field('gym-name-wrap');
  const gymField = field('s-gym-name');
  const showGym = currentRole() === 'gym_owner';
  if (wrap) wrap.hidden = !showGym;
  wrap?.classList.toggle('visible', showGym);
  if (gymField) gymField.required = showGym;
  if (!showGym && gymField) gymField.value = '';
  updateRoleBadge();
}

function clearField(id) {
  field(id + '-e')?.classList.remove('show');
  if (field(id + '-e')) field(id + '-e').textContent = '';
  field(id)?.classList.remove('err');
}

function clearAll() {
  document.querySelectorAll('.ferr').forEach(function (node) {
    node.textContent = '';
    node.classList.remove('show');
  });
  document.querySelectorAll('.input').forEach(function (node) {
    node.classList.remove('err', 'ok');
  });
  document.querySelectorAll('.alert').forEach(function (node) {
    node.textContent = '';
    node.classList.remove('show');
  });
}

function showFerr(id, message) {
  const error = field(id + '-e');
  const input = field(id);
  if (error) {
    error.textContent = message;
    error.classList.add('show');
  }
  input?.classList.add('err');
}

function showErr(id, message) {
  const el = field(id);
  if (!el) return;
  el.textContent = message;
  el.classList.add('show');
}

function showOk(id, message) {
  const el = field(id);
  if (!el) return;
  el.textContent = message;
  el.classList.add('show');
}

function busy(id, on) {
  const button = field(id);
  if (!button) return;
  button.disabled = Boolean(on);
  button.classList.toggle('loading', Boolean(on));
}

function mapAuthError(error) {
  const message = String(error?.message || '').toLowerCase();
  const code = String(error?.code || '').toLowerCase();
  if (message.includes('invalid login credentials') || message.includes('invalid credentials') || code.includes('invalid_credentials')) return t('eBadCreds');
  if (message.includes('email not confirmed') || code.includes('email_not_confirmed')) return t('eEmailNotConfirmed');
  if (message.includes('user not found') || message.includes('email not found')) return t('eUserNotFound');
  if (message.includes('already registered') || message.includes('already exists') || code.includes('user_already_exists')) return t('eEmailTaken');
  if (message.includes('signups not allowed') || message.includes('signup')) return t('eSignupDisabled');
  if (message.includes('password') && message.includes('6')) return t('ePwShort');
  return t('eGeneric');
}

function authUnavailableMessage(error) {
  const message = String(error?.message || '');
  if (/missing supabase config/i.test(message) || /invalid url/i.test(message)) {
    if (lang === 'fr') return 'Configuration Supabase indisponible sur cette page.';
    if (lang === 'ar') return 'إعدادات Supabase غير متاحة في هذه الصفحة.';
    return 'Supabase configuration is unavailable on this page.';
  }
  return mapAuthError(error);
}

function signupPendingMessage() {
  if (lang === 'fr') return 'Compte cree. Verifiez votre email pour activer le compte.';
  if (lang === 'ar') return 'تم إنشاء الحساب. يرجى تأكيد بريدك الإلكتروني ثم تسجيل الدخول.';
  return 'Account created. Please confirm your email, then sign in.';
}

async function resolveDestinationAfterAuth(fallbackRole) {
  const requestedRole = fallbackRole || currentRole();
  const requestedPortal = portalForRole(requestedRole);
  if (requestedPortal === 'coach' || requestedPortal === 'client') {
    localStorage.removeItem('trainw_active_gym');
  }
  const context = await Trainw.auth.getContext(sb, {
    expectedRoles: requestedRole ? [requestedRole] : null,
    loginHref: null,
    redirectOnMissing: false,
    redirectOnMismatch: false,
    redirectOnPendingMembership: false,
    recoveryRole: requestedRole,
    workspaceHref: null,
  });

  if (!context.session || !context.profile) {
    return { href: null, error: new Error('profile_missing') };
  }

  const token = inviteToken();
  if (token && token.length >= 10) {
    const invitationResult = await Trainw.auth.acceptInvitation(sb, token);
    if (invitationResult.error) {
      return { href: null, error: invitationResult.error };
    }
    return {
      href: Trainw.roleToPath(invitationResult.data || context.activeMembership || context.profile),
      error: null,
    };
  }

  const allMemberships = Array.isArray(context.memberships) ? context.memberships : [];
  const scopedMemberships = requestedPortal
    ? allMemberships.filter(function (membership) {
        return String(membership?.portal || '').trim().toLowerCase() === requestedPortal;
      })
    : allMemberships;

  if (scopedMemberships.length > 1) {
    return { href: ROUTES.role, error: null };
  }

  if (!context.activeMembership && scopedMemberships.length) {
    return { href: ROUTES.role, error: null };
  }

  const targetMembership =
    context.activeMembership ||
    (scopedMemberships.length === 1 ? scopedMemberships[0] : null) ||
    context.profile;

  return {
    href: Trainw.roleToPath(targetMembership),
    error: context.error || null,
  };
}

async function doLogin() {
  clearAll();
  const email = field('l-email')?.value.trim() || '';
  const password = field('l-pw')?.value || '';
  let valid = true;

  if (!email) {
    showFerr('l-email', t('eEmailReq'));
    valid = false;
  } else if (!emailRe.test(email)) {
    showFerr('l-email', t('eEmailFmt'));
    valid = false;
  }

  if (!password) {
    showFerr('l-pw', t('ePwReq'));
    valid = false;
  }

  if (!valid) return;

  busy('btn-login', true);
  try {
    getSupabaseClient();
    const { data, error } = await sb.auth.signInWithPassword({ email, password });
    if (error) {
      showErr('l-err', mapAuthError(error));
      return;
    }

    await Trainw.auth.ensureProfile(sb, {
      role: currentRole(),
      email,
      name: data.user?.user_metadata?.name || null,
      gymName: data.user?.user_metadata?.gym_name || null,
    });

    const destination = await resolveDestinationAfterAuth(currentRole());
    if (destination.error || !destination.href) {
      await sb.auth.signOut();
      showErr('l-err', t('eNoProfile'));
      return;
    }

    showOk('l-ok', t('okLogin'));
    window.setTimeout(function () {
      window.location.href = destination.href;
    }, 500);
  } catch (error) {
    console.error(error);
    showErr('l-err', authUnavailableMessage(error));
  } finally {
    busy('btn-login', false);
  }
}

async function doSignup() {
  clearAll();
  const name = field('s-name')?.value.trim() || '';
  const email = field('s-email')?.value.trim().toLowerCase() || '';
  const password = field('s-pw')?.value || '';
  const password2 = field('s-pw2')?.value || '';
  const role = currentRole();
  const gymName = field('s-gym-name')?.value.trim() || '';
  let valid = true;

  if (!name) {
    showFerr('s-name', t('eNameReq'));
    valid = false;
  }
  if (!email) {
    showFerr('s-email', t('eEmailReq'));
    valid = false;
  } else if (!emailRe.test(email)) {
    showFerr('s-email', t('eEmailFmt'));
    valid = false;
  }
  if (!password) {
    showFerr('s-pw', t('ePwReq'));
    valid = false;
  } else if (password.length < 8) {
    showFerr('s-pw', t('ePwShort'));
    valid = false;
  }
  if (password !== password2) {
    showFerr('s-pw2', t('ePwMatch'));
    valid = false;
  }
  if (role === 'gym_owner' && !gymName) {
    showFerr('s-gym-name', t('eGymNameReq'));
    valid = false;
  }
  if (!valid) return;

  busy('btn-signup', true);
  try {
    getSupabaseClient();
    const { data, error } = await sb.auth.signUp({
      email,
      password,
      options: {
        data: {
          name,
          role,
          gym_name: gymName || null,
          language_preference: lang,
        },
      },
    });

    if (error) {
      showErr('s-err', mapAuthError(error));
      return;
    }

    const user = data.user || data.session?.user;
    if (!user?.id) {
      showErr('s-err', t('eGeneric'));
      return;
    }

    if (Array.isArray(user.identities) && user.identities.length === 0) {
      showErr('s-err', t('eEmailTaken'));
      return;
    }

    let authUser = data.session?.user || null;
    if (!authUser) {
      const signIn = await sb.auth.signInWithPassword({ email, password });
      if (signIn.error || !signIn.data.user) {
        const mapped = mapAuthError(signIn.error || new Error('signin_failed'));
        if (mapped === t('eEmailNotConfirmed')) {
          setTab('login');
          showOk('l-ok', signupPendingMessage());
          return;
        }
        showErr('s-err', mapped);
        return;
      }
      authUser = signIn.data.user;
    }

    const profileResult = await Trainw.auth.ensureProfile(sb, {
      role,
      name,
      email,
      gymName,
    });
    if (profileResult?.missing) {
      await sb.auth.signOut();
      showErr('s-err', 'Compte cree mais configuration incomplete. Contactez le support.');
      return;
    }

    const destination = await resolveDestinationAfterAuth(role);
    showOk('s-ok', t('okSignup'));
    window.setTimeout(function () {
      window.location.href = destination.href || ROUTES.role;
    }, 600);
  } catch (error) {
    console.error(error);
    showErr('s-err', authUnavailableMessage(error));
  } finally {
    busy('btn-signup', false);
  }
}

async function forgotPassword() {
  clearField('l-email');
  const email = field('l-email')?.value.trim() || '';
  if (!email || !emailRe.test(email)) {
    showFerr('l-email', t('eEmailFmt'));
    field('l-email')?.focus();
    return;
  }

  busy('forgot-link', true);
  try {
    getSupabaseClient();
    const result = await Trainw.api.run(
      sb.auth.resetPasswordForEmail(email),
      { context: 'reset password email', toastOnError: false, fallback: null }
    );
    if (result.error) {
      showErr('l-err', mapAuthError(result.error));
      return;
    }
    showOk('l-ok', t('okForgot'));
  } finally {
    busy('forgot-link', false);
  }
}

function bindUi() {
  document.querySelectorAll('.tab').forEach(function (button) {
    button.addEventListener('click', function () {
      setTab(button.dataset.tab);
    });
  });

  document.querySelectorAll('.lang-btn').forEach(function (button) {
    button.addEventListener('click', function () {
      lang = button.dataset.lang || 'fr';
      localStorage.setItem('trainw_lang', lang);
      applyTranslations();
    });
  });

  document.querySelectorAll('.eye').forEach(function (button) {
    button.addEventListener('click', function () {
      const input = field(button.dataset.target);
      if (!input) return;
      const isPassword = input.type === 'password';
      input.type = isPassword ? 'text' : 'password';
      button.dataset.visible = isPassword ? 'true' : 'false';
      button.textContent = isPassword ? t('eyeHide') : t('eyeShow');
    });
  });

  field('s-role')?.addEventListener('change', onRoleChange);
  field('btn-login')?.addEventListener('click', doLogin);
  field('btn-signup')?.addEventListener('click', doSignup);
  field('forgot-link')?.addEventListener('click', forgotPassword);
  document.addEventListener('keydown', function (event) {
    if (event.key !== 'Enter') return;
    if (field('panel-login')?.classList.contains('active')) doLogin();
    else doSignup();
  });
}

function hydrateRole() {
  const role = new URLSearchParams(window.location.search).get('role');
  if (!role) {
    onRoleChange();
    return;
  }
  const select = field('s-role');
  if (select) select.value = role;
  onRoleChange();
}

async function restoreSession() {
  try {
    getSupabaseClient();
    const sessionResult = await sb.auth.getSession();
    if (sessionResult.error) throw sessionResult.error;
    if (!sessionResult.data?.session) return;
    const destination = await resolveDestinationAfterAuth(currentRole());
    if (destination.href) {
      window.location.href = destination.href;
    }
  } catch (error) {
    console.error('[Trainw] restoreSession skipped', error);
  }
}

bindUi();
applyTranslations();
hydrateRole();
restoreSession();
