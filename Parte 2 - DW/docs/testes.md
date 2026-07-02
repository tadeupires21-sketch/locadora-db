# Guia dos Testes do Pipeline — Locadora DW

Este documento explica, em linguagem simples, **o que** os testes verificam,
**por que** existem e **como** rodá-los e interpretá-los. Não é preciso ser
especialista em banco de dados para acompanhar.

---

## 1. Por que os testes são em SQL (e não em pytest)?

Pytest é o padrão para projetos **Python**. Mas este pipeline é escrito
inteiramente em **SQL (PostgreSQL)** — não há código Python para testar.
O equivalente ao pytest no mundo PostgreSQL é o **pgTAP** ou, de forma mais
simples e sem instalar nada, **asserções em SQL**.

Uma "asserção" é uma checagem do tipo *"isto deveria ser igual àquilo"*. Se
for, o teste segue em silêncio. Se não for, ele **para na hora e mostra o erro**.
É exatamente o que o `assert` faz no pytest — só que escrito em SQL.

> **Em uma frase:** os testes alimentam o pipeline com dados conhecidos e
> conferem se o resultado é o que deveria ser. Qualquer divergência faz o
> teste falhar com uma mensagem clara.

---

## 2. A peça que tornou os testes possíveis: as funções

Antes, as regras de negócio (como calcular multa, como normalizar um status)
estavam **espalhadas e repetidas** dentro dos scripts de transformação. Isso
torna o teste difícil: não dá para testar um "pedaço de SELECT".

A solução foi extrair essas regras para **funções** reutilizáveis, em
`00-infra/01_functions.sql`. Uma função é uma "caixinha" com entrada e saída
previsíveis. Exemplo:

```
fn_dias_atraso('2026-05-05', '2026-05-03')  →  2
fn_dias_atraso('2026-05-01', '2026-05-03')  →  0   (devolveu antes, não há atraso)
```

Agora os scripts de transformação **chamam essas funções**, e os testes
**testam as mesmas funções**. Ou seja: o teste valida o código que roda de
verdade — não uma cópia que poderia ficar desatualizada.

---

## 3. As três camadas de teste

Pense numa pirâmide: muitos testes pequenos e rápidos na base, poucos testes
grandes no topo.

```
            ▲  poucos, lentos, abrangentes
            │   3) Qualidade de dados   ← o DW final está íntegro?
            │   2) Integração           ← o pipeline inteiro funciona junto?
            │   1) Unitários            ← cada regra isolada está correta?
            ▼  muitos, rápidos, focados
```

### Camada 1 — Testes unitários (`04-tests/01_test_unit_funcoes.sql`)

Testam **uma função de cada vez**, isoladamente. Para cada função há pelo
menos **um caso válido** e **um caso inválido/limite**. Exemplos do que é
verificado:

| Função | Caso válido | Caso inválido / limite |
|---|---|---|
| `fn_normaliza_status_reserva` | `'CANCELADO'` → `cancelada` | `'lixo'` → `desconhecida` |
| `fn_normaliza_placa` | `'abc-1d23'` → `ABC1D23` | `NULL` → `SEMPLACA` |
| `fn_dias_inclusivo` | 1→5 de maio → `5` | datas invertidas → `0` (protegido) |
| `fn_km_rodado` | 10000→10350 → `350` | 5000→4000 → `0` (odômetro invertido) |
| `fn_multa_atraso` | usa valor da origem | sem valor → `dias × diária` |

Não dependem de nenhum dado carregado — são rápidos e podem rodar sozinhos.

### Camada 2 — Teste de integração (`04-tests/02_test_integracao.sql`)

Verifica se o **pipeline inteiro funciona junto**: extração → transformação →
carga. Para isso usamos um **dataset de exemplo** (os "fixtures").

Os fixtures (`00_fixtures_oltp_g1.sql`) são uma fonte de dados **falsa, porém
controlada**, do Grupo 1. Eles incluem de propósito casos difíceis:
- um cliente **sem nome**;
- um veículo **sem placa**;
- um veículo com **status inválido**;
- uma locação **atrasada**, uma **devolvida antes do prazo** e uma com
  **quilometragem invertida**.

Depois de rodar o pipeline sobre esses dados, o teste confere valores
específicos no DW. Exemplo real do que ele assere:

> A locação `1-1` foi retirada 5 dias atrás e devolvida ontem, com previsão
> de devolução para 3 dias atrás. Então o DW **tem que** mostrar:
> `dias_realizados = 5`, `atraso = 2 dias`, `multa = 200,00` (2 dias × R$100).

Se o DW mostrar outro número, algo no pipeline quebrou — e o teste aponta onde.

