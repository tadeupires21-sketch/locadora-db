# =====================================================
# run_oltp_tests.ps1
# Suite de testes do schema OLTP - Locadora de Veiculos
#
# Uso:
#   .\Parte 2 - DW\04-tests\run_oltp_tests.ps1
#   .\Parte 2 - DW\04-tests\run_oltp_tests.ps1 -PsqlPath "C:\Program Files\PostgreSQL\18\bin\psql.exe"
#
# Pre-requisitos:
#   - psql no PATH
#   - variaveis PG* configuradas para um banco de TESTE
#   - schema OLTP ja criado no banco alvo
#
# Este runner nao executa schema.sql e nao altera estruturas do banco.
# Cada arquivo SQL abre transacao e faz ROLLBACK ao final.
# =====================================================

param(
    [string]$PsqlPath
)

$ErrorActionPreference = "Stop"
$ROOT = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

# Corrige exibicao de caracteres UTF-8 no console do Windows
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Garante que o psql leia os arquivos SQL como UTF-8, independente
# da codificacao padrao do Windows (WIN1252). Sem isso, acentos nos
# comentarios e strings SQL causam erro de conversao de encoding.
$env:PGCLIENTENCODING = "UTF8"

function Resolve-Psql {
    if ($PsqlPath) {
        if (-not (Test-Path $PsqlPath)) {
            throw "psql nao encontrado em: $PsqlPath"
        }
        return $PsqlPath
    }

    $cmd = Get-Command psql -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $candidatos = @(
        "C:\Program Files\PostgreSQL\18\bin\psql.exe",
        "C:\Program Files\PostgreSQL\14\bin\psql.exe",
        "C:\Program Files\PostgreSQL\18\pgAdmin 4\runtime\psql.exe"
    )

    foreach ($candidato in $candidatos) {
        if (Test-Path $candidato) {
            return $candidato
        }
    }

    throw "psql nao encontrado no PATH nem nos caminhos padrao do PostgreSQL."
}

$PSQL = Resolve-Psql

function Run-SQL {
    param([string]$arquivo, [string]$descricao)

    $caminho = Join-Path $ROOT $arquivo
    Write-Host "-> $descricao" -ForegroundColor Cyan

    & $PSQL -w -v ON_ERROR_STOP=1 -f $caminho
    if ($LASTEXITCODE -ne 0) {
        Write-Host "X FALHOU: $descricao" -ForegroundColor Red
        exit 1
    }
}

Write-Host "=== Testes OLTP - Locadora ===" -ForegroundColor Yellow
Write-Host "Banco: $env:PGDATABASE em $env:PGHOST`:$env:PGPORT" -ForegroundColor DarkGray

Run-SQL "Parte 2 - DW\04-tests\04_test_oltp_carga_minima.sql" "Carga minima valida"
Run-SQL "Parte 2 - DW\04-tests\05_test_oltp_constraints.sql" "Constraints esperadas"
Run-SQL "Parte 2 - DW\04-tests\06_test_oltp_on_delete.sql" "Regras ON DELETE"
Run-SQL "Parte 2 - DW\04-tests\07_test_oltp_consultas.sql" "Consultas uteis"

Write-Host "=== TODOS OS TESTES OLTP PASSARAM ===" -ForegroundColor Green
