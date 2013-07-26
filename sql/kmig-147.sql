UPDATE config.coded_value_map SET value = 'Software' WHERE id = 24;

UPDATE config.i18n_core set string = 'Multimedia' WHERE (string = 'Software' AND fq_field = 'acpl.name');
