use strict;
use warnings;

package OpenILS::Application::Storage::Driver::Pg::QueryParser;
use OpenILS::Application::Storage::QueryParser;
use base 'QueryParser';
use OpenSRF::Utils qw/:datetime/;
use OpenSRF::Utils::JSON;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::CStoreEditor;
my $U = 'OpenILS::Application::AppUtils';

my ${spc} = ' ' x 2;
sub subquery_callback {
    my ($invocant, $self, $struct, $filter, $params, $negate) = @_;

    return sprintf(' ((%s)) ',
        join(
            ') || (',
            map {
                $_->query_text
            } @{
                OpenILS::Utils::CStoreEditor
                    ->new
                    ->search_actor_search_query({ id => $params })
            }
        )
    );
}

sub filter_group_entry_callback {
    my ($invocant, $self, $struct, $filter, $params, $negate) = @_;

    return sprintf(' saved_query(%s)', 
        join(
            ',', 
            map {
                $_->query
            } @{
                OpenILS::Utils::CStoreEditor
                    ->new
                    ->search_actor_search_filter_group_entry({ id => $params })
            }
        )
    );
}

sub format_callback {
    my ($invocant, $self, $struct, $filter, $params, $negate) = @_;

    my $return = '';
    my $negate_flag = ($negate ? '-' : '');
    my @returns;
    for my $param (@$params) {
        my ($t,$f) = split('-', $param);
        my $treturn = '';
        $treturn .= 'item_type(' . join(',',split('', $t)) . ')' if ($t);
        $treturn .= ' ' if ($t and $f);
        $treturn .= 'item_form(' . join(',',split('', $f)) . ')' if ($f);
        $treturn = '(' . $treturn . ')' if ($t and $f);
        push(@returns, $treturn) if $treturn;
    }
    $return = join(' || ', @returns);
    $return = '(' . $return . ')' if(@returns > 1);
    $return = $negate_flag.$return if($return);
    return $return;
}

sub quote_value {
    my $self = shift;
    my $value = shift;

    if ($value =~ /^\d/) { # may have to use non-$ quoting
        $value =~ s/'/''/g;
        $value =~ s/\\/\\\\/g;
        return "E'$value'";
    }
    return "\$_$$\$$value\$_$$\$";
}

sub quote_phrase_value {
    my $self = shift;
    my $value = shift;
    my $wb = shift;

    my $left_anchored = '';
    my $right_anchored = '';
    $left_anchored  = $1 if $value =~ m/^([*\^])/;
    $right_anchored = $1 if $value =~ m/([*\$])$/;
    $value =~ s/^[*\^]//   if $left_anchored;
    $value =~ s/[*\$]$//  if $right_anchored;
    $value = '^' . $value if $left_anchored eq '^';
    $value = "$value\$"   if $right_anchored eq '$';
    $value = '[[:<:]]' . $value if $wb && !$left_anchored;
    $value .= '[[:>:]]' if $wb && !$right_anchored;
    return $self->quote_value($value);
}

sub init {
    my $class = shift;
}

sub default_preferred_language {
    my $self = shift;
    my $lang = shift;

    $self->custom_data->{default_preferred_language} = $lang if ($lang);
    return $self->custom_data->{default_preferred_language};
}

sub default_preferred_language_multiplier {
    my $self = shift;
    my $lang = shift;

    $self->custom_data->{default_preferred_language_multiplier} = $lang if ($lang);
    return $self->custom_data->{default_preferred_language_multiplier};
}

sub simple_plan {
    my $self = shift;

    return 0 unless $self->parse_tree;
    return 0 if @{$self->parse_tree->filters};
    return 0 if @{$self->parse_tree->modifiers};
    for my $node ( @{ $self->parse_tree->query_nodes } ) {
        return 0 if (!ref($node) && $node eq '|');
        next unless (ref($node));
        return 0 if ($node->isa('QueryParser::query_plan'));
    }

    return 1;
}

sub toSQL {
    my $self = shift;
    return $self->parse_tree->toSQL;
}

sub dynamic_filters {
    my $self = shift;
    my $new = shift;

    $self->custom_data->{dynamic_filters} ||= [];
    push(@{$self->custom_data->{dynamic_filters}}, $new) if ($new);
    return $self->custom_data->{dynamic_filters};
}

sub dynamic_sorters {
    my $self = shift;
    my $new = shift;

    $self->custom_data->{dynamic_sorters} ||= [];
    push(@{$self->custom_data->{dynamic_sorters}}, $new) if ($new);
    return $self->custom_data->{dynamic_sorters};
}

sub facet_field_id_map {
    my $self = shift;
    my $map = shift;

    $self->custom_data->{facet_field_id_map} ||= {};
    $self->custom_data->{facet_field_id_map} = $map if ($map);
    return $self->custom_data->{facet_field_id_map};
}

sub add_facet_field_id_map {
    my $self = shift;
    my $class = shift;
    my $field = shift;
    my $id = shift;
    my $weight = shift;

    $self->add_facet_field( $class => $field );
    $self->facet_field_id_map->{by_id}{$id} = { classname => $class, field => $field, weight => $weight };
    $self->facet_field_id_map->{by_class}{$class}{$field} = $id;

    return {
        by_id => { $id => { classname => $class, field => $field, weight => $weight } },
        by_class => { $class => { $field => $id } }
    };
}

sub facet_field_class_by_id {
    my $self = shift;
    my $id = shift;

    return $self->facet_field_id_map->{by_id}{$id};
}

sub facet_field_ids_by_class {
    my $self = shift;
    my $class = shift;
    my $field = shift;

    return undef unless ($class);

    if ($field) {
        return [$self->facet_field_id_map->{by_class}{$class}{$field}];
    }

    return [values( %{ $self->facet_field_id_map->{by_class}{$class} } )];
}

sub search_field_id_map {
    my $self = shift;
    my $map = shift;

    $self->custom_data->{search_field_id_map} ||= {};
    $self->custom_data->{search_field_id_map} = $map if ($map);
    return $self->custom_data->{search_field_id_map};
}

sub add_search_field_id_map {
    my $self = shift;
    my $class = shift;
    my $field = shift;
    my $id = shift;
    my $weight = shift;
    my $combined = shift;

    $self->add_search_field( $class => $field );
    $self->search_field_id_map->{by_id}{$id} = { classname => $class, field => $field, weight => $weight };
    $self->search_field_id_map->{by_class}{$class}{$field} = $id;

    return {
        by_id => { $id => { classname => $class, field => $field, weight => $weight } },
        by_class => { $class => { $field => $id } }
    };
}

sub search_field_class_by_id {
    my $self = shift;
    my $id = shift;

    return $self->search_field_id_map->{by_id}{$id};
}

sub search_field_ids_by_class {
    my $self = shift;
    my $class = shift;
    my $field = shift;

    return undef unless ($class);

    if ($field) {
        return [$self->search_field_id_map->{by_class}{$class}{$field}];
    }

    return [values( %{ $self->search_field_id_map->{by_class}{$class} } )];
}

sub relevance_bumps {
    my $self = shift;
    my $bumps = shift;

    $self->custom_data->{rel_bumps} ||= {};
    $self->custom_data->{rel_bumps} = $bumps if ($bumps);
    return $self->custom_data->{rel_bumps};
}

sub find_relevance_bumps {
    my $self = shift;
    my $class = shift;
    my $field = shift;

    return $self->relevance_bumps->{$class}{$field};
}

