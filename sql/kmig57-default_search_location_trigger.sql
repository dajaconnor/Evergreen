-- Function: actor.ignore_update_default_search_location()

-- DROP FUNCTION actor.ignore_update_default_search_location();

CREATE OR REPLACE FUNCTION actor.ignore_update_default_search_location()
  RETURNS trigger AS
$BODY$

BEGIN          
   
    IF TG_OP = 'UPDATE' AND new.value NOT ILIKE '"1"' AND new.name ILIKE 'opac.default_search_location' THEN
                SELECT '"1"' INTO new.value FROM actor.usr AS au WHERE au.id = new.usr;
    ELSIF TG_OP = 'INSERT' AND new.value NOT ILIKE '"1"' AND new.name ILIKE 'opac.default_search_location' THEN
                SELECT '"1"' INTO new.value FROM actor.usr AS au WHERE au.id = new.usr;
    END IF;

    RETURN new;

END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 500;
ALTER FUNCTION actor.ignore_update_default_search_location()
  OWNER TO evergreen;


-- Trigger: actor_only_kcls_for_default_search_location on actor.usr_setting

-- DROP TRIGGER actor_only_kcls_for_default_search_location ON actor.usr_setting;

CREATE TRIGGER actor_only_kcls_for_default_search_location
  BEFORE INSERT OR UPDATE
  ON actor.usr_setting
  FOR EACH ROW
  EXECUTE PROCEDURE actor.ignore_update_default_search_location();