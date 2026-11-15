import { AIParseContext } from '../contract/AIService';
import { AIParseIssueCode } from '../model/AIParseResult';
import { AIModelProvider, AIProviderResult } from './AIModelProvider';

export class FakeAIModelProvider implements AIModelProvider {
  private readonly fixtures: Map<string, string>;

  constructor(fixtures: Map<string, string>) {
    this.fixtures = fixtures;
  }

  async requestParse(text: string, _context: AIParseContext): Promise<AIProviderResult> {
    const rawResponse = this.fixtures.get(text);
    if (rawResponse === undefined) {
      return { failure: { code: AIParseIssueCode.PROVIDER_ERROR, retryable: false } };
    }
    return { rawResponse: rawResponse };
  }
}
