import { Injectable, Logger, NestMiddleware } from '@nestjs/common';
import { randomUUID } from 'crypto';
import type { NextFunction, Request, Response } from 'express';

interface RequestWithId extends Request {
  id?: string;
}

@Injectable()
export class RequestContextMiddleware implements NestMiddleware {
  private readonly logger = new Logger('HTTP');

  use(req: RequestWithId, res: Response, next: NextFunction): void {
    const requestId = req.header('x-request-id') ?? randomUUID();
    req.id = requestId;
    res.setHeader('x-request-id', requestId);

    const start = Date.now();
    res.on('finish', () => {
      const durationMs = Date.now() - start;
      this.logger.log(
        `[${requestId}] ${req.method} ${req.originalUrl} -> ${res.statusCode} (${durationMs}ms)`,
      );
    });

    next();
  }
}