sub add_relevance_bump {
    my $self = shift;
    my $class = shift;
    my $field = shift;
    my $type = shift;
    my $multiplier = shift;
    my $active = shift;

    if (defined($active) and $active eq 'f') {
        $active = 0;
    } else {
        $active = 1;
    }

    $self->relevance_bumps->{$class}{$field}{$type} = { multiplier => $multiplier, active => $active };

    return { $class => { $field => { $type => { multiplier => $multiplier, active => $active } } } };
}

sub search_class_weights {
    my $self = shift;
    my $class = shift;
    my $a_weight = shift;
    my $b_weight = shift;
    my $c_weight = shift;
    my $d_weight = shift;

    $self->custom_data->{class_weights} ||= {};
    # Note: This reverses the A-D order, putting D first, because that is how the call actually works in PG
    $self->custom_data->{class_weights}->{$class} ||= [0.1, 0.2, 0.4, 1.0];
    $self->custom_data->{class_weights}->{$class} = [$d_weight, $c_weight, $b_weight, $a_weight] if $a_weight;
    return $self->custom_data->{class_weights}->{$class};
}

sub search_class_combined {
    my $self = shift;
    my $class = shift;
    my $c = shift;

    $self->custom_data->{class_combined} ||= {};
    # Note: This reverses the A-D order, putting D first, because that is how the call actually works in PG
    $self->custom_data->{class_combined}->{$class} ||= 0;
    $self->custom_data->{class_combined}->{$class} = 1 if $c && $c =~ /^(?:t|y|1)/i;
    return $self->custom_data->{class_combined}->{$class};
}

sub class_ts_config {
    my $self = shift;
    my $class = shift;
    my $lang = shift || 'DEFAULT';
    my $always = shift;
    my $ts_config = shift;

    $self->custom_data->{class_ts_config} ||= {};
    $self->custom_data->{class_ts_config}->{$class} ||= {};
    $self->custom_data->{class_ts_config}->{$class}->{$lang} ||= {};
    $self->custom_data->{class_ts_config}->{$class}->{$lang}->{normal} ||= [];
    $self->custom_data->{class_ts_config}->{$class}->{$lang}->{always} ||= [];
    $self->custom_data->{class_ts_config}->{$class}->{'DEFAULT'} ||= {};
    $self->custom_data->{class_ts_config}->{$class}->{'DEFAULT'}->{normal} ||= [];
    $self->custom_data->{class_ts_config}->{$class}->{'DEFAULT'}->{always} ||= [];

    if ($ts_config) {
        push @{$self->custom_data->{class_ts_config}->{$class}->{$lang}->{normal}}, $ts_config unless $always;
        push @{$self->custom_data->{class_ts_config}->{$class}->{$lang}->{always}}, $ts_config if $always;
    }

    my $return = [];
    push @$return, @{$self->custom_data->{class_ts_config}->{$class}->{$lang}->{always}};
    push @$return, @{$self->custom_data->{class_ts_config}->{$class}->{$lang}->{normal}} unless $always;
    if($lang ne 'DEFAULT') {
        push @$return, @{$self->custom_data->{class_ts_config}->{$class}->{'DEFAULT'}->{always}};
        push @$return, @{$self->custom_data->{class_ts_config}->{$class}->{'DEFAULT'}->{normal}} unless $always;
    }
    return $return;
}

sub field_ts_config {
    my $self = shift;
    my $class = shift;
    my $field = shift;
    my $lang = shift || 'DEFAULT';
    my $ts_config = shift;

    $self->custom_data->{field_ts_config} ||= {};
    $self->custom_data->{field_ts_config}->{$class} ||= {};
    $self->custom_data->{field_ts_config}->{$class}->{$field} ||= {};
    $self->custom_data->{field_ts_config}->{$class}->{$field}->{$lang} ||= [];
    $self->custom_data->{field_ts_config}->{$class}->{$field}->{'DEFAULT'} ||= [];

    if ($ts_config) {
        push @{$self->custom_data->{field_ts_config}->{$class}->{$field}->{$lang}}, $ts_config;
    }

    my $return = [];
    push @$return, @{$self->custom_data->{field_ts_config}->{$class}->{$field}->{$lang}};
    if($lang ne 'DEFAULT') {
        push @$return, @{$self->custom_data->{field_ts_config}->{$class}->{$field}->{'DEFAULT'}};
    }
    # Make it easy on us: Grab any "always" for the class here. If we have none we grab them all.
    push @$return, @{$self->class_ts_config($class, $lang, scalar(@$return))};
    return $return;
}

sub initialize_search_field_id_map {
    my $self = shift;
    my $cmf_list = shift;

    for my $cmf (@$cmf_list) {
        __PACKAGE__->add_search_field_id_map( $cmf->field_class, $cmf->name, $cmf->id, $cmf->weight ) if ($U->is_true($cmf->search_field));
        __PACKAGE__->add_facet_field_id_map( $cmf->field_class, $cmf->name, $cmf->id, $cmf->weight ) if ($U->is_true($cmf->facet_field));
    }

    return $self->search_field_id_map;
}

sub initialize_aliases {
    my $self = shift;
    my $cmsa_list = shift;

    for my $cmsa (@$cmsa_list) {
        if (!$cmsa->field) {
            __PACKAGE__->add_search_class_alias( $cmsa->field_class, $cmsa->alias );
        } else {
            my $c = $self->search_field_class_by_id( $cmsa->field );
            __PACKAGE__->add_search_field_alias( $cmsa->field_class, $c->{field}, $cmsa->alias );
        }
    }
}

sub initialize_relevance_bumps {
    my $self = shift;
    my $sra_list = shift;

    for my $sra (@$sra_list) {
        my $c = $self->search_field_class_by_id( $sra->field );
        __PACKAGE__->add_relevance_bump( $c->{classname}, $c->{field}, $sra->bump_type, $sra->multiplier, $sra->active );
    }

    return $self->relevance_bumps;
}

sub initialize_query_normalizers {
    my $self = shift;
    my $tree = shift; # open-ils.cstore.direct.config.metabib_field_index_norm_map.search.atomic { "id" : { "!=" : null } }, { "flesh" : 1, "flesh_fields" : { "cmfinm" : ["norm"] }, "order_by" : [{ "class" : "cmfinm", "field" : "pos" }] }

    for my $cmfinm ( @$tree ) {
        my $field_info = $self->search_field_class_by_id( $cmfinm->field );
        next unless $field_info;
        __PACKAGE__->add_query_normalizer( $field_info->{classname}, $field_info->{field}, $cmfinm->norm->func, OpenSRF::Utils::JSON->JSON2perl($cmfinm->params) );
    }
}

sub initialize_dynamic_filters {
    my $self = shift;
    my $list = shift; # open-ils.cstore.direct.config.record_attr_definition.search.atomic { "id" : { "!=" : null } }

    for my $crad ( @$list ) {
        __PACKAGE__->dynamic_filters( __PACKAGE__->add_search_filter( $crad->name ) ) if ($U->is_true($crad->filter));
        __PACKAGE__->dynamic_sorters( $crad->name ) if ($U->is_true($crad->sorter));
    }
}

