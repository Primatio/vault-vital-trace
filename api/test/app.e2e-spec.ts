import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { join } from 'path';
import { ApiModule } from '../src/cmd/api.module';

const mockUpload = jest.fn();
const mockStorage = {
  bucket: () => ({
    upload: mockUpload,
    file: () => ({ delete: jest.fn().mockResolvedValue(undefined) }),
  }),
};

jest.mock('@google-cloud/storage', () => ({
  Storage: jest.fn(() => mockStorage),
}));

const FIXTURES = join(__dirname, 'fixtures');
// Must match test/setup-e2e.ts, which sets this before the app module loads.
const API_KEY = 'e2e-test-api-key-0123456789';

describe('SessionUploadController (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    mockUpload.mockImplementation((_localPath, opts) =>
      Promise.resolve([
        {
          getMetadata: () => Promise.resolve([{ size: '10' }]),
          delete: jest.fn(),
          name: opts.destination,
        },
      ]),
    );

    const moduleRef = await Test.createTestingModule({
      imports: [ApiModule],
    }).compile();

    app = moduleRef.createNestApplication();
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  beforeEach(() => {
    mockUpload.mockClear();
  });

  function attachAll(
    req: request.Test,
    sessionId = 'session-e2e-1',
  ): request.Test {
    return req
      .field('sessionId', sessionId)
      .attach('videoFile', join(FIXTURES, 'sample.mov'))
      .attach('jsonFile1', join(FIXTURES, 'a.json'))
      .attach('jsonFile2', join(FIXTURES, 'b.json'))
      .attach('csvFile', join(FIXTURES, 'sample.csv'));
  }

  it('GET /health is open without an API key', () => {
    return request(app.getHttpServer()).get('/health').expect(200);
  });

  it('uploads all 4 files under sessions/{sessionId}/ on the happy path', async () => {
    const res = await attachAll(
      request(app.getHttpServer())
        .post('/sessions/uploads')
        .set('x-api-key', API_KEY),
    );

    expect(res.status).toBe(201);
    expect(res.body.files.videoFile.objectName).toBe(
      'sessions/session-e2e-1/video.mov',
    );
    expect(res.body.files.jsonFile1.objectName).toBe(
      'sessions/session-e2e-1/data-1.json',
    );
    expect(res.body.files.jsonFile2.objectName).toBe(
      'sessions/session-e2e-1/data-2.json',
    );
    expect(res.body.files.csvFile.objectName).toBe(
      'sessions/session-e2e-1/data.csv',
    );
    expect(mockUpload).toHaveBeenCalledTimes(4);
  });

  it('rejects a request with no API key', async () => {
    const res = await attachAll(
      request(app.getHttpServer()).post('/sessions/uploads'),
    );
    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe('API_KEY_MISSING');
  });

  it('rejects a request missing a required file', async () => {
    const res = await request(app.getHttpServer())
      .post('/sessions/uploads')
      .set('x-api-key', API_KEY)
      .field('sessionId', 'session-e2e-2')
      .attach('videoFile', join(FIXTURES, 'sample.mov'))
      .attach('jsonFile1', join(FIXTURES, 'a.json'))
      .attach('jsonFile2', join(FIXTURES, 'b.json'));

    expect(res.status).toBe(400);
    expect(
      res.body.error.details.some(
        (d: { field: string; code: string }) =>
          d.field === 'csvFile' && d.code === 'FILE_REQUIRED',
      ),
    ).toBe(true);
  });

  it('rejects the wrong extension in the video slot', async () => {
    const res = await request(app.getHttpServer())
      .post('/sessions/uploads')
      .set('x-api-key', API_KEY)
      .field('sessionId', 'session-e2e-3')
      .attach('videoFile', join(FIXTURES, 'wrong.mp4'))
      .attach('jsonFile1', join(FIXTURES, 'a.json'))
      .attach('jsonFile2', join(FIXTURES, 'b.json'))
      .attach('csvFile', join(FIXTURES, 'sample.csv'));

    expect(res.status).toBe(400);
    expect(
      res.body.error.details.some(
        (d: { field: string; code: string }) =>
          d.field === 'videoFile' && d.code === 'INVALID_FILE_EXTENSION',
      ),
    ).toBe(true);
  });

  it('rejects a missing sessionId', async () => {
    const res = await request(app.getHttpServer())
      .post('/sessions/uploads')
      .set('x-api-key', API_KEY)
      .attach('videoFile', join(FIXTURES, 'sample.mov'))
      .attach('jsonFile1', join(FIXTURES, 'a.json'))
      .attach('jsonFile2', join(FIXTURES, 'b.json'))
      .attach('csvFile', join(FIXTURES, 'sample.csv'));

    expect(res.status).toBe(400);
  });

  it('rejects a path-traversal sessionId', async () => {
    const res = await request(app.getHttpServer())
      .post('/sessions/uploads')
      .set('x-api-key', API_KEY)
      .field('sessionId', '../escape')
      .attach('videoFile', join(FIXTURES, 'sample.mov'))
      .attach('jsonFile1', join(FIXTURES, 'a.json'))
      .attach('jsonFile2', join(FIXTURES, 'b.json'))
      .attach('csvFile', join(FIXTURES, 'sample.csv'));

    expect(res.status).toBe(400);
  });

  it('returns 409 when the storage backend reports the object already exists', async () => {
    mockUpload.mockRejectedValueOnce(
      Object.assign(new Error('precondition failed'), { code: 412 }),
    );

    const res = await attachAll(
      request(app.getHttpServer())
        .post('/sessions/uploads')
        .set('x-api-key', API_KEY),
      'session-e2e-conflict',
    );

    expect(res.status).toBe(409);
    expect(res.body.error.code).toBe('SESSION_ALREADY_EXISTS');
  });
});
