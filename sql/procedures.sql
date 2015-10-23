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
