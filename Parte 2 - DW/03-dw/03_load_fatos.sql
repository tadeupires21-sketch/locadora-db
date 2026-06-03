-- =====================================================
-- 03_load_fatos.sql
-- Carga idempotente das fatos do DW
-- Grupo:
--   Tadeu Belfort Neto              DRE 119034813
--   Vicente Alves                   DRE 1220044148
--   João Pedro de Lacerda           DRE 116076670
-- Execute somente depois da carga das dimensoes.
-- As fatos usam stg.conf_* como fonte principal e resolvem as SKs
-- por meio das chaves naturais conformadas.
--
-- Tabelas conformadas usadas como fonte:
--   stg.conf_reserva, stg.conf_locacao, stg.conf_cobranca,
--   stg.conf_movimentacao_patio.
--
-- Cobranca:
--   stg.conf_cobranca (grao por locacao) alimenta valor_cobranca e
--   status_cobranca de dw.fato_locacao via LEFT JOIN por locacao_nk.
-- =====================================================

BEGIN;

-- =====================================================
-- Validacoes bloqueantes de orfandade antes da carga.
-- Assim, fatos com dimensao obrigatoria ausente nao sao carregadas
-- silenciosamente.
-- =====================================================
DO $$
DECLARE
    qtd_orfaos INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO qtd_orfaos
    FROM stg.conf_reserva r
    LEFT JOIN dw.dim_cliente c
           ON c.cliente_id = r.cliente_nk
    LEFT JOIN dw.dim_grupo_veiculo g
           ON g.grupo_id = r.grupo_veiculo_nk
    LEFT JOIN dw.dim_patio pr
           ON pr.patio_id = r.patio_retirada_nk
    LEFT JOIN dw.dim_patio pd
           ON pd.patio_id = r.patio_devolucao_nk
    LEFT JOIN dw.dim_tempo ti
           ON ti.data = r.data_inicio
    LEFT JOIN dw.dim_tempo tf
           ON tf.data = r.data_fim
    WHERE c.sk_cliente IS NULL
       OR g.sk_grupo_veiculo IS NULL
       OR pr.sk_patio IS NULL
       OR r.data_inicio IS NULL
       OR ti.sk_tempo IS NULL
       OR (r.patio_devolucao_nk IS NOT NULL AND pd.sk_patio IS NULL)
       OR (r.data_fim IS NOT NULL AND tf.sk_tempo IS NULL);

    IF qtd_orfaos > 0 THEN
        RAISE EXCEPTION
            'Carga de dw.fato_reserva abortada: % reserva(s) com dimensao obrigatoria ausente.',
            qtd_orfaos;
    END IF;

    SELECT COUNT(*)
    INTO qtd_orfaos
    FROM stg.conf_locacao l
    LEFT JOIN dw.dim_cliente c
           ON c.cliente_id = l.cliente_nk
    LEFT JOIN dw.dim_condutor cd
           ON cd.condutor_id = l.condutor_nk
    LEFT JOIN dw.dim_veiculo v
           ON v.veiculo_id = l.veiculo_nk
    LEFT JOIN dw.dim_patio pr
           ON pr.patio_id = l.patio_retirada_nk
    LEFT JOIN dw.dim_patio pd
           ON pd.patio_id = l.patio_devolucao_nk
    LEFT JOIN dw.dim_tempo trp
           ON trp.data = l.data_retirada_prevista
    LEFT JOIN dw.dim_tempo trr
           ON trr.data = l.data_retirada
    LEFT JOIN dw.dim_tempo tdp
           ON tdp.data = l.data_devolucao_prevista
    LEFT JOIN dw.dim_tempo tdr
           ON tdr.data = l.data_devolucao
    WHERE c.sk_cliente IS NULL
       OR cd.sk_condutor IS NULL
       OR v.sk_veiculo IS NULL
       OR pr.sk_patio IS NULL
       OR (l.patio_devolucao_nk IS NOT NULL AND pd.sk_patio IS NULL)
       OR (l.data_retirada_prevista IS NOT NULL AND trp.sk_tempo IS NULL)
       OR (l.data_retirada IS NOT NULL AND trr.sk_tempo IS NULL)
       OR (l.data_devolucao_prevista IS NOT NULL AND tdp.sk_tempo IS NULL)
       OR (l.data_devolucao IS NOT NULL AND tdr.sk_tempo IS NULL);

    IF qtd_orfaos > 0 THEN
        RAISE EXCEPTION
            'Carga de dw.fato_locacao abortada: % locacao(oes) com dimensao obrigatoria ausente.',
            qtd_orfaos;
    END IF;

    SELECT COUNT(*)
    INTO qtd_orfaos
    FROM stg.conf_movimentacao_patio m
    LEFT JOIN dw.dim_veiculo v
           ON v.veiculo_id = m.veiculo_nk
    LEFT JOIN dw.dim_patio po
           ON po.patio_id = m.patio_origem_nk
    LEFT JOIN dw.dim_patio pd
           ON pd.patio_id = m.patio_destino_nk
    LEFT JOIN dw.dim_tempo tm
           ON tm.data = m.data_movimentacao
    WHERE v.sk_veiculo IS NULL
       OR po.sk_patio IS NULL
       OR pd.sk_patio IS NULL
       OR m.data_movimentacao IS NULL
       OR tm.sk_tempo IS NULL;

    IF qtd_orfaos > 0 THEN
        RAISE EXCEPTION
            'Carga de dw.fato_veiculo_no_patio abortada: % movimentacao(oes) com dimensao obrigatoria ausente.',
            qtd_orfaos;
    END IF;
END $$;

