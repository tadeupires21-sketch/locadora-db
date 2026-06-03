-- =====================================================
-- seed_test.sql — Dataset de testes para o schema OLTP da Locadora
-- Autor: gerado para suporte a testes automatizados
--
-- Como usar:
--   psql -d locadora_test -f seed_test.sql
--
-- Pré-requisito: schema criado via schema.sql
--   psql -d locadora_test -f schema.sql
--   psql -d locadora_test -f seed_test.sql
--
-- Para limpar após os testes, execute a seção TEARDOWN
-- no final deste arquivo ou rode diretamente:
--   psql -d locadora_test -c "\i seed_test.sql" (inclui teardown)
--
-- Cenários cobertos:
--   [1] Locações ativas (sem data_devolucao_realizada)
--   [2] Locações encerradas (com data_devolucao_realizada)
--   [3] Locações com atraso e multa (devolvido após data_devolucao_prevista)
--   [4] Clientes sem nenhum histórico de aluguel (IDs 8–10)
--   [5] Cobrança pendente, paga e cancelada
--   [6] Veículo em manutenção (indisponível para locação)
--   [7] Locação walk-in (sem reserva prévia)
--   [8] Movimentação entre pátios
-- =====================================================

BEGIN;

-- =====================================================
-- EMPRESA
-- =====================================================

INSERT INTO empresa_locadora (id, nome, cnpj) OVERRIDING SYSTEM VALUE VALUES
    (1, 'Locadora Carioca Ltda',       '12.345.678/0001-90'),
    (2, 'Fluminense Rent-a-Car S/A',   '98.765.432/0001-11');

SELECT setval(pg_get_serial_sequence('empresa_locadora','id'), 2);

-- =====================================================
-- GRUPO DE VEÍCULO
-- =====================================================

INSERT INTO grupo_veiculo (id, nome, categoria) OVERRIDING SYSTEM VALUE VALUES
    (1, 'Econômico',    'Hatch'),
    (2, 'Intermediário','Sedan'),
    (3, 'Executivo',    'SUV'),
    (4, 'Pickup',       'Utilitário');

SELECT setval(pg_get_serial_sequence('grupo_veiculo','id'), 4);

-- =====================================================
-- PÁTIO
-- =====================================================

INSERT INTO patio (id, nome, cidade) OVERRIDING SYSTEM VALUE VALUES
    (1, 'Pátio Centro',        'Rio de Janeiro'),
    (2, 'Pátio Barra',         'Rio de Janeiro'),
    (3, 'Pátio Aeroporto GIG', 'Rio de Janeiro'),
    (4, 'Pátio Niterói',       'Niterói');

SELECT setval(pg_get_serial_sequence('patio','id'), 4);

-- =====================================================
-- VAGA
-- =====================================================

INSERT INTO vaga (codigo, patio_id, status) VALUES
    ('A1', 1, 'livre'),
    ('A2', 1, 'ocupada'),
    ('A3', 1, 'livre'),
    ('B1', 2, 'livre'),
    ('B2', 2, 'ocupada'),
    ('C1', 3, 'livre'),
    ('C2', 3, 'livre'),
    ('D1', 4, 'livre'),
    ('D2', 4, 'ocupada');

-- =====================================================
-- ACESSÓRIO
-- =====================================================

INSERT INTO acessorio (id, nome) OVERRIDING SYSTEM VALUE VALUES
    (1, 'GPS'),
    (2, 'Cadeira de Bebê'),
    (3, 'Rack de Teto'),
    (4, 'Wi-Fi Portátil');

SELECT setval(pg_get_serial_sequence('acessorio','id'), 4);

-- =====================================================
-- VEÍCULO
-- =====================================================
-- V1–V3: econômicos (empresa 1)
-- V4–V5: intermediários (empresa 1)
-- V6–V7: executivos (empresa 2)
-- V8:    pickup (empresa 2)
-- V9:    em manutenção — não pode ser locado [cenário 6]
-- V10:   disponível sem histórico de locação

