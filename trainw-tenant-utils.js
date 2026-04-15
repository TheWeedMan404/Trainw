(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) {
    module.exports = api;
  }
  root.TrainwTenantUtils = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  const ADMIN_PERMISSION_CODES = [
    'manage_staff',
    'manage_roles',
    'manage_branding',
    'manage_payments',
    'view_analytics',
  ];

  function normalizeCode(value) {
    return String(value || '')
      .trim()
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '_')
      .replace(/^_+|_+$/g, '')
      .replace(/_+/g, '_');
  }

  function rolePriority(portal, roleCode) {
    const safePortal = normalizeCode(portal);
    const safeRoleCode = normalizeCode(roleCode);

    if (safeRoleCode === 'gym_owner') return 400;
    if (safeRoleCode === 'gym_admin' || safeRoleCode === 'admin') return 350;
    if (safePortal === 'admin') return 300;
    if (safePortal === 'coach') return 200;
    return 100;
  }

  function resolvePortal(input) {
    const membership = input || {};
    const explicitPortal = normalizeCode(membership.portal || membership.role_portal);
    const roleCode = normalizeCode(membership.role_code || membership.code || membership.role);
    const permissions = Array.isArray(membership.permissions) ? membership.permissions.map(normalizeCode) : [];
    const permissionSet = new Set(permissions);

    if (explicitPortal === 'admin' || explicitPortal === 'coach' || explicitPortal === 'client') {
      return explicitPortal;
    }
    if (roleCode === 'gym_owner' || roleCode === 'gym_admin' || roleCode === 'staff' || roleCode === 'admin') {
      return 'admin';
    }
    if (roleCode === 'coach') {
      return 'coach';
    }
    if (roleCode === 'client') {
      return 'client';
    }
    if (ADMIN_PERMISSION_CODES.some(function (permissionCode) { return permissionSet.has(permissionCode); })) {
      return 'admin';
    }
    if (permissionSet.has('edit_clients') || permissionSet.has('manage_sessions')) {
      return 'coach';
    }
    return 'client';
  }

  function resolveWorkspacePath(input) {
    const portal = resolvePortal(input);
    if (portal === 'admin') return '/admin';
    if (portal === 'coach') return '/coach';
    return '/client';
  }

  function mergePermissionCodes(rolePermissions, overrides) {
    const merged = new Set(
      Array.isArray(rolePermissions)
        ? rolePermissions.map(normalizeCode).filter(Boolean)
        : []
    );

    (Array.isArray(overrides) ? overrides : []).forEach(function (override) {
      const code = normalizeCode(override && override.permission_code ? override.permission_code : override);
      const effect = normalizeCode(override && override.effect ? override.effect : 'allow');
      if (!code) return;
      if (effect === 'deny') {
        merged.delete(code);
        return;
      }
      merged.add(code);
    });

    return Array.from(merged).sort();
  }

  function membershipTimestampScore(membership) {
    const source =
      membership?.last_active_at ||
      membership?.updated_at ||
      membership?.activated_at ||
      membership?.created_at ||
      null;
    const parsed = source ? Date.parse(source) : NaN;
    return Number.isFinite(parsed) ? parsed : 0;
  }

  function normalizeMembership(membership) {
    if (!membership) return null;
    const roleCode = normalizeCode(
      membership.role_code ||
      membership.role?.code ||
      membership.role?.slug ||
      membership.role ||
      membership.code
    );
    const portal = resolvePortal({
      role_code: roleCode,
      portal: membership.portal || membership.role_portal || membership.role?.portal,
      permissions: membership.permissions,
    });

    return {
      ...membership,
      role_code: roleCode,
      role_name: membership.role_name || membership.role?.name || membership.name || roleCode,
      portal,
      permissions: Array.isArray(membership.permissions)
        ? membership.permissions.map(normalizeCode).filter(Boolean)
        : [],
      status: normalizeCode(membership.status || 'active'),
    };
  }

  function pickActiveMembership(memberships, preferredGymId) {
    const normalized = (Array.isArray(memberships) ? memberships : [])
      .map(normalizeMembership)
      .filter(function (membership) {
        return membership && ['accepted', 'active'].includes(membership.status);
      });

    if (!normalized.length) {
      return null;
    }

    const preferred = preferredGymId
      ? normalized.find(function (membership) {
          return membership.gym_id === preferredGymId && membership.status !== 'declined';
        })
      : null;
    if (preferred) {
      return preferred;
    }

    return normalized
      .slice()
      .sort(function (left, right) {
        const leftDefault = left.is_default ? 1 : 0;
        const rightDefault = right.is_default ? 1 : 0;
        if (leftDefault !== rightDefault) return rightDefault - leftDefault;

        const leftStatus = left.status === 'active' ? 2 : left.status === 'accepted' ? 1 : 0;
        const rightStatus = right.status === 'active' ? 2 : right.status === 'accepted' ? 1 : 0;
        if (leftStatus !== rightStatus) return rightStatus - leftStatus;

        const leftPriority = rolePriority(left.portal, left.role_code);
        const rightPriority = rolePriority(right.portal, right.role_code);
        if (leftPriority !== rightPriority) return rightPriority - leftPriority;

        return membershipTimestampScore(right) - membershipTimestampScore(left);
      })[0];
  }

  function slugifyRoleCode(name) {
    const normalized = normalizeCode(name);
    return normalized || 'custom_role';
  }

  function transitionInvitation(membership, action, nowIso) {
    const now = nowIso || new Date().toISOString();
    const current = normalizeMembership(membership) || {};
    const next = { ...current };
    const safeAction = normalizeCode(action);

    if (safeAction === 'accept') {
      next.status = 'active';
      next.invitation_status = 'accepted';
      next.accepted_at = current.accepted_at || now;
      next.activated_at = now;
      return next;
    }

    if (safeAction === 'decline') {
      next.status = 'declined';
      next.invitation_status = 'declined';
      next.declined_at = now;
      return next;
    }

    if (safeAction === 'revoke') {
      next.status = 'revoked';
      next.invitation_status = 'revoked';
      next.revoked_at = now;
      return next;
    }

    return next;
  }

  return {
    ADMIN_PERMISSION_CODES,
    normalizeCode,
    resolvePortal,
    resolveWorkspacePath,
    mergePermissionCodes,
    normalizeMembership,
    pickActiveMembership,
    slugifyRoleCode,
    transitionInvitation,
  };
});