-- =====================================================
-- fato_reserva
-- Medidas:
--   qtd_reservas = 1
--   dias_reservados = data_fim - data_inicio + 1
--   flags derivadas do status conformado.
-- =====================================================
INSERT INTO dw.fato_reserva (
    reserva_id,
    sk_cliente,
    sk_grupo_veiculo,
    sk_patio_retirada,
    sk_patio_devolucao,
    sk_tempo_inicio,
    sk_tempo_fim,
    status_reserva,
    qtd_reservas,
    dias_reservados,
    flag_cancelada,
    flag_confirmada,
    flag_espera
)
SELECT
    r.reserva_nk AS reserva_id,
    c.sk_cliente,
    g.sk_grupo_veiculo,
    pr.sk_patio AS sk_patio_retirada,
    pd.sk_patio AS sk_patio_devolucao,
    ti.sk_tempo AS sk_tempo_inicio,
    tf.sk_tempo AS sk_tempo_fim,
    r.status AS status_reserva,
    1 AS qtd_reservas,
    -- Protegido com GREATEST para nunca ficar negativo (datas invertidas
    -- viram 0, que a validação pós-carga sinaliza como inválido).
    -- Convenção inclusiva (+1), igual a dias_realizados em fato_locacao.
    CASE
        WHEN r.data_inicio IS NOT NULL AND r.data_fim IS NOT NULL
            THEN GREATEST(r.data_fim - r.data_inicio + 1, 0)::INTEGER
    END AS dias_reservados,
    (r.status = 'cancelada') AS flag_cancelada,
    (r.status = 'confirmada') AS flag_confirmada,
    (r.status = 'espera') AS flag_espera
FROM stg.conf_reserva r
JOIN dw.dim_cliente c
  ON c.cliente_id = r.cliente_nk
JOIN dw.dim_grupo_veiculo g
  ON g.grupo_id = r.grupo_veiculo_nk
JOIN dw.dim_patio pr
  ON pr.patio_id = r.patio_retirada_nk
LEFT JOIN dw.dim_patio pd
  ON pd.patio_id = r.patio_devolucao_nk
JOIN dw.dim_tempo ti
  ON ti.data = r.data_inicio
LEFT JOIN dw.dim_tempo tf
  ON tf.data = r.data_fim
ON CONFLICT (reserva_id) DO UPDATE
SET
    sk_cliente = EXCLUDED.sk_cliente,
    sk_grupo_veiculo = EXCLUDED.sk_grupo_veiculo,
    sk_patio_retirada = EXCLUDED.sk_patio_retirada,
    sk_patio_devolucao = EXCLUDED.sk_patio_devolucao,
    sk_tempo_inicio = EXCLUDED.sk_tempo_inicio,
    sk_tempo_fim = EXCLUDED.sk_tempo_fim,
    status_reserva = EXCLUDED.status_reserva,
    qtd_reservas = EXCLUDED.qtd_reservas,
    dias_reservados = EXCLUDED.dias_reservados,
    flag_cancelada = EXCLUDED.flag_cancelada,
    flag_confirmada = EXCLUDED.flag_confirmada,
    flag_espera = EXCLUDED.flag_espera;

-- =====================================================
-- fato_locacao
-- Usa stg.conf_locacao como fonte principal e stg.conf_cobranca
-- (grao por locacao) para as medidas financeiras.
--
-- Cobranca:
--   valor_cobranca  = stg.conf_cobranca.valor_cobranca quando existe;
--                     senao, fallback para conf_locacao.valor_cobrado.
--   status_cobranca = stg.conf_cobranca.status_cobranca (pode ser nulo se
--                     a locacao nao tiver nenhuma cobranca associada).
-- O LEFT JOIN garante que locacoes sem cobranca ainda entrem no fato.
-- =====================================================
INSERT INTO dw.fato_locacao (
    locacao_id,
    reserva_id,
    sk_cliente,
    sk_condutor,
    sk_veiculo,
    sk_grupo_veiculo,
    sk_empresa,
    sk_patio_retirada,
    sk_patio_devolucao,
    sk_tempo_retirada_prevista,
    sk_tempo_retirada_realizada,
    sk_tempo_devolucao_prevista,
    sk_tempo_devolucao_realizada,
    km_entrega,
    km_devolucao,
    km_rodado,
    dias_previstos,
    dias_realizados,
    atraso_devolucao_dias,
    qtd_locacoes,
    valor_cobranca,
    valor_multa_atraso,
    status_cobranca
)
SELECT
    l.locacao_nk AS locacao_id,
    l.reserva_nk AS reserva_id,
    c.sk_cliente,
    cd.sk_condutor,
    v.sk_veiculo,
    v.sk_grupo_veiculo,
    v.sk_empresa,
    pr.sk_patio AS sk_patio_retirada,
    pd.sk_patio AS sk_patio_devolucao,
    trp.sk_tempo AS sk_tempo_retirada_prevista,
    trr.sk_tempo AS sk_tempo_retirada_realizada,
    tdp.sk_tempo AS sk_tempo_devolucao_prevista,
    tdr.sk_tempo AS sk_tempo_devolucao_realizada,
    l.km_entrega,
    l.km_devolucao,
    -- Medidas consumidas DIRETAMENTE de stg.conf_locacao (já protegidas
    -- com GREATEST e convenção de dias inclusiva). Não recalcular aqui:
    -- recalcular das datas/km crus reintroduziria valores negativos e
    -- divergiria da camada transform (era o bug anterior).
    l.km_rodado,
    l.dias_previstos,
    l.dias_realizados,
    l.atraso_devolucao_dias,
    1 AS qtd_locacoes,
    COALESCE(cob.valor_cobranca, l.valor_cobrado) AS valor_cobranca,
    l.valor_multa_atraso,
    cob.status_cobranca
FROM stg.conf_locacao l
JOIN dw.dim_cliente c
  ON c.cliente_id = l.cliente_nk
JOIN dw.dim_condutor cd
  ON cd.condutor_id = l.condutor_nk
JOIN dw.dim_veiculo v
  ON v.veiculo_id = l.veiculo_nk
JOIN dw.dim_patio pr
  ON pr.patio_id = l.patio_retirada_nk
LEFT JOIN dw.dim_patio pd
  ON pd.patio_id = l.patio_devolucao_nk
