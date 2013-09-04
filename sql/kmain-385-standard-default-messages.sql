--KCM-16 Rollback
-----------------------------------
--DROP TABLE config.patron_message;

BEGIN;

CREATE TABLE config.patron_message
(
    id serial NOT NULL,
    message text NOT NULL,
    weight integer DEFAULT 0,
    CONSTRAINT patron_message_pkey PRIMARY KEY (id)
)
WITH (
    OIDS=FALSE
);

INSERT INTO config.patron_message(message, weight)
    VALUES ('Address verifying documentation needed – Limit 2', 0);
INSERT INTO config.patron_message(message, weight)
    VALUES ('Annual address verifying documentation next needed:', 0);
INSERT INTO config.patron_message(message, weight)
    VALUES ('Banned from computer use until:', 0);
INSERT INTO config.patron_message(message, weight)
    VALUES ('Card lost/stolen/left. Require photo ID.', 0);
INSERT INTO config.patron_message(message, weight)
    VALUES ('Foreign-exchange student', 0);
INSERT INTO config.patron_message(message, weight)
    VALUES ('Items missing from holds shelf. Review CKO with patron.', 0);
INSERT INTO config.patron_message(message, weight)
    VALUES ('Limited Checkout due to:', 0);
INSERT INTO config.patron_message(message, weight)
    VALUES ('No Laptop CKO:', 0);
INSERT INTO config.patron_message(message, weight)
    VALUES ('Patron has protected address', 0);
INSERT INTO config.patron_message(message, weight)
    VALUES ('Patron knows one card per year. Card issue date:', 0);
INSERT INTO config.patron_message(message, weight)
    VALUES ('Photo ID required for CKO', 0);
INSERT INTO config.patron_message(message, weight)
    VALUES ('Seattle to King County verifying documentation needed', 0);
INSERT INTO config.patron_message(message, weight)
    VALUES ('Shelf check done:', 0);
INSERT INTO config.patron_message(message, weight)
    VALUES ('Visiting missionary', 0);
INSERT INTO config.patron_message(message, weight)
    VALUES ('Per Unique new Seattle address needed', 1);
INSERT INTO config.patron_message(message, weight)
    VALUES ('Address check needed – verbal approval okay', 2);

ALTER TABLE config.patron_message
    OWNER TO evergreen;

COMMIT;