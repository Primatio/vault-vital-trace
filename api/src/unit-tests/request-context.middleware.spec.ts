import { RequestContextMiddleware } from '../helpers/middleware/request-context.middleware';

describe('RequestContextMiddleware', () => {
  const middleware = new RequestContextMiddleware();

  it('generates a request id when none is provided and echoes it on the response', () => {
    const listeners: Record<string, () => void> = {};
    const req = { header: () => undefined } as unknown as Parameters<
      RequestContextMiddleware['use']
    >[0];
    const res = {
      setHeader: jest.fn(),
      on: jest.fn((event: string, cb: () => void) => {
        listeners[event] = cb;
      }),
      statusCode: 201,
    } as unknown as Parameters<RequestContextMiddleware['use']>[1];
    const next = jest.fn();

    middleware.use(req, res, next);

    expect(req.id).toEqual(expect.any(String));
    expect(res.setHeader).toHaveBeenCalledWith('x-request-id', req.id);
    expect(next).toHaveBeenCalled();

    expect(() => listeners.finish()).not.toThrow();
  });

  it('reuses an incoming x-request-id header', () => {
    const req = {
      header: (name: string) =>
        name === 'x-request-id' ? 'incoming-id' : undefined,
    } as unknown as Parameters<RequestContextMiddleware['use']>[0];
    const res = {
      setHeader: jest.fn(),
      on: jest.fn(),
      statusCode: 200,
    } as unknown as Parameters<RequestContextMiddleware['use']>[1];

    middleware.use(req, res, jest.fn());

    expect(req.id).toBe('incoming-id');
    expect(res.setHeader).toHaveBeenCalledWith('x-request-id', 'incoming-id');
  });
});
