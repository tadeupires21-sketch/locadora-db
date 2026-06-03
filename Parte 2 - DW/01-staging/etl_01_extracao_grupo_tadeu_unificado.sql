-- =====================================================
-- Grupo:
--   Tadeu Belfort Neto              DRE 119034813
--   Vicente Alves                   DRE 120044148
--   João Pedro de Lacerda           DRE 116076670
-- Arquivo: etl_01_extracao_grupo_tadeu.sql
-- Descrição: Extração ETL — Grupo Tadeu (fonte 1/4)
--            Lê do OLTP transacional e carrega na
--            área de staging do DWH.
--
-- Banco: PostgreSQL
-- Agendamento sugerido: diário, às 02:00h
--   (via pg_cron, cron do SO + psql, ou Airflow)
--
-- NOTA: substituir as referências oltp_g1.* pelo schema
--   ou conexão real do OLTP do grupo. No PostgreSQL,
--   acesso a outro banco se faz via postgres_fdw
--   (foreign data wrapper) ou dblink. Aqui assume-se
--   que as tabelas fonte estão acessíveis no schema oltp_g1.
--
-- PRÉ-REQUISITO: as tabelas stg.* já devem existir.
--   O DDL é responsabilidade EXCLUSIVA de create_staging.sql.
--   Este script NÃO cria nem recria tabelas — fazê-lo destruiria
--   os índices definidos em create_staging.sql e poderia divergir
--   do schema canônico. Aqui apenas TRUNCATE + INSERT.
-- =====================================================

-- Garante o charset correto na sessão. Importante porque G2/G3
-- vêm de MySQL (frequentemente latin1) via FDW/réplica; sem isso,
-- acentos podem chegar corrompidos já na staging.
SET client_encoding TO 'UTF8';


-- =====================================================
-- PASSO 1 — Carga incremental para staging
--
-- Estratégia de janela temporal:
--   1ª execução (log vazio)  → fallback de 7 dias para não perder dados
--   Execuções seguintes      → usa o timestamp da última extração bem-sucedida
--
-- Isso elimina o risco de gap: se o job falhar e só reexecutar após
-- 26+ horas, os registros NÃO são perdidos (a janela de 25h fixada antes
-- causaria esse problema).
-- =====================================================

-- Clientes (carga full — tabela pequena, sem campo de alteração)
TRUNCATE TABLE stg.cliente;
INSERT INTO stg.cliente
    (src_id, nome, tipo, cidade, grupo_fonte)
SELECT q.*, 1::SMALLINT AS grupo_fonte
FROM (
SELECT id, nome, tipo, cidade
FROM oltp_g1.cliente
) q;

-- Condutores (carga full)
TRUNCATE TABLE stg.condutor;
INSERT INTO stg.condutor
    (src_id, src_cliente_id, nome, cnh, validade, categoria, grupo_fonte)
SELECT q.*, 1::SMALLINT AS grupo_fonte
FROM (
SELECT id, cliente_id, nome, cnh, validade, categoria
FROM oltp_g1.condutor
) q;

-- Grupos de veículo (carga full — tabela de referência)
TRUNCATE TABLE stg.grupo_veiculo;
INSERT INTO stg.grupo_veiculo
    (src_id, nome, categoria, diaria, grupo_fonte)
SELECT q.*, 1::SMALLINT AS grupo_fonte
FROM (
SELECT id, nome, categoria, diaria
FROM oltp_g1.grupo_veiculo
) q;

-- Veículos (carga full — detecta mudança de status)
TRUNCATE TABLE stg.veiculo;
INSERT INTO stg.veiculo
    (src_id, placa, chassi, modelo, marca, cor,
     tipo_mecanizacao, ar_condicionado, adaptado_cadeirante,
     status, src_grupo_id, src_empresa_id, nome_empresa, grupo_fonte)
