-- =====================================================
-- Nome: Tadeu Belfort Neto
-- DRE: 119034813
-- Arquivo: etl_02_extracao_grupos_externos.sql
-- Descrição: Extração ETL — Grupos 2, 3 e 4 (fontes externas)
--            Lê dos OLTPs das outras empresas e carrega
--            nas tabelas únicas de staging do DWH (schema stg).
--
-- Banco destino: PostgreSQL
--
-- IMPORTANTE sobre acesso às fontes:
--   Os grupos G2 e G3 usam MySQL no original; G4 usa SQL
--   genérico. Para um DW PostgreSQL existem 2 caminhos:
--     (a) replicar os bancos fonte como schemas PostgreSQL
--         (oltp_g2, oltp_g3, oltp_g4) — assumido aqui;
--     (b) usar foreign data wrappers (mysql_fdw para G2/G3).
--   Os nomes de tabela/coluna abaixo seguem os schemas
--   originais de cada grupo; ajustar conforme a réplica.
--
-- Agendamento sugerido:
--   G2 → 02:30h | G3 → 03:00h | G4 → 03:30h
-- =====================================================

-- Observação: as tabelas stg.<entidade> são criadas no etl_01.
-- Este script apenas remove/recarrega as linhas dos grupos 2, 3 e 4.

-- =====================================================================
-- GRUPO 2 — Bernardo, Enzo, Giovanni, Guilherme, Maria Victoria
-- Schema fonte: locadora (origem MySQL → réplica oltp_g2)
-- Particularidades:
--   • Locacao e Devolucao são tabelas separadas
--   • Especificacoes_var guarda estado do veículo em cada evento
--   • Caucao + Custos_devolucao registram valores extras
--   • Capacidade do pátio calculada via contagem de Vaga
--   • Grupo tem Diaria_grupo; cliente é o próprio condutor
-- =====================================================================

-- ------- Extração G2 ------------------------------------------------

DELETE FROM stg.cliente WHERE grupo_fonte = 2;
INSERT INTO stg.cliente
    (src_id, nome, tipo, cidade, uf, email, telefone, grupo_fonte)
SELECT q.*, 2::SMALLINT AS grupo_fonte
FROM (
SELECT c.id_cliente, c.nome_completo, 'PF',
    e.cidade, e.uf, c.email, c.telefone
FROM oltp_g2.cliente   c
JOIN oltp_g2.endereco  e ON e.id_endereco = c.id_endereco
) q;

-- Condutor G2: cliente + CNH de Documento_cliente
DELETE FROM stg.condutor WHERE grupo_fonte = 2;
INSERT INTO stg.condutor
    (src_id, src_cliente_id, cnh, nome, grupo_fonte)
SELECT q.*, 2::SMALLINT AS grupo_fonte
FROM (
SELECT c.id_cliente, c.id_cliente, d.cnh, c.nome_completo
FROM oltp_g2.cliente           c
JOIN oltp_g2.documento_cliente d ON d.id_documento = c.id_documento
WHERE d.cnh IS NOT NULL
) q;

DELETE FROM stg.grupo_veiculo WHERE grupo_fonte = 2;
INSERT INTO stg.grupo_veiculo
    (src_id, nome, categoria, diaria, grupo_fonte)
SELECT q.*, 2::SMALLINT AS grupo_fonte
FROM (
SELECT id_grupo, nome, descricao, diaria_grupo
FROM oltp_g2.grupo
) q;

DELETE FROM stg.veiculo WHERE grupo_fonte = 2;
INSERT INTO stg.veiculo
    (src_id, placa, chassi, modelo, marca,
     tipo_mecanizacao, ar_condicionado, status,
     src_grupo_id, nome_empresa, src_empresa_id, grupo_fonte)
SELECT q.*, 2::SMALLINT AS grupo_fonte
FROM (
SELECT v.id_veiculo, v.placa, v.chassi, v.modelo, v.marca,
    CASE WHEN sc.direcao_automatica = 1 THEN 'automatico' ELSE 'manual' END,
    (sc.ar_condicionado = 1),
    CASE WHEN vg.id_veiculo IS NOT NULL THEN 'alugado' ELSE 'disponivel' END,
    v.id_grupo,
    emp.nome_empresa,
    emp.id_empresa
FROM oltp_g2.veiculo              v
JOIN oltp_g2.especificacoes_const sc ON sc.id_spec_const = v.id_spec_const
LEFT JOIN oltp_g2.vaga            vg ON vg.id_veiculo = v.id_veiculo
CROSS JOIN LATERAL (
    SELECT id_empresa, nome_empresa FROM oltp_g2.empresa LIMIT 1
) emp
) q;