sub initialize_filter_normalizers {
    my $self = shift;
    my $tree = shift; # open-ils.cstore.direct.config.record_attr_index_norm_map.search.atomic { "id" : { "!=" : null } }, { "flesh" : 1, "flesh_fields" : { "crainm" : ["norm"] }, "order_by" : [{ "class" : "crainm", "field" : "pos" }] }

    for my $crainm ( @$tree ) {
        __PACKAGE__->add_filter_normalizer( $crainm->attr, $crainm->norm->func, OpenSRF::Utils::JSON->JSON2perl($crainm->params) );
    }
}

sub initialize_search_class_weights {
    my $self = shift;
    my $classes = shift;

    for my $search_class (@$classes) {
        __PACKAGE__->search_class_weights( $search_class->name, $search_class->a_weight, $search_class->b_weight, $search_class->c_weight, $search_class->d_weight );
        __PACKAGE__->search_class_combined( $search_class->name, $search_class->combined );
    }
}

sub initialize_class_ts_config {
    my $self = shift;
    my $class_entries = shift;

    for my $search_class_entry (@$class_entries) {
        __PACKAGE__->class_ts_config($search_class_entry->field_class,$search_class_entry->search_lang,$U->is_true($search_class_entry->always),$search_class_entry->ts_config);
    }
}

sub initialize_field_ts_config {
    my $self = shift;
    my $field_entries = shift;
    my $field_objects = shift;
    my %field_hash = map { $_->id => $_ } @$field_objects;

    for my $search_field_entry (@$field_entries) {
        my $field_object = $field_hash{$search_field_entry->metabib_field};
        __PACKAGE__->field_ts_config($field_object->field_class,$field_object->name,$search_field_entry->search_lang,$search_field_entry->ts_config);
    }
}

our $_complete = 0;
sub initialization_complete {
    return $_complete;
}

sub initialize {
    my $self = shift;
    my %args = @_;

    return $_complete if ($_complete);

    # tsearch rank normalization adjustments. see http://www.postgresql.org/docs/9.0/interactive/textsearch-controls.html#TEXTSEARCH-RANKING for details
    $self->custom_data->{rank_cd_weight_map} = {
        CD_logDocumentLength    => 1,
        CD_documentLength       => 2,
        CD_meanHarmonic         => 4,
        CD_uniqueWords          => 8,
        CD_logUniqueWords       => 16,
        CD_selfPlusOne          => 32
    };

    $self->add_search_modifier( $_ ) for (keys %{ $self->custom_data->{rank_cd_weight_map} });

    $self->initialize_search_field_id_map( $args{config_metabib_field} )
        if ($args{config_metabib_field});

    $self->initialize_aliases( $args{config_metabib_search_alias} )
        if ($args{config_metabib_search_alias});

    $self->initialize_relevance_bumps( $args{search_relevance_adjustment} )
        if ($args{search_relevance_adjustment});

    $self->initialize_query_normalizers( $args{config_metabib_field_index_norm_map} )
        if ($args{config_metabib_field_index_norm_map});

    $self->initialize_dynamic_filters( $args{config_record_attr_definition} )
        if ($args{config_record_attr_definition});

    $self->initialize_filter_normalizers( $args{config_record_attr_index_norm_map} )
        if ($args{config_record_attr_index_norm_map});

    $self->initialize_search_class_weights( $args{config_metabib_class} )
        if ($args{config_metabib_class});

    $self->initialize_class_ts_config( $args{config_metabib_class_ts_map} )
        if ($args{config_metabib_class_ts_map});

    $self->initialize_field_ts_config( $args{config_metabib_field_ts_map}, $args{config_metabib_field} )
        if ($args{config_metabib_field_ts_map} && $args{config_metabib_field});

    $_complete = 1 if (
        $args{config_metabib_field_index_norm_map} &&
        $args{search_relevance_adjustment} &&
        $args{config_metabib_search_alias} &&
        $args{config_metabib_field} &&
        $args{config_record_attr_definition}
    );

    return $_complete;
}

sub TEST_SETUP {
    
    __PACKAGE__->allow_nested_modifiers(1);

    __PACKAGE__->add_search_field_id_map( series => seriestitle => 1 => 1 );

    __PACKAGE__->add_search_field_id_map( series => seriestitle => 1 => 1 );
    __PACKAGE__->add_relevance_bump( series => seriestitle => first_word => 1.5 );
    __PACKAGE__->add_relevance_bump( series => seriestitle => full_match => 20 );
    
    __PACKAGE__->add_search_field_id_map( title => abbreviated => 2 => 1 );
    __PACKAGE__->add_relevance_bump( title => abbreviated => first_word => 1.5 );
    __PACKAGE__->add_relevance_bump( title => abbreviated => full_match => 20 );
    
    __PACKAGE__->add_search_field_id_map( title => translated => 3 => 1 );
    __PACKAGE__->add_relevance_bump( title => translated => first_word => 1.5 );
    __PACKAGE__->add_relevance_bump( title => translated => full_match => 20 );
    
    __PACKAGE__->add_search_field_id_map( title => proper => 6 => 1 );
    __PACKAGE__->add_query_normalizer( title => proper => 'search_normalize' );
    __PACKAGE__->add_relevance_bump( title => proper => first_word => 1.5 );
    __PACKAGE__->add_relevance_bump( title => proper => full_match => 20 );
    __PACKAGE__->add_relevance_bump( title => proper => word_order => 10 );
    
    __PACKAGE__->add_search_field_id_map( author => corporate => 7 => 1 );
    __PACKAGE__->add_relevance_bump( author => corporate => first_word => 1.5 );
    __PACKAGE__->add_relevance_bump( author => corporate => full_match => 20 );
    
    __PACKAGE__->add_facet_field_id_map( author => personal => 8 => 1 );

    __PACKAGE__->add_search_field_id_map( author => personal => 8 => 1 );
    __PACKAGE__->add_relevance_bump( author => personal => first_word => 1.5 );
    __PACKAGE__->add_relevance_bump( author => personal => full_match => 20 );
    __PACKAGE__->add_query_normalizer( author => personal => 'search_normalize' );
    __PACKAGE__->add_query_normalizer( author => personal => 'split_date_range' );
    
    __PACKAGE__->add_facet_field_id_map( subject => topic => 14 => 1 );

    __PACKAGE__->add_search_field_id_map( subject => topic => 14 => 1 );
    __PACKAGE__->add_relevance_bump( subject => topic => first_word => 1 );
    __PACKAGE__->add_relevance_bump( subject => topic => full_match => 1 );
    
    __PACKAGE__->add_search_field_id_map( subject => complete => 16 => 1 );
    __PACKAGE__->add_relevance_bump( subject => complete => first_word => 1 );
    __PACKAGE__->add_relevance_bump( subject => complete => full_match => 1 );
    
    __PACKAGE__->add_search_field_id_map( keyword => keyword => 15 => 1 );
    __PACKAGE__->add_relevance_bump( keyword => keyword => first_word => 1 );
    __PACKAGE__->add_relevance_bump( keyword => keyword => full_match => 1 );
    
    __PACKAGE__->class_ts_config( 'series', undef, 1, 'english_nostop' );
    __PACKAGE__->class_ts_config( 'title', undef, 1, 'english_nostop' );
    __PACKAGE__->class_ts_config( 'author', undef, 1, 'english_nostop' );
    __PACKAGE__->class_ts_config( 'subject', undef, 1, 'english_nostop' );
    __PACKAGE__->class_ts_config( 'keyword', undef, 1, 'english_nostop' );
    __PACKAGE__->class_ts_config( 'series', undef, 1, 'simple' );
    __PACKAGE__->class_ts_config( 'title', undef, 1, 'simple' );
    __PACKAGE__->class_ts_config( 'author', undef, 1, 'simple' );
    __PACKAGE__->class_ts_config( 'subject', undef, 1, 'simple' );
    __PACKAGE__->class_ts_config( 'keyword', undef, 1, 'simple' );

    # French! To test language limiters
    __PACKAGE__->class_ts_config( 'series', 'fre', 1, 'french_nostop' );
    __PACKAGE__->class_ts_config( 'title', 'fre', 1, 'french_nostop' );
    __PACKAGE__->class_ts_config( 'author', 'fre', 1, 'french_nostop' );
    __PACKAGE__->class_ts_config( 'subject', 'fre', 1, 'french_nostop' );
    __PACKAGE__->class_ts_config( 'keyword', 'fre', 1, 'french_nostop' );

    # Not a default config by any means, but good for some testing
    __PACKAGE__->field_ts_config( 'author', 'personal', 'eng', 'english' );
    __PACKAGE__->field_ts_config( 'author', 'personal', 'fre', 'french' );
    
    __PACKAGE__->add_search_class_alias( keyword => 'kw' );
    __PACKAGE__->add_search_class_alias( title => 'ti' );
    __PACKAGE__->add_search_class_alias( author => 'au' );
    __PACKAGE__->add_search_class_alias( author => 'name' );
    __PACKAGE__->add_search_class_alias( author => 'dc.contributor' );
    __PACKAGE__->add_search_class_alias( subject => 'su' );
    __PACKAGE__->add_search_class_alias( subject => 'bib.subject(?:Title|Place|Occupation)' );
    __PACKAGE__->add_search_class_alias( series => 'se' );
    __PACKAGE__->add_search_class_alias( keyword => 'dc.identifier' );
    
    __PACKAGE__->add_query_normalizer( author => corporate => 'search_normalize' );
    __PACKAGE__->add_query_normalizer( keyword => keyword => 'search_normalize' );
    
    __PACKAGE__->add_search_field_alias( subject => name => 'bib.subjectName' );
    
}