SELECT q.*, 1::SMALLINT AS grupo_fonte
FROM (
SELECT v.id, v.placa, v.chassi, v.modelo, v.marca, v.cor,
    v.tipo_mecanizacao, v.ar_condicionado, v.adaptado_cadeirante,
    v.status, v.grupo_id, v.empresa_id, e.nome
FROM oltp_g1.veiculo v
JOIN oltp_g1.empresa_locadora e ON e.id = v.empresa_id
) q;

-- Pátios + vagas (capacidade calculada na transformação)
TRUNCATE TABLE stg.patio;
INSERT INTO stg.patio
    (src_id, nome, cidade, grupo_fonte)
SELECT q.*, 1::SMALLINT AS grupo_fonte
FROM (
SELECT id, nome, cidade
FROM oltp_g1.patio
) q;

TRUNCATE TABLE stg.vaga;
INSERT INTO stg.vaga
    (codigo, src_patio_id, status, grupo_fonte)
SELECT q.*, 1::SMALLINT AS grupo_fonte
FROM (
SELECT codigo, patio_id, status
FROM oltp_g1.vaga
) q;

-- Reservas — incremental por data_inicio + mudanças de status
-- A janela usa o último run bem-sucedido registrado no log, com fallback
-- de 7 dias para evitar gap em caso de falha prolongada do job.
TRUNCATE TABLE stg.reserva;
INSERT INTO stg.reserva
    (src_id, src_cliente_id, src_grupo_id,
     src_patio_retirada_id, src_patio_devolucao_id,
     data_inicio, data_fim, status, grupo_fonte)
SELECT q.*, 1::SMALLINT AS grupo_fonte
FROM (
SELECT id, cliente_id, grupo_id,
    patio_retirada_id, patio_devolucao_id,
    data_inicio, data_fim, status
FROM oltp_g1.reserva
WHERE data_inicio >= (
        -- Baseline: última extração bem-sucedida ou 7 dias atrás como fallback
        SELECT COALESCE(
            MAX(dt_extracao) - INTERVAL '1 hour',  -- sobreposição de 1h para cobrir race conditions
            NOW() - INTERVAL '7 days'
        )
        FROM stg.log_extracao
        WHERE grupo_fonte = 1
          AND tabela_stg = 'reserva'
          AND status = 'OK'
    )::DATE
   OR status IN ('cancelada', 'espera')
) q;

-- Locações — incremental por l.created_at + abertas (sem devolução)
-- Sempre traz locações abertas (sem data_devolucao_realizada) independente
-- do período, garantindo que nenhuma locação em andamento seja perdida.
TRUNCATE TABLE stg.locacao;
INSERT INTO stg.locacao
    (src_id, src_reserva_id, src_veiculo_id, src_condutor_id, src_cliente_id,
     src_patio_retirada_id, src_patio_devolucao_id,
     data_retirada_prevista, data_retirada_realizada,
     data_devolucao_prevista, data_devolucao_realizada,
     km_entrega, km_devolucao,
     estado_entrega, estado_devolucao, created_at, grupo_fonte)
SELECT q.*, 1::SMALLINT AS grupo_fonte
FROM (
SELECT l.id, l.reserva_id, l.veiculo_id, l.condutor_id, c.cliente_id,
    l.patio_retirada_id, patio_devolucao_id,
    l.data_retirada_prevista, l.data_retirada_realizada,
    l.data_devolucao_prevista, l.data_devolucao_realizada,
    l.km_entrega, l.km_devolucao,
    l.estado_entrega, l.estado_devolucao, l.created_at
FROM oltp_g1.locacao l
JOIN oltp_g1.condutor c ON c.id = l.condutor_id
WHERE l.created_at >= (
        -- Baseline: última extração bem-sucedida ou 7 dias atrás como fallback
        SELECT COALESCE(
            MAX(dt_extracao) - INTERVAL '1 hour',
            NOW() - INTERVAL '7 days'
        )
        FROM stg.log_extracao
        WHERE grupo_fonte = 1
          AND tabela_stg = 'locacao'
          AND status = 'OK'
    )
   OR (l.data_devolucao_realizada IS NULL
       AND l.data_retirada_realizada IS NOT NULL)
) q;

