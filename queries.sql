-- ============================================================================
-- QUERIES FOR FOOD MANAGEMENT SYSTEM
-- ============================================================================
-- Based on schema in sql_one.sql and data in Data_Insert.sql
-- ============================================================================

-- ============================================================================
-- QUERY 1: List the ingredients and the lot number of the last batch of 
--          product type Steak Dinner (100) made by manufacturer MFG001.
-- ============================================================================

-- Note: Lot numbers use format 'product_id-MFG###-batch_id'
-- MFG001 corresponds to manufacturer_id 1 (John Smith)

SELECT 
    I.ingredient_id,
    I.common_name AS ingredient_name,
    PC.ingredient_lot AS lot_number
FROM ProductionConsumption PC
JOIN IngredientBatch IB ON PC.ingredient_lot = IB.lot_number
JOIN Ingredient I ON IB.ingredient_id = I.ingredient_id
WHERE PC.product_batch_lot = (
    SELECT PB.lot_number
    FROM ProductBatch PB
    WHERE PB.product_id = 100  -- Steak Dinner
      AND PB.lot_number LIKE '100-MFG001-%'  -- Manufacturer MFG001
    ORDER BY PB.produced_at DESC
    LIMIT 1
)
ORDER BY I.ingredient_id;

-- Expected Results:
-- ingredient_id | ingredient_name | lot_number
-- --------------|-----------------|------------
-- 106           | Beef Steak      | 106-20-B0006
-- 201           | Seasoning Blend | 201-20-B0002
--
-- Note: Based on Data_Insert.sql, the last batch is '100-MFG001-B0901' 
--       produced on '2025-09-26', which consumed:
--       - 600 units from '106-20-B0006' (Beef Steak)
--       - 20 units from '201-20-B0002' (Seasoning Blend)


-- ============================================================================
-- QUERY 2: For manufacturer MFG002, list all the suppliers that they have 
--          purchased from and the total amount of money they have spent 
--          with that supplier.
-- ============================================================================

-- Note: MFG002 corresponds to manufacturer_id 2 (Alice Lee)
-- Lot numbers use format 'product_id-MFG###-batch_id'

SELECT 
    S.supplier_id,
    S.name AS supplier_name,
    SUM(PC.qty * IB.unit_cost) AS total_amount_spent
FROM ProductBatch PB
JOIN ProductionConsumption PC ON PB.lot_number = PC.product_batch_lot
JOIN IngredientBatch IB ON PC.ingredient_lot = IB.lot_number
JOIN Supplier S ON IB.supplier_id = S.supplier_id
WHERE PB.lot_number LIKE '%-MFG002-%'  -- Manufacturer MFG002
GROUP BY S.supplier_id, S.name
ORDER BY total_amount_spent DESC;

-- Expected Results:
-- supplier_id | supplier_name | total_amount_spent
-- ------------|---------------|--------------------
-- 20          | Jane Doe      | 720.00
--
-- Note: Based on Data_Insert.sql, MFG002 made batch '101-MFG002-B0101' which consumed:
--       - 150 units from '101-20-B0002' (Salt) at 0.1 per unit = 15.00
--       - 2100 units from '108-20-B0003' (Pasta) at 0.25 per unit = 525.00
--       - 600 units from '102-20-B0001' (Pepper) at 0.3 per unit = 180.00
--       Total = 15 + 525 + 180 = 720.00
--       All from supplier 20 (Jane Doe)


-- ============================================================================
-- QUERY 3: For product with lot number 100-MFG001-B0901, find the unit cost 
--          for that product.
-- ============================================================================

-- Method 1: Using the view (recommended)
SELECT 
    lot_number,
    product_id,
    produced_qty,
    total_cost,
    unit_cost
FROM v_ProductBatchCost
WHERE lot_number = '100-MFG001-B0901';

-- Method 2: Direct calculation
SELECT 
    PB.lot_number,
    PB.product_id,
    PB.produced_qty,
    PB.total_cost,
    (PB.total_cost / PB.produced_qty) AS unit_cost
FROM ProductBatch PB
WHERE PB.lot_number = '100-MFG001-B0901';

-- Expected Results:
-- lot_number         | product_id | produced_qty | total_cost | unit_cost
-- -------------------|------------|--------------|------------|-----------
-- 100-MFG001-B0901   | 100        | 100          | 350.00     | 3.50
--
-- Note: Based on Data_Insert.sql, total_cost = 350.00, produced_qty = 100
--       Unit cost = 350.00 / 100 = 3.50


-- ============================================================================
-- QUERY 4: Based on the ingredients currently in product lot number 
--          100-MFG001-B0901, what are all ingredients that cannot be included 
--          (i.e. that are in conflict with the current ingredient list)
-- ============================================================================

