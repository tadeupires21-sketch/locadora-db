-- =====================================================
-- Transformacao - fatos conformadas
-- Projeto academico de Data Warehouse para locadora
-- Grupo:
--   Tadeu Belfort Neto              DRE 119034813
--   Vicente Alves                   DRE 120044148
--   João Pedro de Lacerda           DRE 116076670
-- Este script depende das dimensoes geradas em:
-- transform/01_transform_dimensoes.sql
--
-- Timezone: fixado para que os casts ::DATE sejam determinísticos
-- (ver nota completa em 01_transform_dimensoes.sql).
-- =====================================================

SET timezone TO 'America/Sao_Paulo';

-- =====================================================
-- PRÉ-VALIDAÇÃO: alertas de qualidade no staging bruto
-- Emite WARNING (não bloqueia) para que o operador possa
-- inspecionar os dados antes da carga no DW.
-- =====================================================
DO $$
DECLARE
    qtd INTEGER;
BEGIN
    -- Locações com km_devolucao < km_entrega (odômetro invertido)
    SELECT COUNT(*) INTO qtd
    FROM stg.locacao
    WHERE km_entrega IS NOT NULL
      AND km_devolucao IS NOT NULL
      AND km_devolucao < km_entrega;

    IF qtd > 0 THEN
        RAISE WARNING
            'QUALIDADE: % locação(ões) com km_devolucao < km_entrega. '
            'Serão carregadas com km_rodado = 0 (protegido por GREATEST). '
            'Inspecionar: SELECT * FROM stg.locacao WHERE km_devolucao < km_entrega;',
            qtd;
    END IF;

    -- Datas de devolução anterior à retirada
    SELECT COUNT(*) INTO qtd
    FROM stg.locacao
    WHERE data_devolucao_realizada IS NOT NULL
      AND data_retirada_realizada IS NOT NULL
      AND data_devolucao_realizada < data_retirada_realizada;

    IF qtd > 0 THEN
        RAISE WARNING
            'QUALIDADE: % locação(ões) com data_devolucao < data_retirada. '
            'Inspecionar: SELECT * FROM stg.locacao WHERE data_devolucao_realizada < data_retirada_realizada;',
            qtd;
    END IF;

    -- Reservas sem pátio de retirada (obrigatório para o fato)
    SELECT COUNT(*) INTO qtd
    FROM stg.reserva
    WHERE src_patio_retirada_id IS NULL;

    IF qtd > 0 THEN
        RAISE WARNING
            'QUALIDADE: % reserva(s) sem pátio de retirada (src_patio_retirada_id IS NULL). '
            'sk_patio_retirada ficará NULL no fato.',
            qtd;
    END IF;
END $$;

-- (schema stg já criado em 00-infra/00_create_schemas.sql e
--  01_transform_dimensoes.sql; não recriar aqui.)

-- =====================================================
-- conf_reserva
-- Chaves naturais preservadas para rastreabilidade:
-- reserva_nk, cliente_nk, grupo_veiculo_nk, patio_*_nk.
-- As SKs sao mantidas para compatibilidade com os scripts de carga DW.
-- =====================================================
DROP TABLE IF EXISTS stg.conf_reserva CASCADE;

