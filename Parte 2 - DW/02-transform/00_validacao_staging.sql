-- =====================================================
-- Nome: Tadeu Belfort Neto
-- DRE: 119034813
-- Arquivo: 00_validacao_staging.sql
-- Descrição: Validações da camada de staging bruta (stg.*)
--            ANTES da transformação para conformance.
--
-- Execute após os scripts de extração (etl_01 e etl_02)
-- e ANTES de 01_transform_dimensoes.sql.
--
-- As queries aqui são apenas de leitura (SELECT).
-- Nenhum dado é modificado. Resultados inesperados devem
-- ser investigados antes de prosseguir com o pipeline.
-- =====================================================

-- =====================================================
-- 1. VOLUMES POR TABELA E GRUPO
--    Esperado: cada grupo deve ter registros em todas
--    as tabelas principais. Volume zero = falha na extração.
-- =====================================================
SELECT 'cliente'           AS tabela, grupo_fonte, COUNT(*) AS qtd FROM stg.cliente          GROUP BY grupo_fonte
UNION ALL
SELECT 'condutor',                    grupo_fonte, COUNT(*) FROM stg.condutor         GROUP BY grupo_fonte
UNION ALL
SELECT 'grupo_veiculo',               grupo_fonte, COUNT(*) FROM stg.grupo_veiculo    GROUP BY grupo_fonte
UNION ALL
SELECT 'veiculo',                     grupo_fonte, COUNT(*) FROM stg.veiculo          GROUP BY grupo_fonte
UNION ALL
SELECT 'patio',                       grupo_fonte, COUNT(*) FROM stg.patio            GROUP BY grupo_fonte
UNION ALL
SELECT 'reserva',                     grupo_fonte, COUNT(*) FROM stg.reserva          GROUP BY grupo_fonte
UNION ALL
SELECT 'locacao',                     grupo_fonte, COUNT(*) FROM stg.locacao          GROUP BY grupo_fonte
ORDER BY tabela, grupo_fonte;

-- =====================================================
-- 2. NULOS EM CAMPOS OBRIGATÓRIOS
--    src_id nulo quebraria as chaves naturais compostas.
--    nome/placa/cnh nulos causam dados inúteis no DW.
-- =====================================================
SELECT
    'cliente'    AS tabela,
    grupo_fonte,
    COUNT(*) FILTER (WHERE src_id  IS NULL) AS src_id_nulo,
    COUNT(*) FILTER (WHERE nome    IS NULL OR TRIM(nome) = '') AS nome_nulo
FROM stg.cliente
GROUP BY grupo_fonte

UNION ALL

SELECT
    'veiculo',
    grupo_fonte,
    COUNT(*) FILTER (WHERE src_id  IS NULL) AS src_id_nulo,
    COUNT(*) FILTER (WHERE placa   IS NULL OR TRIM(placa) = '') AS placa_nula
FROM stg.veiculo
GROUP BY grupo_fonte

UNION ALL

SELECT
    'condutor',
    grupo_fonte,
    COUNT(*) FILTER (WHERE src_id  IS NULL) AS src_id_nulo,
    COUNT(*) FILTER (WHERE cnh     IS NULL OR TRIM(cnh) = '') AS cnh_nula
FROM stg.condutor
GROUP BY grupo_fonte

ORDER BY tabela, grupo_fonte;

