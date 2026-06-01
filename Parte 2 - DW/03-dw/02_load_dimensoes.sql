-- =====================================================
-- 02_load_dimensoes.sql
-- Carga idempotente das dimensoes conformadas do DW
--
-- Fonte principal: tabelas conformadas stg.conf_* geradas
-- pelos scripts de transformacao em Parte 2 - DW/02-transform.
--
-- Tabelas conformadas identificadas nos scripts existentes:
--   stg.conf_tempo, stg.conf_cliente, stg.conf_condutor,
--   stg.conf_grupo_veiculo, stg.conf_empresa, stg.conf_patio,
--   stg.conf_veiculo, stg.conf_reserva, stg.conf_locacao,
--   stg.conf_veiculo_no_patio, stg.conf_movimentacao_patio.
-- =====================================================

BEGIN;

-- =====================================================
-- Ordem de carga:
-- 1) dim_tempo, dim_cliente, dim_condutor, dim_grupo_veiculo,
--    dim_empresa e dim_patio nao dependem de outras dimensoes.
-- 2) dim_veiculo depende de dim_grupo_veiculo e dim_empresa.
-- =====================================================

-- =====================================================
-- dim_tempo
-- Inclui todas as datas relevantes vindas de reservas, locacoes
-- e movimentacoes. Datas realizadas nulas sao ignoradas sem erro.
-- =====================================================
WITH datas AS (
    SELECT data FROM stg.conf_tempo

    UNION
    SELECT data_reserva::DATE FROM stg.conf_reserva WHERE data_reserva IS NOT NULL
    UNION
    SELECT data_inicio::DATE FROM stg.conf_reserva WHERE data_inicio IS NOT NULL
    UNION
    SELECT data_fim::DATE FROM stg.conf_reserva WHERE data_fim IS NOT NULL

    UNION
    SELECT data_registro::DATE FROM stg.conf_locacao WHERE data_registro IS NOT NULL
    UNION
    SELECT data_retirada_prevista::DATE FROM stg.conf_locacao WHERE data_retirada_prevista IS NOT NULL
    UNION
    SELECT data_retirada::DATE FROM stg.conf_locacao WHERE data_retirada IS NOT NULL
    UNION
    SELECT data_devolucao_prevista::DATE FROM stg.conf_locacao WHERE data_devolucao_prevista IS NOT NULL
    UNION
    SELECT data_devolucao::DATE FROM stg.conf_locacao WHERE data_devolucao IS NOT NULL

    UNION
    SELECT data_movimentacao::DATE
    FROM stg.conf_movimentacao_patio
    WHERE data_movimentacao IS NOT NULL
)
INSERT INTO dw.dim_tempo (
    sk_tempo,
    data,
    ano,
    mes,
    nome_mes,
    trimestre,
    dia,
    dia_semana,
    nome_dia_semana,
    flag_fim_de_semana
)
SELECT
    TO_CHAR(data, 'YYYYMMDD')::INTEGER AS sk_tempo,
    data,
    EXTRACT(YEAR FROM data)::INTEGER AS ano,
    EXTRACT(MONTH FROM data)::INTEGER AS mes,
    TRIM(TO_CHAR(data, 'TMMonth')) AS nome_mes,
    EXTRACT(QUARTER FROM data)::INTEGER AS trimestre,
    EXTRACT(DAY FROM data)::INTEGER AS dia,
    EXTRACT(ISODOW FROM data)::INTEGER AS dia_semana,
    TRIM(TO_CHAR(data, 'TMDay')) AS nome_dia_semana,
    (EXTRACT(ISODOW FROM data) IN (6, 7)) AS flag_fim_de_semana
FROM datas
WHERE data IS NOT NULL
ON CONFLICT (data) DO UPDATE
SET
    ano = EXCLUDED.ano,
    mes = EXCLUDED.mes,
    nome_mes = EXCLUDED.nome_mes,
    trimestre = EXCLUDED.trimestre,
    dia = EXCLUDED.dia,
    dia_semana = EXCLUDED.dia_semana,
    nome_dia_semana = EXCLUDED.nome_dia_semana,
    flag_fim_de_semana = EXCLUDED.flag_fim_de_semana;

-- =====================================================
-- dim_cliente
-- =====================================================
INSERT INTO dw.dim_cliente (
    cliente_id,
    nome,
    tipo,
    cidade
)
SELECT
    cliente_nk AS cliente_id,
    nome,
    tipo,
    cidade
FROM stg.conf_cliente
ON CONFLICT (cliente_id) DO UPDATE
SET
    nome = EXCLUDED.nome,
    tipo = EXCLUDED.tipo,
    cidade = EXCLUDED.cidade;

-- =====================================================
-- dim_condutor
-- =====================================================
INSERT INTO dw.dim_condutor (
    condutor_id,
    cliente_id,
    nome,
    categoria_cnh,
    validade_cnh
)
SELECT
    condutor_nk AS condutor_id,
    cliente_nk AS cliente_id,
    nome,
    categoria AS categoria_cnh,
    validade AS validade_cnh
FROM stg.conf_condutor
ON CONFLICT (condutor_id) DO UPDATE
SET
    cliente_id = EXCLUDED.cliente_id,
    nome = EXCLUDED.nome,
    categoria_cnh = EXCLUDED.categoria_cnh,
    validade_cnh = EXCLUDED.validade_cnh;

-- =====================================================
-- dim_grupo_veiculo
-- =====================================================
INSERT INTO dw.dim_grupo_veiculo (
    grupo_id,
    nome,
    categoria
)
SELECT
    grupo_veiculo_nk AS grupo_id,
    nome,
    categoria
