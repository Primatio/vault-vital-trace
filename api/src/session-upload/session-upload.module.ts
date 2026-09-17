import { Module } from '@nestjs/common';
import { GoogleModule } from '../google/google.module';
import { SessionUploadService } from './session-upload.service';

@Module({
  imports: [GoogleModule],
  providers: [SessionUploadService],
  exports: [SessionUploadService],
})
export class SessionUploadModule {}
