const crypto = require('node:crypto');
const express = require('express');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const jwt = require('jsonwebtoken');
const argon2 = require('argon2');
const nodemailer = require('nodemailer');
const { Pool } = require('pg');

const app = express();
const pool = new Pool({ connectionString: process.env.DATABASE_URL, ssl: process.env.PGSSL === 'true' ? { rejectUnauthorized: true } : undefined });
const PORT = Number(process.env.PORT || 8080);
const CODE_TTL_MS = 10 * 60 * 1000;
const GRANT_TTL_MS = 5 * 60 * 1000;
const MAX_CODE_ATTEMPTS = 5;

function requireConfig() {
  for (const key of ['DATABASE_URL', 'JWT_SECRET', 'CODE_PEPPER', 'SMTP_HOST', 'SMTP_USER', 'SMTP_PASSWORD', 'MAIL_FROM']) {
    if (!process.env[key] || process.env[key].startsWith('replace-')) throw new Error(`Missing server configuration: ${key}`);
  }
  if (process.env.JWT_SECRET.length < 32 || process.env.CODE_PEPPER.length < 32) throw new Error('JWT_SECRET and CODE_PEPPER must be at least 32 characters');
}

const mailer = () => nodemailer.createTransport({
  host: process.env.SMTP_HOST,
  port: Number(process.env.SMTP_PORT || 587),
  secure: process.env.SMTP_SECURE === 'true',
  auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASSWORD },
});

app.disable('x-powered-by');
app.use(helmet());
app.use(express.json({ limit: '16kb' }));
app.use('/v1/auth', rateLimit({ windowMs: 15 * 60 * 1000, limit: 20, standardHeaders: true, legacyHeaders: false }));
app.use('/v1/verification', rateLimit({ windowMs: 15 * 60 * 1000, limit: 10, standardHeaders: true, legacyHeaders: false }));

const usernameValid = value => typeof value === 'string' && /^[A-Za-z0-9._-]{3,32}$/.test(value);
const emailValid = value => typeof value === 'string' && value.length <= 254 && /^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$/i.test(value);
const passwordValid = value => typeof value === 'string' && value.length >= 10 && value.length <= 128 && /[a-z]/.test(value) && /[A-Z]/.test(value) && /\d/.test(value);
const codeDigest = (challengeId, code) => crypto.createHmac('sha256', process.env.CODE_PEPPER).update(`${challengeId}:${code}`).digest('hex');
const tokenDigest = token => crypto.createHash('sha256').update(token).digest('hex');
const safeEqual = (a, b) => {
  const left = Buffer.from(a, 'hex'); const right = Buffer.from(b, 'hex');
  return left.length === right.length && crypto.timingSafeEqual(left, right);
};

function issueSession(account) {
  const tokenId = crypto.randomUUID();
  const token = jwt.sign({ sub: account.id, jti: tokenId }, process.env.JWT_SECRET, { expiresIn: '7d', issuer: 'spider-vpn-account-api' });
  return { token, tokenId, expiresAt: new Date(Date.now() + 7 * 86400000) };
}

async function auth(req, res, next) {
  try {
    const match = /^Bearer\s+(.+)$/i.exec(req.get('authorization') || '');
    if (!match) return res.status(401).json({ error: 'unauthorized' });
    const payload = jwt.verify(match[1], process.env.JWT_SECRET, { issuer: 'spider-vpn-account-api' });
    const session = await pool.query('SELECT account_id FROM account_sessions WHERE token_id=$1 AND account_id=$2 AND revoked_at IS NULL AND expires_at>now()', [payload.jti, payload.sub]);
    if (!session.rowCount) return res.status(401).json({ error: 'session_expired' });
    req.accountId = payload.sub;
    next();
  } catch (_) { return res.status(401).json({ error: 'unauthorized' }); }
}