INSERT INTO veiculo (id, placa, chassi, modelo, marca, cor, tipo_mecanizacao, ar_condicionado, status, adaptado_cadeirante, grupo_id, empresa_id) OVERRIDING SYSTEM VALUE VALUES
    (1,  'BRA2E19', 'CHSBRA2E19001', 'Argo',      'Fiat',       'Branco',   'manual',     TRUE,  'disponivel',  FALSE, 1, 1),
    (2,  'RIO3F22', 'CHSRIO3F22002', 'HB20',      'Hyundai',    'Prata',    'manual',     TRUE,  'alugado',     FALSE, 1, 1),
    (3,  'NIL4G33', 'CHSNIL4G33003', 'Mobi',      'Fiat',       'Vermelho', 'manual',     FALSE, 'disponivel',  TRUE,  1, 1),
    (4,  'CAR5H44', 'CHSCAR5H44004', 'Corolla',   'Toyota',     'Preto',    'automatico', TRUE,  'alugado',     FALSE, 2, 1),
    (5,  'SOL6I55', 'CHSSOL6I55005', 'Civic',     'Honda',      'Cinza',    'automatico', TRUE,  'disponivel',  FALSE, 2, 1),
    (6,  'EXE7J66', 'CHSEXE7J66006', 'Tiguan',    'Volkswagen', 'Branco',   'automatico', TRUE,  'alugado',     FALSE, 3, 2),
    (7,  'VIP8K77', 'CHSVIP8K77007', 'RAV4',      'Toyota',     'Azul',     'automatico', TRUE,  'disponivel',  FALSE, 3, 2),
    (8,  'UTL9L88', 'CHSUTL9L88008', 'Amarok',    'Volkswagen', 'Prata',    'automatico', TRUE,  'disponivel',  FALSE, 4, 2),
    (9,  'MNT0M99', 'CHSMNT0M99009', 'Onix',      'Chevrolet',  'Azul',     'manual',     TRUE,  'manutencao',  FALSE, 1, 1),
    (10, 'NEW1N10', 'CHSNEW1N10010', 'Polo',      'Volkswagen', 'Branco',   'automatico', TRUE,  'disponivel',  FALSE, 2, 1);

SELECT setval(pg_get_serial_sequence('veiculo','id'), 10);

-- =====================================================
-- VEICULO_ACESSÓRIO
-- =====================================================

INSERT INTO veiculo_acessorio (veiculo_id, acessorio_id) VALUES
    (1, 1),  -- Argo: GPS
    (4, 1),  -- Corolla: GPS
    (4, 2),  -- Corolla: Cadeira de Bebê
    (6, 1),  -- Tiguan: GPS
    (6, 4),  -- Tiguan: Wi-Fi Portátil
    (7, 1),  -- RAV4: GPS
    (7, 3);  -- RAV4: Rack de Teto

-- =====================================================
-- CLIENTE
-- C1–C7:  clientes com histórico de locação
-- C8–C10: clientes sem nenhum aluguel [cenário 4]
-- =====================================================

INSERT INTO cliente (id, nome, tipo, cidade) OVERRIDING SYSTEM VALUE VALUES
    (1,  'Ana Beatriz Souza',       'PF', 'Rio de Janeiro'),
    (2,  'Carlos Drummond Filho',   'PF', 'Niterói'),
    (3,  'Mariana Ferreira Lima',   'PF', 'Rio de Janeiro'),
    (4,  'TechCorp Consultoria Ltda','PJ','Rio de Janeiro'),
    (5,  'Roberto Alves Pinto',     'PF', 'São Gonçalo'),
    (6,  'Juliana Costa Ramos',     'PF', 'Rio de Janeiro'),
    (7,  'Distribuidora Norte S/A', 'PJ', 'Petrópolis'),
    -- Clientes sem histórico de aluguel:
    (8,  'Pedro Henrique Vargas',   'PF', 'Maricá'),
    (9,  'Patrícia Melo Nunes',     'PF', 'Rio de Janeiro'),
    (10, 'LogiExpress Transportes', 'PJ', 'Duque de Caxias');

SELECT setval(pg_get_serial_sequence('cliente','id'), 10);

-- =====================================================
-- CONDUTOR
-- =====================================================

