CREATE OR REPLACE FUNCTION circ_retention_start_date() RETURNS trigger AS $start_date$

    BEGIN

	IF NEW."name" = 'history.circ.retention_start' THEN


		IF NEW."value" = 'true'
		
		THEN NEW."value" := NOW();


		END IF;


		IF NEW."value" = 'false'

		THEN DELETE FROM actor.usr_setting 
			WHERE id = OLD."id";

			RETURN null;

		END IF;

	END IF;



	RETURN NEW;

    END;

$start_date$ LANGUAGE plpgsql;


CREATE TRIGGER circ_retention_start_date BEFORE INSERT OR UPDATE ON actor.usr_setting
   FOR EACH ROW EXECUTE PROCEDURE circ_retention_start_date();