CREATE TABLE stg.conf_reserva AS
WITH base AS (
    SELECT
        r.*,
        ROW_NUMBER() OVER (
            PARTITION BY r.grupo_fonte, r.src_id
            ORDER BY r.dt_extracao DESC
        ) AS rn
    FROM stg.reserva r
),
normalizado AS (
    SELECT
        (grupo_fonte::TEXT || '-' || src_id::TEXT) AS reserva_nk,
        (grupo_fonte::TEXT || '-' || src_cliente_id::TEXT) AS cliente_nk,
        CASE
            WHEN src_grupo_id IS NOT NULL THEN (grupo_fonte::TEXT || '-' || src_grupo_id::TEXT)
        END AS grupo_veiculo_nk,
        CASE
            WHEN src_patio_retirada_id IS NOT NULL THEN (grupo_fonte::TEXT || '-' || src_patio_retirada_id::TEXT)
        END AS patio_retirada_nk,
        CASE
            WHEN src_patio_devolucao_id IS NOT NULL THEN (grupo_fonte::TEXT || '-' || src_patio_devolucao_id::TEXT)
        END AS patio_devolucao_nk,
        src_id,
        grupo_fonte,
        src_cliente_id,
        src_grupo_id,
        src_patio_retirada_id,
        src_patio_devolucao_id,
        COALESCE(data_reserva, data_solicitacao, dt_extracao)::DATE AS data_reserva,
        data_inicio::DATE AS data_inicio,
        data_fim::DATE AS data_fim,
        stg.fn_normaliza_status_reserva(status) AS status,
        preco_previsto::NUMERIC(10,2) AS preco_previsto,
        preco_final::NUMERIC(10,2) AS preco_final,
        dt_extracao
    FROM base
    WHERE rn = 1
)
SELECT
    ROW_NUMBER() OVER (ORDER BY n.grupo_fonte, n.src_id)::INTEGER AS sk_reserva,
    n.reserva_nk,
    n.cliente_nk,
    n.grupo_veiculo_nk,
    n.patio_retirada_nk,
    n.patio_devolucao_nk,
    n.src_id,
    n.grupo_fonte,
    n.src_cliente_id,
    n.src_grupo_id,
    n.src_patio_retirada_id,
    n.src_patio_devolucao_id,
    c.sk_cliente,
    g.sk_grupo,
    pr.sk_patio AS sk_patio_retirada,
    pd.sk_patio AS sk_patio_devolucao,
    n.data_reserva,
    n.data_inicio,
    n.data_fim,
    TO_CHAR(n.data_reserva, 'YYYYMMDD')::INTEGER AS id_data_reserva,
    TO_CHAR(n.data_inicio, 'YYYYMMDD')::INTEGER AS id_data_inicio,
    CASE WHEN n.data_fim IS NOT NULL THEN TO_CHAR(n.data_fim, 'YYYYMMDD')::INTEGER END AS id_data_fim,
    CASE
        WHEN n.data_reserva IS NOT NULL AND n.data_inicio IS NOT NULL
            THEN n.data_inicio - n.data_reserva
        ELSE 0
    END AS antecedencia_dias,
    CASE
        WHEN n.data_inicio IS NOT NULL AND n.data_fim IS NOT NULL
            THEN n.data_fim - n.data_inicio
    END AS duracao_prevista_dias,
    n.status,
    n.preco_previsto,
    n.preco_final,
    n.dt_extracao
FROM normalizado n
LEFT JOIN stg.conf_cliente c
       ON c.cliente_nk = n.cliente_nk
LEFT JOIN stg.conf_grupo_veiculo g
       ON g.grupo_veiculo_nk = n.grupo_veiculo_nk
LEFT JOIN stg.conf_patio pr
       ON pr.patio_nk = n.patio_retirada_nk
LEFT JOIN stg.conf_patio pd
       ON pd.patio_nk = n.patio_devolucao_nk;

-- =====================================================
-- conf_locacao
-- Chaves naturais compostas preservam a origem da locacao
-- e das dimensoes relacionadas.
-- =====================================================
DROP TABLE IF EXISTS stg.conf_locacao CASCADE;

