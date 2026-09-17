import { diskStorage } from 'multer';
import { randomUUID } from 'crypto';
import { tmpdir } from 'os';
import type { MulterOptions } from '@nestjs/platform-express/multer/interfaces/multer-options.interface';
import { FIELD_SPECS } from '../session-upload/session-upload.constants';

/**
 * Reads env directly instead of via AppConfigService: FileFieldsInterceptor
 * needs its options at decoration time, before Nest's DI container is
 * available. Values are still validated by the Joi schema at boot.
 */
export function multerOptionsFactory(): MulterOptions {
  const maxVideoSizeMb = parseInt(process.env.MAX_VIDEO_SIZE_MB ?? '1024', 10);

  return {
    storage: diskStorage({
      destination: tmpdir(),
      filename: (_req, _file, cb) => cb(null, randomUUID()),
    }),
    limits: {
      // multer enforces fileSize globally, not per-field, so this must be
      // the largest cap (video); smaller per-field caps are enforced in
      // SessionFilesValidationPipe.
      fileSize: maxVideoSizeMb * 1024 * 1024,
      files: FIELD_SPECS.length,
      fields: 10,
      parts: 20,
    },
  };
}
