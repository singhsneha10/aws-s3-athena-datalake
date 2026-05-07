/*
===============================================================================
Quality Checks: Silver Layer
===============================================================================
Purpose:
    Validates data integrity across all Silver tables after each load.
    Checks for: duplicate keys, whitespace issues, invalid dates,
    out-of-range values, and data standardisation consistency.

Usage:
    Run after scripts/silver/ddl_silver.sql completes.
    All queries should return 0 rows. Any result = data issue to investigate.
===============================================================================
*/


-- ============================================================
-- silver.cust_info
-- ============================================================

-- Duplicate or NULL primary keys → expect 0 rows
SELECT cst_id, COUNT(*)
FROM silver.cust_info
GROUP BY cst_id
HAVING COUNT(*) > 1;

-- Untrimmed first/last name → expect 0 rows
SELECT cst_firstname
FROM silver.cust_info
WHERE cst_firstname != TRIM(cst_firstname);

SELECT cst_lastname
FROM silver.cust_info
WHERE cst_lastname != TRIM(cst_lastname);

-- Marital status standardisation check → expect only: Single, Married, n/a
SELECT DISTINCT cst_marital_status
FROM silver.cust_info;

-- Gender standardisation check → expect only: Male, Female, n/a
SELECT DISTINCT cst_gndr
FROM silver.cust_info;

-- Future create dates → expect 0 rows
SELECT cst_create_date
FROM silver.cust_info
WHERE cst_create_date > CURRENT_DATE;


-- ============================================================
-- silver.prd_info
-- ============================================================

-- Duplicate product IDs → expect 0 rows
SELECT prd_id, COUNT(*)
FROM silver.prd_info
GROUP BY prd_id
HAVING COUNT(*) > 1;

-- Untrimmed product names → expect 0 rows
SELECT prd_nm
FROM silver.prd_info
WHERE prd_nm != TRIM(prd_nm);

-- NULL or negative cost → expect 0 rows
SELECT prd_cost
FROM silver.prd_info
WHERE prd_cost IS NULL OR prd_cost < 0;

-- Product line standardisation → expect only: Mountain, Road, Other Sales, Touring, n/a
SELECT DISTINCT prd_line
FROM silver.prd_info;


-- ============================================================
-- silver.sales_details
-- ============================================================

-- Duplicate order numbers → expect 0 rows
SELECT sls_ord_num, COUNT(*)
FROM silver.sales_details
GROUP BY sls_ord_num
HAVING COUNT(*) > 1;

-- Composite key duplicates (order + product + customer) → expect 0 rows
SELECT sls_ord_num, sls_prd_key, sls_cust_id, COUNT(*)
FROM silver.sales_details
GROUP BY sls_ord_num, sls_prd_key, sls_cust_id
HAVING COUNT(*) > 1;

-- NULL order dates (invalid source integers) → review volume
SELECT sls_order_dt
FROM silver.sales_details
WHERE sls_order_dt IS NULL;

-- Sales amount consistency: sales = quantity × price → expect 0 rows
SELECT sls_sales, sls_quantity, sls_price
FROM silver.sales_details
WHERE sls_sales != sls_quantity * sls_price
   OR sls_sales IS NULL
   OR sls_quantity IS NULL
   OR sls_price IS NULL;

-- Negative or NULL quantity → expect 0 rows
SELECT sls_quantity
FROM silver.sales_details
WHERE sls_quantity < 0 OR sls_quantity IS NULL;

-- Negative or NULL price → expect 0 rows
SELECT sls_price
FROM silver.sales_details
WHERE sls_price < 0 OR sls_price IS NULL;


-- ============================================================
-- silver.cust_az12 (ERP demographics)
-- ============================================================

-- Duplicate customer IDs → expect 0 rows
SELECT cid, COUNT(*)
FROM silver.cust_az12
GROUP BY cid
HAVING COUNT(*) > 1;

-- Future birthdates → expect 0 rows
SELECT bdate
FROM silver.cust_az12
WHERE CAST(bdate AS DATE) > CURRENT_DATE;

-- Gender standardisation → expect only: Male, Female, n/a
SELECT DISTINCT gen
FROM silver.cust_az12;


-- ============================================================
-- silver.loc_a101 (ERP location)
-- ============================================================

-- Duplicate customer IDs → expect 0 rows
SELECT cid, COUNT(*)
FROM silver.loc_a101
GROUP BY cid
HAVING COUNT(*) > 1;

-- Country standardisation → review for any unmapped values
SELECT DISTINCT cntry
FROM silver.loc_a101
ORDER BY cntry;


-- ============================================================
-- silver.px_cat_g1v2 (ERP product categories)
-- ============================================================

-- Duplicate category IDs → expect 0 rows
SELECT id, COUNT(*)
FROM silver.px_cat_g1v2
GROUP BY id
HAVING COUNT(*) > 1;

-- Subcategory and maintenance standardisation → review values
SELECT DISTINCT subcat       FROM silver.px_cat_g1v2;
SELECT DISTINCT maintenance  FROM silver.px_cat_g1v2;


-- ============================================================
-- Cross-Table Join Validation
-- ============================================================
-- Verifies that Silver table keys align correctly before Gold views are built.
-- These are the same joins used in dim_customers and dim_products.

-- cust_info ↔ cust_az12 join health: how many customers have ERP demographic data?
-- Expect: most customers matched; investigate large unmatched counts
SELECT
    COUNT(*)                                                    AS total_crm_customers,
    COUNT(ca.cid)                                               AS matched_with_erp_demographics,
    COUNT(*) - COUNT(ca.cid)                                    AS unmatched
FROM silver.cust_info ci
LEFT JOIN silver.cust_az12 ca
    ON TRIM(ci.cst_key) = TRIM(ca.cid);

-- cust_info ↔ loc_a101 join health: how many customers have location data?
SELECT
    COUNT(*)                                                    AS total_crm_customers,
    COUNT(la.cid)                                               AS matched_with_location,
    COUNT(*) - COUNT(la.cid)                                    AS unmatched
FROM silver.cust_info ci
LEFT JOIN silver.loc_a101 la
    ON TRIM(ci.cst_key) = TRIM(la.cid);

-- prd_info ↔ px_cat_g1v2 join health: how many products have category data?
SELECT
    COUNT(*)                                                    AS total_products,
    COUNT(px.id)                                                AS matched_with_category,
    COUNT(*) - COUNT(px.id)                                     AS unmatched
FROM silver.prd_info pr
LEFT JOIN silver.px_cat_g1v2 px
    ON pr.cat_id = px.id;

-- Sample join output for manual inspection (first 20 rows)
-- Use this to visually verify join correctness before building Gold layer
SELECT
    ci.cst_key,
    ca.cid,
    ca.bdate,
    ca.gen,
    la.cntry
FROM silver.cust_info ci
LEFT JOIN silver.cust_az12 ca ON TRIM(ci.cst_key) = TRIM(ca.cid)
LEFT JOIN silver.loc_a101  la ON TRIM(ci.cst_key) = TRIM(la.cid)
WHERE ca.bdate IS NOT NULL
LIMIT 20;
