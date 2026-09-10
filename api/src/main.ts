import { NestFactory } from '@nestjs/core';
import { NestExpressApplication } from '@nestjs/platform-express';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import helmet from 'helmet';
import { ApiModule } from './cmd/api.module';
import { AppConfigService } from './config/app-config.service';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create<NestExpressApplication>(ApiModule);
  const appConfig = app.get(AppConfigService);

  app.use(helmet());
  app.enableShutdownHooks();

  if (appConfig.swaggerEnabled) {
    const document = SwaggerModule.createDocument(
      app,
      new DocumentBuilder()
        .setTitle('Vault Vital Trace API')
        .setDescription(
          'Session artifact ingestion: uploads a .mov, two .json and a .csv to Google Cloud Storage.',
        )
        .setVersion('1.0')
        .addApiKey(
          { type: 'apiKey', name: appConfig.apiKeyHeader, in: 'header' },
          'api-key',
        )
        .build(),
    );
    SwaggerModule.setup(appConfig.swaggerPath, app, document, {
      swaggerOptions: { persistAuthorization: true },
    });
  }

  await app.listen(appConfig.port);
}

void bootstrap();
