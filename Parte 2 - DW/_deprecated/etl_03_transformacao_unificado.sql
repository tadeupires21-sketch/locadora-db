-- =====================================================
-- Nome: Tadeu Belfort Neto
-- DRE: 119034813
-- Arquivo: etl_03_transformacao.sql
-- Descrição: Transformação ETL — consolida e conforma
--            os dados dos 4 grupos na área de staging,
--            produzindo tabelas stg.conf_* prontas para
--            carga no DW.
--
-- Banco: PostgreSQL
--
-- Principais tratamentos:
--   1. Geração de surrogate keys globais (SERIAL)
--   2. Conformação de nomes de colunas divergentes
--   3. Normalização de valores categóricos
--      (status, tipo_mecanizacao, tipo_cliente)
--   4. Resolução de duplicatas por CNH
--   5. Cálculo de capacidade de pátio para G1/G2
-- =====================================================

-- =====================================================================
-- PASSO 1 — Tabelas conformadas (conf_*)
-- A surrogate key global é gerada via SERIAL.
-- =====================================================================

DROP TABLE IF EXISTS stg.conf_cliente CASCADE;
CREATE TABLE stg.conf_cliente (
    sk_cliente      SERIAL          PRIMARY KEY,
    src_id          INTEGER         NOT NULL,
    grupo_fonte     SMALLINT        NOT NULL,
    nome            VARCHAR(200)    NOT NULL,
    tipo            VARCHAR(2)      NOT NULL,
    cidade          VARCHAR(100),
    dt_extracao     TIMESTAMP       NOT NULL DEFAULT NOW()
);

DROP TABLE IF EXISTS stg.conf_condutor CASCADE;
CREATE TABLE stg.conf_condutor (
    sk_condutor     SERIAL          PRIMARY KEY,
    src_id          INTEGER         NOT NULL,
    grupo_fonte     SMALLINT        NOT NULL,
    src_cliente_id  INTEGER         NOT NULL,
    nome            VARCHAR(200)    NOT NULL,
    cnh             VARCHAR(20),
    validade        DATE,
    categoria       VARCHAR(5),
    dt_extracao     TIMESTAMP       NOT NULL DEFAULT NOW()
);

DROP TABLE IF EXISTS stg.conf_grupo_veiculo CASCADE;
CREATE TABLE stg.conf_grupo_veiculo (
    sk_grupo        SERIAL          PRIMARY KEY,
    src_id          INTEGER         NOT NULL,
    grupo_fonte     SMALLINT        NOT NULL,
    nome            VARCHAR(100)    NOT NULL,
    categoria       VARCHAR(500)    NOT NULL,
    dt_extracao     TIMESTAMP       NOT NULL DEFAULT NOW()
);

DROP TABLE IF EXISTS stg.conf_veiculo CASCADE;
CREATE TABLE stg.conf_veiculo (
    sk_veiculo          SERIAL          PRIMARY KEY,
    src_id              INTEGER         NOT NULL,
    grupo_fonte         SMALLINT        NOT NULL,
    placa               VARCHAR(10)     NOT NULL,
    chassi              VARCHAR(50),
    modelo              VARCHAR(60)     NOT NULL,
    marca               VARCHAR(60)     NOT NULL,
    tipo_mecanizacao    VARCHAR(20)     NOT NULL,
    ar_condicionado     BOOLEAN         NOT NULL DEFAULT FALSE,
    adaptado_cadeirante BOOLEAN         NOT NULL DEFAULT FALSE,
    status              VARCHAR(20)     NOT NULL,
    sk_grupo            INTEGER         NOT NULL,
    nome_empresa        VARCHAR(150),
    dt_extracao         TIMESTAMP       NOT NULL DEFAULT NOW()
);

DROP TABLE IF EXISTS stg.conf_patio CASCADE;
CREATE TABLE stg.conf_patio (
    sk_patio        SERIAL          PRIMARY KEY,
    src_id          INTEGER         NOT NULL,
    grupo_fonte     SMALLINT        NOT NULL,
    nome            VARCHAR(150)    NOT NULL,
    cidade          VARCHAR(100),
    capacidade      INTEGER         NOT NULL,
    nome_empresa    VARCHAR(150)    NOT NULL,
    dt_extracao     TIMESTAMP       NOT NULL DEFAULT NOW()
);

