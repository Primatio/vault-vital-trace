export interface UploadObjectRequest {
  localPath: string;
  destination: string;
  contentType: string;
  metadata?: Record<string, string>;
  allowOverwrite?: boolean;
}
