/*
===============================================================================
Silver Layer Quality Checks
===============================================================================
Run after silver.load_silver. These are read-only diagnostic queries. Returned
rows are items to investigate, not automatic failures: some findings can be
valid for the source data or this project's transformation rules.
===============================================================================
*/

-- ====================================================================
-- CRM customers
-- ====================================================================
-- NULL or duplicate customer identifiers can prevent reliable joins.
SELECT
    cst_id,
    COUNT(*) AS row_count
FROM silver.crm_cust_info
GROUP BY cst_id
HAVING cst_id IS NULL OR COUNT(*) > 1;

-- cst_key is used to join customer attributes from the ERP sources.
SELECT
    cst_key,
    COUNT(*) AS row_count
FROM silver.crm_cust_info
GROUP BY cst_key
HAVING cst_key IS NULL OR COUNT(*) > 1;

-- Missing names/attributes and values outside the standardization performed
-- by silver.load_silver. Review n/a and NULL values as possible source gaps.
SELECT *
FROM silver.crm_cust_info
WHERE cst_firstname IS NULL OR TRIM(cst_firstname) = ''
   OR cst_lastname IS NULL OR TRIM(cst_lastname) = ''
   OR cst_create_date IS NULL
   OR cst_marital_status IS NULL
   OR cst_marital_status NOT IN ('Single', 'Married', 'n/a')
   OR cst_gndr IS NULL
   OR cst_gndr NOT IN ('Female', 'Male', 'n/a');

-- Check for key values with leading/trailing spaces that could interfere with joins.
SELECT cst_key
FROM silver.crm_cust_info
WHERE cst_key IS NOT NULL AND cst_key <> TRIM(cst_key);

-- Show observed standardized marital-status and gender values for review.
SELECT DISTINCT cst_marital_status, cst_gndr
FROM silver.crm_cust_info
ORDER BY cst_marital_status, cst_gndr;

-- ====================================================================
-- CRM products
-- ====================================================================
-- Product IDs should identify a source product row. Duplicate IDs need review.
SELECT
    prd_id,
    COUNT(*) AS row_count
FROM silver.crm_prd_info
GROUP BY prd_id
HAVING prd_id IS NULL OR COUNT(*) > 1;

-- Multiple historical rows for prd_key can be intentional. Check only the
-- current rows used by gold.dim_products for duplicate join keys.
SELECT
    prd_key,
    COUNT(*) AS current_row_count
FROM silver.crm_prd_info
WHERE prd_end_dt IS NULL
GROUP BY prd_key
HAVING prd_key IS NULL OR COUNT(*) > 1;

-- Missing required join/descriptive fields and unexpected standardized
-- product-line values. A zero cost is allowed by the current Silver loader,
-- which replaces NULL cost with zero; review it separately if appropriate.
SELECT *
FROM silver.crm_prd_info
WHERE cat_id IS NULL OR TRIM(cat_id) = ''
   OR prd_key IS NULL OR TRIM(prd_key) = ''
   OR prd_nm IS NULL OR TRIM(prd_nm) = ''
   OR prd_cost IS NULL OR prd_cost < 0
   OR prd_line IS NULL
   OR prd_line NOT IN ('Mountain', 'Road', 'Other Sales', 'Touring', 'n/a')
   OR prd_start_dt IS NULL;

-- Negative costs are suspicious; zero may have resulted from source NULLs.
SELECT prd_id, prd_key, prd_nm, prd_cost
FROM silver.crm_prd_info
WHERE prd_cost < 0;

-- Detect whitespace in product names and invalid product date ranges.
SELECT prd_id, prd_nm
FROM silver.crm_prd_info
WHERE prd_nm IS NOT NULL AND prd_nm <> TRIM(prd_nm);

SELECT prd_id, prd_key, prd_start_dt, prd_end_dt
FROM silver.crm_prd_info
WHERE prd_end_dt < prd_start_dt;

-- ====================================================================
-- CRM sales
-- ====================================================================
-- Business keys used to link fact rows to dimensions must be present.
SELECT *
FROM silver.crm_sales_details
WHERE sls_ord_num IS NULL OR TRIM(sls_ord_num) = ''
   OR sls_prd_key IS NULL OR TRIM(sls_prd_key) = ''
   OR sls_cust_id IS NULL;

-- Check all source date integers for invalid YYYYMMDD values before
-- transformation. NULL/zero dates are reviewed in the Silver checks below.
SELECT
    sls_ord_num,
    sls_order_dt,
    sls_ship_dt,
    sls_due_dt
FROM bronze.crm_sales_details
WHERE (sls_order_dt IS NOT NULL AND sls_order_dt <> 0
       AND (LEN(CONVERT(varchar(20), sls_order_dt)) <> 8
            OR TRY_CONVERT(date, CONVERT(varchar(20), sls_order_dt), 112) IS NULL))
   OR (sls_ship_dt IS NOT NULL AND sls_ship_dt <> 0
       AND (LEN(CONVERT(varchar(20), sls_ship_dt)) <> 8
            OR TRY_CONVERT(date, CONVERT(varchar(20), sls_ship_dt), 112) IS NULL))
   OR (sls_due_dt IS NOT NULL AND sls_due_dt <> 0
       AND (LEN(CONVERT(varchar(20), sls_due_dt)) <> 8
            OR TRY_CONVERT(date, CONVERT(varchar(20), sls_due_dt), 112) IS NULL));

