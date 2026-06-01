-- =====================================================
-- Nome: Tadeu Belfort Neto
-- DRE: 119034813
-- Arquivo: 00_fixtures_oltp_g1.sql
-- Descrição: Dataset sintético da fonte OLTP do Grupo 1.
--
-- Cria o schema oltp_g1 com as tabelas/colunas exatas que
-- etl_01_extracao_grupo_tadeu_unificado.sql lê, e popula com
-- casos de teste — incluindo casos-limite propositais:
--   • cliente com nome nulo            → testa imputação
--   • veículo com placa nula           → testa imputação de placa
--   • veículo com status desconhecido  → testa domínio
--   • locação atrasada                 → testa atraso/multa
--   • locação devolvida antes do prazo → testa atraso = 0
--   • locação com km invertido         → testa km_rodado = 0
--   • reserva cancelada e desconhecida → testa domínio de status
--
-- Datas usam CURRENT_DATE - N para cair na janela incremental
-- (fallback de 7 dias na 1ª execução), tornando o teste determinístico.
--
-- ⚠️ Apenas para testes. NÃO usar em produção.
-- =====================================================

DROP SCHEMA IF EXISTS oltp_g1 CASCADE;
CREATE SCHEMA oltp_g1;

-- ---- Empresa ----
CREATE TABLE oltp_g1.empresa_locadora (id INT PRIMARY KEY, nome TEXT);
INSERT INTO oltp_g1.empresa_locadora VALUES (1, 'Locadora Tadeu');

-- ---- Cliente (cliente 3 com nome nulo de propósito) ----
CREATE TABLE oltp_g1.cliente (
    id INT PRIMARY KEY, nome TEXT, tipo TEXT, cidade TEXT
);
INSERT INTO oltp_g1.cliente VALUES
    (1, 'Ana Souza',  'PF', 'Rio de Janeiro'),
    (2, 'Empresa XYZ','PJ', 'Niterói'),
    (3, NULL,         'PF', 'Rio de Janeiro');   -- nome nulo → imputado

-- ---- Condutor ----
CREATE TABLE oltp_g1.condutor (
    id INT PRIMARY KEY, cliente_id INT, nome TEXT,
    cnh TEXT, validade DATE, categoria TEXT
);
INSERT INTO oltp_g1.condutor VALUES
    (1, 1, 'Ana Souza',   '11122233344', '2030-01-01', 'B'),
    (2, 2, 'João Motora', '55566677788', '2028-06-30', 'D');

-- ---- Grupo de veículo (com diária para a multa) ----
CREATE TABLE oltp_g1.grupo_veiculo (
    id INT PRIMARY KEY, nome TEXT, categoria TEXT, diaria NUMERIC(10,2)
);
INSERT INTO oltp_g1.grupo_veiculo VALUES
    (1, 'Economico', 'Hatch', 100.00),
    (2, 'Executivo', 'Sedan', 250.00);

-- ---- Veículo (3 com placa nula; 2 com status desconhecido) ----
CREATE TABLE oltp_g1.veiculo (
    id INT PRIMARY KEY, placa TEXT, chassi TEXT, modelo TEXT, marca TEXT,
    cor TEXT, tipo_mecanizacao TEXT, ar_condicionado BOOLEAN,
    adaptado_cadeirante BOOLEAN, status TEXT, grupo_id INT, empresa_id INT
);
INSERT INTO oltp_g1.veiculo VALUES
    (1, 'abc-1d23', 'CHASSI001', 'Mobi',   'Fiat',  'Branco', 'manual',    TRUE,  FALSE, 'disponivel',  1, 1),
    (2, 'xyz9e88',  'CHASSI002', 'Corolla', 'Toyota','Preto',  'automatico',TRUE,  FALSE, 'status_zoado', 2, 1),  -- status desconhecido
    (3, NULL,       'CHASSI003', 'Argo',    'Fiat',  'Prata',  'manual',    FALSE, TRUE,  'alugado',     1, 1);   -- placa nula

