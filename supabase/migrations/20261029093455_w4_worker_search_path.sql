-- W4-02: search_path fixo nas funções auxiliares (advisor 0011). Rollback: alter function ... reset search_path.
alter function public._agent_target_offset(jsonb) set search_path = public;
alter function public._agent_config_validate_extra(jsonb) set search_path = public;
