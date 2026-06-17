-- =====================================================
-- Transformacao - dimensoes conformadas
-- Projeto academico de Data Warehouse para locadora
-- Grupo:
--   Tadeu Belfort Neto              DRE 119034813
--   Vicente Alves                   DRE 120044148
--   João Pedro de Lacerda           DRE 116076670

-- Este script le apenas as tabelas unificadas do schema stg.
-- O campo grupo_fonte faz parte das chaves naturais para evitar
-- colisao entre IDs iguais vindos de bases diferentes.
--
-- NOTA SOBRE SURROGATE KEYS (sk_*):
--   Os sk_* gerados aqui via ROW_NUMBER() são usados apenas
--   internamente nesta camada de conformance (joins entre
--   conf_veiculo → conf_grupo_veiculo, etc.).
--   O script de carga do DW (03-dw/02_load_dimensoes.sql) NÃO usa
--   esses sk_* — ele faz JOIN pelas chaves naturais (*_nk / *_id)
--   e usa os IDENTITY gerados pelo próprio DW como surrogate keys finais.
--   Portanto, a variação dos sk_* entre execuções não compromete a
--   integridade do DW, apenas a rastreabilidade interna do staging.
--
-- NOTA SOBRE TIMEZONE:
--   A staging usa TIMESTAMP sem fuso. Fixamos o fuso canônico da sessão
--   para que os casts ::DATE caiam sempre no mesmo dia, independente do
--   fuso do servidor que executa o ETL.
--   LIMITAÇÃO CONHECIDA: se as 4 fontes gravarem em fusos diferentes,
--   a conversão correta exigiria saber o fuso de origem de cada grupo
--   (idealmente armazenar TIMESTAMPTZ na extração). Enquanto isso não
--   existe, assume-se que todas as fontes já estão em horário de Brasília.
-- =====================================================

\set ON_ERROR_STOP on
SET timezone TO 'America/Sao_Paulo';

-- Transação única: o conjunto DROP+CREATE de todas as conf_* roda como
-- uma só unidade. DDL é transacional no PostgreSQL, então se qualquer
-- etapa falhar o ROLLBACK preserva as tabelas conformadas da execução
-- anterior — evita deixar a camada com tabelas dropadas e não recriadas.
BEGIN;

-- =====================================================
-- conf_cliente
-- Chave natural: grupo_fonte-src_id
--
-- DEDUP: a deduplicação é POR FONTE (grupo_fonte, src_id) + última
-- dt_extracao. NÃO há dedup entre fontes: o mesmo cliente físico
-- cadastrado em 2 locadoras vira 2 linhas (por isso grupo_fonte faz
-- parte da NK). Decisão consciente — modelo multi-tenant. Consequência:
-- métricas de "clientes únicos" podem contar em dobro entre grupos.
-- Uma dedup cross-source exigiria casar por CPF/CNPJ/e-mail (não feito).
-- =====================================================
DROP TABLE IF EXISTS stg.conf_cliente CASCADE;

CREATE TABLE stg.conf_cliente AS
WITH base AS (
    SELECT
        c.*,
        ROW_NUMBER() OVER (
            PARTITION BY c.grupo_fonte, c.src_id
            ORDER BY c.dt_extracao DESC
        ) AS rn
    FROM stg.cliente c
),
normalizado AS (
    SELECT
        (grupo_fonte::TEXT || '-' || src_id::TEXT) AS cliente_nk,
        src_id,
        grupo_fonte,
        COALESCE(NULLIF(TRIM(nome), ''), 'Cliente nao informado') AS nome,
        -- Flag de imputação: distingue nome real de sentinela preenchido,
        -- para que análises possam excluir/auditar os imputados.
        (NULLIF(TRIM(nome), '') IS NULL) AS flag_nome_imputado,
        stg.fn_normaliza_tipo_cliente(tipo) AS tipo,
        NULLIF(TRIM(cidade), '') AS cidade,
        UPPER(NULLIF(TRIM(uf), '')) AS uf,
        LOWER(NULLIF(TRIM(email), '')) AS email,
        NULLIF(REGEXP_REPLACE(COALESCE(telefone, ''), '[^0-9]+', '', 'g'), '') AS telefone,
        dt_extracao
    FROM base
    WHERE rn = 1
)
SELECT
    ROW_NUMBER() OVER (ORDER BY grupo_fonte, src_id)::INTEGER AS sk_cliente,
    cliente_nk,
    src_id,
    grupo_fonte,
    nome,
    flag_nome_imputado,
    tipo,
    cidade,
    uf,
    email,
    telefone,
    dt_extracao
