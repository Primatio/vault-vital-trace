import { MiddlewareConsumer, Module, NestModule } from '@nestjs/common';
import { APP_FILTER, APP_GUARD, APP_PIPE } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { ConfigModule } from '../config/config.module';
import { GoogleModule } from '../google/google.module';
import { HealthModule } from '../health/health.module';
import { SessionUploadApiModule } from '../session-upload-api/session-upload-api.module';
import { ApiKeyGuard } from '../guards/api-key.guard';
import { AllExceptionsFilter } from '../helpers/filters/all-exceptions.filter';
import { RequestContextMiddleware } from '../helpers/middleware/request-context.middleware';

@Module({
  imports: [ConfigModule, GoogleModule, HealthModule, SessionUploadApiModule],
  providers: [
    { provide: APP_GUARD, useClass: ApiKeyGuard },
    { provide: APP_FILTER, useClass: AllExceptionsFilter },
    {
      provide: APP_PIPE,
      useValue: new ValidationPipe({
        whitelist: true,
        forbidNonWhitelisted: true,
        transform: true,
        transformOptions: { enableImplicitConversion: false },
      }),
    },
  ],
})
export class ApiModule implements NestModule {
  configure(consumer: MiddlewareConsumer): void {
    consumer.apply(RequestContextMiddleware).forRoutes('*');
  }
}
