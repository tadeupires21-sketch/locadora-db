-- =====================================================
-- Nome: Tadeu Belfort Neto
-- DRE: 119034813
-- Arquivo: etl_01_extracao_grupo_tadeu.sql
-- Descrição: Extração ETL — Grupo Tadeu (fonte 1/4)
--            Lê do OLTP transacional e carrega na
--            área de staging do DWH.
--
-- Banco: PostgreSQL
-- Agendamento sugerido: diário, às 02:00h
--   (via pg_cron, cron do SO + psql, ou Airflow)
--
-- NOTA: substituir as referências oltp_g1.* pelo schema
--   ou conexão real do OLTP do grupo. No PostgreSQL,
--   acesso a outro banco se faz via postgres_fdw
--   (foreign data wrapper) ou dblink. Aqui assume-se
--   que as tabelas fonte estão acessíveis no schema oltp_g1.
-- =====================================================

-- =====================================================
-- PASSO 0 — Criar schema de staging
-- =====================================================
CREATE SCHEMA IF NOT EXISTS stg;



-- =====================================================
-- PASSO 1 — Criar tabelas únicas de staging
-- Uma tabela por entidade, com grupo_fonte preservando
-- a origem: 1 = Grupo Tadeu, 2/3/4 = grupos externos.
-- =====================================================

DROP TABLE IF EXISTS stg.cliente CASCADE;
CREATE TABLE stg.cliente (
    src_id          INTEGER         NOT NULL,
    nome            VARCHAR(200),
    tipo            VARCHAR(2),
    cidade          VARCHAR(100),
    uf              CHAR(2),
    email           VARCHAR(150),
    telefone        VARCHAR(20),
    grupo_fonte     SMALLINT        NOT NULL,
    dt_extracao     TIMESTAMP       NOT NULL DEFAULT NOW(),
    PRIMARY KEY (grupo_fonte, src_id)
);

DROP TABLE IF EXISTS stg.condutor CASCADE;
CREATE TABLE stg.condutor (
    src_id          INTEGER         NOT NULL,
    src_cliente_id  INTEGER         NOT NULL,
    nome            VARCHAR(200),
    cnh             VARCHAR(20),
    validade        DATE,
    categoria       VARCHAR(5),
    grupo_fonte     SMALLINT        NOT NULL,
    dt_extracao     TIMESTAMP       NOT NULL DEFAULT NOW(),
    PRIMARY KEY (grupo_fonte, src_id)
);

DROP TABLE IF EXISTS stg.grupo_veiculo CASCADE;
CREATE TABLE stg.grupo_veiculo (
    src_id          INTEGER         NOT NULL,
    nome            VARCHAR(100),
    categoria       VARCHAR(500),
    diaria          DECIMAL(10,2),
    grupo_fonte     SMALLINT        NOT NULL,
    dt_extracao     TIMESTAMP       NOT NULL DEFAULT NOW(),
    PRIMARY KEY (grupo_fonte, src_id)
);

DROP TABLE IF EXISTS stg.veiculo CASCADE;
CREATE TABLE stg.veiculo (
    src_id              INTEGER         NOT NULL,
    placa               VARCHAR(10),
    chassi              VARCHAR(50),
    modelo              VARCHAR(60),
    marca               VARCHAR(60),
    cor                 VARCHAR(30),
    tipo_mecanizacao    VARCHAR(20),
    ar_condicionado     BOOLEAN         DEFAULT FALSE,
    adaptado_cadeirante BOOLEAN         DEFAULT FALSE,
    status              VARCHAR(30),
    src_grupo_id        INTEGER,
    src_empresa_id      INTEGER,
    nome_empresa        VARCHAR(150),
    grupo_fonte         SMALLINT        NOT NULL,
    dt_extracao         TIMESTAMP       NOT NULL DEFAULT NOW(),
    PRIMARY KEY (grupo_fonte, src_id)
);

DROP TABLE IF EXISTS stg.patio CASCADE;
CREATE TABLE stg.patio (
    src_id          INTEGER         NOT NULL,
    nome            VARCHAR(150),
    cidade          VARCHAR(100),
    capacidade      INTEGER,
    src_empresa_id  INTEGER,
    nome_empresa    VARCHAR(150),
    grupo_fonte     SMALLINT        NOT NULL,
    dt_extracao     TIMESTAMP       NOT NULL DEFAULT NOW(),
    PRIMARY KEY (grupo_fonte, src_id)
);

