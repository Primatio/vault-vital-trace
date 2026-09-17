import { applyDecorators } from '@nestjs/common';
import { ApiSecurity, ApiUnauthorizedResponse } from '@nestjs/swagger';
import { ErrorResponseDto } from '../../helpers/error-response.dto';

export const ApiKeyAuth = (): MethodDecorator & ClassDecorator =>
  applyDecorators(
    ApiSecurity('api-key'),
    ApiUnauthorizedResponse({ type: ErrorResponseDto }),
  );