DELETE FROM stg.patio WHERE grupo_fonte = 2;
INSERT INTO stg.patio
    (src_id, nome, cidade, capacidade, src_empresa_id, nome_empresa, grupo_fonte)
SELECT q.*, 2::SMALLINT AS grupo_fonte
FROM (
SELECT p.id_patio, p.nome_patio, e.cidade,
    COUNT(v.id_vaga) AS capacidade,
    emp.id_empresa, emp.nome_empresa
FROM oltp_g2.patio        p
JOIN oltp_g2.endereco     e   ON e.id_endereco = p.id_endereco
JOIN oltp_g2.empresa      emp ON emp.id_empresa = p.id_empresa
LEFT JOIN oltp_g2.vaga    v   ON v.id_patio = p.id_patio
GROUP BY p.id_patio, p.nome_patio, e.cidade, emp.id_empresa, emp.nome_empresa
) q;

DELETE FROM stg.reserva WHERE grupo_fonte = 2;
INSERT INTO stg.reserva
    (src_id, src_cliente_id, src_grupo_id,
     src_patio_retirada_id, src_patio_devolucao_id,
     data_inicio, data_fim, data_reserva, status, preco_final, grupo_fonte)
SELECT q.*, 2::SMALLINT AS grupo_fonte
FROM (
SELECT r.id_reserva, r.id_cliente, r.id_grupo,
    r.id_patio_origem, r.id_patio_fim,
    r.data_inicio_combinada, r.data_fim_combinada, r.data_reserva,
    CASE r.estado_reserva
        WHEN 0 THEN 'ativa'
        WHEN 1 THEN 'cancelada'
        WHEN 2 THEN 'confirmada'
    END,
    r.preco_final
FROM oltp_g2.reserva r
WHERE r.data_inicio_combinada >= (NOW() - INTERVAL '25 hours')::DATE
   OR r.estado_reserva = 1
) q;

DELETE FROM stg.locacao WHERE grupo_fonte = 2;
INSERT INTO stg.locacao
    (src_id, src_devolucao_id, src_reserva_id,
     src_veiculo_id, src_condutor_id, src_cliente_id,
     src_patio_retirada_id, src_patio_devolucao_id,
     data_retirada_realizada, data_devolucao_realizada,
     gasolina_entrega, gasolina_devolucao,
     valor_atraso, valor_reparos, preco_final, grupo_fonte)
SELECT q.*, 2::SMALLINT AS grupo_fonte
FROM (
SELECT l.id_locacao, d.id_devolucao, l.id_reserva,
    l.id_veiculo, r.id_cliente, r.id_cliente,
    l.id_patio, vg.id_patio,
    l.data_locacao, d.data_devolucao,
    sv_ret.gasolina, sv_dev.gasolina,
    cd.valor_atraso, cd.valor_reparos, r.preco_final
FROM oltp_g2.locacao              l
JOIN oltp_g2.reserva              r      ON r.id_reserva    = l.id_reserva
JOIN oltp_g2.especificacoes_var   sv_ret ON sv_ret.id_spec_var = l.id_spec_var
LEFT JOIN oltp_g2.devolucao       d      ON d.id_locacao    = l.id_locacao
LEFT JOIN oltp_g2.especificacoes_var sv_dev ON sv_dev.id_spec_var = d.id_spec_var
LEFT JOIN oltp_g2.custos_devolucao cd     ON cd.id_caucao = l.id_caucao
LEFT JOIN oltp_g2.vaga            vg      ON vg.id_vaga   = d.id_vaga
WHERE l.data_locacao >= (NOW() - INTERVAL '25 hours')
   OR d.id_devolucao IS NULL
) q;


-- =====================================================================
-- GRUPO 3 — Ana Clara, Mariana, Matheus, Paulo, Pedro, Ryan
-- Schema fonte: locadora_dw (origem MySQL → réplica oltp_g3)
-- Particularidades:
--   • Cliente usa herança: Cliente + Cliente_pf + Cliente_pj
--   • Motorista é tabela separada de Cliente
--   • Categoria em vez de Grupo (tem Valor_diaria_base)
--   • Patio tem Capacidade direta
--   • Locacao tem pátio real de retirada e devolução
-- =====================================================================