LEFT JOIN dw.dim_tempo trp
  ON trp.data = l.data_retirada_prevista
LEFT JOIN dw.dim_tempo trr
  ON trr.data = l.data_retirada
LEFT JOIN dw.dim_tempo tdp
  ON tdp.data = l.data_devolucao_prevista
LEFT JOIN dw.dim_tempo tdr
  ON tdr.data = l.data_devolucao
LEFT JOIN stg.conf_cobranca cob
  ON cob.locacao_nk = l.locacao_nk
ON CONFLICT (locacao_id) DO UPDATE
SET
    reserva_id = EXCLUDED.reserva_id,
    sk_cliente = EXCLUDED.sk_cliente,
    sk_condutor = EXCLUDED.sk_condutor,
    sk_veiculo = EXCLUDED.sk_veiculo,
    sk_grupo_veiculo = EXCLUDED.sk_grupo_veiculo,
    sk_empresa = EXCLUDED.sk_empresa,
    sk_patio_retirada = EXCLUDED.sk_patio_retirada,
    sk_patio_devolucao = EXCLUDED.sk_patio_devolucao,
    sk_tempo_retirada_prevista = EXCLUDED.sk_tempo_retirada_prevista,
    sk_tempo_retirada_realizada = EXCLUDED.sk_tempo_retirada_realizada,
    sk_tempo_devolucao_prevista = EXCLUDED.sk_tempo_devolucao_prevista,
    sk_tempo_devolucao_realizada = EXCLUDED.sk_tempo_devolucao_realizada,
    km_entrega = EXCLUDED.km_entrega,
    km_devolucao = EXCLUDED.km_devolucao,
    km_rodado = EXCLUDED.km_rodado,
    dias_previstos = EXCLUDED.dias_previstos,
    dias_realizados = EXCLUDED.dias_realizados,
    atraso_devolucao_dias = EXCLUDED.atraso_devolucao_dias,
    qtd_locacoes = EXCLUDED.qtd_locacoes,
    valor_cobranca = EXCLUDED.valor_cobranca,
    valor_multa_atraso = EXCLUDED.valor_multa_atraso,
    status_cobranca = EXCLUDED.status_cobranca;

-- =====================================================
-- fato_veiculo_no_patio
-- Base: movimentacoes entre patios.
-- =====================================================
INSERT INTO dw.fato_veiculo_no_patio (
    movimentacao_patio_id,
    sk_veiculo,
    sk_patio_origem,
    sk_patio_destino,
    sk_tempo_movimentacao,
    motivo,
    qtd_movimentacoes
)
SELECT
    m.movimentacao_patio_nk AS movimentacao_patio_id,
    v.sk_veiculo,
    po.sk_patio AS sk_patio_origem,
    pd.sk_patio AS sk_patio_destino,
    tm.sk_tempo AS sk_tempo_movimentacao,
    m.motivo,
    1 AS qtd_movimentacoes
FROM stg.conf_movimentacao_patio m
JOIN dw.dim_veiculo v
  ON v.veiculo_id = m.veiculo_nk
JOIN dw.dim_patio po
  ON po.patio_id = m.patio_origem_nk
JOIN dw.dim_patio pd
  ON pd.patio_id = m.patio_destino_nk
JOIN dw.dim_tempo tm
  ON tm.data = m.data_movimentacao
ON CONFLICT (movimentacao_patio_id) DO UPDATE
SET
    sk_veiculo = EXCLUDED.sk_veiculo,
    sk_patio_origem = EXCLUDED.sk_patio_origem,
    sk_patio_destino = EXCLUDED.sk_patio_destino,
    sk_tempo_movimentacao = EXCLUDED.sk_tempo_movimentacao,
    motivo = EXCLUDED.motivo,
    qtd_movimentacoes = EXCLUDED.qtd_movimentacoes;

COMMIT;

-- =====================================================
-- Validacoes de consistencia entre transform e DW
-- =====================================================

-- 1. Contagem entre transform e DW.
SELECT *
FROM (
    VALUES
        ('clientes',        (SELECT COUNT(*) FROM stg.conf_cliente),              (SELECT COUNT(*) FROM dw.dim_cliente)),
        ('veiculos',        (SELECT COUNT(*) FROM stg.conf_veiculo),              (SELECT COUNT(*) FROM dw.dim_veiculo)),
        ('reservas',        (SELECT COUNT(*) FROM stg.conf_reserva),              (SELECT COUNT(*) FROM dw.fato_reserva)),
        ('locacoes',        (SELECT COUNT(*) FROM stg.conf_locacao),              (SELECT COUNT(*) FROM dw.fato_locacao)),
        ('movimentacoes',   (SELECT COUNT(*) FROM stg.conf_movimentacao_patio),   (SELECT COUNT(*) FROM dw.fato_veiculo_no_patio))
) AS v(entidade, qtd_transform, qtd_dw)
ORDER BY entidade;

-- 2. Verificacao de chaves orfas nas fatos. O esperado e zero em todas as colunas.
SELECT
    'fato_reserva' AS tabela,
    COUNT(*) FILTER (WHERE c.sk_cliente IS NULL) AS fatos_sem_cliente,
    0 AS fatos_sem_veiculo,
    COUNT(*) FILTER (WHERE pr.sk_patio IS NULL OR (fr.sk_patio_devolucao IS NOT NULL AND pd.sk_patio IS NULL)) AS fatos_sem_patio,
    COUNT(*) FILTER (WHERE ti.sk_tempo IS NULL OR (fr.sk_tempo_fim IS NOT NULL AND tf.sk_tempo IS NULL)) AS fatos_sem_tempo,
    0 AS locacoes_sem_condutor_obrigatorio
