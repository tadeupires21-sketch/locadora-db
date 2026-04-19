CREATE TABLE cliente (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    tipo VARCHAR(2) NOT NULL CHECK (tipo IN ('PF', 'PJ'))
);

CREATE TABLE condutor (
    id SERIAL PRIMARY KEY,
    cliente_id INT NOT NULL,
    cnh VARCHAR(20) NOT NULL UNIQUE,
    validade DATE NOT NULL,
    categoria VARCHAR(5) NOT NULL,
    
    FOREIGN KEY (cliente_id) REFERENCES cliente(id)
        ON DELETE CASCADE
);

CREATE TABLE grupo_veiculo (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(50) NOT NULL,
    categoria VARCHAR(50) NOT NULL
);

CREATE TABLE veiculo (
    id SERIAL PRIMARY KEY,
    placa VARCHAR(10) NOT NULL UNIQUE,
    modelo VARCHAR(50) NOT NULL,
    status VARCHAR(20) NOT NULL CHECK (status IN ('disponivel', 'alugado', 'manutencao')),
    grupo_id INT NOT NULL,

    FOREIGN KEY (grupo_id) REFERENCES grupo_veiculo(id)
);

CREATE TABLE reserva (
    id SERIAL PRIMARY KEY,
    cliente_id INT NOT NULL,
    grupo_id INT NOT NULL,
    data_inicio DATE NOT NULL,
    data_fim DATE NOT NULL,
    
    CHECK (data_fim >= data_inicio),

    FOREIGN KEY (cliente_id) REFERENCES cliente(id),
    FOREIGN KEY (grupo_id) REFERENCES grupo_veiculo(id)
);

CREATE TABLE patio (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(50) NOT NULL,
    cidade VARCHAR(50) NOT NULL
);

CREATE TABLE locacao (
    id SERIAL PRIMARY KEY,
    reserva_id INT UNIQUE, -- garante 1:1 opcional
    veiculo_id INT NOT NULL,
    patio_retirada_id INT NOT NULL,
    patio_devolucao_id INT NOT NULL,
    data_retirada TIMESTAMP NOT NULL,
    data_devolucao TIMESTAMP,

    CHECK (data_devolucao IS NULL OR data_devolucao >= data_retirada),

    FOREIGN KEY (reserva_id) REFERENCES reserva(id),
    FOREIGN KEY (veiculo_id) REFERENCES veiculo(id),
    FOREIGN KEY (patio_retirada_id) REFERENCES patio(id),
    FOREIGN KEY (patio_devolucao_id) REFERENCES patio(id)
);

CREATE TABLE cobranca (
    id SERIAL PRIMARY KEY,
    locacao_id INT UNIQUE NOT NULL,
    valor DECIMAL(10,2) NOT NULL CHECK (valor >= 0),
    status VARCHAR(20) NOT NULL CHECK (status IN ('pendente', 'pago', 'cancelado')),
    data_pagamento DATE,

    FOREIGN KEY (locacao_id) REFERENCES locacao(id)
        ON DELETE CASCADE
);

CREATE TABLE seguro (
    id SERIAL PRIMARY KEY,
    tipo VARCHAR(50) NOT NULL,
    valor DECIMAL(10,2) NOT NULL CHECK (valor >= 0)
);

CREATE TABLE locacao_seguro (
    locacao_id INT NOT NULL,
    seguro_id INT NOT NULL,

    PRIMARY KEY (locacao_id, seguro_id),

    FOREIGN KEY (locacao_id) REFERENCES locacao(id)
        ON DELETE CASCADE,
    FOREIGN KEY (seguro_id) REFERENCES seguro(id)
);

CREATE TABLE foto (
    id SERIAL PRIMARY KEY,
    veiculo_id INT NOT NULL,
    url TEXT NOT NULL,
    tipo VARCHAR(50),

    FOREIGN KEY (veiculo_id) REFERENCES veiculo(id)
        ON DELETE CASCADE
);

CREATE TABLE manutencao (
    id SERIAL PRIMARY KEY,
    veiculo_id INT NOT NULL,
    data DATE NOT NULL,
    descricao TEXT NOT NULL,

    FOREIGN KEY (veiculo_id) REFERENCES veiculo(id)
        ON DELETE CASCADE
);