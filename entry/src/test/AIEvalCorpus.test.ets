import { describe, it, expect } from '@ohos/hypium';
import { AIParseContext } from '../main/ets/ai/contract/AIService';
import { DefaultAIService } from '../main/ets/ai/DefaultAIService';
import { AIParseIssueCode, AIParseStatus } from '../main/ets/ai/model/AIParseResult';
import { FakeAIModelProvider } from '../main/ets/ai/provider/FakeAIModelProvider';
import { TriggerType } from '../main/ets/model/ReminderEnums';
import { SceneResolveResult, SceneResolveStatus, SceneResolver } from '../main/ets/reminder/contract/SceneResolver';

/**
 * 中文语句评测集：每条语料标注"理想模型输出"与期望解析结果。
 * 用途一：作为 Fake 链路的回归测试，锁定解析器、校验器和映射器的既有行为。
 * 用途二：真实 Provider 接入后，把同一批语料发给真实模型统计格式合规率与字段
 * 准确率（方法见 docs/team/真实AI接入准备-2026-10-25.md），用于模型选型。
 * 语料基准时刻固定为 2026-10-25T09:00+08:00（星期日），标注相对时间时以此为据。
 */
const CORPUS_NOW: number = new Date('2026-10-25T09:00:00+08:00').getTime();

function at(iso: string): number {
  return new Date(iso).getTime();
}

interface CorpusExpectation {
  status: AIParseStatus;
  content?: string;
  triggerType?: string;
  triggerTime?: number;
  sceneId?: string;
  issueCode?: AIParseIssueCode;
}

interface CorpusSpec {
  utterance: string;
  modelResponse: string;
  expected: CorpusExpectation;
}

class CorpusResolver implements SceneResolver {
  private readonly ids: Map<string, string> = new Map();

  constructor() {
    this.ids.set('实验室', 'lab-1');
    this.ids.set('家', 'home-1');
    this.ids.set('图书馆', 'library-1');
    this.ids.set('快递站', 'courier-1');
    this.ids.set('宿舍', 'dorm-1');
    this.ids.set('健身房', 'gym-1');
    this.ids.set('办公室', 'office-1');
  }

  async resolveByName(sceneName: string): Promise<SceneResolveResult> {
    const id: string | undefined = this.ids.get(sceneName);
    if (id === undefined) {
      return { status: SceneResolveStatus.NOT_FOUND, candidates: [] };
    }
    return { status: SceneResolveStatus.RESOLVED, match: { id: id, name: sceneName }, candidates: [] };
  }
}

