-- =====================================================
-- 04_views_analiticas.sql
-- Views analiticas para relatorios finais
-- Grupo:
--   Tadeu Belfort Neto              DRE 119034813
--   Vicente Alves                   DRE 120044148
--   João Pedro de Lacerda           DRE 116076670
-- =====================================================

DROP VIEW IF EXISTS dw.vw_atrasos_devolucao;
DROP VIEW IF EXISTS dw.vw_clientes_mais_frequentes;
DROP VIEW IF EXISTS dw.vw_matriz_transicao_patios;
DROP VIEW IF EXISTS dw.vw_movimentacao_entre_patios;
DROP VIEW IF EXISTS dw.vw_ocupacao_por_grupo_veiculo;
DROP VIEW IF EXISTS dw.vw_locacoes_por_mes;
DROP VIEW IF EXISTS dw.vw_reservas_por_status;

-- =====================================================
-- Reservas por status
-- =====================================================
CREATE VIEW dw.vw_reservas_por_status AS
SELECT
    fr.status_reserva,
    SUM(fr.qtd_reservas) AS total_reservas,
    ROUND(
        100.0 * SUM(fr.qtd_reservas)
        / NULLIF(SUM(SUM(fr.qtd_reservas)) OVER (), 0),
        2
    ) AS percentual_status
FROM dw.fato_reserva fr
GROUP BY fr.status_reserva;

COMMENT ON VIEW dw.vw_reservas_por_status IS
'Total e percentual de reservas por status.';

-- =====================================================
-- Locacoes por mes
-- Usa data de retirada realizada quando existe; caso contrario,
-- usa retirada prevista.
-- =====================================================
CREATE VIEW dw.vw_locacoes_por_mes AS
SELECT
    dt.ano,
    dt.mes,
    dt.nome_mes,
    SUM(fl.qtd_locacoes) AS total_locacoes,
    ROUND(AVG(fl.km_rodado)::NUMERIC, 2) AS km_medio_rodado,
    SUM(COALESCE(fl.valor_cobranca, 0)) AS valor_total_cobrado
FROM dw.fato_locacao fl
LEFT JOIN dw.dim_tempo dt
       ON dt.sk_tempo = COALESCE(
            fl.sk_tempo_retirada_realizada,
            fl.sk_tempo_retirada_prevista
       )
GROUP BY
    dt.ano,
    dt.mes,
    dt.nome_mes;

COMMENT ON VIEW dw.vw_locacoes_por_mes IS
'Resumo mensal de locacoes, quilometragem media e valor total cobrado.';

-- =====================================================
-- Ocupacao por grupo de veiculo
-- =====================================================
CREATE VIEW dw.vw_ocupacao_por_grupo_veiculo AS
SELECT
    gv.nome AS grupo,
    gv.categoria,
    SUM(fl.qtd_locacoes) AS total_locacoes,
    SUM(COALESCE(fl.dias_realizados, 0)) AS dias_realizados,
    SUM(COALESCE(fl.km_rodado, 0)) AS km_total_rodado
FROM dw.fato_locacao fl
JOIN dw.dim_grupo_veiculo gv
  ON gv.sk_grupo_veiculo = fl.sk_grupo_veiculo
GROUP BY
    gv.nome,
    gv.categoria;

COMMENT ON VIEW dw.vw_ocupacao_por_grupo_veiculo IS
'Indicadores de locacao, dias realizados e km por grupo de veiculo.';

-- =====================================================
-- Movimentacao entre patios
-- =====================================================
CREATE VIEW dw.vw_movimentacao_entre_patios AS
SELECT
    po.nome AS patio_origem,
    pd.nome AS patio_destino,
    SUM(fp.qtd_movimentacoes) AS total_movimentacoes
FROM dw.fato_veiculo_no_patio fp
JOIN dw.dim_patio po
  ON po.sk_patio = fp.sk_patio_origem
JOIN dw.dim_patio pd
  ON pd.sk_patio = fp.sk_patio_destino
GROUP BY
    po.nome,
    pd.nome;

COMMENT ON VIEW dw.vw_movimentacao_entre_patios IS
'Total de movimentacoes por par de patios origem-destino.';

