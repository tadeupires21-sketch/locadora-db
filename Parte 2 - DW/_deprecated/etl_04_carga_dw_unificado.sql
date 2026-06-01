-- =====================================================
-- Nome: Tadeu Belfort Neto
-- DRE: 119034813
-- Arquivo: etl_04_carga_dw.sql
-- Descrição: Carga ETL — staging conformado → DW
--            Popula dimensões e fatos do esquema estrela
--            a partir das tabelas stg.conf_* .
--
-- Banco: PostgreSQL
--
-- Upsert feito com INSERT ... ON CONFLICT (idiomático no
-- PostgreSQL, substitui o MERGE do SQL Server).
-- Requer que as colunas sk_* das dimensões tenham
-- constraint UNIQUE (já têm, conforme dw_schema_estrela).
--
-- Ordem obrigatória (respeita FKs):
--   1. dim_grupo_veiculo  2. dim_patio  3. dim_cliente
--   4. dim_condutor  5. dim_veiculo
--   6. fato_locacao  7. fato_reserva  8. fato_veiculo_no_patio
-- =====================================================


-- =====================================================================
-- 1. dim_grupo_veiculo
-- =====================================================================
NSERT INTO dim_grupo_veiculo (sk_grupo, nome, categoria)
SELECT sk_grupo, nome, categoria
FROM stg.conf_grupo_veiculo
ON CONFLICT (sk_grupo) DO NOTHING;


-- =====================================================================
-- 2. dim_patio
-- =====================================================================
INSERT INTO dim_patio (sk_patio, nome_patio, cidade, empresa, capacidade)
SELECT sk_patio, nome, COALESCE(cidade,'N/D'), nome_empresa, capacidade
FROM stg.conf_patio
ON CONFLICT (sk_patio) DO UPDATE
   SET capacidade = EXCLUDED.capacidade,
       nome_patio = EXCLUDED.nome_patio;


-- =====================================================================
-- 3. dim_cliente  (SCD Tipo 1 — sobrescreve)
-- =====================================================================
INSERT INTO dim_cliente (sk_cliente, nome, tipo, cidade)
SELECT sk_cliente, nome, tipo, COALESCE(cidade,'N/D')
FROM stg.conf_cliente
ON CONFLICT (sk_cliente) DO UPDATE
   SET nome   = EXCLUDED.nome,
       cidade = EXCLUDED.cidade;


-- =====================================================================
-- 4. dim_condutor  (SCD Tipo 1)
-- =====================================================================
INSERT INTO dim_condutor
    (sk_condutor, nome, cnh, validade, categoria, cidade_cliente, tipo_cliente)
SELECT
    cd.sk_condutor, cd.nome, cd.cnh, cd.validade, cd.categoria,
    cc.cidade, cc.tipo
FROM stg.conf_condutor cd
LEFT JOIN stg.conf_cliente cc
       ON cc.src_id = cd.src_cliente_id
      AND cc.grupo_fonte = cd.grupo_fonte
ON CONFLICT (sk_condutor) DO UPDATE
   SET validade = EXCLUDED.validade;


-- =====================================================================
-- 5. dim_veiculo  (SCD Tipo 1)
-- =====================================================================
INSERT INTO dim_veiculo
    (sk_veiculo, placa, chassi, modelo, marca,
     tipo_mecanizacao, ar_condicionado, adaptado_cadeirante,
     empresa_dona, id_grupo)
SELECT
    v.sk_veiculo, v.placa, v.chassi, v.modelo, v.marca,
    v.tipo_mecanizacao, v.ar_condicionado, v.adaptado_cadeirante,
    v.nome_empresa, g.id_grupo
FROM stg.conf_veiculo v
JOIN dim_grupo_veiculo g ON g.sk_grupo = v.sk_grupo
ON CONFLICT (sk_veiculo) DO NOTHING;


-- =====================================================================
-- 6. fato_locacao
-- Insere apenas locações ainda não carregadas (por nk_locacao_oltp)
-- dim_tempo usa id no formato YYYYMMDD → TO_CHAR(...)::INT
-- =====================================================================
INSERT INTO fato_locacao
    (fk_cliente, fk_condutor, fk_veiculo,
     fk_patio_retirada, fk_patio_devolucao,
     fk_data_registro, fk_dia_retirada, fk_dia_devolucao,
     dias_alocados, dias_para_devolucao,
     valor_cobrado, km_rodado, reserva_previa,
     nk_locacao_oltp)
SELECT
    dc.id_cliente,
    dd.id_condutor,
    dv.id_veiculo,
    dp_ret.id_patio,
    dp_dev.id_patio,
    TO_CHAR(l.data_registro,  'YYYYMMDD')::INT,
    CASE WHEN l.data_retirada IS NOT NULL
         THEN TO_CHAR(l.data_retirada, 'YYYYMMDD')::INT END,
    CASE WHEN l.data_devolucao IS NOT NULL
         THENI TO_CHAR(l.data_devolucao,'YYYYMMDD')::INT END,
    l.dias_alocados,
    CASE WHEN l.data_devolucao IS NULL AND l.data_retirada IS NOT NULL
         THEN (l.data_retirada - CURRENT_DATE)
         ELSE NULL END,
    l.valor_cobrado,
    l.km_rodado,
    l.reserva_previa,
    l.src_id
FROM stg.conf_locacao       l
JOIN dim_cliente            dc      ON dc.sk_cliente  = l.sk_cliente
JOIN dim_condutor           dd      ON dd.sk_condutor = l.sk_condutor
JOIN dim_veiculo            dv      ON dv.sk_veiculo  = l.sk_veiculo
JOIN dim_patio              dp_ret  ON dp_ret.sk_patio = l.sk_patio_retirada
LEFT JOIN dim_patio         dp_dev  ON dp_dev.sk_patio = l.sk_patio_devolucao
WHERE NOT EXISTS (
    SELECT 1 FROM fato_locacao fl
    WHERE fl.nk_locacao_oltp = l.src_id
);


