import {
  CanActivate,
  ExecutionContext,
  Injectable,
  HttpStatus,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { createHash, timingSafeEqual } from 'crypto';
import type { Request } from 'express';
import { AppConfigService } from '../config/app-config.service';
import { AppErrorCode } from '../helpers/app-error-code.enum';
import { AppException } from '../helpers/app.exception';
import { IS_PUBLIC_KEY } from './decorators/public.decorator';

@Injectable()
export class ApiKeyGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly appConfig: AppConfigService,
  ) {}

  canActivate(context: ExecutionContext): boolean {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) {
      return true;
    }

    const request = context.switchToHttp().getRequest<Request>();
    const providedKey = request.header(this.appConfig.apiKeyHeader);

    if (!providedKey) {
      throw new AppException(
        HttpStatus.UNAUTHORIZED,
        AppErrorCode.API_KEY_MISSING,
        'Invalid or missing API key.',
      );
    }

    if (!this.isValidKey(providedKey)) {
      throw new AppException(
        HttpStatus.UNAUTHORIZED,
        AppErrorCode.API_KEY_INVALID,
        'Invalid or missing API key.',
      );
    }

    return true;
  }

  private isValidKey(providedKey: string): boolean {
    const expectedHash = createHash('sha256')
      .update(this.appConfig.apiKey)
      .digest();
    const providedHash = createHash('sha256').update(providedKey).digest();
    return timingSafeEqual(expectedHash, providedHash);
  }
}
