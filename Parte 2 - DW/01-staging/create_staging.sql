-- =====================================================
-- Grupo:
--   Tadeu Belfort Neto              DRE 119034813
--   Vicente Alves                   DRE 1220044148
--   João Pedro de Lacerda           DRE 116076670
-- Arquivo: staging/01_create_staging.sql
-- Descrição: Criação da camada de staging do processo ETL.
--
-- Banco: PostgreSQL
--
-- Observação:
--   Este script cria apenas a estrutura da área de staging.
--   As cargas devem ficar nos scripts de extração:
--
--      02_extract_grupo_tadeu.sql
--      03_extract_grupo_2.sql
--      04_extract_grupo_3.sql
--      05_extract_grupo_4.sql
--
--   Portanto, este arquivo NÃO deve conter:
--      - TRUNCATE
--      - INSERT INTO ... SELECT
--      - SELECT FROM oltp_g1.*
--      - regras de janela incremental
-- =====================================================


-- =====================================================
-- 1. TABELAS DE STAGING
-- =====================================================
-- Uma tabela por entidade consolidada.
--
-- A coluna grupo_fonte identifica a origem:
--   1 = Grupo Tadeu
--   2 = Grupo externo 2
--   3 = Grupo externo 3
--   4 = Grupo externo 4
--
-- As chaves primárias usam grupo_fonte + src_id para evitar
-- conflito entre IDs iguais vindos de bases diferentes.
-- =====================================================


-- -----------------------------------------------------
-- CLIENTE
-- -----------------------------------------------------

CREATE TABLE IF NOT EXISTS stg.cliente (
    src_id          INTEGER      NOT NULL,
    nome            VARCHAR(200),
    tipo            VARCHAR(2),
    cidade          VARCHAR(100),
    uf              CHAR(2),
    email           VARCHAR(150),
    telefone        VARCHAR(20),
    grupo_fonte     SMALLINT     NOT NULL,
    dt_extracao     TIMESTAMP    NOT NULL DEFAULT NOW(),

    CONSTRAINT pk_stg_cliente
        PRIMARY KEY (grupo_fonte, src_id)
);


-- -----------------------------------------------------
-- CONDUTOR
-- -----------------------------------------------------

CREATE TABLE IF NOT EXISTS stg.condutor (
    src_id          INTEGER      NOT NULL,
    src_cliente_id  INTEGER,
    nome            VARCHAR(200),
    cnh             VARCHAR(20),
    validade        DATE,
    categoria       VARCHAR(5),
    telefone        VARCHAR(20),
    grupo_fonte     SMALLINT     NOT NULL,
    dt_extracao     TIMESTAMP    NOT NULL DEFAULT NOW(),

    CONSTRAINT pk_stg_condutor
        PRIMARY KEY (grupo_fonte, src_id)
);


-- -----------------------------------------------------
-- GRUPO DE VEÍCULO
-- -----------------------------------------------------

CREATE TABLE IF NOT EXISTS stg.grupo_veiculo (
    src_id          INTEGER       NOT NULL,
    nome            VARCHAR(100),
    categoria       VARCHAR(500),
    diaria          DECIMAL(10,2),
    grupo_fonte     SMALLINT      NOT NULL,
    dt_extracao     TIMESTAMP     NOT NULL DEFAULT NOW(),

    CONSTRAINT pk_stg_grupo_veiculo
        PRIMARY KEY (grupo_fonte, src_id)
);


-- -----------------------------------------------------
-- VEÍCULO
-- -----------------------------------------------------

CREATE TABLE IF NOT EXISTS stg.veiculo (
    src_id              INTEGER      NOT NULL,
    placa               VARCHAR(10),
    chassi              VARCHAR(50),
    modelo              VARCHAR(60),
    marca               VARCHAR(60),
    cor                 VARCHAR(30),
    tipo_mecanizacao    VARCHAR(20),
    ar_condicionado     BOOLEAN      DEFAULT FALSE,
    adaptado_cadeirante BOOLEAN      DEFAULT FALSE,
    status              VARCHAR(30),
    src_grupo_id        INTEGER,
    src_empresa_id      INTEGER,
    nome_empresa        VARCHAR(150),
    grupo_fonte         SMALLINT     NOT NULL,
    dt_extracao         TIMESTAMP    NOT NULL DEFAULT NOW(),

    CONSTRAINT pk_stg_veiculo
        PRIMARY KEY (grupo_fonte, src_id)
);


