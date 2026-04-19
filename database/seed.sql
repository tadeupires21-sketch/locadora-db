BEGIN;

TRUNCATE TABLE
    locacao_seguro,
    cobranca,
    manutencao,
    foto,
    locacao,
    reserva,
    condutor,
    veiculo,
    seguro,
    patio,
    grupo_veiculo,
    cliente
RESTART IDENTITY CASCADE;

INSERT INTO cliente (id, nome, tipo) VALUES
    (1, 'Ana Souza', 'PF'),
    (2, 'Bruno Almeida', 'PF'),
    (3, 'Carla Martins', 'PF'),
    (4, 'Delta Tecnologia Ltda', 'PJ'),
    (5, 'Expresso Norte Transportes', 'PJ'),
    (6, 'Fernanda Rocha', 'PF'),
    (7, 'Global Consultoria SA', 'PJ'),
    (8, 'Henrique Lima', 'PF');

INSERT INTO condutor (id, cliente_id, cnh, validade, categoria) VALUES
    (1, 1, 'RJ123456789', '2030-05-20', 'B'),
    (2, 2, 'SP987654321', '2028-11-10', 'AB'),
    (3, 3, 'MG456789123', '2027-03-15', 'B'),
    (4, 4, 'RJ555666777', '2029-08-01', 'B'),
    (5, 5, 'PR111222333', '2026-12-30', 'D'),
    (6, 6, 'ES444555666', '2031-01-25', 'B'),
    (7, 7, 'RS777888999', '2028-06-18', 'B'),
    (8, 8, 'BA222333444', '2029-09-09', 'AB');

INSERT INTO grupo_veiculo (id, nome, categoria) VALUES
    (1, 'Economico', 'Hatch compacto'),
    (2, 'Intermediario', 'Sedan compacto'),
    (3, 'SUV', 'Utilitario esportivo'),
    (4, 'Executivo', 'Sedan premium'),
    (5, 'Utilitario', 'Carga leve');

INSERT INTO veiculo (id, placa, modelo, status, grupo_id) VALUES
    (1, 'ABC1D23', 'Fiat Mobi Like 1.0', 'disponivel', 1),
    (2, 'DEF4G56', 'Renault Kwid Zen 1.0', 'alugado', 1),
    (3, 'GHI7J89', 'Hyundai HB20 Comfort 1.0', 'disponivel', 2),
    (4, 'JKL2M34', 'Toyota Corolla XEI 2.0', 'alugado', 4),
    (5, 'MNO5P67', 'Jeep Renegade Sport 1.3', 'manutencao', 3),
    (6, 'PQR8S90', 'Chevrolet Tracker LT 1.0', 'disponivel', 3),
    (7, 'STU3V45', 'Volkswagen Virtus Comfortline', 'disponivel', 2),
    (8, 'VWX6Y78', 'Fiat Fiorino Endurance', 'manutencao', 5),
    (9, 'YZA9B01', 'Honda Civic Touring 1.5', 'disponivel', 4),
    (10, 'BCD2E34', 'Citroen Jumpy Cargo', 'alugado', 5);

INSERT INTO patio (id, nome, cidade) VALUES
    (1, 'Centro Rio', 'Rio de Janeiro'),
    (2, 'Galeao Aeroporto', 'Rio de Janeiro'),
    (3, 'Congonhas Aeroporto', 'Sao Paulo'),
    (4, 'Centro Belo Horizonte', 'Belo Horizonte'),
    (5, 'Curitiba Batel', 'Curitiba');

INSERT INTO reserva (id, cliente_id, grupo_id, data_inicio, data_fim) VALUES
    (1, 1, 1, '2026-04-01', '2026-04-05'),
    (2, 2, 2, '2026-04-03', '2026-04-08'),
    (3, 4, 4, '2026-04-10', '2026-04-12'),
    (4, 5, 5, '2026-04-15', '2026-04-20'),
    (5, 6, 3, '2026-05-01', '2026-05-07'),
    (6, 7, 2, '2026-05-10', '2026-05-14'),
    (7, 8, 1, '2026-05-12', '2026-05-12');

