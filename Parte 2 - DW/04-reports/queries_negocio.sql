-- =====================================================
-- Nome: Tadeu Belfort Neto
-- DRE: 119034813
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
SELECT
    ano,
    mes,
    nome_mes,
    total_locacoes,
    ROUND(receita_total, 2)                         AS receita_total,
    ROUND(AVG(receita_total) OVER (
        ORDER BY ano, mes
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 2)                                           AS media_movel_3m,
    ROUND(receita_total - LAG(receita_total) OVER (
        ORDER BY ano, mes
    ), 2)                                           AS variacao_mes_anterior,
    ROUND(km_total_rodado / NULLIF(total_locacoes, 0), 1) AS km_medio_por_locacao
FROM dw.vw_locacoes_por_mes
ORDER BY ano, mes;


-- =====================================================
-- R2. TOP 10 CLIENTES — por receita gerada
--     Responde: "Quem são nossos clientes mais valiosos?"
-- =====================================================
SELECT
    nome_cliente,
    total_reservas,
    total_locacoes,
    ROUND(valor_cobrado_total, 2) AS receita_total,
    ROUND(valor_cobrado_total / NULLIF(total_locacoes, 0), 2) AS ticket_medio
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
-- R4. OCUPAÇÃO DOS PÁTIOS — disponibilidade x uso
--     Responde: "Quais pátios estão mais/menos ocupados?"
-- =====================================================
SELECT
    p.nome                                          AS patio,
    p.cidade,
    p.capacidade_total,
    COUNT(DISTINCT v.sk_veiculo)                    AS veiculos_cadastrados,
    ROUND(
        COUNT(DISTINCT v.sk_veiculo)::NUMERIC
        / NULLIF(p.capacidade_total, 0) * 100,
        1
    )                                               AS pct_ocupacao_cadastrada
FROM dw.dim_patio p
LEFT JOIN dw.dim_veiculo v ON v.sk_empresa = (
    SELECT sk_empresa FROM dw.dim_empresa e
    WHERE e.empresa_id = (
        SELECT empresa_id FROM dw.dim_empresa WHERE sk_empresa = v.sk_empresa LIMIT 1
    ) LIMIT 1
)
GROUP BY p.sk_patio, p.nome, p.cidade, p.capacidade_total
ORDER BY pct_ocupacao_cadastrada DESC NULLS LAST;


-- =====================================================
-- R5. ATRASOS NA DEVOLUÇÃO — perfil dos infratores
--     Responde: "Quem atrasa mais e quanto custa?"
-- =====================================================
SELECT
    nome_cliente,
    placa_veiculo,
    nome_patio_devolucao,
    data_devolucao_prevista,
    data_devolucao_realizada,
    atraso_dias,
    ROUND(valor_cobrado, 2) AS valor_cobrado
FROM dw.vw_atrasos_devolucao
ORDER BY atraso_dias DESC, valor_cobrado DESC
LIMIT 20;


-- =====================================================
-- R6. MOVIMENTAÇÃO ENTRE PÁTIOS — matriz de fluxo
--     Responde: "Qual o fluxo de veículos entre pátios?"
-- =====================================================
SELECT
    origem,
    destino,
    total_movimentacoes,
    ROUND(pct_saidas_da_origem, 1)  AS pct_do_total_de_saidas
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