DROP TABLE IF EXISTS stg.conf_reserva CASCADE;
CREATE TABLE stg.conf_reserva (
    sk_reserva              SERIAL          PRIMARY KEY,
    src_id                  INTEGER         NOT NULL,
    grupo_fonte             SMALLINT        NOT NULL,
    sk_cliente              INTEGER         NOT NULL,
    sk_grupo                INTEGER         NOT NULL,
    sk_patio_retirada       INTEGER         NOT NULL,
    sk_patio_devolucao      INTEGER,
    data_reserva            DATE,
    data_inicio             DATE            NOT NULL,
    data_fim                DATE,
    status                  VARCHAR(20)     NOT NULL,
    dt_extracao             TIMESTAMP       NOT NULL DEFAULT NOW()
);

DROP TABLE IF EXISTS stg.conf_locacao CASCADE;
CREATE TABLE stg.conf_locacao (
    sk_locacao              SERIAL          PRIMARY KEY,
    src_id                  INTEGER         NOT NULL,
    grupo_fonte             SMALLINT        NOT NULL,
    sk_cliente              INTEGER         NOT NULL,
    sk_condutor             INTEGER         NOT NULL,
    sk_veiculo              INTEGER         NOT NULL,
    sk_patio_retirada       INTEGER         NOT NULL,
    sk_patio_devolucao      INTEGER,
    data_registro           DATE            NOT NULL,
    data_retirada           DATE,
    data_devolucao          DATE,
    dias_alocados           INTEGER,
    km_rodado               INTEGER,
    valor_cobrado           DECIMAL(10,2),
    reserva_previa          BOOLEAN         NOT NULL DEFAULT FALSE,
    dt_extracao             TIMESTAMP       NOT NULL DEFAULT NOW()
);



-- =====================================================================
-- PASSO 2 — Carga nas tabelas conformadas
-- Agora a leitura vem diretamente das tabelas staging únicas
-- stg.cliente, stg.condutor, stg.grupo_veiculo etc.
-- =====================================================================

-- ----- conf_cliente --------------------------------------------------
INSERT INTO stg.conf_cliente (src_id, grupo_fonte, nome, tipo, cidade)
SELECT
    src_id,
    grupo_fonte,
    COALESCE(NULLIF(TRIM(nome),''), 'Cliente não informado') AS nome,
    CASE WHEN UPPER(TRIM(COALESCE(tipo,'PF'))) = 'PJ' THEN 'PJ' ELSE 'PF' END AS tipo,
    NULLIF(TRIM(cidade),'') AS cidade
FROM stg.cliente;

-- ----- conf_condutor -------------------------------------------------
-- Mantém a chave natural composta (grupo_fonte, src_id), pois as locações
-- dependem desse vínculo para resolver corretamente o condutor da origem.
INSERT INTO stg.conf_condutor
    (src_id, grupo_fonte, src_cliente_id, nome, cnh, validade, categoria)
SELECT
    src_id,
    grupo_fonte,
    src_cliente_id,
    COALESCE(NULLIF(TRIM(nome),''), 'Condutor não informado') AS nome,
    NULLIF(TRIM(cnh),'') AS cnh,
    validade,
    NULLIF(UPPER(TRIM(categoria)),'') AS categoria
FROM stg.condutor;

-- ----- conf_grupo_veiculo --------------------------------------------
INSERT INTO stg.conf_grupo_veiculo (src_id, grupo_fonte, nome, categoria)
SELECT
    src_id,
    grupo_fonte,
    COALESCE(NULLIF(TRIM(nome),''), 'Grupo não informado') AS nome,
    COALESCE(NULLIF(TRIM(categoria),''), 'sem categoria') AS categoria
FROM stg.grupo_veiculo;

-- ----- conf_patio ----------------------------------------------------
-- Capacidade: usa capacidade informada quando existir; caso contrário, conta vagas.
INSERT INTO stg.conf_patio (src_id, grupo_fonte, nome, cidade, capacidade, nome_empresa)
SELECT
    p.src_id,
    p.grupo_fonte,
    COALESCE(NULLIF(TRIM(p.nome),''), 'Pátio não informado') AS nome,
    NULLIF(TRIM(p.cidade),'') AS cidade,
    COALESCE(p.capacidade, COUNT(v.codigo)::INT, 0) AS capacidade,
    COALESCE(NULLIF(TRIM(p.nome_empresa),''), 'Empresa G' || p.grupo_fonte) AS nome_empresa
