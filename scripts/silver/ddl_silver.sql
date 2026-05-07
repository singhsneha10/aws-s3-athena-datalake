/*
===============================================================================
DDL Script: Silver Layer — Cleaned & Standardised Tables
===============================================================================
Purpose:
    Transforms raw Bronze data into cleaned, typed, deduplicated Silver tables.
    Stored as Athena CTAS using external_location — writes Parquet files
    directly to dedicated S3 paths under silver/.

Transformations applied:
    - Null handling and default values
    - String trimming and standardisation (gender, marital status, country)
    - Date parsing from integer format (YYYYMMDD → DATE)
    - Deduplication via ROW_NUMBER() window function (wrapped in subquery)
    - Sales amount validation (quantity × price consistency)
    - Product lifecycle tracking via LEAD() window function (wrapped in subquery)

Notes:
    - Uses external_location instead of location (required for Hive-style tables in Athena)
    - Uses format = 'PARQUET' for columnar storage — faster queries, lower scan cost
    - Window function aliases must be resolved in a subquery before being referenced
      in WHERE or outer SELECT — Athena requirement

Run Order:
    1. Set Athena editor database to 'silver' before running
    2. Run bronze/ddl_bronze.sql first
    3. Run each section below in order
===============================================================================
*/

CREATE SCHEMA IF NOT EXISTS silver;


-- ============================================================
-- silver.cust_info — CRM Customer Master
-- ============================================================
-- Deduplicates by cst_id (keep latest record via ROW_NUMBER),
-- trims strings, standardises gender and marital status codes.

DROP TABLE IF EXISTS silver.cust_info;
CREATE TABLE silver.cust_info
WITH (
    external_location = 's3://sneha-datawarehouse-project/silver/cust_info/',
    format = 'PARQUET'
) AS
SELECT
    cst_id,
    cst_key,
    cst_firstname,
    cst_lastname,
    cst_marital_status,
    cst_gndr,
    cst_create_date
FROM (
    SELECT
        cst_id,
        cst_key,
        TRIM(cst_firstname) AS cst_firstname,
        TRIM(cst_lastname)  AS cst_lastname,
        CASE
            WHEN UPPER(TRIM(cst_marital_status)) = 'S' THEN 'Single'
            WHEN UPPER(TRIM(cst_marital_status)) = 'M' THEN 'Married'
            ELSE 'n/a'
        END AS cst_marital_status,
        CASE
            WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
            WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
            ELSE 'n/a'
        END AS cst_gndr,
        cst_create_date,
        ROW_NUMBER() OVER (
            PARTITION BY cst_id
            ORDER BY cst_create_date DESC
        ) AS rn
    FROM datawarehouse.cust_info
)
WHERE rn = 1;


-- ============================================================
-- silver.prd_info — CRM Product Master
-- ============================================================
-- Extracts category ID from product key, decodes product line codes,
-- derives product end dates using LEAD() for SCD Type 2 tracking.
-- Wrapped in subquery so window function aliases resolve correctly.

DROP TABLE IF EXISTS silver.prd_info;
CREATE TABLE silver.prd_info
WITH (
    external_location = 's3://sneha-datawarehouse-project/silver/prd_info/',
    format = 'PARQUET'
) AS
SELECT
    prd_id,
    cat_id,
    prd_key,
    prd_nm,
    prd_cost,
    prd_line,
    prd_start_dt,
    prd_end_dt
FROM (
    SELECT
        prd_id,
        REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_') AS cat_id,
        SUBSTRING(prd_key, 7)                         AS prd_key,
        prd_nm,
        COALESCE(prd_cost, 0)                         AS prd_cost,
        CASE
            WHEN UPPER(TRIM(prd_line)) = 'M' THEN 'Mountain'
            WHEN UPPER(TRIM(prd_line)) = 'R' THEN 'Road'
            WHEN UPPER(TRIM(prd_line)) = 'S' THEN 'Other Sales'
            WHEN UPPER(TRIM(prd_line)) = 'T' THEN 'Touring'
            ELSE 'n/a'
        END AS prd_line,
        CAST(prd_start_dt AS DATE) AS prd_start_dt,
        CAST(
            DATE_ADD('day', -1,
                LEAD(CAST(prd_start_dt AS DATE))
                OVER (PARTITION BY prd_key ORDER BY prd_start_dt)
            ) AS DATE
        ) AS prd_end_dt
    FROM datawarehouse.prd_info
);


