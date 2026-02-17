-- DDL SCRIPT START

-- 1. Manufacturer
CREATE TABLE IF NOT EXISTS Manufacturer (
    manufacturer_id INT PRIMARY KEY,
    name VARCHAR(255) NOT NULL
); 

-- 2. Category
CREATE TABLE IF NOT EXISTS Category (
    category_id INT PRIMARY KEY,
    name VARCHAR(255) NOT NULL
);

-- 3. Product
CREATE TABLE IF NOT EXISTS Product (
    product_id INT PRIMARY KEY,
    product_number VARCHAR(100),
    name VARCHAR(255) NOT NULL,
    standard_batch_units INT CHECK (standard_batch_units > 0),
    category_id INT NOT NULL,
    FOREIGN KEY (category_id) REFERENCES Category(category_id)
);

-- 4. ProductManufacturer (Ownership/Access Control)
CREATE TABLE IF NOT EXISTS ProductManufacturer (
    product_id INT NOT NULL,
    manufacturer_id INT NOT NULL,
    PRIMARY KEY (product_id, manufacturer_id),
    FOREIGN KEY (product_id) REFERENCES Product(product_id),
    FOREIGN KEY (manufacturer_id) REFERENCES Manufacturer(manufacturer_id)
);


-- 5. Product Batch (Updated to include cost fields)
CREATE TABLE IF NOT EXISTS ProductBatch (
    lot_number VARCHAR(100) PRIMARY KEY,
    product_id INT NOT NULL,
    produced_at DATE NOT NULL,
    expiration_date DATE,
    produced_qty DECIMAL(12,2) CHECK (produced_qty >= 0),
    total_cost DECIMAL(12, 2) CHECK (total_cost >= 0) DEFAULT 0, -- NEW: For calculated batch cost
    FOREIGN KEY (product_id) REFERENCES Product(product_id)
);

-- 6. Supplier
CREATE TABLE IF NOT EXISTS Supplier (
    supplier_id INT PRIMARY KEY,
    name VARCHAR(255) NOT NULL
);

-- 7. Ingredient
CREATE TABLE IF NOT EXISTS Ingredient (
    ingredient_id INT PRIMARY KEY,
    common_name VARCHAR(255) NOT NULL,
    type VARCHAR(100) CHECK (type IN ('ATOMIC', 'COMPOUND')) -- Enforcing ATOMIC/COMPOUND type
);

-- 8. IngredientBatch
CREATE TABLE IF NOT EXISTS IngredientBatch (
    lot_number VARCHAR(100) PRIMARY KEY,
    ingredient_id INT NOT NULL,
    supplier_id INT NOT NULL,
    expiration_date DATE,
    quantity DECIMAL(12,2) CHECK (quantity >= 0),
    unit_cost DECIMAL(10,2) CHECK (unit_cost >= 0),
    FOREIGN KEY (ingredient_id) REFERENCES Ingredient(ingredient_id),
    FOREIGN KEY (supplier_id) REFERENCES Supplier(supplier_id)
);

