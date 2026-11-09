/** Erro do worker em linguagem simples; o texto técnico fica por baixo para quem dá suporte. */
export function packageErrorText(err: string | null | undefined): string {
  const e = err ?? "";
  if (/\(-9\)|sinal 9|out of memory|MemoryError/i.test(e)) return "O worker ficou sem memória a processar esta sessão. Tenta de novo; se voltar a falhar, avisa a agência.";
  if (/deixou de responder|lease/i.test(e)) return "O worker parou a meio (reinício ou atualização). Tenta de novo.";
  if (/n[aã]o consegui tirar o som|matches no streams/i.test(e)) return "Não consegui ler o som da câmara escolhida para a lapela. Confirma em que câmara está o som da lapela.";
  if (/gravacao_nao_encontrada|n[aã]o encontr/i.test(e)) return "Uma das gravações já não está pronta na Biblioteca. Carrega-a outra vez e tenta de novo.";
  return "O worker não conseguiu acabar este pacote. Tenta de novo; se voltar a falhar, avisa a agência com o detalhe abaixo.";
}
