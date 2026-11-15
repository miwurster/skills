// The part of grok-mermaid's API that register.tsx uses; the full types ship in the npm package.
export interface MermaidArt {
  plain: string[]
  width: number
}
export declare function render(src: string): MermaidArt | null
