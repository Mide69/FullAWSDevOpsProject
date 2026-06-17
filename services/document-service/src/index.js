const express = require('express');
const { S3Client, ListObjectsV2Command, PutObjectCommand } = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
const crypto = require('crypto');

const app = express();
app.use(express.json());
const VERSION = process.env.APP_VERSION || '1.0.0';
const REGION = process.env.AWS_REGION || 'eu-west-2';
const BUCKET = process.env.DOCUMENTS_BUCKET;

function log(level, msg, extra = {}) {
  console.log(JSON.stringify({ level, msg, service: 'document-service', version: VERSION, time: new Date().toISOString(), ...extra }));
}
app.use((req, res, next) => {
  res.on('finish', () => log('info', 'request', { method: req.method, path: req.path, status: res.statusCode }));
  next();
});

const s3 = new S3Client({ region: REGION });

app.get('/health', (req, res) => res.json({ status: 'healthy', service: 'document-service', version: VERSION, bucket: !!BUCKET }));

// Citizen requests a short-lived URL, then uploads the file straight to S3 —
// the service never handles the file bytes. Faster and cheaper.
app.post('/documents/presign', async (req, res) => {
  const { filename } = req.body || {};
  if (!filename) return res.status(400).json({ error: 'filename is required' });
  try {
    const key = `${crypto.randomUUID()}/${filename}`;
    const url = await getSignedUrl(s3, new PutObjectCommand({ Bucket: BUCKET, Key: key }), { expiresIn: 300 });
    res.status(201).json({ key, uploadUrl: url, expiresInSeconds: 300 });
  } catch (err) { log('error', 'presign failed', { error: err.message }); res.status(500).json({ error: 'internal error' }); }
});

app.get('/documents', async (req, res) => {
  try {
    const out = await s3.send(new ListObjectsV2Command({ Bucket: BUCKET, MaxKeys: 100 }));
    res.json((out.Contents || []).map(o => ({ key: o.Key, size: o.Size, lastModified: o.LastModified })));
  } catch (err) { log('error', 'list failed', { error: err.message }); res.status(500).json({ error: 'internal error' }); }
});

const PORT = process.env.PORT || 3000;
if (require.main === module) {
  app.listen(PORT, () => log('info', `document-service listening on ${PORT}`));
}
module.exports = app;
