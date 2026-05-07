/*
===============================================================================
DDL Script: Gold Layer — Star Schema Views
===============================================================================
Purpose:
    Creates analytics-ready views over the Silver layer.
    Gold layer implements a Star Schema with two dimension tables
    and one fact table — all as Athena views.

Why views and not tables?
    Views have zero S3 storage cost. They rewrite the query at runtime,
    always reflecting the latest Silver data without a separate load step.
    Since Athena charges per data scanned (not per query), views add no overhead.

Data Model:
    dim_customers ──┐
                    ├── fact_sales
    dim_products  ──┘

Notes:
    - Set Athena editor database to 'gold' before running
    - Run silver/ddl_silver.sql first — views depend on Silver tables
    - Gold does NOT create any files in S3 — this is expected behaviour
===============================================================================
*/

CREATE SCHEMA IF NOT EXISTS gold;


-- ============================================================
-- gold.dim_customers — Customer Dimension
-- ============================================================
-- Integrates CRM customer master with ERP demographics and location.
-- Assigns surrogate key via ROW_NUMBER().
-- CRM is the primary source for gender; ERP is the fallback.

DROP VIEW IF EXISTS gold.dim_customers;
CREATE VIEW gold.dim_customers AS
SELECT
    ROW_NUMBER() OVER (ORDER BY ci.cst_id)  AS customer_key,
    ci.cst_id                               AS customer_id,
    ci.cst_key                              AS customer_number,
    ci.cst_firstname                        AS first_name,
    ci.cst_lastname                         AS last_name,
    ca.bdate                                AS birthdate,
    CASE
        WHEN ci.cst_gndr != 'n/a' THEN ci.cst_gndr
        ELSE COALESCE(ca.gen, 'n/a')
    END                                     AS gender,
    ci.cst_marital_status                   AS marital_status,
    la.cntry                                AS country,
    ci.cst_create_date                      AS created_date
FROM silver.cust_info ci
LEFT JOIN silver.cust_az12 ca ON ci.cst_key = ca.cid
LEFT JOIN silver.loc_a101  la ON ci.cst_key = la.cid;


-- ============================================================
-- gold.dim_products — Product Dimension
-- ============================================================
-- Joins product master with category hierarchy.
-- Assigns surrogate key via ROW_NUMBER().

DROP VIEW IF EXISTS gold.dim_products;
CREATE VIEW gold.dim_products AS
SELECT
    ROW_NUMBER() OVER (ORDER BY pr.prd_id)  AS product_key,
    pr.prd_id                               AS product_id,
    pr.cat_id                               AS category_id,
    pr.prd_key                              AS product_number,
    pr.prd_nm                               AS product_name,
    pr.prd_line                             AS line,
    pr.prd_cost                             AS cost,
    px.cat                                  AS category,
    px.subcat                               AS subcategory,
    px.maintenance                          AS maintenance,
    pr.prd_start_dt                         AS start_date
FROM silver.prd_info pr
LEFT JOIN silver.px_cat_g1v2 px ON pr.cat_id = px.id;


-- ============================================================
-- gold.fact_sales — Sales Fact Table
-- ============================================================
-- Joins Silver sales transactions to dimension surrogate keys.
-- All measures (sales, quantity, price) are clean from Silver layer.

DROP VIEW IF EXISTS gold.fact_sales;
CREATE VIEW gold.fact_sales AS
SELECT
    sa.sls_ord_num  AS order_number,
    cu.customer_key AS customer_key,
    pr.product_key  AS product_key,
    sa.sls_order_dt AS order_date,
    sa.sls_ship_dt  AS shipping_date,
    sa.sls_due_dt   AS due_date,
    sa.sls_sales    AS sales,
    sa.sls_quantity AS quantity,
    sa.sls_price    AS price
FROM silver.sales_details sa
LEFT JOIN gold.dim_customers cu ON sa.sls_cust_id = cu.customer_id
LEFT JOIN gold.dim_products  pr ON sa.sls_prd_key = pr.product_number;


-- ============================================================
-- Validation Queries — Run after view creation
-- ============================================================

-- SELECT * FROM gold.dim_customers LIMIT 10;
-- SELECT * FROM gold.dim_products  LIMIT 10;
-- SELECT * FROM gold.fact_sales    LIMIT 10;