-- ------- Extração G3 ------------------------------------------------

DELETE FROM stg.cliente WHERE grupo_fonte = 3;
INSERT INTO stg.cliente
    (src_id, nome, tipo, cidade, uf, email, telefone, grupo_fonte)
SELECT q.*, 3::SMALLINT AS grupo_fonte
FROM (
SELECT c.id_cliente,
    COALESCE(pf.nome_cliente, pj.razao_social),
    c.tipo_cliente,
    e.cidade, e.uf, c.email_cliente, c.telefone_cliente
FROM oltp_g3.cliente      c
JOIN oltp_g3.endereco     e  ON e.id_endereco = c.id_endereco
LEFT JOIN oltp_g3.cliente_pf pf ON pf.id_cliente = c.id_cliente
LEFT JOIN oltp_g3.cliente_pj pj ON pj.id_cliente = c.id_cliente
) q;

DELETE FROM stg.condutor WHERE grupo_fonte = 3;
INSERT INTO stg.condutor
    (src_id, src_cliente_id, nome, cnh, validade, categoria, grupo_fonte)
SELECT q.*, 3::SMALLINT AS grupo_fonte
FROM (
SELECT id_motorista, id_cliente, nome_motorista,
    numero_cnh, validade_cnh, categoria_cnh
FROM oltp_g3.motorista
) q;

DELETE FROM stg.grupo_veiculo WHERE grupo_fonte = 3;
INSERT INTO stg.grupo_veiculo
    (src_id, nome, categoria, diaria, grupo_fonte)
SELECT q.*, 3::SMALLINT AS grupo_fonte
FROM (
SELECT id_categoria, nome_categoria, descricao_categoria, valor_diaria_base
FROM oltp_g3.categoria
) q;

DELETE FROM stg.veiculo WHERE grupo_fonte = 3;
INSERT INTO stg.veiculo
    (src_id, placa, chassi, modelo, marca,
     tipo_mecanizacao, ar_condicionado, status,
     src_grupo_id, nome_empresa, src_empresa_id, grupo_fonte)
SELECT q.*, 3::SMALLINT AS grupo_fonte
FROM (
SELECT v.id_veiculo, v.placa, v.chassi, v.modelo, v.marca,
    v.tipo_cambio,
    (v.possui_ar_condicionado = 1),
    v.status_veiculo,
    v.id_categoria,
    emp.nome_empresa, emp.id_empresa
FROM oltp_g3.veiculo  v
JOIN oltp_g3.empresa  emp ON emp.id_empresa = v.id_empresa
) q;

DELETE FROM stg.patio WHERE grupo_fonte = 3;
INSERT INTO stg.patio
    (src_id, nome, cidade, capacidade, src_empresa_id, nome_empresa, grupo_fonte)
SELECT q.*, 3::SMALLINT AS grupo_fonte
FROM (
SELECT p.id_patio, p.nome_patio, e.cidade, p.capacidade,
    emp.id_empresa, emp.nome_empresa
FROM oltp_g3.patio    p
JOIN oltp_g3.endereco e   ON e.id_endereco = p.id_endereco
JOIN oltp_g3.empresa  emp ON emp.id_empresa = p.id_empresa
) q;

DELETE FROM stg.reserva WHERE grupo_fonte = 3;
INSERT INTO stg.reserva
    (src_id, src_cliente_id, src_grupo_id,
     src_patio_retirada_id, src_patio_devolucao_id,
     data_reserva, data_inicio, data_fim,
     status, preco_previsto, grupo_fonte)
SELECT q.*, 3::SMALLINT AS grupo_fonte
FROM (
SELECT id_reserva, id_cliente, id_categoria,
    id_patio_previsto_retirada, id_patio_previsto_devolucao,
    data_hora_reserva, data_previsao_retirada, data_previsao_devolucao,
    status_reserva, valor_previsto
FROM oltp_g3.reserva
WHERE data_hora_reserva >= (NOW() - INTERVAL '25 hours')
   OR LOWER(status_reserva) LIKE '%cancel%'
) q;

DELETE FROM stg.locacao WHERE grupo_fonte = 3;
INSERT INTO stg.locacao
    (src_id, src_reserva_id, src_veiculo_id,
     src_condutor_id, src_cliente_id,
     src_patio_retirada_id, src_patio_devolucao_id,
     data_retirada_realizada, data_devolucao_realizada,
     km_entrega, km_devolucao, valor_total, status, grupo_fonte)
