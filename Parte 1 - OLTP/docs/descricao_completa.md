# Sistema de Locação de Veículos

## Objetivo
-Desenvolver um banco de dados para gerenciar o sistema transacional de uma locadora de veículos para modelar os dados dos sistemas de Cadastro do Clientes, Controle de Frota de Veículos, Sistemas de Reserva, Sistema de acompanhamento de Locação, Sistema de CObrança e de Controle de Pátio.


## Regras de Negócio

- o sistema suporta a realização de reserva de veículos, efetiva e controla a locação( aluguel), apoia a retirada e devolução do veículo em um dos pátios, e que realiza a cobrança da locação.
- Cada veículo possui: grupo ou categoria(classificação dada pela locadora para resumir a classe de luxo do veículo e a faixa de valor do aluguel por dia), placa, chassis e uma lista de acesórios e características próprias, tais como marca, modelo, cor, tem ou não ar-condicionado, manual ou automático, possui cadeirinha para criança, e demais dados técnicos como dimensão etc.
- Cada veículo possui um prontuário para acompanhar o estado de conservação, revisões e características de rodagem e segurança( pressão dos pneus, nível de óleio etc.)
- Cada veículo possui um conjunto de fotos associadas, sejam elas para propaganda, seja elas para acompanhar o estado de entrega e devolução dos veículos.

- Os clientes( locatários) pode ser pessoas físicas ou jurídicas. Caso sejam PJ os seus funcionários são individualizados para efeitos de controle do condutor do veículo junto as autoridades competentes, detalhes dos motoristas, temos número da CNH, categoria da CNH( para que veículos o condutor está habilitado) e a data de expiração da CNH. Também considere os dados do cliente para realizar o contrato de locação e a sua cobrança.
- O subsistema de reservas controla a frota disponíveis por data, com finalidade de ofertar ao cliente as possibilidades para locação. A partir disso, o sistema pode controlar a fila de reserva por cada grupo de veículo, ou "tipo" de veículo em particular ( por exemplo Fiat Argo S-design, automático, branco, com ar-condicionado, a locadora pode possuir dez deles na frota, uns alugados, outros com janelas de disponinilização). Também, pode controlar uma eventual fila de espera pelos veículos, em particular pelos tipos especiais de veículos( exemplo adaptados para cadeirante), que pode ter desistência.
- O subsistema de controle de locação, possui os dados de data e hora da retirada e devolução( prevista e realizada), pátio de saída e de chegada, além claro, dos dados do condutor ( cliente), e veículo alugado (estado de entrega e de devolução). Também tem os dados das proteções adicionais contratadas junto a parte do seguro obrigatório básico, tais como, proteção de vidros e faróis, faixa de indenização maior etc. Todos esses dados são utilizados para ajustar a cobrança final ( pois já pode ter havido uma cobrança incial, baseada na realização de todos os prazos e condições inicialmente contratada.)