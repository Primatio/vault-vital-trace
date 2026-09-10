import { MulterFile } from '../helpers/multer-file.interface';
import { UploadFieldName } from './session-upload.constants';

export type SessionFiles = Record<UploadFieldName, MulterFile>;

export interface SessionUploadedFile {
  objectName: string;
  gsUri: string;
  size: number;
  contentType: string;
}

export interface SessionUploadResult {
  sessionId: string;
  bucket: string;
  prefix: string;
  uploadedAt: string;
  files: Record<UploadFieldName, SessionUploadedFile>;
}
