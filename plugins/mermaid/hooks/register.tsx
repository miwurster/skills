import type { Register } from 'claude-code'
import { render } from './vendor/grok-mermaid.js'
import type { MermaidArt } from './vendor/grok-mermaid.js'

// A closed ```mermaid fence at the start of a line; one still streaming never matches.
const FENCE = /^```mermaid[ \t]*\n([\s\S]*?)\n```[ \t]*$/gm

// The reply's bullet takes two columns of the transcript's width.
const INDENT = 2

const PANE = 'mermaid'
const PAN_STEP = 20

// A left-to-right or right-to-left flowchart header, which a top-down one draws narrower.
const SIDEWAYS = /^(\s*(?:flowchart|graph)\s+)(?:LR|RL)\b/

// A run of a reply's markdown, ending with the diagram cropped to fit, if any.
export interface Part {
  text: string
  cropped?: MermaidArt
}

// The diagram the pane shows; a reload forgets it.
let shown: MermaidArt | undefined
let offset = 0

// The art that fits the room: as written, else top-down, else the narrower of the two.
function fit(source: string, room: number): MermaidArt | null {
  const art = render(source)
  if (!art || art.width <= room || !SIDEWAYS.test(source)) return art
  const upright = render(source.replace(SIDEWAYS, '$1TD'))
  if (!upright) return art
  return upright.width <= room || upright.width < art.width ? upright : art
}

function crop(art: MermaidArt, room: number): string[] {
  if (art.width <= room) return art.plain
  return [...panned(art, 0, room), `… ${room} of ${art.width} columns shown`]
}

// Swaps each Mermaid fence for a text fence holding its box-drawing art,
// cropped to the room when no layout fits, and splits the markdown after each cropped one.
// A fence the renderer can't draw stays as written.
export function drawParts(markdown: string, columns = Infinity): Part[] {
  const room = columns - INDENT
  const parts: Part[] = []
  let text = ''
  let from = 0
  for (const match of markdown.matchAll(FENCE)) {
    const art = fit(match[1], room)
    if (!art) continue
    text += markdown.slice(from, match.index) + '```text\n' + crop(art, room).join('\n') + '\n```'
    from = match.index + match[0].length
    if (art.width > room) {
      parts.push({ text, cropped: art })
      text = ''
    }
  }
  parts.push({ text: text + markdown.slice(from) })
  return parts
}

export function panned(art: MermaidArt, from: number, room: number): string[] {
  return art.plain.map(line => [...line].slice(from, from + room).join(''))
}

export const register: Register = on => {
  on('ui.render', { component: 'AssistantMessage' }, ($, e, next) => {
    const parts = drawParts(e.props.text, e.viewport?.columns)
    if (parts.length === 1) {
      const { text } = parts[0]
      return next(text === e.props.text ? e : { ...e, props: { ...e.props, text } })
    }
    const { Box, Button, Markdown } = $.ui.resolve(e)
    const show = (art: MermaidArt) => async () => {
      shown = art
      offset = 0
      await $.ui.open({ id: PANE, title: 'Mermaid', focus: true })
      $.ui.invalidate('ui.render')
    }
    return (
      <Box flexDirection="column">
        {parts.map((part, index) => (
          <Box flexDirection="column">
            {part.text && <Markdown text={part.text} />}
            {part.cropped && (
              <Button key={`mermaid-${index}`} onPress={show(part.cropped)}>
                Show full chart
              </Button>
            )}
          </Box>
        ))}
      </Box>
    )
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, ($, e) => {
    const { Box, Button, Text } = $.ui.resolve(e)
    if (!shown) return <Text dimColor>Press Show full chart under a cropped diagram.</Text>
    const art = shown
    const room = Math.max(1, (e.viewport?.columns ?? 80) - 4)
    const last = Math.max(0, art.width - room)
    const pan = (by: number) => () => {
      offset = Math.min(last, Math.max(0, offset + by))
      $.ui.invalidate('ui.render')
    }
    return (
      <Box flexDirection="column">
        {last > 0 && (
          <Box gap={1}>
            <Button hotkey="h" onPress={pan(-PAN_STEP)}>◀</Button>
            <Button hotkey="l" onPress={pan(PAN_STEP)}>▶</Button>
            <Text dimColor>
              columns {offset + 1}–{Math.min(art.width, offset + room)} of {art.width}
            </Text>
          </Box>
        )}
        {panned(art, offset, room).map(line => (
          <Text wrap="truncate-end">{line}</Text>
        ))}
      </Box>
    )
  })
}