export default function aiEvalCorpusTest() {
  describe('aiEvalCorpusTest', () => {
    const specs: CorpusSpec[] = [
      // READY：纯时间
      {
        utterance: '明天下午两点提醒我提交实验报告',
        modelResponse: '{"content":"提交实验报告","triggerType":"TIME","triggerTime":"2026-10-26T14:00:00+08:00","sceneName":null,"ambiguous":false}',
        expected: { status: AIParseStatus.READY, content: '提交实验报告', triggerType: TriggerType.TIME, triggerTime: at('2026-10-26T14:00:00+08:00') }
      },
      {
        utterance: '今晚八点提醒我给妈妈打电话',
        modelResponse: '{"content":"给妈妈打电话","triggerType":"TIME","triggerTime":"2026-10-25T20:00:00+08:00","sceneName":null,"ambiguous":false}',
        expected: { status: AIParseStatus.READY, content: '给妈妈打电话', triggerType: TriggerType.TIME, triggerTime: at('2026-10-25T20:00:00+08:00') }
      },
      {
        utterance: '后天早上九点提醒我去取体检报告',
        modelResponse: '{"content":"去取体检报告","triggerType":"TIME","triggerTime":"2026-10-27T09:00:00+08:00","sceneName":null,"ambiguous":false}',
        expected: { status: AIParseStatus.READY, content: '去取体检报告', triggerType: TriggerType.TIME, triggerTime: at('2026-10-27T09:00:00+08:00') }
      },
      {
        utterance: '2026年11月3日15:30提醒我参加项目评审',
        modelResponse: '{"content":"参加项目评审","triggerType":"TIME","triggerTime":"2026-11-03T15:30:00+08:00","sceneName":null,"ambiguous":false}',
        expected: { status: AIParseStatus.READY, content: '参加项目评审', triggerType: TriggerType.TIME, triggerTime: at('2026-11-03T15:30:00+08:00') }
      },
      // 今天是周日，"周五"应指向未来最近的周五
      {
        utterance: '周五下午三点提醒我交周报',
        modelResponse: '{"content":"交周报","triggerType":"TIME","triggerTime":"2026-10-30T15:00:00+08:00","sceneName":null,"ambiguous":false}',
        expected: { status: AIParseStatus.READY, content: '交周报', triggerType: TriggerType.TIME, triggerTime: at('2026-10-30T15:00:00+08:00') }
      },
      {
        utterance: '十分钟后提醒我关火',
        modelResponse: '{"content":"关火","triggerType":"TIME","triggerTime":"2026-10-25T09:10:00+08:00","sceneName":null,"ambiguous":false}',
        expected: { status: AIParseStatus.READY, content: '关火', triggerType: TriggerType.TIME, triggerTime: at('2026-10-25T09:10:00+08:00') }
      },
      {
        utterance: '下午四点半提醒我去取快递',
        modelResponse: '{"content":"去取快递","triggerType":"TIME","triggerTime":"2026-10-25T16:30:00+08:00","sceneName":null,"ambiguous":false}',
        expected: { status: AIParseStatus.READY, content: '去取快递', triggerType: TriggerType.TIME, triggerTime: at('2026-10-25T16:30:00+08:00') }
      },
      {
        utterance: '12月1日上午十点提醒我续借图书馆的书',
        modelResponse: '{"content":"续借图书馆的书","triggerType":"TIME","triggerTime":"2026-12-01T10:00:00+08:00","sceneName":null,"ambiguous":false}',
        expected: { status: AIParseStatus.READY, content: '续借图书馆的书', triggerType: TriggerType.TIME, triggerTime: at('2026-12-01T10:00:00+08:00') }
      },
      // READY：纯地点
      {
        utterance: '到实验室时提醒我把实验数据拷贝到服务器',
        modelResponse: '{"content":"把实验数据拷贝到服务器","triggerType":"LOCATION","triggerTime":null,"sceneName":"实验室","ambiguous":false}',
        expected: { status: AIParseStatus.READY, content: '把实验数据拷贝到服务器', triggerType: TriggerType.LOCATION, sceneId: 'lab-1' }
      },
      {
        utterance: '路过快递站时提醒我取件',
        modelResponse: '{"content":"取件","triggerType":"LOCATION","triggerTime":null,"sceneName":"快递站","ambiguous":false}',
        expected: { status: AIParseStatus.READY, content: '取件', triggerType: TriggerType.LOCATION, sceneId: 'courier-1' }
      },
      {
        utterance: '回到宿舍后提醒我给手机充电',
        modelResponse: '{"content":"给手机充电","triggerType":"LOCATION","triggerTime":null,"sceneName":"宿舍","ambiguous":false}',
        expected: { status: AIParseStatus.READY, content: '给手机充电', triggerType: TriggerType.LOCATION, sceneId: 'dorm-1' }
      },
      {
        utterance: '到健身房时提醒我先做十分钟拉伸',
        modelResponse: '{"content":"先做十分钟拉伸","triggerType":"LOCATION","triggerTime":null,"sceneName":"健身房","ambiguous":false}',
        expected: { status: AIParseStatus.READY, content: '先做十分钟拉伸', triggerType: TriggerType.LOCATION, sceneId: 'gym-1' }
      },
      {
        utterance: '到办公室后提醒我查看报销进度',
        modelResponse: '{"content":"查看报销进度","triggerType":"LOCATION","triggerTime":null,"sceneName":"办公室","ambiguous":false}',
        expected: { status: AIParseStatus.READY, content: '查看报销进度', triggerType: TriggerType.LOCATION, sceneId: 'office-1' }
      },
      // READY：时间加地点
      {
        utterance: '明天下午四点到实验室后提醒我检查实验数据',
        modelResponse: '{"content":"检查实验数据","triggerType":"BOTH","triggerTime":"2026-10-26T16:00:00+08:00","sceneName":"实验室","ambiguous":false}',
        expected: { status: AIParseStatus.READY, content: '检查实验数据', triggerType: TriggerType.BOTH, triggerTime: at('2026-10-26T16:00:00+08:00'), sceneId: 'lab-1' }
      },
      {
        utterance: '晚上八点到家后提醒我复盘周会纪要',
        modelResponse: '{"content":"复盘周会纪要","triggerType":"BOTH","triggerTime":"2026-10-25T20:00:00+08:00","sceneName":"家","ambiguous":false}',
        expected: { status: AIParseStatus.READY, content: '复盘周会纪要', triggerType: TriggerType.BOTH, triggerTime: at('2026-10-25T20:00:00+08:00'), sceneId: 'home-1' }
      },
      {
        utterance: '明天上午十点在图书馆提醒我还参考书',
        modelResponse: '{"content":"还参考书","triggerType":"BOTH","triggerTime":"2026-10-26T10:00:00+08:00","sceneName":"图书馆","ambiguous":false}',
        expected: { status: AIParseStatus.READY, content: '还参考书', triggerType: TriggerType.BOTH, triggerTime: at('2026-10-26T10:00:00+08:00'), sceneId: 'library-1' }
      },
      {
        utterance: '周六早上九点到办公室提醒我整理结题材料',
        modelResponse: '{"content":"整理结题材料","triggerType":"BOTH","triggerTime":"2026-10-31T09:00:00+08:00","sceneName":"办公室","ambiguous":false}',
        expected: { status: AIParseStatus.READY, content: '整理结题材料', triggerType: TriggerType.BOTH, triggerTime: at('2026-10-31T09:00:00+08:00'), sceneId: 'office-1' }
      },
      {
        utterance: '下午五点半到快递站提醒我寄样品',
        modelResponse: '{"content":"寄样品","triggerType":"BOTH","triggerTime":"2026-10-25T17:30:00+08:00","sceneName":"快递站","ambiguous":false}',
        expected: { status: AIParseStatus.READY, content: '寄样品', triggerType: TriggerType.BOTH, triggerTime: at('2026-10-25T17:30:00+08:00'), sceneId: 'courier-1' }
      },
      // NEEDS_CONFIRMATION：歧义与信息缺失
      // 项目介绍 §4.4：句子没说清是出发前提醒还是到达后提醒，模型必须标记歧义
      {
        utterance: '明天下午两点去实验室，提醒我带电脑',
        modelResponse: '{"content":"带电脑","triggerType":"BOTH","triggerTime":"2026-10-26T14:00:00+08:00","sceneName":"实验室","ambiguous":true}',
        expected: { status: AIParseStatus.NEEDS_CONFIRMATION, issueCode: AIParseIssueCode.AMBIGUOUS_RESULT }
      },
      {
        utterance: '下周提醒我预约牙医',
        modelResponse: '{"content":"预约牙医","triggerType":"TIME","triggerTime":null,"sceneName":null,"ambiguous":true}',
        expected: { status: AIParseStatus.NEEDS_CONFIRMATION, issueCode: AIParseIssueCode.INVALID_TIME }
      },
      {
        utterance: '提醒我买礼物',
        modelResponse: '{"content":"买礼物","triggerType":"TIME","triggerTime":null,"sceneName":null,"ambiguous":true}',
        expected: { status: AIParseStatus.NEEDS_CONFIRMATION, issueCode: AIParseIssueCode.INVALID_TIME }
      },
      {
        utterance: '去飞行主题乐园时提醒我拍照',
        modelResponse: '{"content":"拍照","triggerType":"LOCATION","triggerTime":null,"sceneName":"飞行主题乐园","ambiguous":false}',
        expected: { status: AIParseStatus.NEEDS_CONFIRMATION, issueCode: AIParseIssueCode.UNRESOLVED_LOCATION }
      },
      {
        utterance: '提醒我参加昨天下午的总结会',
        modelResponse: '{"content":"参加总结会","triggerType":"TIME","triggerTime":"2026-10-24T16:00:00+08:00","sceneName":null,"ambiguous":false}',
        expected: { status: AIParseStatus.NEEDS_CONFIRMATION, issueCode: AIParseIssueCode.INVALID_TIME }
      },
      {
        utterance: '月底提醒我交房租',
        modelResponse: '{"content":"交房租","triggerType":"TIME","triggerTime":null,"sceneName":null,"ambiguous":true}',
        expected: { status: AIParseStatus.NEEDS_CONFIRMATION, issueCode: AIParseIssueCode.INVALID_TIME }
      },
      {
        utterance: '下次见到王老师时提醒我问答辩安排',
        modelResponse: '{"content":"问答辩安排","triggerType":"LOCATION","triggerTime":null,"sceneName":"王老师办公室","ambiguous":false}',
        expected: { status: AIParseStatus.NEEDS_CONFIRMATION, issueCode: AIParseIssueCode.UNRESOLVED_LOCATION }
      },
      {
        utterance: '嗯',
        modelResponse: '{"content":"","triggerType":"TIME","triggerTime":null,"sceneName":null,"ambiguous":true}',
        expected: { status: AIParseStatus.NEEDS_CONFIRMATION, issueCode: AIParseIssueCode.MISSING_FIELD }
      },
      // FAILED：基础设施类错误，不产生草稿
      {
        utterance: '抱歉，我无法解析这句话',
        modelResponse: '很抱歉，这句话我识别不出提醒信息。',
        expected: { status: AIParseStatus.FAILED, issueCode: AIParseIssueCode.INVALID_JSON }
      },
      {
        utterance: '截断围栏样例输入',
        modelResponse: '```json\n{content broken\n```',
        expected: { status: AIParseStatus.FAILED, issueCode: AIParseIssueCode.INVALID_JSON }
      },
      // 故意不为该语句提供 fixture：模拟供应商限流或不可用
      {
        utterance: '在吗',
        modelResponse: '',
        expected: { status: AIParseStatus.FAILED, issueCode: AIParseIssueCode.PROVIDER_ERROR }
      },
      // 容错路径：围栏包裹与多余字段不应影响正常解析
      {
        utterance: '明晚七点提醒我备份代码',
        modelResponse: '```json\n{"content":"备份代码","triggerType":"TIME","triggerTime":"2026-10-25T19:00:00+08:00","sceneName":null,"ambiguous":false}\n```',
        expected: { status: AIParseStatus.READY, content: '备份代码', triggerType: TriggerType.TIME, triggerTime: at('2026-10-25T19:00:00+08:00') }
      },
      {
        utterance: '到图书馆后提醒我借移动电源',
        modelResponse: '{"content":"借移动电源","triggerType":"LOCATION","triggerTime":null,"sceneName":"图书馆","ambiguous":false,"explanation":"用户希望到达图书馆后借设备"}',
        expected: { status: AIParseStatus.READY, content: '借移动电源', triggerType: TriggerType.LOCATION, sceneId: 'library-1' }
      }
    ];

    const fixtures = new Map<string, string>();
    for (const spec of specs) {
      if (spec.modelResponse.length > 0) {
        fixtures.set(spec.utterance, spec.modelResponse);
      }
    }
    const context: AIParseContext = { now: CORPUS_NOW, timeZone: 'Asia/Shanghai', locale: 'zh-CN' };
    const service = new DefaultAIService(new FakeAIModelProvider(fixtures), new CorpusResolver());

    for (const spec of specs) {
      it(spec.utterance, 0, async () => {
        const outcome = await service.parseReminder(spec.utterance, context);
        expect(outcome.status).assertEqual(spec.expected.status);
        if (spec.expected.content !== undefined) {
          expect(outcome.draft?.content).assertEqual(spec.expected.content);
        }
        if (spec.expected.triggerType !== undefined) {
          expect(outcome.draft?.triggerType).assertEqual(spec.expected.triggerType);
        }
        if (spec.expected.triggerTime !== undefined) {
          expect(outcome.draft?.triggerTime).assertEqual(spec.expected.triggerTime);
        }
        if (spec.expected.sceneId !== undefined) {
          expect(outcome.draft?.sceneId).assertEqual(spec.expected.sceneId);
        }
        if (spec.expected.issueCode !== undefined) {
          expect(outcome.issues[0].code).assertEqual(spec.expected.issueCode);
        }
      });
    }
  });
}
