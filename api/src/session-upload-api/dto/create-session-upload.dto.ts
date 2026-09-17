import { ApiProperty } from '@nestjs/swagger';
import { IsNotEmpty, IsString, Matches } from 'class-validator';
import { SESSION_ID_PATTERN } from '../../session-upload/session-upload.constants';

export class CreateSessionUploadDto {
  @ApiProperty({
    example: 'a1b2c3d4-5e6f-7081-9abc-def012345678',
    description:
      'Client-generated session identifier; becomes the GCS key prefix.',
  })
  @IsString()
  @IsNotEmpty()
  @Matches(SESSION_ID_PATTERN, {
    message:
      'sessionId must be 1-128 chars of [A-Za-z0-9_-] and start with an alphanumeric character',
  })
  sessionId!: string;
}
