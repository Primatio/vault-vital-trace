import { registerAs } from '@nestjs/config';

export const appConfig = registerAs('app', () => ({
  nodeEnv: process.env.NODE_ENV ?? 'development',
  port: parseInt(process.env.PORT ?? '8080', 10),
  logLevel: process.env.LOG_LEVEL ?? 'log',
  apiKey: process.env.API_KEY ?? '',
  apiKeyHeader: process.env.API_KEY_HEADER ?? 'x-api-key',
  swaggerEnabled: (process.env.SWAGGER_ENABLED ?? 'true') === 'true',
  swaggerPath: process.env.SWAGGER_PATH ?? 'docs',
}));

export const gcsConfig = registerAs('gcs', () => ({
  projectId: process.env.GCS_PROJECT_ID ?? '',
  bucketName: process.env.GCS_BUCKET_NAME ?? '',
  objectPrefix: process.env.GCS_OBJECT_PREFIX ?? 'sessions',
  credentialsJson: process.env.GCS_CREDENTIALS_JSON,
  applicationCredentials: process.env.GOOGLE_APPLICATION_CREDENTIALS,
  allowOverwrite: (process.env.GCS_ALLOW_OVERWRITE ?? 'false') === 'true',
  uploadTimeoutMs: parseInt(process.env.GCS_UPLOAD_TIMEOUT_MS ?? '600000', 10),
}));

export const uploadConfig = registerAs('upload', () => ({
  maxVideoSizeMb: parseInt(process.env.MAX_VIDEO_SIZE_MB ?? '1024', 10),
  maxJsonSizeMb: parseInt(process.env.MAX_JSON_SIZE_MB ?? '16', 10),
  maxCsvSizeMb: parseInt(process.env.MAX_CSV_SIZE_MB ?? '32', 10),
}));
