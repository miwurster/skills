import { expect, test } from 'claude-code/testing'
import { drawParts, panned } from './register'

const drawn = (markdown: string, columns?: number) =>
  drawParts(markdown, columns)
    .map(part => part.text)
    .join('')

const sequence = [
  '```mermaid',
  'sequenceDiagram',
  '    User->>UI: choose command',
  '```',
].join('\n')

test('draws a closed Mermaid fence as a text fence', () => {
  const out = drawn(`Before\n\n${sequence}\n\nAfter`)
  expect(out).toContain('```text\n')
  expect(out).toContain('choose command')
  expect(out).not.toContain('```mermaid')
  expect(out.startsWith('Before\n\n')).toBe(true)
  expect(out.endsWith('\n\nAfter')).toBe(true)
})

test('leaves a fence that is still streaming as written', () => {
  const open = '```mermaid\nsequenceDiagram\n    User->>UI: choose'
  expect(drawn(open)).toBe(open)
})

test('leaves a fence the renderer cannot draw as written', () => {
  const pie = '```mermaid\npie\n    "a" : 1\n```'
  expect(drawn(pie)).toBe(pie)
})

const sideways = [
  '```mermaid',
  'flowchart LR',
  '    A[first step] --> B[second step] --> C[third step]',
  '```',
].join('\n')

test('redraws a sideways flowchart top-down when it does not fit', () => {
  const wide = drawn(sideways)
  const narrow = drawn(sideways, 30)
  const widest = (out: string) => Math.max(...out.split('\n').map(line => [...line].length))
  expect(widest(wide)).toBeGreaterThan(28)
  expect(widest(narrow)).toBeLessThanOrEqual(28)
  expect(narrow).toContain('third step')
})

test('crops a diagram no layout fits and says how much is shown', () => {
  const out = drawn(sequence, 10)
  expect(out).toContain('```text\n')
  expect(out).not.toContain('```mermaid')
  expect(out).toContain('… 8 of ')
})

test('splits the reply after each cropped diagram, carrying its full art', () => {
  const parts = drawParts(`Before\n\n${sequence}\n\nAfter`, 10)
  expect(parts).toHaveLength(2)
  expect(parts[0].text.startsWith('Before\n\n```text\n')).toBe(true)
  expect(parts[0].cropped?.plain.join('\n')).toContain('choose command')
  expect(parts[1]).toEqual({ text: '\n\nAfter' })
})

test('keeps a reply whose diagrams fit in one part', () => {
  const parts = drawParts(`Before\n\n${sequence}\n\nAfter`)
  expect(parts).toHaveLength(1)
  expect(parts[0].cropped).toBeUndefined()
})

test('pans a window across the art', () => {
  const art = { plain: ['abcdef', 'ghijkl'], width: 6 }
  expect(panned(art, 2, 3)).toEqual(['cde', 'ijk'])
})

// The plugin's userConfig requires a token; the mod never reads it.
const options = { SONARQUBE_TOKEN: 'unused' }

test('a button under a cropped diagram shows the full chart in the pane', { options }, async ($, on) => {
  const opened: string[] = []
  on('ui.open', (_$, e) => {
    opened.push(e.id)
    return { value: { isPlaced: true } }
  })
  for (const surface of ['terminal', 'desktop'] as const) {
    const reply = await $.ui.mount({
      plugin: 'mermaid',
      surface,
      component: 'AssistantMessage',
      viewport: { columns: 12, rows: 40 },
      props: { text: `Before\n\n${sequence}\n\nAfter`, isFirstOfReply: true },
    })
    await reply.press({ key: 'mermaid-0' })
    expect(opened.at(-1)).toBe('mermaid')
    const pane = await $.ui.mount({
      plugin: 'mermaid',
      surface,
      component: 'Pane',
      requestId: 'mermaid',
      viewport: { columns: 80, rows: 40 },
      props: {},
    })
    expect(await pane.find({ type: 'Text', text: /choose command/ })).toBeDefined()
    await pane.unmount()
    await reply.unmount()
  }
})
