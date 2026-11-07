# Spider VPN account API (deployment scaffold)

The repository originally contained only local demo authentication and no server, DB, or mail provider. `backend/` provides a deployable API foundation; it is **not active** until deployed, configured, and connected to the client. Never use client-only data as production identity.

## Server setup

1. Node.js 20+ and PostgreSQL 14+.
2. In `backend/`, run `npm ci`; create DB and apply `psql "$DATABASE_URL" -f schema.sql`.
3. Set required secrets using your hosting provider's secret manager, not a committed `.env`: `DATABASE_URL`, `JWT_SECRET` (32+ random bytes), `CODE_PEPPER` (different 32+ random bytes), `SMTP_HOST`, `SMTP_PORT`, `SMTP_SECURE`, `SMTP_USER`, `SMTP_PASSWORD`, `MAIL_FROM`.
4. Configure provider-issued SMTP/app credentials, verified sender/domain and SPF/DKIM/DMARC. Use TLS and HTTPS. Restrict PostgreSQL networking, enable encrypted backups and monitoring.
5. Deploy `node src/server.js`, add health monitoring at `/health`, and point the client at `--dart-define=SPIDER_API_URL=https://api.example.com/`.

The API uses Argon2id password hashes, JWT-backed revocable sessions stored in PostgreSQL, server-generated six-digit codes (10-minute expiry, attempt and send limits, HMAC pepper at rest), single-use verification grants, unique usernames/emails, and no secret/code logging. Email unlink requires the current password and an OTP to the currently verified email. Code delivery fails closed without SMTP configuration.

## API

- `POST /v1/auth/register` and `/v1/auth/login`
- `GET /v1/account` (Bearer session)
- `POST /v1/verification/send` with purpose and optionally new email
- `POST /v1/verification/confirm` with challengeId/code
- `PATCH /v1/account/username`, `/v1/account/password`, `/v1/account/email`
- `DELETE /v1/account/email`

The Flutter adapter in `lib/privacy/privacy_api.dart` supports auth registration/login and stores session tokens using `flutter_secure_storage`. `PrivacyAccountScreen` in `lib/privacy/privacy_account_screen.dart` provides account settings UI in the registration screen's dark/pink/rose palette. It deliberately refuses to simulate OTP verification when the API is unavailable.

## Important integration boundary

The existing `DemoAuthGate` remains a local-only demo and is not wired to this server account API. Before deployment, migrate the registration/login UI to `PrivacyApi.register/login`, retain the token using secure storage, and inject a configured `PrivacyApi` into the profile privacy route. Until that migration and server deployment are complete, the privacy screen is a prepared component, not a functioning production identity service. Do not promise successful email delivery or persistence from the current demo sign-in.
