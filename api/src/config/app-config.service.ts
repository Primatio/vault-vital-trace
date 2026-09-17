import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { CredentialBody } from 'google-auth-library';

@Injectable()
export class AppConfigService {
  constructor(private readonly configService: ConfigService) {}

  get nodeEnv(): string {
    return this.configService.getOrThrow<string>('app.nodeEnv');
  }

  get isProduction(): boolean {
    return this.nodeEnv === 'production';
  }

  get port(): number {
    return this.configService.getOrThrow<number>('app.port');
  }

  get logLevel(): string {
    return this.configService.getOrThrow<string>('app.logLevel');
  }

  get apiKey(): string {
    return this.configService.getOrThrow<string>('app.apiKey');
  }

  get apiKeyHeader(): string {
    return this.configService.getOrThrow<string>('app.apiKeyHeader');
  }

  get swaggerEnabled(): boolean {
    return this.configService.getOrThrow<boolean>('app.swaggerEnabled');
  }

  get swaggerPath(): string {
    return this.configService.getOrThrow<string>('app.swaggerPath');
  }

  get gcsProjectId(): string {
    return this.configService.getOrThrow<string>('gcs.projectId');
  }

  get gcsBucketName(): string {
    return this.configService.getOrThrow<string>('gcs.bucketName');
  }

  get gcsObjectPrefix(): string {
    return this.configService.getOrThrow<string>('gcs.objectPrefix');
  }

  get gcsAllowOverwrite(): boolean {
    return this.configService.getOrThrow<boolean>('gcs.allowOverwrite');
  }

  get gcsUploadTimeoutMs(): number {
    return this.configService.getOrThrow<number>('gcs.uploadTimeoutMs');
  }

  get gcsCredentials(): CredentialBody | undefined {
    const credentialsJson = this.configService.get<string>(
      'gcs.credentialsJson',
    );
    if (!credentialsJson) {
      return undefined;
    }
    try {
      return JSON.parse(credentialsJson) as CredentialBody;
    } catch {
      throw new Error(
        'GCS_CREDENTIALS_JSON is set but is not valid JSON. Refusing to start.',
      );
    }
  }

  get gcsKeyFilename(): string | undefined {
    return this.configService.get<string>('gcs.applicationCredentials');
  }

  get maxVideoSizeMb(): number {
    return this.configService.getOrThrow<number>('upload.maxVideoSizeMb');
  }

  get maxJsonSizeMb(): number {
    return this.configService.getOrThrow<number>('upload.maxJsonSizeMb');
  }

  get maxCsvSizeMb(): number {
    return this.configService.getOrThrow<number>('upload.maxCsvSizeMb');
  }

  get maxVideoSizeBytes(): number {
    return this.maxVideoSizeMb * 1024 * 1024;
  }

  get maxJsonSizeBytes(): number {
    return this.maxJsonSizeMb * 1024 * 1024;
  }

  get maxCsvSizeBytes(): number {
    return this.maxCsvSizeMb * 1024 * 1024;
  }
}
