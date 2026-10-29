# ADR-0008 — Calendário e estados de produção (W3-02)

**Data:** 2026-10-29 · **Estado:** aceite · **Requisitos:** PRD M11 FR-11-01/02/03/05, workflow-registry "Produção", §20; AGENTS §6.

## Contexto

O esquema já aceitava os estados de produção do PRD, mas só `not_started` e `recorded` eram usados. A data de um guião só mudava por edição direta.

## Decisão

1. **Máquina de estados de produção** em `content_production`, mantendo a assinatura e o comportamento antigo (gravar/desfazer com `recording.confirm`). Passos novos com capacidades próprias: `calendar.schedule` (agendar, tirar da agenda, cancelar, reativar) e `production.update` (gravado ↔ em edição → pronto). Transições fora da tabela = `22023 transicao_invalida`. `published` fica para o W6.
2. **Reagendar** = `content_reschedule` com `calendar.schedule`, `lock_version` (PT409), data ≥ hoje no fuso do cliente e ≤ +400 dias; não mexe em arquivados, cancelados nem publicados. O `id` do guião mantém-se; `n` passa a ser o seguinte no dia novo. Evento `script.rescheduled`.
3. **Leitura** = `calendar_range` (máximo 63 dias) com guiões, tarefas e sessões, cada bloco só para quem tem a capacidade de leitura correspondente, e as capacidades de escrita para a UI esconder o que não se pode fazer.
4. Prazos guardados em UTC e agrupados por dia no fuso do cliente; arrastar uma tarefa mantém a hora local.
5. A lista de eventos das automações passa a uma função partilhada (`_handoff_events`) e ganha `production.editing` e `production.ready`.
6. O código de equipa vê o calendário e continua a marcar gravado, mas não reagenda nem muda a produção além disso.

## Alternativas rejeitadas

- Tabela separada de "agendamentos": duplicava a data do guião; quando houver datas distintas de gravação e publicação entram com as publicações (W6).
- Renumerar o dia de origem ao mover: mudava números já vistos pela equipa e pelo motor.

## Pendentes

Vistas por equipa/plataforma/campanha e sobrecarga, publicações no calendário (W6), templates e checklists, contrato com o motor sobre a numeração diária (**UNVERIFIED**).

## Rollback

Bloco no fim de `20261029074048_w3_calendar_production.sql`.
