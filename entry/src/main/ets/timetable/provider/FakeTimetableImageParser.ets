import { TimetableImageContext } from '../contract/TimetableImageParser';
import { TimetableProviderFailureCode } from '../contract/TimetableImageParser';
import { TimetableImageParser, TimetableProviderResult } from '../contract/TimetableImageParser';

/** 测试与 UI 联调用：按 fixture 键返回预置的课程表 JSON 或供应商失败。 */
export class FakeTimetableImageParser implements TimetableImageParser {
  private readonly fixtures: Map<string, string>;

  constructor(fixtures: Map<string, string>) {
    this.fixtures = fixtures;
  }

  async requestTimetableParse(imageToken: string, _context: TimetableImageContext): Promise<TimetableProviderResult> {
    const rawResponse = this.fixtures.get(imageToken);
    if (rawResponse === undefined) {
      return { failure: { code: TimetableProviderFailureCode.PROVIDER_ERROR, retryable: false } };
    }
    return { rawResponse: rawResponse };
  }
}
