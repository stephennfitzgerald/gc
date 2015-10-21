/** views **/

CREATE OR REPLACE VIEW SpeciesView AS 
 SELECT CONCAT(sp.name, '::', ass.name)
 FROM species sp INNER JOIN assembly ass
 ON ass.species_id = sp.id; 

CREATE OR REPLACE VIEW FeatureView AS 
 SELECT feature_type
 FROM feature;
