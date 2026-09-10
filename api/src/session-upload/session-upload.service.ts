import { Injectable, Logger } from '@nestjs/common';
import { promises as fs } from 'fs';
import { AppConfigService } from '../config/app-config.service';
import { GoogleService } from '../google/google.service';
import { FIELD_SPECS, buildObjectKey } from './session-upload.constants';
import { SessionFiles, SessionUploadResult } from './session-upload.types';

@Injectable()
export class SessionUploadService {
  private readonly logger = new Logger(SessionUploadService.name);

  constructor(
    private readonly googleService: GoogleService,
    private readonly appConfig: AppConfigService,
  ) {}

  async uploadSession(
    sessionId: string,
    files: SessionFiles,
  ): Promise<SessionUploadResult> {
    const prefix = this.appConfig.gcsObjectPrefix;

    const descriptors = FIELD_SPECS.map((spec) => {
      const file = files[spec.field];
      return {
        field: spec.field,
        destination: buildObjectKey(prefix, sessionId, spec.objectName),
        localPath: file.path as string,
        contentType: spec.contentType,
        metadata: {
          sessionId,
          fieldName: spec.field,
          originalFilename: file.originalname,
          uploadedAt: new Date().toISOString(),
        },
      };
    });

    try {
      const settled = await Promise.allSettled(
        descriptors.map((d) =>
          this.googleService.uploadObject({
            localPath: d.localPath,
            destination: d.destination,
            contentType: d.contentType,
            metadata: d.metadata,
          }),
        ),
      );

      const failures = settled.filter(
        (r): r is PromiseRejectedResult => r.status === 'rejected',
      );

      if (failures.length > 0) {
        const succeededObjectNames = settled
          .map((r, i) => ({ r, destination: descriptors[i].destination }))
          .filter(({ r }) => r.status === 'fulfilled')
          .map(({ destination }) => destination);

        if (succeededObjectNames.length > 0) {
          this.logger.warn(
            `Rolling back ${succeededObjectNames.length} objects for session ${sessionId} after partial upload failure.`,
          );
          await this.googleService.deleteObjects(succeededObjectNames);
        }

        throw failures[0].reason;
      }

      const uploaded = (
        settled as PromiseFulfilledResult<
          Awaited<ReturnType<GoogleService['uploadObject']>>
        >[]
      ).map((r) => r.value);

      const filesResult = {} as SessionUploadResult['files'];
      descriptors.forEach((d, i) => {
        filesResult[d.field] = {
          objectName: uploaded[i].objectName,
          gsUri: uploaded[i].gsUri,
          size: uploaded[i].size,
          contentType: uploaded[i].contentType,
        };
      });

      return {
        sessionId,
        bucket: this.appConfig.gcsBucketName,
        prefix: `${prefix}/${sessionId}`,
        uploadedAt: new Date().toISOString(),
        files: filesResult,
      };
    } finally {
      await Promise.all(
        descriptors.map((d) =>
          fs.rm(d.localPath, { force: true }).catch(() => undefined),
        ),
      );
    }
  }
}
