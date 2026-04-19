# Sistema de Locação de Veículos

## 1. Objetivo

Desenvolver um banco de dados para gerenciar o sistema transacional de uma locadora de veículos, contemplando os seguintes subsistemas:

- Cadastro de clientes
- Controle de frota de veículos
- Sistema de reservas
- Sistema de locação (aluguel)
- Sistema de cobrança
- Controle de pátio (retirada e devolução)

---

## 2. Visão Geral do Sistema

O sistema permite que clientes realizem reservas de veículos, efetuem locações, realizem retirada e devolução em diferentes pátios e sejam cobrados conforme as condições contratadas.

---

## 3. Regras de Negócio

### 3.1 Veículos

- Cada veículo pertence a um grupo ou categoria, que define sua classe e faixa de preço.
- Cada veículo possui:
  - placa
  - chassi
  - marca
  - modelo
  - cor
  - características (ex: ar-condicionado, tipo de transmissão, acessórios)
- Cada veículo possui:
  - um prontuário (estado de conservação, revisões, segurança)
  - um conjunto de fotos (propaganda e inspeção)

---

### 3.2 Clientes

- Clientes podem ser:
  - Pessoa Física (PF)
  - Pessoa Jurídica (PJ)

- Para clientes PJ:
  - os condutores são cadastrados individualmente

- Cada condutor possui:
  - número da CNH
  - categoria da CNH
  - data de validade

---

### 3.3 Reservas

- O sistema permite reservas por:
  - grupo de veículos
  - ou tipo específico de veículo

- O sistema controla:
  - disponibilidade por data
  - fila de reservas por grupo
  - fila de espera para veículos especiais

---

### 3.4 Locação

- A locação registra:
  - data e hora de retirada (prevista e real)
  - data e hora de devolução (prevista e real)
  - pátio de retirada e devolução
  - veículo alugado
  - condutor

- A locação também registra:
  - estado do veículo na retirada e devolução

---

### 3.5 Cobrança

- A cobrança considera:
  - período da locação
  - condições contratadas
  - proteções adicionais (seguros)

- Pode haver:
  - cobrança inicial (na reserva ou retirada)
  - cobrança final ajustada (na devolução)

---

### 3.6 Proteções e Seguros

- O sistema deve suportar proteções adicionais, como:
  - proteção de vidros
  - proteção de faróis
  - aumento da cobertura de seguro

---

## 4. Observações Importantes para Modelagem

- A reserva não garante um veículo específico, apenas um grupo ou tipo.
- O veículo é associado somente no momento da locação.
- Um veículo não pode estar em mais de uma locação simultaneamente.
- O sistema deve permitir controle de disponibilidade ao longo do tempo.