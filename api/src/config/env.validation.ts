import * as Joi from 'joi';

export const envValidationSchema = Joi.object({
  NODE_ENV: Joi.string()
    .valid('development', 'test', 'production')
    .default('development'),
  PORT: Joi.number().port().default(8080),
  LOG_LEVEL: Joi.string()
    .valid('error', 'warn', 'log', 'debug', 'verbose')
    .default('log'),

  API_KEY: Joi.string().min(16).required(),
  API_KEY_HEADER: Joi.string().default('x-api-key'),

  GCS_PROJECT_ID: Joi.string().required(),
  GCS_BUCKET_NAME: Joi.string().required(),
  GCS_OBJECT_PREFIX: Joi.string().default('sessions'),
  GCS_CREDENTIALS_JSON: Joi.string().optional(),
  GOOGLE_APPLICATION_CREDENTIALS: Joi.string().optional(),
  GCS_ALLOW_OVERWRITE: Joi.boolean().default(false),
  GCS_UPLOAD_TIMEOUT_MS: Joi.number().default(600_000),

  MAX_VIDEO_SIZE_MB: Joi.number().min(1).default(1024),
  MAX_JSON_SIZE_MB: Joi.number().min(1).default(16),
  MAX_CSV_SIZE_MB: Joi.number().min(1).default(32),

  SWAGGER_ENABLED: Joi.boolean().default(true),
  SWAGGER_PATH: Joi.string().default('docs'),
}).nand('GCS_CREDENTIALS_JSON', 'GOOGLE_APPLICATION_CREDENTIALS');
