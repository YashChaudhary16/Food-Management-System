import mysql.connector
from getpass import getpass

# --- 1. Database Configuration ---
DB_CONFIG = {
    'user': 'root',
    'password': 'root',
    'host': '127.0.0.1',
    'database': 'demo',
    'use_pure': True
}

# --- 2. Utility Functions ---

def connect_db():
    """Establishes a connection to the MySQL database."""
    try:
        conn = mysql.connector.connect(**DB_CONFIG)
        conn.autocommit = True  # Enable autocommit to see changes immediately
        # Set isolation level to READ COMMITTED to see committed changes immediately
        cursor = conn.cursor()
        cursor.execute("SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED")
        cursor.close()
        return conn
    except mysql.connector.Error as err:
        print(f"\n[❌ DB CONNECTION ERROR] Could not connect to MySQL: {err}")
        print("Please check your DB_CONFIG settings.")
        return None

def execute_call(conn, procedure_name, args=None, commit=False):
    """Executes a stored procedure or function call."""
    cursor = conn.cursor(buffered=True)
    try:
        # Construct the CALL statement
        arg_placeholders = ', '.join(['%s'] * len(args)) if args else ''
        call_statement = f"CALL {procedure_name}({arg_placeholders})"
        
        cursor.callproc(procedure_name, args)
        
        # Check for results from procedures that return data (like TraceRecall)
        # Important: Consume ALL stored results to avoid caching issues
        results_printed = False
        for result in cursor.stored_results():
            if not results_printed:
                print(f"\n--- Results from {procedure_name} ---")
                results_printed = True
            # Fetch column names for header
            header = [i[0] for i in result.description]
            print("| " + " | ".join(header) + " |")
            print("-" * (sum(len(h) for h in header) + len(header) * 3 + 1))
            
            # Print rows
            for row in result.fetchall():
                print("| " + " | ".join(map(str, row)) + " |")
        
        # Ensure all results are fully consumed
        for _ in cursor.stored_results():
            pass  # Consume any remaining result sets
        
        if commit:
            conn.commit()
            print(f"\n[✅ SUCCESS] Transaction completed via {procedure_name}.")
        else:
             print(f"\n[✅ SUCCESS] Procedure {procedure_name} executed.")

    except mysql.connector.Error as err:
        conn.rollback()
        # Custom error codes (45000) raised by triggers/procedures are handled here
        print(f"\n[❌ TRANSACTION FAILED] Error Code {err.errno}: {err.msg}")

    finally:
        cursor.close()
        # Ensure cursor is fully closed and connection state is refreshed
        # This helps ensure subsequent queries see the latest committed data

def execute_query(conn, query, fetch=True):
    """Executes a SELECT query."""
    cursor = conn.cursor(buffered=True)
    try:
        cursor.execute(query)
        if fetch:
            if cursor.description:
                # Print Header
                header = [i[0] for i in cursor.description]
                print("| " + " | ".join(header) + " |")
                print("-" * (sum(len(h) for h in header) + len(header) * 3 + 1))
                
                # Print Data
                for row in cursor.fetchall():
                    print("| " + " | ".join(map(str, row)) + " |")
            else:
                print("[INFO] Query executed with no rows returned.")
            return cursor.fetchall()
        else:
            conn.commit()
            return None

    except mysql.connector.Error as err:
        print(f"\n[❌ QUERY ERROR] {err}")
        return None
    finally:
        cursor.close()


# --- 3. Role Menu Implementations ---

# ... (Previous utility functions and DB_CONFIG remain the same) ...