INSERT INTO locacao (
    id,
    reserva_id,
    veiculo_id,
    patio_retirada_id,
    patio_devolucao_id,
    data_retirada,
    data_devolucao
) VALUES
    (1, 1, 2, 1, 2, '2026-04-01 09:30:00', '2026-04-05 17:45:00'),
    (2, 2, 3, 3, 3, '2026-04-03 08:00:00', '2026-04-08 10:15:00'),
    (3, 3, 4, 2, 1, '2026-04-10 14:20:00', NULL),
    (4, 4, 10, 5, 5, '2026-04-15 07:50:00', NULL),
    (5, NULL, 7, 4, 4, '2026-04-18 11:00:00', '2026-04-18 19:30:00'),
    (6, NULL, 9, 1, 3, '2026-04-19 10:00:00', NULL);

INSERT INTO cobranca (id, locacao_id, valor, status, data_pagamento) VALUES
    (1, 1, 520.00, 'pago', '2026-04-05'),
    (2, 2, 780.50, 'pago', '2026-04-08'),
    (3, 3, 950.00, 'pendente', NULL),
    (4, 4, 1250.00, 'pendente', NULL),
    (5, 5, 160.00, 'cancelado', NULL),
    (6, 6, 430.00, 'pendente', NULL);

INSERT INTO seguro (id, tipo, valor) VALUES
    (1, 'Basico', 35.00),
    (2, 'Completo', 75.00),
    (3, 'Terceiros', 45.00),
    (4, 'Vidros e pneus', 25.00);

INSERT INTO locacao_seguro (locacao_id, seguro_id) VALUES
    (1, 1),
    (1, 3),
    (2, 2),
    (3, 2),
    (3, 4),
    (4, 1),
    (4, 3),
    (6, 2),
    (6, 3);

INSERT INTO foto (id, veiculo_id, url, tipo) VALUES
    (1, 1, 'https://example.com/frota/fiat-mobi-frente.jpg', 'frente'),
    (2, 1, 'https://example.com/frota/fiat-mobi-lateral.jpg', 'lateral'),
    (3, 2, 'https://example.com/frota/renault-kwid-frente.jpg', 'frente'),
    (4, 3, 'https://example.com/frota/hb20-frente.jpg', 'frente'),
    (5, 4, 'https://example.com/frota/corolla-frente.jpg', 'frente'),
    (6, 5, 'https://example.com/frota/renegade-dano-parachoque.jpg', 'vistoria'),
    (7, 6, 'https://example.com/frota/tracker-frente.jpg', 'frente'),
    (8, 8, 'https://example.com/frota/fiorino-manutencao.jpg', 'vistoria'),
    (9, 9, 'https://example.com/frota/civic-frente.jpg', 'frente'),
    (10, 10, 'https://example.com/frota/jumpy-cargo-frente.jpg', 'frente');

INSERT INTO manutencao (id, veiculo_id, data, descricao) VALUES
    (1, 5, '2026-04-12', 'Troca de para-choque dianteiro e revisao apos avaria.'),
    (2, 8, '2026-04-14', 'Revisao preventiva de freios e suspensao.'),
    (3, 2, '2026-03-25', 'Troca de oleo e filtro.'),
    (4, 4, '2026-03-28', 'Alinhamento, balanceamento e revisao dos pneus.'),
    (5, 10, '2026-04-01', 'Inspecao do compartimento de carga.');

SELECT setval('cliente_id_seq', (SELECT MAX(id) FROM cliente));
SELECT setval('condutor_id_seq', (SELECT MAX(id) FROM condutor));
SELECT setval('grupo_veiculo_id_seq', (SELECT MAX(id) FROM grupo_veiculo));
SELECT setval('veiculo_id_seq', (SELECT MAX(id) FROM veiculo));
SELECT setval('reserva_id_seq', (SELECT MAX(id) FROM reserva));
SELECT setval('patio_id_seq', (SELECT MAX(id) FROM patio));
SELECT setval('locacao_id_seq', (SELECT MAX(id) FROM locacao));
SELECT setval('cobranca_id_seq', (SELECT MAX(id) FROM cobranca));
SELECT setval('seguro_id_seq', (SELECT MAX(id) FROM seguro));
SELECT setval('foto_id_seq', (SELECT MAX(id) FROM foto));
SELECT setval('manutencao_id_seq', (SELECT MAX(id) FROM manutencao));

COMMIT;
