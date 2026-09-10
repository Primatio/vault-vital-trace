// Runs before any test file is imported, so env vars are in place before
// ConfigModule.forRoot()'s Joi validation runs at module-decoration time.
process.env.NODE_ENV = 'test';
process.env.API_KEY = 'e2e-test-api-key-0123456789';
process.env.GCS_PROJECT_ID = 'test-project';
process.env.GCS_BUCKET_NAME = 'test-bucket';
process.env.SWAGGER_ENABLED = 'false';