-- ============================================================
-- silver.sales_details — CRM Sales Transactions
-- ============================================================
-- Parses integer dates (YYYYMMDD) to DATE type with null safety,
-- recalculates sales amount where quantity × price is inconsistent.

DROP TABLE IF EXISTS silver.sales_details;
CREATE TABLE silver.sales_details
WITH (
    external_location = 's3://sneha-datawarehouse-project/silver/sales_details/',
    format = 'PARQUET'
) AS
SELECT
    sls_ord_num,
    sls_prd_key,
    TRY_CAST(sls_cust_id AS INT) AS sls_cust_id,
    CASE
        WHEN sls_order_dt = 0 OR LENGTH(CAST(sls_order_dt AS VARCHAR)) != 8 THEN NULL
        ELSE DATE_PARSE(CAST(sls_order_dt AS VARCHAR), '%Y%m%d')
    END AS sls_order_dt,
    CASE
        WHEN sls_ship_dt = 0 OR LENGTH(CAST(sls_ship_dt AS VARCHAR)) != 8 THEN NULL
        ELSE DATE_PARSE(CAST(sls_ship_dt AS VARCHAR), '%Y%m%d')
    END AS sls_ship_dt,
    CASE
        WHEN sls_due_dt = 0 OR LENGTH(CAST(sls_due_dt AS VARCHAR)) != 8 THEN NULL
        ELSE DATE_PARSE(CAST(sls_due_dt AS VARCHAR), '%Y%m%d')
    END AS sls_due_dt,
    CASE
        WHEN sls_sales IS NULL OR sls_sales <= 0
            OR sls_sales != sls_quantity * ABS(sls_price)
            THEN sls_quantity * ABS(sls_price)
        ELSE sls_sales
    END AS sls_sales,
    sls_quantity,
    CASE
        WHEN sls_price IS NULL OR sls_price <= 0
            THEN sls_sales / NULLIF(sls_quantity, 0)
        ELSE sls_price
    END AS sls_price
FROM datawarehouse.sales_details;


-- ============================================================
-- silver.cust_az12 — ERP Customer Demographics
-- ============================================================
-- Strips 'NAS' prefix from customer IDs for join compatibility,
-- nullifies future birthdates, standardises gender values.

DROP TABLE IF EXISTS silver.cust_az12;
CREATE TABLE silver.cust_az12
WITH (
    external_location = 's3://sneha-datawarehouse-project/silver/cust_az12/',
    format = 'PARQUET'
) AS
SELECT
    CASE
        WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4, LENGTH(cid))
        ELSE cid
    END AS cid,
    CASE
        WHEN CAST(bdate AS DATE) > CURRENT_DATE THEN NULL
        ELSE CAST(bdate AS DATE)
    END AS bdate,
    CASE
        WHEN UPPER(TRIM(gen)) IN ('F', 'FEMALE') THEN 'Female'
        WHEN UPPER(TRIM(gen)) IN ('M', 'MALE')   THEN 'Male'
        ELSE 'n/a'
    END AS gen
FROM datawarehouse.cust_az12;


-- ============================================================
-- silver.loc_a101 — ERP Customer Location
-- ============================================================
-- Removes dashes from customer IDs, standardises country names.

DROP TABLE IF EXISTS silver.loc_a101;
CREATE TABLE silver.loc_a101
WITH (
    external_location = 's3://sneha-datawarehouse-project/silver/loc_a101/',
    format = 'PARQUET'
) AS
SELECT
    REPLACE(cid, '-', '') AS cid,
    CASE
        WHEN UPPER(TRIM(cntry)) IN ('US', 'USA', 'UNITED STATES') THEN 'United States'
        WHEN UPPER(TRIM(cntry)) = 'DE'                            THEN 'Germany'
        WHEN TRIM(cntry) = ''                                      THEN 'n/a'
        ELSE cntry
    END AS cntry
FROM datawarehouse.loc_a101;


-- ============================================================
-- silver.px_cat_g1v2 — ERP Product Category Hierarchy
-- ============================================================
-- Pass-through with schema alignment for Gold layer joins.

DROP TABLE IF EXISTS silver.px_cat_g1v2;
CREATE TABLE silver.px_cat_g1v2
WITH (
    external_location = 's3://sneha-datawarehouse-project/silver/px_cat_g1v2/',
    format = 'PARQUET'
) AS
SELECT
    id,
    cat,
    subcat,
    maintenance
FROM datawarehouse.px_cat_g1v2;