## Modelo Lógico

O modelo lógico foi construído a partir do modelo conceitual (MER), definindo as tabelas, seus atributos, chaves primárias e estrangeiras, garantindo integridade e normalização dos dados.

---

### Tabela: empresa_locadora
- id (PK)
- nome
- cnpj (UNIQUE)

---

### Tabela: cliente
- id (PK)
- nome
- tipo (PF/PJ)
- cidade

---

### Tabela: condutor
- id (PK)
- cliente_id (FK → cliente.id)
- cnh (UNIQUE)
- validade
- categoria

---

### Tabela: grupo_veiculo
- id (PK)
- nome
- categoria

---

### Tabela: veiculo
- id (PK)
- placa