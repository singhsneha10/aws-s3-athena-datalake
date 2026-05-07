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
         │  Athena CTAS (CREATE TABLE AS SELECT)
         ▼
  ┌─────────────────────────────────────────────┐
  │  AWS S3 — silver/                           │
  │  Cleaned & standardised Parquet tables      │
  │  Deduplication, type casting, null handling │
  └─────────────────────────────────────────────┘
         │  Athena Views
         ▼
  ┌─────────────────────────────────────────────┐
  │  AWS Athena — gold/                         │
  │  Star Schema views: dim + fact              │
  │  Analytics-ready, no storage cost           │
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
├── silver/
│   ├── cust_info/
│   ├── prd_info/
│   ├── sales_details/
│   ├── cust_az12/
│   ├── loc_a101/
│   └── px_cat_g1v2/
└── gold/             ← views only, no physical storage
```

---

## Tech Stack

| Service | Purpose |
|---------|---------|
| AWS S3 | Data lake storage across all three layers |
| Amazon Athena | Serverless SQL engine for transformations and querying |
| AWS Glue Data Catalog | Schema registry for Bronze external tables |
| OpenCSV SerDe | CSV parsing for Bronze external table definitions |
| Athena CTAS | Materialises Silver layer transformations into S3 |
| Athena Views | Gold layer Star Schema — zero storage cost |

---

## Project Structure

```
aws-s3-athena-datalake/
├── scripts/
│   ├── bronze/
│   │   └── ddl_bronze.sql          # External tables pointing to S3 raw CSVs
│   ├── silver/
│   │   └── ddl_silver.sql          # CTAS transformations: clean, type, dedupe
│   └── gold/
│       └── ddl_gold.sql            # Star Schema views: dim_customers, dim_products, fact_sales
│
├── tests/
│   ├── quality_checks_silver.sql   # Null, duplicate, format, range checks
│   └── quality_checks_gold.sql     # Surrogate key uniqueness, referential integrity
│
├── docs/
│   └── data_catalogue.md           # Column-level data dictionary for Gold layer
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
- Athena query results bucket configured

### Step 1 — Upload source CSVs to S3

Upload your CRM and ERP CSVs to the corresponding S3 paths shown in the bucket structure above.

### Step 2 — Create Bronze external tables

```sql
-- Run in Athena query editor:
-- scripts/bronze/ddl_bronze.sql
```

This registers external tables pointing to your S3 raw files. No data is moved.

### Step 3 — Build Silver layer

```sql
-- Run in Athena query editor:
-- scripts/silver/ddl_silver.sql
```

CTAS queries read from Bronze, apply all transformations, and write clean Parquet files to `s3://.../silver/`.

### Step 4 — Create Gold views

```sql
-- Run in Athena query editor:
-- scripts/gold/ddl_gold.sql
```

Creates three views (dim_customers, dim_products, fact_sales) over Silver. No data is written to S3.

### Step 5 — Run quality checks

```sql
-- After Silver:  tests/quality_checks_silver.sql
-- After Gold:    tests/quality_checks_gold.sql
-- All queries should return 0 rows.
```

---

## Key Engineering Decisions

**Why S3 + Athena instead of a traditional database?**
S3 + Athena is serverless — no cluster to provision, no idle cost. You pay only per query scanned. For batch analytics workloads this is significantly cheaper than running a dedicated database server.

**Why external tables for Bronze?**
Bronze data must remain unchanged as the raw source of truth. External tables let Athena read the CSVs directly from S3 without copying or transforming them, preserving the original data.

**Why CTAS for Silver?**
CTAS (CREATE TABLE AS SELECT) materialises the transformation output as Parquet files in S3. Parquet is columnar, compressed, and much faster to query than raw CSV — reducing both query time and Athena scan costs.

**Why views for Gold?**
Gold views always reflect the latest Silver data without an additional load step. Since Athena charges per data scanned (not per query), views add zero overhead — they simply rewrite the query at runtime.

**Why surrogate keys via ROW_NUMBER()?**
Natural keys from source systems can be reused or change meaning over time. Surrogate keys generated by `ROW_NUMBER()` provide stable, system-independent identifiers for dimension-to-fact joins.

**Why LEAD() for product end dates?**
Product history is encoded implicitly in the source — each new row for a product signals the old version ended. `LEAD()` calculates the end date as one day before the next version's start date, enabling accurate SCD Type 2 tracking.

---

## Data Quality Checks Summary

**Silver layer validates:**
- No NULL or duplicate primary keys
- No untrimmed whitespace in string columns
- Gender, marital status, country standardised to consistent values
- Integer dates (YYYYMMDD) parsed correctly — invalid dates nullified
- Sales amount = quantity × price consistency enforced

**Gold layer validates:**
- Surrogate key uniqueness in both dimension tables
- No orphaned fact rows (all FKs resolve to a dimension record)
- No NULL measures in fact_sales

---

## Author

**Sneha Singh**
[LinkedIn](https://www.linkedin.com/in/sneha-singh-04a1a6254/) • [GitHub](https://github.com/singhsneha10)
