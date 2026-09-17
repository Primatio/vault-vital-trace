import { HttpStatus, Injectable, PipeTransform } from '@nestjs/common';
import { extname } from 'path';
import { MulterFile } from '../../helpers/multer-file.interface';
import { AppErrorCode } from '../../helpers/app-error-code.enum';
import { AppException, AppExceptionDetail } from '../../helpers/app.exception';
import { FIELD_SPECS } from '../../session-upload/session-upload.constants';
import { SessionFiles } from '../../session-upload/session-upload.types';

export interface UploadSizeLimits {
  maxVideoSizeMb: number;
  maxJsonSizeMb: number;
  maxCsvSizeMb: number;
}

@Injectable()
export class SessionFilesValidationPipe implements PipeTransform<
  Record<string, MulterFile[]> | undefined,
  SessionFiles
> {
  constructor(private readonly limits: UploadSizeLimits) {}

  transform(value: Record<string, MulterFile[]> | undefined): SessionFiles {
    const files = value ?? {};
    const violations: AppExceptionDetail[] = [];
    const result = {} as SessionFiles;

    for (const spec of FIELD_SPECS) {
      const file = files[spec.field]?.[0];

      if (!file) {
        violations.push({
          field: spec.field,
          code: AppErrorCode.FILE_REQUIRED,
        });
        continue;
      }

      const ext = extname(file.originalname).toLowerCase();
      if (ext !== spec.extension) {
        violations.push({
          field: spec.field,
          code: AppErrorCode.INVALID_FILE_EXTENSION,
          expected: spec.extension,
          received: ext,
        });
        continue;
      }

      if (!spec.mimetypes.includes(file.mimetype)) {
        violations.push({
          field: spec.field,
          code: AppErrorCode.INVALID_FILE_MIMETYPE,
          expected: spec.mimetypes.join(', '),
          received: file.mimetype,
        });
        continue;
      }

      const maxSizeBytes = spec.maxSizeMb(this.limits) * 1024 * 1024;
      if (file.size > maxSizeBytes) {
        violations.push({
          field: spec.field,
          code: AppErrorCode.FILE_TOO_LARGE,
          expected: `<= ${spec.maxSizeMb(this.limits)}MB`,
          received: `${Math.round(file.size / (1024 * 1024))}MB`,
        });
        continue;
      }

      result[spec.field] = file;
    }

    if (violations.length > 0) {
      const status = violations.every(
        (v) => v.code === AppErrorCode.FILE_TOO_LARGE,
      )
        ? HttpStatus.PAYLOAD_TOO_LARGE
        : HttpStatus.BAD_REQUEST;
      throw new AppException(
        status,
        AppErrorCode.VALIDATION_FAILED,
        'One or more uploaded files failed validation.',
        violations,
      );
    }

    return result;
  }
}