DROP TABLE IF EXISTS stg.vaga CASCADE;
CREATE TABLE stg.vaga (
    codigo          VARCHAR(20)     NOT NULL,
    src_patio_id    INTEGER         NOT NULL,
    status          VARCHAR(20),
    grupo_fonte     SMALLINT        NOT NULL,
    dt_extracao     TIMESTAMP       NOT NULL DEFAULT NOW(),
    PRIMARY KEY (grupo_fonte, codigo, src_patio_id)
);

DROP TABLE IF EXISTS stg.reserva CASCADE;
CREATE TABLE stg.reserva (
    src_id                  INTEGER         NOT NULL,
    src_cliente_id          INTEGER         NOT NULL,
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
    grupo_fonte             SMALLINT        NOT NULL,
    dt_extracao             TIMESTAMP       NOT NULL DEFAULT NOW(),
    PRIMARY KEY (grupo_fonte, src_id)
);

DROP TABLE IF EXISTS stg.locacao CASCADE;
CREATE TABLE stg.locacao (
    src_id                      INTEGER         NOT NULL,
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
    grupo_fonte                 SMALLINT        NOT NULL,
    dt_extracao                 TIMESTAMP       NOT NULL DEFAULT NOW(),
    PRIMARY KEY (grupo_fonte, src_id)
);

DROP TABLE IF EXISTS stg.cobranca CASCADE;
CREATE TABLE stg.cobranca (
    src_id          INTEGER         NOT NULL,
    src_locacao_id  INTEGER,
    valor           DECIMAL(10,2),
    status          VARCHAR(20),
    data_pagamento  DATE,
    grupo_fonte     SMALLINT        NOT NULL,
    dt_extracao     TIMESTAMP       NOT NULL DEFAULT NOW(),
    PRIMARY KEY (grupo_fonte, src_id)
);

DROP TABLE IF EXISTS stg.movimentacao_patio CASCADE;
CREATE TABLE stg.movimentacao_patio (
    src_id              INTEGER         NOT NULL,
    src_veiculo_id      INTEGER,
    src_origem_id       INTEGER,
    src_destino_id      INTEGER,
    data_movimentacao   TIMESTAMP,
    motivo              VARCHAR(100),
    grupo_fonte         SMALLINT        NOT NULL,
    dt_extracao         TIMESTAMP       NOT NULL DEFAULT NOW(),
    PRIMARY KEY (grupo_fonte, src_id)
);

-- =====================================================
-- PASSO 2 — Carga incremental para staging
--
-- Estratégia de janela temporal:
--   1ª execução (log vazio)  → fallback de 7 dias para não perder dados
--   Execuções seguintes      → usa o timestamp da última extração bem-sucedida
--
-- Isso elimina o risco de gap: se o job falhar e só reexecutar após
-- 26+ horas, os registros NÃO são perdidos (a janela de 25h fixada antes
-- causaria esse problema).
-- =====================================================

-- Clientes (carga full — tabela pequena, sem campo de alteração)
TRUNCATE TABLE stg.cliente;
INSERT INTO stg.cliente
    (src_id, nome, tipo, cidade, grupo_fonte)
SELECT q.*, 1::SMALLINT AS grupo_fonte
FROM (
SELECT id, nome, tipo, cidade
FROM oltp_g1.cliente
) q;

-- Condutores (carga full)
TRUNCATE TABLE stg.condutor;
INSERT INTO stg.condutor
    (src_id, src_cliente_id, nome, cnh, validade, categoria, grupo_fonte)
SELECT q.*, 1::SMALLINT AS grupo_fonte
FROM (
SELECT id, cliente_id, nome, cnh, validade, categoria
FROM oltp_g1.condutor
) q;

-- Grupos de veículo (carga full — tabela de referência)
TRUNCATE TABLE stg.grupo_veiculo;
INSERT INTO stg.grupo_veiculo
    (src_id, nome, categoria, grupo_fonte)
SELECT q.*, 1::SMALLINT AS grupo_fonte
FROM (
SELECT id, nome, categoria
FROM oltp_g1.grupo_veiculo
) q;

-- Veículos (carga full — detecta mudança de status)
TRUNCATE TABLE stg.veiculo;
INSERT INTO stg.veiculo
    (src_id, placa, chassi, modelo, marca, cor,
     tipo_mecanizacao, ar_condicionado, adaptado_cadeirante,
     status, src_grupo_id, src_empresa_id, nome_empresa, grupo_fonte)
