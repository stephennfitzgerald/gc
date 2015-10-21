CREATE TABLE IF NOT EXISTS species (
 id                 INT(10) NOT NULL AUTO_INCREMENT,
 name               VARCHAR(255) NOT NULL,
 binomial_name      VARCHAR(255) NOT NULL,
 taxon_id           INT(10) NOT NULL,

 PRIMARY            KEY(id)

) COLLATE=latin1_swedish_ci ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS assembly (
 id                INT(10) NOT NULL AUTO_INCREMENT,
 name              VARCHAR(255) NOT NULL,
 species_id        INT(10) NOT NULL,

 PRIMARY           KEY(id),
 UNIQUE            KEY(name),
 FOREIGN           KEY(species_id) REFERENCES species(id)

) COLLATE=latin1_swedish_ci ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS feature (
 id                INT(10) NOT NULL AUTO_INCREMENT,
 assembly_id       INT(10) NOT NULL,
 feature_type      VARCHAR(255) NOT NULL,
 feature           LONGBLOB NOT NULL,

 PRIMARY           KEY(id),
 FOREIGN           KEY(assembly_id) REFERENCES assembly(id),
 UNIQUE            KEY(assembly_id, feature_type)

) COLLATE=latin1_swedish_ci ENGINE=InnoDB;
