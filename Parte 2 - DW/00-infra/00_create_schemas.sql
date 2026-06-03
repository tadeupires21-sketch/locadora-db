-- =====================================================
-- Grupo:
--   Tadeu Belfort Neto              DRE 119034813
--   Vicente Alves                   DRE 120044148
--   João Pedro de Lacerda           DRE 116076670
-- Arquivo: 00_create_schemas.sql
-- Descricao: Inicializacao dos schemas do pipeline ETL.
--
-- EXECUTE ESTE SCRIPT PRIMEIRO, antes de qualquer outro.
-- E seguro rodar multiplas vezes (idempotente via IF NOT EXISTS).
--
-- Schemas criados:
--   stg  - area de staging e conformance (dados brutos + transformados)
--   dw   - Data Warehouse dimensional (esquema estrela final)
-- =====================================================

-- Schema de staging: recebe dados brutos extraidos dos 4 OLTPs
-- e as tabelas conformadas geradas na etapa de transformacao.
CREATE SCHEMA IF NOT EXISTS stg;
COMMENT ON SCHEMA stg IS
    'Area de staging e conformance do pipeline ETL. '
    'Contem tabelas brutas (stg.<entidade>) e conformadas (stg.conf_*). '
    'Nunca expor diretamente a usuarios de negocio.';

-- Schema do DW: esquema estrela com dimensoes e fatos finais,
-- prontos para consumo analitico e geracao de relatorios.
CREATE SCHEMA IF NOT EXISTS dw;
COMMENT ON SCHEMA dw IS
    'Data Warehouse dimensional - esquema estrela. '
    'Contem dim_* (dimensoes) e fato_* (fatos). '
    'Fonte oficial para relatorios e dashboards.';

-- =====================================================
-- Verificacao (opcional): confirmar criacao
-- =====================================================
SELECT schema_name,
       pg_size_pretty(pg_catalog.pg_database_size(current_database())) AS db_size
FROM information_schema.schemata
WHERE schema_name IN ('stg', 'dw')
ORDER BY schema_name;
