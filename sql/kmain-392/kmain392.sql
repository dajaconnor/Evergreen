BEGIN;

 INSERT INTO config.usr_setting_type (name,opac_visible,label,description,datatype)
     VALUES (
         'opac.lists_per_page',
         TRUE,
         oils_i18n_gettext(
             'opac.lists_per_page',
             'Lists per Page',
             'cust',
             'label'
         ),
         oils_i18n_gettext(
             'opac.lists_per_page',
             'A number designating the amount of lists displayed per page.',
             'cust',
             'description'
         ),
         'string'
     );
     
INSERT INTO config.usr_setting_type (name,opac_visible,label,description,datatype)
     VALUES (
         'opac.list_items_per_page',
         TRUE,
         oils_i18n_gettext(
             'opac.list_items_per_page',
             'List Items per Page',
             'cust',
             'label'
         ),
         oils_i18n_gettext(
             'opac.list_items_per_page',
             'A number designating the amount of list items displayed per page of a selected list.',
             'cust',
             'description'
         ),
         'string'
     );
     
COMMIT;