async function issueChallenge(accountId, purpose, targetEmail) {
  const now = new Date();
  const recent = await pool.query("SELECT count(*)::int AS count FROM verification_challenges WHERE account_id=$1 AND created_at>now()-interval '1 hour'", [accountId]);
  if (recent.rows[0].count >= 5) { const error = new Error('rate_limited'); error.status = 429; throw error; }
  const code = String(crypto.randomInt(0, 1000000)).padStart(6, '0');
  const created = await pool.query(
    `INSERT INTO verification_challenges(account_id,purpose,target_email,code_hash,expires_at)
     VALUES($1,$2,$3,$4,$5) RETURNING id`,
    [accountId, purpose, targetEmail, codeDigest('pending', code), new Date(now.getTime() + CODE_TTL_MS)],
  );
  const id = created.rows[0].id;
  await pool.query('UPDATE verification_challenges SET code_hash=$1 WHERE id=$2', [codeDigest(id, code), id]);
  try {
    await mailer().sendMail({
      from: process.env.MAIL_FROM,
      to: targetEmail,
      subject: 'Spider VPN — код подтверждения',
      text: `Ваш код подтверждения: ${code}\nСрок действия — 10 минут. Если вы не запрашивали код, проигнорируйте это письмо.`,
    });
  } catch (error) {
    await pool.query('DELETE FROM verification_challenges WHERE id=$1', [id]);
    throw error;
  }
  return id;
}

async function consumeGrant(accountId, grant, purpose, targetEmail, client) {
  if (typeof grant !== 'string' || grant.length < 32) throw Object.assign(new Error('verification_required'), { status: 403 });
  const row = await client.query(
    `SELECT id,grant_hash FROM verification_challenges
     WHERE account_id=$1 AND purpose=$2 AND target_email=$3 AND verified_at IS NOT NULL
       AND consumed_at IS NULL AND grant_expires_at>now()
     ORDER BY verified_at DESC LIMIT 1 FOR UPDATE`,
    [accountId, purpose, targetEmail],
  );
  if (!row.rowCount || !safeEqual(row.rows[0].grant_hash, tokenDigest(grant))) throw Object.assign(new Error('verification_required'), { status: 403 });
  await client.query('UPDATE verification_challenges SET consumed_at=now() WHERE id=$1', [row.rows[0].id]);
}

app.get('/health', (_req, res) => res.json({ status: 'ok' }));

app.post('/v1/auth/register', async (req, res, next) => {
  try {
    const { username, password } = req.body || {};
    if (!usernameValid(username)) return res.status(400).json({ error: 'invalid_username' });
    if (!passwordValid(password)) return res.status(400).json({ error: 'weak_password', message: 'Use 10+ characters with lowercase, uppercase, and a digit.' });
    const hash = await argon2.hash(password, { type: argon2.argon2id });
    const result = await pool.query('INSERT INTO accounts(username,password_hash) VALUES($1,$2) RETURNING id,username,email,email_verified_at', [username, hash]);
    const session = issueSession(result.rows[0]);
    await pool.query('INSERT INTO account_sessions(account_id,token_id,expires_at) VALUES($1,$2,$3)', [result.rows[0].id, session.tokenId, session.expiresAt]);
    res.status(201).json({ token: session.token, account: result.rows[0] });
  } catch (error) { if (error.code === '23505') return res.status(409).json({ error: 'username_unavailable' }); next(error); }
});

app.post('/v1/auth/login', async (req, res, next) => {
  try {
    const { username, password } = req.body || {};
    const found = await pool.query('SELECT id,username,email,email_verified_at,password_hash FROM accounts WHERE lower(username)=lower($1)', [String(username || '')]);
    if (!found.rowCount || !(await argon2.verify(found.rows[0].password_hash, String(password || '')))) return res.status(401).json({ error: 'invalid_credentials' });
    const account = found.rows[0]; const session = issueSession(account);
    await pool.query('INSERT INTO account_sessions(account_id,token_id,expires_at) VALUES($1,$2,$3)', [account.id, session.tokenId, session.expiresAt]);
    delete account.password_hash;
    res.json({ token: session.token, account });
  } catch (error) { next(error); }
});

app.get('/v1/account', auth, async (req, res, next) => {
  try {
    const result = await pool.query('SELECT id,username,email,email_verified_at,created_at FROM accounts WHERE id=$1', [req.accountId]);
    if (!result.rowCount) return res.status(404).json({ error: 'account_not_found' });
    res.json({ account: result.rows[0] });
  } catch (error) { next(error); }
});

