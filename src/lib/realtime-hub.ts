/*
 * Canais de tempo real partilhados (ADR-0019).
 * O cliente Supabase devolve o MESMO canal para o mesmo nome e não aceita novos ouvintes depois de subscribe():
 * dois componentes a abrir "guioes-numeiro" rebentavam a página. Aqui cada nome tem um só canal, com contagem de
 * quem o usa; o canal só fecha quando o último sai. Regra: nenhum código chama sb.channel() fora deste ficheiro.
 */
export type HubChannel = { unsubscribe?: () => unknown };
export type ChannelFactory<C extends HubChannel> = (name: string, emit: (payload: unknown) => void) => C | Promise<C>;
type Entry<C> = { ch: C | null; listeners: Set<(p: unknown) => void>; closed: boolean };

export function createChannelHub<C extends HubChannel>(remove: (ch: C) => void) {
  const entries = new Map<string, Entry<C>>();
  return {
    /** Ouve um canal; devolve a função para deixar de ouvir. */
    listen(name: string, factory: ChannelFactory<C>, fn: (payload: unknown) => void): () => void {
      let e = entries.get(name);
      if (!e) {
        const entry: Entry<C> = { ch: null, listeners: new Set(), closed: false };
        entries.set(name, entry);
        e = entry;
        const emit = (p: unknown) => entry.listeners.forEach((l) => { try { l(p); } catch (err) { console.error("realtime listener", err); } });
        Promise.resolve()
          .then(() => factory(name, emit))
          .then((ch) => { if (entry.closed) remove(ch); else entry.ch = ch; })
          .catch((err) => console.error("realtime", name, err));  // tempo real em falha não deita a página abaixo
      }
      e.listeners.add(fn);
      const mine = e;
      return () => {
        mine.listeners.delete(fn);
        if (mine.listeners.size === 0 && entries.get(name) === mine) {
          mine.closed = true;
          entries.delete(name);
          if (mine.ch) remove(mine.ch);
        }
      };
    },
    size: () => entries.size,
  };
}
