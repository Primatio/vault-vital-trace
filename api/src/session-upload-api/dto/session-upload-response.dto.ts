import { ApiProperty } from '@nestjs/swagger';

class SessionUploadedFileDto {
  @ApiProperty()
  objectName!: string;

  @ApiProperty()
  gsUri!: string;

  @ApiProperty()
  size!: number;

  @ApiProperty()
  contentType!: string;
}

class SessionUploadFilesDto {
  @ApiProperty({ type: SessionUploadedFileDto })
  videoFile!: SessionUploadedFileDto;

  @ApiProperty({ type: SessionUploadedFileDto })
  jsonFile1!: SessionUploadedFileDto;

  @ApiProperty({ type: SessionUploadedFileDto })
  jsonFile2!: SessionUploadedFileDto;

  @ApiProperty({ type: SessionUploadedFileDto })
  csvFile!: SessionUploadedFileDto;
}

export class SessionUploadResponseDto {
  @ApiProperty()
  sessionId!: string;

  @ApiProperty()
  bucket!: string;

  @ApiProperty()
  prefix!: string;

  @ApiProperty()
  uploadedAt!: string;

  @ApiProperty({ type: SessionUploadFilesDto })
  files!: SessionUploadFilesDto;
}
