-- =====================================================
-- Arquivo: 06_test_oltp_on_delete.sql
-- Descricao: Testes de regras ON DELETE no OLTP.
--
-- Este teste valida cascatas e restricoes sem alterar o schema.
-- Todos os dados sao descartados com ROLLBACK ao final.
-- =====================================================

\echo '== OLTP: regras ON DELETE =='

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.assert_eq(rotulo TEXT, obtido TEXT, esperado TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    IF obtido IS DISTINCT FROM esperado THEN
        RAISE EXCEPTION 'FALHOU [%]: obtido=[%] esperado=[%]', rotulo, obtido, esperado;
    END IF;
END;
$$;

-- esperado: código único ('23001|23503') ou lista separada por '|' ('23001|23503').
-- Motivação: PostgreSQL distingue 23001 (RESTRICT) de 23503 (NO ACTION/FK genérico).
-- Ambos indicam que a FK bloqueou a operação — o teste valida a intenção,
-- não o detalhe de implementação da FK.
CREATE OR REPLACE FUNCTION pg_temp.expect_sqlstate(rotulo TEXT, comando TEXT, esperado TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
    v_state TEXT;
    v_msg   TEXT;
    v_lista TEXT[] := string_to_array(esperado, '|');
BEGIN
    BEGIN
        EXECUTE comando;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_state = RETURNED_SQLSTATE,
            v_msg = MESSAGE_TEXT;

        IF v_state = ANY(v_lista) THEN
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
    v_empresa_id        INTEGER;
    v_cliente_id        INTEGER;
    v_condutor_id       INTEGER;
    v_grupo_id          INTEGER;
    v_veiculo_casc_id   INTEGER;
    v_veiculo_restr_id  INTEGER;
    v_patio_casc_id     INTEGER;
    v_patio_ret_id      INTEGER;
    v_patio_dev_id      INTEGER;
    v_reserva_id        INTEGER;
    v_locacao_id        INTEGER;
    v_seguro_id         INTEGER;
    v_acessorio_id      INTEGER;
BEGIN
    INSERT INTO empresa_locadora (nome, cnpj)
    VALUES ('Empresa Delete OLTP', '99.999.999/0001-93')
    RETURNING id INTO v_empresa_id;

    INSERT INTO cliente (nome, tipo, cidade)
    VALUES ('Cliente Delete OLTP', 'PF', 'Rio de Janeiro')
    RETURNING id INTO v_cliente_id;

    INSERT INTO condutor (cliente_id, nome, cnh, validade, categoria)
    VALUES (v_cliente_id, 'Condutor Delete OLTP', 'CNH-TESTE-0003', DATE '2031-01-01', 'B')
    RETURNING id INTO v_condutor_id;

    INSERT INTO grupo_veiculo (nome, categoria)
    VALUES ('Grupo Delete OLTP', 'SUV')
    RETURNING id INTO v_grupo_id;

    -- Veiculo sem dependencia restritiva: deve apagar filhos em cascata.
    INSERT INTO veiculo (
        placa, chassi, modelo, marca, cor, tipo_mecanizacao,
        status, grupo_id, empresa_id
    )
    VALUES (
        'DEL1A01', 'CHASSI-DELETE-CASCADE-001', 'Pulse', 'Fiat', 'Cinza',
        'manual', 'disponivel', v_grupo_id, v_empresa_id
    )
    RETURNING id INTO v_veiculo_casc_id;

    INSERT INTO acessorio (nome)
    VALUES ('Cadeirinha Delete Teste')
    RETURNING id INTO v_acessorio_id;

    INSERT INTO veiculo_acessorio (veiculo_id, acessorio_id)
    VALUES (v_veiculo_casc_id, v_acessorio_id);

    INSERT INTO foto (veiculo_id, url, tipo)
    VALUES (v_veiculo_casc_id, 'https://example.test/delete-foto.jpg', 'vistoria');

    INSERT INTO manutencao (veiculo_id, data, descricao)
    VALUES (v_veiculo_casc_id, DATE '2026-06-01', 'Teste cascade manutencao');

    DELETE FROM veiculo WHERE id = v_veiculo_casc_id;

    PERFORM pg_temp.assert_eq('veiculo_acessorio apagado em cascade',
        (SELECT COUNT(*)::TEXT FROM veiculo_acessorio WHERE veiculo_id = v_veiculo_casc_id), '0');
    PERFORM pg_temp.assert_eq('foto apagada em cascade',
        (SELECT COUNT(*)::TEXT FROM foto WHERE veiculo_id = v_veiculo_casc_id), '0');
    PERFORM pg_temp.assert_eq('manutencao apagada em cascade',
        (SELECT COUNT(*)::TEXT FROM manutencao WHERE veiculo_id = v_veiculo_casc_id), '0');

    -- Patio com vagas: deve apagar vagas em cascata.
    INSERT INTO patio (nome, cidade)
    VALUES ('Patio Delete Cascade', 'Rio de Janeiro')
    RETURNING id INTO v_patio_casc_id;

    INSERT INTO vaga (codigo, patio_id, status)
    VALUES ('D-001', v_patio_casc_id, 'livre'),
           ('D-002', v_patio_casc_id, 'ocupada');

    DELETE FROM patio WHERE id = v_patio_casc_id;

    PERFORM pg_temp.assert_eq('vagas apagadas em cascade ao apagar patio',
        (SELECT COUNT(*)::TEXT FROM vaga WHERE patio_id = v_patio_casc_id), '0');

    -- Dependencias restritivas: entidades referenciadas nao devem ser apagadas.
    INSERT INTO patio (nome, cidade)
    VALUES ('Patio Delete Retirada', 'Rio de Janeiro')
    RETURNING id INTO v_patio_ret_id;

    INSERT INTO patio (nome, cidade)
    VALUES ('Patio Delete Devolucao', 'Niteroi')
    RETURNING id INTO v_patio_dev_id;

    INSERT INTO veiculo (
        placa, chassi, modelo, marca, cor, tipo_mecanizacao,
        status, grupo_id, empresa_id
    )
    VALUES (
        'DEL1A02', 'CHASSI-DELETE-RESTRICT-001', 'Compass', 'Jeep', 'Preto',
        'automatico', 'disponivel', v_grupo_id, v_empresa_id
    )
    RETURNING id INTO v_veiculo_restr_id;

    INSERT INTO reserva (
        cliente_id, grupo_id, patio_retirada_id, patio_devolucao_id,
        data_inicio, data_fim, status
    )
    VALUES (
        v_cliente_id, v_grupo_id, v_patio_ret_id, v_patio_dev_id,
        DATE '2026-08-01', DATE '2026-08-05', 'confirmada'
    )
    RETURNING id INTO v_reserva_id;

    INSERT INTO locacao (
        reserva_id, veiculo_id, condutor_id, patio_retirada_id, patio_devolucao_id,
        data_retirada_prevista, data_devolucao_prevista
    )
    VALUES (
        v_reserva_id, v_veiculo_restr_id, v_condutor_id, v_patio_ret_id, v_patio_dev_id,
        TIMESTAMP '2026-08-01 09:00:00', TIMESTAMP '2026-08-05 18:00:00'
    )
    RETURNING id INTO v_locacao_id;

    INSERT INTO seguro (tipo, valor)
    VALUES ('Seguro Delete Restrict', 50.00)
    RETURNING id INTO v_seguro_id;

    INSERT INTO locacao_seguro (locacao_id, seguro_id)
    VALUES (v_locacao_id, v_seguro_id);

    PERFORM pg_temp.expect_sqlstate(
        'apagar veiculo referenciado por locacao deve falhar',
        format('DELETE FROM veiculo WHERE id = %s', v_veiculo_restr_id),
        '23001|23503'
    );

    PERFORM pg_temp.expect_sqlstate(
        'apagar patio referenciado por reserva/locacao deve falhar',
        format('DELETE FROM patio WHERE id = %s', v_patio_ret_id),
        '23001|23503'
    );

    PERFORM pg_temp.expect_sqlstate(
        'apagar cliente referenciado por condutor/reserva deve falhar',
        format('DELETE FROM cliente WHERE id = %s', v_cliente_id),
        '23001|23503'
    );

    PERFORM pg_temp.expect_sqlstate(
        'apagar grupo_veiculo referenciado por veiculo/reserva deve falhar',
        format('DELETE FROM grupo_veiculo WHERE id = %s', v_grupo_id),
        '23001|23503'
    );

    PERFORM pg_temp.expect_sqlstate(
        'apagar empresa referenciada por veiculo deve falhar',
        format('DELETE FROM empresa_locadora WHERE id = %s', v_empresa_id),
        '23001|23503'
    );

    PERFORM pg_temp.expect_sqlstate(
        'apagar seguro referenciado por locacao_seguro deve falhar',
        format('DELETE FROM seguro WHERE id = %s', v_seguro_id),
        '23001|23503'
    );

    RAISE NOTICE 'OK: regras ON DELETE validadas.';
END $$;

ROLLBACK;

