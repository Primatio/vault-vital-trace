import { Global, Module } from '@nestjs/common';
import { ConfigModule as NestConfigModule } from '@nestjs/config';
import { appConfig, gcsConfig, uploadConfig } from './configuration';
import { envValidationSchema } from './env.validation';
import { AppConfigService } from './app-config.service';

@Global()
@Module({
  imports: [
    NestConfigModule.forRoot({
      isGlobal: true,
      cache: true,
      envFilePath: ['.env.local', '.env'],
      ignoreEnvFile: process.env.NODE_ENV === 'production',
      load: [appConfig, gcsConfig, uploadConfig],
      validationSchema: envValidationSchema,
      validationOptions: { abortEarly: false, allowUnknown: true },
    }),
  ],
  providers: [AppConfigService],
  exports: [AppConfigService],
})
export class ConfigModule {}
