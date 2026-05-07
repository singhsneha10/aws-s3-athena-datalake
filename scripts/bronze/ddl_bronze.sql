/*
===============================================================================
DDL Script: Bronze Layer — External Tables over S3
===============================================================================
Purpose:
    Creates external tables in the 'datawarehouse' schema pointing directly
    to raw CSV files stored in S3. No transformations — exact copy of source.

S3 Structure:
    s3://sneha-datawarehouse-project/bronze/
        ├── crm/
        │   ├── cust_info/
        │   ├── prd_info/
        │   └── sales_details/
        └── erp/
            ├── cust_az12/
            ├── loc_a101/
            └── category_info/

Run Order:
    1. Create schema first
    2. Run this script to register all bronze tables
===============================================================================
*/

-- ============================================================
-- Step 1: Create Schema
-- ============================================================
CREATE SCHEMA datawarehouse;


-- ============================================================
-- CRM Source Tables
-- ============================================================

-- Customer Info
DROP TABLE IF EXISTS datawarehouse.cust_info;
CREATE EXTERNAL TABLE datawarehouse.cust_info (
    cst_id              INT,
    cst_key             STRING,
    cst_firstname       STRING,
    cst_lastname        STRING,
    cst_marital_status  STRING,
    cst_gndr            STRING,
    cst_create_date     STRING
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
    "separatorChar" = ",",
    "quoteChar"     = "\"",
    "escapeChar"    = "\\"
)
LOCATION 's3://sneha-datawarehouse-project/bronze/crm/cust_info/'
TBLPROPERTIES (
    "skip.header.line.count" = "1",
    "use.null.for.invalid.data" = "true"
);


-- Product Info
DROP TABLE IF EXISTS datawarehouse.prd_info;
CREATE EXTERNAL TABLE datawarehouse.prd_info (
    prd_id       INT,
    prd_key      STRING,
    prd_nm       STRING,
    prd_cost     INT,
    prd_line     STRING,
    prd_start_dt STRING
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
    "separatorChar" = ",",
    "quoteChar"     = "\"",
    "escapeChar"    = "\\"
)
LOCATION 's3://sneha-datawarehouse-project/bronze/crm/prd_info/'
TBLPROPERTIES (
    "skip.header.line.count" = "1",
    "use.null.for.invalid.data" = "true"
);


-- Sales Details
DROP TABLE IF EXISTS datawarehouse.sales_details;
CREATE EXTERNAL TABLE datawarehouse.sales_details (
    sls_ord_num  STRING,
    sls_prd_key  STRING,
    sls_cust_id  STRING,
    sls_order_dt INT,
    sls_ship_dt  INT,
    sls_due_dt   INT,
    sls_sales    INT,
    sls_quantity INT,
    sls_price    INT
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
    "separatorChar" = ",",
    "quoteChar"     = "\"",
    "escapeChar"    = "\\"
)
LOCATION 's3://sneha-datawarehouse-project/bronze/crm/sales_details/'
TBLPROPERTIES (
    "skip.header.line.count" = "1",
    "use.null.for.invalid.data" = "true"
);


-- ============================================================
-- ERP Source Tables
-- ============================================================

-- Customer Demographics (birthdate, gender)
DROP TABLE IF EXISTS datawarehouse.cust_az12;
CREATE EXTERNAL TABLE datawarehouse.cust_az12 (
    cid    STRING,
    bdate  STRING,
    gen    STRING
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
    "separatorChar" = ",",
    "quoteChar"     = "\"",
    "escapeChar"    = "\\"
)
LOCATION 's3://sneha-datawarehouse-project/bronze/erp/cust_az12/'
TBLPROPERTIES (
    "skip.header.line.count" = "1",
    "use.null.for.invalid.data" = "true"
);


-- Customer Location / Country
DROP TABLE IF EXISTS datawarehouse.loc_a101;
CREATE EXTERNAL TABLE datawarehouse.loc_a101 (
    cid    STRING,
    cntry  STRING
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
    "separatorChar" = ",",
    "quoteChar"     = "\"",
    "escapeChar"    = "\\"
)
LOCATION 's3://sneha-datawarehouse-project/bronze/erp/loc_a101/'
TBLPROPERTIES (
    "skip.header.line.count" = "1",
    "use.null.for.invalid.data" = "true"
);


-- Product Category Hierarchy
DROP TABLE IF EXISTS datawarehouse.px_cat_g1v2;
CREATE EXTERNAL TABLE datawarehouse.px_cat_g1v2 (
    id          STRING,
    cat         STRING,
    subcat      STRING,
    maintenance STRING
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
    "separatorChar" = ",",
    "quoteChar"     = "\"",
    "escapeChar"    = "\\"
)
LOCATION 's3://sneha-datawarehouse-project/bronze/erp/category_info/'
TBLPROPERTIES (
    "skip.header.line.count" = "1",
    "use.null.for.invalid.data" = "true"
);
