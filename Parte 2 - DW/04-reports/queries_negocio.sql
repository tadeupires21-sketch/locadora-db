-- =====================================================
-- Grupo:
--   Tadeu Belfort Neto              DRE 119034813
--   Vicente Alves                   DRE 120044148
--   João Pedro de Lacerda           DRE 116076670
-- Arquivo: queries_negocio.sql
-- Descrição: Consultas analíticas prontas para relatórios
--            de negócio do DW da locadora de veículos.
--
-- Pré-requisito: views em 03-dw/04_views_analiticas.sql
--                já criadas no banco.
-- =====================================================

-- =====================================================
-- R1. RECEITA MENSAL — evolução de faturamento
--     Responde: "Como está nossa receita mês a mês?"
-- =====================================================
-- Colunas reais da view: total_locacoes, km_medio_rodado, valor_total_cobrado.
-- A receita mensal vem de valor_total_cobrado; km_medio_rodado já é a média
-- de km por locação calculada na view (não há km_total a dividir aqui).
SELECT
    ano,
    mes,
    nome_mes,
    total_locacoes,
    ROUND(valor_total_cobrado, 2)                   AS receita_total,
    ROUND(AVG(valor_total_cobrado) OVER (
        ORDER BY ano, mes
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 2)                                           AS media_movel_3m,
    ROUND(valor_total_cobrado - LAG(valor_total_cobrado) OVER (
        ORDER BY ano, mes
    ), 2)                                           AS variacao_mes_anterior,
    ROUND(km_medio_rodado, 1)                       AS km_medio_por_locacao
FROM dw.vw_locacoes_por_mes
ORDER BY ano, mes;


-- =====================================================
-- R2. TOP 10 CLIENTES — por receita gerada
--     Responde: "Quem são nossos clientes mais valiosos?"
-- =====================================================
-- Colunas reais da view: cliente, tipo, cidade, total_reservas,
-- total_locacoes, valor_total_cobrado.
SELECT
    cliente                                          AS nome_cliente,
    total_reservas,
    total_locacoes,
    ROUND(valor_total_cobrado, 2)                    AS receita_total,
    ROUND(valor_total_cobrado / NULLIF(total_locacoes, 0), 2) AS ticket_medio
FROM dw.vw_clientes_mais_frequentes
WHERE total_locacoes > 0
ORDER BY receita_total DESC
LIMIT 10;


-- =====================================================
-- R3. TAXA DE CANCELAMENTO POR GRUPO DE VEÍCULO
--     Responde: "Qual categoria tem mais cancelamentos?"
-- =====================================================
SELECT
    g.nome                                                      AS grupo_veiculo,
    COUNT(*)                                                    AS total_reservas,
    COUNT(*) FILTER (WHERE r.flag_cancelada = TRUE)             AS canceladas,
    ROUND(
        COUNT(*) FILTER (WHERE r.flag_cancelada = TRUE)::NUMERIC
        / NULLIF(COUNT(*), 0) * 100,
        1
    )                                                           AS pct_cancelamento
FROM dw.fato_reserva r
JOIN dw.dim_grupo_veiculo g ON g.sk_grupo_veiculo = r.sk_grupo_veiculo
GROUP BY g.nome
HAVING COUNT(*) >= 5   -- ignora grupos com amostra insuficiente
ORDER BY pct_cancelamento DESC;


-- =====================================================
-- R4. USO DOS PÁTIOS — movimento de retiradas e devoluções
--     Responde: "Quais pátios concentram mais operação?"
--
-- NOTA DE MODELAGEM: dim_patio NÃO carrega 'capacidade' (a coluna existe
-- em stg.patio, mas não foi promovida ao DW), e não há vínculo estático
-- veículo→pátio no modelo. Portanto não é possível calcular % de ocupação
-- sobre capacidade. Medimos USO REAL a partir de fato_locacao: quantas
-- locações usaram cada pátio como ponto de retirada e de devolução.
-- (Para % de ocupação real, promover 'capacidade' a dim_patio.)
-- =====================================================
SELECT
    p.nome                                          AS patio,
    p.cidade,
    COUNT(*) FILTER (WHERE fl.sk_patio_retirada  = p.sk_patio) AS retiradas,
    COUNT(*) FILTER (WHERE fl.sk_patio_devolucao = p.sk_patio) AS devolucoes,
    COUNT(*) FILTER (WHERE fl.sk_patio_retirada  = p.sk_patio)
    + COUNT(*) FILTER (WHERE fl.sk_patio_devolucao = p.sk_patio) AS movimento_total
FROM dw.dim_patio p
LEFT JOIN dw.fato_locacao fl
       ON p.sk_patio IN (fl.sk_patio_retirada, fl.sk_patio_devolucao)
GROUP BY p.sk_patio, p.nome, p.cidade
ORDER BY movimento_total DESC;


-- =====================================================
-- R5. ATRASOS NA DEVOLUÇÃO — perfil dos infratores
--     Responde: "Quem atrasa mais e quanto custa?"
-- =====================================================
-- Colunas reais da view: locacao_id, cliente, veiculo (placa+marca+modelo),
-- patio_devolucao, data_prevista, data_realizada, atraso_em_dias.
-- A view não expõe valor cobrado; ordenamos apenas pelo atraso.
SELECT
    cliente                 AS nome_cliente,
    veiculo,
    patio_devolucao,
    data_prevista,
    data_realizada,
    atraso_em_dias
FROM dw.vw_atrasos_devolucao
ORDER BY atraso_em_dias DESC
LIMIT 20;


-- =====================================================
-- R6. MOVIMENTAÇÃO ENTRE PÁTIOS — matriz de fluxo
--     Responde: "Qual o fluxo de veículos entre pátios?"
-- =====================================================
-- Coluna real da view: percentual_transicao_origem (% das saídas de cada
-- pátio de origem que vão para cada destino — soma 100% por origem).
SELECT
    origem,
    destino,
    total_movimentacoes,
    ROUND(percentual_transicao_origem, 1)  AS pct_do_total_de_saidas
FROM dw.vw_matriz_transicao_patios
ORDER BY total_movimentacoes DESC;


-- =====================================================
-- R7. VEÍCULOS SEM LOCAÇÃO — ativos mas ociosos
--     Responde: "Quais veículos nunca foram alugados?"
-- =====================================================
SELECT
    v.placa,
    v.marca,
    v.modelo,
    v.status,
    g.nome      AS grupo_veiculo,
    e.nome      AS empresa
FROM dw.dim_veiculo v
JOIN dw.dim_grupo_veiculo g ON g.sk_grupo_veiculo = v.sk_grupo_veiculo
JOIN dw.dim_empresa       e ON e.sk_empresa        = v.sk_empresa
WHERE v.sk_veiculo NOT IN (
    SELECT DISTINCT sk_veiculo FROM dw.fato_locacao WHERE sk_veiculo IS NOT NULL
)
ORDER BY e.nome, v.placa;


-- =====================================================
-- R8. SAZONALIDADE — reservas por dia da semana
--     Responde: "Em quais dias da semana há mais demanda?"
-- =====================================================
SELECT
    t.nome_dia_semana,
    t.dia_semana,
    COUNT(*)            AS total_reservas,
    SUM(r.qtd_reservas) AS qtd_total
FROM dw.fato_reserva r
JOIN dw.dim_tempo t ON t.sk_tempo = r.sk_tempo_inicio
GROUP BY t.nome_dia_semana, t.dia_semana
ORDER BY t.dia_semana;
