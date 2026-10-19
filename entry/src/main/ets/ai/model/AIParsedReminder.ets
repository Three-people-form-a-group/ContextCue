export interface AIParsedReminder {
  content: string;
  triggerType: string;
  triggerTime: number | null;
  sceneName: string | null;
  ambiguous: boolean;
}
