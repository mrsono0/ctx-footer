// Portions adapted from dashband (MIT, (c) 2026 Egon Leitner):
// https://github.com/EgonLeitner/dashband — usage reading pattern, SessionMode hook shape.
import { atom, read, update } from 'claude-code'
import type { Register, SessionContextUsage } from 'claude-code'
import type { ContextReading } from '../types'

// 폭 기준값(셀 수) — P5 확정(docs/07 M5): 가장 긴 모드 힌트에서 최대 라벨이 한 줄에 드는 최소 폭 94 + 여유 2.
export const WIDE_COLUMNS = 96

const ctx = atom({ plugin: 'ctx-footer', key: 'context' } as const, null)

export const toReading = (c: SessionContextUsage): ContextReading | null =>
	c.percent == null ? null : { percent: c.percent, tokens: c.tokens ?? null, window: c.window }

export const label = (r: ContextReading, columns: number | null): string => {
	const pct = `ctx ${r.percent}%`
	if (columns === null || columns < WIDE_COLUMNS || r.tokens === null) return pct
	return `${pct} · ${Math.round(r.tokens / 1000)}k/${Math.round(r.window / 1000)}k`
}

export const register: Register = on => {
	on('session.start', async ($, e, next) => {
		const { context } = await $.session.usage()
		await update($, ctx, () => toReading(context))
		return next(e)
	})
	on('session.measure', async ($, e, next) => {
		await update($, ctx, () => toReading(e.context))
		return next(e)
	})
	on('ui.render', { component: 'SessionMode' }, async ($, e, next) => {
		const r = await read($, ctx)
		if (r === null) return next(e)
		const columns = e.viewport?.columns ?? null
		return next({ ...e, props: { ...e.props, modes: [...e.props.modes, label(r, columns)] } })
	})
}
