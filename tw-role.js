const Trainw = window.TrainwCore;
Trainw.installGlobalErrorHandlers();
let cachedSupabaseClient = null;
let currentContext = null;
let joinRole = 'client';
let lang = localStorage.getItem('trainw_lang') || 'fr';

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
    workspaceTitle: 'Vos espaces',
    workspaceSub: 'Choisissez la salle et le portail que vous voulez ouvrir.',
    workspaceLabel: 'Espaces disponibles',
    noMemberships: "Aucun espace actif n'est encore lie a ce compte.",
    pendingWorkspace: 'Invitation en attente',
    openWorkspace: 'Ouvrir',
    switchWorkspace: 'Changer',
    adminPortal: 'Portail admin',
    coachPortal: 'Portail coach',
    clientPortal: 'Portail client',
    inviteReady: "Une invitation est en attente pour ce compte.",
    acceptInvite: 'Accepter',
    declineInvite: 'Refuser',
    inviteAccepted: 'Invitation acceptee.',
    inviteDeclined: 'Invitation refusee.',
    signedInAs: 'Connecte en tant que',
    pendingBadge: 'En attente',
    activeBadge: 'Actif',
    joinTitle: 'Rejoindre une salle',
    joinSub: 'Aucun espace actif pour le moment. Choisissez une salle et demandez à la rejoindre.',
    joinAsClient: 'En tant que client',
    joinAsCoach: 'En tant que coach',
    joinRequest: 'Demander à rejoindre',
    joinRequested: 'Demande envoyée',
    joinRequestSent: 'Demande envoyée. La salle va l’examiner.',
    joinLoadError: 'Impossible de charger la liste des salles.',
    joinEmpty: 'Aucune salle disponible pour le moment.',
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
    workspaceTitle: 'Your workspaces',
    workspaceSub: 'Choose which gym and portal to open.',
    workspaceLabel: 'Available workspaces',
    noMemberships: 'No active workspace is linked to this account yet.',
    pendingWorkspace: 'Pending invitation',
    openWorkspace: 'Open',
    switchWorkspace: 'Switch',
    adminPortal: 'Admin portal',
    coachPortal: 'Coach portal',
    clientPortal: 'Client portal',
    inviteReady: 'There is a pending invitation on this account.',
    acceptInvite: 'Accept',
    declineInvite: 'Decline',
    inviteAccepted: 'Invitation accepted.',
    inviteDeclined: 'Invitation declined.',
    signedInAs: 'Signed in as',
    pendingBadge: 'Pending',
    activeBadge: 'Active',
    joinTitle: 'Join a gym',
    joinSub: 'No active workspace yet. Pick a gym and request to join it.',
    joinAsClient: 'As a client',
    joinAsCoach: 'As a coach',
    joinRequest: 'Request to join',
    joinRequested: 'Request sent',
    joinRequestSent: 'Request sent. The gym will review it.',
    joinLoadError: 'Could not load the gym list.',
    joinEmpty: 'No gyms available right now.',
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
    workspaceTitle: 'مساحاتك',
    workspaceSub: 'اختر الصالة والبوابة التي تريد فتحها.',
    workspaceLabel: 'المساحات المتاحة',
    noMemberships: 'لا توجد مساحة نشطة مرتبطة بهذا الحساب حتى الآن.',
    pendingWorkspace: 'دعوة معلقة',
    openWorkspace: 'فتح',
    switchWorkspace: 'تبديل',
    adminPortal: 'بوابة الادارة',
    coachPortal: 'بوابة المدرب',
    clientPortal: 'بوابة العميل',
    inviteReady: 'هناك دعوة معلقة على هذا الحساب.',
    acceptInvite: 'قبول',
    declineInvite: 'رفض',
    inviteAccepted: 'تم قبول الدعوة.',
    inviteDeclined: 'تم رفض الدعوة.',
    signedInAs: 'تم تسجيل الدخول باسم',
    pendingBadge: 'معلق',
    activeBadge: 'نشط',
    joinTitle: 'الانضمام إلى صالة',
    joinSub: 'لا توجد مساحة نشطة بعد. اختر صالة واطلب الانضمام إليها.',
    joinAsClient: 'كعميل',
    joinAsCoach: 'كمدرب',
    joinRequest: 'اطلب الانضمام',
    joinRequested: 'تم إرسال الطلب',
    joinRequestSent: 'تم إرسال الطلب. ستقوم الصالة بمراجعته.',
    joinLoadError: 'تعذر تحميل قائمة الصالات.',
    joinEmpty: 'لا توجد صالات متاحة حالياً.',
  },
};