### Camada 3 — Qualidade de dados (`04-tests/03_test_qualidade_dados.sql`)

Não olha valores específicos; olha a **saúde geral** do DW depois da carga.
Cobre as cinco perguntas clássicas de qualidade:

| Dimensão | Pergunta que responde |
|---|---|
| **Nulidade** | Alguma coluna obrigatória ficou vazia? |
| **Unicidade** | Algum ID/chave duplicou? |
| **Domínio** | Algum status saiu da lista de valores permitidos? |
| **Referencial** | Alguma chave estrangeira aponta para um registro que não existe? |
| **Volume** | Alguma tabela essencial veio vazia? |

Este script é **reutilizável em produção**: rodando-o após cada carga real,
ele funciona como um "portão de qualidade" que barra dados corrompidos.

---

## 4. Como rodar

Pré-requisitos: ter o `psql` (cliente PostgreSQL) instalado e as variáveis de
conexão configuradas (`PGHOST`, `PGDATABASE`, `PGUSER`, etc.), **apontando para
um banco de teste** — o teste recria o schema do DW.

```powershell
# Roda a suíte completa (unitários + integração + qualidade)
.\04-tests\run_tests.ps1

# Roda só os testes unitários (não tocam em dados, são instantâneos)
.\04-tests\run_tests.ps1 -OnlyUnit
```

O runner executa cada etapa com a opção `ON_ERROR_STOP=1`, o que significa:
**na primeira falha, ele para e retorna erro**. Nenhuma falha passa despercebida.

---

## 5. Como interpretar o resultado

### Quando tudo passa
Você verá mensagens como:
```
✅ TESTES UNITÁRIOS: todas as asserções passaram.
✅ TESTE DE INTEGRAÇÃO: todas as asserções passaram.
✅ QUALIDADE DE DADOS: todas as asserções passaram.
=== ✅ TODOS OS TESTES PASSARAM ===
```

### Quando algo falha
O teste para e mostra **exatamente** o que estava errado. Exemplo:
```
ERRO:  FALHOU [L1 atraso_devolucao_dias]: obtido=[3] esperado=[2]
```
Leitura: *"no teste do atraso da locação 1, o pipeline calculou 3 dias, mas o
correto era 2"*. O rótulo entre colchetes diz qual checagem falhou, e os
valores `obtido`/`esperado` mostram a diferença — o suficiente para localizar
o problema no código.

Para qualidade de dados a mensagem é parecida:
```
ERRO:  QUALIDADE FALHOU [dim_veiculo.status fora do domínio]: 4 violação(ões) encontrada(s).
```
Leitura: *"4 veículos têm um status que não está na lista permitida"*.

---

## 6. O que os testes **garantem** e o que **não** garantem

**Garantem:**
- Que cada regra de negócio (multa, atraso, status, placa…) está correta.
- Que o pipeline do Grupo 1 roda inteiro sem erro e produz os números certos.
- Que o DW carregado respeita nulidade, unicidade, domínio e integridade.

**Ainda não garantem** (ver `04-tests/CHECKLIST.md` para a lista completa):
- Os **Grupos 2, 3 e 4** — só o Grupo 1 tem dataset de teste, porque os
  modelos de origem dos outros grupos não estão disponíveis no projeto.
- **Idempotência** — rodar duas vezes e conferir que nada duplica.
- **Falha de fonte** — simular um grupo indisponível.
- **Reconciliação das views** analíticas contra os fatos.

---

## 7. Glossário rápido

- **Asserção**: checagem "X deveria ser Y"; falha se não for.
- **Fixture**: conjunto de dados de exemplo, fixo e controlado, usado no teste.
- **Teste unitário**: testa uma peça isolada (uma função).
- **Teste de integração**: testa várias peças funcionando juntas (o pipeline).
- **Qualidade de dados**: checagens sobre nulos, duplicados, domínio, etc.
- **Domínio**: o conjunto de valores válidos de um campo (ex.: tipo só pode
  ser `PF` ou `PJ`).
- **Integridade referencial**: toda chave estrangeira aponta para um registro
  que de fato existe.
- **Idempotência**: rodar a mesma carga várias vezes produz sempre o mesmo
  resultado, sem duplicar.

---

## 8. Arquivos relacionados

- `00-infra/01_functions.sql` — as funções testadas.
- `04-tests/00_fixtures_oltp_g1.sql` — dados de exemplo.
- `04-tests/01_test_unit_funcoes.sql` — testes unitários.
- `04-tests/02_test_integracao.sql` — teste de integração.
- `04-tests/03_test_qualidade_dados.sql` — validações de qualidade.
- `04-tests/run_tests.ps1` — executa tudo.
- `04-tests/CHECKLIST.md` — o que falta testar.