FROM stg.patio p
LEFT JOIN stg.vaga v
       ON v.src_patio_id = p.src_id
      AND v.grupo_fonte = p.grupo_fonte
GROUP BY p.src_id, p.grupo_fonte, p.nome, p.cidade, p.capacidade, p.nome_empresa;

-- ----- conf_veiculo --------------------------------------------------
INSERT INTO stg.conf_veiculo
    (src_id, grupo_fonte, placa, chassi, modelo, marca,
     tipo_mecanizacao, ar_condicionado, adaptado_cadeirante,
     status, sk_grupo, nome_empresa)
SELECT
    v.src_id,
    v.grupo_fonte,
    COALESCE(NULLIF(TRIM(v.placa),''), 'SEMPLACA') AS placa,
    NULLIF(TRIM(v.chassi),'') AS chassi,
    COALESCE(NULLIF(TRIM(v.modelo),''), 'Modelo não informado') AS modelo,
    COALESCE(NULLIF(TRIM(v.marca),''), 'Marca não informada') AS marca,
    CASE WHEN LOWER(COALESCE(v.tipo_mecanizacao,'')) LIKE '%auto%' THEN 'automatico'
         ELSE 'manual' END AS tipo_mecanizacao,
    COALESCE(v.ar_condicionado, FALSE) AS ar_condicionado,
    COALESCE(v.adaptado_cadeirante, FALSE) AS adaptado_cadeirante,
    CASE
        WHEN LOWER(COALESCE(v.status,'')) LIKE '%alug%'   THEN 'alugado'
        WHEN LOWER(COALESCE(v.status,'')) LIKE '%manut%'  THEN 'manutencao'
        WHEN LOWER(COALESCE(v.status,'')) LIKE '%dispon%' THEN 'disponivel'
        WHEN LOWER(COALESCE(v.status,'')) LIKE '%avail%'  THEN 'disponivel'
        ELSE 'disponivel'
    END AS status,
    cg.sk_grupo,
    COALESCE(NULLIF(TRIM(v.nome_empresa),''), 'Empresa G' || v.grupo_fonte) AS nome_empresa
FROM stg.veiculo v
JOIN stg.conf_grupo_veiculo cg
  ON cg.src_id = v.src_grupo_id
 AND cg.grupo_fonte = v.grupo_fonte;

-- ----- conf_reserva --------------------------------------------------
INSERT INTO stg.conf_reserva
    (src_id, grupo_fonte, sk_cliente, sk_grupo,
     sk_patio_retirada, sk_patio_devolucao,
     data_reserva, data_inicio, data_fim, status)
SELECT
    r.src_id,
    r.grupo_fonte,
    cc.sk_cliente,
    cg.sk_grupo,
    cp_ret.sk_patio,
    cp_dev.sk_patio,
    COALESCE(r.data_reserva, r.data_solicitacao, r.dt_extracao)::DATE AS data_reserva,
    r.data_inicio::DATE,
    r.data_fim::DATE,
    CASE
        WHEN LOWER(COALESCE(r.status,'')) LIKE '%cancel%'  THEN 'cancelada'
        WHEN LOWER(COALESCE(r.status,'')) LIKE '%confirm%' THEN 'confirmada'
        WHEN LOWER(COALESCE(r.status,'')) LIKE '%espera%'  THEN 'espera'
        WHEN LOWER(COALESCE(r.status,'')) LIKE '%wait%'    THEN 'espera'
        ELSE 'ativa'
    END AS status
FROM stg.reserva r
JOIN stg.conf_cliente cc
  ON cc.src_id = r.src_cliente_id
 AND cc.grupo_fonte = r.grupo_fonte
JOIN stg.conf_grupo_veiculo cg
  ON cg.src_id = r.src_grupo_id
 AND cg.grupo_fonte = r.grupo_fonte
JOIN stg.conf_patio cp_ret
  ON cp_ret.src_id = r.src_patio_retirada_id
 AND cp_ret.grupo_fonte = r.grupo_fonte
