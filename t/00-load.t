#!/usr/bin/env perl

use strict;
use warnings;
use Test::More tests => 17;

BEGIN {
    use_ok('Carp');
    use_ok('Class::Data::Accessor');
    use_ok('CPAN::LinksToDocs');
    use_ok('URI');
    use_ok('LWP::UserAgent');
    use_ok('DBI');
    use_ok('DBD::SQLite');
    use_ok('Devel::TakeHashArgs');
    use_ok('CPAN::LinksToDocs::No404s::Remember');
}

diag( "Testing CPAN::LinksToDocs::No404s::Remember $CPAN::LinksToDocs::No404s::Remember::VERSION, Perl $], $^X" );

my $o = CPAN::LinksToDocs::No404s::Remember->new( tags => {foos => 'bars'});
isa_ok($o, 'CPAN::LinksToDocs::No404s::Remember');
can_ok($o, qw(new link_for tags _make_tags _splitty _make_not_found_link
    response
    message_404
    ua
    dbh
));

my $VAR1 = [
          'http://perldoc.perl.org/functions/map.html',
          'http://perldoc.perl.org/functions/grep.html',
          'http://search.cpan.org/perldoc?perlrequick',
          'http://search.cpan.org/perldoc?perlretut',
          'http://search.cpan.org/perldoc?perlre',
          'http://search.cpan.org/perldoc?perlreref',
          'http://search.cpan.org/perldoc?perlboot',
          'http://search.cpan.org/perldoc?perltoot',
          'http://search.cpan.org/perldoc?perltooc',
          'http://search.cpan.org/perldoc?perlbot',
        ];
is_deeply(
    $o->link_for('map,grep,RE,OOP'),
    $VAR1,
    'checks for links'
);

is( $o->tags->{foos}, 'bars', 'custom tags' );
is_deeply( $o->link_for('foos'), ['bars'], 'custom tags with ->link_for()');

my $res = $o->link_for('POE::Component::IRC');

ok( $res !~ /Not found/, 'link_for with present module');

$res = $o->link_for('POEfdfsfsdffsdfdsfsdfsdfsfsfsfsdfsfdgsgsdgsdgsdgdsg')->[0];
like(
    $res,
    qr/^(?:Not found|Network error.+)$/,
    'link_for with non-existant module'
);
$o->message_404('testing THIS');
$res = $o->link_for('POEfdfsfsdffsdfdsfsdfsdfsfsfsfsdfsfdgsgsdgsdgsdgdsg')->[0];

like(
    $res,
    qr/^(?:testing THIS|Network error.+)$/,
    'link_for with non-existant module and custom 404'
);