__PACKAGE__->default_search_class( 'keyword' );

# implements EG-specific stored subqueries
__PACKAGE__->add_search_filter( 'saved_query', sub { return __PACKAGE__->subquery_callback(@_) } );
__PACKAGE__->add_search_filter( 'filter_group_entry', sub { return __PACKAGE__->filter_group_entry_callback(@_) } );

# will be retained simply for back-compat
__PACKAGE__->add_search_filter( 'format', sub { return __PACKAGE__->format_callback(@_) } );

# grumble grumble, special cases against date1 and date2
__PACKAGE__->add_search_filter( 'before' );
__PACKAGE__->add_search_filter( 'after' );
__PACKAGE__->add_search_filter( 'between' );
__PACKAGE__->add_search_filter( 'during' );

# various filters for limiting in various ways
__PACKAGE__->add_search_filter( 'edit_date' );
__PACKAGE__->add_search_filter( 'create_date' );
__PACKAGE__->add_search_filter( 'statuses' );
__PACKAGE__->add_search_filter( 'locations' );
__PACKAGE__->add_search_filter( 'location_groups' );
__PACKAGE__->add_search_filter( 'bib_source' );
__PACKAGE__->add_search_filter( 'site' );
__PACKAGE__->add_search_filter( 'pref_ou' );
__PACKAGE__->add_search_filter( 'lasso' );
__PACKAGE__->add_search_filter( 'my_lasso' );
__PACKAGE__->add_search_filter( 'depth' );
__PACKAGE__->add_search_filter( 'language' );
__PACKAGE__->add_search_filter( 'offset' );
__PACKAGE__->add_search_filter( 'limit' );
__PACKAGE__->add_search_filter( 'check_limit' );
__PACKAGE__->add_search_filter( 'skip_check' );
__PACKAGE__->add_search_filter( 'superpage' );
__PACKAGE__->add_search_filter( 'superpage_size' );
__PACKAGE__->add_search_filter( 'estimation_strategy' );
__PACKAGE__->add_search_modifier( 'available' );
__PACKAGE__->add_search_modifier( 'staff' );
__PACKAGE__->add_search_modifier( 'deleted' );
__PACKAGE__->add_search_modifier( 'lucky' );

# Start from container data (bre, acn, acp): container(bre,bookbag,123,deadb33fdeadb33fdeadb33fdeadb33f)
__PACKAGE__->add_search_filter( 'container' );

# Start from a list of record ids, either bre or metarecords, depending on the #metabib modifier
__PACKAGE__->add_search_filter( 'record_list' );

# used internally, but generally not user-settable
__PACKAGE__->add_search_filter( 'preferred_language' );
__PACKAGE__->add_search_filter( 'preferred_language_weight' );
__PACKAGE__->add_search_filter( 'preferred_language_multiplier' );
__PACKAGE__->add_search_filter( 'core_limit' );

# XXX Valid values to be supplied by SVF
__PACKAGE__->add_search_filter( 'sort' );

# modifies core query, not configurable
__PACKAGE__->add_search_modifier( 'descending' );
__PACKAGE__->add_search_modifier( 'ascending' );
__PACKAGE__->add_search_modifier( 'nullsfirst' );
__PACKAGE__->add_search_modifier( 'nullslast' );
__PACKAGE__->add_search_modifier( 'metarecord' );
__PACKAGE__->add_search_modifier( 'metabib' );


#-------------------------------
package OpenILS::Application::Storage::Driver::Pg::QueryParser::query_plan;
use base 'QueryParser::query_plan';
use OpenSRF::Utils::Logger qw($logger);
use OpenSRF::Utils qw/:datetime/;
use Data::Dumper;
use OpenILS::Application::AppUtils;
my $apputils = "OpenILS::Application::AppUtils";