SELECT q.*, 1::SMALLINT AS grupo_fonte
FROM (
SELECT v.id, v.placa, v.chassi, v.modelo, v.marca, v.cor,
    v.tipo_mecanizacao, v.ar_condicionado, v.adaptado_cadeirante,
    v.status, v.grupo_id, v.empresa_id, e.nome
FROM oltp_g1.veiculo v
JOIN oltp_g1.empresa_locadora e ON e.id = v.empresa_id
) q;

-- Pátios + vagas (capacidade calculada na transformação)
TRUNCATE TABLE stg.patio;
INSERT INTO stg.patio
    (src_id, nome, cidade, grupo_fonte)
SELECT q.*, 1::SMALLINT AS grupo_fonte
FROM (
SELECT id, nome, cidade
FROM oltp_g1.patio
) q;

TRUNCATE TABLE stg.vaga;
INSERT INTO stg.vaga
    (codigo, src_patio_id, status, grupo_fonte)
SELECT q.*, 1::SMALLINT AS grupo_fonte
FROM (
SELECT codigo, patio_id, status
FROM oltp_g1.vaga
) q;

-- Reservas — incremental por data_inicio + mudanças de status
-- A janela usa o último run bem-sucedido registrado no log, com fallback
-- de 7 dias para evitar gap em caso de falha prolongada do job.
TRUNCATE TABLE stg.reserva;
INSERT INTO stg.reserva
    (src_id, src_cliente_id, src_grupo_id,
     src_patio_retirada_id, src_patio_devolucao_id,
     data_inicio, data_fim, status, grupo_fonte)
SELECT q.*, 1::SMALLINT AS grupo_fonte
FROM (
SELECT id, cliente_id, grupo_id,
    patio_retirada_id, patio_devolucao_id,
    data_inicio, data_fim, status
FROM oltp_g1.reserva
WHERE data_inicio >= (
        -- Baseline: última extração bem-sucedida ou 7 dias atrás como fallback
        SELECT COALESCE(
            MAX(dt_extracao) - INTERVAL '1 hour',  -- sobreposição de 1h para cobrir race conditions
            NOW() - INTERVAL '7 days'
        )
        FROM stg.log_extracao
        WHERE grupo_fonte = 1
          AND tabela_stg = 'reserva'
          AND status = 'OK'
    )::DATE
   OR status IN ('cancelada', 'espera')
) q;

-- Locações — incremental por l.created_at + abertas (sem devolução)
-- Sempre traz locações abertas (sem data_devolucao_realizada) independente
-- do período, garantindo que nenhuma locação em andamento seja perdida.
TRUNCATE TABLE stg.locacao;
INSERT INTO stg.locacao
    (src_id, src_reserva_id, src_veiculo_id, src_condutor_id, src_cliente_id,
     src_patio_retirada_id, src_patio_devolucao_id,
     data_retirada_prevista, data_retirada_realizada,
     data_devolucao_prevista, data_devolucao_realizada,
     km_entrega, km_devolucao,
     estado_entrega, estado_devolucao, created_at, grupo_fonte)
SELECT q.*, 1::SMALLINT AS grupo_fonte
FROM (
SELECT l.id, l.reserva_id, l.veiculo_id, l.condutor_id, c.cliente_id,
    l.patio_retirada_id, patio_devolucao_id,
    l.data_retirada_prevista, l.data_retirada_realizada,
    l.data_devolucao_prevista, l.data_devolucao_realizada,
    l.km_entrega, l.km_devolucao,
    l.estado_entrega, l.estado_devolucao, l.created_at
FROM oltp_g1.locacao l
JOIN oltp_g1.condutor c ON c.id = l.condutor_id
WHERE l.created_at >= (
        -- Baseline: última extração bem-sucedida ou 7 dias atrás como fallback
        SELECT COALESCE(
            MAX(dt_extracao) - INTERVAL '1 hour',
            NOW() - INTERVAL '7 days'
        )
        FROM stg.log_extracao
        WHERE grupo_fonte = 1
          AND tabela_stg = 'locacao'
          AND status = 'OK'
    )
   OR (l.data_devolucao_realizada IS NULL
       AND l.data_retirada_realizada IS NOT NULL)
) q;

-- Cobranças — pendentes + pagas desde a última extração
TRUNCATE TABLE stg.cobranca;
INSERT INTO stg.cobranca
    (src_id, src_locacao_id, valor, status, data_pagamento, grupo_fonte)