-- Cobranças — pendentes + pagas desde a última extração
TRUNCATE TABLE stg.cobranca;
INSERT INTO stg.cobranca
    (src_id, src_locacao_id, valor, status, data_pagamento, grupo_fonte)
SELECT q.*, 1::SMALLINT AS grupo_fonte
FROM (
SELECT id, locacao_id, valor, status, data_pagamento
FROM oltp_g1.cobranca
WHERE status = 'pendente'
   OR data_pagamento >= (
        -- Baseline: última extração bem-sucedida ou 7 dias atrás como fallback
        SELECT COALESCE(
            MAX(dt_extracao) - INTERVAL '1 hour',
            NOW() - INTERVAL '7 days'
        )
        FROM stg.log_extracao
        WHERE grupo_fonte = 1
          AND tabela_stg = 'cobranca'
          AND status = 'OK'
    )::DATE
) q;

-- Movimentações entre pátios — incremental por data_movimentacao
TRUNCATE TABLE stg.movimentacao_patio;
INSERT INTO stg.movimentacao_patio
    (src_id, src_veiculo_id, src_origem_id,
     src_destino_id, data_movimentacao, motivo, grupo_fonte)
SELECT q.*, 1::SMALLINT AS grupo_fonte
FROM (
SELECT id, veiculo_id, origem_patio_id,
    destino_patio_id, data_movimentacao, motivo
FROM oltp_g1.movimentacao_patio
WHERE data_movimentacao >= (
        -- Baseline: última extração bem-sucedida ou 7 dias atrás como fallback
        SELECT COALESCE(
            MAX(dt_extracao) - INTERVAL '1 hour',
            NOW() - INTERVAL '7 days'
        )
        FROM stg.log_extracao
        WHERE grupo_fonte = 1
          AND tabela_stg = 'movimentacao_patio'
          AND status = 'OK'
    )
) q;


-- =====================================================
-- PASSO 2 — Log de controle de extração
--
-- A tabela log_extracao cumpre dois papéis:
--   1. Auditoria: registra contagem de linhas por tabela/grupo/run.
--   2. Baseline incremental: o status 'OK' é usado nos WHERE das
--      extrações seguintes para calcular a janela temporal.
--
-- Registra o resultado desta execução com status OK
INSERT INTO stg.log_extracao (grupo_fonte, tabela_stg, qtd_registros, status)
VALUES
    (1, 'cliente',           (SELECT COUNT(*) FROM stg.cliente),            'OK'),
    (1, 'condutor',          (SELECT COUNT(*) FROM stg.condutor),           'OK'),
    (1, 'grupo_veiculo',     (SELECT COUNT(*) FROM stg.grupo_veiculo),      'OK'),
    (1, 'veiculo',           (SELECT COUNT(*) FROM stg.veiculo),            'OK'),
    (1, 'patio',             (SELECT COUNT(*) FROM stg.patio),              'OK'),
    (1, 'reserva',           (SELECT COUNT(*) FROM stg.reserva),            'OK'),
    (1, 'locacao',           (SELECT COUNT(*) FROM stg.locacao),            'OK'),
    (1, 'cobranca',          (SELECT COUNT(*) FROM stg.cobranca),           'OK'),
    (1, 'movimentacao_patio',(SELECT COUNT(*) FROM stg.movimentacao_patio), 'OK');

-- =====================================================
-- AGENDAMENTO SUGERIDO
-- =====================================================
-- Via pg_cron (extensão):
--   SELECT cron.schedule('etl_extracao_g1', '0 2 * * *',
--          'psql -f etl_01_extracao_grupo_tadeu.sql');
--
-- Escalonar os grupos para evitar concorrência de I/O:
--   G1 → 02:00h | G2 → 02:30h | G3 → 03:00h | G4 → 03:30h
-- =====================================================