CREATE TABLE stg.conf_locacao AS
WITH base AS (
    SELECT
        l.*,
        ROW_NUMBER() OVER (
            PARTITION BY l.grupo_fonte, l.src_id
            ORDER BY l.dt_extracao DESC
        ) AS rn
    FROM stg.locacao l
),
normalizado AS (
    SELECT
        (grupo_fonte::TEXT || '-' || src_id::TEXT) AS locacao_nk,
        CASE
            WHEN src_reserva_id IS NOT NULL THEN (grupo_fonte::TEXT || '-' || src_reserva_id::TEXT)
        END AS reserva_nk,
        CASE
            WHEN src_veiculo_id IS NOT NULL THEN (grupo_fonte::TEXT || '-' || src_veiculo_id::TEXT)
        END AS veiculo_nk,
        CASE
            WHEN src_condutor_id IS NOT NULL THEN (grupo_fonte::TEXT || '-' || src_condutor_id::TEXT)
        END AS condutor_nk,
        CASE
            WHEN src_cliente_id IS NOT NULL THEN (grupo_fonte::TEXT || '-' || src_cliente_id::TEXT)
        END AS cliente_nk,
        CASE
            WHEN src_patio_retirada_id IS NOT NULL THEN (grupo_fonte::TEXT || '-' || src_patio_retirada_id::TEXT)
        END AS patio_retirada_nk,
        CASE
            WHEN src_patio_devolucao_id IS NOT NULL THEN (grupo_fonte::TEXT || '-' || src_patio_devolucao_id::TEXT)
        END AS patio_devolucao_nk,
        src_id,
        grupo_fonte,
        src_devolucao_id,
        src_reserva_id,
        src_veiculo_id,
        src_condutor_id,
        src_cliente_id,
        src_patio_retirada_id,
        src_patio_devolucao_id,
        COALESCE(created_at, data_retirada_realizada, data_retirada_prevista, dt_extracao)::DATE AS data_registro,
        data_retirada_prevista::DATE AS data_retirada_prevista,
        data_retirada_realizada::DATE AS data_retirada,
        data_devolucao_prevista::DATE AS data_devolucao_prevista,
        data_devolucao_realizada::DATE AS data_devolucao,
        km_entrega,
        km_devolucao,
        gasolina_entrega,
        gasolina_devolucao,
        valor_atraso::NUMERIC(10,2) AS valor_atraso,
        valor_reparos::NUMERIC(10,2) AS valor_reparos,
        -- COALESCE com NULLIF: trata 0 como ausente, priorizando o valor
        -- mais completo disponível (cobrança > total geral > valor calculado).
        -- Sem NULLIF, preco_final = 0 ocultaria valor_total correto.
        COALESCE(
            NULLIF(preco_final,   0),
            NULLIF(valor_total,   0),
            NULLIF(valor_final,   0),
            NULLIF(valor_atraso + COALESCE(valor_reparos, 0), 0),
            0
        )::NUMERIC(10,2) AS valor_cobrado,
        CASE
            WHEN LOWER(COALESCE(status, '')) LIKE '%cancel%' THEN 'cancelada'
            WHEN data_devolucao_realizada IS NULL AND data_retirada_realizada IS NOT NULL THEN 'aberta'
            WHEN data_devolucao_realizada IS NOT NULL THEN 'finalizada'
            ELSE COALESCE(NULLIF(LOWER(TRIM(status)), ''), 'registrada')
        END AS status,
        estado_entrega,
        estado_devolucao,
        dt_extracao
    FROM base
    WHERE rn = 1
)
SELECT
    ROW_NUMBER() OVER (ORDER BY n.grupo_fonte, n.src_id)::INTEGER AS sk_locacao,
    n.locacao_nk,
    n.reserva_nk,
    n.veiculo_nk,
    n.condutor_nk,
    n.cliente_nk,
    n.patio_retirada_nk,
    n.patio_devolucao_nk,
    n.src_id,
    n.grupo_fonte,
    n.src_devolucao_id,
    n.src_reserva_id,
    n.src_veiculo_id,
    n.src_condutor_id,
    n.src_cliente_id,
    n.src_patio_retirada_id,
    n.src_patio_devolucao_id,
    c.sk_cliente,
    cd.sk_condutor,
    v.sk_veiculo,
    pr.sk_patio AS sk_patio_retirada,
    pd.sk_patio AS sk_patio_devolucao,
    r.sk_reserva,
    n.data_registro,
    n.data_retirada_prevista,
    n.data_retirada,
    n.data_devolucao_prevista,
    n.data_devolucao,
    n.km_entrega,
    n.km_devolucao,
    TO_CHAR(n.data_registro, 'YYYYMMDD')::INTEGER AS id_data_registro,
    CASE WHEN n.data_retirada IS NOT NULL THEN TO_CHAR(n.data_retirada, 'YYYYMMDD')::INTEGER END AS id_data_retirada,
    CASE WHEN n.data_devolucao IS NOT NULL THEN TO_CHAR(n.data_devolucao, 'YYYYMMDD')::INTEGER END AS id_data_devolucao,
    -- =================================================================
    -- MEDIDAS CANÔNICAS (fonte única da verdade)
    -- O DW (03_load_fatos.sql) DEVE consumir estas colunas em vez de
    -- recalcular a partir das datas/km crus. Convenção de dias: INCLUSIVA
    -- (retirada e devolução no mesmo dia = 1 dia), por isso o "+ 1".
    -- Todas protegidas com GREATEST(..., 0) para nunca ficarem negativas.
    -- =================================================================
    stg.fn_dias_inclusivo(n.data_retirada_prevista, n.data_devolucao_prevista) AS dias_previstos,
    stg.fn_dias_inclusivo(n.data_retirada, n.data_devolucao) AS dias_realizados,
    -- Dias de atraso: só conta atraso real (devolução antecipada vira 0).
    stg.fn_dias_atraso(n.data_devolucao, n.data_devolucao_prevista) AS atraso_devolucao_dias,
    -- Locações ainda abertas: dias restantes até a devolução prevista.
    CASE
        WHEN n.data_devolucao IS NULL AND n.data_devolucao_prevista IS NOT NULL
            THEN n.data_devolucao_prevista - CURRENT_DATE
    END AS dias_para_devolucao,
    stg.fn_km_rodado(n.km_entrega, n.km_devolucao) AS km_rodado,
    n.gasolina_entrega,
    n.gasolina_devolucao,
    n.valor_atraso,
    n.valor_reparos,
    n.valor_cobrado,
    -- =================================================================
    -- MULTA POR ATRASO (regra de negócio)
    -- Prioriza o valor de atraso já cobrado na origem (G1/G2). Quando a
    -- fonte não tem esse valor (G3/G4), estima a multa como:
    --   dias_de_atraso × diária do grupo do veículo.
    -- Assim a medida fica comparável entre os 4 grupos.
    -- =================================================================
    stg.fn_multa_atraso(n.valor_atraso, n.data_devolucao, n.data_devolucao_prevista, g.diaria) AS valor_multa_atraso,
    (n.src_reserva_id IS NOT NULL) AS reserva_previa,
    n.status,
    n.estado_entrega,
    n.estado_devolucao,
    n.dt_extracao
