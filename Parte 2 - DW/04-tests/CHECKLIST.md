# Checklist de Testes e Validações — Locadora DW

## ✅ O que já está coberto

### Testes unitários (`01_test_unit_funcoes.sql`)
Cada função de `00-infra/01_functions.sql` tem caso válido + inválido/limite:
- [x] `fn_normaliza_status_reserva` / `_veiculo` / `_cobranca`
- [x] `fn_normaliza_tipo_cliente` / `_tipo_mecanizacao`
- [x] `fn_normaliza_placa` + `fn_placa_imputada`
- [x] `fn_dias_inclusivo` / `fn_dias_atraso` / `fn_km_rodado` (proteção contra negativo)
- [x] `fn_multa_atraso` (valor de origem, estimativa, e zero)

### Teste de integração (`02_test_integracao.sql`)
- [x] Pipeline extract→transform→load roda fim a fim sobre fixtures G1
- [x] Contagem `conf_* = fato_*`
- [x] Valores esperados (dias, atraso, km, multa, status_cobranca) por locação
- [x] Casos-limite: devolução antecipada (atraso 0), km invertido (0)
- [x] Imputação propaga às dimensões; status desconhecido preservado
- [x] Integridade referencial (sem FK obrigatória nula)
- [x] `dim_tempo` contínua (sem buracos)

### Qualidade de dados (`03_test_qualidade_dados.sql`)
- [x] Nulidade, Unicidade, Domínio, Referencial, Medidas, Volume — como asserções

## ⬜ O que ainda precisa ser testado/validado

- [ ] **Fixtures G2, G3, G4**: hoje a integração cobre só o Grupo 1. Os
      grupos externos exigem fixtures dos schemas `oltp_g2..g4` (cujos
      modelos reais não estão disponíveis). Sem isso, a unificação
      multi-fonte (deduplicação cross-group, colisão de IDs) não é testada.
- [ ] **Teste de idempotência**: rodar o pipeline 2× e asserir que as
      contagens e medidas não mudam (valida o `ON CONFLICT`).
- [ ] **Teste incremental**: validar que a janela baseada em `log_extracao`
      pega novos registros e não reprocessa indevidamente após uma 2ª carga.
- [ ] **Falha de fonte**: simular `oltp_g2` indisponível e asserir que o
      bloco `EXCEPTION` registra `status='ERR'` e não aborta os outros grupos.
- [ ] **Volume com bandas**: trocar o check "vazio" por faixas (ex.: alertar
      se a carga do dia for < 80% da média móvel) — exige histórico.
- [ ] **`fato_veiculo_no_patio`**: asserções de valores (hoje só G1 tem dados).
- [ ] **Views analíticas** (`04_views_analiticas.sql`): asserir que os totais
      das views batem com os fatos (reconciliação view × fato).
- [ ] **dim_funcionario**: inexistente — depende de extrair funcionários.
- [ ] **SCD Tipo 2**: se for decidido versionar `dim_cliente`/`dim_veiculo`,
      criar testes de vigência (`flag_atual`, datas de validade).
- [ ] **Performance**: tempo de carga e plano de consulta das views em volume
      realista (os índices existem, mas não há teste de carga).

## Como rodar
```powershell
# tudo (cria oltp_g1 sintético + reconstrói dw — use banco de teste)
.\04-tests\run_tests.ps1

# só os unitários (não tocam em dados)
.\04-tests\run_tests.ps1 -OnlyUnit
```
