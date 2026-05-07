# AWS S3 + Athena Data Lake — Medallion Architecture

A production-style **cloud data lake** built on **AWS S3 and Amazon Athena**, implementing a full **Bronze → Silver → Gold** medallion architecture. Raw data from two source systems (CRM and ERP) is stored in S3, transformed using Athena SQL, and modelled into a **Star Schema** ready for analytics — with no servers to manage.

---

## Architecture

```
Data Sources
  ├── CRM System  (cust_info, prd_info, sales_details)
  └── ERP System  (cust_az12, loc_a101, px_cat_g1v2)
         │
         ▼
  ┌─────────────────────────────────────────────┐
  │  AWS S3 — bronze/                           │
  │  External tables via AWS Glue Data Catalog  │
  │  Raw CSVs — no transformations              │
  └─────────────────────────────────────────────┘
         │  Athena CTAS with external_location
         ▼
  ┌─────────────────────────────────────────────┐
  │  AWS S3 — silver/                           │
  │  Cleaned & standardised Parquet tables      │
  │  Deduplication, type casting, null handling │
  └─────────────────────────────────────────────┘
         │  Athena Views (no S3 storage)
         ▼
  ┌─────────────────────────────────────────────┐
  │  AWS Athena — gold schema                   │
  │  Star Schema views: dim + fact              │
  │  Analytics-ready, zero storage cost         │
  └─────────────────────────────────────────────┘
         │
         ▼
  Analytics / Reporting (Athena, QuickSight, etc.)
```

---

## S3 Bucket Structure

```
s3://sneha-datawarehouse-project/
├── bronze/
│   ├── crm/
│   │   ├── cust_info/
│   │   ├── prd_info/
│   │   └── sales_details/
│   └── erp/
│       ├── cust_az12/
│       ├── loc_a101/
│       └── category_info/
└── silver/
    ├── cust_info/        ← Parquet files (CTAS output)
    ├── prd_info/         ← Parquet files (CTAS output)
    ├── sales_details/    ← Parquet files (CTAS output)
    ├── cust_az12/        ← Parquet files (CTAS output)
    ├── loc_a101/         ← Parquet files (CTAS output)
    └── px_cat_g1v2/      ← Parquet files (CTAS output)

Note: Gold layer does not exist in S3.
Gold is implemented as Athena views — metadata only, no physical storage.
```

---

## Tech Stack

| Service | Purpose |
|---------|---------|
| AWS S3 | Data lake storage for Bronze (CSV) and Silver (Parquet) layers |
| Amazon Athena | Serverless SQL engine for all transformations and querying |
| AWS Glue Data Catalog | Schema registry for Bronze external table definitions |
| OpenCSV SerDe | CSV parsing for Bronze external tables |
| Athena CTAS + external_location | Writes Silver Parquet files to explicit S3 paths |
| Athena Views | Gold Star Schema — zero storage cost, always up to date |

---

## Project Structure

```
aws-s3-athena-datalake/
├── scripts/
│   ├── bronze/
│   │   └── ddl_bronze.sql          # External tables pointing to S3 raw CSVs
│   ├── silver/
│   │   └── ddl_silver.sql          # CTAS with external_location + Parquet format
│   └── gold/
│       └── ddl_gold.sql            # Star Schema views: dim_customers, dim_products, fact_sales
│
├── tests/
│   ├── quality_checks_silver.sql   # Null, duplicate, format, range, join checks
│   └── quality_checks_gold.sql     # Surrogate key uniqueness, referential integrity
│
├── docs/
│   ├── data_catalogue.md           # Column-level data dictionary for Gold layer
│   └── screenshots/                # Athena query results and S3 structure proof
│
└── README.md
```

---

## Star Schema — Gold Layer

```
                ┌──────────────────────┐
                │    dim_customers     │
                │──────────────────────│
                │ customer_key  PK     │◄──┐
                │ customer_id          │   │
                │ customer_number      │   │
                │ first_name           │   │
                │ last_name            │   │
                │ gender               │   │
                │ marital_status       │   │
                │ birthdate            │   │
                │ country              │   │
                │ created_date         │   │
                └──────────────────────┘   │
                                           │
┌──────────────────────┐   ┌──────────────┴───────────┐
│    dim_products      │   │        fact_sales         │
│──────────────────────│   │───────────────────────────│
│ product_key  PK      │◄──│ order_number              │
│ product_id           │   │ customer_key     FK       │
│ product_number       │   │ product_key      FK       │
│ product_name         │   │ order_date                │
│ line                 │   │ shipping_date             │
│ cost                 │   │ due_date                  │
│ category             │   │ sales                     │
│ subcategory          │   │ quantity                  │
│ maintenance          │   │ price                     │
│ start_date           │   └───────────────────────────┘
└──────────────────────┘
```

