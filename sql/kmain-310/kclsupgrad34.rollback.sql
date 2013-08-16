-- Trigger: language_filter_trigger on biblio.record_entry

DROP TRIGGER IF EXISTS language_filter_trigger ON biblio.record_entry;
  
-- Table: metabib.language_filter

DROP TABLE IF EXISTS metabib.language_filter;

-- Function: biblio.extract_languages(bigint)

DROP FUNCTION IF EXISTS biblio.extract_languages(bigint);
  
-- Function: biblio.update_language_filter()

DROP FUNCTION IF EXISTS biblio.update_language_filter();

-- RECORD in config.org_unit_setting_type

DELETE FROM config.org_unit_setting_type_log WHERE field_name = 'opac.additional_language.subfields';
DELETE FROM actor.org_unit_setting WHERE name = 'opac.additional_language.subfields';
DELETE FROM config.org_unit_setting_type_log WHERE field_name = 'opac.additional_language.subfields';
DELETE FROM config.org_unit_setting_type WHERE name = 'opac.additional_language.subfields';
