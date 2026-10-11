// ctx-footer 단위 테스트(docs/03 §5 3묶음). claude plugin test 로 실행.
import { describe, expect, test } from 'claude-code/testing'
import { label, toReading, WIDE_COLUMNS } from '../hooks/register'
import type { ContextReading } from '../types'

const reading = (over: Partial<ContextReading> = {}): ContextReading => ({
	percent: 53,
	tokens: 531000,
	window: 1000000,
	...over,
})

describe('toReading', () => {
	test('percent 있음 → { percent, tokens, window }', () => {
		expect(toReading({ percent: 53, tokens: 531000, window: 1000000 })).toEqual({
			percent: 53,
			tokens: 531000,
			window: 1000000,
		})
	})

	test('percent 없음 → null', () => {
		expect(toReading({ window: 1000000 })).toBe(null)
	})

	test('tokens 없음 → tokens: null(넓은 화면에서도 짧은 형식)', () => {
		const r = toReading({ percent: 53, window: 1000000 })
		expect(r && r.tokens).toBe(null)
		expect(r && label(r, WIDE_COLUMNS)).toBe('ctx 53%')
	})
})

describe('label', () => {
	test('columns 기준값-1 → 짧은 형식', () => {
		expect(label(reading(), WIDE_COLUMNS - 1)).toBe('ctx 53%')
	})

	test('columns 기준값 → 긴 형식', () => {
		expect(label(reading(), WIDE_COLUMNS)).toBe('ctx 53% · 531k/1000k')
	})

	test('columns 없음 → 짧은 형식', () => {
		expect(label(reading(), null)).toBe('ctx 53%')
	})
})

describe('SessionMode 훅', () => {
	// 엔진 호출로 구동: $.session.measure 로 값을 넣고 $.ui.mount 로 렌더를 일으킨 뒤
	// 테스트의 최하위 훅이 플러그인을 거친 뒤의 modes 를 기록한다(플러그인은 자동 로드).
	test('값 없음 → modes 그대로', async ($, on) => {
		let seen: string[] | undefined
		on('session.measure', async (_$, e) => e)
		on('ui.render', { component: 'SessionMode' }, async (_$, e) => {
			seen = [...e.props.modes]
			return { type: 'Text', children: [e.props.modes.join(' & ')] }
		})
		await $.session.measure({ context: { window: 1000000 }, rateLimits: [], changed: ['context'] })
		await $.ui.mount({
			plugin: 'ctx-footer',
			surface: 'terminal',
			component: 'SessionMode',
			props: { modes: ['focus'] },
		})
		expect(seen).toEqual(['focus'])
	})

	test('값 있음 → 끝에 라벨 하나, 기존 순서 보존', async ($, on) => {
		let seen: string[] | undefined
		on('session.measure', async (_$, e) => e)
		on('ui.render', { component: 'SessionMode' }, async (_$, e) => {
			seen = [...e.props.modes]
			return { type: 'Text', children: [e.props.modes.join(' & ')] }
		})
		await $.session.measure({
			context: { percent: 53, tokens: 531000, window: 1000000 },
			rateLimits: [],
			changed: ['context'],
		})
		await $.ui.mount({
			plugin: 'ctx-footer',
			surface: 'terminal',
			component: 'SessionMode',
			props: { modes: ['focus', 'memory paused'] },
			viewport: { columns: WIDE_COLUMNS, rows: 30 },
		})
		expect(seen).toEqual(['focus', 'memory paused', 'ctx 53% · 531k/1000k'])
	})
})