FROM normalizado n
LEFT JOIN stg.conf_cliente c
       ON c.cliente_nk = n.cliente_nk
LEFT JOIN stg.conf_condutor cd
       ON cd.condutor_nk = n.condutor_nk
LEFT JOIN stg.conf_veiculo v
       ON v.veiculo_nk = n.veiculo_nk
-- grupo do veículo: necessário para estimar a multa via diária
LEFT JOIN stg.conf_grupo_veiculo g
       ON g.grupo_veiculo_nk = v.grupo_veiculo_nk
LEFT JOIN stg.conf_patio pr
       ON pr.patio_nk = n.patio_retirada_nk
LEFT JOIN stg.conf_patio pd
       ON pd.patio_nk = n.patio_devolucao_nk
LEFT JOIN stg.conf_reserva r
       ON r.reserva_nk = n.reserva_nk;

-- =====================================================
-- conf_cobranca
-- Grao: uma linha por LOCACAO (locacao_nk), nao por cobranca.
-- O G1 pode ter varias cobrancas por locacao; G2/G3/G4 tem 1:1
-- (derivada do valor da locacao na extracao). Aqui consolidamos:
--   valor_cobranca  = soma de todas as cobrancas da locacao
--   status_cobranca = status consolidado (regra de prioridade abaixo)
-- Alimenta dw.fato_locacao.valor_cobranca e status_cobranca.
-- =====================================================
DROP TABLE IF EXISTS stg.conf_cobranca CASCADE;

CREATE TABLE stg.conf_cobranca AS
WITH base AS (
    SELECT
        (grupo_fonte::TEXT || '-' || src_locacao_id::TEXT) AS locacao_nk,
        grupo_fonte,
        src_locacao_id,
        valor,
        -- Normaliza o status cru das diferentes fontes para um vocabulario unico.
        stg.fn_normaliza_status_cobranca(status) AS status_norm,
        data_pagamento,
        dt_extracao
    FROM stg.cobranca
    WHERE src_locacao_id IS NOT NULL
)
SELECT
    locacao_nk,
    grupo_fonte,
    COUNT(*) AS qtd_cobrancas,
    SUM(COALESCE(valor, 0))::NUMERIC(12,2) AS valor_cobranca,
    -- Prioridade: qualquer pendencia/atraso domina; so e 'pago' se TODAS
    -- as cobrancas estiverem pagas; cancelamento total vira 'cancelada';
    -- combinacoes restantes (ex.: parte paga, parte cancelada) viram 'parcial'.
    CASE
        WHEN COUNT(*) FILTER (WHERE status_norm = 'pendente')  > 0 THEN 'pendente'
        WHEN COUNT(*) FILTER (WHERE status_norm = 'em_atraso') > 0 THEN 'em_atraso'
        WHEN COUNT(*) FILTER (WHERE status_norm = 'pago')      = COUNT(*) THEN 'pago'
        WHEN COUNT(*) FILTER (WHERE status_norm = 'cancelada') = COUNT(*) THEN 'cancelada'
        ELSE 'parcial'
    END AS status_cobranca,
    MAX(data_pagamento) AS data_ultimo_pagamento,
    MAX(dt_extracao) AS dt_extracao
FROM base
GROUP BY locacao_nk, grupo_fonte;

-- =====================================================
-- conf_veiculo_no_patio
-- Snapshot operacional do patio atual inferido pela ultima locacao.
-- Quando a locacao esta aberta, o veiculo fica marcado como alugado.
-- =====================================================
DROP TABLE IF EXISTS stg.conf_veiculo_no_patio CASCADE;

