const request = require('supertest');
const app = require('../../app/src/index');

// Mock AWS SDK to avoid real calls in unit tests
jest.mock('aws-xray-sdk', () => ({
  captureAWS: (aws) => aws,
  express: {
    openSegment: () => (req, res, next) => next(),
    closeSegment: () => (req, res, next) => next()
  }
}));

jest.mock('aws-sdk', () => ({
  DynamoDB: {
    DocumentClient: jest.fn().mockImplementation(() => ({
      scan: jest.fn().mockReturnValue({
        promise: jest.fn().mockResolvedValue({ Items: [{ id: '1', name: 'Test Item' }] })
      })
    }))
  }
}));

describe('GET /health', () => {
  it('returns 200 with healthy status', async () => {
    const res = await request(app).get('/health');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('healthy');
    expect(res.body.timestamp).toBeDefined();
  });
});

describe('GET /api/items', () => {
  it('returns items from DynamoDB', async () => {
    process.env.TABLE_NAME = 'test-table';
    const res = await request(app).get('/api/items');
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    expect(res.body[0].name).toBe('Test Item');
  });

  it('returns 500 when DynamoDB fails', async () => {
    const AWS = require('aws-sdk');
    AWS.DynamoDB.DocumentClient.mockImplementationOnce(() => ({
      scan: jest.fn().mockReturnValue({
        promise: jest.fn().mockRejectedValue(new Error('DynamoDB error'))
      })
    }));
    const res = await request(app).get('/api/items');
    expect(res.status).toBe(500);
    expect(res.body.error).toBeDefined();
  });
});