sub toSQL {
    my $self = shift;

    my %filters;

    for my $f ( qw/preferred_language preferred_language_multiplier preferred_language_weight core_limit check_limit skip_check superpage superpage_size/ ) {
        my $col = $f;
        $col = 'preferred_language_multiplier' if ($f eq 'preferred_language_weight');
        my ($filter) = $self->find_filter($f);
        if ($filter and @{$filter->args}) {
            $filters{$col} = $filter->args->[0];
        }
    }

    $self->QueryParser->superpage($filters{superpage}) if ($filters{superpage});
    $self->QueryParser->superpage_size($filters{superpage_size}) if ($filters{superpage_size});
    $self->QueryParser->core_limit($filters{core_limit}) if ($filters{core_limit});

    $logger->debug("Query plan:\n".Dumper($self));

    my $flat_plan = $self->flatten;


    # generate the relevance ranking
    my $rel = '1'; # Default to something simple in case rank_list is empty.
    if (@{$$flat_plan{rank_list}}) {
        $rel = "AVG(\n"
             . ${spc} x 5 ."("
             . join(")\n" . ${spc} x 5 . "+ (", @{$$flat_plan{rank_list}})
             . ")\n"
             . ${spc} x 4 . ")+1";
    }

    # find any supplied sort option
    my ($sort_filter) = $self->find_filter('sort');
    if ($sort_filter) {
        $sort_filter = $sort_filter->args->[0];
    } else {
        $sort_filter = 'rel';
    }

    if (($filters{preferred_language} || $self->QueryParser->default_preferred_language) && ($filters{preferred_language_multiplier} || $self->QueryParser->default_preferred_language_multiplier)) {
        my $pl = $self->QueryParser->quote_value( $filters{preferred_language} ? $filters{preferred_language} : $self->QueryParser->default_preferred_language );
        my $plw = $filters{preferred_language_multiplier} ? $filters{preferred_language_multiplier} : $self->QueryParser->default_preferred_language_multiplier;
        $rel = "($rel * COALESCE( NULLIF( FIRST(mrd.attrs \@> hstore('item_lang', $pl)), FALSE )::INT * $plw, 1))";
    }
    $rel = "1.0/($rel)::NUMERIC";

    my $mra_join = 'INNER JOIN metabib.record_attr mrd ON m.source = mrd.id';

    my $bre_join = '';
    if ($self->find_modifier('deleted')) {
        $bre_join = 'INNER JOIN biblio.record_entry bre ON m.source = bre.id AND bre.deleted';
        # The above suffices for filters too when the #deleted modifier
        # is in use.
    } elsif ($$flat_plan{uses_bre}) {
        $bre_join = 'INNER JOIN biblio.record_entry bre ON m.source = bre.id';
    }
    my $mlf_join = '';
    if ($$flat_plan{uses_mlf}) {
        $mlf_join = 'JOIN metabib.language_filter AS mlf ON m.source = mlf.source';
    }
    
    my $rank = $rel;

    my $desc = 'ASC';
    $desc = 'DESC' if ($self->find_modifier('descending'));

    my $nullpos = 'NULLS LAST';
    $nullpos = 'NULLS FIRST' if ($self->find_modifier('nullsfirst'));

    if (grep {$_ eq $sort_filter} @{$self->QueryParser->dynamic_sorters}) {
        $rank = "FIRST(mrd.attrs->'$sort_filter')"
    } elsif ($sort_filter eq 'create_date') {
        $rank = "FIRST((SELECT create_date FROM biblio.record_entry rbr WHERE rbr.id = m.source))";
    } elsif ($sort_filter eq 'edit_date') {
        $rank = "FIRST((SELECT edit_date FROM biblio.record_entry rbr WHERE rbr.id = m.source))";
    } else {
        # default to rel ranking
        $rank = $rel;
    }

    my $key = 'm.source';
    $key = 'm.metarecord' if (grep {$_->name eq 'metarecord' or $_->name eq 'metabib'} @{$self->modifiers});

    my $core_limit = $self->QueryParser->core_limit || 25000;
    $core_limit = 1 if($self->find_modifier('lucky'));

    my $flat_where = $$flat_plan{where};
    if ($flat_where ne '') {
        $flat_where = "AND (\n" . ${spc} x 5 . $flat_where . "\n" . ${spc} x 4 . ")";
    }
    my $with = $$flat_plan{with};
    $with= "\nWITH $with" if $with;

    # Need an array for query parser db function; this gives a better plan
    # than the ARRAY_AGG(DISTINCT m.source) option as of PostgreSQL 9.1
    my $agg_records = 'ARRAY[m.source] AS records';
    if ($key =~ /metarecord/) {
        # metarecord searches still require the ARRAY_AGG approach
        $agg_records = 'ARRAY_AGG(DISTINCT m.source) AS records';
    }

    my $sql = <<SQL;
$with
SELECT  $key AS id,
        $agg_records,
        $rel AS rel,
        $rank AS rank, 
        FIRST(mrd.attrs->'date1') AS tie_break
  FROM  metabib.metarecord_source_map m
        $$flat_plan{from}
        $mra_join
        $bre_join
        $mlf_join
  WHERE 1=1
        $flat_where
  GROUP BY 1
  ORDER BY 4 $desc $nullpos, 5 DESC $nullpos, 3 DESC
  LIMIT $core_limit
SQL

open SQLTXT, ">", "/tmp/sql.txt";
print SQLTXT $sql;
close SQLTXT;

    warn $sql if $self->QueryParser->debug;
    return $sql;

}

