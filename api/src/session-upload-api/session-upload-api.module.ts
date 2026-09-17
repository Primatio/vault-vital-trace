import { Module } from '@nestjs/common';
import { SessionUploadModule } from '../session-upload/session-upload.module';
import { SessionUploadController } from './session-upload.controller';

@Module({
  imports: [SessionUploadModule],
  controllers: [SessionUploadController],
})
export class SessionUploadApiModule {}