-- -----------------------------------------------------
-- PÁTIO
-- -----------------------------------------------------

CREATE TABLE IF NOT EXISTS stg.patio (
    src_id          INTEGER      NOT NULL,
    nome            VARCHAR(150),
    cidade          VARCHAR(100),
    capacidade      INTEGER,
    src_empresa_id  INTEGER,
    nome_empresa    VARCHAR(150),
    grupo_fonte     SMALLINT     NOT NULL,
    dt_extracao     TIMESTAMP    NOT NULL DEFAULT NOW(),

    CONSTRAINT pk_stg_patio
        PRIMARY KEY (grupo_fonte, src_id)
);


-- -----------------------------------------------------
-- VAGA
-- -----------------------------------------------------

CREATE TABLE IF NOT EXISTS stg.vaga (
    codigo          VARCHAR(20)  NOT NULL,
    src_patio_id    INTEGER      NOT NULL,
    status          VARCHAR(20),
    grupo_fonte     SMALLINT     NOT NULL,
    dt_extracao     TIMESTAMP    NOT NULL DEFAULT NOW(),

    CONSTRAINT pk_stg_vaga
        PRIMARY KEY (grupo_fonte, codigo, src_patio_id)
);


-- -----------------------------------------------------
-- RESERVA
-- -----------------------------------------------------

CREATE TABLE IF NOT EXISTS stg.reserva (
    src_id                  INTEGER       NOT NULL,
    src_cliente_id          INTEGER,
    src_grupo_id            INTEGER,
    src_patio_retirada_id   INTEGER,
    src_patio_devolucao_id  INTEGER,
    data_solicitacao        TIMESTAMP,
    data_reserva            TIMESTAMP,
    data_inicio             TIMESTAMP,
    data_fim                TIMESTAMP,
    status                  VARCHAR(30),
    preco_final             DECIMAL(10,2),
    preco_previsto          DECIMAL(10,2),
    grupo_fonte             SMALLINT      NOT NULL,
    dt_extracao             TIMESTAMP     NOT NULL DEFAULT NOW(),

    CONSTRAINT pk_stg_reserva
        PRIMARY KEY (grupo_fonte, src_id)
);


-- -----------------------------------------------------
-- LOCAÇÃO
-- -----------------------------------------------------

CREATE TABLE IF NOT EXISTS stg.locacao (
    src_id                      INTEGER       NOT NULL,
    src_devolucao_id            INTEGER,
    src_reserva_id              INTEGER,
    src_veiculo_id              INTEGER,
    src_condutor_id             INTEGER,
    src_cliente_id              INTEGER,
    src_patio_retirada_id       INTEGER,
    src_patio_devolucao_id      INTEGER,

    data_retirada_prevista      TIMESTAMP,
    data_retirada_realizada     TIMESTAMP,
    data_devolucao_prevista     TIMESTAMP,
    data_devolucao_realizada    TIMESTAMP,

    km_entrega                  INTEGER,
    km_devolucao                INTEGER,

    gasolina_entrega            INTEGER,
    gasolina_devolucao          INTEGER,

    valor_atraso                DECIMAL(10,2),
    valor_reparos               DECIMAL(10,2),
    preco_final                 DECIMAL(10,2),
    valor_total                 DECIMAL(10,2),
    valor_final                 DECIMAL(10,2),

    status                      VARCHAR(30),
    estado_entrega              TEXT,
    estado_devolucao            TEXT,

    created_at                  TIMESTAMP,
    updated_at                  TIMESTAMP,

    grupo_fonte                 SMALLINT      NOT NULL,
    dt_extracao                 TIMESTAMP     NOT NULL DEFAULT NOW(),

    CONSTRAINT pk_stg_locacao
        PRIMARY KEY (grupo_fonte, src_id)
);