sub flatten {
    my $self = shift;

    my $from = shift || '';
    my $where = shift || '';
    my $with = '';
    my $uses_bre = 0;
    my $uses_mlf = 0;

    my @rank_list;
    for my $node ( @{$self->query_nodes} ) {

        if (ref($node)) {
            if ($node->isa( 'QueryParser::query_plan::node' )) {

                unless (@{$node->only_atoms}) {
                    push @rank_list, '1';
                    $where .= 'TRUE';
                    next;
                }

                my $table = $node->table;
                my $ctable = $node->combined_table;
                my $talias = $node->table_alias;

                my $node_rank = 'COALESCE(' . $node->rank . " * ${talias}.weight, 0.0)";

                $from .= "\n" . ${spc} x 4 ."LEFT JOIN (\n"
                      . ${spc} x 5 . "SELECT fe.*, fe_weight.weight, ${talias}_xq.tsq, ${talias}_xq.tsq_rank /* search */\n"
                      . ${spc} x 6 . "FROM  $table AS fe";
                $from .= "\n" . ${spc} x 7 . "JOIN config.metabib_field AS fe_weight ON (fe_weight.id = fe.field)";

                my @bump_fields;
                my @field_ids;
                if (@{$node->fields} > 0) {
                    @bump_fields = @{$node->fields};

                    @field_ids = grep defined, (
                        map {
                            $self->QueryParser->search_field_ids_by_class(
                                $node->classname, $_
                            )->[0]
                        } @bump_fields
                    );
                } else {
                    @bump_fields = @{$self->QueryParser->search_fields->{$node->classname}};
                }

                if ($node->dummy_count < @{$node->only_atoms} ) {
                    $with .= ",\n     " if $with;
                    $with .= "${talias}_xq AS (SELECT ". $node->tsquery ." AS tsq,". $node->tsquery_rank ." AS tsq_rank )";
                    if ($node->combined_search) {
                        $from .= "\n" . ${spc} x 6 . "JOIN $ctable AS com ON (com.record = fe.source";
                        if (@field_ids) {
                            $from .= " AND com.metabib_field IN (" . join(',',@field_ids) . "))";
                        } else {
                            $from .= " AND com.metabib_field IS NULL)";
                        }
                        $from .= "\n" . ${spc} x 6 . "JOIN ${talias}_xq ON (com.index_vector @@ ${talias}_xq.tsq)";
                    } else {
                        $from .= "\n" . ${spc} x 6 . "JOIN ${talias}_xq ON (fe.index_vector @@ ${talias}_xq.tsq)";
                    }
                } else {
                    $from .= "\n" . ${spc} x 6 . ", (SELECT NULL::tsquery AS tsq, NULL:tsquery AS tsq_rank ) AS ${talias}_xq";
                }

                if (@field_ids) {
                    $from .= "\n" . ${spc} x 6 . "WHERE fe_weight.id IN  (" .
                        join(',', @field_ids) . ")";
                }

                $from .= "\n" . ${spc} x 4 . ") AS $talias ON (m.source = ${talias}.source)";

                my %used_bumps;
                my @bumps;
                my @bumpmults;
                for my $field ( @bump_fields ) {
                    my $bumps = $self->QueryParser->find_relevance_bumps( $node->classname => $field );
                    for my $b (keys %$bumps) {
                        next if (!$$bumps{$b}{active});
                        next if ($used_bumps{$b});
                        $used_bumps{$b} = 1;

                        next if ($$bumps{$b}{multiplier} == 1); # optimization to remove unneeded bumps
                        push @bumps, $b;
                        push @bumpmults, $$bumps{$b}{multiplier};
                    }
                }

                if(scalar @bumps > 0 && scalar @{$node->only_positive_atoms} > 0) {
                    # Note: Previous rank function used search_normalize outright. Duplicating that here.
                    $node_rank .= "\n" . ${spc} x 5 . "* evergreen.rel_bump(('{' || quote_literal(search_normalize(";
                    $node_rank .= join(")) || ',' || quote_literal(search_normalize(",map { $self->QueryParser->quote_phrase_value($_->content) } @{$node->only_positive_atoms});
                    $node_rank .= ")) || '}')::TEXT[], " . $node->table_alias . ".value, '{" . join(",",@bumps) . "}'::TEXT[], '{" . join(",",@bumpmults) . "}'::NUMERIC[])";
                }

                my $NOT = '';
                $NOT = 'NOT ' if $node->negate;

                $where .= "$NOT(" . $talias . ".id IS NOT NULL";
                if (@{$node->phrases}) {
                    $where .= ' AND ' . join(' AND ', map {
                        "${talias}.value ~* xml_encode_special_chars(search_normalize(".$self->QueryParser->quote_phrase_value($_, 1)."))"
                    } @{$node->phrases});
                } elsif (((@{$node->only_real_atoms}[0])->{content}) =~ /^\^/) { # matches exactly
                    $where .= " AND ${talias}.value ilike xml_encode_special_chars(search_normalize(";
                    my $phrase_list;
                    for my $atom (@{$node->only_real_atoms}) {
#                       my $content = $atom->{content};
                        my $content = ref($atom) ? $atom->{content} : $atom;
                        $content =~ s/^\^//;
                        $content =~ s/\$$//;
                        $phrase_list .= "$content ";
#                       next unless $atom->{content} && $atom->{content} =~ /(^\^|\$$)/;
#                       $where .= " AND ${talias}.value ~* search_normalize(".$self->QueryParser->quote_phrase_value($atom->{content}).")";
                    }
                    $where .= $self->QueryParser->quote_phrase_value($phrase_list).'))';
                }
                $where .= ')';

                push @rank_list, $node_rank;

            } elsif ($node->isa( 'QueryParser::query_plan::facet' )) {

                my $talias = $node->table_alias;

                my @field_ids;
                if (@{$node->fields} > 0) {
                    push(@field_ids, $self->QueryParser->facet_field_ids_by_class( $node->classname, $_ )->[0]) for (@{$node->fields});
                } else {
                    @field_ids = @{ $self->QueryParser->facet_field_ids_by_class( $node->classname ) };
                }

                my $join_type = ($node->negate or !$self->top_plan) ? 'LEFT' : 'INNER';
                $from .= "\n${spc}$join_type JOIN /* facet */ metabib.facet_entry $talias ON (\n"
                      . ${spc} x 2 . "m.source = ${talias}.source\n"
                      . ${spc} x 2 . "AND SUBSTRING(${talias}.value,1,1024) IN ("
                      . join(",", map { $self->QueryParser->quote_value($_) } @{$node->values}) . ")\n"
                      . ${spc} x 2 ."AND ${talias}.field IN (". join(',', @field_ids) . ")\n"
                      . "${spc})";

                if ($join_type ne 'INNER') {
                    my $NOT = $node->negate ? '' : ' NOT';
                    $where .= "${talias}.id IS$NOT NULL";
                } elsif ($where ne '') {
                    # Strip extra joiner
                    $where =~ s/(\s|\n)+(AND|OR)\s$//;
                }

            } else {
                my $subnode = $node->flatten;

                # strip the trailing bool from the previous loop if there is 
                # nothing to add to the where within this loop.
                if ($$subnode{where} eq '') {
                    $where =~ s/(\s|\n)+(AND|OR)\s$//;
                }

                push(@rank_list, @{$$subnode{rank_list}});
                $from .= $$subnode{from};

                my $NOT = '';
                $NOT = 'NOT ' if $node->negate;

                if ($$subnode{where} ne '') {
                    $where .= "$NOT(\n"
                           . ${spc} x ($self->plan_level + 6) . $$subnode{where} . "\n"
                           . ${spc} x ($self->plan_level + 5) . ')';
                }

                if ($$subnode{with}) {
                    $with .= ",\n     " if $with;
                    $with .= $$subnode{with};
                }

                $uses_bre = $$subnode{uses_bre};
                $uses_mlf = $$subnode{uses_mlf};
            }
        } else {

            warn "flatten(): appending WHERE bool to: $where\n" if $self->QueryParser->debug;

            if ($where ne '') {
                $where .= "\n" . ${spc} x ( $self->plan_level + 5 ) . 'AND ' if ($node eq '&');
                $where .= "\n" . ${spc} x ( $self->plan_level + 5 ) . 'OR ' if ($node eq '|');
            }
        }
    }

    my $joiner = "\n" . ${spc} x ( $self->plan_level + 5 ) . ($self->joiner eq '&' ? 'AND ' : 'OR ');
    # for each dynamic filter, build more of the WHERE clause

    for my $filter (@{$self->filters}) {
        my $NOT = $filter->negate ? 'NOT ' : '';
        if (grep { $_ eq $filter->name } @{ $self->QueryParser->dynamic_filters }) {

            warn "flatten(): processing dynamic filter ". $filter->name ."\n"
                if $self->QueryParser->debug;

            # bool joiner for intra-plan nodes/filters
            $where .= $joiner if $where ne '';

            my @fargs = @{$filter->args};
            my $fname = $filter->name;
            $fname = 'item_lang' if $fname eq 'language'; #XXX filter aliases 
            if ($fname eq 'item_lang')
            {
                $where .= "$NOT( " . 'mlf.value @@ ' . "\'" . join('|', @fargs) . '\'::tsquery)';
                $uses_mlf = 1;
            } else {
                $where .= sprintf(
                    "${NOT}COALESCE((mrd.attrs->'%s') IN (%s), false)", $fname, 
                    join(',', map { $self->QueryParser->quote_value($_) } @fargs));
            }

            warn "flatten(): filter where => $where\n"
                if $self->QueryParser->debug;
        } else {
            if ($filter->name eq 'before') {
                if (@{$filter->args} == 1) {
                    $where .= $joiner if $where ne '';
                    $where .= "${NOT}COALESCE((mrd.attrs->'date1') <= "
                           . $self->QueryParser->quote_value($filter->args->[0])
                           . ", false)";
                }
            } elsif ($filter->name eq 'after') {
                if (@{$filter->args} == 1) {
                    $where .= $joiner if $where ne '';
                    $where .= "${NOT}COALESCE((mrd.attrs->'date1') >= "
                           . $self->QueryParser->quote_value($filter->args->[0])
                           . ", false)";
                }
            } elsif ($filter->name eq 'during') {
                if (@{$filter->args} == 1) {
                    $where .= $joiner if $where ne '';
                    $where .= "${NOT}COALESCE("
                           . $self->QueryParser->quote_value($filter->args->[0])
                           . " BETWEEN (mrd.attrs->'date1') AND (mrd.attrs->'date2'), false)";
                }
            } elsif ($filter->name eq 'between') {
                if (@{$filter->args} == 2) {
                    $where .= $joiner if $where ne '';
                    $where .= "${NOT}COALESCE((mrd.attrs->'date1') BETWEEN "
                           . $self->QueryParser->quote_value($filter->args->[0])
                           . " AND "
                           . $self->QueryParser->quote_value($filter->args->[1])
                           . ", false)";
                }
            } elsif ($filter->name eq 'container') {
                if (@{$filter->args} >= 3) {
                    my ($class, $ctype, $cid, $token) = @{$filter->args};
                    my $perm_join = '';
                    my $rec_join = '';
                    my $rec_field = 'ci.target_biblio_record_entry';
                    if ($class eq 'bre') {
                        $class = 'biblio_record_entry';
                    } elsif ($class eq 'acn') {
                        $class = 'call_number';
                        $rec_field = 'cn.record';
                        $rec_join = 'JOIN asset.call_number cn ON (ci.target_call_number = cn.id)';
                    } elsif ($class eq 'acp') {
                        $class = 'copy';
                        $rec_field = 'cn.record';
                        $rec_join = 'JOIN asset.copy cp ON (ci.target_copy = cp.id) JOIN asset.call_number cn ON (cp.call_number = cn.id)';
                    } else {
                        $class = undef;
                    }

                    if ($class) {
                        my ($u,$e) = $apputils->checksesperm($token) if ($token);
                        $perm_join = ' OR c.owner = ' . $u->id if ($u && !$e);

                        my $filter_alias = "$filter";
                        $filter_alias =~ s/^.*\(0(x[0-9a-fA-F]+)\)$/$1/go;
                        $filter_alias =~ s/\|/_/go;

                        $with .= ",\n     " if $with;
                        $with .= "container_${filter_alias} AS (\n";
                        $with .= "       SELECT $rec_field AS record FROM container.${class}_bucket_item ci\n"
                               . "             JOIN container.${class}_bucket c ON (c.id = ci.bucket) $rec_join\n"
                               . "       WHERE c.btype = " . $self->QueryParser->quote_value($ctype) . "\n"
                               . "             AND c.id = " . $self->QueryParser->quote_value($cid) . "\n"
                               . "             AND (c.pub IS TRUE$perm_join)\n";
                        if ($class eq 'copy') {
                            $with .= "       UNION\n"
                                   . "       SELECT pr.peer_record AS record FROM container.copy_bucket_item ci\n"
                                   . "             JOIN container.copy_bucket c ON (c.id = ci.bucket)\n"
                                   . "             JOIN biblio.peer_bib_copy_map pr ON ci.target_copy = pr.target_copy\n"
                                   . "       WHERE c.btype = " . $self->QueryParser->quote_value($ctype) . "\n"
                                   . "             AND c.id = " . $self->QueryParser->quote_value($cid) . "\n"
                                   . "             AND (c.pub IS TRUE$perm_join)\n";
                        }
                        $with .= "     )";

                        $from .= "\n" . ${spc} x 3 . "LEFT JOIN container_${filter_alias} ON container_${filter_alias}.record = m.source";

                        my $spcdepth = $self->plan_level + 5;

                        $where .= $joiner if $where ne '';
                        $where .= "${NOT}(container_${filter_alias} IS NOT NULL)";
                    }
                }
            } elsif ($filter->name eq 'record_list') {
                if (@{$filter->args} > 0) {
                    my $key = 'm.source';
                    $key = 'm.metarecord' if (grep {$_->name eq 'metarecord' or $_->name eq 'metabib'} @{$self->QueryParser->parse_tree->modifiers});
                    $where .= $joiner if $where ne '';
                    $where .= "$key ${NOT}IN (" . join(',', map { $self->QueryParser->quote_value($_) } @{$filter->args}) . ')';
                }

            } elsif ($filter->name eq 'edit_date' or $filter->name eq 'create_date') {
                # bre.create_date and bre.edit_date filtering
                my $datefilter = $filter->name;

                $uses_bre = 1;

                if ($filter && $filter->args && scalar(@{$filter->args}) > 0 && scalar(@{$filter->args}) < 3) {
                    my ($cstart, $cend) = @{$filter->args};
        
                    if (!$cstart and !$cend) {
                        # useless use of filter
                    } elsif (!$cstart or $cstart eq '-infinity') { # no start supplied
                        if ($cend eq 'infinity') {
                            # useless use of filter
                        } else {
                            # "before $cend"
                            $cend = cleanse_ISO8601($cend);
                            $where .= $joiner if $where ne '';
                            $where .= "bre.$datefilter <= \$_$$\$$cend\$_$$\$";
                        }
            
                    } elsif (!$cend or $cend eq 'infinity') { # no end supplied
                        if ($cstart eq '-infinity') {
                            # useless use of filter
                        } else { # "after $cstart"
                            $cstart = cleanse_ISO8601($cstart);
                            $where .= $joiner if $where ne '';
                            $where .= "bre.$datefilter >= \$_$$\$$cstart\$_$$\$";
                        }
                    } else { # both supplied
                        # "between $cstart and $cend"
                        $cstart = cleanse_ISO8601($cstart);
                        $cend = cleanse_ISO8601($cend);
                        $where .= $joiner if $where ne '';
                        $where .= "bre.$datefilter BETWEEN \$_$$\$$cstart\$_$$\$ AND \$_$$\$$cend\$_$$\$";
                    }
                }
            } elsif ($filter->name eq 'bib_source') {
                $uses_bre = 1;

                if (@{$filter->args} > 0) {
                    $where .= $joiner if $where ne '';
                    $where .= "${NOT}COALESCE(bre.source IN ("
                           . join(',', map { $self->QueryParser->quote_value($_) } @{ $filter->args })
                           . "), false)";
                }
            }
        }
    }
    warn "flatten(): full filter where => $where\n" if $self->QueryParser->debug;

    return { rank_list => \@rank_list, from => $from, where => $where,  with => $with, uses_bre => $uses_bre, uses_mlf => $uses_mlf};
}