FROM normalizado;

-- =====================================================
-- conf_condutor
-- Chaves naturais:
--   condutor_nk = grupo_fonte-src_id
--   cliente_nk  = grupo_fonte-src_cliente_id
-- =====================================================
DROP TABLE IF EXISTS stg.conf_condutor CASCADE;

CREATE TABLE stg.conf_condutor AS
WITH base AS (
    SELECT
        c.*,
        ROW_NUMBER() OVER (
            PARTITION BY c.grupo_fonte, c.src_id
            ORDER BY c.dt_extracao DESC
        ) AS rn
    FROM stg.condutor c
),
normalizado AS (
    SELECT
        (grupo_fonte::TEXT || '-' || src_id::TEXT) AS condutor_nk,
        (grupo_fonte::TEXT || '-' || src_cliente_id::TEXT) AS cliente_nk,
        src_id,
        grupo_fonte,
        src_cliente_id,
        COALESCE(NULLIF(TRIM(nome), ''), 'Condutor nao informado') AS nome,
        NULLIF(REGEXP_REPLACE(COALESCE(cnh, ''), '[^0-9]+', '', 'g'), '') AS cnh,
        validade::DATE AS validade,
        UPPER(NULLIF(TRIM(categoria), '')) AS categoria,
        dt_extracao
    FROM base
    WHERE rn = 1
)
SELECT
    ROW_NUMBER() OVER (ORDER BY grupo_fonte, src_id)::INTEGER AS sk_condutor,
    condutor_nk,
    cliente_nk,
    src_id,
    grupo_fonte,
    src_cliente_id,
    nome,
    cnh,
    validade,
    categoria,
    dt_extracao
FROM normalizado;

-- =====================================================
-- conf_grupo_veiculo
-- Chave natural: grupo_fonte-src_id
-- =====================================================
DROP TABLE IF EXISTS stg.conf_grupo_veiculo CASCADE;

CREATE TABLE stg.conf_grupo_veiculo AS
WITH base AS (
    SELECT
        g.*,
        ROW_NUMBER() OVER (
            PARTITION BY g.grupo_fonte, g.src_id
            ORDER BY g.dt_extracao DESC
        ) AS rn
    FROM stg.grupo_veiculo g
),
normalizado AS (
    SELECT
        (grupo_fonte::TEXT || '-' || src_id::TEXT) AS grupo_veiculo_nk,
        src_id,
        grupo_fonte,
        COALESCE(NULLIF(TRIM(nome), ''), 'Grupo nao informado') AS nome,
        COALESCE(NULLIF(TRIM(categoria), ''), 'Sem categoria') AS categoria,
        diaria::NUMERIC(10,2) AS diaria,
        dt_extracao
    FROM base
    WHERE rn = 1
)
SELECT
    ROW_NUMBER() OVER (ORDER BY grupo_fonte, src_id)::INTEGER AS sk_grupo,
    grupo_veiculo_nk,
    src_id,
    grupo_fonte,
    nome,
    categoria,
    diaria,
    dt_extracao
FROM normalizado;

-- =====================================================
-- conf_empresa
-- A staging atual guarda empresa junto de patio/veiculo.
-- Esta dimensao conformada consolida essas ocorrencias.
-- =====================================================
DROP TABLE IF EXISTS stg.conf_empresa CASCADE;

CREATE TABLE stg.conf_empresa AS
WITH empresas AS (
    SELECT
        p.grupo_fonte,
        p.src_empresa_id,
        NULLIF(TRIM(p.nome_empresa), '') AS nome_empresa,
        p.dt_extracao
    FROM stg.patio p
    WHERE p.src_empresa_id IS NOT NULL
       OR NULLIF(TRIM(COALESCE(p.nome_empresa, '')), '') IS NOT NULL

    UNION

    SELECT
        v.grupo_fonte,
        v.src_empresa_id,
        NULLIF(TRIM(v.nome_empresa), '') AS nome_empresa,
        v.dt_extracao
    FROM stg.veiculo v
    WHERE v.src_empresa_id IS NOT NULL
       OR NULLIF(TRIM(COALESCE(v.nome_empresa, '')), '') IS NOT NULL
),
normalizado AS (
    SELECT
        grupo_fonte,
        src_empresa_id,
        COALESCE(nome_empresa, 'Empresa G' || grupo_fonte::TEXT) AS nome_empresa,
        (
            grupo_fonte::TEXT || '-' ||
            COALESCE(
                src_empresa_id::TEXT,
                REGEXP_REPLACE(UPPER(COALESCE(nome_empresa, 'EMPRESA_ND')), '[^A-Z0-9]+', '_', 'g')
            )
        ) AS empresa_nk,
        MAX(dt_extracao) AS dt_extracao
    FROM empresas
    GROUP BY grupo_fonte, src_empresa_id, nome_empresa
),
dedup AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY empresa_nk
            ORDER BY src_empresa_id NULLS LAST, nome_empresa
        ) AS rn
    FROM normalizado
)
SELECT
    ROW_NUMBER() OVER (ORDER BY grupo_fonte, empresa_nk)::INTEGER AS sk_empresa,
    empresa_nk,
    src_empresa_id,
    grupo_fonte,
    nome_empresa,
    dt_extracao
