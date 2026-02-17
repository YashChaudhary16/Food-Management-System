================================================================================
                    FOOD MANAGEMENT SYSTEM - README
================================================================================

TEAM MEMBERS:
-------------
Shail Patel (sapate23@ncsu.edu)
Yash Chaudhary (ychaudh@ncsu.edu)
Harsh Chaudhari (hchaudh3@ncsu.edu)
Aryan Shah (aashah9@ncsu.edu)

For any questions or issues, please contact us at our NCSU email addresses.

================================================================================
                        PROJECT SETUP INSTRUCTIONS
================================================================================

1. DATABASE SETUP (MySQL Workbench)
------------------------------------
   a. Open MySQL Workbench and connect to your MySQL server
   
   b. Create a new schema named "final":
      - In MySQL Workbench, click on "Create a new schema" icon
      - Name the schema: "final"
      - Click "Apply"
   
   c. Execute the SQL files in the following order:
      
      STEP 1: Execute "setup.sql"
             - This file contains:
               * Table definitions (DDL)
               * Constraints (Primary Keys, Foreign Keys, Check constraints)
               * Stored Procedures
               * Triggers
               * Views
      
      STEP 2: Execute "data_insert.sql"
             - This file contains SQL INSERT statements to populate the database
               with sample data for testing
             - This includes sample categories, ingredients, suppliers, 
               manufacturers, products, recipes, batches, and conflict pairs

2. PYTHON ENVIRONMENT SETUP
----------------------------
   a. Install the required Python package:
      
      pip install mysql-connector-python
   
   b. Verify Python installation (Python 3.x recommended)

3. CONFIGURE DATABASE CONNECTION
--------------------------------
   a. Open "food.py" in a text editor
   
   b. Locate the DB_CONFIG section (lines 4-11):
      
      DB_CONFIG = {
          'user': 'root',
          'password': 'root',
          'host': '127.0.0.1',
          'database': 'final',
          'use_pure': True
      }
   
   c. Update the following values according to your MySQL setup:
      - 'user': Change to your MySQL username (default is 'root')
      - 'password': Change to your MySQL password
      - 'host': Keep as '127.0.0.1' for localhost (or change if using remote server)
      - 'database': Keep as 'final' (must match the schema name created in step 1b)
      - 'use_pure': Keep as True

4. RUNNING THE APPLICATION
---------------------------
   a. Open a terminal/command prompt
   
   b. Navigate to the project directory
   
   c. Run the Python CLI:
      
      python food.py
   
   d. The application will display a menu with three roles:
      - Manufacturer (ID: 1 or 2)
      - Supplier (ID: 20 or 21)
      - General (Viewer)
   
   e. Follow the on-screen prompts to navigate through the system

================================================================================
                        FILE STRUCTURE
================================================================================

The project contains the following files:

1. setup.sql
   - Contains all database schema definitions
   - Includes: Tables, Constraints, Stored Procedures, Triggers, Views
   - Execute this FIRST before running any other SQL scripts

2. data_insert.sql
   - Contains INSERT statements for sample data
   - Populates tables with test data for demonstration
   - Execute this AFTER finalized_sql_file_one.sql

3. food.py
   - Main Python CLI application
   - Implements menu-driven interface for all three user roles
   - Connects to MySQL database and executes stored procedures/queries

4. README.txt
   - This file - contains setup and execution instructions

5. report.docx
   - This file - our project report

6. updated_er.png - contains latest ER Model

7. old_er.jpg - contains previous ER Model

================================================================================
                        SYSTEM REQUIREMENTS
================================================================================

- MySQL Server (MariaDB/MySQL 5.7 or higher)
- MySQL Workbench (for database setup)
- Python 3.x
- mysql-connector-python package

================================================================================
                        TROUBLESHOOTING
================================================================================

Common Issues and Solutions:

1. "Could not connect to MySQL" error:
   - Verify MySQL server is running
   - Check DB_CONFIG credentials in food.py
   - Ensure 'final' schema exists in MySQL

2. "Table doesn't exist" error:
   - Make sure you executed finalized_sql_file_one.sql first
   - Verify all tables were created successfully

3. "Access denied" error:
   - Check MySQL username and password in DB_CONFIG
   - Verify user has privileges on the 'final' database

4. "ModuleNotFoundError: No module named 'mysql'" error:
   - Run: pip install mysql-connector-python

5. "Schema 'final' does not exist" error:
   - Create the schema in MySQL Workbench as described in step 1b

================================================================================
                        TESTING THE SYSTEM
================================================================================

After setup, you can test the system using the following sample data:

Manufacturers:
- ID: 1 (John Smith) - owns Product 100 (Steak Dinner)
- ID: 2 (Alice Lee) - owns Product 101 (Mac & Cheese)

Suppliers:
- ID: 20 (Jane Doe)
- ID: 21 (James Miller)

Products:
- Product 100: Steak Dinner (standard_batch_units = 100)
- Product 101: Mac & Cheese (standard_batch_units = 300)

Note: Product 100's standard_batch_units may be 120 in your database. 
Adjust test cases accordingly (use multiples of 120: 120, 240, 360, etc.)

================================================================================
                        IMPORTANT NOTES
================================================================================

- The database name MUST be "final" (as specified in food.py) if you keep other name
make sure the change is made in food.py file as well.
- All SQL scripts must be executed in the correct order
- Ensure MySQL server is running before executing food.py
- The system uses CURDATE() = November 16, 2025 for date-based validations
- Ingredient batches require expiration dates >= 90 days from current date
- Production batches must produce units that are multiples of the product's 
  standard_batch_units

================================================================================

For additional support or questions, please contact us at our NCSU email addresses.

Thank you for reviewing our project!

================================================================================