-- First, get all ingredients (both atomic and compound) in the product batch
-- and also expand compound ingredients to their atomic components
WITH BatchIngredients AS (
    -- Get all ingredients (atomic and compound) directly used in the batch
    SELECT DISTINCT IB.ingredient_id
    FROM ProductionConsumption PC
    JOIN IngredientBatch IB ON PC.ingredient_lot = IB.lot_number
    WHERE PC.product_batch_lot = '100-MFG001-B0901'
    
    UNION
    
    -- Get atomic ingredients from compound ingredients (for conflict checking)
    SELECT DISTINCT FM.ingredient_id
    FROM ProductionConsumption PC
    JOIN IngredientBatch IB ON PC.ingredient_lot = IB.lot_number
    JOIN Ingredient I ON IB.ingredient_id = I.ingredient_id
    JOIN IngredientFormulation IFo ON I.ingredient_id = IFo.ingredient_id
    JOIN FormulationMaterials FM ON IFo.formulation_id = FM.formulation_id
    WHERE PC.product_batch_lot = '100-MFG001-B0901'
      AND I.type = 'COMPOUND'
)
-- Find all ingredients that conflict with any ingredient in the batch
SELECT DISTINCT 
    CASE 
        WHEN CP.ingredient_a IN (SELECT ingredient_id FROM BatchIngredients) 
        THEN CP.ingredient_b
        ELSE CP.ingredient_a
    END AS conflicting_ingredient_id,
    I.common_name AS conflicting_ingredient_name
FROM ConflictPairs CP
JOIN Ingredient I ON (
    CASE 
        WHEN CP.ingredient_a IN (SELECT ingredient_id FROM BatchIngredients) 
        THEN CP.ingredient_b
        ELSE CP.ingredient_a
    END = I.ingredient_id
)
WHERE CP.ingredient_a IN (SELECT ingredient_id FROM BatchIngredients)
   OR CP.ingredient_b IN (SELECT ingredient_id FROM BatchIngredients)
ORDER BY conflicting_ingredient_id;

-- Expected Results:
-- conflicting_ingredient_id | conflicting_ingredient_name
-- -------------------------|-----------------------------
-- 104                      | Sodium Phosphate
--
-- Note: Based on Data_Insert.sql:
--       - Batch '100-MFG001-B0901' contains:
--         * Direct: 106 (Beef Steak) and 201 (Seasoning Blend)
--         * From Seasoning Blend (201): 101 (Salt) and 102 (Pepper)
--       - ConflictPairs table has:
--         * (201, 104) - Seasoning Blend conflicts with Sodium Phosphate
--         * (106, 104) - Beef Steak conflicts with Sodium Phosphate
--       - Therefore, ingredient 104 (Sodium Phosphate) cannot be included


-- ============================================================================
-- QUERY 5: Which manufacturers have supplier James Miller (21) NOT supplied to?
-- ============================================================================

-- Note: Lot numbers use format 'product_id-MFG###-batch_id'
-- We need to extract the manufacturer code from the lot number and map it to manufacturer_id

SELECT 
    M.manufacturer_id,
    M.name AS manufacturer_name
FROM Manufacturer M
WHERE M.manufacturer_id NOT IN (
    SELECT DISTINCT PM.manufacturer_id
    FROM ProductBatch PB
    JOIN ProductionConsumption PC ON PB.lot_number = PC.product_batch_lot
    JOIN IngredientBatch IB ON PC.ingredient_lot = IB.lot_number
    JOIN ProductManufacturer PM ON PB.product_id = PM.product_id
    WHERE IB.supplier_id = 21  -- James Miller
)
ORDER BY M.manufacturer_id;

-- Alternative approach: Extract manufacturer code from lot number and match via User table
-- SELECT 
--     M.manufacturer_id,
--     M.name AS manufacturer_name
-- FROM Manufacturer M
-- WHERE NOT EXISTS (
--     SELECT 1
--     FROM ProductBatch PB
--     JOIN ProductionConsumption PC ON PB.lot_number = PC.product_batch_lot
--     JOIN IngredientBatch IB ON PC.ingredient_lot = IB.lot_number
--     JOIN User U ON SUBSTRING_INDEX(SUBSTRING_INDEX(PB.lot_number, '-', 2), '-', -1) = U.user_id
--     WHERE IB.supplier_id = 21  -- James Miller
--       AND U.role_code = 'MANUFACTURER'
--       AND CAST(SUBSTRING(U.user_id, 4) AS UNSIGNED) = M.manufacturer_id
-- )
-- ORDER BY M.manufacturer_id;

-- Expected Results:
-- manufacturer_id | manufacturer_name
-- ----------------|------------------
-- 1               | John Smith
-- 2               | Alice Lee
--
-- Note: Based on Data_Insert.sql:
--       - James Miller (supplier_id 21) only supplied ingredient batch '101-21-B0001' (Salt)
--       - This batch was NOT used in any product batch (no ProductionConsumption record)
--       - Therefore, James Miller has NOT supplied to any manufacturer
--       - Both manufacturers (1 and 2) should be in the result