FROM dedup
WHERE rn = 1;

-- =====================================================
-- conf_patio
-- Chaves naturais:
--   patio_nk   = grupo_fonte-src_id
--   empresa_nk = grupo_fonte-src_empresa_id ou grupo_fonte-nome
-- A capacidade nula recebe 0 para manter compatibilidade com a carga DW.
-- =====================================================
DROP TABLE IF EXISTS stg.conf_patio CASCADE;

CREATE TABLE stg.conf_patio AS
WITH base AS (
    SELECT
        p.*,
        ROW_NUMBER() OVER (
            PARTITION BY p.grupo_fonte, p.src_id
            ORDER BY p.dt_extracao DESC
        ) AS rn
    FROM stg.patio p
),
normalizado AS (
    SELECT
        (grupo_fonte::TEXT || '-' || src_id::TEXT) AS patio_nk,
        (
            grupo_fonte::TEXT || '-' ||
            COALESCE(
                src_empresa_id::TEXT,
                REGEXP_REPLACE(
                    UPPER(COALESCE(NULLIF(TRIM(nome_empresa), ''), 'EMPRESA_ND')),
                    '[^A-Z0-9]+',
                    '_',
                    'g'
                )
            )
        ) AS empresa_nk,
        src_id,
        grupo_fonte,
        src_empresa_id,
        COALESCE(NULLIF(TRIM(nome), ''), 'Patio nao informado') AS nome,
        NULLIF(TRIM(cidade), '') AS cidade,
        COALESCE(capacidade, 0)::INTEGER AS capacidade,
        COALESCE(NULLIF(TRIM(nome_empresa), ''), 'Empresa G' || grupo_fonte::TEXT) AS nome_empresa,
        dt_extracao
    FROM base
    WHERE rn = 1
)
SELECT
    ROW_NUMBER() OVER (ORDER BY grupo_fonte, src_id)::INTEGER AS sk_patio,
    patio_nk,
    empresa_nk,
    src_id,
    grupo_fonte,
    src_empresa_id,
    nome,
    cidade,
    capacidade,
    nome_empresa,
    dt_extracao
FROM normalizado;

-- =====================================================
-- conf_veiculo
-- Chaves naturais:
--   veiculo_nk       = grupo_fonte-src_id
--   grupo_veiculo_nk = grupo_fonte-src_grupo_id
-- =====================================================
DROP TABLE IF EXISTS stg.conf_veiculo CASCADE;

CREATE TABLE stg.conf_veiculo AS
WITH base AS (
    SELECT
        v.*,
        ROW_NUMBER() OVER (
            PARTITION BY v.grupo_fonte, v.src_id
            ORDER BY v.dt_extracao DESC
        ) AS rn
    FROM stg.veiculo v
),
normalizado AS (
    SELECT
        (grupo_fonte::TEXT || '-' || src_id::TEXT) AS veiculo_nk,
        CASE
            WHEN src_grupo_id IS NOT NULL THEN (grupo_fonte::TEXT || '-' || src_grupo_id::TEXT)
        END AS grupo_veiculo_nk,
        (
            grupo_fonte::TEXT || '-' ||
            COALESCE(
                src_empresa_id::TEXT,
                REGEXP_REPLACE(
                    UPPER(COALESCE(NULLIF(TRIM(nome_empresa), ''), 'EMPRESA_ND')),
                    '[^A-Z0-9]+',
                    '_',
                    'g'
                )
            )
        ) AS empresa_nk,
        src_id,
        grupo_fonte,
        src_grupo_id,
        src_empresa_id,
        stg.fn_normaliza_placa(placa) AS placa,
        -- Flag de imputação: TRUE quando a placa original era vazia/nula.
        stg.fn_placa_imputada(placa) AS flag_placa_imputada,
        NULLIF(TRIM(chassi), '') AS chassi,
        COALESCE(NULLIF(TRIM(modelo), ''), 'Modelo nao informado') AS modelo,
        COALESCE(NULLIF(TRIM(marca), ''), 'Marca nao informada') AS marca,
        NULLIF(TRIM(cor), '') AS cor,
        stg.fn_normaliza_tipo_mecanizacao(tipo_mecanizacao) AS tipo_mecanizacao,
        COALESCE(ar_condicionado, FALSE) AS ar_condicionado,
        COALESCE(adaptado_cadeirante, FALSE) AS adaptado_cadeirante,
        stg.fn_normaliza_status_veiculo(status) AS status,
        COALESCE(NULLIF(TRIM(nome_empresa), ''), 'Empresa G' || grupo_fonte::TEXT) AS nome_empresa,
        dt_extracao
    FROM base
    WHERE rn = 1
)
SELECT
    ROW_NUMBER() OVER (ORDER BY n.grupo_fonte, n.src_id)::INTEGER AS sk_veiculo,
    n.veiculo_nk,
    n.grupo_veiculo_nk,
    n.empresa_nk,
    n.src_id,
    n.grupo_fonte,
    n.src_grupo_id,
    n.src_empresa_id,
    n.placa,
    n.flag_placa_imputada,
    n.chassi,
    n.modelo,
    n.marca,
    n.cor,
    n.tipo_mecanizacao,
    n.ar_condicionado,
    n.adaptado_cadeirante,
    n.status,
    g.sk_grupo,
    e.sk_empresa,
    n.nome_empresa,
    n.dt_extracao