def manufacturer_menu(conn, manufacturer_id):
    """Manufacturer CLI flow, invoking procedures and reports."""
    while True:
        print("\n--- Manufacturer Menu (ID:", manufacturer_id, ") ---")
        print("1) Define/Update Product")
        print("2) Define/Update Product BOM (Recipe)")
        print("3) Record Ingredient Receipt (Triggers Lot/Inventory Update)")
        print("4) Create Production Batch (Triggers & Conflicts Check)")
        print("5) Reports")
        print("6) Product Recall Trace")
        print("0) Back to Main Menu")
        
        choice = input("Enter choice: ")
        
        try:
            if choice == '1':
                # CALL UpsertProduct(p_product_id, p_manufacturer_id, p_product_number, p_name, p_category_id, p_standard_batch_units)
                p_id = int(input("Product ID: "))
                num = input("Product Number (P-XXX): ")
                name = input("Product Name: ")
                cat_id = int(input("Category ID: "))
                units = int(input("Standard Batch Units: "))
                execute_call(conn, "UpsertProduct", (p_id, manufacturer_id, num, name, cat_id, units), commit=True)
            
            # --- IMPLEMENTATION FOR OPTION 2: Define/Update Product BOM (Recipe) ---
            # --- IMPLEMENTATION FOR OPTION 2: Define/Update Product BOM (Recipe) ---
            elif choice == '2':
                print("\n-- Define New Recipe Version --")
                p_id = int(input("Product ID for the recipe: "))
                
                ing_id = int(input("Ingredient ID to add/update in the new recipe version: "))
                qty = float(input("Quantity required for ingredient in standard batch units: "))
                
                # FIX: Added manufacturer_id (the 4th argument)
                execute_call(conn, "CreateNewRecipeVersion", (p_id, manufacturer_id, ing_id, qty), commit=True)
                
                print("[INFO] A new recipe version has been created for Product", p_id)


            # --- IMPLEMENTATION FOR OPTION 3: Record Ingredient Receipt ---
            elif choice == '3':
                # This mirrors the logic from the Supplier menu, ensuring the Manufacturer can also receive ingredients
                # The Lot Number Trigger is essential here.
                print("\n-- Recording New Ingredient Receipt --")
                i_id = int(input("Ingredient ID: "))
                s_id = int(input("Supplier ID (from whom you received it): "))
                quantity = float(input("Quantity Received: "))
                cost = float(input("Unit Cost: "))
                exp_date = input("Expiration Date (YYYY-MM-DD): ")
                b_id = input("Manufacturer's Internal Batch ID (e.g., 0001): ")
                
                # Construct the lot number as required by the strict 'int-int-Bint' trigger check
                lot_num = f"{i_id}-{s_id}-B{b_id}"
                
                query = f"""
                INSERT INTO IngredientBatch 
                (lot_number, ingredient_id, supplier_id, quantity, unit_cost, expiration_date) 
                VALUES ('{lot_num}', {i_id}, {s_id}, {quantity}, {cost}, '{exp_date}')
                """
                # The execution will trigger trg_IngredientBatch_LotNumber_BI
                execute_query(conn, query, fetch=False)
                print(f"[INFO] Attempted to insert lot: {lot_num}.")


            elif choice == '4':
                # CALL CreateProductBatch(p_product_id, p_manufacturer_id, p_recipe_id, p_units_produced, p_batch_id)
                p_id = int(input("Product ID: "))
                r_id = int(input("Recipe ID to use: "))
                units = int(input("Units to Produce (must be multiple of standard): "))
                b_id = input("Manufacturer Batch ID (e.g., 0001): ")
                exp_date = input("Expiration Date (YYYY-MM-DD): ")
                unit_cost = float(input("Unit Cost: "))
                
                # Lot number for product batch will be constructed as 'P_ID-M_ID-B_ID'
                lot_number = f"{p_id}-{manufacturer_id}-{b_id}"
                execute_call(conn, "CreateProductBatch", (p_id, manufacturer_id, r_id, units, b_id, exp_date, unit_cost), commit=True)
                
                # Verify batch was created and consumption records exist
                try:
                    verify_cursor = conn.cursor(buffered=True)
                    # Check if ProductBatch exists
                    verify_cursor.execute("SELECT lot_number FROM ProductBatch WHERE lot_number = %s", (lot_number,))
                    batch_exists = verify_cursor.fetchone()
                    
                    # Check if ProductionConsumption records exist
                    verify_cursor.execute("SELECT COUNT(*) FROM ProductionConsumption WHERE product_batch_lot = %s", (lot_number,))
                    consumption_count = verify_cursor.fetchone()[0]
                    
                    verify_cursor.close()
                    
                    if batch_exists:
                        print(f"[✓ VERIFICATION] Product batch {lot_number} created successfully.")
                        print(f"[✓ VERIFICATION] ProductionConsumption records: {consumption_count}")
                    else:
                        print(f"[⚠ WARNING] Product batch {lot_number} not found in database!")
                except Exception as e:
                    print(f"[⚠ WARNING] Could not verify batch creation: {e}")

            elif choice == '5':
                # ... (Reports logic remains the same) ...
                print("\n-- Reports --")
                print("5a) On-Hand Inventory")
                print("5b) Almost-Expired Lots (next 10 days)")
                print("5c) Nearly-Out-of-Stock (less than 1 standard batch)")
                report_choice = input("Enter report choice (a, b, c): ")
                
                if report_choice == 'a':
                    execute_query(conn, "SELECT IB.ingredient_id, I.common_name, IB.lot_number, IB.quantity, IB.expiration_date FROM IngredientBatch IB JOIN Ingredient I ON IB.ingredient_id = I.ingredient_id ORDER BY IB.ingredient_id, IB.expiration_date;")
                elif report_choice == 'b':
                    execute_query(conn, "SELECT lot_number, common_name, expiration_date FROM IngredientBatch JOIN Ingredient USING (ingredient_id) WHERE expiration_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 10 DAY) AND quantity > 0 ORDER BY expiration_date ASC;")
                elif report_choice == 'c':
                    # Simplified query relying on the logic defined earlier
                    execute_query(conn, "SELECT P.name AS ProductName, I.common_name AS IngredientName, SUM(IB.quantity) AS TotalOnHand, RI.qty * P.standard_batch_units AS RequiredForBatch FROM Product P JOIN RecipeMaster RM ON P.product_id = RM.product_id JOIN RecipeIngredient RI ON RM.recipe_id = RI.recipe_id JOIN Ingredient I ON RI.ingredient_id = I.ingredient_id LEFT JOIN IngredientBatch IB ON I.ingredient_id = IB.ingredient_id WHERE RM.version_no = (SELECT MAX(version_no) FROM RecipeMaster WHERE product_id = P.product_id) GROUP BY P.name, I.common_name, RequiredForBatch HAVING TotalOnHand < RequiredForBatch;")


            elif choice == '6':
                # CALL TraceRecall(p_recalled_ingredient_id, p_recalled_lot_number)
                # Ensure we see the latest committed data by using a direct query instead of stored procedure
                # This avoids MySQL Connector Python's caching issues with stored procedures
                try:
                    # Force commit and refresh connection state
                    conn.commit()
                    # Execute a dummy query to refresh the connection
                    temp_cursor = conn.cursor()
                    temp_cursor.execute("SELECT 1")
                    temp_cursor.fetchall()
                    temp_cursor.close()
                    
                    ing_id = input("Ingredient ID (or leave blank): ") or None
                    lot_num = input("Specific Lot Number (or leave blank): ") or None
                    
                    # Requires conversion for SQL call
                    ing_id = int(ing_id) if ing_id else None
                    
                    # Build the WHERE clause dynamically with proper SQL injection protection
                    where_clause = ""
                    if ing_id is not None and lot_num is not None:
                        where_clause = f"((IB.ingredient_id = %s) OR (IB.lot_number = %s))"
                        params = (ing_id, lot_num)
                    elif ing_id is not None:
                        where_clause = f"(IB.ingredient_id = %s)"
                        params = (ing_id,)
                    elif lot_num is not None:
                        where_clause = f"(IB.lot_number = %s)"
                        params = (lot_num,)
                    else:
                        where_clause = "1=0"  # No criteria provided, return nothing
                        params = ()
                    
                    # Use direct SQL query with parameterized query to ensure fresh data
                    query = f"""
                    SELECT DISTINCT
                        PB.lot_number AS ProductLot, 
                        P.name AS ProductName,
                        PB.produced_at,
                        IB.lot_number AS ConsumedIngredientLot, 
                        IB.expiration_date AS LotExpiration
                    FROM 
                        ProductBatch PB
                    JOIN 
                        ProductionConsumption PC ON PB.lot_number = PC.product_batch_lot
                    JOIN 
                        IngredientBatch IB ON PC.ingredient_lot = IB.lot_number
                    JOIN 
                        Product P ON PB.product_id = P.product_id
                    WHERE 
                        {where_clause}
                        -- 20-day time window: only include products produced within the last 20 days
                        AND PB.produced_at >= DATE_SUB(CURDATE(), INTERVAL 20 DAY)
                        AND PB.produced_at <= CURDATE()
                    ORDER BY 
                        PB.produced_at DESC
                    """
                    
                    print("\n--- Results from TraceRecall ---")
                    # Use execute_query but with parameterized query
                    cursor = conn.cursor(buffered=True)
                    try:
                        if params:
                            cursor.execute(query, params)
                        else:
                            cursor.execute(query)
                        
                        if cursor.description:
                            # Print Header
                            header = [i[0] for i in cursor.description]
                            print("| " + " | ".join(header) + " |")
                            print("-" * (sum(len(h) for h in header) + len(header) * 3 + 1))
                            
                            # Print Data
                            rows = cursor.fetchall()
                            if rows:
                                for row in rows:
                                    print("| " + " | ".join(map(str, row)) + " |")
                            else:
                                print("[INFO] No results found.")
                    finally:
                        cursor.close()
                    
                except Exception as e:
                    print(f"\n[❌ ERROR] Error executing trace recall: {e}")
                    import traceback
                    traceback.print_exc()
                    # Fallback to stored procedure if direct query fails
                    if 'ing_id' in locals():
                        execute_call(conn, "TraceRecall", (ing_id, lot_num))

            elif choice == '0':
                break
            else:
                print("Invalid choice.")
        except ValueError:
            print("Invalid input. Please enter numbers where expected.")

