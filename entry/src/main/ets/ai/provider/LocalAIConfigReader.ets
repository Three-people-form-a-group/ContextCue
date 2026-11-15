import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { AIProviderConfig, parseAIProviderConfig } from './AIProviderConfig';

export const LOCAL_AI_CONFIG_FILENAME: string = 'ai.config.local.json';

/**
 * 从应用沙箱 files 目录读取本地 AI 配置（ai.config.local.json）。
 * 文件不存在 → undefined（保持 Fake Provider 的开发模式）；
 * 文件存在但形状不合法 → 抛错（配置错误必须显性失败，不能静默降级）。
 * 本文件路径永远不在 .gitignore 覆盖的仓库内；凭证不落日志。
 */
export function readLocalAIProviderConfig(filesDir: string): AIProviderConfig | undefined {
  const path: string = filesDir + '/' + LOCAL_AI_CONFIG_FILENAME;
  let file: fs.File;
  try {
    file = fs.openSync(path, fs.OpenMode.READ_ONLY);
  } catch (_) {
    return undefined;
  }
  try {
    const stat = fs.statSync(path);
    const buf: ArrayBuffer = new ArrayBuffer(stat.size);
    fs.readSync(file.fd, buf);
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
    const json: string = decoder.decodeWithBytes(new Uint8Array(buf));
    const config = parseAIProviderConfig(json);
    if (config === undefined) {
      throw new Error('AI_CONFIG_INVALID');
    }
    return config;
  } finally {
    fs.closeSync(file);
  }
}
