-- NOTE: This script assumes the finalized DDL (including RecipeMaster, RecipeIngredient, 
-- and ProductBatch cost fields) has already been executed.

-- 1. Category
INSERT INTO Category (category_id, name) VALUES
(2, 'Dinners'),
(3, 'Sides');

-- 2. Ingredient
INSERT INTO Ingredient (ingredient_id, common_name, type) VALUES
(101, 'Salt', 'ATOMIC'),
(102, 'Pepper', 'ATOMIC'),
(104, 'Sodium Phosphate', 'ATOMIC'),
(106, 'Beef Steak', 'ATOMIC'),
(108, 'Pasta', 'ATOMIC'),
(201, 'Seasoning Blend', 'COMPOUND'),
(301, 'Super Seasoning', 'COMPOUND');

-- 3. Supplier
INSERT INTO Supplier (supplier_id, name) VALUES
(20, 'Jane Doe'),
(21, 'James Miller');

-- 4. Manufacturer
INSERT INTO Manufacturer (manufacturer_id, name) VALUES
(1, 'John Smith'),
(2, 'Alice Lee');

-- 5. User
INSERT INTO User (user_id, first_name, last_name, role_code) VALUES
('MFG001', 'John', 'Smith', 'MANUFACTURER'),
('MFG002', 'Alice', 'Lee', 'MANUFACTURER'),
('SUP020', 'Jane', 'Doe', 'SUPPLIER'),
('SUP021', 'James', 'Miller', 'SUPPLIER'),
('VIEW001', 'Bob', 'Johnson', 'VIEWER');

-- 6. Product
INSERT INTO Product (product_id, product_number, name, category_id, standard_batch_units) VALUES
(100, 'P-100', 'Steak Dinner', 2, 100),
(101, 'P-101', 'Mac & Cheese', 3, 300);

-- 7. ProductManufacturer (Ownership)
INSERT INTO ProductManufacturer (product_id, manufacturer_id) VALUES
(100, 1),
(101, 2);

-- 8. RecipeMaster (NEW: Creating V1 for each product)
-- Note: recipe_id is typically auto-incremented, but explicit values are used here for RecipeIngredient FKs.
INSERT INTO RecipeMaster (recipe_id, product_id, version_no, creation_date) VALUES
(1, 100, 1, '2025-01-01'), -- Steak Dinner V1
(2, 101, 1, '2025-01-01'); -- Mac & Cheese V1

-- 9. RecipeIngredient (Replaced original Recipe table)
INSERT INTO RecipeIngredient (recipe_id, ingredient_id, qty) VALUES
(1, 106, 6.0),  -- Steak Dinner V1: Beef Steak
(1, 201, 0.2),  -- Steak Dinner V1: Seasoning Blend
(2, 108, 7.0),  -- Mac & Cheese V1: Pasta
(2, 101, 0.5),  -- Mac & Cheese V1: Salt
(2, 102, 2.0);  -- Mac & Cheese V1: Pepper

-- 10. IngredientFormulation
INSERT INTO IngredientFormulation (formulation_id, ingredient_id, supplier_id, version_no, effective_start, effective_end, price_per_pack, pack_size) VALUES
(1, 201, 20, 1, '2025-01-01', '2025-06-30', 20.0, 8.0);

-- 11. FormulationMaterials
INSERT INTO FormulationMaterials (formulation_id, ingredient_id, qty) VALUES
(1, 101, 6.0),
(1, 102, 2.0);

-- 12. IngredientBatch (No change, as it fits the DDL)
INSERT INTO IngredientBatch (lot_number, ingredient_id, supplier_id, quantity, unit_cost, expiration_date) VALUES
('101-20-B0001', 101, 20, 1000, 0.1, '2026-11-15'),
('101-21-B0001', 101, 21, 800, 0.08, '2026-10-30'),
('101-20-B0002', 101, 20, 500, 0.1, '2026-11-01'),
('101-20-B0003', 101, 20, 500, 0.1, '2026-12-15'),
('102-20-B0001', 102, 20, 1200, 0.3, '2026-12-15'),
('106-20-B0005', 106, 20, 3000, 0.5, '2026-12-15'),
('106-20-B0006', 106, 20, 600, 0.5, '2026-12-20'),
('108-20-B0001', 108, 20, 1000, 0.25, '2026-09-28'),
('108-20-B0003', 108, 20, 6300, 0.25, '2026-12-31'),
('201-20-B0001', 201, 20, 100, 2.5, '2026-11-30'),
('201-20-B0002', 201, 20, 20, 2.5, '2026-12-30');

-- 13. ProductBatch (UPDATED: Computed cost fields from consumption data)
-- 100-MFG001-B0901 Cost: (600*0.5) + (20*2.5) = 300 + 50 = 350. Unit Cost: 350/100 = 3.50
-- 101-MFG002-B0101 Cost: (150*0.1) + (2100*0.25) + (600*0.3) = 15 + 525 + 180 = 720. Unit Cost: 720/300 = 2.40
INSERT INTO ProductBatch (lot_number, product_id, produced_qty, produced_at, expiration_date, total_cost) VALUES
('100-MFG001-B0901', 100, 100, '2025-09-26', '2025-11-15', 350.00),
('101-MFG002-B0101', 101, 300, '2025-09-10', '2025-10-30', 720.00);

-- 14. ProductionConsumption (No change, as it fits the DDL)
INSERT INTO ProductionConsumption (product_batch_lot, ingredient_lot, qty) VALUES
('100-MFG001-B0901', '106-20-B0006', 600),
('100-MFG001-B0901', '201-20-B0002', 20),
('101-MFG002-B0101', '101-20-B0002', 150),
('101-MFG002-B0101', '108-20-B0003', 2100),
('101-MFG002-B0101', '102-20-B0001', 600);

-- 15. ConflictPairs (No change, as it fits the DDL)
INSERT INTO ConflictPairs (ingredient_a, ingredient_b) VALUES
(201, 104), -- Seasoning Blend (201) cannot combine with Sodium Phosphate (104)
(106, 104); -- Beef Steak (106) cannot combine with Sodium Phosphate (104)

-- 16. SupplierCapability (NEW: Inferred capabilities from existing batches/formulations)
INSERT INTO SupplierCapability (supplier_id, ingredient_id) VALUES
(20, 101), -- Jane Doe supplies Salt
(20, 102), -- Jane Doe supplies Pepper
(20, 106), -- Jane Doe supplies Beef Steak
(20, 108), -- Jane Doe supplies Pasta
(20, 201), -- Jane Doe supplies Seasoning Blend
(21, 101); -- James Miller supplies Salt