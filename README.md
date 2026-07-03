# postgres-index-benchmark

Mini projeto tecnico em PostgreSQL, SQL e analise de performance com
`EXPLAIN ANALYZE`.

O objetivo e comparar a mesma consulta antes e depois da criacao de um indice
composto, mostrando a mudanca no plano de execucao e no tempo observado.

Tema usado como guia do experimento:

> Indice muda mesmo uma consulta? Testando na pratica com PostgreSQL e EXPLAIN ANALYZE

## Objetivo

Demonstrar, de forma simples e pratica, como um indice composto pode ajudar o
PostgreSQL a executar uma consulta especifica com mais eficiencia.

O projeto usa `EXPLAIN (ANALYZE, BUFFERS)` para comparar:

- consulta antes do indice;
- criacao do indice composto;
- mesma consulta depois do indice.

## Contexto

A tabela `orders` simula pedidos de uma aplicacao backend. O experimento busca
pedidos de um cliente especifico, com um status especifico, ordenando os pedidos
mais recentes e limitando o retorno.

Este projeto nao usa API, ORM, framework web, `.env` ou dados reais. O foco e
SQL, PostgreSQL e leitura basica de plano de execucao.

## Tecnologias

- PostgreSQL 16
- SQL
- `EXPLAIN (ANALYZE, BUFFERS)`
- Docker Compose
- PowerShell ou Bash para automacao
- Python opcional para gerar grafico

## O Que E Um Indice

Um indice e uma estrutura auxiliar que ajuda o banco a encontrar linhas com mais
eficiencia em certos tipos de consulta.

Ele pode reduzir a quantidade de dados lidos, mas tambem tem custo de
armazenamento e pode deixar escritas mais caras, porque o indice precisa ser
atualizado em operacoes de `INSERT`, `UPDATE` e `DELETE`.

## O Que E EXPLAIN ANALYZE

`EXPLAIN` mostra o plano que o PostgreSQL pretende usar para executar uma
consulta.

`EXPLAIN ANALYZE` executa a consulta de fato e mostra tempos reais, linhas
processadas e outras informacoes. Com `BUFFERS`, tambem e possivel observar
blocos encontrados em cache ou lidos durante a execucao.

## Estrutura

```text
postgres-index-benchmark/
|-- docker-compose.yml
|-- sql/
|   |-- 01_create_schema.sql
|   |-- 02_seed_data.sql
|   |-- 03_query_before_index.sql
|   |-- 04_create_index.sql
|   |-- 05_query_after_index.sql
|   `-- 06_cleanup.sql
|-- scripts/
|   |-- run-benchmark.sh
|   |-- run-benchmark.ps1
|   |-- generate_chart.py
|   `-- requirements.txt
|-- results/
|   |-- README.md
|   |-- before-index.txt
|   |-- after-index.txt
|   |-- summary.csv
|   |-- resource-summary.csv
|   |-- benchmark-results.png
|   `-- execution-time-comparison.png
|-- README.md
|-- LICENSE
`-- .gitignore
```

Os arquivos `results/benchmark-results.png` e
`results/execution-time-comparison.png` sao gerados opcionalmente pelo script de
grafico.

## Como Executar

### Requisitos

- Docker
- Docker Compose
- Python 3, apenas se quiser gerar o grafico opcional

### 1. Subir o PostgreSQL

```bash
docker compose up -d
```

Para conferir se o container ficou saudavel:

```bash
docker compose ps
```

### 2. Rodar o benchmark

No Windows PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-benchmark.ps1
```

Ou, se a politica local ja permitir a execucao de scripts:

```powershell
.\scripts\run-benchmark.ps1
```

No Linux, macOS ou WSL:

```bash
bash scripts/run-benchmark.sh
```

Os scripts fazem o fluxo completo:

- sobem o PostgreSQL com Docker Compose;
- aguardam o banco ficar disponivel;
- criam a tabela `orders`;
- inserem 500.000 registros ficticios;
- executam a consulta antes do indice;
- criam o indice composto;
- executam a mesma consulta depois do indice;
- salvam os resultados e resumos em `results/`.

### 3. Conferir os arquivos gerados

Depois da execucao, abra:

- `results/before-index.txt`
- `results/after-index.txt`
- `results/summary.csv`
- `results/resource-summary.csv`

Esses arquivos contem os planos reais, os tempos e os indicadores de recursos
extraidos da execucao local.

### 4. Gerar o grafico opcional

Instale as dependencias opcionais:

```bash
pip install -r scripts/requirements.txt
```

Gere o grafico:

```bash
python scripts/generate_chart.py
```

Os arquivos gerados serao:

```text
results/benchmark-results.png
results/execution-time-comparison.png
```

O grafico principal usa apenas os valores de `results/summary.csv` e
`results/resource-summary.csv`. A copia `execution-time-comparison.png` e
mantida por compatibilidade.

## Consulta Analisada

```sql
SELECT
    id,
    customer_id,
    status,
    total_amount,
    created_at