LEFT JOIN stg.conf_patio cp_dev
  ON cp_dev.src_id = r.src_patio_devolucao_id
 AND cp_dev.grupo_fonte = r.grupo_fonte
WHERE r.data_inicio IS NOT NULL
  AND r.data_fim IS NOT NULL;

-- ----- conf_locacao --------------------------------------------------
INSERT INTO stg.conf_locacao
    (src_id, grupo_fonte, sk_cliente, sk_condutor, sk_veiculo,
     sk_patio_retirada, sk_patio_devolucao,
     data_registro, data_retirada, data_devolucao,
     dias_alocados, km_rodado, valor_cobrado, reserva_previa)
SELECT
    l.src_id,
    l.grupo_fonte,
    cc.sk_cliente,
    cd.sk_condutor,
    cv.sk_veiculo,
    cp_ret.sk_patio,
    cp_dev.sk_patio,
    COALESCE(l.created_at, l.data_retirada_realizada, l.dt_extracao)::DATE AS data_registro,
    l.data_retirada_realizada::DATE AS data_retirada,
    l.data_devolucao_realizada::DATE AS data_devolucao,
    CASE WHEN l.data_devolucao_realizada IS NOT NULL AND l.data_retirada_realizada IS NOT NULL
         THEN (l.data_devolucao_realizada::DATE - l.data_retirada_realizada::DATE)
         ELSE NULL END AS dias_alocados,
    CASE WHEN l.km_entrega IS NOT NULL AND l.km_devolucao IS NOT NULL
         THEN l.km_devolucao - l.km_entrega
         ELSE NULL END AS km_rodado,
    COALESCE(l.preco_final, l.valor_total, l.valor_final, 0) AS valor_cobrado,
    (l.src_reserva_id IS NOT NULL) AS reserva_previa
FROM stg.locacao l
JOIN stg.conf_cliente cc
  ON cc.src_id = l.src_cliente_id
 AND cc.grupo_fonte = l.grupo_fonte
JOIN stg.conf_condutor cd
  ON cd.src_id = l.src_condutor_id
 AND cd.grupo_fonte = l.grupo_fonte
JOIN stg.conf_veiculo cv
  ON cv.src_id = l.src_veiculo_id
 AND cv.grupo_fonte = l.grupo_fonte
JOIN stg.conf_patio cp_ret
  ON cp_ret.src_id = l.src_patio_retirada_id
 AND cp_ret.grupo_fonte = l.grupo_fonte
LEFT JOIN stg.conf_patio cp_dev
  ON cp_dev.src_id = l.src_patio_devolucao_id
 AND cp_dev.grupo_fonte = l.grupo_fonte;

-- =====================================================================
-- PASSO 3 — Preencher dim_tempo (se ainda não populada)
-- Gera todos os dias de 2020-01-01 a 2030-12-31 com generate_series.
-- Muito mais idiomático que loop em PostgreSQL.
-- =====================================================================
INSERT INTO dim_tempo
    (id_tempo, data, ano, semestre, trimestre, mes, nome_mes,
     semana_do_ano, dia, dia_da_semana, nome_dia, fim_de_semana)
SELECT
    TO_CHAR(d, 'YYYYMMDD')::INT,
    d::DATE,
    EXTRACT(YEAR FROM d)::INT,
    CASE WHEN EXTRACT(MONTH FROM d) <= 6 THEN 1 ELSE 2 END,
    EXTRACT(QUARTER FROM d)::INT,
    EXTRACT(MONTH FROM d)::INT,
    TRIM(TO_CHAR(d, 'TMMonth')),               -- nome do mês localizado
    EXTRACT(WEEK FROM d)::INT,
    EXTRACT(DAY FROM d)::INT,
    EXTRACT(ISODOW FROM d)::INT,               -- 1=segunda ... 7=domingo
    TRIM(TO_CHAR(d, 'TMDay')),
    (EXTRACT(ISODOW FROM d) IN (6,7))          -- sábado ou domingo
FROM generate_series('2020-01-01'::DATE, '2030-12-31'::DATE, '1 day') AS d
WHERE NOT EXISTS (
    SELECT 1 FROM dim_tempo dt
    WHERE dt.id_tempo = TO_CHAR(d, 'YYYYMMDD')::INT
);