CREATE TABLE stg.conf_veiculo_no_patio AS
WITH ultima_locacao AS (
    SELECT
        l.*,
        ROW_NUMBER() OVER (
            PARTITION BY l.veiculo_nk
            ORDER BY COALESCE(l.data_devolucao, l.data_retirada, l.data_registro) DESC, l.sk_locacao DESC
        ) AS rn
    FROM stg.conf_locacao l
    WHERE l.veiculo_nk IS NOT NULL
)
SELECT
    ((CURRENT_DATE)::TEXT || '-' || v.veiculo_nk) AS veiculo_no_patio_nk,
    v.veiculo_nk,
    COALESCE(ul.patio_devolucao_nk, ul.patio_retirada_nk) AS patio_atual_nk,
    ul.patio_retirada_nk AS patio_origem_nk,
    v.sk_veiculo,
    p_atual.sk_patio AS sk_patio_atual,
    p_origem.sk_patio AS sk_patio_origem,
    CURRENT_DATE AS data_snapshot,
    TO_CHAR(CURRENT_DATE, 'YYYYMMDD')::INTEGER AS id_data_snapshot,
    CASE
        WHEN ul.sk_locacao IS NOT NULL AND ul.data_devolucao IS NULL THEN 'alugado'
        ELSE v.status
    END AS status_veiculo,
    CASE
        WHEN p_atual.nome_empresa IS NOT NULL AND v.nome_empresa IS NOT NULL
            THEN LOWER(p_atual.nome_empresa) = LOWER(v.nome_empresa)
        ELSE NULL
    END AS patio_original,
    v.grupo_fonte,
    v.dt_extracao
FROM stg.conf_veiculo v
LEFT JOIN ultima_locacao ul
       ON ul.veiculo_nk = v.veiculo_nk
      AND ul.rn = 1
LEFT JOIN stg.conf_patio p_atual
       ON p_atual.patio_nk = COALESCE(ul.patio_devolucao_nk, ul.patio_retirada_nk)
LEFT JOIN stg.conf_patio p_origem
       ON p_origem.patio_nk = ul.patio_retirada_nk;

-- =====================================================
-- conf_movimentacao_patio
-- Fato opcional para movimentacoes entre patios.
-- =====================================================
DROP TABLE IF EXISTS stg.conf_movimentacao_patio CASCADE;

CREATE TABLE stg.conf_movimentacao_patio AS
WITH base AS (
    SELECT
        m.*,
        ROW_NUMBER() OVER (
            PARTITION BY m.grupo_fonte, m.src_id
            ORDER BY m.dt_extracao DESC
        ) AS rn
    FROM stg.movimentacao_patio m
),
normalizado AS (
    SELECT
        (grupo_fonte::TEXT || '-' || src_id::TEXT) AS movimentacao_patio_nk,
        CASE
            WHEN src_veiculo_id IS NOT NULL THEN (grupo_fonte::TEXT || '-' || src_veiculo_id::TEXT)
        END AS veiculo_nk,
        CASE
            WHEN src_origem_id IS NOT NULL THEN (grupo_fonte::TEXT || '-' || src_origem_id::TEXT)
        END AS patio_origem_nk,
        CASE
            WHEN src_destino_id IS NOT NULL THEN (grupo_fonte::TEXT || '-' || src_destino_id::TEXT)
        END AS patio_destino_nk,
        src_id,
        grupo_fonte,
        src_veiculo_id,
        src_origem_id,
        src_destino_id,
        data_movimentacao::DATE AS data_movimentacao,
        NULLIF(TRIM(motivo), '') AS motivo,
        dt_extracao
    FROM base
    WHERE rn = 1
)
SELECT
    ROW_NUMBER() OVER (ORDER BY n.grupo_fonte, n.src_id)::INTEGER AS sk_movimentacao_patio,
    n.movimentacao_patio_nk,
    n.veiculo_nk,
    n.patio_origem_nk,
    n.patio_destino_nk,
    n.src_id,
    n.grupo_fonte,
    n.src_veiculo_id,
    n.src_origem_id,
    n.src_destino_id,
    v.sk_veiculo,
    po.sk_patio AS sk_patio_origem,
    pd.sk_patio AS sk_patio_destino,
    n.data_movimentacao,
    CASE WHEN n.data_movimentacao IS NOT NULL THEN TO_CHAR(n.data_movimentacao, 'YYYYMMDD')::INTEGER END AS id_data_movimentacao,
    n.motivo,
    n.dt_extracao
FROM normalizado n
LEFT JOIN stg.conf_veiculo v
       ON v.veiculo_nk = n.veiculo_nk
LEFT JOIN stg.conf_patio po
       ON po.patio_nk = n.patio_origem_nk
LEFT JOIN stg.conf_patio pd
       ON pd.patio_nk = n.patio_destino_nk;