/** A single durable document. write must complete only after the value is flushed. */
export interface TextStorage {
  read(): Promise<string | undefined>;
  write(value: string): Promise<void>;
}
