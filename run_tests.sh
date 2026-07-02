# salve como run_tests.sh
set -e


psql -w -v ON_ERROR_STOP=1 -f "Parte 2 - DW/00-infra/00_create_schemas.sql"
psql -w -v ON_ERROR_STOP=1 -f "Parte 2 - DW/00-infra/01_functions.sql"
psql -w -v ON_ERROR_STOP=1 -f "Parte 2 - DW/04-tests/01_test_unit_funcoes.sql"
psql -w -v ON_ERROR_STOP=1 -f "Parte 2 - DW/04-tests/00_fixtures_oltp_g1.sql"
psql -w -v ON_ERROR_STOP=1 -f "Parte 2 - DW/01-staging/create_staging.sql"
psql -w -v ON_ERROR_STOP=1 -f "Parte 2 - DW/01-staging/etl_01_extracao_grupo_tadeu_unificado.sql"
psql -w -v ON_ERROR_STOP=1 -f "Parte 2 - DW/02-transform/01_transform_dimensoes.sql"
psql -w -v ON_ERROR_STOP=1 -f "Parte 2 - DW/02-transform/02_transform_fatos.sql"
psql -w -v ON_ERROR_STOP=1 -f "Parte 2 - DW/03-dw/01_create_dw.sql"
psql -w -v ON_ERROR_STOP=1 -f "Parte 2 - DW/03-dw/02_load_dimensoes.sql"
psql -w -v ON_ERROR_STOP=1 -f "Parte 2 - DW/03-dw/03_load_fatos.sql"
psql -w -v ON_ERROR_STOP=1 -f "Parte 2 - DW/04-tests/02_test_integracao.sql"
psql -w -v ON_ERROR_STOP=1 -f "Parte 2 - DW/04-tests/03_test_qualidade_dados.sql"

echo "=== TODOS OS TESTES PASSARAM ==="