-- -----------------------------------------------------
-- COBRANÇA
-- -----------------------------------------------------

CREATE TABLE IF NOT EXISTS stg.cobranca (
    src_id          INTEGER       NOT NULL,
    src_locacao_id  INTEGER,
    valor           DECIMAL(10,2),
    status          VARCHAR(20),
    data_pagamento  DATE,
    grupo_fonte     SMALLINT      NOT NULL,
    dt_extracao     TIMESTAMP     NOT NULL DEFAULT NOW(),

    CONSTRAINT pk_stg_cobranca
        PRIMARY KEY (grupo_fonte, src_id)
);


-- -----------------------------------------------------
-- MOVIMENTAÇÃO ENTRE PÁTIOS
-- -----------------------------------------------------

CREATE TABLE IF NOT EXISTS stg.movimentacao_patio (
    src_id              INTEGER      NOT NULL,
    src_veiculo_id      INTEGER,
    src_origem_id       INTEGER,
    src_destino_id      INTEGER,
    data_movimentacao   TIMESTAMP,
    motivo              VARCHAR(100),
    grupo_fonte         SMALLINT     NOT NULL,
    dt_extracao         TIMESTAMP    NOT NULL DEFAULT NOW(),

    CONSTRAINT pk_stg_movimentacao_patio
        PRIMARY KEY (grupo_fonte, src_id)
);


-- =====================================================
-- 2. TABELA DE LOG DA EXTRAÇÃO
-- =====================================================

CREATE TABLE IF NOT EXISTS stg.log_extracao (
    id_log          SERIAL       PRIMARY KEY,
    grupo_fonte     SMALLINT     NOT NULL,
    tabela_stg      VARCHAR(60)  NOT NULL,
    dt_extracao     TIMESTAMP    NOT NULL DEFAULT NOW(),
    qtd_registros   INTEGER      NOT NULL,
    status          VARCHAR(10)  NOT NULL DEFAULT 'OK',
    observacao      VARCHAR(200)
);


-- =====================================================
-- 3. ÍNDICES AUXILIARES
-- =====================================================
-- Índices pensados para joins dos transforms e cargas no DW.
-- =====================================================


-- -----------------------------------------------------
-- CLIENTE / CONDUTOR
-- -----------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_stg_condutor_cliente
    ON stg.condutor (grupo_fonte, src_cliente_id);


-- -----------------------------------------------------
-- VEÍCULO / GRUPO / EMPRESA
-- -----------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_stg_veiculo_grupo
    ON stg.veiculo (grupo_fonte, src_grupo_id);

CREATE INDEX IF NOT EXISTS idx_stg_veiculo_empresa
    ON stg.veiculo (grupo_fonte, src_empresa_id);

CREATE INDEX IF NOT EXISTS idx_stg_veiculo_placa
    ON stg.veiculo (placa);


-- -----------------------------------------------------
-- PÁTIO / VAGA
-- -----------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_stg_vaga_patio
    ON stg.vaga (grupo_fonte, src_patio_id);


-- -----------------------------------------------------
-- RESERVA
-- -----------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_stg_reserva_cliente
    ON stg.reserva (grupo_fonte, src_cliente_id);

CREATE INDEX IF NOT EXISTS idx_stg_reserva_grupo
    ON stg.reserva (grupo_fonte, src_grupo_id);

CREATE INDEX IF NOT EXISTS idx_stg_reserva_patio_retirada
    ON stg.reserva (grupo_fonte, src_patio_retirada_id);

CREATE INDEX IF NOT EXISTS idx_stg_reserva_patio_devolucao
    ON stg.reserva (grupo_fonte, src_patio_devolucao_id);

CREATE INDEX IF NOT EXISTS idx_stg_reserva_periodo
    ON stg.reserva (data_inicio, data_fim);

CREATE INDEX IF NOT EXISTS idx_stg_reserva_status
    ON stg.reserva (status);


-- -----------------------------------------------------
-- LOCAÇÃO
-- -----------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_stg_locacao_reserva
    ON stg.locacao (grupo_fonte, src_reserva_id);

