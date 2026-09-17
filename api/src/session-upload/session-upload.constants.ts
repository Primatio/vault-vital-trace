export const UPLOAD_FIELDS = {
  VIDEO: 'videoFile',
  JSON_1: 'jsonFile1',
  JSON_2: 'jsonFile2',
  CSV: 'csvFile',
} as const;

export type UploadFieldName =
  (typeof UPLOAD_FIELDS)[keyof typeof UPLOAD_FIELDS];

export interface FieldSpec {
  field: UploadFieldName;
  extension: string;
  mimetypes: string[];
  objectName: string;
  contentType: string;
  maxSizeMb: (opts: {
    maxVideoSizeMb: number;
    maxJsonSizeMb: number;
    maxCsvSizeMb: number;
  }) => number;
}

export const FIELD_SPECS: FieldSpec[] = [
  {
    field: UPLOAD_FIELDS.VIDEO,
    extension: '.mov',
    mimetypes: [
      'video/quicktime',
      'video/x-quicktime',
      'application/octet-stream',
    ],
    objectName: 'video.mov',
    contentType: 'video/quicktime',
    maxSizeMb: ({ maxVideoSizeMb }) => maxVideoSizeMb,
  },
  {
    field: UPLOAD_FIELDS.JSON_1,
    extension: '.json',
    mimetypes: [
      'application/json',
      'text/json',
      'text/plain',
      'application/octet-stream',
    ],
    objectName: 'data-1.json',
    contentType: 'application/json',
    maxSizeMb: ({ maxJsonSizeMb }) => maxJsonSizeMb,
  },
  {
    field: UPLOAD_FIELDS.JSON_2,
    extension: '.json',
    mimetypes: [
      'application/json',
      'text/json',
      'text/plain',
      'application/octet-stream',
    ],
    objectName: 'data-2.json',
    contentType: 'application/json',
    maxSizeMb: ({ maxJsonSizeMb }) => maxJsonSizeMb,
  },
  {
    field: UPLOAD_FIELDS.CSV,
    extension: '.csv',
    mimetypes: [
      'text/csv',
      'application/csv',
      'text/plain',
      'application/vnd.ms-excel',
      'application/octet-stream',
    ],
    objectName: 'data.csv',
    contentType: 'text/csv',
    maxSizeMb: ({ maxCsvSizeMb }) => maxCsvSizeMb,
  },
];

/** Path-traversal guard: sessionId is concatenated directly into a GCS object key. */
export const SESSION_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/;

export function buildObjectKey(
  objectPrefix: string,
  sessionId: string,
  objectName: string,
): string {
  return `${objectPrefix}/${sessionId}/${objectName}`;
}
