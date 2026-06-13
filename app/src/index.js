const express = require('express');

const app = express();
app.use(express.json());

const VERSION = process.env.APP_VERSION || '1.0.0';

// Structured JSON logging — one line per request, machine-parseable.
// In a government platform every log line carries enough to trace a request.
function log(level, msg, extra = {}) {
  console.log(JSON.stringify({
    level,
    msg,
    service: 'user-service',
    version: VERSION,
    time: new Date().toISOString(),
    ...extra,
  }));
}

app.use((req, res, next) => {
  res.on('finish', () => {
    log('info', 'request', { method: req.method, path: req.path, status: res.statusCode });
  });
  next();
});

// In-memory store — replaced by RDS PostgreSQL in a later phase.
const users = new Map();
let nextId = 1;

// Liveness/readiness probe target. Kubernetes hits this constantly.
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'user-service', version: VERSION });
});

app.post('/users', (req, res) => {
  const { name, email } = req.body || {};
  if (!name || !email) {
    return res.status(400).json({ error: 'name and email are required' });
  }
  const id = String(nextId++);
  const user = { id, name, email };
  users.set(id, user);
  res.status(201).json(user);
});

app.get('/users/:id', (req, res) => {
  const user = users.get(req.params.id);
  if (!user) return res.status(404).json({ error: 'user not found' });
  res.json(user);
});

app.get('/users', (req, res) => {
  res.json(Array.from(users.values()));
});

const PORT = process.env.PORT || 3000;
if (require.main === module) {
  app.listen(PORT, () => log('info', `user-service listening on ${PORT}`));
}

module.exports = app;