INSERT INTO condutor (id, cliente_id, nome, cnh, validade, categoria, telefone) OVERRIDING SYSTEM VALUE VALUES
    (1,  1, 'Ana Beatriz Souza',       '00111222333', (NOW() + INTERVAL '4 years')::DATE, 'B',  '21988880001'),
    (2,  2, 'Carlos Drummond Filho',   '00444555666', (NOW() + INTERVAL '2 years')::DATE, 'B',  '21988880002'),
    (3,  3, 'Mariana Ferreira Lima',   '00777888999', (NOW() + INTERVAL '3 years')::DATE, 'B',  '21988880003'),
    (4,  4, 'José Marcos da Silva',    '01122334455', (NOW() + INTERVAL '5 years')::DATE, 'D',  '21988880004'),
    (5,  5, 'Roberto Alves Pinto',     '02233445566', (NOW() + INTERVAL '1 year')::DATE,  'B',  '21988880005'),
    (6,  6, 'Juliana Costa Ramos',     '03344556677', (NOW() + INTERVAL '3 years')::DATE, 'AB', '21988880006'),
    (7,  7, 'Fábio Mendes Torres',     '04455667788', (NOW() + INTERVAL '2 years')::DATE, 'D',  '21988880007'),
    -- Condutor adicional do cliente 1 (motorista diferente)
    (8,  1, 'Lucas Souza Pereira',     '05566778899', (NOW() + INTERVAL '6 years')::DATE, 'B',  '21988880008');

SELECT setval(pg_get_serial_sequence('condutor','id'), 8);

-- =====================================================
-- SEGURO
-- =====================================================

INSERT INTO seguro (id, tipo, valor) OVERRIDING SYSTEM VALUE VALUES
    (1, 'Básico',           89.90),
    (2, 'Proteção Total',  189.90),
    (3, 'Premium',         299.90);

SELECT setval(pg_get_serial_sequence('seguro','id'), 3);

-- =====================================================
-- RESERVA
-- =====================================================

INSERT INTO reserva (id, cliente_id, grupo_id, patio_retirada_id, patio_devolucao_id, data_inicio, data_fim, status) OVERRIDING SYSTEM VALUE VALUES
    -- R1: confirmada → originou locação encerrada no prazo [cenário 2]
    (1,  1, 1, 1, 1, (NOW() - INTERVAL '20 days')::DATE, (NOW() - INTERVAL '15 days')::DATE, 'confirmada'),
    -- R2: confirmada → originou locação com atraso [cenário 3]
    (2,  2, 2, 1, 2, (NOW() - INTERVAL '14 days')::DATE, (NOW() - INTERVAL '10 days')::DATE, 'confirmada'),
    -- R3: confirmada → originou locação ATIVA (em andamento) [cenário 1]
    (3,  3, 3, 3, 3, (NOW() - INTERVAL '3 days')::DATE,  (NOW() + INTERVAL '4 days')::DATE,  'confirmada'),
    -- R4: cancelada — nunca virou locação
    (4,  4, 2, 1, 2, (NOW() + INTERVAL '5 days')::DATE,  (NOW() + INTERVAL '10 days')::DATE, 'cancelada'),
    -- R5: confirmada → originou locação ativa PJ [cenário 1]
    (5,  4, 3, 2, 3, (NOW() - INTERVAL '2 days')::DATE,  (NOW() + INTERVAL '5 days')::DATE,  'confirmada'),
    -- R6: confirmada → originou locação encerrada com cobrança paga
    (6,  5, 1, 4, 1, (NOW() - INTERVAL '30 days')::DATE, (NOW() - INTERVAL '25 days')::DATE, 'confirmada'),
    -- R7: confirmada → locação com atraso severo [cenário 3]
    (7,  6, 2, 2, 2, (NOW() - INTERVAL '12 days')::DATE, (NOW() - INTERVAL '7 days')::DATE,  'confirmada'),
    -- R8: ativa (ainda não virou locação)
    (8,  7, 4, 1, 4, (NOW() + INTERVAL '2 days')::DATE,  (NOW() + INTERVAL '6 days')::DATE,  'ativa'),
    -- R9: em espera
    (9,  1, 3, 3, 2, (NOW() + INTERVAL '10 days')::DATE, (NOW() + INTERVAL '14 days')::DATE, 'espera');

SELECT setval(pg_get_serial_sequence('reserva','id'), 9);

-- =====================================================
-- LOCAÇÃO
-- =====================================================
-- L1:  encerrada no prazo,  cobrança paga           [cenário 2]
-- L2:  encerrada com atraso de 4 dias, paga         [cenário 3]
-- L3:  ATIVA (sem devolução realizada)              [cenário 1]
-- L4:  ATIVA PJ (sem devolução realizada)           [cenário 1]
-- L5:  encerrada, cobrança paga (walk-in, sem res.) [cenário 7]
-- L6:  encerrada com atraso de 7 dias, pendente     [cenário 3 + cobrança pendente]
-- L7:  encerrada, cobrança cancelada

