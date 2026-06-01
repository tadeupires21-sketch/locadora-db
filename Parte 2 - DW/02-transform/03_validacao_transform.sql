-- =====================================================
-- Validacao da camada transformada stg.conf_*
-- Execute apos:
--   1) transform/01_transform_dimensoes.sql
--   2) transform/02_transform_fatos.sql
-- =====================================================

-- Objetivo: conferir volume total das tabelas conformadas.
SELECT *
FROM (
    VALUES
        ('conf_cliente',              (SELECT COUNT(*) FROM stg.conf_cliente)),
        ('conf_condutor',             (SELECT COUNT(*) FROM stg.conf_condutor)),
        ('conf_grupo_veiculo',        (SELECT COUNT(*) FROM stg.conf_grupo_veiculo)),
        ('conf_empresa',              (SELECT COUNT(*) FROM stg.conf_empresa)),
        ('conf_patio',                (SELECT COUNT(*) FROM stg.conf_patio)),
        ('conf_veiculo',              (SELECT COUNT(*) FROM stg.conf_veiculo)),
        ('conf_tempo',                (SELECT COUNT(*) FROM stg.conf_tempo)),
        ('conf_reserva',              (SELECT COUNT(*) FROM stg.conf_reserva)),
        ('conf_locacao',              (SELECT COUNT(*) FROM stg.conf_locacao)),
        ('conf_veiculo_no_patio',     (SELECT COUNT(*) FROM stg.conf_veiculo_no_patio)),
        ('conf_movimentacao_patio',   (SELECT COUNT(*) FROM stg.conf_movimentacao_patio))
) AS v(tabela, qtd_registros)
ORDER BY tabela;

-- Objetivo: conferir distribuicao por grupo_fonte nas dimensoes.
SELECT 'conf_cliente' AS tabela, grupo_fonte, COUNT(*) AS qtd
FROM stg.conf_cliente
GROUP BY grupo_fonte
ORDER BY grupo_fonte;

SELECT 'conf_condutor' AS tabela, grupo_fonte, COUNT(*) AS qtd
FROM stg.conf_condutor
GROUP BY grupo_fonte
ORDER BY grupo_fonte;

SELECT 'conf_grupo_veiculo' AS tabela, grupo_fonte, COUNT(*) AS qtd
FROM stg.conf_grupo_veiculo
GROUP BY grupo_fonte
ORDER BY grupo_fonte;

SELECT 'conf_empresa' AS tabela, grupo_fonte, COUNT(*) AS qtd
FROM stg.conf_empresa
GROUP BY grupo_fonte
ORDER BY grupo_fonte;

SELECT 'conf_patio' AS tabela, grupo_fonte, COUNT(*) AS qtd
FROM stg.conf_patio
GROUP BY grupo_fonte
ORDER BY grupo_fonte;

SELECT 'conf_veiculo' AS tabela, grupo_fonte, COUNT(*) AS qtd
FROM stg.conf_veiculo
GROUP BY grupo_fonte
ORDER BY grupo_fonte;

-- Objetivo: conferir distribuicao por grupo_fonte nas fatos.
SELECT 'conf_reserva' AS tabela, grupo_fonte, COUNT(*) AS qtd
FROM stg.conf_reserva
GROUP BY grupo_fonte
ORDER BY grupo_fonte;

SELECT 'conf_locacao' AS tabela, grupo_fonte, COUNT(*) AS qtd
FROM stg.conf_locacao
GROUP BY grupo_fonte
ORDER BY grupo_fonte;

SELECT 'conf_veiculo_no_patio' AS tabela, grupo_fonte, COUNT(*) AS qtd
FROM stg.conf_veiculo_no_patio
GROUP BY grupo_fonte
ORDER BY grupo_fonte;

SELECT 'conf_movimentacao_patio' AS tabela, grupo_fonte, COUNT(*) AS qtd
FROM stg.conf_movimentacao_patio
GROUP BY grupo_fonte
ORDER BY grupo_fonte;