CREATE INDEX IF NOT EXISTS idx_stg_locacao_veiculo
    ON stg.locacao (grupo_fonte, src_veiculo_id);

CREATE INDEX IF NOT EXISTS idx_stg_locacao_condutor
    ON stg.locacao (grupo_fonte, src_condutor_id);

CREATE INDEX IF NOT EXISTS idx_stg_locacao_cliente
    ON stg.locacao (grupo_fonte, src_cliente_id);

CREATE INDEX IF NOT EXISTS idx_stg_locacao_patio_retirada
    ON stg.locacao (grupo_fonte, src_patio_retirada_id);

CREATE INDEX IF NOT EXISTS idx_stg_locacao_patio_devolucao
    ON stg.locacao (grupo_fonte, src_patio_devolucao_id);

CREATE INDEX IF NOT EXISTS idx_stg_locacao_retirada_realizada
    ON stg.locacao (data_retirada_realizada);

CREATE INDEX IF NOT EXISTS idx_stg_locacao_devolucao_realizada
    ON stg.locacao (data_devolucao_realizada);

CREATE INDEX IF NOT EXISTS idx_stg_locacao_status
    ON stg.locacao (status);


-- -----------------------------------------------------
-- COBRANÇA
-- -----------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_stg_cobranca_locacao
    ON stg.cobranca (grupo_fonte, src_locacao_id);

CREATE INDEX IF NOT EXISTS idx_stg_cobranca_status
    ON stg.cobranca (status);


-- -----------------------------------------------------
-- MOVIMENTAÇÃO ENTRE PÁTIOS
-- -----------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_stg_movimentacao_veiculo
    ON stg.movimentacao_patio (grupo_fonte, src_veiculo_id);

CREATE INDEX IF NOT EXISTS idx_stg_movimentacao_origem
    ON stg.movimentacao_patio (grupo_fonte, src_origem_id);

CREATE INDEX IF NOT EXISTS idx_stg_movimentacao_destino
    ON stg.movimentacao_patio (grupo_fonte, src_destino_id);

CREATE INDEX IF NOT EXISTS idx_stg_movimentacao_data
    ON stg.movimentacao_patio (data_movimentacao);


-- -----------------------------------------------------
-- LOG
-- -----------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_stg_log_extracao_grupo_tabela
    ON stg.log_extracao (grupo_fonte, tabela_stg);

CREATE INDEX IF NOT EXISTS idx_stg_log_extracao_data
    ON stg.log_extracao (dt_extracao);


-- =====================================================
-- 4. COMENTÁRIOS DE DOCUMENTAÇÃO
-- =====================================================

COMMENT ON SCHEMA stg IS
'Schema de staging do processo ETL do Data Warehouse da locadora de veículos.';

COMMENT ON TABLE stg.cliente IS
'Tabela de staging consolidada para clientes extraídos das fontes OLTP.';

COMMENT ON TABLE stg.condutor IS
'Tabela de staging consolidada para condutores extraídos das fontes OLTP.';

COMMENT ON TABLE stg.grupo_veiculo IS
'Tabela de staging consolidada para grupos de veículos.';

COMMENT ON TABLE stg.veiculo IS
'Tabela de staging consolidada para veículos.';

COMMENT ON TABLE stg.patio IS
'Tabela de staging consolidada para pátios.';

COMMENT ON TABLE stg.vaga IS
'Tabela de staging consolidada para vagas dos pátios.';

COMMENT ON TABLE stg.reserva IS
'Tabela de staging consolidada para reservas.';

COMMENT ON TABLE stg.locacao IS
'Tabela de staging consolidada para locações.';

COMMENT ON TABLE stg.cobranca IS
'Tabela de staging consolidada para cobranças associadas às locações.';

COMMENT ON TABLE stg.movimentacao_patio IS
'Tabela de staging consolidada para movimentações de veículos entre pátios.';

COMMENT ON TABLE stg.log_extracao IS
'Tabela de controle das execuções dos scripts de extração para staging.';