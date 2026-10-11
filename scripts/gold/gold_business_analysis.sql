/*
===============================================================================
Gold Layer Business Analysis
===============================================================================
Purpose:
    Read-only portfolio queries using the existing Gold views:
    gold.fact_sales, gold.dim_products, and gold.dim_customers.

Run after creating the Gold views. Sales and quantity are reported from the
sales-detail grain of gold.fact_sales.
===============================================================================
*/

USE DataWarehouse;
GO

-- Business question: How do sales, units sold, and order counts trend by month?
-- Rows with a NULL order_date are excluded because they cannot be assigned
-- reliably to a calendar month.
SELECT
    DATEFROMPARTS(YEAR(order_date), MONTH(order_date), 1) AS sales_month,
    SUM(CONVERT(decimal(19, 2), sales_amount)) AS total_sales,
    SUM(CONVERT(bigint, quantity)) AS units_sold,
    COUNT(DISTINCT order_number) AS order_count
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY DATEFROMPARTS(YEAR(order_date), MONTH(order_date), 1)
ORDER BY sales_month;
GO

-- Business question: Which product categories contribute the most sales?
-- Unmatched or unclassified products are retained in a clearly labeled bucket.
SELECT
    COALESCE(NULLIF(TRIM(p.category), ''), 'Unmapped / not classified') AS category,
    SUM(CONVERT(decimal(19, 2), fs.sales_amount)) AS total_sales,
    SUM(CONVERT(bigint, fs.quantity)) AS units_sold,
    COUNT(DISTINCT fs.order_number) AS order_count
FROM gold.fact_sales AS fs
LEFT JOIN gold.dim_products AS p
    ON fs.product_key = p.product_key
GROUP BY COALESCE(NULLIF(TRIM(p.category), ''), 'Unmapped / not classified')
ORDER BY total_sales DESC, category;
GO

-- Business question: Which 10 mapped products have the highest sales?
-- Unmatched fact rows are excluded because they have no verified product
-- attributes in gold.dim_products.
SELECT TOP (10)
    p.product_number,
    p.product_name,
    p.category,
    p.subcategory,
    SUM(CONVERT(decimal(19, 2), fs.sales_amount)) AS total_sales,
    SUM(CONVERT(bigint, fs.quantity)) AS units_sold,
    COUNT(DISTINCT fs.order_number) AS order_count
FROM gold.fact_sales AS fs
INNER JOIN gold.dim_products AS p
    ON fs.product_key = p.product_key
GROUP BY
    p.product_number,
    p.product_name,
    p.category,
    p.subcategory
ORDER BY total_sales DESC, p.product_number;
GO

-- Business question: How are sales distributed across customers and countries?
-- The LEFT JOIN retains unmatched sales; their customer attributes remain NULL
-- rather than being assigned invented customer or country values.
SELECT
    c.customer_id,
    c.customer_number,
    c.first_name,
    c.last_name,
    c.country,
    SUM(CONVERT(decimal(19, 2), fs.sales_amount)) AS total_sales,
    SUM(CONVERT(bigint, fs.quantity)) AS units_sold,
    COUNT(DISTINCT fs.order_number) AS order_count
FROM gold.fact_sales AS fs
LEFT JOIN gold.dim_customers AS c
    ON fs.customer_key = c.customer_key
GROUP BY
    c.customer_id,
    c.customer_number,
    c.first_name,
    c.last_name,
    c.country
ORDER BY total_sales DESC, c.country, c.customer_id;
GO

-- Business question: What is the average total sales value per order?
-- Aggregate detail rows first so multi-line orders contribute one order total
-- to the average. Exclude orders with missing line sales or order numbers so
-- incomplete totals do not understate the average order value.
WITH order_totals AS (
    SELECT
        order_number,
        SUM(CONVERT(decimal(19, 2), sales_amount)) AS order_sales
    FROM gold.fact_sales
    WHERE order_number IS NOT NULL
    GROUP BY order_number
    HAVING COUNT_BIG(*) = COUNT(sales_amount)
)
SELECT
    COUNT_BIG(*) AS order_count,
    AVG(order_sales) AS average_order_value
FROM order_totals;
GO

-- Business question: How do total sales and units sold compare by product line?
-- Unmatched or unclassified products are retained in a clearly labeled bucket.
SELECT
    COALESCE(NULLIF(TRIM(p.product_line), ''), 'Unmapped / not classified') AS product_line,
    SUM(CONVERT(decimal(19, 2), fs.sales_amount)) AS total_sales,
    SUM(CONVERT(bigint, fs.quantity)) AS units_sold,
    COUNT(DISTINCT fs.order_number) AS order_count
FROM gold.fact_sales AS fs
LEFT JOIN gold.dim_products AS p
    ON fs.product_key = p.product_key
GROUP BY COALESCE(NULLIF(TRIM(p.product_line), ''), 'Unmapped / not classified')
ORDER BY total_sales DESC, product_line;
GO
