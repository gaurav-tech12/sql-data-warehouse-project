# SQL Data Warehouse Project

This project builds a SQL Server data warehouse from six CSV files from CRM and ERP source systems. It uses a three-layer design:

- **Bronze:** source-shaped tables loaded from CSV files.
- **Silver:** cleaned and standardized tables populated from Bronze.
- **Gold:** customer and product dimensions and a sales fact view for analysis.

The Gold objects are SQL views, not persisted tables. The sales fact view is based on sales detail rows joined to the customer and product dimensions.

## Architecture and data flow

```text
CRM and ERP CSV files
        |
        v
Bronze tables -- bronze.load_bronze
        |
        v
Silver tables -- silver.load_silver
        |
        v
Gold views: dim_customers, dim_products, fact_sales
        |
        v
Silver and Gold quality-check scripts
```

## Technologies and prerequisites

- Microsoft SQL Server (the scripts use T-SQL features such as `BULK INSERT`, `GO`, and `CREATE OR ALTER PROCEDURE`)
- SQL Server Management Studio (SSMS), or another SQL Server client that supports executing scripts with `GO` batch separators
- Permission to create/drop the `DataWarehouse` database and its objects
- Permission for the SQL Server service to read the CSV files from the configured local paths

The SQL Server service must be able to read the source files; access from your Windows account alone may not be sufficient for `BULK INSERT`.

## Project structure

```text
.
├── datasets/
│   ├── source_crm/
│   │   ├── cust_info.csv
│   │   ├── prd_info.csv
│   │   └── sales_details.csv
│   └── source_erp/
│       ├── CUST_AZ12.csv
│       ├── LOC_A101.csv
│       └── PX_CAT_G1V2.csv
├── docs/
│   ├── data_architecture.png
│   ├── data_flow.png
│   ├── data_integration.png
│   ├── data_model.png
│   ├── ETL.png
│   ├── data_catalog.md
│   ├── naming_conventions.md
│   ├── Project_Notes_Sketches.pdf
│   └── data_layers.pdf
├── scripts/
│   ├── init_database.sql
│   ├── bronze/
│   │   ├── ddl_bronze.sql
│   │   └── proc_load_bronze_fixed_path.sql
│   ├── silver/
│   │   ├── ddl_silver.sql
│   │   └── proc_load_silver.sql
│   └── gold/
│       ├── ddl_gold.sql
│       └── gold_business_analysis.sql
├── tests/
│   ├── quality_checks_silver.sql
│   └── quality_checks_gold.sql
├── .gitignore
├── FUNDING.yml
├── LICENSE
└── README.md
```

## Setup and execution

Run the scripts in SSMS while connected to the SQL Server instance where you want the warehouse. Open each `.sql` file and execute it with **Execute** (or press **F5**). Run the steps in order:

1. **Initialize the database and schemas** — execute `scripts/init_database.sql`.
2. **Create Bronze tables** — select `DataWarehouse` as the database in SSMS, then execute `scripts/bronze/ddl_bronze.sql`.
3. **Create Silver tables** — execute `scripts/silver/ddl_silver.sql`.
4. **Create the Bronze loading procedure** — execute `scripts/bronze/proc_load_bronze_fixed_path.sql`.
5. **Configure its CSV paths**, as described below, before running the procedure.
6. **Create the Silver loading procedure** — execute `scripts/silver/proc_load_silver.sql`.
7. **Load Bronze** — execute:

   ```sql
   USE DataWarehouse;
   EXEC bronze.load_bronze;
   ```

8. **Load Silver** — execute:

   ```sql
   USE DataWarehouse;
   EXEC silver.load_silver;
   ```

9. **Create the Gold views** — execute `scripts/gold/ddl_gold.sql`.
10. **Run the quality checks** — execute `tests/quality_checks_silver.sql`, then `tests/quality_checks_gold.sql`. Review the result sets and investigate any unexpected rows.
11. **Run the Gold business analysis** — execute `scripts/gold/gold_business_analysis.sql` after creating the Gold views. Review its monthly sales, product, customer, order-value, and product-line result sets.

Steps 2–4, 6, and 9 create database objects; step 5 configures the local file paths, and steps 7 and 8 run the data loads. Load Bronze before Silver. The Silver checks are intended to be run after loading Silver, and the Gold checks and business analysis after creating the Gold views.

### Important: scripts that can delete objects or data

**Do not run these scripts against a database whose contents you need to keep unless you have a backup and intend to replace those objects:**

- `scripts/init_database.sql` drops and recreates the entire `DataWarehouse` database if it already exists. All data in that database is deleted.
- `scripts/bronze/ddl_bronze.sql` drops and recreates the Bronze tables if they already exist.
- `scripts/silver/ddl_silver.sql` drops and recreates the Silver tables if they already exist.

The Bronze and Silver loading procedures also truncate their target tables before loading. Re-running a load replaces the existing contents of those target tables.

## Configure CSV file paths

The Bronze procedure in `scripts/bronze/proc_load_bronze_fixed_path.sql` contains six absolute file paths in its `BULK INSERT` statements. They currently point into this project's `datasets` folders on the author's local `D:` drive. **These paths will not automatically work on another computer.**

Before running `EXEC bronze.load_bronze`:

1. Find the actual location of the cloned project on your computer.
2. In `proc_load_bronze_fixed_path.sql`, update each `FROM '...'` path to the matching CSV file in your local `datasets\source_crm` or `datasets\source_erp` folder.
3. Keep the paths in SQL Server's expected format, for example:

   ```sql
   FROM 'C:\Users\YourName\Projects\sql-data-warehouse-project\datasets\source_crm\cust_info.csv'
   ```

4. Save and execute the edited procedure script again so SQL Server stores the updated definition.
5. Confirm that the SQL Server service account can read those files, then run the Bronze load.

There are three CRM files (`cust_info.csv`, `prd_info.csv`, `sales_details.csv`) and three ERP files (`CUST_AZ12.csv`, `LOC_A101.csv`, `PX_CAT_G1V2.csv`). Keep each path paired with its matching table and file. Windows paths are case-insensitive by default, but use the names shown in the repository when locating the files.

## Quality checks

The `tests` folder contains manual SQL diagnostic queries, not an automated test runner:

- `quality_checks_silver.sql` checks selected Silver-layer keys, text formatting, standardization, dates, and sales-field consistency.
- `quality_checks_gold.sql` checks dimension surrogate-key uniqueness and whether fact rows have matching dimension keys.

Run them after their respective layers are loaded/created. Some queries are designed to return problematic rows; review the comments in each script for the expected result. A query returning no rows is only meaningful for the specific check it performs and does not certify the entire warehouse.

## Exploring the Gold views

After the pipeline and Gold view script have run, try these example queries in SSMS:

```sql
USE DataWarehouse;

SELECT TOP (10) * FROM gold.dim_customers;
SELECT TOP (10) * FROM gold.dim_products;
SELECT TOP (10) * FROM gold.fact_sales;
```

For field descriptions, see [`docs/data_catalog.md`](docs/data_catalog.md). Naming guidance is in [`docs/naming_conventions.md`](docs/naming_conventions.md).

## Git ignore note

The current `.gitignore` contains global `*.csv`, `*.png`, and `*.pdf` rules. As a result, all six CSV source files, all five PNG diagrams, and both PDF documents listed above are ignored by Git unless already tracked or explicitly force-added. The ignore rules are not changed by this README update.

## License

See [LICENSE](LICENSE).
