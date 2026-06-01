# =====================================================
# run_tests.ps1
# Suíte de testes do pipeline ETL — Locadora de Veículos DW
#
# Uso:
#   .\04-tests\run_tests.ps1                 # roda tudo
#   .\04-tests\run_tests.ps1 -OnlyUnit       # só testes unitários
#
# Pré-requisitos: psql no PATH + variáveis PG* (ver run_pipeline.ps1).
#
# ⚠️ Cria um schema oltp_g1 SINTÉTICO e RECONSTRÓI o schema dw.
#    Use um banco de TESTE, nunca o de produção.
#
# Cada etapa roda com ON_ERROR_STOP=1: qualquer RAISE EXCEPTION
# de uma asserção aborta a suíte com código de saída != 0.
# =====================================================

param(
    [switch]$OnlyUnit
)

$ErrorActionPreference = "Stop"
$ROOT = Split-Path $PSScriptRoot -Parent   # raiz do projeto (pasta acima de 04-tests)

function Run-SQL {
    param([string]$arquivo, [string]$descricao)
    Write-Host "→ $descricao" -ForegroundColor Cyan
    psql -v ON_ERROR_STOP=1 -f (Join-Path $ROOT $arquivo)
    if ($LASTEXITCODE -ne 0) {
        Write-Host "✗ FALHOU: $descricao" -ForegroundColor Red
        exit 1
    }
}

Write-Host "=== Testes — Locadora DW ===" -ForegroundColor Yellow

# ---- Infra mínima necessária para os testes unitários ----
Run-SQL "00-infra\00_create_schemas.sql"  "Schemas"
Run-SQL "00-infra\01_functions.sql"        "Funções de transformação"

# ---- 1. TESTES UNITÁRIOS (não dependem de dados) ----
Run-SQL "04-tests\01_test_unit_funcoes.sql" "Testes unitários das funções"

if ($OnlyUnit) {
    Write-Host "=== Apenas unitários concluídos ===" -ForegroundColor Green
    exit 0
}

# ---- 2. MONTAGEM DO AMBIENTE DE INTEGRAÇÃO (somente Grupo 1) ----
Run-SQL "04-tests\00_fixtures_oltp_g1.sql"                          "Fixtures OLTP G1"
Run-SQL "01-staging\create_staging.sql"                             "Cria staging"
Run-SQL "01-staging\etl_01_extracao_grupo_tadeu_unificado.sql"     "Extração G1"
Run-SQL "02-transform\01_transform_dimensoes.sql"                  "Transform dimensões"
Run-SQL "02-transform\02_transform_fatos.sql"                      "Transform fatos"
Run-SQL "03-dw\01_create_dw.sql"                                   "Cria DW"
Run-SQL "03-dw\02_load_dimensoes.sql"                              "Carga dimensões"
Run-SQL "03-dw\03_load_fatos.sql"                                  "Carga fatos"

# ---- 3. ASSERÇÕES SOBRE O DW CARREGADO ----
Run-SQL "04-tests\02_test_integracao.sql"        "Teste de integração"
Run-SQL "04-tests\03_test_qualidade_dados.sql"   "Validações de qualidade de dados"

Write-Host "=== ✅ TODOS OS TESTES PASSARAM ===" -ForegroundColor Green