-- Show rows with missing dates after transformation. Missing values may be
-- intentional source data or invalid source dates converted by the loader.
SELECT sls_ord_num, sls_order_dt, sls_ship_dt, sls_due_dt
FROM silver.crm_sales_details
WHERE sls_order_dt IS NULL OR sls_ship_dt IS NULL OR sls_due_dt IS NULL;

-- Dates should be chronologically consistent when present. Investigate rows
-- where shipping precedes the order, due precedes the order, or shipping is
-- later than the due date.
SELECT sls_ord_num, sls_order_dt, sls_ship_dt, sls_due_dt
FROM silver.crm_sales_details
WHERE (sls_order_dt IS NOT NULL AND sls_ship_dt IS NOT NULL
       AND sls_order_dt > sls_ship_dt)
   OR (sls_order_dt IS NOT NULL AND sls_due_dt IS NOT NULL
       AND sls_order_dt > sls_due_dt)
   OR (sls_ship_dt IS NOT NULL AND sls_due_dt IS NOT NULL
       AND sls_ship_dt > sls_due_dt);

-- Non-positive or missing measures are suspicious for sales detail, but
-- review against source meaning before treating any row as invalid.
SELECT
    sls_ord_num,
    sls_prd_key,
    sls_cust_id,
    sls_sales,
    sls_quantity,
    sls_price
FROM silver.crm_sales_details
WHERE sls_sales IS NULL OR sls_sales <= 0
   OR sls_quantity IS NULL OR sls_quantity <= 0
   OR sls_price IS NULL OR sls_price <= 0;

-- Compare sales with quantity times price. Integer source fields and the
-- loader's repair logic may produce rounding or other differences; investigate
-- mismatches rather than assuming this is an unconditional business rule.
SELECT
    sls_ord_num,
    sls_sales,
    sls_quantity,
    sls_price,
    CAST(sls_quantity AS decimal(19, 0))
        * CAST(sls_price AS decimal(19, 0)) AS calculated_sales
FROM silver.crm_sales_details
WHERE sls_sales IS NOT NULL
  AND sls_quantity IS NOT NULL
  AND sls_price IS NOT NULL
  AND CAST(sls_sales AS decimal(19, 0))
      <> CAST(sls_quantity AS decimal(19, 0))
         * CAST(sls_price AS decimal(19, 0));

-- Exact duplicate sales rows may be duplicate source records, but identical
-- values can also represent legitimate repeated lines; inspect with context.
SELECT
    sls_ord_num,
    sls_prd_key,
    sls_cust_id,
    sls_order_dt,
    sls_ship_dt,
    sls_due_dt,
    sls_sales,
    sls_quantity,
    sls_price,
    COUNT(*) AS duplicate_count
FROM silver.crm_sales_details
GROUP BY
    sls_ord_num,
    sls_prd_key,
    sls_cust_id,
    sls_order_dt,
    sls_ship_dt,
    sls_due_dt,
    sls_sales,
    sls_quantity,
    sls_price
HAVING COUNT(*) > 1;

-- ====================================================================
-- ERP customer and location keys
-- ====================================================================
-- ERP customer identifiers are join keys after prefix cleanup. NULLs or
-- duplicate identifiers can make customer enrichment incomplete or multiply rows.
SELECT cid, COUNT(*) AS row_count
FROM silver.erp_cust_az12
GROUP BY cid
HAVING cid IS NULL OR COUNT(*) > 1;

SELECT cid, COUNT(*) AS row_count
FROM silver.erp_loc_a101
GROUP BY cid
HAVING cid IS NULL OR COUNT(*) > 1;

-- Check missing/unknown ERP customer attributes and show the age/date outliers.
SELECT *
FROM silver.erp_cust_az12
WHERE gen IS NULL
   OR gen NOT IN ('Female', 'Male', 'n/a');

SELECT cid, bdate
FROM silver.erp_cust_az12
WHERE bdate < '1924-01-01' OR bdate > CONVERT(date, GETDATE());

-- Country values are not restricted to a fixed list because the source may
-- contain additional countries. This result lists distinct observed values.
SELECT DISTINCT cntry
FROM silver.erp_loc_a101
ORDER BY cntry;

-- ====================================================================
-- ERP product categories
-- ====================================================================
-- Category IDs are joined to CRM product cat_id; NULL/duplicate keys may
-- cause missing category details or row multiplication in the Gold view.
SELECT id, COUNT(*) AS row_count
FROM silver.erp_px_cat_g1v2
GROUP BY id
HAVING id IS NULL OR COUNT(*) > 1;

-- Show category rows with missing descriptive attributes for investigation.
SELECT *
FROM silver.erp_px_cat_g1v2
WHERE cat IS NULL OR TRIM(cat) = ''
   OR subcat IS NULL OR TRIM(subcat) = ''
   OR maintenance IS NULL OR TRIM(maintenance) = '';

-- Detect unwanted spaces and display observed maintenance values. Do not
-- assume an allowed-value list beyond what the source data establishes.
SELECT *
FROM silver.erp_px_cat_g1v2
WHERE (cat IS NOT NULL AND cat <> TRIM(cat))
   OR (subcat IS NOT NULL AND subcat <> TRIM(subcat))
   OR (maintenance IS NOT NULL AND maintenance <> TRIM(maintenance));

SELECT DISTINCT maintenance
FROM silver.erp_px_cat_g1v2
ORDER BY maintenance;
