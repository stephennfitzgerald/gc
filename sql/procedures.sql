/** procedures **/

DELIMITER $$
DROP PROCEDURE IF EXISTS GetFeatureProc$$

CREATE PROCEDURE GetFeatureProc (
 IN assembly_name_param varchar(255),
 IN feature_type_param varchar(255)
)

BEGIN
 SELECT ft.feature 
 FROM feature ft
 INNER JOIN assembly ass
 ON ass.id = ft.assembly_id
 WHERE ft.feature_type = feature_type_param
 AND ass.name = assembly_name_param;
END$$
DELIMITER ;

DELIMITER $$
DROP PROCEDURE IF EXISTS CheckFeature$$

CREATE PROCEDURE CheckFeature (
 IN assembly_id_param INT(10),
 IN feature_type_param VARCHAR(255)
)

BEGIN
 SELECT 1 
 FROM feature 
 WHERE assembly_id = assembly_id_param
 AND feature_type = feature_type_param;
END$$
DELIMITER ;

DELIMITER $$
DROP PROCEDURE IF EXISTS DeleteFeature$$

CREATE PROCEDURE DeleteFeature (
 IN feature_id_param INT(10)
)

BEGIN
 DELETE FROM feature 
 WHERE id = feature_id_param;
END$$
DELIMITER ;
