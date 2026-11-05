# ADR-0055 — Pacote com o estilo guardado e alternativas da IA no modo guiado (W10-07)

**Data:** 2026-11-06 · **Estado:** aceite · **Requisitos:** PRD EDL-13, EDL-10, EDL-01, EDL-07, CHG-007; AGENTS §2.6, §4, §7, §15.

## Contexto

O motor (numeiro-engine #16) já sabe (a) receber `input.look` e `input.style_version` no job `package` e pôr o aspeto e a música do estilo guardado na versão 1 de cada documento (`package_style`), e (b) guardar 2-3 takes alternativos por secção em `doc.ai.alternatives` (`{hook_texts, sections: {hook|body|cta: {replaces, options: [{id, segments, words, text, duration, confidence, note}]}}}`). Faltava a app mandar o aspeto no pedido e o modo guiado mostrar e usar as alternativas.

## Decisão

1. **`edit_package_request` lê o aspeto no servidor**: versão atual do estilo pedido em `edit_styles` deste cliente, não arquivado, com `look`. Junta `look` e `style_version` ao input do job; sem aspeto (estilo do catálogo, arquivado ou sem `look`) o input fica como hoje. A música só vai se continuar a ser um áudio ativo da biblioteca do cliente (a regra de `edit_style_apply`); senão vai a `null` e o resto do aspeto segue. Sem `jsonb_strip_nulls`: `highlight`/`background` a `null` querem dizer "sem destaque/sem caixa". A versão do estilo entra na chave de idempotência (`…:E01:v2`): gravar o estilo outra vez e pedir o mesmo pacote cria um job novo com o aspeto novo; pedidos com a mesma versão continuam a dar o mesmo job. Auditoria com `style_version`.
2. **`edit_doc_get` devolve `ai_alternatives`** da última versão `ai`/`import` do documento (a que o worker escreveu), não da versão aberta: as alternativas são proposta da IA, não edição.
3. **`edit_alternative_apply(p_ws, p_asset, p_base_version, p_section, p_option_id)`** monta a versão nova no servidor a partir dessas alternativas; o browser só diz a secção e o id da opção. Cortes: saem os de `replaces` e os de qualquer outra opção da mesma secção já usada, os da opção entram no lugar do primeiro que saiu (no hook, se já não houver nenhum, no início; no corpo/CTA recusa com `alternativa_sem_lugar`). Legendas: saem as palavras que só se ouviam nos cortes que saíram, entram as da opção sem repetir o mesmo instante, ordenadas pelo tempo da fonte. O resto do documento (hook, aspeto, câmaras, visuais, som, notas) fica igual. Conflito 40001 se a versão base já não é a atual; se a opção já está no documento devolve-o sem versão nova (um retry de rede não duplica nem dá conflito). Validado por `_edit_doc_problem`, auditado (`edit.alternative_applied`, com a opção, a versão da IA e os cortes substituídos) e evento `edit.version_saved`. Permitido a `edit.timeline` e `edit.guided` (`_edit_require`); não passa por `_edit_guided_problem` porque os cortes não vêm do browser (o mesmo princípio de `edit_style_apply`, ADR-0050). Os cortes substituídos ficam no `cut_pool` e podem ser repostos no modo guiado.
4. **UI:** no passo Corte, "Alternativas da IA" por secção (texto, duração, confiança, nota, "Usar esta" ou "Em uso"); precisa da versão atual sem alterações por gravar; conflito com "Recarregar", erro com "Tentar de novo", sem permissão com a mensagem do servidor. No passo Hook, os `hook_texts` entram nas alternativas com a etiqueta "alternativa da IA".

## Alternativas rejeitadas

- **Mandar os cortes da alternativa pelo `edit_doc_save`:** o modo guiado não pode criar cortes novos (`_edit_guided_problem`), e abrir essa regra deixaria o browser inventar cortes; assim o servidor só usa o que o worker guardou.
- **Ler as alternativas da versão aberta:** uma edição na linha do tempo podia alterar ou apagar `doc.ai`; a versão da IA é imutável e é a fonte certa.
- **Chave de idempotência sem a versão do estilo:** um estilo regravado devolveria o job antigo com o aspeto antigo.
- **Recusar o pacote quando a música do estilo saiu da biblioteca:** o aspeto continua útil; a música fica de fora e quem edita escolhe outra.

## Limitações

- As câmaras não são recalculadas para os cortes novos: onde não há câmara o render usa a da frente; quem tem a linha do tempo ajusta.
- `doc.render` (duração e fim do hook gravados pelo motor) não é recalculado, como em qualquer outra edição; o render recalcula a partir dos segmentos.
- Só documentos feitos pelo pacote depois do numeiro-engine #16 têm alternativas; os outros mostram o passo Corte como antes.

## Rollback

Bloco no fim de `supabase/migrations/PENDING_w10_pacote_estilo_alternativas.sql` (drop de `edit_alternative_apply`; repor `edit_doc_get` e `edit_package_request` de `20261105215624_w5_auditoria_fix.sql`). Sem mudanças de tabelas.
