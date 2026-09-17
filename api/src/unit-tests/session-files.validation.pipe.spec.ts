import { SessionFilesValidationPipe } from '../session-upload-api/pipes/session-files.validation.pipe';
import { UPLOAD_FIELDS } from '../session-upload/session-upload.constants';
import { MulterFile } from '../helpers/multer-file.interface';
import { AppException } from '../helpers/app.exception';

const limits = { maxVideoSizeMb: 1, maxJsonSizeMb: 1, maxCsvSizeMb: 1 };

function makeFile(overrides: Partial<MulterFile> = {}): MulterFile {
  return {
    fieldname: 'x',
    originalname: 'x',
    encoding: '7bit',
    mimetype: 'application/octet-stream',
    size: 100,
    path: '/tmp/x',
    ...overrides,
  };
}

function validFiles(): Record<string, MulterFile[]> {
  return {
    [UPLOAD_FIELDS.VIDEO]: [
      makeFile({ originalname: 'a.mov', mimetype: 'video/quicktime' }),
    ],
    [UPLOAD_FIELDS.JSON_1]: [
      makeFile({ originalname: 'b.json', mimetype: 'application/json' }),
    ],
    [UPLOAD_FIELDS.JSON_2]: [
      makeFile({ originalname: 'c.json', mimetype: 'application/json' }),
    ],
    [UPLOAD_FIELDS.CSV]: [
      makeFile({ originalname: 'd.csv', mimetype: 'text/csv' }),
    ],
  };
}

function captureError(fn: () => unknown): AppException {
  try {
    fn();
  } catch (e) {
    if (e instanceof AppException) {
      return e;
    }
    throw e;
  }
  throw new Error('expected transform() to throw an AppException');
}

describe('SessionFilesValidationPipe', () => {
  const pipe = new SessionFilesValidationPipe(limits);

  it('accepts a fully valid set of files', () => {
    const result = pipe.transform(validFiles());
    expect(result[UPLOAD_FIELDS.VIDEO].originalname).toBe('a.mov');
    expect(result[UPLOAD_FIELDS.CSV].originalname).toBe('d.csv');
  });

  it('accepts a case-insensitive .MOV extension', () => {
    const files = validFiles();
    files[UPLOAD_FIELDS.VIDEO][0].originalname = 'a.MOV';
    expect(() => pipe.transform(files)).not.toThrow();
  });

  it.each(Object.values(UPLOAD_FIELDS))(
    'rejects when %s is missing',
    (field) => {
      const files = validFiles();
      delete files[field];
      const error = captureError(() => pipe.transform(files));
      expect(error.details).toEqual(
        expect.arrayContaining([
          expect.objectContaining({ field, code: 'FILE_REQUIRED' }),
        ]),
      );
    },
  );

  it('rejects the wrong extension in the video slot', () => {
    const files = validFiles();
    files[UPLOAD_FIELDS.VIDEO][0].originalname = 'a.mp4';
    const error = captureError(() => pipe.transform(files));
    expect(error.details).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          field: UPLOAD_FIELDS.VIDEO,
          code: 'INVALID_FILE_EXTENSION',
        }),
      ]),
    );
  });

  it('rejects a disallowed mimetype', () => {
    const files = validFiles();
    files[UPLOAD_FIELDS.CSV][0].mimetype = 'image/png';
    const error = captureError(() => pipe.transform(files));
    expect(error.details).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          field: UPLOAD_FIELDS.CSV,
          code: 'INVALID_FILE_MIMETYPE',
        }),
      ]),
    );
  });

  it('rejects an oversized file with a 413', () => {
    const files = validFiles();
    files[UPLOAD_FIELDS.JSON_1][0].size = 2 * 1024 * 1024;
    const error = captureError(() => pipe.transform(files));
    expect(error.getStatus()).toBe(413);
    expect(error.details).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          field: UPLOAD_FIELDS.JSON_1,
          code: 'FILE_TOO_LARGE',
        }),
      ]),
    );
  });

  it('aggregates multiple simultaneous violations into one exception', () => {
    const files = validFiles();
    delete files[UPLOAD_FIELDS.VIDEO];
    files[UPLOAD_FIELDS.CSV][0].originalname = 'd.txt';
    const error = captureError(() => pipe.transform(files));
    expect(error.details?.length).toBe(2);
  });
});