FROM normalizado n
LEFT JOIN stg.conf_grupo_veiculo g
       ON g.grupo_veiculo_nk = n.grupo_veiculo_nk
LEFT JOIN stg.conf_empresa e
       ON e.empresa_nk = n.empresa_nk;

-- =====================================================
-- conf_tempo
-- Gera a dimensao de tempo somente a partir das datas existentes
-- nas reservas, locacoes e movimentacoes de patio carregadas no staging.
-- =====================================================
DROP TABLE IF EXISTS stg.conf_tempo CASCADE;

CREATE TABLE stg.conf_tempo AS
WITH datas AS (
    SELECT COALESCE(data_reserva, data_solicitacao)::DATE AS data
    FROM stg.reserva
    WHERE COALESCE(data_reserva, data_solicitacao) IS NOT NULL

    UNION

    SELECT data_inicio::DATE
    FROM stg.reserva
    WHERE data_inicio IS NOT NULL

    UNION

    SELECT data_fim::DATE
    FROM stg.reserva
    WHERE data_fim IS NOT NULL

    UNION

    SELECT COALESCE(created_at, data_retirada_realizada, data_retirada_prevista)::DATE
    FROM stg.locacao
    WHERE COALESCE(created_at, data_retirada_realizada, data_retirada_prevista) IS NOT NULL

    UNION

    SELECT data_retirada_realizada::DATE
    FROM stg.locacao
    WHERE data_retirada_realizada IS NOT NULL

    UNION

    SELECT data_devolucao_realizada::DATE
    FROM stg.locacao
    WHERE data_devolucao_realizada IS NOT NULL

    UNION

    SELECT data_movimentacao::DATE
    FROM stg.movimentacao_patio
    WHERE data_movimentacao IS NOT NULL
)
SELECT
    TO_CHAR(data, 'YYYYMMDD')::INTEGER AS id_tempo,
    data,
    EXTRACT(YEAR FROM data)::INTEGER AS ano,
    EXTRACT(MONTH FROM data)::INTEGER AS mes,
    EXTRACT(DAY FROM data)::INTEGER AS dia,
    EXTRACT(QUARTER FROM data)::INTEGER AS trimestre,
    EXTRACT(ISODOW FROM data)::INTEGER AS dia_semana,
    -- Nomes em português via CASE/array (TO_CHAR 'TMDay'/'TMMonth' depende
    -- do lc_time do servidor e não é determinístico entre ambientes).
    (ARRAY['Segunda-feira','Terça-feira','Quarta-feira','Quinta-feira',
           'Sexta-feira','Sábado','Domingo']
     )[EXTRACT(ISODOW FROM data)::INTEGER] AS nome_dia_semana,
    (ARRAY['Janeiro','Fevereiro','Março','Abril','Maio','Junho',
           'Julho','Agosto','Setembro','Outubro','Novembro','Dezembro']
     )[EXTRACT(MONTH FROM data)::INTEGER] AS nome_mes,
    (EXTRACT(ISODOW FROM data) IN (6, 7)) AS fim_de_semana
FROM datas
WHERE data IS NOT NULL
ORDER BY data;

COMMIT;
