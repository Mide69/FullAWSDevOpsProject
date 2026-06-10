const express = require('express');
const AWSXRay = require('aws-xray-sdk');
const AWS = AWSXRay.captureAWS(require('aws-sdk'));

const app = express();
AWSXRay.express.openSegment('FullAWSDevOpsApp');

app.use(express.json());

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

app.get('/api/items', async (req, res) => {
  const dynamodb = new AWS.DynamoDB.DocumentClient();
  try {
    const result = await dynamodb.scan({ TableName: process.env.TABLE_NAME }).promise();
    res.json(result.Items);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

AWSXRay.express.closeSegment();

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Server running on port ${PORT}`));

module.exports = app;