FROM stg.conf_grupo_veiculo
ON CONFLICT (grupo_id) DO UPDATE
SET
    nome = EXCLUDED.nome,
    categoria = EXCLUDED.categoria;

-- =====================================================
-- dim_empresa
-- CNPJ fica nulo porque a camada transformada atual nao traz
-- esse atributo de forma conformada.
-- =====================================================
INSERT INTO dw.dim_empresa (
    empresa_id,
    nome,
    cnpj
)
SELECT
    empresa_nk AS empresa_id,
    nome_empresa AS nome,
    NULL::TEXT AS cnpj
FROM stg.conf_empresa
ON CONFLICT (empresa_id) DO UPDATE
SET
    nome = EXCLUDED.nome,
    cnpj = COALESCE(EXCLUDED.cnpj, dw.dim_empresa.cnpj);

-- =====================================================
-- dim_patio
-- =====================================================
INSERT INTO dw.dim_patio (
    patio_id,
    nome,
    cidade
)
SELECT
    patio_nk AS patio_id,
    nome,
    cidade
FROM stg.conf_patio
ON CONFLICT (patio_id) DO UPDATE
SET
    nome = EXCLUDED.nome,
    cidade = EXCLUDED.cidade;

-- =====================================================
-- Validacao bloqueante antes da carga de dim_veiculo.
-- Veiculos sem grupo ou empresa conformados devem ser corrigidos
-- na transformacao antes de entrar no DW.
-- =====================================================
DO $$
DECLARE
    qtd_orfaos INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO qtd_orfaos
    FROM stg.conf_veiculo v
    LEFT JOIN dw.dim_grupo_veiculo g
           ON g.grupo_id = v.grupo_veiculo_nk
    LEFT JOIN dw.dim_empresa e
           ON e.empresa_id = v.empresa_nk
    WHERE v.grupo_veiculo_nk IS NULL
       OR v.empresa_nk IS NULL
       OR g.sk_grupo_veiculo IS NULL
       OR e.sk_empresa IS NULL;

    IF qtd_orfaos > 0 THEN
        RAISE EXCEPTION
            'Carga de dw.dim_veiculo abortada: % veiculo(s) sem grupo ou empresa conformados.',
            qtd_orfaos;
    END IF;
END $$;

-- =====================================================
-- dim_veiculo
-- =====================================================
INSERT INTO dw.dim_veiculo (
    veiculo_id,
    placa,
    chassi,
    marca,
    modelo,
    cor,
    tipo_mecanizacao,
    ar_condicionado,
    adaptado_cadeirante,
    status,
    sk_grupo_veiculo,
    sk_empresa
)
SELECT
    v.veiculo_nk AS veiculo_id,
    v.placa,
    v.chassi,
    v.marca,
    v.modelo,
    v.cor,
    v.tipo_mecanizacao,
    v.ar_condicionado,
    v.adaptado_cadeirante,
    v.status,
    g.sk_grupo_veiculo,
    e.sk_empresa
FROM stg.conf_veiculo v
JOIN dw.dim_grupo_veiculo g
  ON g.grupo_id = v.grupo_veiculo_nk
JOIN dw.dim_empresa e
  ON e.empresa_id = v.empresa_nk
ON CONFLICT (veiculo_id) DO UPDATE
SET
    placa = EXCLUDED.placa,
    chassi = EXCLUDED.chassi,
    marca = EXCLUDED.marca,
    modelo = EXCLUDED.modelo,
    cor = EXCLUDED.cor,
    tipo_mecanizacao = EXCLUDED.tipo_mecanizacao,
    ar_condicionado = EXCLUDED.ar_condicionado,
    adaptado_cadeirante = EXCLUDED.adaptado_cadeirante,
    status = EXCLUDED.status,
    sk_grupo_veiculo = EXCLUDED.sk_grupo_veiculo,
    sk_empresa = EXCLUDED.sk_empresa;

COMMIT;

-- =====================================================
-- Validacoes informativas da carga de dimensoes
-- =====================================================

-- Contagem entre transform e DW para dimensoes.
SELECT *
FROM (
    VALUES
        ('clientes',        (SELECT COUNT(*) FROM stg.conf_cliente),        (SELECT COUNT(*) FROM dw.dim_cliente)),
        ('condutores',      (SELECT COUNT(*) FROM stg.conf_condutor),       (SELECT COUNT(*) FROM dw.dim_condutor)),
        ('grupos_veiculo',  (SELECT COUNT(*) FROM stg.conf_grupo_veiculo),  (SELECT COUNT(*) FROM dw.dim_grupo_veiculo)),
        ('empresas',        (SELECT COUNT(*) FROM stg.conf_empresa),        (SELECT COUNT(*) FROM dw.dim_empresa)),
        ('patios',          (SELECT COUNT(*) FROM stg.conf_patio),          (SELECT COUNT(*) FROM dw.dim_patio)),
        ('veiculos',        (SELECT COUNT(*) FROM stg.conf_veiculo),        (SELECT COUNT(*) FROM dw.dim_veiculo))
) AS v(entidade, qtd_transform, qtd_dw)
ORDER BY entidade;

-- Chaves naturais duplicadas nas dimensoes. O esperado e retornar zero linhas.
SELECT 'dim_cliente' AS tabela, cliente_id AS chave_natural, COUNT(*) AS qtd
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
HAVING COUNT(*) > 1;
