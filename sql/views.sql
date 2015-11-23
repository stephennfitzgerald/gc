/** views **/

CREATE OR REPLACE VIEW SpeciesView AS 
 SELECT CONCAT(sp.name, '::', ass.name), ass.id
 FROM species sp INNER JOIN assembly ass
 ON ass.species_id = sp.id; 

CREATE OR REPLACE VIEW FeatureView AS 
 SELECT DISTINCT(feature_type)
 FROM feature
 ORDER BY id DESC;
 
CREATE OR REPLACE VIEW SpeciesFeatureView AS
 SELECT feat.id, CONCAT(sp.name, '::', feat.feature_type)
 FROM feature feat INNER JOIN assembly ass
 ON ass.id = feat.assembly_id INNER JOIN species sp
 ON sp.id = ass.species_id;