FROM dw.fato_reserva fr
LEFT JOIN dw.dim_cliente c ON c.sk_cliente = fr.sk_cliente
LEFT JOIN dw.dim_patio pr ON pr.sk_patio = fr.sk_patio_retirada
LEFT JOIN dw.dim_patio pd ON pd.sk_patio = fr.sk_patio_devolucao
LEFT JOIN dw.dim_tempo ti ON ti.sk_tempo = fr.sk_tempo_inicio
LEFT JOIN dw.dim_tempo tf ON tf.sk_tempo = fr.sk_tempo_fim
UNION ALL
SELECT
    'fato_locacao',
    COUNT(*) FILTER (WHERE c.sk_cliente IS NULL),
    COUNT(*) FILTER (WHERE v.sk_veiculo IS NULL),
    COUNT(*) FILTER (WHERE pr.sk_patio IS NULL OR (fl.sk_patio_devolucao IS NOT NULL AND pd.sk_patio IS NULL)),
    COUNT(*) FILTER (
        WHERE (fl.sk_tempo_retirada_prevista IS NOT NULL AND trp.sk_tempo IS NULL)
           OR (fl.sk_tempo_retirada_realizada IS NOT NULL AND trr.sk_tempo IS NULL)
           OR (fl.sk_tempo_devolucao_prevista IS NOT NULL AND tdp.sk_tempo IS NULL)
           OR (fl.sk_tempo_devolucao_realizada IS NOT NULL AND tdr.sk_tempo IS NULL)
    ),
    COUNT(*) FILTER (WHERE cd.sk_condutor IS NULL)
FROM dw.fato_locacao fl
LEFT JOIN dw.dim_cliente c ON c.sk_cliente = fl.sk_cliente
LEFT JOIN dw.dim_condutor cd ON cd.sk_condutor = fl.sk_condutor
LEFT JOIN dw.dim_veiculo v ON v.sk_veiculo = fl.sk_veiculo
LEFT JOIN dw.dim_patio pr ON pr.sk_patio = fl.sk_patio_retirada
LEFT JOIN dw.dim_patio pd ON pd.sk_patio = fl.sk_patio_devolucao
LEFT JOIN dw.dim_tempo trp ON trp.sk_tempo = fl.sk_tempo_retirada_prevista
LEFT JOIN dw.dim_tempo trr ON trr.sk_tempo = fl.sk_tempo_retirada_realizada
LEFT JOIN dw.dim_tempo tdp ON tdp.sk_tempo = fl.sk_tempo_devolucao_prevista
LEFT JOIN dw.dim_tempo tdr ON tdr.sk_tempo = fl.sk_tempo_devolucao_realizada
UNION ALL
SELECT
    'fato_veiculo_no_patio',
    0,
    COUNT(*) FILTER (WHERE v.sk_veiculo IS NULL),
    COUNT(*) FILTER (WHERE po.sk_patio IS NULL OR pd.sk_patio IS NULL),
    COUNT(*) FILTER (WHERE tm.sk_tempo IS NULL),
    0
FROM dw.fato_veiculo_no_patio fp
LEFT JOIN dw.dim_veiculo v ON v.sk_veiculo = fp.sk_veiculo
LEFT JOIN dw.dim_patio po ON po.sk_patio = fp.sk_patio_origem
LEFT JOIN dw.dim_patio pd ON pd.sk_patio = fp.sk_patio_destino
LEFT JOIN dw.dim_tempo tm ON tm.sk_tempo = fp.sk_tempo_movimentacao;

-- 3. Verificacao de duplicidade nas dimensoes e fatos.
SELECT 'dim_cliente' AS tabela, cliente_id AS chave, COUNT(*) AS qtd
FROM dw.dim_cliente
GROUP BY cliente_id
HAVING COUNT(*) > 1
UNION ALL
SELECT 'dim_condutor', condutor_id, COUNT(*)
FROM dw.dim_condutor
GROUP BY condutor_id
HAVING COUNT(*) > 1
UNION ALL
SELECT 'dim_grupo_veiculo', grupo_id, COUNT(*)
FROM dw.dim_grupo_veiculo
GROUP BY grupo_id
HAVING COUNT(*) > 1
UNION ALL
SELECT 'dim_empresa', empresa_id, COUNT(*)
FROM dw.dim_empresa
GROUP BY empresa_id
HAVING COUNT(*) > 1
UNION ALL
SELECT 'dim_patio', patio_id, COUNT(*)
FROM dw.dim_patio
GROUP BY patio_id
HAVING COUNT(*) > 1
UNION ALL
SELECT 'dim_veiculo', veiculo_id, COUNT(*)
FROM dw.dim_veiculo
GROUP BY veiculo_id
HAVING COUNT(*) > 1
UNION ALL
SELECT 'fato_reserva', reserva_id, COUNT(*)
FROM dw.fato_reserva
GROUP BY reserva_id
HAVING COUNT(*) > 1
UNION ALL
SELECT 'fato_locacao', locacao_id, COUNT(*)
FROM dw.fato_locacao
GROUP BY locacao_id
HAVING COUNT(*) > 1
UNION ALL
SELECT 'fato_veiculo_no_patio', movimentacao_patio_id, COUNT(*)
FROM dw.fato_veiculo_no_patio
GROUP BY movimentacao_patio_id
HAVING COUNT(*) > 1;

-- 4. Verificacao de medidas derivadas. O esperado e zero em todas as colunas.
SELECT
    COUNT(*) FILTER (WHERE km_rodado < 0) AS locacoes_km_rodado_negativo,
    COUNT(*) FILTER (WHERE dias_previstos < 0) AS locacoes_dias_previstos_negativo,
    COUNT(*) FILTER (WHERE dias_realizados < 0) AS locacoes_dias_realizados_negativo,
    COUNT(*) FILTER (
        WHERE t_real.data IS NOT NULL
          AND t_prev.data IS NOT NULL
          -- atraso é clampado em 0 (devolução antecipada não vira atraso
          -- negativo), então compara-se contra GREATEST(diff, 0).
          AND atraso_devolucao_dias <> GREATEST(t_real.data - t_prev.data, 0)
    ) AS locacoes_atraso_incoerente
