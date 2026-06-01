ARQUIVOS OBSOLETOS — NÃO EXECUTAR

Estes arquivos foram substituídos pela versão refatorada do pipeline
e estão aqui apenas para referência histórica.

etl_03_transformacao_unificado.sql
  → Substituído por: 02-transform/01_transform_dimensoes.sql
                     02-transform/02_transform_fatos.sql

etl_04_carga_dw_unificado.sql
  → Substituído por: 03-dw/02_load_dimensoes.sql
                     03-dw/03_load_fatos.sql
  → ATENÇÃO: contém typo "NSERT" na linha 26 (sintaxe inválida).

Pipeline correto: ver run_pipeline.ps1 na raiz do projeto.
