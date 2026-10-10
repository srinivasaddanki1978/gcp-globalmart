// Who is calling. The Cloud Run service requires authentication, so requests arrive
// with a Google ID token that Cloud Run has already verified (from `gcloud run services
// proxy` or another authenticated client); IAP adds X-Goog-Authenticated-User-Email.
// Used for display and logging only; access control is Cloud Run IAM.
import type { Request } from 'express';

export function callerEmail(req: Request): string | null {
  const iap = req.header('x-goog-authenticated-user-email');
  if (iap) return iap.replace(/^accounts\.google\.com:/, '');
  // Cloud Run strips the token signature and may pass it in X-Serverless-Authorization.
  const auth = req.header('x-serverless-authorization') ?? req.header('authorization') ?? '';
  const token = auth.replace(/^Bearer\s+/i, '');
  const payload = token.split('.')[1];
  if (!payload) return null;
  try {
    const claims = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')) as { email?: string };
    return claims.email ?? null;
  } catch {
    return null;
  }
}
