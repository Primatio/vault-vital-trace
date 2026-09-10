import { HttpException, HttpStatus } from '@nestjs/common';
import { AppErrorCode } from './app-error-code.enum';

export interface AppExceptionDetail {
  field?: string;
  code: AppErrorCode;
  expected?: string;
  received?: string;
  message?: string;
}

export class AppException extends HttpException {
  constructor(
    status: HttpStatus,
    public readonly code: AppErrorCode,
    message: string,
    public readonly details?: AppExceptionDetail[],
  ) {
    super({ code, message, details }, status);
  }
}
