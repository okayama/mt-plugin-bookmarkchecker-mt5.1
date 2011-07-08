package MT::Plugin::BookMarkChecker;
use strict;
use MT;
use MT::Plugin;
use base qw( MT::Plugin );
@MT::Plugin::BookMarkChecker::ISA = qw( MT::Plugin );

use MT::Util qw( encode_url );

use Digest::MD5 qw( md5_hex );
use JSON;

our $VERSION = '0.2';

my $plugin = __PACKAGE__->new( {
    id => 'BookMarkChecker',
    key => 'bookmarkchecker',
    name => 'BookMarkChecker',
    author_name => 'okayama', 
    author_link => 'http://weeeblog.net/',
    description => '<MT_TRANS phrase=\'_PLUGIN_DESCRIPTION\'>',
    version => $VERSION,
    l10n_class => 'BookMarkChecker::L10N',
    settings => new MT::PluginSettings( [
        [ 'check_delicious', { Default => 1 } ],
        [ 'check_hatena', { Default => 1 } ],
        [ 'check_livedoor', { Default => 1 } ],
        [ 'check_yahoo', { Default => 1 } ],
        [ 'check_buzzurl', { Default => 1 } ],
        [ 'check_delicious_at_listing', { Default => 0 } ],
        [ 'check_hatena_at_listing', { Default => 1 } ],
        [ 'check_livedoor_at_listing', { Default => 1 } ],
        [ 'check_yahoo_at_listing', { Default => 1 } ],
        [ 'check_buzzurl_at_listing', { Default => 1 } ],
    ] ),
    blog_config_template => 'bookmarkchecker_config.tmpl',
} );
MT->add_plugin( $plugin );

sub init_registry {
    my $plugin = shift;
    $plugin->registry( {
        callbacks => {
            'MT::App::CMS::template_param.edit_entry'
                => \&_cb_tp_edit_entry,
            'MT::App::CMS::template_param.edit_template'
                => \&_cb_tp_edit_template,
        },
        list_properties => {        
            entry => {
                bookmark => {
                    label => 'BookMarks',
                    order => 207,
                    html => sub { _html_bookmark( @_ ) },
                },
            },
            page => {
                bookmark => {
                    label => 'BookMarks',
                    order => 207,
                    html => sub { _html_bookmark( @_ ) },
                },
            },
        },
    } );
}

sub _html_bookmark {
    my ( $prop, $obj, $app ) = @_;
    my $blog_id = $obj->blog_id;
    my $permalink = $obj->permalink;
$permalink =~ s/plus\-mt5\.1\.//;
    return _build_innerHTML( $blog_id, $permalink, $obj->id, { screen => 'listing' } );
}

sub _cb_tp_edit_template {
    my ( $cb, $app, $param, $tmpl ) = @_;
    my $tmpl_id = $app->param( 'id' );
    my $blog_id = $app->param( 'blog_id' );
    my $tmpl_obj = MT::Template->load( $tmpl_id );
    if ( $tmpl_obj && $tmpl_obj->type eq 'index' && $blog_id ) {
        my $outfile = $tmpl_obj->outfile;
        my $blog = MT::Blog->load( $blog_id );
        my $site_url = $blog->site_url;
        my $permalink = $site_url . $outfile;
$permalink =~ s/plus\-mt5\.1\.//;
        if ( my $innerHTML = _build_innerHTML( $blog_id, $permalink ) ) {
            $innerHTML = '<ul>' . $innerHTML . ' </ul>';
            my $widget = $tmpl->createElement( 'app:widget', { id => 'bookmarks-widget',
                                                               label => $plugin->translate( 'BookMarks' ),
                                                               required => 0,
                                                             }
                                             );
            $widget->innerHTML( $innerHTML );
            my $pointer = $tmpl->getElementById( 'useful-links' );
            $tmpl->insertAfter( $widget, $pointer );
        }
    }
}

sub _cb_tp_edit_entry {
    my ( $cb, $app, $param, $tmpl ) = @_;
    my $entry_id = $app->param( 'id' );
    my $entry = MT::Entry->load( $entry_id );
    if ( $entry_id ) {
        # create elements
        my $blog_id = $entry->blog_id;
        my $permalink = $entry->permalink;
$permalink =~ s/plus\-mt5\.1\.//;
        my $innerHTML;
        if ( my $innerHTML = _build_innerHTML( $blog_id, $permalink ) ) {
            $innerHTML = '<ul>' . $innerHTML . ' </ul>';
            my $widget = $tmpl->createElement( 'app:widget', { id => 'bookmarks-widget',
                                                               label => $plugin->translate( 'BookMarks' ),
                                                               required => 0,
                                                             }
                                             );
            $widget->innerHTML( $innerHTML );
            my $pointer = $tmpl->getElementById( 'entry-publishing-widget' );
            $tmpl->insertBefore( $widget, $pointer );
        }
    }
}

