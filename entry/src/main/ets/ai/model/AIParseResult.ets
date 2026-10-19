import { CreateReminderInput } from '../../model/CreateReminderInput';

export enum AIParseStatus {
  READY = 'READY',
  NEEDS_CONFIRMATION = 'NEEDS_CONFIRMATION',
  FAILED = 'FAILED'
}

export enum AIParseIssueCode {
  NETWORK_ERROR = 'NETWORK_ERROR',
  PROVIDER_ERROR = 'PROVIDER_ERROR',
  INVALID_JSON = 'INVALID_JSON',
  MISSING_FIELD = 'MISSING_FIELD',
  INVALID_FIELD = 'INVALID_FIELD',
  INVALID_TIME = 'INVALID_TIME',
  UNRESOLVED_LOCATION = 'UNRESOLVED_LOCATION',
  AMBIGUOUS_RESULT = 'AMBIGUOUS_RESULT',
  INVALID_INPUT = 'INVALID_INPUT',
  SCENE_RESOLVER_ERROR = 'SCENE_RESOLVER_ERROR'
}

export interface AIParseIssue {
  code: AIParseIssueCode;
  field?: string;
  message: string;
  retryable: boolean;
}

export interface AIParseOutcome {
  status: AIParseStatus;
  draft?: CreateReminderInput;
  issues: AIParseIssue[];
}