INSERT INTO locacao (
    id, reserva_id, veiculo_id, condutor_id,
    patio_retirada_id, patio_devolucao_id,
    data_retirada_prevista, data_retirada_realizada,
    data_devolucao_prevista, data_devolucao_realizada,
    estado_entrega, estado_devolucao,
    km_entrega, km_devolucao
) OVERRIDING SYSTEM VALUE VALUES
    -- L1: encerrada no prazo (devolvida 1 dia antes)
    (1, 1, 2, 1, 1, 1,
     NOW() - INTERVAL '20 days', NOW() - INTERVAL '20 days',
     NOW() - INTERVAL '15 days', NOW() - INTERVAL '16 days',
     'Sem avarias', 'Sem avarias',
     32000, 32480),

    -- L2: encerrada com atraso de 4 dias (prevista D-10, devolvida D-6)
    (2, 2, 4, 2, 1, 2,
     NOW() - INTERVAL '14 days', NOW() - INTERVAL '14 days',
     NOW() - INTERVAL '10 days', NOW() - INTERVAL '6 days',
     'Sem avarias', 'Pequeno arranhão para-choque',
     55000, 55920),

    -- L3: ATIVA — retirado há 3 dias, previsto devolver em 4 dias
    (3, 3, 6, 3, 3, 3,
     NOW() - INTERVAL '3 days', NOW() - INTERVAL '3 days',
     NOW() + INTERVAL '4 days', NULL,
     'Sem avarias', NULL,
     71000, NULL),

    -- L4: ATIVA PJ — retirado há 2 dias, previsto devolver em 5 dias
    (4, 5, 7, 4, 2, 3,
     NOW() - INTERVAL '2 days', NOW() - INTERVAL '2 days',
     NOW() + INTERVAL '5 days', NULL,
     'Sem avarias', NULL,
     18500, NULL),

    -- L5: walk-in (sem reserva), encerrada no prazo, cobrança paga
    (5, NULL, 8, 5, 4, 1,
     NOW() - INTERVAL '30 days', NOW() - INTERVAL '30 days',
     NOW() - INTERVAL '25 days', NOW() - INTERVAL '25 days',
     'Sem avarias', 'Sem avarias',
     9800, 10220),

    -- L6: encerrada com atraso de 7 dias (prevista D-7, devolvida hoje), cobrança pendente
    (6, 7, 5, 6, 2, 2,
     NOW() - INTERVAL '12 days', NOW() - INTERVAL '12 days',
     NOW() - INTERVAL '7 days',  NOW(),
     'Sem avarias', 'Pneu com desgaste irregular',
     43000, 43750),

    -- L7: encerrada, cobrança cancelada (cliente cancelou pagamento)
    (7, 6, 1, 7, 4, 1,
     NOW() - INTERVAL '30 days', NOW() - INTERVAL '30 days',
     NOW() - INTERVAL '25 days', NOW() - INTERVAL '26 days',
     'Sem avarias', 'Sem avarias',
     12000, 12310);

SELECT setval(pg_get_serial_sequence('locacao','id'), 7);

-- =====================================================
-- COBRANÇA
-- =====================================================

INSERT INTO cobranca (id, locacao_id, valor, status, data_pagamento) OVERRIDING SYSTEM VALUE VALUES
    -- L1: 5 dias × R$100 = R$500 — pago
    (1, 1,  500.00, 'pago',      (NOW() - INTERVAL '16 days')::DATE),
    -- L2: 4 dias × R$250 + multa 4 dias atraso = R$1.000 + R$1.000 = R$2.000 — pago
    (2, 2, 2000.00, 'pago',      (NOW() - INTERVAL '6 days')::DATE),
    -- L3: ativa, sem cobrança ainda (cobrança gerada na devolução)
    -- L4: ativa, sem cobrança ainda
    -- L5: walk-in, 5 dias × R$250 = R$1.250 — pago
    (3, 5, 1250.00, 'pago',      (NOW() - INTERVAL '25 days')::DATE),
    -- L6: atraso 7 dias × R$250 estimado = multa alta — pendente
    (4, 6, 3500.00, 'pendente',  NULL),
    -- L7: cancelada (disputa)
    (5, 7,  310.00, 'cancelado', NULL);

