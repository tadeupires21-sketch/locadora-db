-- =====================================================
-- Arquivo: 07_test_oltp_consultas.sql
-- Descricao: Consultas uteis de validacao do OLTP.
--
-- Insere uma pequena massa controlada, executa consultas do projeto
-- e valida que retornam os resultados esperados.
-- Tudo e descartado com ROLLBACK ao final.
-- =====================================================

\echo '== OLTP: consultas uteis =='

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.assert_eq(rotulo TEXT, obtido TEXT, esperado TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    IF obtido IS DISTINCT FROM esperado THEN
        RAISE EXCEPTION 'FALHOU [%]: obtido=[%] esperado=[%]', rotulo, obtido, esperado;
    END IF;
END;
$$;

DO $$
DECLARE
    v_empresa_id       INTEGER;
    v_cliente_id       INTEGER;
    v_condutor_id      INTEGER;
    v_grupo_id         INTEGER;
    v_veiculo_id       INTEGER;
    v_patio_ret_id     INTEGER;
    v_patio_dev_id     INTEGER;
    v_reserva_id       INTEGER;
    v_locacao_id       INTEGER;
BEGIN
    INSERT INTO empresa_locadora (nome, cnpj)
    VALUES ('Empresa Consultas OLTP', '99.999.999/0001-94')
    RETURNING id INTO v_empresa_id;

    INSERT INTO cliente (nome, tipo, cidade)
    VALUES ('Cliente Consultas OLTP', 'PJ', 'Rio de Janeiro')
    RETURNING id INTO v_cliente_id;

    INSERT INTO condutor (cliente_id, nome, cnh, validade, categoria)
    VALUES (v_cliente_id, 'Condutor Consultas OLTP', 'CNH-TESTE-0004', DATE '2031-01-01', 'B')
    RETURNING id INTO v_condutor_id;

    INSERT INTO grupo_veiculo (nome, categoria)
    VALUES ('Grupo Consultas OLTP', 'Executivo')
    RETURNING id INTO v_grupo_id;

    INSERT INTO veiculo (
        placa, chassi, modelo, marca, cor, tipo_mecanizacao,
        status, grupo_id, empresa_id
    )
    VALUES (
        'QRY1A01', 'CHASSI-CONSULTAS-OLTP-001', 'Civic', 'Honda', 'Azul',
        'automatico', 'alugado', v_grupo_id, v_empresa_id
    )
    RETURNING id INTO v_veiculo_id;

    INSERT INTO patio (nome, cidade)
    VALUES ('Patio Consultas Retirada', 'Rio de Janeiro')
    RETURNING id INTO v_patio_ret_id;

    INSERT INTO patio (nome, cidade)
    VALUES ('Patio Consultas Devolucao', 'Niteroi')
    RETURNING id INTO v_patio_dev_id;

    INSERT INTO reserva (
        cliente_id, grupo_id, patio_retirada_id, patio_devolucao_id,
        data_inicio, data_fim, status
    )
    VALUES (
        v_cliente_id, v_grupo_id, v_patio_ret_id, v_patio_dev_id,
        DATE '2026-09-01', DATE '2026-09-03', 'confirmada'
    )
    RETURNING id INTO v_reserva_id;

    INSERT INTO locacao (
        reserva_id, veiculo_id, condutor_id, patio_retirada_id, patio_devolucao_id,
        data_retirada_prevista, data_retirada_realizada,
        data_devolucao_prevista, data_devolucao_realizada,
        km_entrega, km_devolucao
    )
    VALUES (
        v_reserva_id, v_veiculo_id, v_condutor_id, v_patio_ret_id, v_patio_dev_id,
        TIMESTAMP '2026-09-01 09:00:00', TIMESTAMP '2026-09-01 09:00:00',
        TIMESTAMP '2026-09-03 18:00:00', TIMESTAMP '2026-09-03 18:30:00',
        30000, 30500
    )
    RETURNING id INTO v_locacao_id;

    INSERT INTO cobranca (locacao_id, valor, status, data_pagamento)
    VALUES (v_locacao_id, 700.00, 'pendente', NULL);

    INSERT INTO movimentacao_patio (
        veiculo_id, origem_patio_id, destino_patio_id, data_movimentacao, motivo
    )
    VALUES (
        v_veiculo_id, v_patio_ret_id, v_patio_dev_id,
        TIMESTAMP '2026-09-04 10:00:00', 'Reposicionamento pos-locacao'
    );

    -- Reservas por patio de retirada.
    PERFORM pg_temp.assert_eq(
        'reservas por patio de retirada',
        (
            SELECT COUNT(*)::TEXT
            FROM (
                SELECT p.nome AS patio_retirada, COUNT(*) AS total_reservas
                FROM reserva r
                JOIN patio p ON p.id = r.patio_retirada_id
                WHERE p.id = v_patio_ret_id
                GROUP BY p.nome
            ) q
        ),
        '1'
    );

    -- Veiculos por empresa e grupo.
    PERFORM pg_temp.assert_eq(
        'veiculos por empresa e grupo',
        (
            SELECT total_veiculos::TEXT
            FROM (
                SELECT e.nome AS empresa, g.nome AS grupo, COUNT(*) AS total_veiculos
                FROM veiculo v
                JOIN empresa_locadora e ON e.id = v.empresa_id
                JOIN grupo_veiculo g ON g.id = v.grupo_id
                WHERE e.id = v_empresa_id AND g.id = v_grupo_id
                GROUP BY e.nome, g.nome
            ) q
        ),
        '1'
    );

    -- Locacoes com cliente, condutor, veiculo e patios.
    PERFORM pg_temp.assert_eq(
        'locacoes com cliente condutor veiculo patios',
        (
            SELECT COUNT(*)::TEXT
            FROM locacao l
            JOIN reserva r ON r.id = l.reserva_id
            JOIN cliente c ON c.id = r.cliente_id
            JOIN condutor cd ON cd.id = l.condutor_id
            JOIN veiculo v ON v.id = l.veiculo_id
            JOIN patio pr ON pr.id = l.patio_retirada_id
            JOIN patio pd ON pd.id = l.patio_devolucao_id
            WHERE l.id = v_locacao_id
              AND c.id = v_cliente_id
              AND cd.id = v_condutor_id
              AND v.id = v_veiculo_id
              AND pr.id = v_patio_ret_id
              AND pd.id = v_patio_dev_id
        ),
        '1'
    );

    -- Movimentacoes entre patios.
    PERFORM pg_temp.assert_eq(
        'movimentacoes entre patios',
        (
            SELECT COUNT(*)::TEXT
            FROM movimentacao_patio mp
            JOIN patio po ON po.id = mp.origem_patio_id
            JOIN patio pd ON pd.id = mp.destino_patio_id
            WHERE mp.veiculo_id = v_veiculo_id
              AND po.id = v_patio_ret_id
              AND pd.id = v_patio_dev_id
        ),
        '1'
    );

    -- Cobranca por locacao.
    PERFORM pg_temp.assert_eq(
        'cobranca por locacao',
        (
            SELECT valor::TEXT
            FROM cobranca
            WHERE locacao_id = v_locacao_id
        ),
        '700.00'
    );

    RAISE NOTICE 'OK: consultas uteis retornaram resultados coerentes.';
END $$;

ROLLBACK;