FROM orders
WHERE customer_id = 12345
  AND status = 'PAID'
ORDER BY created_at DESC
LIMIT 20;
```

Antes do indice, o PostgreSQL precisou varrer muitos registros para encontrar as
linhas que atendiam ao filtro e depois ordenar o resultado.

Depois do indice, o PostgreSQL conseguiu usar o indice para buscar os registros
de `customer_id = 12345` e `status = 'PAID'` ja alinhados com
`created_at DESC`.

## Indice Criado

```sql
CREATE INDEX idx_orders_customer_status_created_at
ON orders (customer_id, status, created_at DESC);
```

Esse indice foi escolhido para esta consulta especifica:

- `customer_id` e `status` aparecem no filtro `WHERE`;
- `created_at DESC` aparece no `ORDER BY`;
- a consulta usa `LIMIT 20`, entao encontrar os registros mais recentes mais cedo
  pode reduzir bastante o trabalho.

## Resultados Observados

Nesta execucao local, com 500.000 registros ficticios:

| Cenario | Plano principal | Tempo |
| --- | --- | ---: |
| Antes do indice | `Parallel Seq Scan` + `Sort` | `341.939 ms` |
| Depois do indice | `Index Scan using idx_orders_customer_status_created_at` | `43.730 ms` |

Os valores acima vieram dos arquivos em `results/`:

- `results/before-index.txt`
- `results/after-index.txt`
- `results/summary.csv`

Tambem foi observado em `results/resource-summary.csv`:

| Cenario | Shared hits | Shared reads | Rows removed by filter | Sort memory | Workers |
| --- | ---: | ---: | ---: | ---: | ---: |
| Antes do indice | `5449` | `0` | `166333` | `27 kB` | `2` |
| Depois do indice | `1` | `3` | `0` | `0 kB` | `0` |

Esses indicadores vem do `EXPLAIN (ANALYZE, BUFFERS)`. Eles mostram recursos do
plano dentro do PostgreSQL, como blocos em cache, blocos lidos, linhas
descartadas pelo filtro e memoria usada na etapa de ordenacao. Eles nao medem
CPU ou memoria total do container.

## Como Comparar Os Resultados

Ao abrir os arquivos de resultado, procure por:

- tipo de scan, como `Seq Scan`, `Parallel Seq Scan`, `Index Scan` ou
  `Bitmap Index Scan`;
- `Execution Time`;
- quantidade de linhas processadas;
- `Buffers`, principalmente `shared hit` e `read`;
- `Rows Removed by Filter`;
- memoria usada por `Sort`, quando houver;
- existencia ou nao de etapa de ordenacao, como `Sort`.

## Limites Do Experimento

Este projeto e um experimento simples e controlado. Os resultados podem variar
conforme maquina, versao do PostgreSQL, volume de dados, cache, distribuicao dos
registros e consulta utilizada.

Um indice nao melhora tudo automaticamente. O ganho depende do volume de dados,
seletividade da consulta, tipo de indice, estatisticas, cache e estrutura da
tabela. Indices tambem tem custo em escrita e armazenamento.

## Limpeza Opcional

Para remover o indice criado:

```bash
docker compose exec -T postgres psql -U postgres -d index_benchmark -f /sql/06_cleanup.sql
```

Para parar e remover o volume local do banco:

```bash
docker compose down -v
```

Use este ultimo comando apenas se quiser apagar os dados locais do experimento.

## Possiveis Proximos Passos

- Testar uma consulta com baixa seletividade.
- Comparar indice simples contra indice composto.
- Medir o impacto do indice em operacoes de `INSERT`.
- Repetir a consulta mais de uma vez para observar efeito de cache.
- Criar um post tecnico explicando o antes e depois com trechos dos planos reais.
