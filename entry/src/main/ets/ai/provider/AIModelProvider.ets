import { AIParseContext } from '../contract/AIService';
import { AIParseIssueCode } from '../model/AIParseResult';

export interface AIProviderFailure {
  code: AIParseIssueCode.NETWORK_ERROR | AIParseIssueCode.PROVIDER_ERROR;
  retryable: boolean;
}

export interface AIProviderResult {
  rawResponse?: string;
  failure?: AIProviderFailure;
}

export interface AIModelProvider {
  requestParse(text: string, context: AIParseContext): Promise<AIProviderResult>;
}
