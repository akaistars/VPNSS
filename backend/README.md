# Spider VPN account API (deployment scaffold)

This repository had no backend, database, or email provider. `backend/` adds a server-side foundation; the Flutter demo authentication is not yet a production identity system. Deploy this API and configure its secrets before relying on account operations. Never put SMTP credentials, JWT secrets, or verification peppers in Flutter.

## Setup

1. Install Node.js 20+ and PostgreSQL 14+.
2. Create a database and apply `schema.sql` (`psql "$DATABASE_URL" -f schema.sql`).
3. Copy `.env.example` to `.env` and set strong random `JWT_SECRET` and `CODE_PEPPER` values, plus SMTP settings.
4. Run `npm ci`, then `npm start` from `backend/`.
5. Publish the API over HTTPS and set the Flutter `API_BASE_URL` to that origin when integrating the client.

SMTP account requirements: configure the provider's SMTP host/port, TLS, sender address and provider-issued app/API password as server environment variables. Do not commit `.env` or print codes/secrets in logs. For production, terminate TLS at a trusted proxy, restrict network access to PostgreSQL, configure backups, and use a managed secrets store.

## API overview

- `POST /v1/auth/register` `{username,password}`
- `POST /v1/auth/login` `{username,password}`
- `GET /v1/account` (Bearer session token)
- `POST /v1/verification/send` `{purpose,email?}` (Bearer)
- `POST /v1/verification/confirm` `{challengeId,code}` (Bearer) returns a short-lived, single-use grant
- `PATCH /v1/account/username` `{username,grant}` (Bearer)
- `PATCH /v1/account/password` `{password,grant}` (Bearer)
- `PATCH /v1/account/email` `{email,grant}` (Bearer)
- `DELETE /v1/account/email` `{password,grant}` (Bearer)

Codes expire after 10 minutes, are HMAC-hashed at rest, limited to five attempts, and consumed once. Sending is throttled per account. Passwords are Argon2id hashes. Unlinking also requires the current password and an OTP to the currently verified email. The API does not expose a development-only OTP bypass.

## Flutter status

`lib/privacy/` contains the account API client and a privacy UI component in the registration screen's dark/pink Spider VPN style. The existing app still has local demo authentication and the profile's privacy action must be wired to this screen after the backend is deployed; do not treat the current demo login as server authentication. This separation is intentional: it avoids claiming email verification or password security that cannot be provided by a client-only demo.
