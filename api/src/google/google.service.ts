import { HttpStatus, Injectable, Logger } from '@nestjs/common';
import { Storage } from '@google-cloud/storage';
import { AppConfigService } from '../config/app-config.service';
import { AppErrorCode } from '../helpers/app-error-code.enum';
import { AppException } from '../helpers/app.exception';
import { UploadObjectRequest } from './interfaces/upload-object-request.interface';
import { UploadedObject } from './interfaces/uploaded-object.interface';

interface GcsError extends Error {
  code?: number | string;
}

@Injectable()
export class GoogleService {
  private readonly logger = new Logger(GoogleService.name);
  private readonly storage: Storage;

  constructor(private readonly appConfig: AppConfigService) {
    this.storage = new Storage({
      projectId: appConfig.gcsProjectId,
      credentials: appConfig.gcsCredentials,
      // keyFilename: appConfig.gcsKeyFilename,
    });
  }

  async uploadObject(request: UploadObjectRequest): Promise<UploadedObject> {
    const bucketName = this.appConfig.gcsBucketName;
    const bucket = this.storage.bucket(bucketName);
    const allowOverwrite =
      request.allowOverwrite ?? this.appConfig.gcsAllowOverwrite;

    try {
      const [file] = await bucket.upload(request.localPath, {
        destination: request.destination,
        resumable: true,
        contentType: request.contentType,
        metadata: request.metadata ? { metadata: request.metadata } : undefined,
        ...(allowOverwrite
          ? {}
          : { preconditionOpts: { ifGenerationMatch: 0 } }),
      });

      const [metadata] = await file.getMetadata();

      return {
        objectName: request.destination,
        bucket: bucketName,
        gsUri: `gs://${bucketName}/${request.destination}`,
        publicUrl: `https://storage.googleapis.com/${bucketName}/${request.destination}`,
        size: Number(metadata.size ?? 0),
        contentType: request.contentType,
      };
    } catch (error) {
      throw this.mapUploadError(error as GcsError, request.destination);
    }
  }

  async deleteObject(objectName: string): Promise<void> {
    try {
      await this.storage
        .bucket(this.appConfig.gcsBucketName)
        .file(objectName)
        .delete({ ignoreNotFound: true });
    } catch (error) {
      this.logger.warn(
        `Best-effort delete failed for ${objectName}: ${(error as Error).message}`,
      );
    }
  }

  async deleteObjects(objectNames: string[]): Promise<void> {
    await Promise.all(objectNames.map((name) => this.deleteObject(name)));
  }

  private mapUploadError(error: GcsError, destination: string): AppException {
    const code = error.code;

    if (code === 412) {
      return new AppException(
        HttpStatus.CONFLICT,
        AppErrorCode.SESSION_ALREADY_EXISTS,
        `An object already exists at ${destination}.`,
      );
    }

    if (code === 403) {
      this.logger.error(
        `GCS permission denied for ${destination}: ${error.message}`,
      );
      return new AppException(
        HttpStatus.INTERNAL_SERVER_ERROR,
        AppErrorCode.GCS_PERMISSION_DENIED,
        'Storage backend rejected the request due to insufficient permissions.',
      );
    }

    if (code === 404) {
      this.logger.error(
        `GCS bucket not found for ${destination}: ${error.message}`,
      );
      return new AppException(
        HttpStatus.INTERNAL_SERVER_ERROR,
        AppErrorCode.GCS_BUCKET_NOT_FOUND,
        'Storage bucket was not found.',
      );
    }

    this.logger.error(
      `GCS upload failed for ${destination}: ${error.message}`,
      error.stack,
    );
    return new AppException(
      HttpStatus.INTERNAL_SERVER_ERROR,
      AppErrorCode.GCS_UPLOAD_FAILED,
      'Failed to upload file to storage. 12345',
    );
  }
}
