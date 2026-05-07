# Data Catalogue — Gold Layer

Column-level data dictionary for all Gold layer views.

---

## gold.dim_customers

| Column | Type | Source | Description |
|--------|------|--------|-------------|
| customer_key | INT | Generated | Surrogate key via ROW_NUMBER() |
| customer_id | INT | silver.cust_info.cst_id | Natural customer ID from CRM |
| customer_number | STRING | silver.cust_info.cst_key | Business customer code |
| first_name | STRING | silver.cust_info.cst_firstname | Trimmed first name |
| last_name | STRING | silver.cust_info.cst_lastname | Trimmed last name |
| birthdate | DATE | silver.cust_az12.bdate | From ERP; NULL if future date |
| gender | STRING | CRM primary / ERP fallback | Male / Female / n/a |
| marital_status | STRING | silver.cust_info.cst_marital_status | Single / Married / n/a |
| country | STRING | silver.loc_a101.cntry | Standardised country name |
| created_date | STRING | silver.cust_info.cst_create_date | CRM account creation date |

---

## gold.dim_products

| Column | Type | Source | Description |
|--------|------|--------|-------------|
| product_key | INT | Generated | Surrogate key via ROW_NUMBER() |
| product_id | INT | silver.prd_info.prd_id | Natural product ID from CRM |
| category_id | STRING | silver.prd_info.cat_id | Extracted from product key prefix |
| product_number | STRING | silver.prd_info.prd_key | Business product code |
| product_name | STRING | silver.prd_info.prd_nm | Product display name |
| line | STRING | silver.prd_info.prd_line | Mountain / Road / Touring / Other Sales / n/a |
| cost | INT | silver.prd_info.prd_cost | Unit cost; 0 if NULL in source |
| category | STRING | silver.px_cat_g1v2.cat | Top-level category from ERP |
| subcategory | STRING | silver.px_cat_g1v2.subcat | Subcategory from ERP |
| maintenance | STRING | silver.px_cat_g1v2.maintenance | Maintenance flag from ERP |
| start_date | DATE | silver.prd_info.prd_start_dt | Product version effective date |

---

## gold.fact_sales

| Column | Type | Source | Description |
|--------|------|--------|-------------|
| order_number | STRING | silver.sales_details.sls_ord_num | Business order identifier |
| customer_key | INT | gold.dim_customers | FK to dim_customers surrogate key |
| product_key | INT | gold.dim_products | FK to dim_products surrogate key |
| order_date | DATE | silver.sales_details.sls_order_dt | Parsed from YYYYMMDD integer |
| shipping_date | DATE | silver.sales_details.sls_ship_dt | Parsed from YYYYMMDD integer |
| due_date | DATE | silver.sales_details.sls_due_dt | Parsed from YYYYMMDD integer |
| sales | INT | silver.sales_details.sls_sales | Validated: quantity × price |
| quantity | INT | silver.sales_details.sls_quantity | Units ordered |
| price | INT | silver.sales_details.sls_price | Unit price; recalculated if invalid |
