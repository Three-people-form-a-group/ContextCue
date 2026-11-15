import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { AIProviderConfig, parseAIProviderConfig } from './AIProviderConfig';

export const LOCAL_AI_CONFIG_FILENAME: string = 'ai.config.local.json';

/** 开发回退路径：模拟器/开发机上 hdc 可写、应用可读；真机可能被 SELinux 拦截，勿依赖。 */
export const LOCAL_AI_CONFIG_FALLBACK_PATH: string = '/data/local/tmp/ai.config.local.json';

/**
 * 读取本地 AI 配置。查找顺序：
 *   1. 应用沙箱 files 目录（首选，真机/模拟器均可用——但 hdc 无法直接写入，需应用内粘贴）
 *   2. /data/local/tmp（开发回退：hdc file send 可写，供模拟器联调真实 Provider）
 * 两处都不存在 → undefined（保持 Fake Provider 的开发模式）；
 * 存在但形状不合法 → 抛错（配置错误必须显性失败，不能静默降级）。
 * 凭证不落日志。
 */
function loadConfigFrom(path: string): AIProviderConfig | undefined | null {
  let file: fs.File;
  try {
    file = fs.openSync(path, fs.OpenMode.READ_ONLY);
  } catch (_) {
    return null;
  }
  try {
    const stat = fs.statSync(path);
    const buf: ArrayBuffer = new ArrayBuffer(stat.size);
    fs.readSync(file.fd, buf);
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
    const json: string = decoder.decodeToString(new Uint8Array(buf));
    const config = parseAIProviderConfig(json);
    if (config === undefined) {
      throw new Error('AI_CONFIG_INVALID');
    }
    return config;
  } finally {
    fs.closeSync(file);
  }
}

export function readLocalAIProviderConfig(filesDir: string): AIProviderConfig | undefined {
  const primary: AIProviderConfig | undefined | null =
    loadConfigFrom(filesDir + '/' + LOCAL_AI_CONFIG_FILENAME);
  if (primary !== null) {
    return primary;
  }
  const fallback: AIProviderConfig | undefined | null = loadConfigFrom(LOCAL_AI_CONFIG_FALLBACK_PATH);
  if (fallback !== null) {
    return fallback;
  }
  return undefined;
}