# ... (Supplier Menu, Viewer Menu, and main functions remain the same) ...
def supplier_menu(conn, supplier_id):
    """Supplier CLI flow, focusing on data maintenance."""
    while True:
        print("\n--- Supplier Menu ---")
        print("1) Declare Ingredients Supplied")
        print("2) Maintain Do-Not-Combine List")
        print("3) Create Ingredient Batch (Triggers Lot/Inventory Update)")
        print("4) Create/Update Ingredient (Atomic or Compound)")
        print("0) Back to Main Menu")
        
        choice = input("Enter choice: ")
        
        try:
            if choice == '1':
                # CALL ManageSupplierCapability(p_supplier_id, p_ingredient_id, p_action)
                ing_id = int(input("Ingredient ID to ADD/REMOVE capability for: "))
                action = input("Action ('ADD' or 'REMOVE'): ").upper()
                execute_call(conn, "ManageSupplierCapability", (supplier_id, ing_id, action), commit=True)

            elif choice == '2':
                # CALL ManageConflictPairs(p_ingredient_a, p_ingredient_b, p_action)
                ing_a = int(input("First Ingredient ID: "))
                ing_b = int(input("Second Ingredient ID: "))
                action = input("Action ('ADD' or 'REMOVE'): ").upper()
                execute_call(conn, "ManageConflictPairs", (ing_a, ing_b, action), commit=True)
            
            elif choice == '3':
                # INSERT INTO IngredientBatch (Triggers are implicitly activated)
                print("\n-- Recording New Ingredient Receipt --")
                i_id = int(input("Ingredient ID: "))
                quantity = float(input("Quantity Received: "))
                cost = float(input("Unit Cost: "))
                exp_date = input("Expiration Date (YYYY-MM-DD): ")
                b_id = input("Supplier's Internal Batch ID (e.g., B999): ")
                
                # Construct the lot number as required by the trigger check
                lot_num = f"{i_id}-{supplier_id}-{b_id}"
                
                query = f"""
                INSERT INTO IngredientBatch 
                (lot_number, ingredient_id, supplier_id, quantity, unit_cost, expiration_date) 
                VALUES ('{lot_num}', {i_id}, {supplier_id}, {quantity}, {cost}, '{exp_date}')
                """
                execute_query(conn, query, fetch=False)
            
            elif choice == '4':
                # Create/Update Ingredient (Atomic or Compound)
                print("\n-- Create/Update Ingredient --")
                ing_id = int(input("Ingredient ID: "))
                common_name = input("Ingredient Name: ")
                ing_type = input("Type (ATOMIC or COMPOUND): ").upper()
                
                if ing_type not in ['ATOMIC', 'COMPOUND']:
                    print("[❌ ERROR] Type must be either 'ATOMIC' or 'COMPOUND'.")
                    continue
                
                cursor = conn.cursor(buffered=True)
                try:
                    # Check if ingredient exists
                    cursor.execute("SELECT ingredient_id, type FROM Ingredient WHERE ingredient_id = %s", (ing_id,))
                    existing = cursor.fetchone()
                    
                    if existing:
                        # Update existing ingredient
                        cursor.execute(
                            "UPDATE Ingredient SET common_name = %s, type = %s WHERE ingredient_id = %s",
                            (common_name, ing_type, ing_id)
                        )
                        print(f"[✓ UPDATED] Ingredient {ing_id} ({common_name}) updated.")
                    else:
                        # Insert new ingredient
                        cursor.execute(
                            "INSERT INTO Ingredient (ingredient_id, common_name, type) VALUES (%s, %s, %s)",
                            (ing_id, common_name, ing_type)
                        )
                        print(f"[✓ CREATED] New ingredient {ing_id} ({common_name}) created as {ing_type}.")
                    
                    # If COMPOUND, handle formulation
                    if ing_type == 'COMPOUND':
                        print("\n-- Define Compound Ingredient Formulation --")
                        
                        # Check for existing formulation
                        cursor.execute(
                            "SELECT MAX(version_no) FROM IngredientFormulation WHERE ingredient_id = %s AND supplier_id = %s",
                            (ing_id, supplier_id)
                        )
                        result = cursor.fetchone()
                        next_version = (result[0] + 1) if result[0] else 1
                        
                        print(f"\nNext version number for this ingredient: {next_version}")
                        version_choice = input(f"Create new version {next_version}? (y/n): ").lower()
                        
                        if version_choice == 'y':
                            pack_size = float(input("Pack Size (in ounces): "))
                            price_per_pack = float(input("Price Per Pack: "))
                            effective_start = input("Effective Start Date (YYYY-MM-DD): ")
                            effective_end_input = input("Effective End Date (YYYY-MM-DD, or leave blank): ")
                            effective_end = effective_end_input if effective_end_input.strip() else None
                            
                            # Insert formulation
                            if effective_end:
                                cursor.execute(
                                    """INSERT INTO IngredientFormulation 
                                    (ingredient_id, supplier_id, version_no, pack_size, price_per_pack, effective_start, effective_end)
                                    VALUES (%s, %s, %s, %s, %s, %s, %s)""",
                                    (ing_id, supplier_id, next_version, pack_size, price_per_pack, effective_start, effective_end)
                                )
                            else:
                                cursor.execute(
                                    """INSERT INTO IngredientFormulation 
                                    (ingredient_id, supplier_id, version_no, pack_size, price_per_pack, effective_start)
                                    VALUES (%s, %s, %s, %s, %s, %s)""",
                                    (ing_id, supplier_id, next_version, pack_size, price_per_pack, effective_start)
                                )
                            
                            formulation_id = cursor.lastrowid
                            print(f"[✓ CREATED] Formulation version {next_version} (Formulation ID: {formulation_id})")
                            
                            # Add materials (atomic ingredients)
                            print("\n-- Add Atomic Materials to Formulation --")
                            materials = []
                            while True:
                                material_id = input("Atomic Ingredient ID (or 'done' to finish): ")
                                if material_id.lower() == 'done':
                                    break
                                
                                try:
                                    material_id = int(material_id)
                                    # Verify it's atomic
                                    cursor.execute("SELECT type FROM Ingredient WHERE ingredient_id = %s", (material_id,))
                                    mat_type = cursor.fetchone()
                                    
                                    if not mat_type:
                                        print(f"[⚠ WARNING] Ingredient {material_id} does not exist. Skipping.")
                                        continue
                                    
                                    if mat_type[0] != 'ATOMIC':
                                        print(f"[⚠ WARNING] Ingredient {material_id} is not ATOMIC. Only ATOMIC ingredients can be materials.")
                                        continue
                                    
                                    qty = float(input(f"Quantity (in ounces) of ingredient {material_id}: "))
                                    
                                    # Insert material
                                    cursor.execute(
                                        "INSERT INTO FormulationMaterials (formulation_id, ingredient_id, qty) VALUES (%s, %s, %s)",
                                        (formulation_id, material_id, qty)
                                    )
                                    materials.append((material_id, qty))
                                    print(f"[✓ ADDED] Material {material_id} with quantity {qty} oz")
                                    
                                except ValueError:
                                    print("[⚠ WARNING] Invalid ingredient ID. Please enter a number.")
                            
                            if materials:
                                print(f"\n[✓ SUCCESS] Formulation created with {len(materials)} material(s).")
                            else:
                                print("[⚠ WARNING] Formulation created but no materials were added.")
                        else:
                            print("[INFO] Formulation creation cancelled.")
                    
                    conn.commit()
                    print(f"\n[✅ SUCCESS] Ingredient operation completed.")
                    
                except mysql.connector.Error as err:
                    conn.rollback()
                    print(f"\n[❌ ERROR] Database error: {err}")
                finally:
                    cursor.close()
                
            elif choice == '0':
                break
            else:
                print("Invalid choice.")
        except ValueError:
            print("Invalid input. Please enter numbers where expected.")

