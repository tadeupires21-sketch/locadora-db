-- =====================================================
-- Grupo:
--   Tadeu Belfort Neto              DRE 119034813
--   Vicente Alves                   DRE 120044148
--   João Pedro de Lacerda           DRE 116076670
-- Arquivo: 02_test_integracao.sql
-- Descrição: Teste de INTEGRAÇÃO do pipeline (apenas Grupo 1).
--
-- Valida que, após rodar extract → transform → load sobre os
-- fixtures de 00_fixtures_oltp_g1.sql, os dados chegam ao DW com
-- os VALORES ESPERADOS e com integridade referencial.
--
-- ORDEM DE EXECUÇÃO (ver run_tests.ps1) — este arquivo assume que
-- o pipeline G1 JÁ FOI EXECUTADO sobre os fixtures:
--   00-infra/00_create_schemas.sql
--   00-infra/01_functions.sql
--   04-tests/00_fixtures_oltp_g1.sql
--   01-staging/create_staging.sql
--   01-staging/etl_01_extracao_grupo_tadeu_unificado.sql   (só G1)
--   02-transform/01_transform_dimensoes.sql
--   02-transform/02_transform_fatos.sql
--   03-dw/01_create_dw.sql
--   03-dw/02_load_dimensoes.sql
--   03-dw/03_load_fatos.sql
--
-- Se qualquer asserção falhar, o script aborta com RAISE EXCEPTION.
-- =====================================================

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
    v_dias_real   INTEGER;
    v_atraso      INTEGER;
    v_km          INTEGER;
    v_multa       NUMERIC;
    v_status_cob  TEXT;
    v_qtd         INTEGER;
BEGIN
    -- ----- 1. Contagens: tudo que entrou na conformance chegou ao DW -----
    PERFORM pg_temp.assert_eq('linhas fato_locacao = conf_locacao',
        (SELECT COUNT(*) FROM dw.fato_locacao)::TEXT,
        (SELECT COUNT(*) FROM stg.conf_locacao)::TEXT);

    PERFORM pg_temp.assert_eq('linhas fato_reserva = conf_reserva',
        (SELECT COUNT(*) FROM dw.fato_reserva)::TEXT,
        (SELECT COUNT(*) FROM stg.conf_reserva)::TEXT);

    -- 3 clientes nos fixtures
    PERFORM pg_temp.assert_eq('dim_cliente tem 3 clientes',
        (SELECT COUNT(*) FROM dw.dim_cliente)::TEXT, '3');

    -- ----- 2. Valores esperados da LOCAÇÃO 1 (atrasada) -----
    -- retirada D-5, devolução real D-1 → 5 dias inclusivos
    -- prev devolução D-3, real D-1     → atraso 2
    -- km 10000 → 10350                 → km_rodado 350
    SELECT dias_realizados, atraso_devolucao_dias, km_rodado, valor_multa_atraso, status_cobranca
    INTO v_dias_real, v_atraso, v_km, v_multa, v_status_cob
    FROM dw.fato_locacao
    WHERE locacao_id = '1-1';

    PERFORM pg_temp.assert_eq('L1 dias_realizados',         v_dias_real::TEXT, '5');
    PERFORM pg_temp.assert_eq('L1 atraso_devolucao_dias',   v_atraso::TEXT,    '2');
    PERFORM pg_temp.assert_eq('L1 km_rodado',               v_km::TEXT,        '350');
    -- multa: valor de origem ausente em conf? conf usa valor_atraso (nulo nos
    -- fixtures G1) → estima 2 dias × diária do grupo Economico (100) = 200.
    PERFORM pg_temp.assert_eq('L1 valor_multa_atraso (2x100)', v_multa::TEXT, '200.00');
    PERFORM pg_temp.assert_eq('L1 status_cobranca',         v_status_cob,      'pago');

    -- ----- 3. LOCAÇÃO 2 (devolvida antes) → atraso 0 -----
    SELECT atraso_devolucao_dias INTO v_atraso
    FROM dw.fato_locacao WHERE locacao_id = '1-2';
    PERFORM pg_temp.assert_eq('L2 atraso = 0 (devolução antecipada)', v_atraso::TEXT, '0');

    -- ----- 4. LOCAÇÃO 3 (km invertido) → km_rodado 0 -----
    SELECT km_rodado INTO v_km
    FROM dw.fato_locacao WHERE locacao_id = '1-3';
    PERFORM pg_temp.assert_eq('L3 km_rodado = 0 (protegido)', v_km::TEXT, '0');

    -- ----- 5. Imputação propagada às dimensões -----
    PERFORM pg_temp.assert_eq('cliente 1-3 tem nome imputado',
        (SELECT flag_nome_imputado FROM dw.dim_cliente WHERE cliente_id = '1-3')::TEXT, 'true');
    PERFORM pg_temp.assert_eq('veículo 1-3 tem placa imputada',
        (SELECT flag_placa_imputada FROM dw.dim_veiculo WHERE veiculo_id = '1-3')::TEXT, 'true');
    PERFORM pg_temp.assert_eq('veículo 1-3 placa = SEMPLACA',
        (SELECT placa FROM dw.dim_veiculo WHERE veiculo_id = '1-3'), 'SEMPLACA');

    -- ----- 6. Domínio: status desconhecido preservado (não mascarado) -----
    PERFORM pg_temp.assert_eq('veículo 1-2 status desconhecido',
        (SELECT status FROM dw.dim_veiculo WHERE veiculo_id = '1-2'), 'desconhecido');
    PERFORM pg_temp.assert_eq('reserva 1-3 status desconhecida',
        (SELECT status_reserva FROM dw.fato_reserva WHERE reserva_id = '1-3'), 'desconhecida');

    -- ----- 7. Integridade referencial: nenhuma FK obrigatória nula -----
    SELECT COUNT(*) INTO v_qtd FROM dw.fato_locacao
    WHERE sk_cliente IS NULL OR sk_condutor IS NULL OR sk_veiculo IS NULL
       OR sk_grupo_veiculo IS NULL OR sk_empresa IS NULL OR sk_patio_retirada IS NULL;
    PERFORM pg_temp.assert_eq('fato_locacao sem FK obrigatória nula', v_qtd::TEXT, '0');

    -- ----- 8. dim_tempo CONTÍNUA: count = (max - min + 1) -----
    PERFORM pg_temp.assert_eq('dim_tempo é contínua (sem buracos)',
        (SELECT COUNT(*) FROM dw.dim_tempo)::TEXT,
        (SELECT (MAX(data) - MIN(data) + 1)::TEXT FROM dw.dim_tempo));

    RAISE NOTICE '✅ TESTE DE INTEGRAÇÃO: todas as asserções passaram.';
END $$;
