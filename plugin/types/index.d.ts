// ctx-footer PluginState 계약 (docs/03 D-4). 이 파일의 내보낸 이름은
// hooks 모듈이 'claude-code'에서 다시 가져오지 않고 여기서 직접 쓴다.
export type ContextReading = { percent: number; tokens: number | null; window: number }

declare module 'claude-code' {
  interface PluginState {
    'ctx-footer': { context: ContextReading | null }
  }
}