app.post('/v1/verification/send', auth, async (req, res, next) => {
  try {
    const { purpose, email } = req.body || {};
    const allowed = ['password_change','username_change','email_link','email_change','email_unlink'];
    if (!allowed.includes(purpose)) return res.status(400).json({ error: 'invalid_purpose' });
    const result = await pool.query('SELECT email,email_verified_at FROM accounts WHERE id=$1', [req.accountId]);
    if (!result.rowCount) return res.status(404).json({ error: 'account_not_found' });
    const account = result.rows[0];
    let target;
    if (purpose === 'email_link' || purpose === 'email_change') {
      if (!emailValid(email)) return res.status(400).json({ error: 'invalid_email' });
      target = email.trim().toLowerCase();
      const existing = await pool.query('SELECT id FROM accounts WHERE lower(email)=lower($1) AND id<>$2', [target, req.accountId]);
      if (existing.rowCount) return res.status(409).json({ error: 'email_unavailable' });
      if (purpose === 'email_link' && account.email) return res.status(409).json({ error: 'email_already_linked' });
      if (purpose === 'email_change' && !account.email_verified_at) return res.status(409).json({ error: 'verified_email_required' });
    } else {
      if (!account.email_verified_at || !account.email) return res.status(409).json({ error: 'verified_email_required' });
      target = account.email;
    }
    const challengeId = await issueChallenge(req.accountId, purpose, target);
    res.status(201).json({ challengeId, expiresInSeconds: CODE_TTL_MS / 1000 });
  } catch (error) { next(error); }
});

app.post('/v1/verification/confirm', auth, async (req, res, next) => {
  const client = await pool.connect();
  try {
    const { challengeId, code } = req.body || {};
    if (typeof challengeId !== 'string' || !/^\d{6}$/.test(String(code || ''))) return res.status(400).json({ error: 'invalid_code' });
    await client.query('BEGIN');
    const found = await client.query('SELECT * FROM verification_challenges WHERE id=$1 AND account_id=$2 FOR UPDATE', [challengeId, req.accountId]);
    if (!found.rowCount) { await client.query('ROLLBACK'); return res.status(400).json({ error: 'invalid_or_expired_code' }); }
    const challenge = found.rows[0];
    if (challenge.consumed_at || challenge.verified_at || new Date(challenge.expires_at) <= new Date() || challenge.attempts >= MAX_CODE_ATTEMPTS) {
      await client.query('ROLLBACK'); return res.status(400).json({ error: 'invalid_or_expired_code' });
    }
    if (!safeEqual(challenge.code_hash, codeDigest(challenge.id, String(code)))) {
      await client.query('UPDATE verification_challenges SET attempts=attempts+1 WHERE id=$1', [challenge.id]);
      await client.query('COMMIT'); return res.status(400).json({ error: 'invalid_or_expired_code' });
    }
    const grant = crypto.randomBytes(32).toString('base64url');
    await client.query('UPDATE verification_challenges SET verified_at=now(),grant_hash=$1,grant_expires_at=$2 WHERE id=$3', [tokenDigest(grant), new Date(Date.now() + GRANT_TTL_MS), challenge.id]);
    await client.query('COMMIT');
    res.json({ grant, expiresInSeconds: GRANT_TTL_MS / 1000, purpose: challenge.purpose, targetEmail: challenge.target_email });
  } catch (error) { await client.query('ROLLBACK').catch(() => {}); next(error); }
  finally { client.release(); }
});

app.patch('/v1/account/username', auth, async (req, res, next) => {
  const client = await pool.connect();
  try {
    const { username, grant } = req.body || {};
    if (!usernameValid(username)) return res.status(400).json({ error: 'invalid_username' });
    await client.query('BEGIN');
    const account = await client.query('SELECT email FROM accounts WHERE id=$1 FOR UPDATE', [req.accountId]);
    if (!account.rowCount || !account.rows[0].email) { await client.query('ROLLBACK'); return res.status(409).json({ error: 'verified_email_required' }); }
    await consumeGrant(req.accountId, grant, 'username_change', account.rows[0].email, client);
    const updated = await client.query('UPDATE accounts SET username=$1,updated_at=now() WHERE id=$2 RETURNING id,username,email,email_verified_at', [username, req.accountId]);
    await client.query('COMMIT'); res.json({ account: updated.rows[0] });
  } catch (error) { await client.query('ROLLBACK').catch(() => {}); if (error.code === '23505') return res.status(409).json({ error: 'username_unavailable' }); next(error); }
  finally { client.release(); }
});

