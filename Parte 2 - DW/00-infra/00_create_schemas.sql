-- =====================================================
-- Nome: Tadeu Belfort Neto
-- DRE: 119034813
-- Arquivo: 00_create_schemas.sql
-- Descrição: Inicialização dos schemas do pipeline ETL.
--
-- EXECUTE ESTE SCRIPT PRIMEIRO, antes de qualquer outro.
-- É seguro rodar múltiplas vezes (idempotente via IF NOT EXISTS).
--
-- Schemas criados:
--   stg  — área de staging e conformance (dados brutos + transformados)
--   dw   — Data Warehouse dimensional (esquema estrela final)
-- =====================================================

-- Schema de staging: recebe dados brutos extraídos dos 4 OLTPs
-- e as tabelas conformadas geradas na etapa de transformação.
CREATE SCHEMA IF NOT EXISTS stg;
COMMENT ON SCHEMA stg IS
    'Área de staging e conformance do pipeline ETL. '
    'Contém tabelas brutas (stg.<entidade>) e conformadas (stg.conf_*). '
    'Nunca expor diretamente a usuários de negócio.';

-- Schema do DW: esquema estrela com dimensões e fatos finais,
-- prontos para consumo analítico e geração de relatórios.
CREATE SCHEMA IF NOT EXISTS dw;
COMMENT ON SCHEMA dw IS
    'Data Warehouse dimensional — esquema estrela. '
    'Contém dim_* (dimensões) e fato_* (fatos). '
    'Fonte oficial para relatórios e dashboards.';

-- =====================================================
-- Verificação (opcional): confirmar criação
-- =====================================================
SELECT schema_name,
       pg_size_pretty(pg_catalog.pg_database_size(current_database())) AS db_size
FROM information_schema.schemata
WHERE schema_name IN ('stg', 'dw')
ORDER BY schema_name;
