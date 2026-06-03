-- =====================================================
-- Grupo:
--   Tadeu Belfort Neto              DRE 119034813
--   Vicente Alves                   DRE 120044148
--   João Pedro de Lacerda           DRE 116076670
-- Arquivo: 01_functions.sql
-- Descrição: Biblioteca de funções puras de transformação.
--
-- Estas funções encapsulam as REGRAS DE NEGÓCIO e normalizações
-- usadas pela camada transform (stg.conf_*). Centralizá-las aqui:
--   • elimina duplicação de lógica entre transform e validação;
--   • dá um ponto único de manutenção das regras;
--   • permite testes UNITÁRIOS determinísticos (ver 04-tests/).
--
-- Todas são IMMUTABLE (saída depende só dos argumentos) — exceto
-- onde indicado. Execute este script logo após 00_create_schemas.sql.
-- =====================================================

-- -----------------------------------------------------
-- Normalização de status de RESERVA
-- Domínio de saída: cancelada | confirmada | espera | ativa | desconhecida
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION stg.fn_normaliza_status_reserva(p_status TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN LOWER(COALESCE(p_status, '')) LIKE '%cancel%'  THEN 'cancelada'
        WHEN LOWER(COALESCE(p_status, '')) LIKE '%confirm%' THEN 'confirmada'
        WHEN LOWER(COALESCE(p_status, '')) LIKE '%espera%'  THEN 'espera'
        WHEN LOWER(COALESCE(p_status, '')) LIKE '%wait%'    THEN 'espera'
        WHEN LOWER(COALESCE(p_status, '')) LIKE '%ativa%'   THEN 'ativa'
        ELSE 'desconhecida'   -- não mascara entrada inválida
    END;
$$;

-- -----------------------------------------------------
-- Normalização de status de VEÍCULO
-- Domínio: alugado | manutencao | indisponivel | disponivel | desconhecido
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION stg.fn_normaliza_status_veiculo(p_status TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN LOWER(COALESCE(p_status, '')) LIKE '%alug%'   THEN 'alugado'
        WHEN LOWER(COALESCE(p_status, '')) LIKE '%locad%'  THEN 'alugado'
        WHEN LOWER(COALESCE(p_status, '')) LIKE '%manut%'  THEN 'manutencao'
        WHEN LOWER(COALESCE(p_status, '')) LIKE '%indisp%' THEN 'indisponivel'
        WHEN LOWER(COALESCE(p_status, '')) LIKE '%dispon%' THEN 'disponivel'
        WHEN LOWER(COALESCE(p_status, '')) LIKE '%avail%'  THEN 'disponivel'
        ELSE 'desconhecido'
    END;
$$;

-- -----------------------------------------------------
-- Normalização de status de COBRANÇA (por linha, antes da consolidação)
-- Domínio: pendente | em_atraso | cancelada | pago | desconhecido
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION stg.fn_normaliza_status_cobranca(p_status TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN LOWER(COALESCE(p_status, '')) LIKE '%pend%'   THEN 'pendente'
        WHEN LOWER(COALESCE(p_status, '')) LIKE '%atras%'  THEN 'em_atraso'
        WHEN LOWER(COALESCE(p_status, '')) LIKE '%cancel%' THEN 'cancelada'
        WHEN LOWER(COALESCE(p_status, '')) LIKE '%pag%'    THEN 'pago'
        WHEN LOWER(COALESCE(p_status, '')) LIKE '%quit%'   THEN 'pago'
        ELSE COALESCE(NULLIF(LOWER(TRIM(p_status)), ''), 'desconhecido')
    END;
$$;

-- -----------------------------------------------------
-- Normalização de TIPO DE CLIENTE
-- Domínio: PF | PJ  (qualquer coisa que não seja PJ vira PF)
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION stg.fn_normaliza_tipo_cliente(p_tipo TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN UPPER(TRIM(COALESCE(p_tipo, 'PF'))) = 'PJ' THEN 'PJ'
        ELSE 'PF'
    END;
$$;

-- -----------------------------------------------------
-- Normalização de TIPO DE MECANIZAÇÃO
-- Domínio: automatico | manual
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION stg.fn_normaliza_tipo_mecanizacao(p_tipo TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN LOWER(COALESCE(p_tipo, '')) LIKE '%auto%' THEN 'automatico'
        ELSE 'manual'
    END;
$$;

-- -----------------------------------------------------
-- Normalização de PLACA (uppercase, só A-Z0-9; vazio → 'SEMPLACA')
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION stg.fn_normaliza_placa(p_placa TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
    SELECT COALESCE(
        NULLIF(REGEXP_REPLACE(UPPER(TRIM(COALESCE(p_placa, ''))), '[^A-Z0-9]+', '', 'g'), ''),
        'SEMPLACA'
    );
$$;

-- TRUE quando a placa original era vazia/nula (foi imputada).
CREATE OR REPLACE FUNCTION stg.fn_placa_imputada(p_placa TEXT)
RETURNS BOOLEAN LANGUAGE sql IMMUTABLE AS $$
    SELECT NULLIF(REGEXP_REPLACE(UPPER(TRIM(COALESCE(p_placa, ''))), '[^A-Z0-9]+', '', 'g'), '') IS NULL;
$$;

-- -----------------------------------------------------
-- DIAS INCLUSIVOS entre duas datas (mesmo dia = 1 dia).
-- Protegido: datas invertidas ou nulas não geram negativo.
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION stg.fn_dias_inclusivo(p_inicio DATE, p_fim DATE)
RETURNS INTEGER LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN p_inicio IS NULL OR p_fim IS NULL THEN NULL
        ELSE GREATEST(p_fim - p_inicio + 1, 0)
    END;
$$;

-- -----------------------------------------------------
-- DIAS DE ATRASO (devolução real - prevista). Devolução
-- antecipada NÃO vira atraso negativo: fica 0.
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION stg.fn_dias_atraso(p_real DATE, p_prevista DATE)
RETURNS INTEGER LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN p_real IS NULL OR p_prevista IS NULL THEN NULL
        ELSE GREATEST(p_real - p_prevista, 0)
    END;
$$;

-- -----------------------------------------------------
-- KM RODADO (devolução - entrega). Protegido contra odômetro invertido.
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION stg.fn_km_rodado(p_km_entrega INTEGER, p_km_devolucao INTEGER)
RETURNS INTEGER LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN p_km_entrega IS NULL OR p_km_devolucao IS NULL THEN NULL
        ELSE GREATEST(p_km_devolucao - p_km_entrega, 0)
    END;
$$;

-- -----------------------------------------------------
-- MULTA POR ATRASO (regra de negócio).
-- Prioriza o valor de atraso cobrado na origem; se ausente/zero,
-- estima como dias_de_atraso × diária do grupo.
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION stg.fn_multa_atraso(
    p_valor_atraso NUMERIC,
    p_dev_real     DATE,
    p_dev_prevista DATE,
    p_diaria       NUMERIC
)
RETURNS NUMERIC LANGUAGE sql IMMUTABLE AS $$
    SELECT COALESCE(
        NULLIF(p_valor_atraso, 0),
        (GREATEST(COALESCE(p_dev_real - p_dev_prevista, 0), 0) * COALESCE(p_diaria, 0))
    )::NUMERIC(10,2);
$$;