SELECT setval(pg_get_serial_sequence('cobranca','id'), 5);

-- =====================================================
-- LOCAÇÃO_SEGURO
-- =====================================================

INSERT INTO locacao_seguro (locacao_id, seguro_id) VALUES
    (1, 1),   -- L1: básico
    (2, 2),   -- L2: proteção total
    (3, 3),   -- L3 ativa: premium
    (4, 2),   -- L4 ativa: proteção total
    (5, 1),   -- L5 walk-in: básico
    (6, 2),   -- L6 atraso: proteção total
    (7, 1);   -- L7 cancelada: básico

-- =====================================================
-- FOTO (vistoria de entrega/devolução)
-- =====================================================

INSERT INTO foto (id, veiculo_id, url, tipo) OVERRIDING SYSTEM VALUE VALUES
    (1,  2, 'https://storage.locadora.test/vistoria/v2-entrada-l1.jpg',  'entrada'),
    (2,  2, 'https://storage.locadora.test/vistoria/v2-saida-l1.jpg',    'saida'),
    (3,  4, 'https://storage.locadora.test/vistoria/v4-entrada-l2.jpg',  'entrada'),
    (4,  4, 'https://storage.locadora.test/vistoria/v4-saida-l2.jpg',    'saida'),
    (5,  6, 'https://storage.locadora.test/vistoria/v6-entrada-l3.jpg',  'entrada'),
    (6,  1, 'https://storage.locadora.test/catalogo/v1-externo.jpg',     'catalogo'),
    (7,  5, 'https://storage.locadora.test/catalogo/v5-externo.jpg',     'catalogo'),
    (8,  9, 'https://storage.locadora.test/manutencao/v9-avaria.jpg',    'manutencao');

SELECT setval(pg_get_serial_sequence('foto','id'), 8);

-- =====================================================
-- MANUTENÇÃO
-- =====================================================

INSERT INTO manutencao (id, veiculo_id, data, descricao) OVERRIDING SYSTEM VALUE VALUES
    -- V9 em manutenção ativa [cenário 6]
    (1, 9, (NOW() - INTERVAL '5 days')::DATE, 'Substituição de embreagem — veículo indisponível'),
    -- Revisões preventivas concluídas
    (2, 2, (NOW() - INTERVAL '40 days')::DATE, 'Revisão de 30.000 km — troca de óleo e filtros'),
    (3, 4, (NOW() - INTERVAL '60 days')::DATE, 'Troca de pneus dianteiros'),
    (4, 1, (NOW() - INTERVAL '15 days')::DATE, 'Revisão de 20.000 km');

SELECT setval(pg_get_serial_sequence('manutencao','id'), 4);

-- =====================================================
-- MOVIMENTAÇÃO ENTRE PÁTIOS
-- =====================================================

INSERT INTO movimentacao_patio (id, veiculo_id, origem_patio_id, destino_patio_id, data_movimentacao, motivo) OVERRIDING SYSTEM VALUE VALUES
    (1, 1, 1, 3, NOW() - INTERVAL '18 days', 'Reposicionamento para demanda no aeroporto'),
    (2, 5, 2, 1, NOW() - INTERVAL '10 days', 'Transferência por excesso de frota no Barra'),
    (3, 8, 4, 1, NOW() - INTERVAL '8 days',  'Demanda de pickup no Centro'),
    (4, 3, 1, 4, NOW() - INTERVAL '5 days',  'Reposicionamento para Niterói');

SELECT setval(pg_get_serial_sequence('movimentacao_patio','id'), 4);

COMMIT;

-- =====================================================
-- VERIFICAÇÃO — contagens esperadas por tabela
-- =====================================================
-- Execute após o seed para confirmar integridade dos dados.
-- =====================================================

\echo ''
\echo '=== VERIFICAÇÃO DE CONTAGENS ==='