FROM dw.fato_locacao fl
LEFT JOIN dw.dim_tempo t_real
       ON t_real.sk_tempo = fl.sk_tempo_devolucao_realizada
LEFT JOIN dw.dim_tempo t_prev
       ON t_prev.sk_tempo = fl.sk_tempo_devolucao_prevista;

SELECT
    COUNT(*) FILTER (WHERE dias_reservados <= 0) AS reservas_dias_reservados_invalidos
FROM dw.fato_reserva;

-- 5. Cobertura temporal: toda SK de tempo usada nas fatos deve existir em dim_tempo.
WITH chaves_tempo AS (
    SELECT 'fato_reserva.sk_tempo_inicio' AS origem, sk_tempo_inicio AS sk_tempo
    FROM dw.fato_reserva
    WHERE sk_tempo_inicio IS NOT NULL
    UNION ALL
    SELECT 'fato_reserva.sk_tempo_fim', sk_tempo_fim
    FROM dw.fato_reserva
    WHERE sk_tempo_fim IS NOT NULL
    UNION ALL
    SELECT 'fato_locacao.sk_tempo_retirada_prevista', sk_tempo_retirada_prevista
    FROM dw.fato_locacao
    WHERE sk_tempo_retirada_prevista IS NOT NULL
    UNION ALL
    SELECT 'fato_locacao.sk_tempo_retirada_realizada', sk_tempo_retirada_realizada
    FROM dw.fato_locacao
    WHERE sk_tempo_retirada_realizada IS NOT NULL
    UNION ALL
    SELECT 'fato_locacao.sk_tempo_devolucao_prevista', sk_tempo_devolucao_prevista
    FROM dw.fato_locacao
    WHERE sk_tempo_devolucao_prevista IS NOT NULL
    UNION ALL
    SELECT 'fato_locacao.sk_tempo_devolucao_realizada', sk_tempo_devolucao_realizada
    FROM dw.fato_locacao
    WHERE sk_tempo_devolucao_realizada IS NOT NULL
    UNION ALL
    SELECT 'fato_veiculo_no_patio.sk_tempo_movimentacao', sk_tempo_movimentacao
    FROM dw.fato_veiculo_no_patio
    WHERE sk_tempo_movimentacao IS NOT NULL
)
SELECT
    origem,
    COUNT(*) AS qtd_chaves_sem_dim_tempo
FROM chaves_tempo ct
LEFT JOIN dw.dim_tempo dt
       ON dt.sk_tempo = ct.sk_tempo
WHERE dt.sk_tempo IS NULL
GROUP BY origem
ORDER BY origem;

-- 6. Integridade analitica das medidas aditivas.
SELECT *
FROM (
    VALUES
        ('reservas',      (SELECT COUNT(*) FROM stg.conf_reserva),              (SELECT COALESCE(SUM(qtd_reservas), 0) FROM dw.fato_reserva)),
        ('locacoes',      (SELECT COUNT(*) FROM stg.conf_locacao),              (SELECT COALESCE(SUM(qtd_locacoes), 0) FROM dw.fato_locacao)),
        ('movimentacoes', (SELECT COUNT(*) FROM stg.conf_movimentacao_patio),   (SELECT COALESCE(SUM(qtd_movimentacoes), 0) FROM dw.fato_veiculo_no_patio))
) AS v(entidade, qtd_transform, soma_qtd_dw)
ORDER BY entidade;

-- =====================================================
-- VALIDACOES DE CONSISTENCIA ENTRE CAMADAS
--
-- Objetivo:
--   1. Verificar se alguma linha sumiu indevidamente.
--   2. Verificar se alguma linha duplicou.
--   3. Verificar se alguma chave natural deixou de encontrar dimensao.
--   4. Verificar se alguma medida ficou negativa ou nula indevidamente.
--   5. Verificar se as views analiticas batem com as tabelas fato.
--
-- Observacao:
--   Os scripts de transform criam tabelas conformadas no schema stg com
--   prefixo conf_*, incluindo stg.conf_cobranca (grao por locacao), que
--   alimenta valor_cobranca e status_cobranca de dw.fato_locacao.
-- =====================================================

-- -----------------------------------------------------
-- OLTP -> staging
-- Grupo 1, conforme os nomes reais usados em:
-- Parte 2 - DW/01-staging/etl_01_extracao_grupo_tadeu_unificado.sql
--
-- Para os grupos externos, os nomes de tabelas OLTP variam por fonte
-- e os ETLs aplicam filtros incrementais. Use stg.log_extracao para
-- conferir o volume efetivamente extraido por grupo_fonte.
-- -----------------------------------------------------

-- Volumes brutos esperados do grupo 1 contra staging (apenas tabelas de
-- carga FULL — cliente/condutor/grupo/veiculo/patio).
--
-- NOTA: as tabelas incrementais (reserva, locacao, cobranca,
-- movimentacao_patio) NÃO são reconciliadas aqui por contagem direta no
-- OLTP. A extração usa janela baseada em stg.log_extracao (última execução
-- OK), então recomputar o filtro aqui daria divergência. A reconciliação
-- dessas tabelas é feita pela conferência do log logo abaixo.
SELECT *
FROM (
    VALUES
        ('cliente',             (SELECT COUNT(*) FROM oltp_g1.cliente),             (SELECT COUNT(*) FROM stg.cliente WHERE grupo_fonte = 1)),
        ('condutor',            (SELECT COUNT(*) FROM oltp_g1.condutor),            (SELECT COUNT(*) FROM stg.condutor WHERE grupo_fonte = 1)),
        ('grupo_veiculo',       (SELECT COUNT(*) FROM oltp_g1.grupo_veiculo),       (SELECT COUNT(*) FROM stg.grupo_veiculo WHERE grupo_fonte = 1)),
        ('veiculo',             (SELECT COUNT(*) FROM oltp_g1.veiculo),             (SELECT COUNT(*) FROM stg.veiculo WHERE grupo_fonte = 1)),
        ('patio',               (SELECT COUNT(*) FROM oltp_g1.patio),               (SELECT COUNT(*) FROM stg.patio WHERE grupo_fonte = 1))
) AS v(entidade, qtd_oltp_esperada, qtd_staging)
ORDER BY entidade;

