import { ExecutionContext } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { ApiKeyGuard } from '../guards/api-key.guard';
import { AppException } from '../helpers/app.exception';

function makeContext(headers: Record<string, string>): ExecutionContext {
  return {
    switchToHttp: () => ({
      getRequest: () => ({
        header: (name: string) => headers[name.toLowerCase()],
      }),
    }),
    getHandler: () => ({}),
    getClass: () => ({}),
  } as unknown as ExecutionContext;
}

describe('ApiKeyGuard', () => {
  const appConfig = { apiKey: 'super-secret-key', apiKeyHeader: 'x-api-key' };

  function makeGuard(isPublic = false): ApiKeyGuard {
    const reflector = {
      getAllAndOverride: jest.fn().mockReturnValue(isPublic),
    } as unknown as Reflector;
    return new ApiKeyGuard(reflector, appConfig as never);
  }

  it('allows a request with the correct key', () => {
    const guard = makeGuard();
    expect(
      guard.canActivate(makeContext({ 'x-api-key': 'super-secret-key' })),
    ).toBe(true);
  });

  it('rejects a request with a missing key', () => {
    const guard = makeGuard();
    expect(() => guard.canActivate(makeContext({}))).toThrow(AppException);
  });

  it('rejects a request with the wrong key', () => {
    const guard = makeGuard();
    expect(() =>
      guard.canActivate(makeContext({ 'x-api-key': 'wrong' })),
    ).toThrow(AppException);
  });

  it('allows any request when the handler is marked @Public()', () => {
    const guard = makeGuard(true);
    expect(guard.canActivate(makeContext({}))).toBe(true);
  });
});