SELECT 'empresa_locadora'   AS tabela, COUNT(*) AS total, 2  AS esperado, COUNT(*) = 2  AS ok FROM empresa_locadora
UNION ALL
SELECT 'grupo_veiculo',     COUNT(*), 4,  COUNT(*) = 4  FROM grupo_veiculo
UNION ALL
SELECT 'patio',             COUNT(*), 4,  COUNT(*) = 4  FROM patio
UNION ALL
SELECT 'vaga',              COUNT(*), 9,  COUNT(*) = 9  FROM vaga
UNION ALL
SELECT 'acessorio',         COUNT(*), 4,  COUNT(*) = 4  FROM acessorio
UNION ALL
SELECT 'veiculo',           COUNT(*), 10, COUNT(*) = 10 FROM veiculo
UNION ALL
SELECT 'veiculo_acessorio', COUNT(*), 7,  COUNT(*) = 7  FROM veiculo_acessorio
UNION ALL
SELECT 'cliente',           COUNT(*), 10, COUNT(*) = 10 FROM cliente
UNION ALL
SELECT 'condutor',          COUNT(*), 8,  COUNT(*) = 8  FROM condutor
UNION ALL
SELECT 'seguro',            COUNT(*), 3,  COUNT(*) = 3  FROM seguro
UNION ALL
SELECT 'reserva',           COUNT(*), 9,  COUNT(*) = 9  FROM reserva
UNION ALL
SELECT 'locacao',           COUNT(*), 7,  COUNT(*) = 7  FROM locacao
UNION ALL
SELECT 'cobranca',          COUNT(*), 5,  COUNT(*) = 5  FROM cobranca
UNION ALL
SELECT 'locacao_seguro',    COUNT(*), 7,  COUNT(*) = 7  FROM locacao_seguro
UNION ALL
SELECT 'foto',              COUNT(*), 8,  COUNT(*) = 8  FROM foto
UNION ALL
SELECT 'manutencao',        COUNT(*), 4,  COUNT(*) = 4  FROM manutencao
UNION ALL
SELECT 'movimentacao_patio',COUNT(*), 4,  COUNT(*) = 4  FROM movimentacao_patio
ORDER BY tabela;

\echo ''
\echo '=== VERIFICAÇÃO DE CENÁRIOS DE NEGÓCIO ==='

-- [1] Locações ativas (sem devolução realizada)
SELECT 'locacoes_ativas' AS cenario,
       COUNT(*) AS total,
       2 AS esperado,
       COUNT(*) = 2 AS ok
FROM locacao
WHERE data_devolucao_realizada IS NULL;

-- [2] Locações encerradas
SELECT 'locacoes_encerradas' AS cenario,
       COUNT(*) AS total,
       5 AS esperado,
       COUNT(*) = 5 AS ok
FROM locacao
WHERE data_devolucao_realizada IS NOT NULL;

-- [3] Locações com atraso (devolução realizada após a prevista)
SELECT 'locacoes_com_atraso' AS cenario,
       COUNT(*) AS total,
       2 AS esperado,
       COUNT(*) = 2 AS ok
FROM locacao
WHERE data_devolucao_realizada > data_devolucao_prevista;

-- [4] Clientes sem nenhum histórico de aluguel
SELECT 'clientes_sem_locacao' AS cenario,
       COUNT(*) AS total,
       3 AS esperado,
       COUNT(*) = 3 AS ok
FROM cliente c
WHERE NOT EXISTS (
    SELECT 1 FROM reserva r WHERE r.cliente_id = c.id
);

-- [5] Cobranças por status
SELECT status AS cenario, COUNT(*) AS total
FROM cobranca
GROUP BY status
ORDER BY status;

-- [6] Veículo em manutenção
SELECT 'veiculos_em_manutencao' AS cenario,
       COUNT(*) AS total,
       1 AS esperado,
       COUNT(*) = 1 AS ok
FROM veiculo
WHERE status = 'manutencao';

-- =====================================================
-- TEARDOWN — limpar todos os dados após os testes
-- =====================================================
-- Para usar: descomente e execute, ou rode separadamente:
--   psql -d locadora_test -c "$(grep -A999 'TEARDOWN' seed_test.sql | tail -n +2)"
-- =====================================================

-- BEGIN;
-- TRUNCATE TABLE
--     movimentacao_patio,
--     manutencao,
--     foto,
--     locacao_seguro,
--     cobranca,
--     locacao,
--     reserva,
--     vaga,
--     veiculo_acessorio,
--     veiculo,
--     condutor,
--     seguro,
--     acessorio,
--     cliente,
--     patio,
--     grupo_veiculo,
--     empresa_locadora
-- CASCADE;
-- COMMIT;