-- Conferencia do log de extracao contra o estado atual da staging.
SELECT
    le.grupo_fonte,
    le.tabela_stg,
    le.qtd_registros AS qtd_registrada_no_log,
    CASE le.tabela_stg
        WHEN 'cliente' THEN (SELECT COUNT(*) FROM stg.cliente s WHERE s.grupo_fonte = le.grupo_fonte)
        WHEN 'condutor' THEN (SELECT COUNT(*) FROM stg.condutor s WHERE s.grupo_fonte = le.grupo_fonte)
        WHEN 'grupo_veiculo' THEN (SELECT COUNT(*) FROM stg.grupo_veiculo s WHERE s.grupo_fonte = le.grupo_fonte)
        WHEN 'veiculo' THEN (SELECT COUNT(*) FROM stg.veiculo s WHERE s.grupo_fonte = le.grupo_fonte)
        WHEN 'patio' THEN (SELECT COUNT(*) FROM stg.patio s WHERE s.grupo_fonte = le.grupo_fonte)
        WHEN 'vaga' THEN (SELECT COUNT(*) FROM stg.vaga s WHERE s.grupo_fonte = le.grupo_fonte)
        WHEN 'reserva' THEN (SELECT COUNT(*) FROM stg.reserva s WHERE s.grupo_fonte = le.grupo_fonte)
        WHEN 'locacao' THEN (SELECT COUNT(*) FROM stg.locacao s WHERE s.grupo_fonte = le.grupo_fonte)
        WHEN 'cobranca' THEN (SELECT COUNT(*) FROM stg.cobranca s WHERE s.grupo_fonte = le.grupo_fonte)
        WHEN 'movimentacao_patio' THEN (SELECT COUNT(*) FROM stg.movimentacao_patio s WHERE s.grupo_fonte = le.grupo_fonte)
    END AS qtd_atual_staging
FROM stg.log_extracao le
ORDER BY le.grupo_fonte, le.tabela_stg;

-- Duplicidades na staging por chave natural tecnica (grupo_fonte, src_id).
SELECT 'stg.cliente' AS tabela, grupo_fonte, src_id, COUNT(*) AS qtd
FROM stg.cliente
GROUP BY grupo_fonte, src_id
HAVING COUNT(*) > 1
UNION ALL
SELECT 'stg.condutor', grupo_fonte, src_id, COUNT(*)
FROM stg.condutor
GROUP BY grupo_fonte, src_id
HAVING COUNT(*) > 1
UNION ALL
SELECT 'stg.grupo_veiculo', grupo_fonte, src_id, COUNT(*)
FROM stg.grupo_veiculo
GROUP BY grupo_fonte, src_id
HAVING COUNT(*) > 1
UNION ALL
SELECT 'stg.veiculo', grupo_fonte, src_id, COUNT(*)
FROM stg.veiculo
GROUP BY grupo_fonte, src_id
HAVING COUNT(*) > 1
UNION ALL
SELECT 'stg.patio', grupo_fonte, src_id, COUNT(*)
FROM stg.patio
GROUP BY grupo_fonte, src_id
HAVING COUNT(*) > 1
UNION ALL
SELECT 'stg.reserva', grupo_fonte, src_id, COUNT(*)
FROM stg.reserva
GROUP BY grupo_fonte, src_id
HAVING COUNT(*) > 1
UNION ALL
SELECT 'stg.locacao', grupo_fonte, src_id, COUNT(*)
FROM stg.locacao
GROUP BY grupo_fonte, src_id
HAVING COUNT(*) > 1
UNION ALL
SELECT 'stg.movimentacao_patio', grupo_fonte, src_id, COUNT(*)
FROM stg.movimentacao_patio
GROUP BY grupo_fonte, src_id
HAVING COUNT(*) > 1;

-- -----------------------------------------------------
-- staging -> transform
-- -----------------------------------------------------

-- Volumes entre staging e tabelas conformadas. Diferencas podem ser
-- esperadas quando a transformacao deduplica registros por grupo_fonte/src_id.
SELECT *
FROM (
    VALUES
        ('cliente',             (SELECT COUNT(*) FROM stg.cliente),             (SELECT COUNT(*) FROM stg.conf_cliente)),
        ('condutor',            (SELECT COUNT(*) FROM stg.condutor),            (SELECT COUNT(*) FROM stg.conf_condutor)),
        ('grupo_veiculo',       (SELECT COUNT(*) FROM stg.grupo_veiculo),       (SELECT COUNT(*) FROM stg.conf_grupo_veiculo)),
        ('empresa',             (SELECT COUNT(DISTINCT grupo_fonte::TEXT || '-' || COALESCE(src_empresa_id::TEXT, nome_empresa)) FROM stg.patio WHERE src_empresa_id IS NOT NULL OR nome_empresa IS NOT NULL), (SELECT COUNT(*) FROM stg.conf_empresa)),
        ('patio',               (SELECT COUNT(*) FROM stg.patio),               (SELECT COUNT(*) FROM stg.conf_patio)),
        ('veiculo',             (SELECT COUNT(*) FROM stg.veiculo),             (SELECT COUNT(*) FROM stg.conf_veiculo)),
        ('reserva',             (SELECT COUNT(*) FROM stg.reserva),             (SELECT COUNT(*) FROM stg.conf_reserva)),
        ('locacao',             (SELECT COUNT(*) FROM stg.locacao),             (SELECT COUNT(*) FROM stg.conf_locacao)),
        ('movimentacao_patio',  (SELECT COUNT(*) FROM stg.movimentacao_patio),  (SELECT COUNT(*) FROM stg.conf_movimentacao_patio))
) AS v(entidade, qtd_staging, qtd_transform)
ORDER BY entidade;

