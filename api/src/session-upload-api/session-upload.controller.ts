import {
  Body,
  Controller,
  HttpCode,
  HttpStatus,
  Post,
  UploadedFiles,
  UseInterceptors,
} from '@nestjs/common';
import { FileFieldsInterceptor } from '@nestjs/platform-express';
import {
  ApiBadRequestResponse,
  ApiBody,
  ApiConflictResponse,
  ApiConsumes,
  ApiCreatedResponse,
  ApiOperation,
  ApiPayloadTooLargeResponse,
  ApiTags,
} from '@nestjs/swagger';
import { ApiKeyAuth } from '../guards/decorators/api-key-auth.decorator';
import { ErrorResponseDto } from '../helpers/error-response.dto';
import { SessionUploadService } from '../session-upload/session-upload.service';
import { UPLOAD_FIELDS } from '../session-upload/session-upload.constants';
import type { SessionFiles } from '../session-upload/session-upload.types';
import { CreateSessionUploadDto } from './dto/create-session-upload.dto';
import { SessionUploadResponseDto } from './dto/session-upload-response.dto';
import { SessionFilesValidationPipe } from './pipes/session-files.validation.pipe';
import { multerOptionsFactory } from './multer-options.factory';

// Read once at module-load time, same documented exception as
// multerOptionsFactory: decorator arguments are evaluated before Nest's DI
// container exists, so this can't go through AppConfigService. The Joi
// schema still validates these values at boot.
const uploadSizeLimits = {
  maxVideoSizeMb: parseInt(process.env.MAX_VIDEO_SIZE_MB ?? '1024', 10),
  maxJsonSizeMb: parseInt(process.env.MAX_JSON_SIZE_MB ?? '16', 10),
  maxCsvSizeMb: parseInt(process.env.MAX_CSV_SIZE_MB ?? '32', 10),
};

@ApiTags('session-upload')
@ApiKeyAuth()
@Controller('sessions/uploads')
export class SessionUploadController {
  constructor(private readonly sessionUploadService: SessionUploadService) {}

  @Post()
  @HttpCode(HttpStatus.CREATED)
  @UseInterceptors(
    FileFieldsInterceptor(
      [
        { name: UPLOAD_FIELDS.VIDEO, maxCount: 1 },
        { name: UPLOAD_FIELDS.JSON_1, maxCount: 1 },
        { name: UPLOAD_FIELDS.JSON_2, maxCount: 1 },
        { name: UPLOAD_FIELDS.CSV, maxCount: 1 },
      ],
      multerOptionsFactory(),
    ),
  )
  @ApiOperation({
    summary: 'Upload the 4 session artifacts for a recording session',
  })
  @ApiConsumes('multipart/form-data')
  @ApiBody({
    schema: {
      type: 'object',
      required: [
        'sessionId',
        UPLOAD_FIELDS.VIDEO,
        UPLOAD_FIELDS.JSON_1,
        UPLOAD_FIELDS.JSON_2,
        UPLOAD_FIELDS.CSV,
      ],
      properties: {
        sessionId: {
          type: 'string',
          example: 'a1b2c3d4-5e6f-7081-9abc-def012345678',
        },
        [UPLOAD_FIELDS.VIDEO]: {
          type: 'string',
          format: 'binary',
          description: 'QuickTime video, .mov extension',
        },
        [UPLOAD_FIELDS.JSON_1]: { type: 'string', format: 'binary' },
        [UPLOAD_FIELDS.JSON_2]: { type: 'string', format: 'binary' },
        [UPLOAD_FIELDS.CSV]: { type: 'string', format: 'binary' },
      },
    },
  })
  @ApiCreatedResponse({ type: SessionUploadResponseDto })
  @ApiBadRequestResponse({ type: ErrorResponseDto })
  @ApiConflictResponse({
    type: ErrorResponseDto,
    description: 'sessionId already has uploaded artifacts',
  })
  @ApiPayloadTooLargeResponse({ type: ErrorResponseDto })
  async upload(
    @Body() dto: CreateSessionUploadDto,
    @UploadedFiles(new SessionFilesValidationPipe(uploadSizeLimits))
    files: SessionFiles,
  ): Promise<SessionUploadResponseDto> {
    return this.sessionUploadService.uploadSession(dto.sessionId, files);
  }
}