-- Objetivo: identificar nulos em chaves naturais e SKs importantes.
SELECT
    'conf_cliente' AS tabela,
    COUNT(*) FILTER (WHERE cliente_nk IS NULL) AS nk_nulo,
    COUNT(*) FILTER (WHERE sk_cliente IS NULL) AS sk_nulo,
    0 AS fk_nula
FROM stg.conf_cliente;

SELECT
    'conf_condutor' AS tabela,
    COUNT(*) FILTER (WHERE condutor_nk IS NULL OR cliente_nk IS NULL) AS nk_nulo,
    COUNT(*) FILTER (WHERE sk_condutor IS NULL) AS sk_nulo,
    COUNT(*) FILTER (WHERE src_cliente_id IS NULL) AS fk_nula
FROM stg.conf_condutor;

SELECT
    'conf_veiculo' AS tabela,
    COUNT(*) FILTER (WHERE veiculo_nk IS NULL) AS nk_nulo,
    COUNT(*) FILTER (WHERE sk_veiculo IS NULL) AS sk_nulo,
    COUNT(*) FILTER (WHERE grupo_veiculo_nk IS NULL OR sk_grupo IS NULL) AS fk_nula
FROM stg.conf_veiculo;

SELECT
    'conf_reserva' AS tabela,
    COUNT(*) FILTER (WHERE reserva_nk IS NULL) AS nk_nulo,
    COUNT(*) FILTER (WHERE sk_reserva IS NULL) AS sk_nulo,
    COUNT(*) FILTER (
        WHERE sk_cliente IS NULL
           OR sk_grupo IS NULL
           OR sk_patio_retirada IS NULL
           OR data_reserva IS NULL
           OR data_inicio IS NULL
    ) AS fk_nula
FROM stg.conf_reserva;

SELECT
    'conf_locacao' AS tabela,
    COUNT(*) FILTER (WHERE locacao_nk IS NULL) AS nk_nulo,
    COUNT(*) FILTER (WHERE sk_locacao IS NULL) AS sk_nulo,
    COUNT(*) FILTER (
        WHERE sk_cliente IS NULL
           OR sk_condutor IS NULL
           OR sk_veiculo IS NULL
           OR sk_patio_retirada IS NULL
           OR data_registro IS NULL
    ) AS fk_nula
FROM stg.conf_locacao;

-- Objetivo: verificar duplicidades nas chaves naturais das dimensoes.
SELECT 'conf_cliente' AS tabela, cliente_nk AS chave_natural, COUNT(*) AS qtd
FROM stg.conf_cliente
GROUP BY cliente_nk
HAVING COUNT(*) > 1;

SELECT 'conf_condutor' AS tabela, condutor_nk AS chave_natural, COUNT(*) AS qtd
FROM stg.conf_condutor
GROUP BY condutor_nk
HAVING COUNT(*) > 1;

SELECT 'conf_grupo_veiculo' AS tabela, grupo_veiculo_nk AS chave_natural, COUNT(*) AS qtd
FROM stg.conf_grupo_veiculo
GROUP BY grupo_veiculo_nk
HAVING COUNT(*) > 1;

SELECT 'conf_empresa' AS tabela, empresa_nk AS chave_natural, COUNT(*) AS qtd
FROM stg.conf_empresa
GROUP BY empresa_nk
HAVING COUNT(*) > 1;

SELECT 'conf_patio' AS tabela, patio_nk AS chave_natural, COUNT(*) AS qtd
FROM stg.conf_patio
GROUP BY patio_nk
HAVING COUNT(*) > 1;

SELECT 'conf_veiculo' AS tabela, veiculo_nk AS chave_natural, COUNT(*) AS qtd
FROM stg.conf_veiculo
GROUP BY veiculo_nk
HAVING COUNT(*) > 1;

-- Objetivo: verificar duplicidades nas chaves naturais das fatos.
SELECT 'conf_reserva' AS tabela, reserva_nk AS chave_natural, COUNT(*) AS qtd
FROM stg.conf_reserva
GROUP BY reserva_nk
HAVING COUNT(*) > 1;

SELECT 'conf_locacao' AS tabela, locacao_nk AS chave_natural, COUNT(*) AS qtd
FROM stg.conf_locacao
GROUP BY locacao_nk
HAVING COUNT(*) > 1;

