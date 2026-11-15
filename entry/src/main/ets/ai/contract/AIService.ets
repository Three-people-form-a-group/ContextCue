import { AIParseOutcome } from '../model/AIParseResult';

export interface AIParseContext {
  now: number;
  timeZone: string;
  locale: string;
}

export interface AIService {
  parseReminder(text: string, context: AIParseContext): Promise<AIParseOutcome>;
}
