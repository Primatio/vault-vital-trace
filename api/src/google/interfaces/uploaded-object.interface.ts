export interface UploadedObject {
  objectName: string;
  bucket: string;
  gsUri: string;
  publicUrl: string;
  size: number;
  contentType: string;
}