SELECT q.*, 1::SMALLINT AS grupo_fonte
FROM (
SELECT id, locacao_id, valor, status, data_pagamento
FROM oltp_g1.cobranca
WHERE status = 'pendente'
   OR data_pagamento >= (
        -- Baseline: última extração bem-sucedida ou 7 dias atrás como fallback
        SELECT COALESCE(
            MAX(dt_extracao) - INTERVAL '1 hour',
            NOW() - INTERVAL '7 days'
        )
        FROM stg.log_extracao
        WHERE grupo_fonte = 1
          AND tabela_stg = 'cobranca'
          AND status = 'OK'
    )::DATE
) q;

-- Movimentações entre pátios — incremental por data_movimentacao
TRUNCATE TABLE stg.movimentacao_patio;
INSERT INTO stg.movimentacao_patio
    (src_id, src_veiculo_id, src_origem_id,
     src_destino_id, data_movimentacao, motivo, grupo_fonte)
SELECT q.*, 1::SMALLINT AS grupo_fonte
FROM (
SELECT id, veiculo_id, origem_patio_id,
    destino_patio_id, data_movimentacao, motivo
FROM oltp_g1.movimentacao_patio
WHERE data_movimentacao >= (
        -- Baseline: última extração bem-sucedida ou 7 dias atrás como fallback
        SELECT COALESCE(
            MAX(dt_extracao) - INTERVAL '1 hour',
            NOW() - INTERVAL '7 days'
        )
        FROM stg.log_extracao
        WHERE grupo_fonte = 1
          AND tabela_stg = 'movimentacao_patio'
          AND status = 'OK'
    )
) q;


-- =====================================================
-- PASSO 3 — Log de controle de extração
--
-- A tabela log_extracao cumpre dois papéis:
--   1. Auditoria: registra contagem de linhas por tabela/grupo/run.
--   2. Baseline incremental: o status 'OK' é usado nos WHERE das
--      extrações seguintes para calcular a janela temporal.
--
-- IMPORTANTE: a tabela é criada aqui com IF NOT EXISTS para que
-- exista na primeira execução. Em banco limpo, o script
-- 00-infra/00_create_schemas.sql deve ser rodado antes deste.
-- =====================================================
CREATE TABLE IF NOT EXISTS stg.log_extracao (
    id_log          SERIAL          PRIMARY KEY,
    grupo_fonte     SMALLINT        NOT NULL,
    tabela_stg      VARCHAR(60)     NOT NULL,
    dt_extracao     TIMESTAMP       NOT NULL DEFAULT NOW(),
    qtd_registros   INTEGER         NOT NULL,
    -- 'OK' = extração concluída com sucesso (usado como baseline incremental)
    -- 'ERR' = extração falhou (não deve ser usado como baseline)
    status          VARCHAR(10)     NOT NULL DEFAULT 'OK',
    observacao      VARCHAR(200)
);

-- Registra o resultado desta execução com status OK
INSERT INTO stg.log_extracao (grupo_fonte, tabela_stg, qtd_registros, status)
VALUES
    (1, 'cliente',           (SELECT COUNT(*) FROM stg.cliente),            'OK'),
    (1, 'condutor',          (SELECT COUNT(*) FROM stg.condutor),           'OK'),
    (1, 'grupo_veiculo',     (SELECT COUNT(*) FROM stg.grupo_veiculo),      'OK'),
    (1, 'veiculo',           (SELECT COUNT(*) FROM stg.veiculo),            'OK'),
    (1, 'patio',             (SELECT COUNT(*) FROM stg.patio),              'OK'),
    (1, 'reserva',           (SELECT COUNT(*) FROM stg.reserva),            'OK'),
    (1, 'locacao',           (SELECT COUNT(*) FROM stg.locacao),            'OK'),
    (1, 'cobranca',          (SELECT COUNT(*) FROM stg.cobranca),           'OK'),
    (1, 'movimentacao_patio',(SELECT COUNT(*) FROM stg.movimentacao_patio), 'OK');

-- =====================================================
-- AGENDAMENTO SUGERIDO
-- =====================================================
-- Via pg_cron (extensão):
--   SELECT cron.schedule('etl_extracao_g1', '0 2 * * *',
--          'psql -f etl_01_extracao_grupo_tadeu.sql');
--
-- Escalonar os grupos para evitar concorrência de I/O:
--   G1 → 02:00h | G2 → 02:30h | G3 → 03:00h | G4 → 03:30h
-- =====================================================