app.patch('/v1/account/password', auth, async (req, res, next) => {
  const client = await pool.connect();
  try {
    const { password, grant } = req.body || {};
    if (!passwordValid(password)) return res.status(400).json({ error: 'weak_password', message: 'Use 10+ characters with lowercase, uppercase, and a digit.' });
    await client.query('BEGIN');
    const account = await client.query('SELECT email FROM accounts WHERE id=$1 FOR UPDATE', [req.accountId]);
    if (!account.rowCount || !account.rows[0].email) { await client.query('ROLLBACK'); return res.status(409).json({ error: 'verified_email_required' }); }
    await consumeGrant(req.accountId, grant, 'password_change', account.rows[0].email, client);
    const hash = await argon2.hash(password, { type: argon2.argon2id });
    await client.query('UPDATE accounts SET password_hash=$1,updated_at=now() WHERE id=$2', [hash, req.accountId]);
    await client.query('UPDATE account_sessions SET revoked_at=now() WHERE account_id=$1 AND token_id<>$2 AND revoked_at IS NULL', [req.accountId, req.authTokenId]);
    await client.query('COMMIT'); res.json({ ok: true });
  } catch (error) { await client.query('ROLLBACK').catch(() => {}); next(error); }
  finally { client.release(); }
});

app.patch('/v1/account/email', auth, async (req, res, next) => {
  const client = await pool.connect();
  try {
    const { email, grant } = req.body || {};
    if (!emailValid(email)) return res.status(400).json({ error: 'invalid_email' });
    const target = email.trim().toLowerCase();
    await client.query('BEGIN');
    const challenge = await client.query("SELECT id FROM verification_challenges WHERE account_id=$1 AND purpose IN ('email_link','email_change') AND target_email=$2 AND verified_at IS NOT NULL AND consumed_at IS NULL AND grant_expires_at>now() ORDER BY verified_at DESC LIMIT 1", [req.accountId, target]);
    if (!challenge.rowCount) { await client.query('ROLLBACK'); return res.status(403).json({ error: 'verification_required' }); }
    await consumeGrant(req.accountId, grant, challenge.rows[0].purpose, target, client);
    const updated = await client.query('UPDATE accounts SET email=$1,email_verified_at=now(),updated_at=now() WHERE id=$2 RETURNING id,username,email,email_verified_at', [target, req.accountId]);
    await client.query('COMMIT'); res.json({ account: updated.rows[0] });
  } catch (error) { await client.query('ROLLBACK').catch(() => {}); if (error.code === '23505') return res.status(409).json({ error: 'email_unavailable' }); next(error); }
  finally { client.release(); }
});

app.delete('/v1/account/email', auth, async (req, res, next) => {
  const client = await pool.connect();
  try {
    const { password, grant } = req.body || {};
    await client.query('BEGIN');
    const account = await client.query('SELECT email,password_hash FROM accounts WHERE id=$1 FOR UPDATE', [req.accountId]);
    if (!account.rowCount || !account.rows[0].email) { await client.query('ROLLBACK'); return res.status(409).json({ error: 'no_email_linked' }); }
    if (!(await argon2.verify(account.rows[0].password_hash, String(password || '')))) { await client.query('ROLLBACK'); return res.status(403).json({ error: 'invalid_credentials' }); }
    await consumeGrant(req.accountId, grant, 'email_unlink', account.rows[0].email, client);
    await client.query('UPDATE accounts SET email=NULL,email_verified_at=NULL,updated_at=now() WHERE id=$1', [req.accountId]);
    await client.query('COMMIT'); res.json({ ok: true });
  } catch (error) { await client.query('ROLLBACK').catch(() => {}); next(error); }
  finally { client.release(); }
});

app.use((error, _req, res, _next) => {
  if (error.status === 429 || error.message === 'rate_limited') return res.status(429).json({ error: 'rate_limited' });
  // Deliberately do not log request bodies, passwords, codes, grants, or SMTP details.
  console.error('account_api_error', error.code || error.name || 'unknown');
  res.status(500).json({ error: 'internal_error' });
});

if (require.main === module) {
  try { requireConfig(); app.listen(PORT, () => console.log(`account_api_listening port=${PORT}`)); }
  catch (error) { console.error(error.message); process.exit(1); }
}

module.exports = { app, codeDigest, usernameValid, emailValid, passwordValid };
