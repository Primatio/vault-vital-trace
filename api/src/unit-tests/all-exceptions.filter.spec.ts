import { ArgumentsHost, BadRequestException, HttpStatus } from '@nestjs/common';
import { MulterError } from 'multer';
import { AllExceptionsFilter } from '../helpers/filters/all-exceptions.filter';
import { AppErrorCode } from '../helpers/app-error-code.enum';
import { AppException } from '../helpers/app.exception';

function makeHost(): {
  host: ArgumentsHost;
  res: { status: jest.Mock; json: jest.Mock };
} {
  const json = jest.fn();
  const status = jest.fn().mockReturnValue({ json });
  const res = { status, json };
  const req = { id: 'req-1', method: 'POST', url: '/sessions/uploads' };
  const host = {
    switchToHttp: () => ({
      getResponse: () => res,
      getRequest: () => req,
    }),
  } as unknown as ArgumentsHost;
  return { host, res };
}

describe('AllExceptionsFilter', () => {
  const filter = new AllExceptionsFilter();

  it('passes through a structured AppException', () => {
    const { host, res } = makeHost();
    const exception = new AppException(
      HttpStatus.CONFLICT,
      AppErrorCode.SESSION_ALREADY_EXISTS,
      'already exists',
    );

    filter.catch(exception, host);

    expect(res.status).toHaveBeenCalledWith(409);
    expect(res.json).toHaveBeenCalledWith(
      expect.objectContaining({
        error: expect.objectContaining({
          code: 'SESSION_ALREADY_EXISTS',
          message: 'already exists',
          request_id: 'req-1',
        }),
      }),
    );
  });

  it('maps Nest ValidationPipe errors to VALIDATION_FAILED with details', () => {
    const { host, res } = makeHost();
    const exception = new BadRequestException(['sessionId must be a string']);

    filter.catch(exception, host);

    expect(res.status).toHaveBeenCalledWith(400);
    const body = res.json.mock.calls[0][0];
    expect(body.error.code).toBe('VALIDATION_FAILED');
    expect(body.error.details).toEqual([
      expect.objectContaining({ message: 'sessionId must be a string' }),
    ]);
  });

  it('maps a MulterError LIMIT_FILE_SIZE to 413 FILE_TOO_LARGE', () => {
    const { host, res } = makeHost();
    const exception = new MulterError('LIMIT_FILE_SIZE', 'videoFile');

    filter.catch(exception, host);

    expect(res.status).toHaveBeenCalledWith(413);
    expect(res.json.mock.calls[0][0].error.code).toBe('FILE_TOO_LARGE');
  });

  it('maps a MulterError LIMIT_UNEXPECTED_FILE to 400 UNEXPECTED_FILE_FIELD', () => {
    const { host, res } = makeHost();
    const exception = new MulterError('LIMIT_UNEXPECTED_FILE', 'extraFile');

    filter.catch(exception, host);

    expect(res.status).toHaveBeenCalledWith(400);
    expect(res.json.mock.calls[0][0].error.code).toBe('UNEXPECTED_FILE_FIELD');
  });

  it('maps an unknown error to 500 INTERNAL_ERROR without leaking details', () => {
    const { host, res } = makeHost();
    filter.catch(new Error('db exploded'), host);

    expect(res.status).toHaveBeenCalledWith(500);
    const body = res.json.mock.calls[0][0];
    expect(body.error.code).toBe('INTERNAL_ERROR');
    expect(body.error.message).not.toContain('db exploded');
  });
});
