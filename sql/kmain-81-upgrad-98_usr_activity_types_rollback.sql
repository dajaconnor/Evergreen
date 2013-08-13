
------- Delete added user activities -------------------------
DELETE FROM  config.usr_activity_type
WHERE ewho IS NULL AND ehow IS NULL AND ewhat = 'payment';
DELETE FROM  config.usr_activity_type
WHERE ewho IS NULL AND ehow IS NULL AND ewhat = 'checkin';
DELETE FROM  config.usr_activity_type
WHERE ewho IS NULL AND ehow IS NULL AND ewhat = 'checkout';
DELETE FROM  config.usr_activity_type
WHERE ewho IS NULL AND ehow IS NULL AND ewhat = 'hold';

-------Revert constraint change------
ALTER TABLE actor.usr_activity
    DROP CONSTRAINT usr_activity_etype_fkey;

ALTER TABLE actor.usr_activity
    ADD CONSTRAINT usr_activity_etype_fkey FOREIGN KEY (etype)
    REFERENCES config.usr_activity_type (id) MATCH SIMPLE
    ON UPDATE NO ACTION ON DELETE NO ACTION;