-- Chaves naturais da transform que deixaram de encontrar dimensoes conformadas.
SELECT
    'stg.conf_reserva' AS tabela,
    COUNT(*) FILTER (WHERE c.sk_cliente IS NULL) AS sem_cliente,
    COUNT(*) FILTER (WHERE g.sk_grupo IS NULL) AS sem_grupo_veiculo,
    0 AS sem_veiculo,
    COUNT(*) FILTER (WHERE pr.sk_patio IS NULL OR (r.patio_devolucao_nk IS NOT NULL AND pd.sk_patio IS NULL)) AS sem_patio,
    0 AS sem_condutor
FROM stg.conf_reserva r
LEFT JOIN stg.conf_cliente c ON c.cliente_nk = r.cliente_nk
LEFT JOIN stg.conf_grupo_veiculo g ON g.grupo_veiculo_nk = r.grupo_veiculo_nk
LEFT JOIN stg.conf_patio pr ON pr.patio_nk = r.patio_retirada_nk
LEFT JOIN stg.conf_patio pd ON pd.patio_nk = r.patio_devolucao_nk
UNION ALL
SELECT
    'stg.conf_locacao',
    COUNT(*) FILTER (WHERE c.sk_cliente IS NULL),
    0,
    COUNT(*) FILTER (WHERE v.sk_veiculo IS NULL),
    COUNT(*) FILTER (WHERE pr.sk_patio IS NULL OR (l.patio_devolucao_nk IS NOT NULL AND pd.sk_patio IS NULL)),
    COUNT(*) FILTER (WHERE cd.sk_condutor IS NULL)
FROM stg.conf_locacao l
LEFT JOIN stg.conf_cliente c ON c.cliente_nk = l.cliente_nk
LEFT JOIN stg.conf_condutor cd ON cd.condutor_nk = l.condutor_nk
LEFT JOIN stg.conf_veiculo v ON v.veiculo_nk = l.veiculo_nk
LEFT JOIN stg.conf_patio pr ON pr.patio_nk = l.patio_retirada_nk
LEFT JOIN stg.conf_patio pd ON pd.patio_nk = l.patio_devolucao_nk
UNION ALL
SELECT
    'stg.conf_movimentacao_patio',
    0,
    0,
    COUNT(*) FILTER (WHERE v.sk_veiculo IS NULL),
    COUNT(*) FILTER (WHERE po.sk_patio IS NULL OR pd.sk_patio IS NULL),
    0
FROM stg.conf_movimentacao_patio m
LEFT JOIN stg.conf_veiculo v ON v.veiculo_nk = m.veiculo_nk
LEFT JOIN stg.conf_patio po ON po.patio_nk = m.patio_origem_nk
LEFT JOIN stg.conf_patio pd ON pd.patio_nk = m.patio_destino_nk;

-- Medidas negativas ou nulas indevidas na transform.
SELECT
    'stg.conf_reserva' AS tabela,
    COUNT(*) FILTER (WHERE data_inicio IS NULL) AS data_base_nula,
    COUNT(*) FILTER (WHERE data_fim IS NOT NULL AND data_fim < data_inicio) AS periodo_negativo,
    0 AS km_negativo,
    0 AS valor_negativo
FROM stg.conf_reserva
UNION ALL
SELECT
    'stg.conf_locacao',
    COUNT(*) FILTER (WHERE data_retirada_prevista IS NULL AND data_retirada IS NULL),
    COUNT(*) FILTER (
        WHERE data_devolucao_prevista IS NOT NULL
          AND data_retirada_prevista IS NOT NULL
          AND data_devolucao_prevista < data_retirada_prevista
    ),
    COUNT(*) FILTER (WHERE km_rodado < 0),
    COUNT(*) FILTER (WHERE valor_cobrado < 0)
FROM stg.conf_locacao
UNION ALL
SELECT
    'stg.conf_movimentacao_patio',
    COUNT(*) FILTER (WHERE data_movimentacao IS NULL),
    0,
    0,
    0
FROM stg.conf_movimentacao_patio;

-- -----------------------------------------------------
-- transform -> dw
-- -----------------------------------------------------

-- Volumes e medidas aditivas entre transform e DW.
SELECT *
FROM (
    VALUES
        ('cliente',             (SELECT COUNT(*) FROM stg.conf_cliente),             (SELECT COUNT(*) FROM dw.dim_cliente)),
        ('condutor',            (SELECT COUNT(*) FROM stg.conf_condutor),            (SELECT COUNT(*) FROM dw.dim_condutor)),
        ('grupo_veiculo',       (SELECT COUNT(*) FROM stg.conf_grupo_veiculo),       (SELECT COUNT(*) FROM dw.dim_grupo_veiculo)),
        ('empresa',             (SELECT COUNT(*) FROM stg.conf_empresa),             (SELECT COUNT(*) FROM dw.dim_empresa)),
        ('patio',               (SELECT COUNT(*) FROM stg.conf_patio),               (SELECT COUNT(*) FROM dw.dim_patio)),
        ('veiculo',             (SELECT COUNT(*) FROM stg.conf_veiculo),             (SELECT COUNT(*) FROM dw.dim_veiculo)),
        ('reserva',             (SELECT COUNT(*) FROM stg.conf_reserva),             (SELECT COUNT(*) FROM dw.fato_reserva)),
        ('locacao',             (SELECT COUNT(*) FROM stg.conf_locacao),             (SELECT COUNT(*) FROM dw.fato_locacao)),
        ('movimentacao_patio',  (SELECT COUNT(*) FROM stg.conf_movimentacao_patio),  (SELECT COUNT(*) FROM dw.fato_veiculo_no_patio))
) AS v(entidade, qtd_transform, qtd_dw)
ORDER BY entidade;