#-------------------------------
package OpenILS::Application::Storage::Driver::Pg::QueryParser::query_plan::filter;
use base 'QueryParser::query_plan::filter';

#-------------------------------
package OpenILS::Application::Storage::Driver::Pg::QueryParser::query_plan::facet;
use base 'QueryParser::query_plan::facet';

sub classname {
    my $self = shift;
    my ($classname) = split '\|', $self->name;
    return $classname;
}

sub fields {
    my $self = shift;
    my ($classname,@fields) = split '\|', $self->name;
    return \@fields;
}

sub table_alias {
    my $self = shift;

    my $table_alias = "$self";
    $table_alias =~ s/^.*\(0(x[0-9a-fA-F]+)\)$/$1/go;
    $table_alias .= '_' . $self->name;
    $table_alias =~ s/\|/_/go;

    return $table_alias;
}


#-------------------------------
package OpenILS::Application::Storage::Driver::Pg::QueryParser::query_plan::modifier;
use base 'QueryParser::query_plan::modifier';

#-------------------------------
package OpenILS::Application::Storage::Driver::Pg::QueryParser::query_plan::node::atom;
use base 'QueryParser::query_plan::node::atom';

sub sql {
    my $self = shift;
    my $sql = shift;

    $self->{sql} = $sql if ($sql);

    return $self->{sql} if ($self->{sql});
    return $self->buildSQL;
}

