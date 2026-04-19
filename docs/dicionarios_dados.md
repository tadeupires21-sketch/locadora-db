# Dicionário de Dados - Sistema de Locação de Veículos

Este documento descreve as tabelas, atributos e restrições do banco de dados.

---

## Tabela: cliente

| Campo | Tipo | Descrição | Restrição |
|------|------|----------|----------|
| id | SERIAL | Identificador único do cliente | PK |
| nome | VARCHAR(100) | Nome do cliente | NOT NULL |
| tipo | VARCHAR(2) | Tipo de cliente (PF ou PJ) | NOT NULL, CHECK |

---

## Tabela: condutor

| Campo | Tipo | Descrição | Restrição |
|------|------|----------|----------|
| id | SERIAL | Identificador do condutor | PK |
| cliente_id | INT | Cliente ao qual pertence | FK, NOT NULL |
| cnh | VARCHAR(20) | Número da CNH | UNIQUE, NOT NULL |
| validade | DATE | Validade da CNH | NOT NULL |
| categoria | VARCHAR(5) | Categoria da CNH | NOT NULL |

---

## Tabela: grupo_veiculo

| Campo | Tipo | Descrição | Restrição |
|------|------|----------|----------|
| id | SERIAL | Identificador do grupo | PK |
| nome | VARCHAR(50) | Nome do grupo | NOT NULL |
| categoria | VARCHAR(50) | Categoria do veículo | NOT NULL |

---

## Tabela: veiculo

| Campo | Tipo | Descrição | Restrição |
|------|------|----------|----------|
| id | SERIAL | Identificador do veículo | PK |
| placa | VARCHAR(10) | Placa do veículo | UNIQUE, NOT NULL |
| modelo | VARCHAR(50) | Modelo do veículo | NOT NULL |
| status | VARCHAR(20) | Status do veículo | CHECK, NOT NULL |
| grupo_id | INT | Grupo do veículo | FK, NOT NULL |

---

## Tabela: reserva

| Campo | Tipo | Descrição | Restrição |
|------|------|----------|----------|
| id | SERIAL | Identificador da reserva | PK |
| cliente_id | INT | Cliente que fez a reserva | FK, NOT NULL |
| grupo_id | INT | Grupo reservado | FK, NOT NULL |
| data_inicio | DATE | Data inicial | NOT NULL |
| data_fim | DATE | Data final | CHECK, NOT NULL |

---

## Tabela: locacao

| Campo | Tipo | Descrição | Restrição |
|------|------|----------|----------|
| id | SERIAL | Identificador da locação | PK |
| reserva_id | INT | Reserva associada | FK, UNIQUE |
| veiculo_id | INT | Veículo utilizado | FK, NOT NULL |
| patio_retirada_id | INT | Pátio de retirada | FK, NOT NULL |
| patio_devolucao_id | INT | Pátio de devolução | FK, NOT NULL |
| data_retirada | TIMESTAMP | Data de retirada | NOT NULL |
| data_devolucao | TIMESTAMP | Data de devolução | CHECK |

---

## Tabela: patio

| Campo | Tipo | Descrição | Restrição |
|------|------|----------|----------|
| id | SERIAL | Identificador do pátio | PK |
| nome | VARCHAR(50) | Nome do pátio | NOT NULL |
| cidade | VARCHAR(50) | Cidade do pátio | NOT NULL |

---

## Tabela: cobranca

| Campo | Tipo | Descrição | Restrição |
|------|------|----------|----------|
| id | SERIAL | Identificador da cobrança | PK |
| locacao_id | INT | Locação associada | FK, UNIQUE |
| valor | DECIMAL | Valor da cobrança | CHECK, NOT NULL |
| status | VARCHAR(20) | Status da cobrança | CHECK, NOT NULL |
| data_pagamento | DATE | Data de pagamento | |

---

## Tabela: seguro

| Campo | Tipo | Descrição | Restrição |
|------|------|----------|----------|
| id | SERIAL | Identificador do seguro | PK |
| tipo | VARCHAR(50) | Tipo de seguro | NOT NULL |
| valor | DECIMAL | Valor do seguro | CHECK |

---

## Tabela: locacao_seguro

| Campo | Tipo | Descrição | Restrição |
|------|------|----------|----------|
| locacao_id | INT | Locação | PK, FK |
| seguro_id | INT | Seguro | PK, FK |

---

## Tabela: foto

| Campo | Tipo | Descrição | Restrição |
|------|------|----------|----------|
| id | SERIAL | Identificador da foto | PK |
| veiculo_id | INT | Veículo associado | FK |
| url | TEXT | Caminho da imagem | NOT NULL |
| tipo | VARCHAR(50) | Tipo da foto | |

---

## Tabela: manutencao

| Campo | Tipo | Descrição | Restrição |
|------|------|----------|----------|
| id | SERIAL | Identificador | PK |
| veiculo_id | INT | Veículo associado | FK |
| data | DATE | Data da manutenção | NOT NULL |
| descricao | TEXT | Descrição do serviço | NOT NULL |