-- =====================================================
-- Matriz de transicao entre patios
-- =====================================================
CREATE VIEW dw.vw_matriz_transicao_patios AS
WITH movimentos AS (
    SELECT
        po.nome AS origem,
        pd.nome AS destino,
        SUM(fp.qtd_movimentacoes) AS total_movimentacoes
    FROM dw.fato_veiculo_no_patio fp
    JOIN dw.dim_patio po
      ON po.sk_patio = fp.sk_patio_origem
    JOIN dw.dim_patio pd
      ON pd.sk_patio = fp.sk_patio_destino
    GROUP BY
        po.nome,
        pd.nome
)
SELECT
    origem,
    destino,
    total_movimentacoes,
    ROUND(
        100.0 * total_movimentacoes
        / NULLIF(SUM(total_movimentacoes) OVER (PARTITION BY origem), 0),
        2
    ) AS percentual_transicao_origem
FROM movimentos;

COMMENT ON VIEW dw.vw_matriz_transicao_patios IS
'Matriz percentual de transicao a partir de cada patio de origem.';

-- =====================================================
-- Clientes mais frequentes
-- Agrega reservas e locacoes separadamente para evitar multiplicacao
-- de linhas ao juntar fatos com graos diferentes.
-- =====================================================
CREATE VIEW dw.vw_clientes_mais_frequentes AS
WITH reservas AS (
    SELECT
        sk_cliente,
        SUM(qtd_reservas) AS total_reservas
    FROM dw.fato_reserva
    GROUP BY sk_cliente
),
locacoes AS (
    SELECT
        sk_cliente,
        SUM(qtd_locacoes) AS total_locacoes,
        SUM(COALESCE(valor_cobranca, 0)) AS valor_total_cobrado
    FROM dw.fato_locacao
    GROUP BY sk_cliente
),
clientes AS (
    SELECT
        COALESCE(r.sk_cliente, l.sk_cliente) AS sk_cliente,
        COALESCE(r.total_reservas, 0) AS total_reservas,
        COALESCE(l.total_locacoes, 0) AS total_locacoes,
        COALESCE(l.valor_total_cobrado, 0) AS valor_total_cobrado
    FROM reservas r
    FULL JOIN locacoes l
      ON l.sk_cliente = r.sk_cliente
)
SELECT
    dc.nome AS cliente,
    dc.tipo,
    dc.cidade,
    c.total_reservas,
    c.total_locacoes,
    c.valor_total_cobrado
FROM clientes c
JOIN dw.dim_cliente dc
  ON dc.sk_cliente = c.sk_cliente;

COMMENT ON VIEW dw.vw_clientes_mais_frequentes IS
'Ranking analitico de clientes por reservas, locacoes e valor cobrado.';

-- =====================================================
-- Atrasos de devolucao
-- =====================================================
CREATE VIEW dw.vw_atrasos_devolucao AS
SELECT
    fl.locacao_id,
    dc.nome AS cliente,
    CONCAT(dv.placa, ' - ', dv.marca, ' ', dv.modelo) AS veiculo,
    dp.nome AS patio_devolucao,
    t_prev.data AS data_prevista,
    t_real.data AS data_realizada,
    fl.atraso_devolucao_dias AS atraso_em_dias
FROM dw.fato_locacao fl
JOIN dw.dim_cliente dc
  ON dc.sk_cliente = fl.sk_cliente
JOIN dw.dim_veiculo dv
  ON dv.sk_veiculo = fl.sk_veiculo
LEFT JOIN dw.dim_patio dp
  ON dp.sk_patio = fl.sk_patio_devolucao
LEFT JOIN dw.dim_tempo t_prev
  ON t_prev.sk_tempo = fl.sk_tempo_devolucao_prevista
LEFT JOIN dw.dim_tempo t_real
  ON t_real.sk_tempo = fl.sk_tempo_devolucao_realizada
WHERE fl.atraso_devolucao_dias > 0;

COMMENT ON VIEW dw.vw_atrasos_devolucao IS
'Locacoes com devolucao realizada apos a data prevista.';