sub buildSQL {
    my $self = shift;

    my $classname = $self->node->classname;

    return $self->sql("to_tsquery('$classname','')") if $self->{dummy};

    my $normalizers = $self->node->plan->QueryParser->query_normalizers( $classname );
    my $fields = $self->node->fields;

    my $lang;
    my $filter = $self->node->plan->find_filter('preferred_language');
    $lang ||= $filter->args->[0] if ($filter && $filter->args);
    $lang ||= $self->node->plan->QueryParser->default_preferred_language;
    my $ts_configs = [];

    if (@{$self->node->phrases}) {
        # We assume we want 'simple' for phrases. Gives us less to match against later.
        $ts_configs = ['simple'];
    } else {
        if (!@$fields) {
            $ts_configs = $self->node->plan->QueryParser->class_ts_config($classname, $lang);
        } else {
            for my $field (@$fields) {
                push @$ts_configs, @{$self->node->plan->QueryParser->field_ts_config($classname, $field, $lang)};
            }
        }
        $ts_configs = [keys %{{map { $_ => 1 } @$ts_configs}}];
    }

    # Assume we want exact if none otherwise provided.
    # Because we can reasonably expect this to exist
    $ts_configs = ['simple'] unless (scalar @$ts_configs);

    $fields = $self->node->plan->QueryParser->search_fields->{$classname} if (!@$fields);

    my %norms;
    my $pos = 0;
    for my $field (@$fields) {
        for my $nfield (keys %$normalizers) {
            for my $nizer ( @{$$normalizers{$nfield}} ) {
                if ($field eq $nfield) {
                    my $param_string = OpenSRF::Utils::JSON->perl2JSON($nizer->{params});
                    if (!exists($norms{$nizer->{function}.$param_string})) {
                        $norms{$nizer->{function}.$param_string} = {p=>$pos++,n=>$nizer};
                    }
                }
            }
        }
    }

    my $sql = $self->node->plan->QueryParser->quote_value($self->content);

    for my $n ( map { $$_{n} } sort { $$a{p} <=> $$b{p} } values %norms ) {
        $sql = join(', ', $sql, map { $self->node->plan->QueryParser->quote_value($_) } @{ $n->{params} });
        $sql = $n->{function}."($sql)";
    }

    my $prefix = $self->prefix || '';
    my $suffix = $self->suffix || '';
    my $joiner = ' || ';
    $joiner = ' && ' if $self->prefix eq '!'; # Negative atoms should be "none of the variants" instead of "any of the variants"

    $prefix = "'$prefix' ||" if $prefix;
    my $suffix_op = '';
    my $suffix_after = '';

    $suffix_op = ":$suffix" if $suffix;
    $suffix_after = "|| '$suffix_op'" if $suffix;

    my @sql_set = ();
    for my $ts_config (@$ts_configs) {
        push @sql_set, "to_tsquery('$ts_config', COALESCE(NULLIF($prefix '(' || btrim(regexp_replace($sql,E'(?:\\\\s+|:)','$suffix_op&','g'),'&|') $suffix_after || ')', '()'), ''))";
    }

    $sql = join($joiner, @sql_set);
    $sql = '(' . $sql . ')' if (scalar(@$ts_configs) > 1);

    return $self->sql($sql);
}

#-------------------------------
package OpenILS::Application::Storage::Driver::Pg::QueryParser::query_plan::node;
use OpenILS::Application::Storage::QueryParser;
use base 'QueryParser::query_plan::node';
use OpenSRF::Utils::Logger qw($logger);
use Data::Dumper;

sub only_atoms {
    my $self = shift;

    $self->{dummy_count} = 0;

    my $atoms = $self->query_atoms;
    my @only_atoms;
    for my $a (@$atoms) {
        push(@only_atoms, $a) if (ref($a) && $a->isa('QueryParser::query_plan::node::atom'));
        $self->{dummy_count}++ if (ref($a) && $a->{dummy});
    }

    return \@only_atoms;
}

sub only_real_atoms {
    my $self = shift;

    my $atoms = $self->query_atoms;
    my @only_real_atoms;
    for my $a (@$atoms) {
        push(@only_real_atoms, $a) if ((ref($a) && $a->isa('QueryParser::query_plan::node::atom') && !($a->{dummy})) ||
                                        $self->plan->QueryParser->query =~ '^.*&.*$');
    }
    return \@only_real_atoms;
}

sub only_positive_atoms {
    my $self = shift;

    my $atoms = $self->query_atoms;
    my @only_positive_atoms;
    for my $a (@$atoms) {
        push(@only_positive_atoms, $a) if (ref($a) && $a->isa('QueryParser::query_plan::node::atom') && !($a->{dummy}) && ($a->{prefix} ne '!'));
    }

    return \@only_positive_atoms;
}

sub dummy_count {
    my $self = shift;
    return $self->{dummy_count};
}

sub table {
    my $self = shift;
    my $table = shift;
    $self->{table} = $table if ($table);
    return $self->{table} if $self->{table};
    return $self->table( 'metabib.' . $self->classname . '_field_entry' );
}

sub combined_table {
    my $self = shift;
    my $ctable = shift;
    $self->{ctable} = $ctable if ($ctable);
    return $self->{ctable} if $self->{ctable};
    return $self->combined_table( 'metabib.combined_' . $self->classname . '_field_entry' );
}

sub combined_search {
    my $self = shift;
    return $self->plan->QueryParser->search_class_combined($self->classname);
}

sub table_alias {
    my $self = shift;
    my $table_alias = shift;
    $self->{table_alias} = $table_alias if ($table_alias);
    return $self->{table_alias} if ($self->{table_alias});

    $table_alias = "$self";
    $table_alias =~ s/^.*\(0(x[0-9a-fA-F]+)\)$/$1/go;
    $table_alias .= '_' . $self->requested_class;
    $table_alias =~ s/\|/_/go;

    return $self->table_alias( $table_alias );
}

sub tsquery {
    my $self = shift;
    return $self->{tsquery} if ($self->{tsquery});

    for my $atom (@{$self->query_atoms}) {
        if (ref($atom)) {
            $self->{tsquery} .= "\n" . ${spc} x 3 . $atom->sql;
        } else {
            $self->{tsquery} .= $atom x 2;
        }
    }

    return $self->{tsquery};
}

sub tsquery_rank {
    my $self = shift;
    return $self->{tsquery_rank} if ($self->{tsquery_rank});
    my @atomlines;

    for my $atom (@{$self->only_positive_atoms}) {
        push @atomlines, "\n" . ${spc} x 3 . $atom->sql;
    }
    $self->{tsquery_rank} = join(' ||', @atomlines);
    $self->{tsquery_rank} = 'NULL::tsquery' unless $self->{tsquery_rank};
    return $self->{tsquery_rank};
}

sub rank {
    my $self = shift;
    return $self->{rank} if ($self->{rank});

    my $rank_norm_map = $self->plan->QueryParser->custom_data->{rank_cd_weight_map};

    my $cover_density = 0;
    for my $norm ( keys %$rank_norm_map) {
        $cover_density += $$rank_norm_map{$norm} if ($self->plan->find_modifier($norm));
    }

    my $weights = join(', ', @{$self->plan->QueryParser->search_class_weights($self->classname)});

    return $self->{rank} = "ts_rank_cd('{" . $weights . "}', " . $self->table_alias . '.index_vector, ' . $self->table_alias . ".tsq_rank, $cover_density)";
}


1;

