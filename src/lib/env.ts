const envValues = {
  appUrl: process.env.NEXT_PUBLIC_APP_URL ?? "http://localhost:3000",
  captchaSecretKey: process.env.CAPTCHA_SECRET_KEY ?? "",
  hcaptchaSiteKey: process.env.NEXT_PUBLIC_HCAPTCHA_SITE_KEY ?? "",
  supabaseAnonKey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "",
  supabaseServiceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY ?? "",
  supabaseUrl: process.env.NEXT_PUBLIC_SUPABASE_URL ?? "",
};

export const env = envValues;

export function isSupabaseConfigured() {
  return Boolean(env.supabaseUrl && env.supabaseAnonKey);
}

export function isSupabaseAdminConfigured() {
  return isSupabaseConfigured() && Boolean(env.supabaseServiceRoleKey);
}

export function getAbsoluteUrl(pathname = "/") {
  return new URL(pathname, env.appUrl).toString();
}