sub _build_innerHTML {
    my ( $blog_id, $permalink, $object_id, $options ) = @_;
    return unless $blog_id;
    return unless $permalink;
    my $screen = $options ? $options->{ screen } : 'edit';
    my $innerHTML;
    if ( $plugin->get_config_value( $screen eq 'listing' ? 'check_delicious_at_listing' : 'check_delicious', 'blog:' . $blog_id ) ) {
        $innerHTML .= _delicious_tmpl( $permalink, $object_id );
    }
    if ( $plugin->get_config_value( $screen eq 'listing' ? 'check_hatena_at_listing' : 'check_hatena', 'blog:' . $blog_id ) ) {
        $innerHTML .= _hatena_tmpl( $permalink );
    }
    if ( $plugin->get_config_value( $screen eq 'listing' ? 'check_yahoo_at_listing' : 'check_yahoo', 'blog:' . $blog_id ) ) {
        $innerHTML .= _yahoo_tmpl( $permalink );
    }
    if ( $plugin->get_config_value( $screen eq 'listing' ? 'check_buzzurl_at_listing' : 'check_buzzurl', 'blog:' . $blog_id ) ) {
        $innerHTML .= _buzzurl_tmpl( $permalink );
    }
    if ( $plugin->get_config_value( $screen eq 'listing' ? 'check_livedoor_at_listing' : 'check_livedoor', 'blog:' . $blog_id ) ) {
        $innerHTML .= _livedoor_tmpl( $permalink );
    }
    return $innerHTML;
}

sub _delicious_tmpl {
    my ( $url, $object_id ) = @_;
    my $label = $plugin->translate( 'del.icio.us' );
    my $url_hash = md5_hex( $url );

    my $url = 'http://badges.del.icio.us/feeds/json/url/data?hash=' . $url_hash;
    my $ua = MT->new_ua or return;
    my $request = new HTTP::Request( GET => $url );
    my $res = $ua->request( $request );
    my $count = 0;
    if ( $res->is_success() ) {
        if ( my $content = $res->content() ) {
            my $json = JSON->new->utf8( 0 );
            my $result = $json->decode( $content );
            $count = $$result[ 0 ]->{ total_posts };
        }
    }
    return '<li><a href="http://del.icio.us/url/' . $url_hash . '" target="_blank" class="icon-left icon-related">' . $label . ': ' . $count . '</a></li>';
}

#     return<<TMPL;
# <li id="delicious_$object_id"></li>
# <script type="text/javascript">
# function getDeliciousNum_$object_id( data ) {
#     var totalPosts;
#     var target;
#     totalPosts = data[0] ? data[0].total_posts: 0;
#     target = document.getElementById( 'delicious_$object_id' );
#     target.innerHTML = '<a href="http://del.icio.us/url/$url_hash" target="_blank" class="icon-left icon-related">$label: ' + totalPosts + '</a>';
# }
# </script>
# <script src="http://badges.del.icio.us/feeds/json/url/data?hash=$url_hash&callback=getDeliciousNum_$object_id"></script>
# TMPL

# sub _delicious_tmpl {
#     my ( $url, $entry_id ) = @_;
#     my $label = $plugin->translate( 'del.icio.us' );
#     my $pointer_id = $entry_id ? 'delicious_' . $entry_id : 'delicious';
#     my $url_hash = md5_hex( $url );
#     return<<TMPL;
# <li id="delicious"><a href="http://del.icio.us/url/$url_hash" target="_blank" class="icon-left icon-related">$label: <img src="http://del.icio.us/feeds/img/savedcount/$url_hash?aggregate" /></a></li>
# TMPL
# } 


sub _hatena_tmpl {
    my ( $url ) = @_;
    my $label = $plugin->translate( 'Hatena' );
    return<<TMPL;
<li><a href="http://b.hatena.ne.jp/entry/$url" target="_blank" class="icon-left icon-related">$label: <img src="http://b.hatena.ne.jp/entry/image/$url" /></a></li>
TMPL
}

sub _livedoor_tmpl {
    my ( $url ) = @_;
    my $label = $plugin->translate( 'Livedoor' );
    return<<TMPL;
<li><a hrf="http://clip.livedoor.com/page/$url" class="icon-left icon-related">$label: <img src="http://image.clip.livedoor.com/counter/$url"></a></li>
TMPL
}

sub _yahoo_tmpl {
    my ( $url ) = @_;
    my $label = $plugin->translate( 'Yahoo!' );
    my $url_encoded = encode_url( $url );
    return<<TMPL;
<li><a href="http://bookmarks.yahoo.co.jp/url?url=$url_encoded" target="_blank" class="icon-left icon-related">$label: <img src="http://num.bookmarks.yahoo.co.jp/ybmimage.php?disptype=small&url=$url_encoded" /></a></li>
TMPL
}

sub _buzzurl_tmpl {
    my ( $url ) = @_;
    my $label = $plugin->translate( 'Buzzurl' );
    my $url_encoded = encode_url( $url );
    return<<TMPL;
<li><a href="http://buzzurl.jp/entry/$url" target="_blank" class="icon-left icon-related">$label: <img src="http://api.buzzurl.jp/api/counter/v1/image?url=$url_encoded" /></a></li>
TMPL
}

1;
