package OpenILS::WWW::EGCatLoader;
use strict; use warnings;
use Apache2::Const -compile => qw(OK DECLINED FORBIDDEN HTTP_INTERNAL_SERVER_ERROR REDIRECT HTTP_BAD_REQUEST);
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::AppUtils;
my $U = 'OpenILS::Application::AppUtils';

# Retrieve the users cached records AKA 'My List'
# Returns an empty list if there are no cached records
sub fetch_mylist {
    my ($self, $with_marc_xml) = @_;

    my $list = [];
    my $cache_key = $self->cgi->cookie((ref $self)->COOKIE_ANON_CACHE);

    if($cache_key) {

        $list = $U->simplereq(
            'open-ils.actor',
            'open-ils.actor.anon_cache.get_value', 
            $cache_key, (ref $self)->ANON_CACHE_MYLIST);

        if(!$list) {
            $cache_key = undef;
            $list = [];
        }
    }

    {   # sanitize
        no warnings qw/numeric/;
        $list = [map { int $_ } @$list];
        $list = [grep { $_ > 0} @$list];
    };

    my $marc_xml;
    if ($with_marc_xml) {
        my $ctx = $self->ctx;

        # capture pref_ou for callnumber filter/display
        $ctx->{pref_ou} = $self->_get_pref_lib() || $ctx->{search_ou};

        # search for local callnumbers for display
        my $focus_ou = $ctx->{physical_loc} || $ctx->{pref_ou};

        my (undef, @recs) = $self->get_records_and_facets(
            $list, undef, {
                flesh => '{mra,holdings_xml,acp,exclude_invisible_acn}',
                flesh_depth => 1,
                site => $ctx->{get_aou}->($focus_ou)->shortname,
                pref_lib => $ctx->{pref_ou}
            }
        );

        # make it look like the caller is expecting
        $marc_xml = { map {$_->{id} => $_->{marc_xml}} @recs };

    }

    # Leverage QueryParser to sort the items by values of config.metabib_fields
    # from the items' marc records.
    if (@$list) {
        my ($sorter, $modifier) = $self->_get_bookbag_sort_params("anonsort");
        my $query = $self->_prepare_anonlist_sorting_query($list, $sorter, $modifier);
        my $args = {
            "limit" => 1000,
            "offset" => 0
        };
        $list = $U->bib_record_list_via_search($query, $args) or
            return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR;
    }

    return ($cache_key, $list, $marc_xml);
}


# Adds a record (by id) to My List, creating a new anon cache + list if necessary.
sub load_mylist_add {
    my $self = shift;
    my $rec_id = $self->cgi->param('record');

    my ($cache_key, $list) = $self->fetch_mylist;
    push(@$list, $rec_id);

    $cache_key = $U->simplereq(
        'open-ils.actor',
        'open-ils.actor.anon_cache.set_value', 
        $cache_key, (ref $self)->ANON_CACHE_MYLIST, $list);

    # Check if we need to warn patron about adding to a "temporary"
    # list:
    if ($self->check_for_temp_list_warning) {
        return $self->mylist_warning_redirect($cache_key);
    }

    return $self->mylist_action_redirect($cache_key);
}

sub load_mylist_delete {
    my $self = shift;
    my $rec_id = $self->cgi->param('record');

    my ($cache_key, $list) = $self->fetch_mylist;
    $list = [ grep { $_ ne $rec_id } @$list ];

    $cache_key = $U->simplereq(
        'open-ils.actor',
        'open-ils.actor.anon_cache.set_value', 
        $cache_key, (ref $self)->ANON_CACHE_MYLIST, $list);

    return $self->mylist_action_redirect($cache_key);
}

sub load_mylist_move {
    my $self = shift;
    my @rec_ids = $self->cgi->param('record');
    my $action = $self->cgi->param('action') || '';

    return $self->load_myopac_bookbag_update('place_hold', undef, @rec_ids)
        if $action eq 'place_hold';

    my ($cache_key, $list) = $self->fetch_mylist;
    return $self->mylist_action_redirect unless $cache_key;

    my @keep;
    foreach my $id (@$list) { push(@keep, $id) unless grep { $id eq $_ } @rec_ids; }

    $cache_key = $U->simplereq(
        'open-ils.actor',
        'open-ils.actor.anon_cache.set_value', 
        $cache_key, (ref $self)->ANON_CACHE_MYLIST, \@keep
    );

    if ($self->ctx->{user} and $action =~ /^\d+$/) {
        # in this case, action becomes list_id
        $self->load_myopac_bookbag_update('add_rec', $self->cgi->param('action'));
        # XXX TODO: test for failure of above
    }

    return $self->mylist_action_redirect($cache_key);
}

sub load_cache_clear {
    my $self = shift;
    $self->clear_anon_cache;
    return $self->mylist_action_redirect;
}

# Wipes the entire anonymous cache, including My List
sub clear_anon_cache {
    my $self = shift;
    my $field = shift;

    my $cache_key = $self->cgi->cookie((ref $self)->COOKIE_ANON_CACHE) or return;

    $U->simplereq(
        'open-ils.actor',
        'open-ils.actor.anon_cache.delete_session', $cache_key)
        if $cache_key;

}

# Called after an anon-cache / My List action occurs.  Redirect
# to the redirect_url (cgi param) or referrer or home.
sub mylist_action_redirect {
    my $self = shift;
    my $cache_key = shift;

    my $url;
    if( my $anchor = $self->cgi->param('anchor') ) {
        # on the results page, we want to redirect 
        # back to record that was affected
        $url = $self->ctx->{referer};
        $url =~ s/#.*|$/#$anchor/;
    } 

    return $self->generic_redirect(
        $url,
        $self->cgi->cookie(
            -name => (ref $self)->COOKIE_ANON_CACHE,
            -path => '/',
            -value => ($cache_key) ? $cache_key : '',
            -expires => ($cache_key) ? undef : '-1h'
        )
    );
}

# called after an anon-cache / my list addition when we are configured
# to show a warning to the user.

sub mylist_warning_redirect {
    my $self = shift;
    my $cache_key = shift;

    my $base_url = sprintf(
        "%s://%s%s/temp_warn",
        $self->ctx->{proto},
        $self->ctx->{hostname},
        $self->ctx->{opac_root}
    );

    my $redirect = $self->ctx->{referer};
    if (my $anchor = $self->cgi->param('anchor')) {
        $redirect =~ s/#.*|$/#$anchor/;
    }

    $base_url .= '?redirect_to=' . uri_escape($redirect);

    return $self->generic_redirect(
        $base_url,
        $self->cgi->cookie(
            -name => (ref $self)->COOKIE_ANON_CACHE,
            -path => '/',
            -value => ($cache_key) ? $cache_key : '',
            -expires => ($cache_key) ? undef : '-1h'
        )
    );
}

sub load_mylist {
    my ($self) = shift;
    (undef, $self->ctx->{mylist}, $self->ctx->{mylist_marc_xml}) =
        $self->fetch_mylist(1);

    return Apache2::Const::OK;
}

sub load_temp_warn_post {
    my $self = shift;
    my $url = $self->cgi->param('redirect_to');
    return $self->generic_redirect(
        $url,
        $self->cgi->cookie(
            -name => 'no_temp_list_warn',
            -path => '/',
            -value => ($self->cgi->param('no_temp_list_warn')) ? '1' : '',
            -expires => ($self->cgi->param('no_temp_list_warn')) ? undef : '-1h'
        )
    );
}

sub load_temp_warn {
    my $self = shift;
    $self->ctx->{'redirect_to'} = $self->cgi->param('redirect_to');
    return Apache2::Const::OK;
}

1;