SELECT 'conf_movimentacao_patio' AS tabela, movimentacao_patio_nk AS chave_natural, COUNT(*) AS qtd
FROM stg.conf_movimentacao_patio
GROUP BY movimentacao_patio_nk
HAVING COUNT(*) > 1;

-- Objetivo: comparar volumes basicos entre staging bruto e transformado.
-- Diferencas podem indicar deduplicacao, filtro de registros invalidos ou falta de relacionamento.
SELECT *
FROM (
    VALUES
        ('cliente',             (SELECT COUNT(*) FROM stg.cliente),             (SELECT COUNT(*) FROM stg.conf_cliente)),
        ('condutor',            (SELECT COUNT(*) FROM stg.condutor),            (SELECT COUNT(*) FROM stg.conf_condutor)),
        ('grupo_veiculo',       (SELECT COUNT(*) FROM stg.grupo_veiculo),       (SELECT COUNT(*) FROM stg.conf_grupo_veiculo)),
        ('patio',               (SELECT COUNT(*) FROM stg.patio),               (SELECT COUNT(*) FROM stg.conf_patio)),
        ('veiculo',             (SELECT COUNT(*) FROM stg.veiculo),             (SELECT COUNT(*) FROM stg.conf_veiculo)),
        ('reserva',             (SELECT COUNT(*) FROM stg.reserva),             (SELECT COUNT(*) FROM stg.conf_reserva)),
        ('locacao',             (SELECT COUNT(*) FROM stg.locacao),             (SELECT COUNT(*) FROM stg.conf_locacao)),
        ('movimentacao_patio',  (SELECT COUNT(*) FROM stg.movimentacao_patio),  (SELECT COUNT(*) FROM stg.conf_movimentacao_patio))
) AS v(entidade, qtd_staging, qtd_transformado)
ORDER BY entidade;

-- Objetivo: encontrar fatos que nao conseguiram resolver dimensoes.
SELECT
    'conf_reserva' AS tabela,
    COUNT(*) FILTER (WHERE sk_cliente IS NULL) AS sem_cliente,
    COUNT(*) FILTER (WHERE sk_grupo IS NULL) AS sem_grupo_veiculo,
    COUNT(*) FILTER (WHERE sk_patio_retirada IS NULL) AS sem_patio_retirada,
    COUNT(*) FILTER (WHERE patio_devolucao_nk IS NOT NULL AND sk_patio_devolucao IS NULL) AS sem_patio_devolucao
FROM stg.conf_reserva;

SELECT
    'conf_locacao' AS tabela,
    COUNT(*) FILTER (WHERE sk_cliente IS NULL) AS sem_cliente,
    COUNT(*) FILTER (WHERE sk_condutor IS NULL) AS sem_condutor,
    COUNT(*) FILTER (WHERE sk_veiculo IS NULL) AS sem_veiculo,
    COUNT(*) FILTER (WHERE sk_patio_retirada IS NULL) AS sem_patio_retirada,
    COUNT(*) FILTER (WHERE patio_devolucao_nk IS NOT NULL AND sk_patio_devolucao IS NULL) AS sem_patio_devolucao
FROM stg.conf_locacao;

-- Objetivo: validar consistencia de datas e medidas.
SELECT
    'conf_reserva' AS tabela,
    COUNT(*) FILTER (WHERE data_fim IS NOT NULL AND data_inicio IS NOT NULL AND data_fim < data_inicio) AS periodo_invertido,
    COUNT(*) FILTER (WHERE antecedencia_dias < 0) AS antecedencia_negativa,
    COUNT(*) FILTER (WHERE duracao_prevista_dias < 0) AS duracao_negativa
FROM stg.conf_reserva;

SELECT
    'conf_locacao' AS tabela,
    COUNT(*) FILTER (WHERE data_devolucao IS NOT NULL AND data_retirada IS NOT NULL AND data_devolucao < data_retirada) AS periodo_invertido,
    COUNT(*) FILTER (WHERE km_rodado < 0) AS km_negativo,
    COUNT(*) FILTER (WHERE valor_cobrado < 0) AS valor_negativo
FROM stg.conf_locacao;
