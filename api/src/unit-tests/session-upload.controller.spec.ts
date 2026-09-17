import { Test } from '@nestjs/testing';
import { SessionUploadController } from '../session-upload-api/session-upload.controller';
import { SessionUploadService } from '../session-upload/session-upload.service';
import { UPLOAD_FIELDS } from '../session-upload/session-upload.constants';
import { SessionFiles } from '../session-upload/session-upload.types';
import { MulterFile } from '../helpers/multer-file.interface';

function makeFile(originalname: string): MulterFile {
  return {
    fieldname: 'x',
    originalname,
    encoding: '7bit',
    mimetype: 'application/octet-stream',
    size: 10,
    path: '/tmp/x',
  };
}

describe('SessionUploadController', () => {
  let controller: SessionUploadController;
  const sessionUploadService = { uploadSession: jest.fn() };

  beforeEach(async () => {
    jest.clearAllMocks();
    const moduleRef = await Test.createTestingModule({
      controllers: [SessionUploadController],
      providers: [
        { provide: SessionUploadService, useValue: sessionUploadService },
      ],
    }).compile();

    controller = moduleRef.get(SessionUploadController);
  });

  it('delegates to SessionUploadService with the dto sessionId and validated files', async () => {
    const files: SessionFiles = {
      [UPLOAD_FIELDS.VIDEO]: makeFile('a.mov'),
      [UPLOAD_FIELDS.JSON_1]: makeFile('b.json'),
      [UPLOAD_FIELDS.JSON_2]: makeFile('c.json'),
      [UPLOAD_FIELDS.CSV]: makeFile('d.csv'),
    };
    const expected = { sessionId: 'abc123' };
    sessionUploadService.uploadSession.mockResolvedValue(expected);

    const result = await controller.upload({ sessionId: 'abc123' }, files);

    expect(sessionUploadService.uploadSession).toHaveBeenCalledWith(
      'abc123',
      files,
    );
    expect(result).toBe(expected);
  });
});
