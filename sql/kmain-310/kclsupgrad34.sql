-- Table: metabib.language_filter

-- DROP TABLE metabib.language_filter;

CREATE TABLE metabib.language_filter
(
  id bigserial NOT NULL,
  source bigint NOT NULL,
  value tsvector,
  CONSTRAINT id PRIMARY KEY (id ),
  CONSTRAINT source FOREIGN KEY (source)
      REFERENCES biblio.record_entry (id) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION
)
WITH (
  OIDS=FALSE
);
ALTER TABLE metabib.language_filter
  OWNER TO evergreen;

-- Function: biblio.extract_languages(bigint)

-- DROP FUNCTION biblio.extract_languages(bigint);

CREATE OR REPLACE FUNCTION biblio.extract_languages(bigint)
  RETURNS tsvector AS
$BODY$

DECLARE
    alt_lang    text;
    lang        text;
    subfields   text;
BEGIN
    lang := biblio.marc21_extract_fixed_field($1, 'Lang');  

--  read MARC 041 subfields from actor.org_unit_setting.opac_additional_language_subfields
--  trim any '"' chars, split into array of subfields   

    SELECT value INTO subfields FROM actor.org_unit_setting where name like 'opac.additional_language_subfields';
--
--  query MARC 041 specified subfields for additional search languages
--
    FOR alt_lang IN (SELECT value FROM biblio.flatten_marc($1) where tag='041' and POSITION(subfield IN subfields) > 0)
    LOOP
        lang := lang || ' ' || alt_lang;
    END LOOP;
    
    return lang::tsvector;
END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
ALTER FUNCTION biblio.extract_languages(bigint)
  OWNER TO evergreen;
  
-- Function: update_language_filter()

-- DROP FUNCTION update_language_filter();

CREATE OR REPLACE FUNCTION biblio.update_language_filter()
  RETURNS trigger AS
$BODY$
DECLARE
    lang    tsvector;
    lang_filter bigint;
BEGIN    
    lang := biblio.extract_languages(NEW.id);   
        
    SELECT metabib.language_filter.source INTO lang_filter FROM metabib.language_filter WHERE NEW.id = metabib.language_filter.source;

    IF FOUND THEN
    UPDATE metabib.language_filter SET value = lang WHERE metabib.language_filter.source = NEW.id;  
    ELSE
    INSERT INTO metabib.language_filter(source, value) VALUES (NEW.id, lang);   
    END IF;

    RETURN NEW;

END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
ALTER FUNCTION biblio.update_language_filter()
  OWNER TO evergreen;

-- Trigger: language_filter_trigger on biblio.record_entry

-- DROP TRIGGER language_filter_trigger ON biblio.record_entry;
  
CREATE TRIGGER language_filter_trigger
  AFTER INSERT OR UPDATE
  ON biblio.record_entry
  FOR EACH ROW
  EXECUTE PROCEDURE biblio.update_language_filter();

--
-- added record in config.org_unit_setting_type is used in proposal/additional_language_search
--
INSERT INTO config.org_unit_setting_type 
    (name, label, grp, description, datatype)
    VALUES (
        'opac.additional_language.subfields',
        'Specify MARC 041 subfields for additional search languages',
        'opac',
        'Specify which MARC 041 subfields should be used when searching for additional languages.',
        'string'
    );

INSERT INTO actor.org_unit_setting
    (org_unit, name, value) VALUES
    (1, 'opac.additional_language.subfields', '"abdefj"'
    );
