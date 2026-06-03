<!--
=========================================
Grupo:   Tadeu Belfort Neto    - 119034813
         Vicente Alves         - 120044148
         João Pedro de Lacerda - 116076670
=========================================
-->

# Sistema de Locação de Veículos

Projeto desenvolvido para a disciplina **Big Data (MAE016)**.

O projeto tem duas partes: o banco transacional (**OLTP**) que sustenta a
operação da locadora, e o **Data Warehouse (DW)** que consolida os dados de
quatro locadoras em um esquema dimensional para análise.

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
└── Parte 2 - DW/               # Pipeline ETL + Data Warehouse dimensional
    ├── 00-infra/               # Schemas (stg, dw) e funções de transformação
    ├── 01-staging/             # Extração das 4 fontes para a área de staging
    ├── 02-transform/           # Limpeza, normalização e conformação (stg.conf_*)
    ├── 03-dw/                  # Esquema estrela, carga das dimensões/fatos e views
    └── 04-reports/             # Consultas analíticas de negócio
```

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

> **Banco:** PostgreSQL.
