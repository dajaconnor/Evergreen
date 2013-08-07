--Insert in four more activity types (Payment, Checkin, Checkout, Hold Request).
--Default Activity Types use up the first 24 of the 1000 reserved IDs.
INSERT INTO config.usr_activity_type (ewhat, egroup, label)
VALUES
('payment' ,'circ', 'Payment'),
('checkin' ,'circ', 'Check in'),
('checkout' ,'circ', 'Check out'),
('hold' ,'hold' , 'Hold Request')
;


-- Change constraint to 'cascade' on delete, rather than 'no action'
-- For easier rollback of activities

ALTER TABLE actor.usr_activity
    DROP CONSTRAINT usr_activity_etype_fkey;

ALTER TABLE actor.usr_activity
    ADD CONSTRAINT usr_activity_etype_fkey FOREIGN KEY (etype)
    REFERENCES config.usr_activity_type (id) MATCH SIMPLE
    ON UPDATE NO ACTION ON DELETE CASCADE;