SELECT q.*, 3::SMALLINT AS grupo_fonte
FROM (
SELECT l.id_locacao, l.id_reserva, l.id_veiculo,
    l.id_motorista, m.id_cliente,
    l.id_patio_real_retirada, l.id_patio_real_devolucao,
    l.data_hora_retirada_real, l.data_hora_devolucao_real,
    l.km_retirada, l.km_devolucao,
    l.valor_total_final, l.status_locacao
FROM oltp_g3.locacao   l
JOIN oltp_g3.motorista m ON m.id_motorista = l.id_motorista
WHERE l.data_hora_retirada_real >= (NOW() - INTERVAL '25 hours')
   OR l.data_hora_devolucao_real IS NULL
) q;


-- =====================================================================
-- GRUPO 4 — Thomas, Thiago, Yan
-- Schema fonte: tabelas diretas (réplica oltp_g4)
-- Particularidades:
--   • Sem tabela Empresa — nome está em Patio.Empresa_Dona
--   • Motorista separado de Cliente
--   • Reserva pode ter ID_Veiculo_Especifico
--   • Locacao tem pátio chegada prevista e realizada
--   • Sem tabela de cobrança; valor está em Locacao
-- =====================================================================

-- ------- Extração G4 ------------------------------------------------

DELETE FROM stg.cliente WHERE grupo_fonte = 4;
INSERT INTO stg.cliente
    (src_id, nome, tipo, cidade, grupo_fonte)
SELECT q.*, 4::SMALLINT AS grupo_fonte
FROM (
SELECT id_cliente, nome_razao_social, tipo_cliente, NULL
FROM oltp_g4.cliente
) q;

DELETE FROM stg.condutor WHERE grupo_fonte = 4;
INSERT INTO stg.condutor
    (src_id, src_cliente_id, nome, cnh, validade, categoria, grupo_fonte)
SELECT q.*, 4::SMALLINT AS grupo_fonte
FROM (
SELECT id_motorista, id_cliente, nome_condutor,
    numero_cnh, data_expiracao_cnh, categoria_habilitacao
FROM oltp_g4.motorista
) q;

DELETE FROM stg.grupo_veiculo WHERE grupo_fonte = 4;
INSERT INTO stg.grupo_veiculo
    (src_id, nome, categoria, diaria, grupo_fonte)
SELECT q.*, 4::SMALLINT AS grupo_fonte
FROM (
SELECT id_grupo, nome_categoria, classe_luxo, valor_diaria
FROM oltp_g4.grupo_veiculo
) q;

DELETE FROM stg.veiculo WHERE grupo_fonte = 4;
INSERT INTO stg.veiculo
    (src_id, placa, chassi, modelo, marca,
     tipo_mecanizacao, ar_condicionado, adaptado_cadeirante,
     status, src_grupo_id, nome_empresa, grupo_fonte)
SELECT q.*, 4::SMALLINT AS grupo_fonte
FROM (
SELECT v.id_veiculo, v.placa, v.chassi, v.modelo, v.marca,
    v.mecanizacao,
    v.ar_condicionado,
    FALSE,                       -- G4 não tem campo adaptado_cadeirante
    v.status_disponibilidade,
    v.id_grupo,
    (SELECT p.empresa_dona
     FROM oltp_g4.reserva r
     JOIN oltp_g4.patio   p ON p.id_patio = r.id_patio_retirada
     WHERE r.id_veiculo_especifico = v.id_veiculo
     LIMIT 1)
FROM oltp_g4.veiculo v
) q;

DELETE FROM stg.patio WHERE grupo_fonte = 4;
INSERT INTO stg.patio
    (src_id, nome, cidade, capacidade, nome_empresa, grupo_fonte)
SELECT q.*, 4::SMALLINT AS grupo_fonte
FROM (
SELECT id_patio, nome_localizacao, NULL, capacidade_vagas, empresa_dona
FROM oltp_g4.patio
) q;

DELETE FROM stg.reserva WHERE grupo_fonte = 4;
INSERT INTO stg.reserva
    (src_id, src_cliente_id, src_grupo_id,
     src_patio_retirada_id, data_solicitacao,
     data_inicio, data_fim, status, grupo_fonte)
