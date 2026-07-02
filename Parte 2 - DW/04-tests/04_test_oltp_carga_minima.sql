-- =====================================================
-- Arquivo: 04_test_oltp_carga_minima.sql
-- Descricao: Teste de carga minima valida do schema OLTP.
--
-- Este teste nao altera o schema. Todos os dados inseridos ficam
-- dentro de uma transacao e sao removidos com ROLLBACK ao final.
-- =====================================================

\echo '== OLTP: carga minima valida =='

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
    v_cobranca_id      INTEGER;
    v_seguro_id        INTEGER;
    v_acessorio_id     INTEGER;
    v_foto_id          INTEGER;
    v_manutencao_id    INTEGER;
    v_movimentacao_id  INTEGER;
BEGIN
    INSERT INTO empresa_locadora (nome, cnpj)
    VALUES ('Locadora Teste OLTP', '99.999.999/0001-91')
    RETURNING id INTO v_empresa_id;

    INSERT INTO cliente (nome, tipo, cidade)
    VALUES ('Cliente Teste OLTP', 'PF', 'Rio de Janeiro')
    RETURNING id INTO v_cliente_id;

    INSERT INTO condutor (cliente_id, nome, cnh, validade, categoria, telefone)
    VALUES (v_cliente_id, 'Condutor Teste OLTP', 'CNH-TESTE-0001', DATE '2030-12-31', 'B', '21999990000')
    RETURNING id INTO v_condutor_id;

    INSERT INTO grupo_veiculo (nome, categoria)
    VALUES ('Economico Teste', 'Hatch')
    RETURNING id INTO v_grupo_id;

    INSERT INTO veiculo (
        placa, chassi, modelo, marca, cor, tipo_mecanizacao,
        ar_condicionado, status, adaptado_cadeirante, grupo_id, empresa_id
    )
    VALUES (
        'TST1A01', 'CHASSI-TESTE-OLTP-001', 'Onix', 'Chevrolet', 'Prata',
        'manual', TRUE, 'disponivel', FALSE, v_grupo_id, v_empresa_id
    )
    RETURNING id INTO v_veiculo_id;

    INSERT INTO patio (nome, cidade)
    VALUES ('Patio Retirada Teste', 'Rio de Janeiro')
    RETURNING id INTO v_patio_ret_id;

    INSERT INTO patio (nome, cidade)
    VALUES ('Patio Devolucao Teste', 'Niteroi')
    RETURNING id INTO v_patio_dev_id;

    INSERT INTO vaga (codigo, patio_id, status)
    VALUES ('T-001', v_patio_ret_id, 'livre'),
           ('T-002', v_patio_dev_id, 'ocupada');

    INSERT INTO reserva (
        cliente_id, grupo_id, patio_retirada_id, patio_devolucao_id,
        data_inicio, data_fim, status
    )
    VALUES (
        v_cliente_id, v_grupo_id, v_patio_ret_id, v_patio_dev_id,
        DATE '2026-06-10', DATE '2026-06-15', 'confirmada'
    )
    RETURNING id INTO v_reserva_id;

    INSERT INTO locacao (
        reserva_id, veiculo_id, condutor_id, patio_retirada_id, patio_devolucao_id,
        data_retirada_prevista, data_retirada_realizada,
        data_devolucao_prevista, data_devolucao_realizada,
        estado_entrega, estado_devolucao, km_entrega, km_devolucao
    )
    VALUES (
        v_reserva_id, v_veiculo_id, v_condutor_id, v_patio_ret_id, v_patio_dev_id,
        TIMESTAMP '2026-06-10 09:00:00', TIMESTAMP '2026-06-10 09:10:00',
        TIMESTAMP '2026-06-15 18:00:00', TIMESTAMP '2026-06-15 17:40:00',
        'Sem avarias', 'Sem avarias', 10000, 10420
    )
    RETURNING id INTO v_locacao_id;

    INSERT INTO cobranca (locacao_id, valor, status, data_pagamento)
    VALUES (v_locacao_id, 950.00, 'pago', DATE '2026-06-15')
    RETURNING id INTO v_cobranca_id;

    INSERT INTO seguro (tipo, valor)
    VALUES ('Protecao completa teste', 120.00)
    RETURNING id INTO v_seguro_id;

    INSERT INTO locacao_seguro (locacao_id, seguro_id)
    VALUES (v_locacao_id, v_seguro_id);

    INSERT INTO acessorio (nome)
    VALUES ('GPS Teste OLTP')
    RETURNING id INTO v_acessorio_id;

    INSERT INTO veiculo_acessorio (veiculo_id, acessorio_id)
    VALUES (v_veiculo_id, v_acessorio_id);

    INSERT INTO foto (veiculo_id, url, tipo)
    VALUES (v_veiculo_id, 'https://example.test/foto-veiculo.jpg', 'vistoria')
    RETURNING id INTO v_foto_id;

    INSERT INTO manutencao (veiculo_id, data, descricao)
    VALUES (v_veiculo_id, DATE '2026-05-20', 'Troca de oleo preventiva')
    RETURNING id INTO v_manutencao_id;

    INSERT INTO movimentacao_patio (
        veiculo_id, origem_patio_id, destino_patio_id, data_movimentacao, motivo
    )
    VALUES (
        v_veiculo_id, v_patio_ret_id, v_patio_dev_id,
        TIMESTAMP '2026-06-16 08:30:00', 'Reposicionamento para demanda'
    )
    RETURNING id INTO v_movimentacao_id;

    PERFORM pg_temp.assert_eq('empresa inserida',
        (SELECT COUNT(*)::TEXT FROM empresa_locadora WHERE id = v_empresa_id), '1');
    PERFORM pg_temp.assert_eq('cliente inserido',
        (SELECT COUNT(*)::TEXT FROM cliente WHERE id = v_cliente_id), '1');
    PERFORM pg_temp.assert_eq('condutor inserido',
        (SELECT COUNT(*)::TEXT FROM condutor WHERE id = v_condutor_id), '1');
    PERFORM pg_temp.assert_eq('grupo_veiculo inserido',
        (SELECT COUNT(*)::TEXT FROM grupo_veiculo WHERE id = v_grupo_id), '1');
    PERFORM pg_temp.assert_eq('veiculo inserido',
        (SELECT COUNT(*)::TEXT FROM veiculo WHERE id = v_veiculo_id), '1');
    PERFORM pg_temp.assert_eq('patios inseridos',
        (SELECT COUNT(*)::TEXT FROM patio WHERE id IN (v_patio_ret_id, v_patio_dev_id)), '2');
    PERFORM pg_temp.assert_eq('vagas inseridas',
        (SELECT COUNT(*)::TEXT FROM vaga WHERE patio_id IN (v_patio_ret_id, v_patio_dev_id)), '2');
    PERFORM pg_temp.assert_eq('reserva inserida',
        (SELECT COUNT(*)::TEXT FROM reserva WHERE id = v_reserva_id), '1');
    PERFORM pg_temp.assert_eq('locacao inserida',
        (SELECT COUNT(*)::TEXT FROM locacao WHERE id = v_locacao_id), '1');
    PERFORM pg_temp.assert_eq('cobranca inserida',
        (SELECT COUNT(*)::TEXT FROM cobranca WHERE id = v_cobranca_id), '1');
    PERFORM pg_temp.assert_eq('seguro inserido',
        (SELECT COUNT(*)::TEXT FROM seguro WHERE id = v_seguro_id), '1');
    PERFORM pg_temp.assert_eq('locacao_seguro inserida',
        (SELECT COUNT(*)::TEXT FROM locacao_seguro WHERE locacao_id = v_locacao_id AND seguro_id = v_seguro_id), '1');
    PERFORM pg_temp.assert_eq('veiculo_acessorio inserido',
        (SELECT COUNT(*)::TEXT FROM veiculo_acessorio WHERE veiculo_id = v_veiculo_id AND acessorio_id = v_acessorio_id), '1');
    PERFORM pg_temp.assert_eq('foto inserida',
        (SELECT COUNT(*)::TEXT FROM foto WHERE id = v_foto_id), '1');
    PERFORM pg_temp.assert_eq('manutencao inserida',
        (SELECT COUNT(*)::TEXT FROM manutencao WHERE id = v_manutencao_id), '1');
    PERFORM pg_temp.assert_eq('movimentacao_patio inserida',
        (SELECT COUNT(*)::TEXT FROM movimentacao_patio WHERE id = v_movimentacao_id), '1');

    RAISE NOTICE 'OK: carga minima valida inserida e consultada com sucesso.';
END $$;

ROLLBACK;

