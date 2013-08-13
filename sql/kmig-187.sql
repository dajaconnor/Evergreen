CREATE OR REPLACE FUNCTION action.get_hold_queue_status_by_id(INTEGER)
RETURNS TABLE(id INTEGER, cut_in_line BOOLEAN, request_time timestamp with time zone) 
AS $$
WITH holds(holdid) AS 
( SELECT acm.hold FROM action.hold_copy_map acm 
  JOIN action.hold_copy_map acm2 USING(target_copy) 
  WHERE acm2.hold=$1) 
  SELECT id, cut_in_line, request_time FROM action.hold_request 
  WHERE id IN (SELECT holdid FROM holds) 
  ORDER BY coalesce(cut_in_line, false ) DESC, request_time; 
$$ 
LANGUAGE SQL STABLE;