SELECT q.*, 4::SMALLINT AS grupo_fonte
FROM (
SELECT id_reserva, id_cliente, id_grupo,
    id_patio_retirada, data_hora_solicitacao,
    data_hora_retirada_prevista, data_hora_devolucao_prevista,
    status_reserva
FROM oltp_g4.reserva
WHERE data_hora_solicitacao >= (NOW() - INTERVAL '25 hours')
   OR LOWER(status_reserva) LIKE '%cancel%'
) q;

DELETE FROM stg.locacao WHERE grupo_fonte = 4;
INSERT INTO stg.locacao
    (src_id, src_reserva_id, src_veiculo_id,
     src_condutor_id, src_cliente_id,
     src_patio_retirada_id, src_patio_devolucao_id,
     data_retirada_realizada, data_devolucao_realizada, valor_final, grupo_fonte)
SELECT q.*, 4::SMALLINT AS grupo_fonte
FROM (
SELECT l.id_locacao, l.id_reserva, l.id_veiculo,
    l.id_motorista, m.id_cliente,
    l.id_patio_saida, l.id_patio_chegada_realizada,
    l.data_hora_retirada, l.data_hora_devolucao_realizada,
    l.valor_final
FROM oltp_g4.locacao   l
JOIN oltp_g4.motorista m ON m.id_motorista = l.id_motorista
WHERE l.data_hora_retirada >= (NOW() - INTERVAL '25 hours')
   OR l.data_hora_devolucao_realizada IS NULL
) q;


-- =====================================================================
-- LOG DE EXTRAÇÃO — todos os grupos externos
-- =====================================================================
INSERT INTO stg.log_extracao (grupo_fonte, tabela_stg, qtd_registros)
VALUES
    (2,'cliente',       (SELECT COUNT(*) FROM stg.cliente       WHERE grupo_fonte = 2)),
    (2,'condutor',      (SELECT COUNT(*) FROM stg.condutor      WHERE grupo_fonte = 2)),
    (2,'grupo_veiculo', (SELECT COUNT(*) FROM stg.grupo_veiculo WHERE grupo_fonte = 2)),
    (2,'veiculo',       (SELECT COUNT(*) FROM stg.veiculo       WHERE grupo_fonte = 2)),
    (2,'patio',         (SELECT COUNT(*) FROM stg.patio         WHERE grupo_fonte = 2)),
    (2,'reserva',       (SELECT COUNT(*) FROM stg.reserva       WHERE grupo_fonte = 2)),
    (2,'locacao',       (SELECT COUNT(*) FROM stg.locacao       WHERE grupo_fonte = 2)),
    (3,'cliente',       (SELECT COUNT(*) FROM stg.cliente       WHERE grupo_fonte = 3)),
    (3,'condutor',      (SELECT COUNT(*) FROM stg.condutor      WHERE grupo_fonte = 3)),
    (3,'grupo_veiculo', (SELECT COUNT(*) FROM stg.grupo_veiculo WHERE grupo_fonte = 3)),
    (3,'veiculo',       (SELECT COUNT(*) FROM stg.veiculo       WHERE grupo_fonte = 3)),
    (3,'patio',         (SELECT COUNT(*) FROM stg.patio         WHERE grupo_fonte = 3)),
    (3,'reserva',       (SELECT COUNT(*) FROM stg.reserva       WHERE grupo_fonte = 3)),
    (3,'locacao',       (SELECT COUNT(*) FROM stg.locacao       WHERE grupo_fonte = 3)),
    (4,'cliente',       (SELECT COUNT(*) FROM stg.cliente       WHERE grupo_fonte = 4)),
    (4,'condutor',      (SELECT COUNT(*) FROM stg.condutor      WHERE grupo_fonte = 4)),
    (4,'grupo_veiculo', (SELECT COUNT(*) FROM stg.grupo_veiculo WHERE grupo_fonte = 4)),
    (4,'veiculo',       (SELECT COUNT(*) FROM stg.veiculo       WHERE grupo_fonte = 4)),
    (4,'patio',         (SELECT COUNT(*) FROM stg.patio         WHERE grupo_fonte = 4)),
    (4,'reserva',       (SELECT COUNT(*) FROM stg.reserva       WHERE grupo_fonte = 4)),
    (4,'locacao',       (SELECT COUNT(*) FROM stg.locacao       WHERE grupo_fonte = 4));
