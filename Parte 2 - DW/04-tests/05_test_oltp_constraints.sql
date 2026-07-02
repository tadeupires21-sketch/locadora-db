-- =====================================================
-- Arquivo: 05_test_oltp_constraints.sql
-- Descricao: Testes de constraints do OLTP que devem falhar.
--
-- O teste passa quando cada erro esperado e capturado.
-- Nenhum dado fica persistido: tudo roda em transacao com ROLLBACK.
-- =====================================================

\echo '== OLTP: constraints esperadas =='

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.expect_sqlstate(rotulo TEXT, comando TEXT, esperado TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
    v_state TEXT;
    v_msg   TEXT;
BEGIN
    BEGIN
        EXECUTE comando;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_state = RETURNED_SQLSTATE,
            v_msg = MESSAGE_TEXT;

        IF v_state = esperado THEN
            RAISE NOTICE 'OK [%]: SQLSTATE % capturado (%)', rotulo, v_state, v_msg;
            RETURN;
        END IF;

        RAISE EXCEPTION 'FALHOU [%]: SQLSTATE obtido %, esperado %. Mensagem: %',
            rotulo, v_state, esperado, v_msg;
    END;

    RAISE EXCEPTION 'FALHOU [%]: comando deveria falhar com SQLSTATE %, mas executou sem erro.',
        rotulo, esperado;
END;
$$;

DO $$
DECLARE
    v_empresa_id     INTEGER;
    v_cliente_id     INTEGER;
    v_condutor_id    INTEGER;
    v_grupo_id       INTEGER;
    v_veiculo_id     INTEGER;
    v_patio_ret_id   INTEGER;
    v_patio_dev_id   INTEGER;
    v_reserva_id     INTEGER;
    v_locacao_id     INTEGER;
BEGIN
    INSERT INTO empresa_locadora (nome, cnpj)
    VALUES ('Empresa Constraints OLTP', '99.999.999/0001-92')
    RETURNING id INTO v_empresa_id;

    INSERT INTO cliente (nome, tipo, cidade)
    VALUES ('Cliente Constraints OLTP', 'PF', 'Rio de Janeiro')
    RETURNING id INTO v_cliente_id;

    INSERT INTO condutor (cliente_id, nome, cnh, validade, categoria)
    VALUES (v_cliente_id, 'Condutor Constraints OLTP', 'CNH-TESTE-0002', DATE '2031-01-01', 'B')
    RETURNING id INTO v_condutor_id;

    INSERT INTO grupo_veiculo (nome, categoria)
    VALUES ('Grupo Constraints OLTP', 'Sedan')
    RETURNING id INTO v_grupo_id;

    INSERT INTO patio (nome, cidade)
    VALUES ('Patio Constraints Retirada', 'Rio de Janeiro')
    RETURNING id INTO v_patio_ret_id;

    INSERT INTO patio (nome, cidade)
    VALUES ('Patio Constraints Devolucao', 'Niteroi')
    RETURNING id INTO v_patio_dev_id;

    INSERT INTO veiculo (
        placa, chassi, modelo, marca, cor, tipo_mecanizacao,
        status, grupo_id, empresa_id
    )
    VALUES (
        'TST2A02', 'CHASSI-TESTE-OLTP-002', 'Corolla', 'Toyota', 'Branco',
        'automatico', 'disponivel', v_grupo_id, v_empresa_id
    )
    RETURNING id INTO v_veiculo_id;

    INSERT INTO reserva (
        cliente_id, grupo_id, patio_retirada_id, patio_devolucao_id,
        data_inicio, data_fim, status
    )
    VALUES (
        v_cliente_id, v_grupo_id, v_patio_ret_id, v_patio_dev_id,
        DATE '2026-07-01', DATE '2026-07-05', 'confirmada'
    )
    RETURNING id INTO v_reserva_id;

    INSERT INTO locacao (
        reserva_id, veiculo_id, condutor_id, patio_retirada_id, patio_devolucao_id,
        data_retirada_prevista, data_retirada_realizada,
        data_devolucao_prevista, km_entrega
    )
    VALUES (
        v_reserva_id, v_veiculo_id, v_condutor_id, v_patio_ret_id, v_patio_dev_id,
        TIMESTAMP '2026-07-01 09:00:00', TIMESTAMP '2026-07-01 09:15:00',
        TIMESTAMP '2026-07-05 18:00:00', 20000
    )
    RETURNING id INTO v_locacao_id;

    PERFORM pg_temp.expect_sqlstate(
        'cliente com tipo invalido',
        'INSERT INTO cliente (nome, tipo, cidade) VALUES (''Cliente Tipo Invalido'', ''XX'', ''Rio'')',
        '23514'
    );

    PERFORM pg_temp.expect_sqlstate(
        'veiculo com tipo_mecanizacao invalido',
        format(
            'INSERT INTO veiculo (placa, chassi, modelo, marca, cor, tipo_mecanizacao, status, grupo_id, empresa_id)
             VALUES (%L, %L, %L, %L, %L, %L, %L, %s, %s)',
            'BAD1A01', 'CHASSI-BAD-MEC-001', 'Modelo', 'Marca', 'Preto',
            'cvt', 'disponivel', v_grupo_id, v_empresa_id
        ),
        '23514'
    );

    PERFORM pg_temp.expect_sqlstate(
        'veiculo com status invalido',
        format(
            'INSERT INTO veiculo (placa, chassi, modelo, marca, cor, tipo_mecanizacao, status, grupo_id, empresa_id)
             VALUES (%L, %L, %L, %L, %L, %L, %L, %s, %s)',
            'BAD1A02', 'CHASSI-BAD-STATUS-001', 'Modelo', 'Marca', 'Preto',
            'manual', 'vendido', v_grupo_id, v_empresa_id
        ),
        '23514'
    );

    PERFORM pg_temp.expect_sqlstate(
        'reserva com data_fim menor que data_inicio',
        format(
            'INSERT INTO reserva (cliente_id, grupo_id, patio_retirada_id, patio_devolucao_id, data_inicio, data_fim, status)
             VALUES (%s, %s, %s, %s, DATE %L, DATE %L, %L)',
            v_cliente_id, v_grupo_id, v_patio_ret_id, v_patio_dev_id,
            '2026-07-10', '2026-07-09', 'ativa'
        ),
        '23514'
    );

    PERFORM pg_temp.expect_sqlstate(
        'locacao com devolucao prevista menor que retirada prevista',
        format(
            'INSERT INTO locacao (veiculo_id, condutor_id, patio_retirada_id, patio_devolucao_id, data_retirada_prevista, data_devolucao_prevista)
             VALUES (%s, %s, %s, %s, TIMESTAMP %L, TIMESTAMP %L)',
            v_veiculo_id, v_condutor_id, v_patio_ret_id, v_patio_dev_id,
            '2026-07-10 10:00:00', '2026-07-09 10:00:00'
        ),
        '23514'
    );

    PERFORM pg_temp.expect_sqlstate(
        'locacao com retirada realizada e km_entrega NULL',
        format(
            'INSERT INTO locacao (veiculo_id, condutor_id, patio_retirada_id, patio_devolucao_id, data_retirada_prevista, data_retirada_realizada, data_devolucao_prevista, km_entrega)
             VALUES (%s, %s, %s, %s, TIMESTAMP %L, TIMESTAMP %L, TIMESTAMP %L, NULL)',
            v_veiculo_id, v_condutor_id, v_patio_ret_id, v_patio_dev_id,
            '2026-07-10 10:00:00', '2026-07-10 10:05:00', '2026-07-12 10:00:00'
        ),
        '23514'
    );

    PERFORM pg_temp.expect_sqlstate(
        'cobranca com valor negativo',
        format(
            'INSERT INTO cobranca (locacao_id, valor, status) VALUES (%s, -1.00, %L)',
            v_locacao_id, 'pendente'
        ),
        '23514'
    );

    PERFORM pg_temp.expect_sqlstate(
        'seguro com valor negativo',
        'INSERT INTO seguro (tipo, valor) VALUES (''Seguro Negativo'', -10.00)',
        '23514'
    );

    PERFORM pg_temp.expect_sqlstate(
        'movimentacao_patio com origem igual ao destino',
        format(
            'INSERT INTO movimentacao_patio (veiculo_id, origem_patio_id, destino_patio_id, motivo)
             VALUES (%s, %s, %s, %L)',
            v_veiculo_id, v_patio_ret_id, v_patio_ret_id, 'Origem igual destino'
        ),
        '23514'
    );

    PERFORM pg_temp.expect_sqlstate(
        'duplicar placa de veiculo',
        format(
            'INSERT INTO veiculo (placa, chassi, modelo, marca, cor, tipo_mecanizacao, status, grupo_id, empresa_id)
             VALUES (%L, %L, %L, %L, %L, %L, %L, %s, %s)',
            'TST2A02', 'CHASSI-DUP-PLACA-001', 'Modelo', 'Marca', 'Azul',
            'manual', 'disponivel', v_grupo_id, v_empresa_id
        ),
        '23505'
    );

    PERFORM pg_temp.expect_sqlstate(
        'duplicar CNH de condutor',
        format(
            'INSERT INTO condutor (cliente_id, nome, cnh, validade, categoria)
             VALUES (%s, %L, %L, DATE %L, %L)',
            v_cliente_id, 'Condutor CNH Duplicada', 'CNH-TESTE-0002', '2032-01-01', 'B'
        ),
        '23505'
    );

    PERFORM pg_temp.expect_sqlstate(
        'usar mesma reserva em duas locacoes',
        format(
            'INSERT INTO locacao (reserva_id, veiculo_id, condutor_id, patio_retirada_id, patio_devolucao_id, data_retirada_prevista, data_devolucao_prevista)
             VALUES (%s, %s, %s, %s, %s, TIMESTAMP %L, TIMESTAMP %L)',
            v_reserva_id, v_veiculo_id, v_condutor_id, v_patio_ret_id, v_patio_dev_id,
            '2026-07-20 10:00:00', '2026-07-22 10:00:00'
        ),
        '23505'
    );

    RAISE NOTICE 'OK: todas as constraints esperadas foram acionadas.';
END $$;

ROLLBACK;

