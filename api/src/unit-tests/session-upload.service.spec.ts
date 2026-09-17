import { Test } from '@nestjs/testing';
import { promises as fs } from 'fs';
import { SessionUploadService } from '../session-upload/session-upload.service';
import { GoogleService } from '../google/google.service';
import { AppConfigService } from '../config/app-config.service';
import { UPLOAD_FIELDS } from '../session-upload/session-upload.constants';
import { GoogleServiceMock } from './mocks/google.service.mock';
import { SessionFiles } from '../session-upload/session-upload.types';
import { MulterFile } from '../helpers/multer-file.interface';

jest.mock('fs', () => ({
  promises: { rm: jest.fn().mockResolvedValue(undefined) },
}));

function makeFile(path: string, originalname: string): MulterFile {
  return {
    fieldname: 'x',
    originalname,
    encoding: '7bit',
    mimetype: 'application/octet-stream',
    size: 10,
    path,
  };
}

function sessionFiles(): SessionFiles {
  return {
    [UPLOAD_FIELDS.VIDEO]: makeFile('/tmp/video', 'a.mov'),
    [UPLOAD_FIELDS.JSON_1]: makeFile('/tmp/json1', 'b.json'),
    [UPLOAD_FIELDS.JSON_2]: makeFile('/tmp/json2', 'c.json'),
    [UPLOAD_FIELDS.CSV]: makeFile('/tmp/csv', 'd.csv'),
  };
}

describe('SessionUploadService', () => {
  let service: SessionUploadService;
  const appConfig = {
    gcsObjectPrefix: 'sessions',
    gcsBucketName: 'test-bucket',
  };

  beforeEach(async () => {
    jest.clearAllMocks();
    const moduleRef = await Test.createTestingModule({
      providers: [
        SessionUploadService,
        { provide: GoogleService, useValue: GoogleServiceMock },
        { provide: AppConfigService, useValue: appConfig },
      ],
    }).compile();

    service = moduleRef.get(SessionUploadService);
  });

  it('uploads all 4 files under the correct sessionId prefix and cleans up temp files', async () => {
    GoogleServiceMock.uploadObject.mockImplementation(
      ({ destination, contentType }) =>
        Promise.resolve({
          objectName: destination,
          bucket: 'test-bucket',
          gsUri: `gs://test-bucket/${destination}`,
          publicUrl: `https://storage.googleapis.com/test-bucket/${destination}`,
          size: 10,
          contentType,
        }),
    );

    const result = await service.uploadSession('abc123', sessionFiles());

    expect(GoogleServiceMock.uploadObject).toHaveBeenCalledTimes(4);
    expect(result.files[UPLOAD_FIELDS.VIDEO].objectName).toBe(
      'sessions/abc123/video.mov',
    );
    expect(result.files[UPLOAD_FIELDS.JSON_1].objectName).toBe(
      'sessions/abc123/data-1.json',
    );
    expect(result.files[UPLOAD_FIELDS.JSON_2].objectName).toBe(
      'sessions/abc123/data-2.json',
    );
    expect(result.files[UPLOAD_FIELDS.CSV].objectName).toBe(
      'sessions/abc123/data.csv',
    );
    expect(result.prefix).toBe('sessions/abc123');
    expect(fs.rm).toHaveBeenCalledTimes(4);
  });

  it('rolls back successfully-uploaded objects and still cleans up temp files on partial failure', async () => {
    GoogleServiceMock.uploadObject.mockImplementation(({ destination }) => {
      if (destination.endsWith('data-2.json')) {
        return Promise.reject(new Error('upload failed'));
      }
      return Promise.resolve({
        objectName: destination,
        bucket: 'test-bucket',
        gsUri: `gs://test-bucket/${destination}`,
        publicUrl: `https://storage.googleapis.com/test-bucket/${destination}`,
        size: 10,
        contentType: 'application/octet-stream',
      });
    });

    await expect(
      service.uploadSession('abc123', sessionFiles()),
    ).rejects.toThrow('upload failed');

    expect(GoogleServiceMock.deleteObjects).toHaveBeenCalledTimes(1);
    const deletedNames = GoogleServiceMock.deleteObjects.mock.calls[0][0];
    expect(deletedNames).toEqual(
      expect.arrayContaining([
        'sessions/abc123/video.mov',
        'sessions/abc123/data-1.json',
        'sessions/abc123/data.csv',
      ]),
    );
    expect(deletedNames).not.toContain('sessions/abc123/data-2.json');
    expect(fs.rm).toHaveBeenCalledTimes(4);
  });
});
