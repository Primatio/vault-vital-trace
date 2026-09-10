import { Test } from '@nestjs/testing';
import { GoogleService } from '../google/google.service';
import { AppConfigService } from '../config/app-config.service';

const mockFile = {
  getMetadata: jest.fn(),
  delete: jest.fn(),
};
const mockBucket = {
  upload: jest.fn(),
  file: jest.fn(() => mockFile),
};
const mockStorage = {
  bucket: jest.fn(() => mockBucket),
};

jest.mock('@google-cloud/storage', () => ({
  Storage: jest.fn(() => mockStorage),
}));

describe('GoogleService', () => {
  let service: GoogleService;
  let appConfig: {
    gcsProjectId: string;
    gcsCredentials: undefined;
    gcsKeyFilename: undefined;
    gcsBucketName: string;
    gcsAllowOverwrite: boolean;
  };

  beforeEach(async () => {
    jest.clearAllMocks();
    mockFile.getMetadata.mockResolvedValue([{ size: '1234' }]);
    mockFile.delete.mockResolvedValue(undefined);
    mockBucket.upload.mockResolvedValue([mockFile]);

    appConfig = {
      gcsProjectId: 'test-project',
      gcsCredentials: undefined,
      gcsKeyFilename: undefined,
      gcsBucketName: 'test-bucket',
      gcsAllowOverwrite: false,
    };

    const moduleRef = await Test.createTestingModule({
      providers: [
        GoogleService,
        { provide: AppConfigService, useValue: appConfig },
      ],
    }).compile();

    service = moduleRef.get(GoogleService);
  });

  it('uploads with precondition when overwrite is disabled', async () => {
    const result = await service.uploadObject({
      localPath: '/tmp/file.mov',
      destination: 'sessions/abc/video.mov',
      contentType: 'video/quicktime',
      metadata: { sessionId: 'abc' },
    });

    expect(mockBucket.upload).toHaveBeenCalledWith(
      '/tmp/file.mov',
      expect.objectContaining({
        destination: 'sessions/abc/video.mov',
        contentType: 'video/quicktime',
        metadata: { metadata: { sessionId: 'abc' } },
        preconditionOpts: { ifGenerationMatch: 0 },
      }),
    );
    expect(result.objectName).toBe('sessions/abc/video.mov');
    expect(result.bucket).toBe('test-bucket');
    expect(result.gsUri).toBe('gs://test-bucket/sessions/abc/video.mov');
    expect(result.size).toBe(1234);
  });

  it('omits the precondition when overwrite is enabled', async () => {
    appConfig.gcsAllowOverwrite = true;

    await service.uploadObject({
      localPath: '/tmp/file.mov',
      destination: 'sessions/abc/video.mov',
      contentType: 'video/quicktime',
    });

    const callArgs = mockBucket.upload.mock.calls[0][1];
    expect(callArgs.preconditionOpts).toBeUndefined();
  });

  it('maps a 412 precondition failure to SESSION_ALREADY_EXISTS (409)', async () => {
    mockBucket.upload.mockRejectedValue(
      Object.assign(new Error('precondition failed'), { code: 412 }),
    );

    const error = await service
      .uploadObject({
        localPath: '/tmp/file.mov',
        destination: 'sessions/abc/video.mov',
        contentType: 'video/quicktime',
      })
      .catch((e) => e);

    expect(error).toMatchObject({ code: 'SESSION_ALREADY_EXISTS' });
    expect(error.getStatus()).toBe(409);
  });

  it('maps a 403 error to GCS_PERMISSION_DENIED (500)', async () => {
    mockBucket.upload.mockRejectedValue(
      Object.assign(new Error('forbidden'), { code: 403 }),
    );

    const error = await service
      .uploadObject({
        localPath: '/tmp/file.mov',
        destination: 'sessions/abc/video.mov',
        contentType: 'video/quicktime',
      })
      .catch((e) => e);

    expect(error).toMatchObject({ code: 'GCS_PERMISSION_DENIED' });
    expect(error.getStatus()).toBe(500);
  });

  it('maps an unknown error to GCS_UPLOAD_FAILED (500)', async () => {
    mockBucket.upload.mockRejectedValue(new Error('boom'));

    const error = await service
      .uploadObject({
        localPath: '/tmp/file.mov',
        destination: 'sessions/abc/video.mov',
        contentType: 'video/quicktime',
      })
      .catch((e) => e);

    expect(error).toMatchObject({ code: 'GCS_UPLOAD_FAILED' });
    expect(error.getStatus()).toBe(500);
  });

  it('deleteObject swallows errors (best-effort)', async () => {
    mockFile.delete.mockRejectedValue(new Error('not found'));
    await expect(
      service.deleteObject('sessions/abc/video.mov'),
    ).resolves.toBeUndefined();
  });
});
