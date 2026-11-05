# ADR-0050 — Estilos guardados no editor (W5-11)

**Data:** 2026-11-05 · **Estado:** aceite · **Requisitos:** PRD EDL-13 (parcial), VAR-02, CHG-007; AGENTS §1, §2.6, §7.

## Contexto

EDL-13: "Guardar como estilo" grava as escolhas (legendas, hook, cor, música, layouts) como preset versionado do cliente, que a IA usa na versão 1 seguinte; complementa VAR-02. Já existe o catálogo versionado de estilos por cliente (`edit_styles`, `edit_style_versions`, ADR-0027) com layouts 1080×1920, capacidade `styles.manage` e preset de edição que fixa versões.

## Decisão

1. **Reusar o catálogo do VAR-02**, sem tabela nova: `edit_style_versions.look` (nula) guarda as escolhas do editor: `captions` e `hook` (aspeto, como `doc.look`, ADR-0047), `music` (`label`, `asset`, `db`) e `layout` (o `style` do vídeo). Um trigger mantém o `look` da versão anterior quando o estilo é gravado pelo catálogo (`edit_style_save` não sabe dele). Assim um estilo guardado no editor entra no mesmo preset que a IA lê (EDL-01).
2. **Guardar como estilo** (`edit_style_from_doc`, `styles.manage`): o servidor lê a versão gravada do documento, nunca o que o browser manda. Estilo novo com chave `E01..E99` e nome; o layout é copiado do estilo do catálogo que o vídeo usa (se existir; ativo se for válido, senão rascunho). Ou versão nova de um estilo existente com a versão esperada (conflito 40001). Auditoria com antes/depois e vídeo de origem.
3. **Aplicar a outro vídeo** (`edit_style_apply`, `edit.timeline` ou `edit.guided`): versão nova do documento a partir da atual (40001 se mudou), com `look` do estilo (e `look.from` = chave e versão) e a música; a música tem de continuar ativa na biblioteca do mesmo cliente. Não muda cortes, palavras, hook, visuais nem o layout do vídeo. Aplicar outra vez não cria versão. É assim que o modo guiado muda o aspeto: o servidor monta o documento a partir de um estilo que quem gere o cliente aprovou.
4. **UI:** no modo completo, "Aspeto e estilos guardados" (cores, destaque da palavra dita, tamanho, altura, maiúsculas das legendas e do hook; aplicar e guardar como estilo); no modo guiado, o passo Estilo aplica estilos guardados. Precisa da versão atual sem alterações por gravar.

## Alternativas rejeitadas

- **Tabela nova de "estilos do editor":** duplicava versões, permissões e o preset; a IA teria de ler dois catálogos.
- **Aplicar o layout do estilo ao vídeo:** mudar de master para um split screen precisa de imagens e cortes que o documento não tem; fica guardado no estilo para a IA (versão 1 seguinte), não se aplica a um vídeo já montado.
- **Guardar o aspeto mandado pelo browser:** deixaria gravar um estilo que nenhuma versão tem.

## Limitações

- A IA ainda não lê o `look` na versão 1 (job do pacote EDL-01 por fazer); o render do export (EDL-11) tem de desenhar `doc.look` (sem ele, o aspeto por omissão do palco).
- Sem pré-visualização do estilo antes de aplicar (aplicar cria versão; desfaz-se restaurando a anterior).

## Rollback

Bloco no fim de `supabase/migrations/PENDING_w5_07b_editor_styles.sql`; a coluna `look` só sai num contract posterior.