SELECT *
FROM (
    VALUES
        ('reservas',      (SELECT COUNT(*) FROM stg.conf_reserva),             (SELECT COALESCE(SUM(qtd_reservas), 0) FROM dw.fato_reserva)),
        ('locacoes',      (SELECT COUNT(*) FROM stg.conf_locacao),             (SELECT COALESCE(SUM(qtd_locacoes), 0) FROM dw.fato_locacao)),
        ('movimentacoes', (SELECT COUNT(*) FROM stg.conf_movimentacao_patio),  (SELECT COALESCE(SUM(qtd_movimentacoes), 0) FROM dw.fato_veiculo_no_patio))
) AS v(medida, qtd_transform, soma_medida_dw)
ORDER BY medida;

-- Chaves naturais que nao encontraram dimensao no DW.
SELECT
    'dw.fato_reserva' AS tabela,
    COUNT(*) FILTER (WHERE c.sk_cliente IS NULL) AS sem_cliente,
    0 AS sem_condutor,
    0 AS sem_veiculo,
    COUNT(*) FILTER (WHERE pr.sk_patio IS NULL OR (fr.sk_patio_devolucao IS NOT NULL AND pd.sk_patio IS NULL)) AS sem_patio,
    COUNT(*) FILTER (WHERE ti.sk_tempo IS NULL OR (fr.sk_tempo_fim IS NOT NULL AND tf.sk_tempo IS NULL)) AS sem_tempo
FROM dw.fato_reserva fr
LEFT JOIN dw.dim_cliente c ON c.sk_cliente = fr.sk_cliente
LEFT JOIN dw.dim_patio pr ON pr.sk_patio = fr.sk_patio_retirada
LEFT JOIN dw.dim_patio pd ON pd.sk_patio = fr.sk_patio_devolucao
LEFT JOIN dw.dim_tempo ti ON ti.sk_tempo = fr.sk_tempo_inicio
LEFT JOIN dw.dim_tempo tf ON tf.sk_tempo = fr.sk_tempo_fim
UNION ALL
SELECT
    'dw.fato_locacao',
    COUNT(*) FILTER (WHERE c.sk_cliente IS NULL),
    COUNT(*) FILTER (WHERE cd.sk_condutor IS NULL),
    COUNT(*) FILTER (WHERE v.sk_veiculo IS NULL),
    COUNT(*) FILTER (WHERE pr.sk_patio IS NULL OR (fl.sk_patio_devolucao IS NOT NULL AND pd.sk_patio IS NULL)),
    COUNT(*) FILTER (
        WHERE (fl.sk_tempo_retirada_prevista IS NOT NULL AND trp.sk_tempo IS NULL)
           OR (fl.sk_tempo_retirada_realizada IS NOT NULL AND trr.sk_tempo IS NULL)
           OR (fl.sk_tempo_devolucao_prevista IS NOT NULL AND tdp.sk_tempo IS NULL)
           OR (fl.sk_tempo_devolucao_realizada IS NOT NULL AND tdr.sk_tempo IS NULL)
    )
FROM dw.fato_locacao fl
LEFT JOIN dw.dim_cliente c ON c.sk_cliente = fl.sk_cliente
LEFT JOIN dw.dim_condutor cd ON cd.sk_condutor = fl.sk_condutor
LEFT JOIN dw.dim_veiculo v ON v.sk_veiculo = fl.sk_veiculo
LEFT JOIN dw.dim_patio pr ON pr.sk_patio = fl.sk_patio_retirada
LEFT JOIN dw.dim_patio pd ON pd.sk_patio = fl.sk_patio_devolucao
LEFT JOIN dw.dim_tempo trp ON trp.sk_tempo = fl.sk_tempo_retirada_prevista
LEFT JOIN dw.dim_tempo trr ON trr.sk_tempo = fl.sk_tempo_retirada_realizada
LEFT JOIN dw.dim_tempo tdp ON tdp.sk_tempo = fl.sk_tempo_devolucao_prevista
LEFT JOIN dw.dim_tempo tdr ON tdr.sk_tempo = fl.sk_tempo_devolucao_realizada
UNION ALL
SELECT
    'dw.fato_veiculo_no_patio',
    0,
    0,
    COUNT(*) FILTER (WHERE v.sk_veiculo IS NULL),
    COUNT(*) FILTER (WHERE po.sk_patio IS NULL OR pd.sk_patio IS NULL),
    COUNT(*) FILTER (WHERE tm.sk_tempo IS NULL)
FROM dw.fato_veiculo_no_patio fp
LEFT JOIN dw.dim_veiculo v ON v.sk_veiculo = fp.sk_veiculo
LEFT JOIN dw.dim_patio po ON po.sk_patio = fp.sk_patio_origem
LEFT JOIN dw.dim_patio pd ON pd.sk_patio = fp.sk_patio_destino
LEFT JOIN dw.dim_tempo tm ON tm.sk_tempo = fp.sk_tempo_movimentacao;

-- Medidas negativas ou nulas indevidas no DW.
SELECT
    'dw.fato_reserva' AS tabela,
    COUNT(*) FILTER (WHERE qtd_reservas <> 1 OR qtd_reservas IS NULL) AS qtd_invalida,
    COUNT(*) FILTER (WHERE dias_reservados <= 0) AS dias_invalidos,
    0 AS km_negativo,
    0 AS valor_negativo
FROM dw.fato_reserva
UNION ALL
SELECT
    'dw.fato_locacao',
    COUNT(*) FILTER (WHERE qtd_locacoes <> 1 OR qtd_locacoes IS NULL),
    COUNT(*) FILTER (WHERE dias_previstos < 0 OR dias_realizados < 0 OR atraso_devolucao_dias < 0),
    COUNT(*) FILTER (WHERE km_rodado < 0),
    COUNT(*) FILTER (WHERE valor_cobranca < 0 OR valor_multa_atraso < 0)
FROM dw.fato_locacao
UNION ALL
SELECT
    'dw.fato_veiculo_no_patio',
    COUNT(*) FILTER (WHERE qtd_movimentacoes <> 1 OR qtd_movimentacoes IS NULL),
    0,
    0,
    0
FROM dw.fato_veiculo_no_patio;
