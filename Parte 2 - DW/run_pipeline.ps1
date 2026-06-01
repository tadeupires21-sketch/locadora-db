# =====================================================
# run_pipeline.ps1
# Orquestrador do pipeline ETL — Locadora de Veículos DW
#
# Uso:
#   .\run_pipeline.ps1
#   .\run_pipeline.ps1 -SkipExtract   # pula extração, roda só transform+load
#   .\run_pipeline.ps1 -SkipValidacao # pula queries de validação intermediárias
#
# Pré-requisitos:
#   - psql no PATH (PostgreSQL client)
#   - Variáveis de ambiente configuradas (ver bloco de configuração abaixo)
#     ou arquivo .pgpass em %APPDATA%\postgresql\pgpass.conf
#
# Variáveis de ambiente esperadas:
#   PGHOST     — host do banco (padrão: localhost)
#   PGPORT     — porta (padrão: 5432)
#   PGDATABASE — nome do banco de dados
#   PGUSER     — usuário PostgreSQL
#   PGPASSWORD — senha (ou usar .pgpass)
# =====================================================

param(
    [switch]$SkipExtract,
    [switch]$SkipValidacao
)

# ---- Configuração ----
$ErrorActionPreference = "Stop"
$ROOT = $PSScriptRoot   # pasta raiz do projeto (onde este script está)

function Log {
    param([string]$msg, [string]$level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $cor = switch ($level) {
        "OK"   { "Green"  }
        "WARN" { "Yellow" }
        "ERR"  { "Red"    }
        default { "Cyan"  }
    }
    Write-Host "[$ts] [$level] $msg" -ForegroundColor $cor
}

function Invoke-SQL {
    param([string]$arquivo, [string]$descricao)
    Log "Executando: $descricao"
    $caminho = Join-Path $ROOT $arquivo
    psql -f $caminho
    if ($LASTEXITCODE -ne 0) {
        Log "FALHA em '$descricao' (exit code $LASTEXITCODE). Pipeline interrompido." "ERR"
        exit 1
    }
    Log "$descricao — OK" "OK"
}

# ---- Início ----
$inicio = Get-Date
Log "=== Pipeline ETL — Locadora de Veículos DW ===" "INFO"
Log "Banco: $env:PGDATABASE em $env:PGHOST`:$env:PGPORT" "INFO"

# ---- ETAPA 0: Infraestrutura (schemas + funções) ----
Invoke-SQL "00-infra\00_create_schemas.sql" "Criação de schemas (stg, dw)"
Invoke-SQL "00-infra\01_functions.sql"      "Criação das funções de transformação"

# ---- ETAPA 1: Staging (criar tabelas) ----
Invoke-SQL "01-staging\create_staging.sql" "Criação das tabelas de staging"

# ---- ETAPA 2: Extração ----
if (-not $SkipExtract) {
    Invoke-SQL "01-staging\etl_01_extracao_grupo_tadeu_unificado.sql"  "Extração Grupo 1 (Tadeu)"
    Invoke-SQL "01-staging\etl_02_extracao_grupos_externos_unificado.sql" "Extração Grupos 2, 3 e 4"
} else {
    Log "Extração ignorada (flag -SkipExtract)" "WARN"
}

# ---- ETAPA 3: Validação da staging bruta ----
if (-not $SkipValidacao) {
    Invoke-SQL "02-transform\00_validacao_staging.sql" "Validação da staging bruta"
    Log "Verifique os resultados acima antes de continuar." "WARN"
    $continuar = Read-Host "Continuar com a transformação? (S/N)"
    if ($continuar -ne 'S' -and $continuar -ne 's') {
        Log "Pipeline interrompido pelo operador após validação." "WARN"
        exit 0
    }
}

# ---- ETAPA 4: Transformação (conformance) ----
Invoke-SQL "02-transform\01_transform_dimensoes.sql" "Transform — dimensões conformadas"
Invoke-SQL "02-transform\02_transform_fatos.sql"     "Transform — fatos conformados"

if (-not $SkipValidacao) {
    Invoke-SQL "02-transform\03_validacao_transform.sql" "Validação da camada de conformance"
}

# ---- ETAPA 5: Data Warehouse ----
Invoke-SQL "03-dw\01_create_dw.sql"      "Criação do schema DW (estrela)"
Invoke-SQL "03-dw\02_load_dimensoes.sql" "Carga das dimensões"
Invoke-SQL "03-dw\03_load_fatos.sql"     "Carga dos fatos"
Invoke-SQL "03-dw\04_views_analiticas.sql" "Criação das views analíticas"

# ---- Relatório final ----
$fim = Get-Date
$duracao = ($fim - $inicio).TotalMinutes
Log "=== Pipeline concluído com sucesso em $([math]::Round($duracao, 1)) minuto(s) ===" "OK"
Log "Próxima execução sugerida: $(($fim.AddHours(24)).ToString('yyyy-MM-dd HH:mm'))" "INFO"