def viewer_menu(conn):
    """General Viewer CLI flow, primarily using views."""
    while True:
        print("\n--- General (Viewer) Menu ---")
        print("1) Product Catalog (v_ProductCatalog)")
        print("2) Flattened Product BOM (v_FlattenedBOM)")
        print("3) Active Formulations List (v_ActiveFormulations)")
        print("4) Recent Health Risk Violations (v_RecentHealthRiskViolations)")
        print("0) Back to Main Menu")

        choice = input("Enter choice: ")

        if choice == '1':
            execute_query(conn, "SELECT * FROM v_ProductCatalog;")
        elif choice == '2':
            r_id = input("Enter Recipe ID to view BOM: ")
            execute_query(conn, f"SELECT * FROM v_FlattenedBOM WHERE recipe_id = {r_id};")
        elif choice == '3':
            execute_query(conn, "SELECT * FROM v_ActiveFormulations;")
        elif choice == '4':
            execute_query(conn, "SELECT * FROM v_RecentHealthRiskViolations;")
        elif choice == '0':
            break
        else:
            print("Invalid choice.")


def login_menu():
    """Main application loop and role selection."""
    conn = connect_db()
    if not conn:
        return

    while True:
        print("\n==============================")
        print("  FOOD MANAGEMENT SYSTEM CLI  ")
        print("==============================")
        print("Select Role:")
        print("1. Manufacturer (e.g., 1 or 2)")
        print("2. Supplier (e.g., 20 or 21)")
        print("3. General (Viewer)")
        print("0. Exit")

        role_choice = input("Enter role choice: ")

        if role_choice == '1':
            try:
                user_id = int(input("Enter Manufacturer ID: "))
                manufacturer_menu(conn, user_id)
            except ValueError:
                print("Invalid Manufacturer ID.")
        elif role_choice == '2':
            try:
                user_id = int(input("Enter Supplier ID: "))
                supplier_menu(conn, user_id)
            except ValueError:
                print("Invalid Supplier ID.")
        elif role_choice == '3':
            viewer_menu(conn)
        elif role_choice == '0':
            print("Exiting CLI. Goodbye!")
            conn.close()
            break
        else:
            print("Invalid role choice.")


if __name__ == "__main__":
    # WARNING: Please update the DB_CONFIG credentials before running this script.
    # The 'password' field should probably use getpass.getpass() in a real application.
    
    # Example using actual secure input for the password
    # DB_CONFIG['password'] = getpass("Enter database password: ")
    
    login_menu()