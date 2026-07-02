# Data Warehouse — Locadora de Veículos

**Autor:** Tadeu Belfort Neto · DRE 119034813  
**Banco:** PostgreSQL  
**Modelo:** Esquema estrela (com ramo snowflake em `dim_veiculo`)

---

## Visão geral

Pipeline ETL que consolida dados de **4 locadoras (grupos)** em um Data Warehouse dimensional único. Os dados brutos vêm dos schemas OLTP (`oltp_g1` a `oltp_g4`) e chegam ao DW após três camadas: staging → conformance → estrela.

```
oltp_g1                ┐
oltp_g2  ──► stg.*  ──► stg.conf_*  ──► dw.dim_* / dw.fato_*
oltp_g3                │   (staging)      (conformance)    (DW estrela)
oltp_g4                ┘
```

---

## Estrutura de pastas

```
Parte 2 - DW/
├── 00-infra/                  # Pré-requisitos — rodar PRIMEIRO
│   ├── 00_create_schemas.sql  # Cria schemas stg e dw
│   └── 01_functions.sql       # Funções de normalização (reutilizadas no transform)
│
├── 01-staging/                # Extração e área de staging
│   ├── create_staging.sql                        # DDL das tabelas stg.*
│   ├── etl_01_extracao_grupo_tadeu_unificado.sql # Extração Grupo 1 (Tadeu)
│   └── etl_02_extracao_grupos_externos_unificado.sql # Extração Grupos 2, 3 e 4
│
├── 02-transform/              # Conformance (stg.conf_*)
│   ├── 00_validacao_staging.sql   # Checagens antes de transformar
│   ├── 01_transform_dimensoes.sql # Gera conf_cliente, conf_veiculo, etc.
│   ├── 02_transform_fatos.sql     # Gera conf_locacao, conf_reserva, etc.
│   └── 03_validacao_transform.sql # Checagens após transformar
│
├── 03-dw/                     # Camada dimensional final
│   ├── 01_create_dw.sql       # Recria schema dw (DROP CASCADE + CREATE)
│   ├── 02_load_dimensoes.sql  # Carga das dimensões (SCD Tipo 1)
│   ├── 03_load_fatos.sql      # Carga das tabelas fato
│   └── 04_views_analiticas.sql # Views prontas para consumo
│
├── 04-tests/                  # Suite de testes
│   ├── 00_fixtures_oltp_g1.sql     # Dados sintéticos do Grupo 1
│   ├── 01_test_unit_funcoes.sql    # Testes unitários das funções
│   ├── 02_test_integracao.sql      # Teste fim a fim (extract→load)
│   ├── 03_test_qualidade_dados.sql # Asserções de qualidade no DW
│   ├── 04_test_oltp_carga_minima.sql
│   ├── 05_test_oltp_constraints.sql
│   ├── 06_test_oltp_on_delete.sql
│   ├── 07_test_oltp_consultas.sql
│   ├── run_tests.ps1          # Orquestrador dos testes
│   ├── run_oltp_tests.ps1     # Testes OLTP isolados
│   └── CHECKLIST.md           # O que está coberto e o que falta
│
├── 04-reports/
│   └── queries_negocio.sql    # Consultas analíticas prontas para relatórios
│
├── docs/
│   └── testes.md
│
└── run_pipeline.ps1           # Orquestrador principal do pipeline ETL
```

---

## Como executar

### Pré-requisitos

- PostgreSQL client (`psql`) no PATH
- Variáveis de ambiente configuradas:

```powershell
$env:PGHOST     = "localhost"
$env:PGPORT     = "5432"
$env:PGDATABASE = "nome_do_banco"
$env:PGUSER     = "usuario"
$env:PGPASSWORD = "senha"   # ou usar .pgpass
```

### Pipeline completo

```powershell
.\run_pipeline.ps1
```

O orquestrador executa as etapas nesta ordem e para em caso de erro:

| Etapa | Scripts executados |
|---|---|
| 0 — Infraestrutura | `00-infra/00_create_schemas.sql`, `00-infra/01_functions.sql` |
| 1 — Staging (DDL) | `01-staging/create_staging.sql` |
| 2 — Extração | `etl_01_*`, `etl_02_*` |
| 3 — Validação staging | `02-transform/00_validacao_staging.sql` (pausa para confirmação) |
| 4 — Transform | `02-transform/01_transform_dimensoes.sql`, `02_transform_fatos.sql` |
| 5 — Validação transform | `02-transform/03_validacao_transform.sql` |
| 6 — DW | `03-dw/01_create_dw.sql`, `02_load_dimensoes.sql`, `03_load_fatos.sql`, `04_views_analiticas.sql` |

### Flags opcionais

```powershell
.\run_pipeline.ps1 -SkipExtract    # pula extração (usa staging já populada)
.\run_pipeline.ps1 -SkipValidacao  # pula pausas de validação
```

### Só testes

```powershell
.\04-tests\run_tests.ps1           # cria fixtures G1 + reconstrói DW + roda todos os testes
.\04-tests\run_tests.ps1 -OnlyUnit # apenas testes unitários das funções
.\04-tests\run_oltp_tests.ps1      # testes OLTP isolados
```

---

## Schemas

| Schema | Finalidade |
|---|---|
| `stg` | Staging e conformance. Nunca expor a usuários de negócio. |
| `dw` | Esquema estrela final — fonte oficial para relatórios e dashboards. |

---

## Modelo dimensional

### Dimensões (`dw.dim_*`)

| Tabela | Grão | SCD |
|---|---|---|
| `dim_tempo` | Um dia | — (gerada por série de datas) |
| `dim_cliente` | Um cliente por grupo-fonte | Tipo 1 |
| `dim_condutor` | Um condutor por grupo-fonte | Tipo 1 |
| `dim_veiculo` | Um veículo por placa | Tipo 1 |
| `dim_grupo_veiculo` | Um grupo/categoria de veículo | Tipo 1 |
| `dim_empresa` | Uma locadora/empresa | Tipo 1 |
| `dim_patio` | Um pátio | Tipo 1 |

`dim_veiculo` referencia `dim_grupo_veiculo` e `dim_empresa` (ramo snowflake).

### Fatos (`dw.fato_*`)

| Tabela | Grão | Principais medidas |
|---|---|---|
| `fato_locacao` | Uma locação | `valor_total`, `dias_locacao`, `km_rodado`, `valor_atraso` |
| `fato_reserva` | Uma reserva | `preco_previsto`, `preco_final`, `dias_reserva` |
| `fato_cobranca` | Uma cobrança | `valor`, `status_cobranca` |
| `fato_veiculo_no_patio` | Presença de veículo em pátio | `dias_permanencia` |
| `fato_movimentacao_patio` | Uma movimentação entre pátios | — |

### Views analíticas (`dw.vw_*`)

| View | Responde |
|---|---|
| `vw_locacoes_por_mes` | Receita e volume mês a mês |
| `vw_clientes_mais_frequentes` | Clientes mais valiosos por receita |
| `vw_atrasos_devolucao` | Padrão de atrasos por grupo de veículo |
| `vw_ocupacao_por_grupo_veiculo` | Ocupação da frota por categoria |
| `vw_reservas_por_status` | Distribuição de reservas por status |
| `vw_movimentacao_entre_patios` | Fluxo de veículos entre pátios |
| `vw_matriz_transicao_patios` | Matriz origem × destino das movimentações |

---

## Decisões de design

- **`grupo_fonte` como parte da chave natural** — o mesmo `src_id` pode existir em dois grupos distintos; `(grupo_fonte, src_id)` garante unicidade na staging sem precisar reescrever IDs.
- **SCD Tipo 1** — o DW reflete o estado atual de cada dimensão. Não há versionamento histórico.
- **`01_create_dw.sql` é destrutivo** — executa `DROP SCHEMA dw CASCADE` seguido de `CREATE SCHEMA dw`. Surrogate keys são regenerados a cada rebuild total. Não executar em produção sem intenção explícita.
- **Funções IMMUTABLE em `01_functions.sql`** — centralizadas para eliminar duplicação entre transform e validação, e para permitir testes unitários determinísticos.
- **Conformance recria `conf_*` a cada execução** — `DROP TABLE IF EXISTS ... CASCADE` antes de cada `CREATE TABLE AS SELECT`, tornando o transform idempotente.