-- ---- Pátio + Vaga ----
CREATE TABLE oltp_g1.patio (id INT PRIMARY KEY, nome TEXT, cidade TEXT);
INSERT INTO oltp_g1.patio VALUES
    (1, 'Patio Centro', 'Rio de Janeiro'),
    (2, 'Patio Zona Sul','Rio de Janeiro');

CREATE TABLE oltp_g1.vaga (codigo TEXT, patio_id INT, status TEXT);
INSERT INTO oltp_g1.vaga VALUES
    ('A1', 1, 'livre'), ('A2', 1, 'ocupada'), ('B1', 2, 'livre');

-- ---- Reserva (cancelada, desconhecida, ativa) ----
CREATE TABLE oltp_g1.reserva (
    id INT PRIMARY KEY, cliente_id INT, grupo_id INT,
    patio_retirada_id INT, patio_devolucao_id INT,
    data_inicio TIMESTAMP, data_fim TIMESTAMP, status TEXT
);
INSERT INTO oltp_g1.reserva VALUES
    (1, 1, 1, 1, 1, CURRENT_DATE - 3, CURRENT_DATE - 1, 'confirmada'),
    (2, 2, 2, 1, 2, CURRENT_DATE - 2, CURRENT_DATE,     'cancelada'),
    (3, 1, 1, 2, 2, CURRENT_DATE - 2, CURRENT_DATE - 1, 'estado_invalido');  -- domínio

-- ---- Locação ----
-- L1: atrasada — retirada D-5, prev devolução D-3, real devolução D-1 → atraso 2, dias_realizados 5
-- L2: devolvida antes — prev devolução D-1, real devolução D-3        → atraso 0
-- L3: km invertido — entrega 5000, devolução 4000                     → km_rodado 0
CREATE TABLE oltp_g1.locacao (
    id INT PRIMARY KEY, reserva_id INT, veiculo_id INT, condutor_id INT,
    patio_retirada_id INT, patio_devolucao_id INT,
    data_retirada_prevista TIMESTAMP, data_retirada_realizada TIMESTAMP,
    data_devolucao_prevista TIMESTAMP, data_devolucao_realizada TIMESTAMP,
    km_entrega INT, km_devolucao INT, estado_entrega TEXT, estado_devolucao TEXT,
    created_at TIMESTAMP
);
INSERT INTO oltp_g1.locacao VALUES
    (1, 1, 1, 1, 1, 1,
     CURRENT_DATE - 5, CURRENT_DATE - 5,
     CURRENT_DATE - 3, CURRENT_DATE - 1,
     10000, 10350, 'ok', 'ok', CURRENT_DATE - 5),
    (2, 2, 2, 2, 1, 2,
     CURRENT_DATE - 5, CURRENT_DATE - 5,
     CURRENT_DATE - 1, CURRENT_DATE - 3,
     20000, 20100, 'ok', 'ok', CURRENT_DATE - 5),
    (3, 3, 3, 1, 2, 2,
     CURRENT_DATE - 4, CURRENT_DATE - 4,
     CURRENT_DATE - 2, CURRENT_DATE - 1,
     5000, 4000, 'ok', 'avariado', CURRENT_DATE - 4);   -- km invertido

-- ---- Cobrança (L1 paga, L2 paga, L3 pendente) ----
CREATE TABLE oltp_g1.cobranca (
    id INT PRIMARY KEY, locacao_id INT, valor NUMERIC(10,2),
    status TEXT, data_pagamento DATE
);
INSERT INTO oltp_g1.cobranca VALUES
    (1, 1, 500.00, 'pago',     CURRENT_DATE - 1),
    (2, 2, 750.00, 'pago',     CURRENT_DATE - 3),
    (3, 3, 300.00, 'pendente', NULL);

-- ---- Movimentação entre pátios ----
CREATE TABLE oltp_g1.movimentacao_patio (
    id INT PRIMARY KEY, veiculo_id INT, origem_patio_id INT,
    destino_patio_id INT, data_movimentacao TIMESTAMP, motivo TEXT
);
INSERT INTO oltp_g1.movimentacao_patio VALUES
    (1, 1, 1, 2, CURRENT_DATE - 2, 'realocacao'),
    (2, 3, 2, 1, CURRENT_DATE - 1, 'manutencao');