-- =====================================================================
-- 7. fato_reserva
-- =====================================================================
INSERT INTO fato_reserva
    (fk_cliente, fk_grupo_veiculo,
     fk_patio_retirada, fk_patio_devolucao,
     fk_data_reserva, fk_dia_retirada_prevista, fk_dia_devolucao_prevista,
     antecedencia_dias, duracao_prevista_dias,
     tempo_ate_retirada, status_reserva,
     nk_reserva_oltp)
SELECT
    dc.id_cliente,
    dg.id_grupo,
    dp_ret.id_patio,
    dp_dev.id_patio,
    TO_CHAR(r.data_reserva, 'YYYYMMDD')::INT,
    TO_CHAR(r.data_inicio,  'YYYYMMDD')::INT,
    CASE WHEN r.data_fim IS NOT NULL
         THEN TO_CHAR(r.data_fim, 'YYYYMMDD')::INT END,
    CASE WHEN r.data_reserva IS NOT NULL AND r.data_inicio IS NOT NULL
         THEN (r.data_inicio - r.data_reserva)
         ELSE 0 END,
    CASE WHEN r.data_fim IS NOT NULL AND r.data_inicio IS NOT NULL
         THEN (r.data_fim - r.data_inicio)
         ELSE NULL END,
    CASE WHEN r.data_inicio >= CURRENT_DATE
         THEN (r.data_inicio - CURRENT_DATE)
         ELSE 0 END,
    r.status,
    r.src_id
FROM stg.conf_reserva       r
JOIN dim_cliente            dc      ON dc.sk_cliente = r.sk_cliente
JOIN dim_grupo_veiculo      dg      ON dg.sk_grupo   = r.sk_grupo
JOIN dim_patio              dp_ret  ON dp_ret.sk_patio = r.sk_patio_retirada
LEFT JOIN dim_patio         dp_dev  ON dp_dev.sk_patio = r.sk_patio_devolucao
WHERE NOT EXISTS (
    SELECT 1 FROM fato_reserva fr
    WHERE fr.nk_reserva_oltp = r.src_id
);


-- =====================================================================
-- 8. fato_veiculo_no_patio  (snapshot diário)
-- Registra a posição atual de cada veículo para a data de hoje.
-- =====================================================================
INSERT INTO fato_veiculo_no_patio
    (fk_veiculo, fk_patio_atual, fk_data_snapshot,
     status_veiculo, patio_original, fk_patio_origem)
SELECT
    dv.id_veiculo,
    dp.id_patio,
    TO_CHAR(CURRENT_DATE, 'YYYYMMDD')::INT,
    CASE WHEN fl_aberta.id_locacao IS NOT NULL THEN 'alugado'
         ELSE cv.status END,
    (LOWER(dp.empresa) = LOWER(dv.empresa_dona)),
    dp_orig.id_patio
FROM stg.conf_veiculo cv
JOIN dim_veiculo       dv  ON dv.sk_veiculo = cv.sk_veiculo
LEFT JOIN (
    SELECT fk_veiculo,
           MAX(id_locacao) AS id_locacao,
           MAX(fk_patio_devolucao) AS fk_patio_devolucao,
           MAX(fk_patio_retirada)  AS fk_patio_retirada
    FROM fato_locacao
    WHERE fk_dia_devolucao IS NOT NULL
    GROUP BY fk_veiculo
) ul ON ul.fk_veiculo = dv.id_veiculo
LEFT JOIN dim_patio dp ON dp.id_patio = COALESCE(ul.fk_patio_devolucao, ul.fk_patio_retirada)
LEFT JOIN (
    SELECT id_locacao, fk_veiculo
    FROM fato_locacao
    WHERE fk_dia_devolucao IS NULL
) fl_aberta ON fl_aberta.fk_veiculo = dv.id_veiculo
LEFT JOIN dim_patio dp_orig ON dp_orig.id_patio = ul.fk_patio_retirada
WHERE dp.id_patio IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM fato_veiculo_no_patio fvp
    WHERE fvp.fk_veiculo = dv.id_veiculo
      AND fvp.fk_data_snapshot = TO_CHAR(CURRENT_DATE, 'YYYYMMDD')::INT
);


-- =====================================================================
-- LOG DE CARGA
-- =====================================================================
CREATE TABLE IF NOT EXISTS stg.log_carga (
    id_log          SERIAL          PRIMARY KEY,
    tabela_dw       VARCHAR(60)     NOT NULL,
    dt_carga        TIMESTAMP       NOT NULL DEFAULT NOW(),
    qtd_inserida    INTEGER         NOT NULL,
    status          VARCHAR(10)     NOT NULL DEFAULT 'OK'
);

INSERT INTO stg.log_carga (tabela_dw, qtd_inserida)
VALUES
    ('dim_grupo_veiculo',     (SELECT COUNT(*) FROM dim_grupo_veiculo)),
    ('dim_patio',             (SELECT COUNT(*) FROM dim_patio)),
    ('dim_cliente',           (SELECT COUNT(*) FROM dim_cliente)),
    ('dim_condutor',          (SELECT COUNT(*) FROM dim_condutor)),
    ('dim_veiculo',           (SELECT COUNT(*) FROM dim_veiculo)),
    ('fato_locacao',          (SELECT COUNT(*) FROM fato_locacao)),
    ('fato_reserva',          (SELECT COUNT(*) FROM fato_reserva)),
    ('fato_veiculo_no_patio', (SELECT COUNT(*) FROM fato_veiculo_no_patio));