-- =====================================================
-- 3. DUPLICATAS NA STAGING
--    A PK (grupo_fonte, src_id) deve ser única.
--    Qualquer resultado aqui indica problema na extração.
-- =====================================================
SELECT 'cliente'        AS tabela, grupo_fonte, src_id, COUNT(*) AS ocorrencias FROM stg.cliente        GROUP BY grupo_fonte, src_id HAVING COUNT(*) > 1
UNION ALL
SELECT 'veiculo',                  grupo_fonte, src_id, COUNT(*) FROM stg.veiculo        GROUP BY grupo_fonte, src_id HAVING COUNT(*) > 1
UNION ALL
SELECT 'condutor',                 grupo_fonte, src_id, COUNT(*) FROM stg.condutor       GROUP BY grupo_fonte, src_id HAVING COUNT(*) > 1
UNION ALL
SELECT 'reserva',                  grupo_fonte, src_id, COUNT(*) FROM stg.reserva        GROUP BY grupo_fonte, src_id HAVING COUNT(*) > 1
UNION ALL
SELECT 'locacao',                  grupo_fonte, src_id, COUNT(*) FROM stg.locacao        GROUP BY grupo_fonte, src_id HAVING COUNT(*) > 1
UNION ALL
SELECT 'movimentacao_patio',       grupo_fonte, src_id, COUNT(*) FROM stg.movimentacao_patio GROUP BY grupo_fonte, src_id HAVING COUNT(*) > 1
ORDER BY tabela, grupo_fonte;

-- =====================================================
-- 4. DATAS IMPOSSÍVEIS EM LOCAÇÕES
--    data_devolucao_prevista anterior à data_retirada_prevista
--    indica erro de cadastro no OLTP fonte.
-- =====================================================
SELECT
    grupo_fonte,
    src_id,
    data_retirada_prevista,
    data_devolucao_prevista,
    data_retirada_realizada,
    data_devolucao_realizada
FROM stg.locacao
WHERE (data_devolucao_prevista IS NOT NULL
       AND data_retirada_prevista IS NOT NULL
       AND data_devolucao_prevista < data_retirada_prevista)
   OR (data_devolucao_realizada IS NOT NULL
       AND data_retirada_realizada IS NOT NULL
       AND data_devolucao_realizada < data_retirada_realizada)
ORDER BY grupo_fonte, src_id;

-- =====================================================
-- 5. KM INVERTIDO EM LOCAÇÕES
--    km_devolucao < km_entrega indica odômetro zerado/trocado
--    ou erro de digitação. O transform protege com GREATEST(..., 0)
--    mas o dado original deve ser investigado.
-- =====================================================
SELECT
    grupo_fonte,
    src_id,
    km_entrega,
    km_devolucao,
    km_devolucao - km_entrega AS km_rodado_calculado
FROM stg.locacao
WHERE km_entrega IS NOT NULL
  AND km_devolucao IS NOT NULL
  AND km_devolucao < km_entrega
ORDER BY grupo_fonte, src_id;

-- =====================================================
-- 6. LOCAÇÕES SEM VEICULO OU CONDUTOR
--    FK obrigatória — locação sem veículo não pode entrar no DW.
-- =====================================================
SELECT
    grupo_fonte,
    COUNT(*) FILTER (WHERE src_veiculo_id  IS NULL) AS sem_veiculo,
    COUNT(*) FILTER (WHERE src_condutor_id IS NULL) AS sem_condutor,
    COUNT(*) FILTER (WHERE src_cliente_id  IS NULL) AS sem_cliente
FROM stg.locacao
GROUP BY grupo_fonte
HAVING COUNT(*) FILTER (WHERE src_veiculo_id IS NULL) > 0
    OR COUNT(*) FILTER (WHERE src_condutor_id IS NULL) > 0
    OR COUNT(*) FILTER (WHERE src_cliente_id IS NULL) > 0;

-- =====================================================
-- 7. RESUMO DO LOG DE EXTRAÇÃO
--    Compara a última extração registrada com o volume atual.
--    Quedas bruscas de volume indicam falha parcial ou truncamento.
-- =====================================================
SELECT
    l.grupo_fonte,
    l.tabela_stg,
    l.dt_extracao,
    l.qtd_registros AS qtd_na_extracao,
    l.status
FROM stg.log_extracao l
WHERE (l.grupo_fonte, l.tabela_stg, l.dt_extracao) IN (
    SELECT grupo_fonte, tabela_stg, MAX(dt_extracao)
    FROM stg.log_extracao
    GROUP BY grupo_fonte, tabela_stg
)
ORDER BY l.grupo_fonte, l.tabela_stg;
