DROP FUNCTION IF EXISTS asset.get_holdings_maintenance_page(bigint);

DROP TYPE IF EXISTS holdings_maintenance;

CREATE TYPE holdings_maintenance AS (acn_create_date timestamp with time zone, acn_creator bigint, acn_deleted boolean, acn_edit_date timestamp with time zone, acn_editor bigint,
acn_id bigint, label text, acn_owning_lib integer, label_sortkey text, label_class bigint, prefix integer, suffix integer, age_protect integer, alert_message text, barcode text, call_numer bigint, 
circ_as_type text, circ_lib integer, circ_modifier text, circulate boolean, copy_number integer, 
create_date timestamp with time zone, active_date timestamp with time zone, creator bigint, deleted boolean, dummy_isbn text, 
deposit boolean, deposit_amount numeric(6,2), dummy_author text, dummy_title text, edit_date timestamp with time zone, 
editor bigint, fine_level integer, holdable boolean, id bigint, load_duration integer, location integer, 
opac_visible boolean, price numeric(8,2), ref boolean, status integer, status_changed_time timestamp with time zone, 
mint_condition boolean, floating boolean, cost numeric(8,2), checkin_lib integer, checkin_staff integer, 
checkin_time timestamp with time zone, circ_circ_lib integer, circ_staff integer, desk_renewal boolean, due_date timestamp with time zone, 
duration interval, duration_rule text, fine_interval interval, circ_id bigint, max_fine numeric(6,2), 
max_fine_rule text, opac_renewal boolean, phone_renewal boolean, recurring_fine numeric(6,2), 
recurring_fine_rule text, renewal_remaining integer, grace_period interval, stop_fines text, stop_fines_time timestamp with time zone, 
target_copy bigint, usr integer, xact_finish timestamp with time zone, xact_start timestamp with time zone, create_time timestamp with time zone, workstation integer, 
checkin_workstation integer, checkin_scan_time timestamp with time zone, parent_circ bigint, unrecovered boolean, copy_location integer);

CREATE OR REPLACE FUNCTION asset.get_holdings_maintenance_page(tcn_value bigint)
RETURNS SETOF holdings_maintenance AS
$BODY$

DECLARE
   r holdings_maintenance;
   
BEGIN

FOR r IN

SELECT acn.create_date, acn.creator, acn.deleted, acn.edit_date, acn.editor, acn.id, acn.label, acn.owning_lib, acn.label_sortkey, acn.label_class, acn.prefix, acn.suffix, acp.age_protect, acp.alert_message, acp.barcode, acp.call_number, acp.circ_as_type, acp.circ_lib, acp.circ_modifier, acp.circulate, acp.copy_number, acp.create_date, acp.active_date, acp.creator, acp.deleted, acp.dummy_isbn, acp.deposit, acp.deposit_amount, acp.dummy_author, acp.dummy_title, acp.edit_date, acp.editor, acp.fine_level, acp.holdable, acp.id, acp.loan_duration, acp.LOCATION, acp.opac_visible, acp.price, acp.REF, acp.STATUS, acp.status_changed_time, acp.mint_condition, acp.floating, acp.COST, circ.checkin_lib, circ.checkin_staff, circ.checkin_time, circ.circ_lib, circ.circ_staff, circ.desk_renewal, circ.due_date, circ.duration, circ.duration_rule, circ.fine_interval, circ.id, circ.max_fine, circ.max_fine_rule, circ.opac_renewal, circ.phone_renewal, circ.recurring_fine, circ.recurring_fine_rule, circ.renewal_remaining, circ.grace_period, circ.stop_fines, circ.stop_fines_time, circ.target_copy, circ.usr, circ.xact_finish, circ.xact_start, circ.create_time, circ.workstation, circ.checkin_workstation, circ.checkin_scan_time, circ.parent_circ, circ.unrecovered, circ.copy_location

	FROM asset.COPY AS acp 

	JOIN asset.call_number acn ON (acp.call_number = acn.id)
	JOIN actor.org_unit aou ON (acn.owning_lib = aou.id)
	JOIN action.circulation circ ON (acp.id = circ.target_copy)


	WHERE acn.record = tcn_value 
		AND circ.xact_start = (
			SELECT c.xact 
			FROM ( 
				SELECT target_copy, max(xact_start) AS xact 
				FROM action.circulation 
				WHERE target_copy = acp.id  
				GROUP BY target_copy) AS c)
		AND aou.parent_ou = '1' 
		AND acn.deleted = 'f' 
		AND acn.LABEL <> '##URI##'
		AND acp.deleted = 'f'

UNION

SELECT acn.create_date, acn.creator, acn.deleted, acn.edit_date, acn.editor, acn.id, acn.label, acn.owning_lib, acn.label_sortkey, acn.label_class, acn.prefix, acn.suffix, acp.age_protect, acp.alert_message, acp.barcode, acp.call_number, acp.circ_as_type, acp.circ_lib, acp.circ_modifier, acp.circulate, acp.copy_number, acp.create_date, acp.active_date, acp.creator, acp.deleted, acp.dummy_isbn, acp.deposit, acp.deposit_amount, acp.dummy_author, acp.dummy_title, acp.edit_date, acp.editor, acp.fine_level, acp.holdable, acp.id, acp.loan_duration, acp.LOCATION, acp.opac_visible, acp.price, acp.REF, acp.STATUS, acp.status_changed_time, acp.mint_condition, acp.floating, acp.COST, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null

	FROM asset.COPY AS acp 

	JOIN asset.call_number acn ON (acp.call_number = acn.id)
	JOIN actor.org_unit aou ON (acn.owning_lib = aou.id)


	WHERE acn.record = tcn_value 
		AND acp.id NOT IN (SELECT circ.target_copy
			FROM action.circulation circ
			WHERE circ.target_copy = acp.id)
		AND aou.parent_ou = '1' 
		AND acn.deleted = 'f' 
		AND acn.LABEL <> '##URI##'
		AND acp.deleted = 'f'




LOOP
RETURN NEXT r;
END LOOP;

RETURN;

END;
$BODY$
LANGUAGE 'plpgsql' IMMUTABLE
