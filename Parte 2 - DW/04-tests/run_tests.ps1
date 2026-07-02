# =====================================================
# run_tests.ps1
# Suite de testes do pipeline ETL - Locadora de Veiculos DW
#
# Uso:
#   .\04-tests\run_tests.ps1                 # roda tudo
#   .\04-tests\run_tests.ps1 -OnlyUnit       # so testes unitarios
#
# Pre-requisitos: psql no PATH + variaveis PG* (ver run_pipeline.ps1).
#
# ATENCAO: Cria um schema oltp_g1 SINTETICO e RECONSTROI o schema dw.
#    Use um banco de TESTE, nunca o de producao.
#
# Cada etapa roda com ON_ERROR_STOP=1: qualquer RAISE EXCEPTION
# de uma assercao aborta a suite com codigo de saida != 0.
# =====================================================

param(
    [switch]$OnlyUnit
)

$ErrorActionPreference = "Stop"
$ROOT = Split-Path $PSScriptRoot -Parent   # raiz do projeto (pasta acima de 04-tests)

# Corrige exibicao de caracteres UTF-8 no console do Windows
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Garante que o psql leia os arquivos SQL como UTF-8, independente
# da codificacao padrao do Windows (WIN1252). Sem isso, acentos nos
# comentarios e strings SQL causam erro de conversao de encoding.
$env:PGCLIENTENCODING = "UTF8"

function Run-SQL {
    param([string]$arquivo, [string]$descricao)
    Write-Host "-> $descricao" -ForegroundColor Cyan
    psql -v ON_ERROR_STOP=1 -f (Join-Path $ROOT $arquivo)
    if ($LASTEXITCODE -ne 0) {
        Write-Host "X FALHOU: $descricao" -ForegroundColor Red
        exit 1
    }
}

Write-Host "=== Testes - Locadora DW ===" -ForegroundColor Yellow

# ---- Infra minima necessaria para os testes unitarios ----
Run-SQL "00-infra\00_create_schemas.sql"  "Schemas"
Run-SQL "00-infra\01_functions.sql"        "Funcoes de transformacao"

# ---- 1. TESTES UNITARIOS (nao dependem de dados) ----
Run-SQL "04-tests\01_test_unit_funcoes.sql" "Testes unitarios das funcoes"

if ($OnlyUnit) {
    Write-Host "=== Apenas unitarios concluidos ===" -ForegroundColor Green
    exit 0
}

# ---- 2. MONTAGEM DO AMBIENTE DE INTEGRACAO (somente Grupo 1) ----
Run-SQL "04-tests\00_fixtures_oltp_g1.sql"                         "Fixtures OLTP G1"
Run-SQL "01-staging\create_staging.sql"                            "Cria staging"
Run-SQL "01-staging\etl_01_extracao_grupo_tadeu_unificado.sql"    "Extracao G1"
Run-SQL "02-transform\01_transform_dimensoes.sql"                 "Transform dimensoes"
Run-SQL "02-transform\02_transform_fatos.sql"                     "Transform fatos"
Run-SQL "03-dw\01_create_dw.sql"                                  "Cria DW"
Run-SQL "03-dw\02_load_dimensoes.sql"                             "Carga dimensoes"
Run-SQL "03-dw\03_load_fatos.sql"                                 "Carga fatos"

# ---- 3. ASSERCOES SOBRE O DW CARREGADO ----
Run-SQL "04-tests\02_test_integracao.sql"       "Teste de integracao"
Run-SQL "04-tests\03_test_qualidade_dados.sql"  "Validacoes de qualidade de dados"

Write-Host "=== TODOS OS TESTES PASSARAM ===" -ForegroundColor Green
