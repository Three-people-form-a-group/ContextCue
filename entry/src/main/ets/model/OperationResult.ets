export interface OperationError {
  code: string;
  message: string;
  field?: string;
  retryable: boolean;
}

export interface OperationResult<T> {
  success: boolean;
  data?: T;
  error?: OperationError;
  /**
   * 业务已保存但投递（触发注册）未完全生效时的非阻断提示。
   * 创建与投递分离：warning 不代表失败，由启动/回前台对账自动补排。
   * 冻结文件增量字段，2026-11-28 三人知悉（通知授权自愈闭环）。
   */
  warnings?: OperationError[];
}
