export interface OperationError {
  code: string;
  message: string;
  field?: string;
  retryable: boolean;
}

export interface OperationResult<T> {
  success: boolean;
  data?: T;
  error?: OperationError;
}
