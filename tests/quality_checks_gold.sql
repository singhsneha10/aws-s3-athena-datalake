/*
===============================================================================
Quality Checks: Gold Layer
===============================================================================
Purpose:
    Validates the integrity and connectivity of the Gold Star Schema.
    Checks for: surrogate key uniqueness, referential integrity between
    fact and dimension tables, and NULL dimension keys in fact.

Usage:
    Run after scripts/gold/ddl_gold.sql completes.
    All queries should return 0 rows. Any result = data issue to investigate.
===============================================================================
*/


-- ============================================================
-- gold.dim_customers
-- ============================================================

-- Duplicate surrogate keys → expect 0 rows
SELECT customer_key, COUNT(*) AS duplicate_count
FROM gold.dim_customers
GROUP BY customer_key
HAVING COUNT(*) > 1;

-- Row count sanity check
SELECT COUNT(*) AS total_customers FROM gold.dim_customers;


-- ============================================================
-- gold.dim_products
-- ============================================================

-- Duplicate surrogate keys → expect 0 rows
SELECT product_key, COUNT(*) AS duplicate_count
FROM gold.dim_products
GROUP BY product_key
HAVING COUNT(*) > 1;

-- Row count sanity check
SELECT COUNT(*) AS total_products FROM gold.dim_products;


-- ============================================================
-- gold.fact_sales — Referential Integrity
-- ============================================================

-- Orphaned fact rows (no matching customer or product) → expect 0 rows
SELECT *
FROM gold.fact_sales f
LEFT JOIN gold.dim_customers c ON c.customer_key = f.customer_key
LEFT JOIN gold.dim_products  p ON p.product_key  = f.product_key
WHERE p.product_key IS NULL
   OR c.customer_key IS NULL;

-- NULL measures in fact → expect 0 rows
SELECT *
FROM gold.fact_sales
WHERE sales IS NULL
   OR quantity IS NULL
   OR price IS NULL;

-- Row count and total revenue sanity check
SELECT
    COUNT(*)       AS total_orders,
    SUM(sales)     AS total_revenue,
    SUM(quantity)  AS total_units
FROM gold.fact_sales;
