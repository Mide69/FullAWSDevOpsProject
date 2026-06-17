const express = require('express');
const { Pool } = require('pg');
const { SecretsManagerClient, GetSecretValueCommand } = require('@aws-sdk/client-secrets-manager');

const app = express();
app.use(express.json());

const VERSION = process.env.APP_VERSION || '2.0.0';

// Structured JSON logging — one line per event, machine-parseable.
function log(level, msg, extra = {}) {
  console.log(JSON.stringify({
    level, msg, service: 'user-service', version: VERSION,
    time: new Date().toISOString(), ...extra,
  }));
}

app.use((req, res, next) => {
  res.on('finish', () => {
    log('info', 'request', { method: req.method, path: req.path, status: res.statusCode });
  });
  next();
});

// ---------------------------------------------------------------------------
// Database wiring.
//
// The pod runs as the `user-service` ServiceAccount → assumes its IAM role
// (IRSA). The AWS SDK below picks up those temporary credentials automatically
// — no keys in code. We use them ONLY to read the DB password from Secrets
// Manager. The DB host/name/secret-ARN come from environment variables
// (injected from Terraform outputs via a ConfigMap), because they change on
// every rebuild.
// ---------------------------------------------------------------------------
let pool; // set once the DB is ready

async function getDbCredentials() {
  const region = process.env.AWS_REGION || 'eu-west-2';
  const secretArn = process.env.DB_SECRET_ARN;
  if (!secretArn) throw new Error('DB_SECRET_ARN not set');

  const sm = new SecretsManagerClient({ region });
  const out = await sm.send(new GetSecretValueCommand({ SecretId: secretArn }));
  // RDS-managed secret is JSON: { "username": "...", "password": "..." }
  return JSON.parse(out.SecretString);
}

async function initDb() {
  const creds = await getDbCredentials();
  pool = new Pool({
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT || 5432),
    database: process.env.DB_NAME || 'govplatform',
    user: creds.username,
    password: creds.password,
    ssl: { rejectUnauthorized: false }, // dev: RDS provides TLS; prod uses the RDS CA bundle
    max: 5,
    connectionTimeoutMillis: 10000,
  });

  // Create the table if it doesn't exist (simple idempotent migration).
  await pool.query(`
    CREATE TABLE IF NOT EXISTS users (
      id    SERIAL PRIMARY KEY,
      name  TEXT NOT NULL,
      email TEXT NOT NULL UNIQUE
    )
  `);
  log('info', 'database ready');
}

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------

// Liveness: process is up. Readiness: DB is connected.
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'user-service', version: VERSION, db: !!pool });
});

app.post('/users', async (req, res) => {
  const { name, email } = req.body || {};
  if (!name || !email) {
    return res.status(400).json({ error: 'name and email are required' });
  }
  try {
    const { rows } = await pool.query(
      'INSERT INTO users (name, email) VALUES ($1, $2) RETURNING id, name, email',
      [name, email],
    );
    res.status(201).json(rows[0]);
  } catch (err) {
    if (err.code === '23505') return res.status(409).json({ error: 'email already exists' });
    log('error', 'create failed', { error: err.message });
    res.status(500).json({ error: 'internal error' });
  }
});

app.get('/users/:id', async (req, res) => {
  try {
    const { rows } = await pool.query('SELECT id, name, email FROM users WHERE id = $1', [req.params.id]);
    if (rows.length === 0) return res.status(404).json({ error: 'user not found' });
    res.json(rows[0]);
  } catch (err) {
    log('error', 'get failed', { error: err.message });
    res.status(500).json({ error: 'internal error' });
  }
});

app.get('/users', async (req, res) => {
  try {
    const { rows } = await pool.query('SELECT id, name, email FROM users ORDER BY id');
    res.json(rows);
  } catch (err) {
    log('error', 'list failed', { error: err.message });
    res.status(500).json({ error: 'internal error' });
  }
});

const PORT = process.env.PORT || 3000;
if (require.main === module) {
  // Start serving immediately so liveness passes; connect to the DB with retries.
  app.listen(PORT, () => log('info', `user-service listening on ${PORT}`));

  (async function connectWithRetry(attempt = 1) {
    try {
      await initDb();
    } catch (err) {
      log('error', `db connect attempt ${attempt} failed`, { error: err.message });
      if (attempt < 10) return setTimeout(() => connectWithRetry(attempt + 1), 5000);
      log('error', 'giving up on database after 10 attempts');
    }
  })();
}

module.exports = app;
