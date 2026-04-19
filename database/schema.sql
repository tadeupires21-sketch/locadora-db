-- =========================
-- EMPRESA
-- =========================
CREATE TABLE empresa_locadora (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    cnpj VARCHAR(20) NOT NULL UNIQUE
);

-- =========================
-- CLIENTE
-- =========================
CREATE TABLE cliente (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    tipo VARCHAR(2) NOT NULL CHECK (tipo IN ('PF','PJ')),
    cidade VARCHAR(50) NOT NULL
);

-- =========================
-- CONDUTOR
-- =========================
CREATE TABLE condutor (
    id SERIAL PRIMARY KEY,
    cliente_id INT NOT NULL,
    cnh VARCHAR(20) NOT NULL UNIQUE,
    validade DATE NOT NULL,
    categoria VARCHAR(5) NOT NULL,
    FOREIGN KEY (cliente_id) REFERENCES cliente(id)
);

-- =========================
-- GRUPO VEÍCULO
-- =========================
CREATE TABLE grupo_veiculo (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(50) NOT NULL,
    categoria VARCHAR(50) NOT NULL
);

-- =========================
-- VEÍCULO
-- =========================
CREATE TABLE veiculo (
    id SERIAL PRIMARY KEY,
    placa VARCHAR(10) NOT NULL UNIQUE,
    chassi VARCHAR(30) NOT NULL UNIQUE,
    modelo VARCHAR(50) NOT NULL,
    marca VARCHAR(50) NOT NULL,
    cor VARCHAR(30) NOT NULL,
    tipo_mecanizacao VARCHAR(20) NOT NULL CHECK (tipo_mecanizacao IN ('manual','automatico')),
    ar_condicionado BOOLEAN NOT NULL,
    status VARCHAR(20) CHECK (status IN ('disponivel','alugado','manutencao')),
    adaptado_cadeirante BOOLEAN DEFAULT FALSE,
    grupo_id INT NOT NULL,
    empresa_id INT NOT NULL,
    FOREIGN KEY (grupo_id) REFERENCES grupo_veiculo(id),
    FOREIGN KEY (empresa_id) REFERENCES empresa_locadora(id)
);

-- =========================
-- ACESSÓRIO
-- =========================
CREATE TABLE acessorio (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(50) NOT NULL UNIQUE
);

-- =========================
-- VEÍCULO_ACESSÓRIO (N:N)
-- =========================
CREATE TABLE veiculo_acessorio (
    veiculo_id INT,
    acessorio_id INT,
    PRIMARY KEY (veiculo_id, acessorio_id),
    FOREIGN KEY (veiculo_id) REFERENCES veiculo(id) ON DELETE CASCADE,
    FOREIGN KEY (acessorio_id) REFERENCES acessorio(id) ON DELETE CASCADE
);

-- =========================
-- PÁTIO
-- =========================
CREATE TABLE patio (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(50) NOT NULL,
    cidade VARCHAR(50) NOT NULL
);

-- =========================
-- VAGA (PK COMPOSTA)
-- =========================
CREATE TABLE vaga (
    codigo VARCHAR(10),
    patio_id INT,
    status VARCHAR(20) CHECK (status IN ('livre','ocupada')),
    PRIMARY KEY (codigo, patio_id),
    FOREIGN KEY (patio_id) REFERENCES patio(id)
);

-- =========================
-- RESERVA
-- =========================
CREATE TABLE reserva (
    id SERIAL PRIMARY KEY,
    cliente_id INT NOT NULL,
    grupo_id INT NOT NULL,
    patio_id INT NOT NULL,
    data_inicio DATE NOT NULL,
    data_fim DATE NOT NULL,
    status VARCHAR(20) CHECK (status IN ('ativa','confirmada','cancelada','espera')),
    FOREIGN KEY (cliente_id) REFERENCES cliente(id),
    FOREIGN KEY (grupo_id) REFERENCES grupo_veiculo(id),
    FOREIGN KEY (patio_id) REFERENCES patio(id),
    CHECK (data_fim >= data_inicio)
);

-- =========================
-- LOCAÇÃO
-- =========================
CREATE TABLE locacao (
    id SERIAL PRIMARY KEY,
    reserva_id INT UNIQUE,
    veiculo_id INT NOT NULL,
    condutor_id INT NOT NULL,
    patio_retirada_id INT NOT NULL,
    patio_devolucao_id INT NOT NULL,
    data_retirada TIMESTAMP NOT NULL,
    data_devolucao TIMESTAMP,
    FOREIGN KEY (reserva_id) REFERENCES reserva(id),
    FOREIGN KEY (veiculo_id) REFERENCES veiculo(id),
    FOREIGN KEY (condutor_id) REFERENCES condutor(id),
    FOREIGN KEY (patio_retirada_id) REFERENCES patio(id),
    FOREIGN KEY (patio_devolucao_id) REFERENCES patio(id),
    CHECK (data_devolucao IS NULL OR data_devolucao >= data_retirada)
);

-- =========================
-- COBRANÇA
-- =========================
CREATE TABLE cobranca (
    id SERIAL PRIMARY KEY,
    locacao_id INT UNIQUE,
    valor DECIMAL(10,2) CHECK (valor >= 0),
    status VARCHAR(20) CHECK (status IN ('pendente','pago','cancelado')),
    data_pagamento DATE,
    FOREIGN KEY (locacao_id) REFERENCES locacao(id)
);

-- =========================
-- SEGURO
-- =========================
CREATE TABLE seguro (
    id SERIAL PRIMARY KEY,
    tipo VARCHAR(50) NOT NULL,
    valor DECIMAL(10,2) CHECK (valor >= 0)
);

-- =========================
-- LOCAÇÃO_SEGURO (N:N)
-- =========================
CREATE TABLE locacao_seguro (
    locacao_id INT,
    seguro_id INT,
    PRIMARY KEY (locacao_id, seguro_id),
    FOREIGN KEY (locacao_id) REFERENCES locacao(id) ON DELETE CASCADE,
    FOREIGN KEY (seguro_id) REFERENCES seguro(id) ON DELETE CASCADE
);

-- =========================
-- FOTO
-- =========================
CREATE TABLE foto (
    id SERIAL PRIMARY KEY,
    veiculo_id INT,
    url TEXT NOT NULL,
    tipo VARCHAR(50),
    FOREIGN KEY (veiculo_id) REFERENCES veiculo(id) ON DELETE CASCADE
);

-- =========================
-- MANUTENÇÃO
-- =========================
CREATE TABLE manutencao (
    id SERIAL PRIMARY KEY,
    veiculo_id INT,
    data DATE NOT NULL,
    descricao TEXT NOT NULL,
    FOREIGN KEY (veiculo_id) REFERENCES veiculo(id) ON DELETE CASCADE
);