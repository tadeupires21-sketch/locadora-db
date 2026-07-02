# Sistema de Locação de Veículos — OLTP · DW · Big Data

Projeto desenvolvido para a disciplina **Big Data (MAE016)** — UFRJ · Instituto de Computação.

## Grupo

| Integrante | DRE |
|------------|-----|
| Tadeu Belfort Neto | 119034813 |
| Vicente Alves | 120044148 |
| João Pedro de Lacerda | 116076670 |

O projeto foi desenvolvido em três partes: o banco transacional (**OLTP**) que
sustenta a operação da locadora; o **Data Warehouse (DW)** que consolida os
dados de quatro locadoras em um esquema dimensional para análise; e a
**Proposta Executiva de Big Data**, que estende a solução para uma frota
conectada com telemetria em tempo real.

## Estrutura

```
.
├── Parte 1 - OLTP/              # Banco transacional da locadora
│   ├── schema.sql              # Definição das tabelas do OLTP
│   ├── seed.sql                # Dados de exemplo
│   ├── seed_test.sql           # Dados para testes
│   ├── docs/                   # Documentação (dicionário de dados, modelo lógico)
│   └── diagrams/               # MER (modelo entidade-relacionamento)
│
├── Parte 2 - DW/                # Pipeline ETL + Data Warehouse dimensional
│   ├── 00-infra/               # Schemas (stg, dw) e funções de transformação
│   ├── 01-staging/             # Extração das 4 fontes para a área de staging
│   ├── 02-transform/           # Limpeza, normalização e conformação (stg.conf_*)
│   ├── 03-dw/                  # Esquema estrela, carga das dimensões/fatos e views
│   ├── 04-reports/             # Consultas analíticas de negócio
│   ├── 04-tests/               # Testes automatizados (unidade, integração, qualidade)
│   └── docs/                   # Relatórios (ETL, modelo dimensional) e apresentação da Parte 2
│
├── Parte 3 - DW+BigData/        # Proposta Executiva de Big Data (frota conectada)
│   ├── proposta_executiva.pdf              # Documento 1 — Proposta Executiva (entregável)
│   ├── Apresentacao Completa DW - Big Data.pdf  # Slides da defesa (Parte 2 + Parte 3)
│   ├── apresentacao.pdf / .html            # Slides da Parte 3
│   ├── arquitetura_referencia.pdf / .html  # Diagrama da arquitetura de referência
│   ├── decisoes_do_grupo.pdf / .html       # Registro das decisões de tecnologia
│   └── briefing_estimativa_custos.pdf / .html  # Briefing de custos de nuvem
│
├── schema.sql / seed.sql        # Versões consolidadas usadas pelo pipeline da Parte 2
└── run_tests.sh                 # Roda o pipeline + testes da Parte 2 (psql)
```

Os arquivos `.html` da Parte 3 são a fonte dos PDFs correspondentes
(gerados via Chrome headless).

### Parte 1 — OLTP
Modelo relacional normalizado da operação: clientes, condutores, veículos,
grupos, pátios, vagas, reservas, locações, cobranças e movimentações.

### Parte 2 — DW (pipeline ETL)
Fluxo em camadas, executadas na ordem das pastas:

| Pasta | Papel |
|-------|-------|
| `00-infra` | Cria os schemas `stg`/`dw` e as funções de regra de negócio |
| `01-staging` | Extrai os dados das 4 fontes para tabelas `stg.*` |
| `02-transform` | Normaliza e conforma os dados em `stg.conf_*` |
| `03-dw` | Cria e carrega o esquema estrela (`dim_*` e `fato_*`) e as views |
| `04-reports` | Consultas de negócio sobre o DW |
| `04-tests` | Testes de unidade, integração e qualidade de dados |

### Parte 3 — DW + Big Data (Proposta Executiva)
Proposta de arquitetura, no papel de consultoria, para operar uma frota
conectada em escala de cidade: computação de borda nos veículos, ingestão por
**Apache Kafka**, **lakehouse** unificado (Databricks + Spark + Delta Lake,
arquitetura Kappa/medalhão), armazenamento poliglota (Redis · MongoDB ·
Delta · PostgreSQL/DW da Parte 2) e consumo via Grafana, BI e ML — com
redução de custo como critério explícito de projeto. Inclui, como extra, a
especificação funcional de um concierge de viagem por voz (LLM + RAG).

## Como executar

### Parte 1 — OLTP
1. Criar o banco
2. Rodar `Parte 1 - OLTP/schema.sql`
3. Rodar `Parte 1 - OLTP/seed.sql`

### Parte 2 — DW (na ordem das pastas)
1. `Parte 2 - DW/00-infra/00_create_schemas.sql`
2. `Parte 2 - DW/00-infra/01_functions.sql`
3. `Parte 2 - DW/01-staging/` — `create_staging.sql` e depois os `etl_*`
4. `Parte 2 - DW/02-transform/` — `01_transform_dimensoes.sql`, `02_transform_fatos.sql`
5. `Parte 2 - DW/03-dw/` — `01_create_dw.sql`, `02_load_dimensoes.sql`, `03_load_fatos.sql`, `04_views_analiticas.sql`
6. `Parte 2 - DW/04-reports/queries_negocio.sql` — consultas analíticas

Ou, de uma vez (pipeline + testes): `./run_tests.sh`

> **Banco:** PostgreSQL.

### Parte 3 — DW + Big Data
Não há código a executar: os entregáveis são os documentos em
`Parte 3 - DW+BigData/` (proposta executiva e slides da defesa).
