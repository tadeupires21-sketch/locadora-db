-- =====================================================
-- Nome: Tadeu Belfort Neto
-- DRE: 119034813
-- Arquivo: 01_test_unit_funcoes.sql
-- Descrição: Testes UNITÁRIOS das funções de transformação
--            (00-infra/01_functions.sql).
--
-- Cada função tem ao menos um caso VÁLIDO e um INVÁLIDO/limite.
-- Framework: asserção pura em PL/pgSQL (sem dependência externa),
-- usando uma função helper de sessão (pg_temp.assert_eq). Cada falha
-- aborta com RAISE EXCEPTION indicando o caso. Se o script terminar
-- sem erro, todos os testes passaram.
--
-- Pré-requisito: 00-infra/01_functions.sql já executado.
-- pgTAP: onde a extensão existir, assert_eq equivale a is(); a
--   lógica dos casos é a mesma.
-- =====================================================

-- Helper de asserção (vive só nesta sessão, schema pg_temp).
CREATE OR REPLACE FUNCTION pg_temp.assert_eq(rotulo TEXT, obtido TEXT, esperado TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    IF obtido IS DISTINCT FROM esperado THEN
        RAISE EXCEPTION 'FALHOU [%]: obtido=[%] esperado=[%]', rotulo, obtido, esperado;
    END IF;
END;
$$;

DO $$
BEGIN
    -- ===== fn_normaliza_status_reserva =====
    PERFORM pg_temp.assert_eq('status_reserva válido (CANCELADO)',
        stg.fn_normaliza_status_reserva('CANCELADO'), 'cancelada');
    PERFORM pg_temp.assert_eq('status_reserva inválido (lixo) -> desconhecida',
        stg.fn_normaliza_status_reserva('estado_invalido'), 'desconhecida');
    PERFORM pg_temp.assert_eq('status_reserva nulo -> desconhecida',
        stg.fn_normaliza_status_reserva(NULL), 'desconhecida');

    -- ===== fn_normaliza_status_veiculo =====
    PERFORM pg_temp.assert_eq('status_veiculo válido (Locado)',
        stg.fn_normaliza_status_veiculo('Locado'), 'alugado');
    PERFORM pg_temp.assert_eq('status_veiculo inválido -> desconhecido',
        stg.fn_normaliza_status_veiculo('status_zoado'), 'desconhecido');

    -- ===== fn_normaliza_status_cobranca =====
    PERFORM pg_temp.assert_eq('status_cobranca válido (QUITADO)',
        stg.fn_normaliza_status_cobranca('QUITADO'), 'pago');
    PERFORM pg_temp.assert_eq('status_cobranca pendente',
        stg.fn_normaliza_status_cobranca('pendente'), 'pendente');

    -- ===== fn_normaliza_tipo_cliente =====
    PERFORM pg_temp.assert_eq('tipo_cliente PJ',
        stg.fn_normaliza_tipo_cliente('pj'), 'PJ');
    PERFORM pg_temp.assert_eq('tipo_cliente inválido -> PF (default)',
        stg.fn_normaliza_tipo_cliente('xyz'), 'PF');

    -- ===== fn_normaliza_tipo_mecanizacao =====
    PERFORM pg_temp.assert_eq('mecanização automática',
        stg.fn_normaliza_tipo_mecanizacao('Cambio Automatico'), 'automatico');
    PERFORM pg_temp.assert_eq('mecanização default -> manual',
        stg.fn_normaliza_tipo_mecanizacao('cvt?'), 'manual');

    -- ===== fn_normaliza_placa =====
    PERFORM pg_temp.assert_eq('placa válida normalizada',
        stg.fn_normaliza_placa('abc-1d23'), 'ABC1D23');
    PERFORM pg_temp.assert_eq('placa nula -> SEMPLACA',
        stg.fn_normaliza_placa(NULL), 'SEMPLACA');

    -- ===== fn_placa_imputada =====
    PERFORM pg_temp.assert_eq('placa imputada (nula) = true',
        stg.fn_placa_imputada(NULL)::TEXT, 'true');
    PERFORM pg_temp.assert_eq('placa imputada (válida) = false',
        stg.fn_placa_imputada('ABC1D23')::TEXT, 'false');

    -- ===== fn_dias_inclusivo =====
    PERFORM pg_temp.assert_eq('dias_inclusivo mesmo dia = 1',
        stg.fn_dias_inclusivo(DATE '2026-05-01', DATE '2026-05-01')::TEXT, '1');
    PERFORM pg_temp.assert_eq('dias_inclusivo 5 dias',
        stg.fn_dias_inclusivo(DATE '2026-05-01', DATE '2026-05-05')::TEXT, '5');
    PERFORM pg_temp.assert_eq('dias_inclusivo invertido -> 0 (protegido)',
        stg.fn_dias_inclusivo(DATE '2026-05-05', DATE '2026-05-01')::TEXT, '0');
    PERFORM pg_temp.assert_eq('dias_inclusivo nulo -> NULL',
        stg.fn_dias_inclusivo(NULL, DATE '2026-05-01')::TEXT, NULL);

    -- ===== fn_dias_atraso =====
    PERFORM pg_temp.assert_eq('atraso de 2 dias',
        stg.fn_dias_atraso(DATE '2026-05-05', DATE '2026-05-03')::TEXT, '2');
    PERFORM pg_temp.assert_eq('devolução antecipada -> atraso 0',
        stg.fn_dias_atraso(DATE '2026-05-01', DATE '2026-05-03')::TEXT, '0');

    -- ===== fn_km_rodado =====
    PERFORM pg_temp.assert_eq('km_rodado normal',
        stg.fn_km_rodado(10000, 10350)::TEXT, '350');
    PERFORM pg_temp.assert_eq('km_rodado invertido -> 0 (protegido)',
        stg.fn_km_rodado(5000, 4000)::TEXT, '0');

    -- ===== fn_multa_atraso =====
    PERFORM pg_temp.assert_eq('multa usa valor da origem quando presente',
        stg.fn_multa_atraso(150.00, DATE '2026-05-05', DATE '2026-05-03', 100.00)::TEXT, '150.00');
    PERFORM pg_temp.assert_eq('multa estimada (sem valor origem) = 2 dias x 100',
        stg.fn_multa_atraso(NULL, DATE '2026-05-05', DATE '2026-05-03', 100.00)::TEXT, '200.00');
    PERFORM pg_temp.assert_eq('multa sem atraso e sem valor = 0',
        stg.fn_multa_atraso(NULL, DATE '2026-05-01', DATE '2026-05-03', 100.00)::TEXT, '0.00');

    RAISE NOTICE '✅ TESTES UNITÁRIOS: todas as asserções passaram.';
END $$;
