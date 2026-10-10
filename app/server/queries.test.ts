import { describe, expect, it } from 'vitest';
import { parseQuery, plain, validateParams } from './queries.js';

const def = parseQuery('q', '-- @param target_year INT64\n-- @param label STRING\nSELECT @target_year, @label');

describe('parseQuery', () => {
  it('reads @param headers', () => expect(def.params).toEqual({ target_year: 'INT64', label: 'STRING' }));
});

describe('validateParams', () => {
  it('accepts declared, correctly typed parameters', () =>
    expect(validateParams(def, { target_year: 2025, label: 'East' })).toEqual({ target_year: 2025, label: 'East' }));
  it('rejects unknown parameters (no free-form SQL inputs)', () =>
    expect(() => validateParams(def, { target_year: 2025, label: 'x', extra: 1 })).toThrow(/unknown/));
  it('rejects wrong types, e.g. SQL text in an INT64', () =>
    expect(() => validateParams(def, { target_year: '2025; DROP TABLE x', label: 'x' })).toThrow(/INT64/));
  it('rejects missing parameters', () => expect(() => validateParams(def, { label: 'x' })).toThrow(/missing/));
});

describe('plain', () => {
  it('unwraps BigQuery value objects to numbers or strings', () => {
    expect(plain({ value: '42' })).toBe(42);
    expect(plain({ value: '2025-01-31' })).toBe('2025-01-31');
    expect(plain(3.5)).toBe(3.5);
  });
});

import { callerEmail } from './identity.js';

describe('callerEmail', () => {
  const token = (claims: object) => `Bearer h.${Buffer.from(JSON.stringify(claims)).toString('base64url')}`; // signature stripped
  const req = (headers: Record<string, string>) => ({ header: (n: string) => headers[n.toLowerCase()] }) as never;
  it('reads the email claim from a signature-stripped Cloud Run token', () =>
    expect(callerEmail(req({ authorization: token({ email: 'a@b.com' }) }))).toBe('a@b.com'));
  it('prefers X-Serverless-Authorization', () =>
    expect(callerEmail(req({ 'x-serverless-authorization': token({ email: 'x@y.com' }), authorization: token({ email: 'a@b.com' }) }))).toBe('x@y.com'));
  it('reads IAP identity', () =>
    expect(callerEmail(req({ 'x-goog-authenticated-user-email': 'accounts.google.com:me@g.com' }))).toBe('me@g.com'));
});
