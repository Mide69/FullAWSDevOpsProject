const express = require('express');
const { Pool } = require('pg');
const { SecretsManagerClient, GetSecretValueCommand } = require('@aws-sdk/client-secrets-manager');
const { SQSClient, SendMessageCommand } = require('@aws-sdk/client-sqs');

const app = express();
app.use(express.json());
const VERSION = process.env.APP_VERSION || '1.0.0';
const REGION = process.env.AWS_REGION || 'eu-west-2';

function log(level, msg, extra = {}) {
  console.log(JSON.stringify({ level, msg, service: 'claim-service', version: VERSION, time: new Date().toISOString(), ...extra }));
}
app.use((req, res, next) => {
  res.on('finish', () => log('info', 'request', { method: req.method, path: req.path, status: res.statusCode }));
  next();
});

let pool;
const sqs = new SQSClient({ region: REGION });

async function initDb() {
  const sm = new SecretsManagerClient({ region: REGION });
  const out = await sm.send(new GetSecretValueCommand({ SecretId: process.env.DB_SECRET_ARN }));
  const creds = JSON.parse(out.SecretString);
  pool = new Pool({
    host: process.env.DB_HOST, port: Number(process.env.DB_PORT || 5432),
    database: process.env.DB_NAME || 'govplatform', user: creds.username, password: creds.password,
    ssl: { rejectUnauthorized: false }, max: 5, connectionTimeoutMillis: 10000,
  });
  await pool.query(`CREATE TABLE IF NOT EXISTS claims (
    id SERIAL PRIMARY KEY, claimant TEXT NOT NULL, amount NUMERIC NOT NULL,
    status TEXT NOT NULL DEFAULT 'submitted', created_at TIMESTAMPTZ DEFAULT now())`);
  log('info', 'database ready');
}

app.get('/health', (req, res) => res.json({ status: 'healthy', service: 'claim-service', version: VERSION, db: !!pool }));

app.post('/claims', async (req, res) => {
  const { claimant, amount } = req.body || {};
  if (!claimant || amount == null) return res.status(400).json({ error: 'claimant and amount are required' });
  try {
    const { rows } = await pool.query(
      'INSERT INTO claims (claimant, amount) VALUES ($1, $2) RETURNING id, claimant, amount, status',
      [claimant, amount]);
    const claim = rows[0];
    // Publish to SQS for async downstream processing (event-driven architecture).
    await sqs.send(new SendMessageCommand({
      QueueUrl: process.env.CLAIMS_QUEUE_URL,
      MessageBody: JSON.stringify({ event: 'claim.submitted', claim }),
    }));
    log('info', 'claim queued', { id: claim.id });
    res.status(201).json(claim);
  } catch (err) {
    log('error', 'create failed', { error: err.message });
    res.status(500).json({ error: 'internal error' });
  }
});

app.get('/claims', async (req, res) => {
  try {
    const { rows } = await pool.query('SELECT id, claimant, amount, status, created_at FROM claims ORDER BY id');
    res.json(rows);
  } catch (err) { res.status(500).json({ error: 'internal error' }); }
});

const PORT = process.env.PORT || 3000;
if (require.main === module) {
  app.listen(PORT, () => log('info', `claim-service listening on ${PORT}`));
  (async function retry(n = 1) {
    try { await initDb(); } catch (e) {
      log('error', `db attempt ${n} failed`, { error: e.message });
      if (n < 10) setTimeout(() => retry(n + 1), 5000);
    }
  })();
}
module.exports = app;
