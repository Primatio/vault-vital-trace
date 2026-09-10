import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

class ErrorDetailDto {
  @ApiPropertyOptional()
  field?: string;

  @ApiProperty()
  code!: string;

  @ApiPropertyOptional()
  expected?: string;

  @ApiPropertyOptional()
  received?: string;
}

class ErrorBodyDto {
  @ApiProperty({ example: 'VALIDATION_FAILED' })
  code!: string;

  @ApiProperty({ example: 'One or more uploaded files failed validation.' })
  message!: string;

  @ApiPropertyOptional({ type: [ErrorDetailDto] })
  details?: ErrorDetailDto[];

  @ApiProperty()
  request_id!: string;

  @ApiProperty()
  timestamp!: string;
}

export class ErrorResponseDto {
  @ApiProperty({ type: ErrorBodyDto })
  error!: ErrorBodyDto;
}