---

## How to Run

### Prerequisites
- AWS account with Athena and S3 access
- IAM role with `AmazonAthenaFullAccess` and `AmazonS3FullAccess`
- Athena query results bucket configured in Athena settings

### Step 1 — Upload source CSVs to S3

Upload CRM and ERP CSVs to the corresponding S3 paths shown in the bucket structure above.

### Step 2 — Create Bronze external tables

Set Athena editor database to `datawarehouse`, then run:
```sql
-- scripts/bronze/ddl_bronze.sql
```
Registers external tables pointing to raw S3 CSVs. No data is moved or copied.

### Step 3 — Build Silver layer

Set Athena editor database to `silver`, then run each table in order:
```sql
-- scripts/silver/ddl_silver.sql
```
CTAS queries with `external_location` read from Bronze, apply all transformations, and write Parquet files to `s3://sneha-datawarehouse-project/silver/`.

### Step 4 — Create Gold views

Set Athena editor database to `gold`, then run:
```sql
-- scripts/gold/ddl_gold.sql
```
Creates three views over Silver. No data is written to S3 — this is expected.

### Step 5 — Run quality checks

```sql
-- After Silver:  tests/quality_checks_silver.sql
-- After Gold:    tests/quality_checks_gold.sql
-- All duplicate/null checks should return 0 rows.
```

---

## Key Engineering Decisions

**Why S3 + Athena instead of a traditional database?**
S3 + Athena is fully serverless — no cluster to provision, no idle compute cost. You pay only per query scanned. For batch analytics workloads this is significantly cheaper than maintaining a dedicated database server.

**Why external tables for Bronze?**
Bronze data must remain unchanged as the raw source of truth. External tables let Athena read CSVs directly from S3 without copying or transforming them, preserving the original data exactly as received from source systems.

**Why `external_location` in Silver CTAS?**
Athena's Hive-style tables require `external_location` instead of `location` to write CTAS output to a specific S3 path. This ensures Silver Parquet files land in clean, predictable S3 locations (`silver/cust_info/`, `silver/prd_info/`, etc.) rather than the default Athena query results bucket.

**Why Parquet for Silver?**
Parquet is columnar and compressed. Compared to raw CSV, Parquet reduces Athena query scan costs significantly and improves query performance — especially for large datasets with many columns where only a subset is queried at a time.

**Why views for Gold?**
Gold views always reflect the latest Silver data without a separate load step. Since Athena charges per data scanned (not per query), views add zero cost overhead — they simply rewrite the query at runtime against Silver tables.

**Why surrogate keys via ROW_NUMBER()?**
Natural keys from source systems can be reused or change meaning over time. Surrogate keys generated by `ROW_NUMBER()` provide stable, system-independent identifiers for dimension-to-fact joins in the Star Schema.

**Why LEAD() for product end dates?**
Product history is encoded implicitly in the source — each new row for a product signals the old version ended. `LEAD()` calculates the end date as one day before the next version's start date, enabling accurate SCD Type 2 tracking without any manual date management.

**Why wrap window functions in subqueries?**
Athena (Presto SQL) does not allow referencing window function aliases in the same SELECT or WHERE clause they are defined in. Wrapping the window function in a subquery first and referencing the alias in the outer query is the correct Athena pattern.

---

## Data Quality Checks Summary

**Silver layer validates:**
- No NULL or duplicate primary keys
- No untrimmed whitespace in string columns
- Gender, marital status, country standardised to consistent values
- Integer dates (YYYYMMDD) parsed correctly — invalid dates nullified
- Sales amount = quantity × price consistency enforced
- Cross-table join health between cust_info, cust_az12, loc_a101, and prd_info

**Gold layer validates:**
- Surrogate key uniqueness in both dimension tables
- No orphaned fact rows (all FKs resolve to a valid dimension record)
- No NULL measures in fact_sales

---

## Author

**Sneha Singh**
[LinkedIn](https://www.linkedin.com/in/sneha-singh-04a1a6254/) • [GitHub](https://github.com/singhsneha10)