function t(key) {
  return T[lang]?.[key] || T.fr[key] || T.en[key] || key;
}

function portalLabel(portal) {
  if (portal === 'admin') return t('adminPortal');
  if (portal === 'coach') return t('coachPortal');
  return t('clientPortal');
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

function initials(name) {
  return String(name || 'TW')
    .split(/\s+/)
    .filter(Boolean)
    .map(function (part) { return part[0] || ''; })
    .join('')
    .slice(0, 2)
    .toUpperCase();
}

function getInviteToken() {
  return new URLSearchParams(window.location.search).get('invite') || '';
}

function getWorkspaceCard(membership) {
  const statusKey = membership.status === 'active' ? 'activeBadge' : 'pendingBadge';
  const actionLabel = membership.status === 'active' ? t('openWorkspace') : t('pendingWorkspace');
  const disabledAttr = membership.status === 'active' ? '' : 'disabled';
  return (
    '<button class="role-card workspace-card" type="button" data-membership-gym="' + Trainw.escapeHTML(membership.gym_id) + '" ' + disabledAttr + '>' +
      '<div class="role-icon workspace-icon">' + Trainw.escapeHTML(initials(membership.gym_name || membership.role_name || 'TW')) + '</div>' +
      '<div class="role-body">' +
        '<div class="role-title">' + Trainw.escapeHTML(membership.gym_name || 'Trainw Gym') + '</div>' +
        '<div class="workspace-meta-row">' +
          '<span class="workspace-pill">' + Trainw.escapeHTML(portalLabel(membership.portal)) + '</span>' +
          '<span class="workspace-pill workspace-pill-status">' + Trainw.escapeHTML(t(statusKey)) + '</span>' +
        '</div>' +
        '<div class="role-desc">' + Trainw.escapeHTML(membership.role_name || membership.role_code || '') + '</div>' +
      '</div>' +
      '<div class="role-arrow workspace-action">' + Trainw.escapeHTML(actionLabel) + '</div>' +
    '</button>'
  );
}

function renderAnonymousState() {
  const title = document.querySelector('.card-title');
  const sub = document.querySelector('.card-sub');
  const label = document.querySelector('.role-label');
  const footer = document.querySelector('.footer-txt');
  const grid = document.querySelector('.role-grid');

  if (title) title.textContent = t('cardTitle');
  if (sub) sub.textContent = t('cardSub');
  if (label) label.textContent = t('roleLabel');
  if (footer) footer.innerHTML =
    '<span data-i18n="newHere">' + Trainw.escapeHTML(t('newHere')) + '</span> ' +
    '<a href="/" data-i18n="learnMore">' + Trainw.escapeHTML(t('learnMore')) + '</a>';
  if (!grid) return;

  grid.innerHTML = [
    {
      href: '/login?role=gym_owner',
      short: 'GY',
      title: t('gymTitle'),
      desc: t('gymDesc'),
    },
    {
      href: '/login?role=coach',
      short: 'CO',
      title: t('coachTitle'),
      desc: t('coachDesc'),
    },
    {
      href: '/login?role=client',
      short: 'CL',
      title: t('clientTitle'),
      desc: t('clientDesc'),
    },
  ].map(function (item) {
    return (
      '<a href="' + item.href + '" class="role-card">' +
        '<div class="role-icon">' + Trainw.escapeHTML(item.short) + '</div>' +
        '<div class="role-body">' +
          '<div class="role-title">' + Trainw.escapeHTML(item.title) + '</div>' +
          '<div class="role-desc">' + Trainw.escapeHTML(item.desc) + '</div>' +
        '</div>' +
        '<div class="role-arrow">&rarr;</div>' +
      '</a>'
    );
  }).join('');
}

function renderWorkspaceState(context) {
  const title = document.querySelector('.card-title');
  const sub = document.querySelector('.card-sub');
  const label = document.querySelector('.role-label');
  const footer = document.querySelector('.footer-txt');
  const grid = document.querySelector('.role-grid');
  const inviteToken = getInviteToken();
  const memberships = Array.isArray(context?.memberships) ? context.memberships : [];
  const actionableMemberships = memberships.filter(function (membership) {
    return membership.status === 'accepted' || membership.status === 'active';
  });

  if (title) title.textContent = t('workspaceTitle');
  if (sub) sub.textContent = t('workspaceSub');
  if (label) label.textContent = t('workspaceLabel');
  if (footer && context?.session?.user?.email) {
    footer.innerHTML =
      '<span>' + Trainw.escapeHTML(t('signedInAs')) + '</span> ' +
      '<strong>' + Trainw.escapeHTML(context.session.user.email) + '</strong>';
  }
  if (!grid) return;

  if (!memberships.length) {
    grid.innerHTML = '<div class="role-card workspace-empty"><div class="role-body"><div class="role-title">' + Trainw.escapeHTML(t('workspaceTitle')) + '</div><div class="role-desc">' + Trainw.escapeHTML(t('noMemberships')) + '</div></div></div>';
  } else {
    grid.innerHTML = memberships.map(getWorkspaceCard).join('');

    if (!inviteToken && actionableMemberships.length === 1) {
      const nextMembership = actionableMemberships[0];
      void openWorkspace(nextMembership.gym_id);
    }
  }

  // Round 9: no usable workspace yet — the user is at a dead end unless
  // they can join a gym. Show the public gym directory with a join
  // request per gym (client or coach). Pending requests already render
  // as cards above; the directory stays until one is approved.
  if (!actionableMemberships.length) {
    void loadJoinDirectory();
  }
}

function syncJoinRoleButtons() {
  document.querySelectorAll('[data-join-role]').forEach(function (button) {
    button.classList.toggle('active', button.dataset.joinRole === joinRole);
  });
}

async function loadJoinDirectory() {
  const card = document.querySelector('.card');
  if (!card || document.getElementById('role-join-directory')) return;

  const section = document.createElement('div');
  section.id = 'role-join-directory';
  section.className = 'role-join-directory';
  section.innerHTML =
    '<div class="role-join-title">' + Trainw.escapeHTML(t('joinTitle')) + '</div>' +
    '<div class="role-join-sub">' + Trainw.escapeHTML(t('joinSub')) + '</div>' +
    '<div class="role-join-roles">' +
      '<button class="btn-secondary role-join-role" type="button" data-join-role="client">' + Trainw.escapeHTML(t('joinAsClient')) + '</button>' +
      '<button class="btn-secondary role-join-role" type="button" data-join-role="coach">' + Trainw.escapeHTML(t('joinAsCoach')) + '</button>' +
    '</div>' +
    '<div class="role-join-list"><p class="empty-state">Chargement...</p></div>';
  card.appendChild(section);

  joinRole = currentContext?.profile?.role === 'coach' ? 'coach' : 'client';
  syncJoinRoleButtons();

  const sb = getSupabaseClient();
  const list = section.querySelector('.role-join-list');
  if (!list) return;
  let result;
  try {
    result = await sb.rpc('list_public_gyms');
  } catch (error) {
    result = { error };
  }
  if (result.error) {
    list.innerHTML = '<p class="empty-state">' + Trainw.escapeHTML(t('joinLoadError')) + '</p>';
    return;
  }
  const gyms = Array.isArray(result.data) ? result.data : [];
  if (!gyms.length) {
    list.innerHTML = '<p class="empty-state">' + Trainw.escapeHTML(t('joinEmpty')) + '</p>';
    return;
  }
  list.innerHTML = gyms.map(function (gym) {
    const place = [gym.address, gym.location].filter(Boolean).join(' · ');
    return (
      '<div class="role-card role-join-card">' +
        '<div class="role-icon workspace-icon">' + Trainw.escapeHTML(initials(gym.name || 'TW')) + '</div>' +
        '<div class="role-body">' +
          '<div class="role-title">' + Trainw.escapeHTML(gym.name || 'Trainw Gym') + '</div>' +
          (place ? '<div class="role-desc">' + Trainw.escapeHTML(place) + '</div>' : '') +
        '</div>' +
        '<button class="btn-primary role-join-btn" type="button" data-join-gym="' + Trainw.escapeHTML(gym.gym_id || '') + '">' + Trainw.escapeHTML(t('joinRequest')) + '</button>' +
      '</div>'
    );
  }).join('');
}

async function requestJoin(gymId) {
  if (!gymId) return;
  const sb = getSupabaseClient();
  const response = await sb.rpc('request_gym_membership', { p_gym_id: gymId, p_role_code: joinRole });
  if (response.error) {
    Trainw.ui.showToast(Trainw.api.userMessage(response.error, t('joinLoadError')), 'error');
    return;
  }
  Trainw.ui.showToast(t('joinRequestSent'), 'success');
  await bootstrap();
}

async function openWorkspace(gymId) {
  const sb = getSupabaseClient();
  const activeResult = await Trainw.auth.setActiveGym(sb, gymId);
  if (activeResult.error) {
    Trainw.ui.showToast(Trainw.api.userMessage(activeResult.error, 'Workspace selection failed.'), 'error');
    return;
  }
  window.location.href = Trainw.roleToPath(activeResult.data || currentContext?.activeMembership || currentContext?.profile?.role);
}

async function handleInvite(action) {
  const inviteToken = getInviteToken();
  if (!inviteToken) return;
  const sb = getSupabaseClient();
  const response = action === 'accept'
    ? await Trainw.auth.acceptInvitation(sb, inviteToken)
    : await Trainw.auth.declineInvitation(sb, inviteToken);

  if (response.error) {
    Trainw.ui.showToast(Trainw.api.userMessage(response.error, 'Invitation request failed.'), 'error');
    return;
  }

  Trainw.ui.showToast(t(action === 'accept' ? 'inviteAccepted' : 'inviteDeclined'), 'success');
  if (action === 'accept' && response.data?.gym_id) {
    window.location.href = Trainw.roleToPath(response.data);
    return;
  }

  const url = new URL(window.location.href);
  url.searchParams.delete('invite');
  window.history.replaceState({}, '', url.toString());
  await bootstrap();
}

function ensureInviteBanner() {
  const inviteToken = getInviteToken();
  let banner = document.getElementById('role-invite-banner');
  if (!inviteToken || !currentContext?.session) {
    if (banner) banner.remove();
    return;
  }

  if (!banner) {
    banner = document.createElement('div');
    banner.id = 'role-invite-banner';
    banner.className = 'role-invite-banner';
    const card = document.querySelector('.card');
    card?.insertBefore(banner, card.querySelector('.role-grid'));
  }

  banner.innerHTML =
    '<div class="role-invite-copy">' + Trainw.escapeHTML(t('inviteReady')) + '</div>' +
    '<div class="role-invite-actions">' +
      '<button class="btn-secondary invite-action-btn" type="button" data-invite-action="decline">' + Trainw.escapeHTML(t('declineInvite')) + '</button>' +
      '<button class="btn-primary invite-action-btn" type="button" data-invite-action="accept">' + Trainw.escapeHTML(t('acceptInvite')) + '</button>' +
    '</div>';
}

async function bootstrap() {
  applyTranslations();

  let sb = null;
  try {
    sb = getSupabaseClient();
  } catch (error) {
    console.error('[Trainw] workspace bootstrap skipped', error);
    renderAnonymousState();
    return;
  }

  currentContext = await Trainw.auth.getContext(sb, {
    redirectOnMissing: false,
    redirectOnPendingMembership: false,
    redirectOnMismatch: false,
    workspaceHref: null,
  });

  if (!currentContext?.session || !currentContext?.profile) {
    renderAnonymousState();
    ensureInviteBanner();
    return;
  }

  renderWorkspaceState(currentContext);
  ensureInviteBanner();
}

document.addEventListener('click', function (event) {
  const workspaceButton = event.target.closest('[data-membership-gym]');
  if (workspaceButton && !workspaceButton.disabled) {
    void openWorkspace(workspaceButton.dataset.membershipGym || '');
    return;
  }

  const joinRoleButton = event.target.closest('[data-join-role]');
  if (joinRoleButton) {
    joinRole = joinRoleButton.dataset.joinRole === 'coach' ? 'coach' : 'client';
    syncJoinRoleButtons();
    return;
  }

  const joinGymButton = event.target.closest('[data-join-gym]');
  if (joinGymButton && !joinGymButton.disabled) {
    void requestJoin(joinGymButton.dataset.joinGym || '');
    return;
  }

  const inviteActionButton = event.target.closest('[data-invite-action]');
  if (inviteActionButton) {
    void handleInvite(inviteActionButton.dataset.inviteAction || '');
  }
});

document.querySelectorAll('.lang-btn').forEach(function (button) {
  button.addEventListener('click', function () {
    lang = button.dataset.lang || 'fr';
    localStorage.setItem('trainw_lang', lang);
    bootstrap();
  });
});

bootstrap();