-- 9. Ingredient Formulation (Supplier's definition of an ingredient, including versioning)
CREATE TABLE IF NOT EXISTS IngredientFormulation (
    formulation_id INT PRIMARY KEY AUTO_INCREMENT,
    ingredient_id INT NOT NULL, -- This is the compound ingredient ID
    supplier_id INT NOT NULL,
    version_no INT NOT NULL,
    pack_size DECIMAL(12,2) CHECK (pack_size > 0),
    price_per_pack DECIMAL(10,2) CHECK (price_per_pack >= 0),
    effective_start DATE NOT NULL,
    effective_end DATE,
    
    UNIQUE (ingredient_id, supplier_id, version_no), -- Ensures version uniqueness
    UNIQUE (ingredient_id, supplier_id, effective_start), -- Helps prevent overlapping effective periods
    
    FOREIGN KEY (ingredient_id) REFERENCES Ingredient(ingredient_id),
    FOREIGN KEY (supplier_id) REFERENCES Supplier(supplier_id)
);

-- 10. FormulationMaterials (Composition of a compound ingredient, enforces one-level composition)
CREATE TABLE IF NOT EXISTS FormulationMaterials (
    formulation_id INT NOT NULL,
    ingredient_id INT NOT NULL, -- This is the ATOMIC material ID
    qty DECIMAL(12,2) CHECK (qty > 0),
    -- NOTE: Business rule (Material must be ATOMIC) must be enforced by application/trigger
    
    PRIMARY KEY (formulation_id, ingredient_id),
    FOREIGN KEY (formulation_id) REFERENCES IngredientFormulation(formulation_id),
    FOREIGN KEY (ingredient_id) REFERENCES Ingredient(ingredient_id)
);

-- 11. RecipeMaster (NEW: Manages versioning of product recipes)
CREATE TABLE IF NOT EXISTS RecipeMaster (
    recipe_id INT PRIMARY KEY AUTO_INCREMENT,
    product_id INT NOT NULL,
    version_no INT NOT NULL,
    creation_date DATE NOT NULL,
    
    UNIQUE (product_id, version_no), -- Ensures version number is unique per product
    FOREIGN KEY (product_id) REFERENCES Product(product_id)
);

-- 12. RecipeIngredient (Replaces the old 'Recipe' table, links to RecipeMaster)
CREATE TABLE IF NOT EXISTS RecipeIngredient (
    recipe_id INT NOT NULL,
    ingredient_id INT NOT NULL,
    qty DECIMAL(12,2) CHECK (qty > 0),

    -- PK is now fully dependent on both columns
    PRIMARY KEY (recipe_id, ingredient_id),

    FOREIGN KEY (recipe_id) REFERENCES RecipeMaster(recipe_id),
    FOREIGN KEY (ingredient_id) REFERENCES Ingredient(ingredient_id)
);


-- 13. ProductionConsumption (Associative entity linking ProductBatch to IngredientBatch)
CREATE TABLE IF NOT EXISTS ProductionConsumption (
    product_batch_lot VARCHAR(100) NOT NULL,
    ingredient_lot VARCHAR(100) NOT NULL,
    qty DECIMAL(12,2) CHECK (qty > 0),
    
    PRIMARY KEY (product_batch_lot, ingredient_lot),
    FOREIGN KEY (product_batch_lot) REFERENCES ProductBatch(lot_number),
    FOREIGN KEY (ingredient_lot) REFERENCES IngredientBatch(lot_number)
);

-- 14. ConflictPairs (The global Do-Not-Combine List)
CREATE TABLE IF NOT EXISTS ConflictPairs (
    ingredient_a INT NOT NULL,
    ingredient_b INT NOT NULL,
    PRIMARY KEY (ingredient_a, ingredient_b),
    FOREIGN KEY (ingredient_a) REFERENCES Ingredient(ingredient_id),
    FOREIGN KEY (ingredient_b) REFERENCES Ingredient(ingredient_id),
    CHECK (ingredient_a <> ingredient_b)
);

-- 15. User (For login/access roles)
CREATE TABLE IF NOT EXISTS User (
    user_id VARCHAR(100) PRIMARY KEY,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    role_code VARCHAR(100)
);

-- 16. SupplierCapability (NEW: Maintains which ingredient types a supplier can provide)
CREATE TABLE IF NOT EXISTS SupplierCapability (
    supplier_id INT NOT NULL,
    ingredient_id INT NOT NULL,
    PRIMARY KEY (supplier_id, ingredient_id),
    FOREIGN KEY (supplier_id) REFERENCES Supplier(supplier_id),
    FOREIGN KEY (ingredient_id) REFERENCES Ingredient(ingredient_id)
);

-- DDL SCRIPT END


-- ------------------------------------------------------------------------

DELIMITER //
-- Procedure to manage Supplier capabilities (Manage Ingredients Supplied)
CREATE PROCEDURE ManageSupplierCapability (
    IN p_supplier_id INT,
    IN p_ingredient_id INT,
    IN p_action VARCHAR(10) -- 'ADD' or 'REMOVE'
)
BEGIN
    IF p_action = 'ADD' THEN
        INSERT IGNORE INTO SupplierCapability (supplier_id, ingredient_id)
        VALUES (p_supplier_id, p_ingredient_id);
    ELSEIF p_action = 'REMOVE' THEN
        DELETE FROM SupplierCapability
        WHERE supplier_id = p_supplier_id AND ingredient_id = p_ingredient_id;
    END IF;
END //

-- Procedure to manage the Do-Not-Combine List
CREATE PROCEDURE ManageConflictPairs (
    IN p_ingredient_a INT,
    IN p_ingredient_b INT,
    IN p_action VARCHAR(10) -- 'ADD' or 'REMOVE'
)
BEGIN
    -- Ensure order is consistent to prevent duplicate entries (A, B) and (B, A)
    DECLARE v_ing_1 INT;
    DECLARE v_ing_2 INT;
    
    IF p_ingredient_a < p_ingredient_b THEN
        SET v_ing_1 = p_ingredient_a;
        SET v_ing_2 = p_ingredient_b;
    ELSE
        SET v_ing_1 = p_ingredient_b;
        SET v_ing_2 = p_ingredient_a;
    END IF;

    IF p_action = 'ADD' THEN
        INSERT IGNORE INTO ConflictPairs (ingredient_a, ingredient_b)
        VALUES (v_ing_1, v_ing_2);
    ELSEIF p_action = 'REMOVE' THEN
        DELETE FROM ConflictPairs
        WHERE ingredient_a = v_ing_1 AND ingredient_b = v_ing_2;
    END IF;
END //

-- Procedure to create or update a Product Type and set ownership
CREATE PROCEDURE UpsertProduct (
    IN p_product_id INT,
    IN p_manufacturer_id INT,
    IN p_product_number VARCHAR(100),
    IN p_name VARCHAR(255),
    IN p_category_id INT,
    IN p_standard_batch_units INT
)
BEGIN
    -- Upsert Product
    INSERT INTO Product (product_id, product_number, name, category_id, standard_batch_units)
    VALUES (p_product_id, p_product_number, p_name, p_category_id, p_standard_batch_units)
    ON DUPLICATE KEY UPDATE 
        product_number = p_product_number, name = p_name, 
        category_id = p_category_id, standard_batch_units = p_standard_batch_units;

    -- Establish/Confirm Ownership
    INSERT IGNORE INTO ProductManufacturer (product_id, manufacturer_id)
    VALUES (p_product_id, p_manufacturer_id);
END //

-- Procedure to create a new Recipe Version
CREATE PROCEDURE CreateNewRecipeVersion (
    IN p_product_id INT,
    IN p_manufacturer_id INT,
    -- NOTE: In a CLI, ingredient pairs would be passed as a temporary table or JSON
    IN p_ing_1 INT, 
    IN p_qty_1 DECIMAL(12,2) 
    -- ... and so on
)
BEGIN
    DECLARE v_new_version_no INT;
    DECLARE v_new_recipe_id INT;
    
    -- 1. Authorization Check (Manufacturer must own the product)
    IF NOT EXISTS (SELECT 1 FROM ProductManufacturer WHERE product_id = p_product_id AND manufacturer_id = p_manufacturer_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Manufacturer does not own this product.';
    END IF;

    -- 2. Get Next Version Number
    SELECT IFNULL(MAX(version_no), 0) + 1 INTO v_new_version_no
    FROM RecipeMaster WHERE product_id = p_product_id;

    -- 3. BEGIN TRANSACTION: Insert RecipeMaster
    START TRANSACTION;
    INSERT INTO RecipeMaster (product_id, version_no, creation_date)
    VALUES (p_product_id, v_new_version_no, CURDATE());
    SET v_new_recipe_id = LAST_INSERT_ID();

    -- 4. Insert Recipe Ingredients (BOM) - CORRECTED FOR BCNF
    IF p_ing_1 IS NOT NULL THEN
        -- The product_id column has been removed here:
        INSERT INTO RecipeIngredient (recipe_id, ingredient_id, qty)
        VALUES (v_new_recipe_id, p_ing_1, p_qty_1);
    END IF;
    -- ... (Logic to loop through all input ingredient pairs)
    
    COMMIT;
END //
DELIMITER ;
-- -----------------------------------------------
DELIMITER //
CREATE FUNCTION fn_CheckForConflicts(p_recipe_id INT)
RETURNS INT
DETERMINISTIC
BEGIN
    DECLARE v_conflict_count INT DEFAULT 0;
    
    -- Use the v_FlattenedBOM logic to get the full ingredient set for the recipe
    WITH RecipeIngredients AS (
        SELECT DISTINCT atomic_ingredient_id 
        FROM v_FlattenedBOM  
        WHERE recipe_id = p_recipe_id
    )
    -- Select the count of ALL conflict pairs (CP) where BOTH ingredient_a 
    -- and ingredient_b are present in the RecipeIngredients set.
    SELECT COUNT(CP.ingredient_a) INTO v_conflict_count
    FROM ConflictPairs CP
    WHERE 
        -- Check if ingredient_a is present in the recipe
        CP.ingredient_a IN (SELECT atomic_ingredient_id FROM RecipeIngredients)
        AND
        -- Check if ingredient_b is also present in the recipe
        CP.ingredient_b IN (SELECT atomic_ingredient_id FROM RecipeIngredients);
        
    RETURN v_conflict_count;
END //
DELIMITER ;

DELIMITER //
CREATE PROCEDURE CreateProductBatch (
    IN p_product_id INT,
    IN p_manufacturer_id INT,
    IN p_recipe_id INT,
    IN p_units_produced INT,
    IN p_batch_id VARCHAR(50), -- The unique identifier portion from the manufacturer
    IN p_expiration_date DATE,
    IN p_unit_cost DECIMAL(10,2)
)
BEGIN
    -- All variable declarations
    DECLARE v_standard_units INT;
    DECLARE v_total_cost DECIMAL(12,2) DEFAULT 0;
    DECLARE v_lot_number VARCHAR(100);
    DECLARE v_conflict_count INT;
    DECLARE v_error_message VARCHAR(255);
    DECLARE v_batch_multiplier DECIMAL(12,2);
    
    -- Variables for cursor loop
    DECLARE done INT DEFAULT 0;
    DECLARE v_ingredient_id INT;
    DECLARE v_required_qty DECIMAL(12,2);
    DECLARE v_total_needed DECIMAL(12,2);
    DECLARE v_remaining DECIMAL(12,2);
    DECLARE v_lot_number_ing VARCHAR(100);
    DECLARE v_available_qty DECIMAL(12,2);
    DECLARE v_consume_qty DECIMAL(12,2);
    DECLARE v_lot_cost DECIMAL(12,2);
    
    -- Cursor for recipe ingredients
    DECLARE v_recipe_cursor CURSOR FOR 
        SELECT ingredient_id, qty 
        FROM RecipeIngredient 
        WHERE recipe_id = p_recipe_id;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;
    
    -- Lot generation
    SET v_lot_number = CONCAT(p_product_id, '-', p_manufacturer_id, '-', p_batch_id);

    -- 1. Pre-Transaction Validations
    SELECT standard_batch_units INTO v_standard_units FROM Product WHERE product_id = p_product_id;
    
    -- Ensure production quantity is positive and a multiple of standard batch size
    IF p_units_produced <= 0 OR v_standard_units IS NULL OR p_units_produced % v_standard_units != 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Produced units must be a positive multiple of the standard batch size.';
    END IF;

    -- 2. Health Risk Evaluation (Blocking Check)
    SET v_conflict_count = fn_CheckForConflicts(p_recipe_id);
    IF v_conflict_count > 0 THEN
        SET v_error_message = CONCAT('Batch creation blocked: Recipe contains ', v_conflict_count, ' incompatible ingredient pair(s).');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_error_message;
    END IF;

    -- Ensure we have expiration and cost values
    IF p_expiration_date IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Expiration date must be provided.';
    END IF;

    -- Calculate batch multiplier (how many standard batches we're producing)
    SET v_batch_multiplier = p_units_produced / v_standard_units;

    -- 3. BEGIN TRANSACTION: FEFO Selection, Consumption, and Costing
    START TRANSACTION;
    
    -- Step 3a: Pre-validate inventory availability and calculate cost
    -- Reset cursor state
    SET done = 0;
    SET v_total_cost = 0;
    
    -- Open cursor to iterate through recipe ingredients (first pass: validation and costing)
    OPEN v_recipe_cursor;
    
    ingredient_loop: LOOP
        FETCH v_recipe_cursor INTO v_ingredient_id, v_required_qty;
        IF done THEN
            LEAVE ingredient_loop;
        END IF;
        
        -- Calculate total quantity needed for this production run
        SET v_total_needed = v_required_qty * v_batch_multiplier;
        SET v_remaining = v_total_needed;
        
        -- FEFO: Check available lots and calculate cost (validation pass)
        lot_loop: WHILE v_remaining > 0 DO
            -- Get next available lot by FEFO (First Expired, First Out)
            SELECT lot_number, quantity, unit_cost
            INTO v_lot_number_ing, v_available_qty, v_lot_cost
            FROM IngredientBatch
            WHERE ingredient_id = v_ingredient_id 
              AND quantity > 0
              AND expiration_date > CURDATE()
            ORDER BY expiration_date ASC, lot_number ASC
            LIMIT 1;
            
            -- Check if we have enough inventory
            IF v_lot_number_ing IS NULL THEN
                ROLLBACK;
                SET v_error_message = CONCAT('Insufficient inventory for ingredient ID ', v_ingredient_id, '. Required: ', v_remaining);
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_error_message;
            END IF;
            
            -- Determine how much we'll consume from this lot
            IF v_remaining >= v_available_qty THEN
                SET v_consume_qty = v_available_qty;
            ELSE
                SET v_consume_qty = v_remaining;
            END IF;
            
            -- Accumulate cost: quantity consumed * unit cost of lot
            SET v_total_cost = v_total_cost + (v_consume_qty * v_lot_cost);
            
            -- Decrement remaining needed
            SET v_remaining = v_remaining - v_consume_qty;
        END WHILE lot_loop;
    END LOOP ingredient_loop;
    
    CLOSE v_recipe_cursor;
    
    -- Step 3b: Insert ProductBatch FIRST (required for foreign key in ProductionConsumption)
    INSERT INTO ProductBatch (lot_number, product_id, produced_at, expiration_date, produced_qty, total_cost)
    VALUES (v_lot_number, p_product_id, CURDATE(), p_expiration_date, p_units_produced, v_total_cost);
    
    -- Step 3c: Now insert ProductionConsumption records (second pass: actual consumption)
    -- Reset cursor state for second pass
    SET done = 0;
    
    -- Reopen cursor to iterate through recipe ingredients again (second pass: consumption)
    OPEN v_recipe_cursor;
    
    ingredient_loop2: LOOP
        FETCH v_recipe_cursor INTO v_ingredient_id, v_required_qty;
        IF done THEN
            LEAVE ingredient_loop2;
        END IF;
        
        -- Reset done flag in case it was set by SELECT INTO in previous iteration
        SET done = 0;
        
        -- Calculate total quantity needed for this production run
        SET v_total_needed = v_required_qty * v_batch_multiplier;
        SET v_remaining = v_total_needed;
        
        -- FEFO: Consume from lots ordered by expiration date (earliest first)
        lot_loop2: WHILE v_remaining > 0 DO
            -- Reset done flag before SELECT INTO (in case it was set previously)
            SET done = 0;
            
            -- Get next available lot by FEFO (First Expired, First Out)
            SELECT lot_number, quantity
            INTO v_lot_number_ing, v_available_qty
            FROM IngredientBatch
            WHERE ingredient_id = v_ingredient_id 
              AND quantity > 0
              AND expiration_date > CURDATE()
            ORDER BY expiration_date ASC, lot_number ASC
            LIMIT 1;
            
            -- Check if we found a lot (either NULL or done was set by NOT FOUND handler)
            IF v_lot_number_ing IS NULL OR done = 1 THEN
                ROLLBACK;
                SET v_error_message = CONCAT('Insufficient inventory for ingredient ID ', v_ingredient_id, ' in second pass. Required: ', v_remaining);
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_error_message;
            END IF;
            
            -- Reset done flag after successful SELECT
            SET done = 0;
            
            -- Determine how much to consume from this lot
            IF v_remaining >= v_available_qty THEN
                SET v_consume_qty = v_available_qty;
            ELSE
                SET v_consume_qty = v_remaining;
            END IF;
            
            -- Insert consumption record (triggers will validate expiration and decrement inventory)
            INSERT INTO ProductionConsumption (product_batch_lot, ingredient_lot, qty)
            VALUES (v_lot_number, v_lot_number_ing, v_consume_qty);
            
            -- Decrement remaining needed
            SET v_remaining = v_remaining - v_consume_qty;
        END WHILE lot_loop2;
    END LOOP ingredient_loop2;
    
    CLOSE v_recipe_cursor;
    
    COMMIT;
END //
DELIMITER ;


-- ------------------
DELIMITER //
CREATE PROCEDURE TraceRecall (
    IN p_recalled_ingredient_id INT,
    IN p_recalled_lot_number VARCHAR(100)
)
BEGIN
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
        -- Trace based on ID OR specific Lot Number (handle NULL parameters)
        ((p_recalled_ingredient_id IS NOT NULL AND IB.ingredient_id = p_recalled_ingredient_id)
         OR 
         (p_recalled_lot_number IS NOT NULL AND IB.lot_number = p_recalled_lot_number))
        -- 20-day time window: only include products produced within the last 20 days
        AND PB.produced_at >= DATE_SUB(CURDATE(), INTERVAL 20 DAY)
        AND PB.produced_at <= CURDATE()
    ORDER BY 
        PB.produced_at DESC;
END //
DELIMITER ;

-- ------------------------------------------------------------------------

DELIMITER //
CREATE TRIGGER trg_IngredientBatch_LotNumber_BI
BEFORE INSERT ON IngredientBatch
FOR EACH ROW
BEGIN
    -- The pattern strictly enforces: [Digits]-[Digits]-B[Digits]
    IF NEW.lot_number NOT REGEXP '^[0-9]+-[0-9]+-B[0-9]+$' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Lot number must follow the strict pattern: <ingredientId>-<supplierId>-B<batchId>. Example: 101-20-B0001.';
    END IF;
END //
DELIMITER ;

DELIMITER //
CREATE TRIGGER trg_ProductionConsumption_CheckExpiration_BI
BEFORE INSERT ON ProductionConsumption
FOR EACH ROW
BEGIN
    DECLARE v_expiration_date DATE;
    DECLARE v_production_date DATE;

    -- 1. Fetch the expiration date of the specific ingredient lot
    SELECT expiration_date INTO v_expiration_date
    FROM IngredientBatch
    WHERE lot_number = NEW.ingredient_lot;

    -- 2. Fetch the production date of the final product batch
    SELECT produced_at INTO v_production_date
    FROM ProductBatch
    WHERE lot_number = NEW.product_batch_lot;

    -- 3. Block the consumption if the ingredient expired BEFORE the product was made
    -- Check: If the ingredient expires on 2025-10-30, and production starts on 2025-10-31, it is expired.
    IF v_expiration_date < v_production_date THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Consumption rejected: Ingredient lot is already expired.';
    END IF;
END //
DELIMITER ;

DELIMITER //
CREATE TRIGGER trg_ProductionConsumption_DecrementInventory_AI
AFTER INSERT ON ProductionConsumption
FOR EACH ROW
BEGIN
    DECLARE v_new_quantity DECIMAL(12,2);

    -- Check if sufficient quantity exists before decrementing (redundant due to procedure, but safe)
    SELECT quantity - NEW.qty INTO v_new_quantity
    FROM IngredientBatch
    WHERE lot_number = NEW.ingredient_lot;

    IF v_new_quantity < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient inventory detected. Transaction rolled back.';
    END IF;
    
    -- Update the on-hand quantity
    UPDATE IngredientBatch
    SET quantity = quantity - NEW.qty
    WHERE lot_number = NEW.ingredient_lot;
END //
DELIMITER ;

DELIMITER //
CREATE TRIGGER trg_IngredientBatch_IncrementInventory_AI
AFTER INSERT ON IngredientBatch
FOR EACH ROW
BEGIN
    -- Inventory is maintained by the single quantity column in IngredientBatch.
    -- Since the lot is newly inserted, the quantity is simply NEW.quantity.
    -- No complex update is needed here, as the initial insert sets the balance.
    -- This trigger serves as the placeholder for 'Maintain On-Hand' on receipt.
    
    -- NOTE: If the schema tracked total Ingredient inventory separately, the update would go here.
    -- With the current schema, the INSERT itself fulfills the requirement.
END //
DELIMITER ;

DELIMITER //
CREATE TRIGGER trg_IngredientBatch_ShelfLife_BI
BEFORE INSERT ON IngredientBatch
FOR EACH ROW
BEGIN
    -- Set the minimum acceptable expiration date (Today + 90 days)
    DECLARE v_min_expiration_date DATE;
    SET v_min_expiration_date = DATE_ADD(CURDATE(), INTERVAL 90 DAY);

    -- Check if the new expiration date is before the required minimum date
    IF NEW.expiration_date < v_min_expiration_date THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Ingredient lot expiration date is too near (less than 90 days shelf life remaining).';
    END IF;
END //
DELIMITER ;

-- -----------------------------------------------------------------------------------

CREATE VIEW v_ActiveFormulations AS
SELECT 
    IFF.formulation_id,
    IFF.ingredient_id,
    IFF.supplier_id,
    IFF.version_no,
    IFF.price_per_pack
FROM 
    IngredientFormulation IFF
WHERE
    IFF.effective_start <= CURDATE() 
    AND (IFF.effective_end IS NULL OR IFF.effective_end >= CURDATE());
    
CREATE OR REPLACE VIEW v_FlattenedBOM AS
(
    -- 1. Direct ATOMIC Ingredients
    SELECT
        RM.recipe_id,
        RI.ingredient_id AS atomic_ingredient_id,
        I.common_name AS IngredientName,
        RI.qty AS total_contribution_qty
    FROM
        RecipeMaster RM
    JOIN
        RecipeIngredient RI ON RM.recipe_id = RI.recipe_id
    JOIN
        Ingredient I ON RI.ingredient_id = I.ingredient_id
    WHERE
        I.type = 'ATOMIC'

    UNION ALL

    -- 2. Derived ATOMIC Ingredients (from COMPOUND ingredients)
    SELECT
        RM.recipe_id,
        FM.ingredient_id AS atomic_ingredient_id,
        I_Atomic.common_name AS IngredientName,
        -- Calculated Qty: (Recipe Qty of Compound) * (Formulation Qty of Atomic Material)
        RI.qty * FM.qty AS total_contribution_qty
    FROM
        RecipeMaster RM
    JOIN
        RecipeIngredient RI ON RM.recipe_id = RI.recipe_id
    JOIN
        Ingredient I_Compound ON RI.ingredient_id = I_Compound.ingredient_id
    JOIN
        -- Join to find the active formulation for the compound ingredient
        IngredientFormulation IFo ON I_Compound.ingredient_id = IFo.ingredient_id
    JOIN
        -- Join to find the atomic materials in the formulation
        FormulationMaterials FM ON IFo.formulation_id = FM.formulation_id
    JOIN
        Ingredient I_Atomic ON FM.ingredient_id = I_Atomic.ingredient_id
    WHERE
        I_Compound.type = 'COMPOUND'
        -- NOTE: For robust production systems, this should only join to the LATEST active formulation.
);
    
/* Requires a dedicated logging table to store detected conflicts */
CREATE TABLE IF NOT EXISTS BatchConflictLog (
    log_id INT PRIMARY KEY AUTO_INCREMENT,
    log_date DATETIME DEFAULT NOW(),
    product_batch_lot VARCHAR(100),
    ingredient_a INT NOT NULL,
    ingredient_b INT NOT NULL,
    FOREIGN KEY (ingredient_a) REFERENCES Ingredient(ingredient_id),
    FOREIGN KEY (ingredient_b) REFERENCES Ingredient(ingredient_id)
);

CREATE VIEW v_RecentHealthRiskViolations AS
SELECT 
    BCL.log_date,
    BCL.product_batch_lot,
    IA.common_name AS Ingredient1,
    IB.common_name AS Ingredient2
FROM 
    BatchConflictLog BCL
JOIN
    Ingredient IA ON BCL.ingredient_a = IA.ingredient_id
JOIN
    Ingredient IB ON BCL.ingredient_b = IB.ingredient_id
WHERE
    BCL.log_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
ORDER BY
    BCL.log_date DESC;
    
CREATE OR REPLACE VIEW v_ProductCatalog AS
SELECT
    P.product_id,
    P.product_number,
    P.name AS product_name,
    C.name AS category_name,
    M.name AS manufacturer_name
FROM
    Product P
JOIN
    Category C ON P.category_id = C.category_id
JOIN
    ProductManufacturer PM ON P.product_id = PM.product_id
JOIN
    Manufacturer M ON PM.manufacturer_id = M.manufacturer_id
ORDER BY
    P.product_id;
    
-- New View: Calculates unit cost dynamically to satisfy 3NF
CREATE OR REPLACE VIEW v_ProductBatchCost AS
SELECT
    PB.lot_number,
    PB.product_id,
    PB.produced_qty,
    PB.total_cost,
    -- Calculate unit_cost on the fly
    (PB.total_cost / NULLIF(PB.produced_qty, 0)) AS unit_cost, 
    PB.produced_at
FROM
    ProductBatch PB;