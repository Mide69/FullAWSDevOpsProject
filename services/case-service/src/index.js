const express = require('express');
const { Pool } = require('pg');
const { SecretsManagerClient, GetSecretValueCommand } = require('@aws-sdk/client-secrets-manager');

const app = express();
app.use(express.json());
const VERSION = process.env.APP_VERSION || '1.0.0';
const REGION = process.env.AWS_REGION || 'eu-west-2';

function log(level, msg, extra = {}) {
  console.log(JSON.stringify({ level, msg, service: 'case-service', version: VERSION, time: new Date().toISOString(), ...extra }));
}
app.use((req, res, next) => {
  res.on('finish', () => log('info', 'request', { method: req.method, path: req.path, status: res.statusCode }));
  next();
});

let pool;
async function initDb() {
  const sm = new SecretsManagerClient({ region: REGION });
  const out = await sm.send(new GetSecretValueCommand({ SecretId: process.env.DB_SECRET_ARN }));
  const creds = JSON.parse(out.SecretString);
  pool = new Pool({
    host: process.env.DB_HOST, port: Number(process.env.DB_PORT || 5432),
    database: process.env.DB_NAME || 'govplatform', user: creds.username, password: creds.password,
    ssl: { rejectUnauthorized: false }, max: 5, connectionTimeoutMillis: 10000,
  });
  await pool.query(`CREATE TABLE IF NOT EXISTS cases (
    id SERIAL PRIMARY KEY, reference TEXT NOT NULL, assignee TEXT,
    status TEXT NOT NULL DEFAULT 'open', created_at TIMESTAMPTZ DEFAULT now())`);
  log('info', 'database ready');
}

app.get('/health', (req, res) => res.json({ status: 'healthy', service: 'case-service', version: VERSION, db: !!pool }));

app.post('/cases', async (req, res) => {
  const { reference, assignee } = req.body || {};
  if (!reference) return res.status(400).json({ error: 'reference is required' });
  try {
    const { rows } = await pool.query(
      'INSERT INTO cases (reference, assignee) VALUES ($1, $2) RETURNING id, reference, assignee, status',
      [reference, assignee || null]);
    res.status(201).json(rows[0]);
  } catch (err) { log('error', 'create failed', { error: err.message }); res.status(500).json({ error: 'internal error' }); }
});

app.get('/cases', async (req, res) => {
  try {
    const { rows } = await pool.query('SELECT id, reference, assignee, status, created_at FROM cases ORDER BY id');
    res.json(rows);
  } catch (err) { res.status(500).json({ error: 'internal error' }); }
});

const PORT = process.env.PORT || 3000;
if (require.main === module) {
  app.listen(PORT, () => log('info', `case-service listening on ${PORT}`));
  (async function retry(n = 1) {
    try { await initDb(); } catch (e) {
      log('error', `db attempt ${n} failed`, { error: e.message });
      if (n < 10) setTimeout(() => retry(n + 1), 5000);
    }
  })();
}
module.exports = app;