-- =====================================================
-- Validacao simples das views
-- Cada SELECT deve executar sem erro.
-- =====================================================
SELECT 'dw.vw_reservas_por_status' AS view_name, COUNT(*) AS qtd_linhas
FROM dw.vw_reservas_por_status
UNION ALL
SELECT 'dw.vw_locacoes_por_mes', COUNT(*)
FROM dw.vw_locacoes_por_mes
UNION ALL
SELECT 'dw.vw_ocupacao_por_grupo_veiculo', COUNT(*)
FROM dw.vw_ocupacao_por_grupo_veiculo
UNION ALL
SELECT 'dw.vw_movimentacao_entre_patios', COUNT(*)
FROM dw.vw_movimentacao_entre_patios
UNION ALL
SELECT 'dw.vw_matriz_transicao_patios', COUNT(*)
FROM dw.vw_matriz_transicao_patios
UNION ALL
SELECT 'dw.vw_clientes_mais_frequentes', COUNT(*)
FROM dw.vw_clientes_mais_frequentes
UNION ALL
SELECT 'dw.vw_atrasos_devolucao', COUNT(*)
FROM dw.vw_atrasos_devolucao;

-- =====================================================
-- VALIDACOES DE CONSISTENCIA ENTRE CAMADAS - VIEWS
--
-- Complementa a secao VALIDACOES DE CONSISTENCIA ENTRE CAMADAS
-- do script 03_load_fatos.sql. Estas consultas ficam aqui porque
-- dependem das views criadas neste script.
--
-- Objetivo: verificar se as views analiticas batem com as tabelas fato.
-- =====================================================

SELECT
    'vw_reservas_por_status' AS validacao,
    (SELECT COALESCE(SUM(total_reservas), 0) FROM dw.vw_reservas_por_status) AS total_view,
    (SELECT COALESCE(SUM(qtd_reservas), 0) FROM dw.fato_reserva) AS total_fato
UNION ALL
SELECT
    'vw_locacoes_por_mes',
    (SELECT COALESCE(SUM(total_locacoes), 0) FROM dw.vw_locacoes_por_mes),
    (SELECT COALESCE(SUM(qtd_locacoes), 0) FROM dw.fato_locacao)
UNION ALL
SELECT
    'vw_ocupacao_por_grupo_veiculo',
    (SELECT COALESCE(SUM(total_locacoes), 0) FROM dw.vw_ocupacao_por_grupo_veiculo),
    (SELECT COALESCE(SUM(qtd_locacoes), 0) FROM dw.fato_locacao)
UNION ALL
SELECT
    'vw_movimentacao_entre_patios',
    (SELECT COALESCE(SUM(total_movimentacoes), 0) FROM dw.vw_movimentacao_entre_patios),
    (SELECT COALESCE(SUM(qtd_movimentacoes), 0) FROM dw.fato_veiculo_no_patio)
UNION ALL
SELECT
    'vw_matriz_transicao_patios',
    (SELECT COALESCE(SUM(total_movimentacoes), 0) FROM dw.vw_matriz_transicao_patios),
    (SELECT COALESCE(SUM(qtd_movimentacoes), 0) FROM dw.fato_veiculo_no_patio)
UNION ALL
SELECT
    'vw_clientes_mais_frequentes_reservas',
    (SELECT COALESCE(SUM(total_reservas), 0) FROM dw.vw_clientes_mais_frequentes),
    (SELECT COALESCE(SUM(qtd_reservas), 0) FROM dw.fato_reserva)
UNION ALL
SELECT
    'vw_clientes_mais_frequentes_locacoes',
    (SELECT COALESCE(SUM(total_locacoes), 0) FROM dw.vw_clientes_mais_frequentes),
    (SELECT COALESCE(SUM(qtd_locacoes), 0) FROM dw.fato_locacao)
UNION ALL
SELECT
    'vw_atrasos_devolucao',
    (SELECT COUNT(*) FROM dw.vw_atrasos_devolucao),
    (SELECT COUNT(*) FROM dw.fato_locacao WHERE atraso_devolucao_dias > 0);
