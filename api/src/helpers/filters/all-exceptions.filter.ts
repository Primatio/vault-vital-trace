import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import { MulterError } from 'multer';
import { AppErrorCode } from '../app-error-code.enum';
import { AppException, AppExceptionDetail } from '../app.exception';

interface RequestWithId extends Request {
  id?: string;
}

@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly logger = new Logger(AllExceptionsFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const request = ctx.getRequest<RequestWithId>();
    const requestId = request.id ?? 'unknown';

    const { status, code, message, details } = this.normalize(exception);

    if (status >= 500) {
      this.logger.error(
        `[${requestId}] ${request.method} ${request.url} -> ${status} ${code}: ${message}`,
        exception instanceof Error ? exception.stack : undefined,
      );
    } else {
      this.logger.warn(
        `[${requestId}] ${request.method} ${request.url} -> ${status} ${code}: ${message}`,
      );
    }

    response.status(status).json({
      error: {
        code,
        message,
        ...(details ? { details } : {}),
        request_id: requestId,
        timestamp: new Date().toISOString(),
      },
    });
  }

  private normalize(exception: unknown): {
    status: number;
    code: string;
    message: string;
    details?: AppExceptionDetail[];
  } {
    if (exception instanceof AppException) {
      return {
        status: exception.getStatus(),
        code: exception.code,
        message: exception.message,
        details: exception.details,
      };
    }

    if (exception instanceof MulterError) {
      return this.fromMulterError(exception);
    }

    if (exception instanceof HttpException) {
      return this.fromHttpException(exception);
    }

    return {
      status: HttpStatus.INTERNAL_SERVER_ERROR,
      code: AppErrorCode.INTERNAL_ERROR,
      message: 'An unexpected error occurred.',
    };
  }

  private fromMulterError(exception: MulterError): {
    status: number;
    code: string;
    message: string;
  } {
    switch (exception.code) {
      case 'LIMIT_FILE_SIZE':
        return {
          status: HttpStatus.PAYLOAD_TOO_LARGE,
          code: AppErrorCode.FILE_TOO_LARGE,
          message: 'Uploaded file exceeds the maximum allowed size.',
        };
      case 'LIMIT_UNEXPECTED_FILE':
        return {
          status: HttpStatus.BAD_REQUEST,
          code: AppErrorCode.UNEXPECTED_FILE_FIELD,
          message: `Unexpected file field: ${exception.field ?? 'unknown'}`,
        };
      default:
        return {
          status: HttpStatus.BAD_REQUEST,
          code: AppErrorCode.MALFORMED_MULTIPART,
          message: exception.message,
        };
    }
  }

  private fromHttpException(exception: HttpException): {
    status: number;
    code: string;
    message: string;
    details?: AppExceptionDetail[];
  } {
    const status = exception.getStatus();
    const body = exception.getResponse();

    // Multer errors sometimes arrive wrapped in a BadRequestException by Nest's pipe layer.
    if (
      exception.cause instanceof MulterError ||
      (body &&
        typeof body === 'object' &&
        'message' in body &&
        typeof (body as { message?: unknown }).message === 'string' &&
        /^(LIMIT_|Unexpected field)/.test(
          (body as { message: string }).message,
        ))
    ) {
      const message =
        typeof body === 'object' && body && 'message' in body
          ? String(body.message)
          : exception.message;
      return {
        status: HttpStatus.BAD_REQUEST,
        code: AppErrorCode.MALFORMED_MULTIPART,
        message,
      };
    }

    if (
      typeof body === 'object' &&
      body !== null &&
      'message' in body &&
      Array.isArray(body.message)
    ) {
      const messages = (body as { message: string[] }).message;
      return {
        status,
        code: AppErrorCode.VALIDATION_FAILED,
        message: 'Request validation failed.',
        details: messages.map((m) => ({
          code: AppErrorCode.VALIDATION_FAILED,
          message: m,
        })),
      };
    }

    const message =
      typeof body === 'object' && body !== null && 'message' in body
        ? String(body.message)
        : exception.message;

    return {
      status,
      code: this.codeForStatus(status),
      message,
    };
  }

  private codeForStatus(status: HttpStatus): AppErrorCode {
    switch (status) {
      case HttpStatus.UNAUTHORIZED:
        return AppErrorCode.API_KEY_INVALID;
      case HttpStatus.CONFLICT:
        return AppErrorCode.SESSION_ALREADY_EXISTS;
      case HttpStatus.PAYLOAD_TOO_LARGE:
        return AppErrorCode.FILE_TOO_LARGE;
      case HttpStatus.BAD_REQUEST:
        return AppErrorCode.VALIDATION_FAILED;
      default:
        return AppErrorCode.INTERNAL_ERROR;
    }
  }
}
