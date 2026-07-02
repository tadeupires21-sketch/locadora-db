-- =====================================================
-- Grupo:
--   Tadeu Belfort Neto              DRE 119034813
--   Vicente Alves                   DRE 120044148
--   João Pedro de Lacerda           DRE 116076670
-- Arquivo: 03_test_qualidade_dados.sql
-- Descrição: VALIDAÇÕES DE QUALIDADE DE DADOS sobre o DW carregado.
--
-- Diferente de 02-transform/03_validacao_transform.sql (que só LISTA
-- resultados para inspeção), este script ASSERTA: qualquer violação
-- aborta com RAISE EXCEPTION. Serve tanto para o teste automatizado
-- quanto como "gate" de qualidade em produção (rodar após a carga).
--
-- Cobre as 5 dimensões de qualidade pedidas:
--   1. Nulidade   2. Unicidade   3. Domínio
--   4. Referencial 5. Volume
-- =====================================================

CREATE OR REPLACE FUNCTION pg_temp.assert_zero(rotulo TEXT, qtd BIGINT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    IF qtd <> 0 THEN
        RAISE EXCEPTION 'QUALIDADE FALHOU [%]: % violação(ões) encontrada(s).', rotulo, qtd;
    END IF;
END;
$$;

DO $$
DECLARE
    v BIGINT;
BEGIN
    -- =================================================================
    -- 1. NULIDADE — colunas obrigatórias não podem ter nulo
    -- =================================================================
    SELECT COUNT(*) INTO v FROM dw.dim_cliente WHERE cliente_id IS NULL OR nome IS NULL OR tipo IS NULL;
    PERFORM pg_temp.assert_zero('dim_cliente: NK/nome/tipo nulos', v);

    SELECT COUNT(*) INTO v FROM dw.dim_veiculo WHERE veiculo_id IS NULL OR placa IS NULL OR status IS NULL OR sk_grupo_veiculo IS NULL OR sk_empresa IS NULL;
    PERFORM pg_temp.assert_zero('dim_veiculo: campos obrigatórios nulos', v);

    SELECT COUNT(*) INTO v FROM dw.fato_locacao
    WHERE sk_cliente IS NULL OR sk_condutor IS NULL OR sk_veiculo IS NULL
       OR sk_grupo_veiculo IS NULL OR sk_empresa IS NULL OR sk_patio_retirada IS NULL;
    PERFORM pg_temp.assert_zero('fato_locacao: FK obrigatória nula', v);

    SELECT COUNT(*) INTO v FROM dw.fato_reserva
    WHERE sk_cliente IS NULL OR sk_grupo_veiculo IS NULL OR sk_patio_retirada IS NULL OR sk_tempo_inicio IS NULL;
    PERFORM pg_temp.assert_zero('fato_reserva: FK obrigatória nula', v);

    -- =================================================================
    -- 2. UNICIDADE — chaves naturais e surrogate não podem duplicar
    -- =================================================================
    SELECT COUNT(*) INTO v FROM (SELECT cliente_id FROM dw.dim_cliente GROUP BY cliente_id HAVING COUNT(*) > 1) d;
    PERFORM pg_temp.assert_zero('dim_cliente: cliente_id duplicado', v);

    SELECT COUNT(*) INTO v FROM (SELECT veiculo_id FROM dw.dim_veiculo GROUP BY veiculo_id HAVING COUNT(*) > 1) d;
    PERFORM pg_temp.assert_zero('dim_veiculo: veiculo_id duplicado', v);

    SELECT COUNT(*) INTO v FROM (SELECT locacao_id FROM dw.fato_locacao GROUP BY locacao_id HAVING COUNT(*) > 1) d;
    PERFORM pg_temp.assert_zero('fato_locacao: locacao_id duplicado', v);

    SELECT COUNT(*) INTO v FROM (SELECT data FROM dw.dim_tempo GROUP BY data HAVING COUNT(*) > 1) d;
    PERFORM pg_temp.assert_zero('dim_tempo: data duplicada', v);

    -- =================================================================
    -- 3. DOMÍNIO — categóricos dentro do conjunto permitido
    -- =================================================================
    SELECT COUNT(*) INTO v FROM dw.dim_cliente WHERE tipo NOT IN ('PF', 'PJ');
    PERFORM pg_temp.assert_zero('dim_cliente.tipo fora do domínio {PF,PJ}', v);

    SELECT COUNT(*) INTO v FROM dw.dim_veiculo WHERE tipo_mecanizacao NOT IN ('automatico', 'manual');
    PERFORM pg_temp.assert_zero('dim_veiculo.tipo_mecanizacao fora do domínio', v);

    SELECT COUNT(*) INTO v FROM dw.dim_veiculo
    WHERE status NOT IN ('alugado','manutencao','indisponivel','disponivel','desconhecido');
    PERFORM pg_temp.assert_zero('dim_veiculo.status fora do domínio', v);

    SELECT COUNT(*) INTO v FROM dw.fato_reserva
    WHERE status_reserva NOT IN ('cancelada','confirmada','espera','ativa','desconhecida');
    PERFORM pg_temp.assert_zero('fato_reserva.status_reserva fora do domínio', v);

    -- status_cobranca pode ser nulo (locação sem cobrança), mas se preenchido
    -- deve estar no domínio consolidado.
    SELECT COUNT(*) INTO v FROM dw.fato_locacao
    WHERE status_cobranca IS NOT NULL
      AND status_cobranca NOT IN ('pago','pendente','em_atraso','cancelada','parcial');
    PERFORM pg_temp.assert_zero('fato_locacao.status_cobranca fora do domínio', v);

    -- =================================================================
    -- 4. INTEGRIDADE REFERENCIAL — toda FK aponta para registro existente
    -- (as FKs físicas já garantem; este check pega NULLs órfãos lógicos
    --  e protege contra cargas que tenham desabilitado constraints)
    -- =================================================================
    SELECT COUNT(*) INTO v FROM dw.fato_locacao f
    LEFT JOIN dw.dim_cliente c ON c.sk_cliente = f.sk_cliente
    WHERE c.sk_cliente IS NULL;
    PERFORM pg_temp.assert_zero('fato_locacao.sk_cliente órfão', v);

    SELECT COUNT(*) INTO v FROM dw.fato_locacao f
    LEFT JOIN dw.dim_veiculo dv ON dv.sk_veiculo = f.sk_veiculo
    WHERE dv.sk_veiculo IS NULL;
    PERFORM pg_temp.assert_zero('fato_locacao.sk_veiculo órfão', v);

    SELECT COUNT(*) INTO v FROM dw.dim_veiculo dv
    LEFT JOIN dw.dim_grupo_veiculo g ON g.sk_grupo_veiculo = dv.sk_grupo_veiculo
    WHERE g.sk_grupo_veiculo IS NULL;
    PERFORM pg_temp.assert_zero('dim_veiculo.sk_grupo_veiculo órfão', v);

    -- Cobertura temporal: toda SK de tempo dos fatos existe em dim_tempo.
    SELECT COUNT(*) INTO v FROM dw.fato_reserva f
    LEFT JOIN dw.dim_tempo t ON t.sk_tempo = f.sk_tempo_inicio
    WHERE t.sk_tempo IS NULL;
    PERFORM pg_temp.assert_zero('fato_reserva.sk_tempo_inicio sem dim_tempo', v);

    -- =================================================================
    -- 5. MEDIDAS — nenhuma medida protegida pode ser negativa
    -- =================================================================
    SELECT COUNT(*) INTO v FROM dw.fato_locacao
    WHERE km_rodado < 0 OR dias_previstos < 0 OR dias_realizados < 0
       OR atraso_devolucao_dias < 0 OR valor_cobranca < 0 OR valor_multa_atraso < 0;
    PERFORM pg_temp.assert_zero('fato_locacao: medida negativa', v);

    SELECT COUNT(*) INTO v FROM dw.fato_reserva WHERE dias_reservados < 0;
    PERFORM pg_temp.assert_zero('fato_reserva: dias_reservados negativo', v);

    -- =================================================================
    -- 6. VOLUME — alerta se uma tabela essencial vier vazia
    -- (Em produção, trocar por bandas: ex. WARN se < 80%% da média móvel.)
    -- =================================================================
    SELECT COUNT(*) INTO v FROM dw.dim_cliente;
    IF v = 0 THEN RAISE EXCEPTION 'VOLUME: dim_cliente vazia.'; END IF;
    SELECT COUNT(*) INTO v FROM dw.dim_veiculo;
    IF v = 0 THEN RAISE EXCEPTION 'VOLUME: dim_veiculo vazia.'; END IF;
    SELECT COUNT(*) INTO v FROM dw.fato_locacao;
    IF v = 0 THEN RAISE EXCEPTION 'VOLUME: fato_locacao vazia.'; END IF;

    RAISE NOTICE '✅ QUALIDADE DE DADOS: todas as asserções passaram.';
END $$;
