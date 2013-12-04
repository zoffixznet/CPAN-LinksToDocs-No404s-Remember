package CPAN::LinksToDocs::No404s::Remember;

use warnings;
use strict;

our $VERSION = '0.002';

use base qw(Class::Data::Accessor  CPAN::LinksToDocs);
use Carp;
use URI;
use LWP::UserAgent;
use Devel::TakeHashArgs;
use DBI;

__PACKAGE__->mk_classaccessors qw(
    response
    message_404
    ua
    dbh
);

sub new {
    my $self = bless {}, shift;

    get_args_as_hash(\@_,\my %args, {
            timeout => 30,
            db_file => 'cpan_links_to_docs.db',
        }
    ) or croak $@;

    my $do_create_db = not -e $args{db_file};

    my $dbh = DBI->connect(
        "dbi:SQLite:dbname=$args{db_file}",'','',
         { RaiseError => 1, AutoCommit => 1 },
    );

    $do_create_db
        and $dbh->do('CREATE TABLE links (link TEXT)');

    $self->dbh( $dbh );

    my %tags = $self->_make_tags();
    $tags{$_} = $args{tags}{$_}
        for keys %{ $args{tags} || {} };

    unless ( exists $args{ua} ) {
        $args{ua} = LWP::UserAgent->new(
            timeout => $args{timeout},
            agent   => 'Mozilla/5.0 (X11; U; Linux x86_64; en-US;'
                        . ' rv:1.8.1.12) Gecko/20080207 Ubuntu/7.10 (gutsy)'
                        . ' Firefox/2.0.0.12',
        );
    }

    $args{message_404} = 'Not found'
        unless exists $args{message_404};

    $self->$_( $args{$_} ) for qw(ua message_404);
    $self->tags( \%tags );

    return $self;
}

sub _save_uri {
    my ( $self, $uri ) = @_;
    $self->dbh->do('DELETE FROM links WHERE link == ?', undef, $uri);
    $self->dbh->do('INSERT INTO links VALUES(?)', undef, $uri);

    return "$uri";
}

sub _is_saved_uri {
    my ( $self, $uri ) = @_;
    ($self->dbh->selectrow_array(
        'SELECT * FROM links WHERE link == ?',
        undef,
        $uri
    )) and return $uri;
    return;
}

sub _make_not_found_link {
    my ( $self, $what ) = @_;
    my $uri = URI->new("http://search.cpan.org/perldoc?$what");

    my $saved_uri = $self->_is_saved_uri( $uri );
    defined $saved_uri
        and return $saved_uri;

    my $response = $self->response( $self->ua->get( $uri ) );

    if ( $response->is_success ) {
        return $self->_save_uri($uri);
    }
    elsif ( $response->code == 404 ) {
        return $self->message_404;
    }
    else {
        return 'Network error: ' . $response->status_line;
    }
}


1;
__END__

=head1 NAME

CPAN::LinksToDocs::No404s::Remember - same as CPAN::LinksToDocs::No404s with persistent storage of working links in SQLite database

=head1 SYNOPSIS

    use strict;
    use warnings;

    use CPAN::LinksToDocs::No404s::Remember;

    my $linker = CPAN::LinksToDocs::No404s::Remember->new;

    for ( @{ $linker->link_for('map,grep,RE,OOP') } ) {
        print "$_\n";
    }

=head1 DESCRIPTION

The module provides means to get links to documentation on
L<http://search.cpan.org> by giving it "tags". There are a few tags
which group several links together (e.g. C<RE>, C<REF> or C<OOP> tags).
The base code of this module is what is used under the hood of
L<http://tnx.nl/404> website. Thanks to Juerd Waalboer you can now use it
too :)

The module is similiar to L<CPAN::LinksToDocs::No404s> module, except
this one will store working links for non-predefined tags in a SQLite
database as to speed up any subsequent requests for the same tag.

=head1 CONSTRUCTOR

=head2 new

    my $linker = CPAN::LinksToDocs::No404s::Remember->new;

    my $linker2 = CPAN::LinksToDocs::No404s::Remember->new(
        tags => {
            some    => 'http://there.somewhere',
            map     => 'http://some_custom.link.to.map.function',
            BOTH    => 'some,map', # will return 'some' and 'map' together
        },
        db_file     => 'cpan_links_to_docs.db',
        message_404 => 'NO DOCS!',
        timeout => 20,
        # or
        ua  => LWP::UserAgent->new( timeout => 20, agent => 'foos!' ),
    );

Returns a freshly baked C<CPAN::LinksToDocs::No404s::Remember> object.
Takes several
I<optional> arguments which are as follows;

=head3 tags

    ->new(
        tags => {
            some    => 'http://there.somewhere',
            map     => 'http://some_custom.link.to.map.function',
            BOTH    => 'some,map', # will return 'some' and 'map' together
        },
    );

B<Optional>.
The C<tags> argument takes a hashref as a value. The keys of this
hashref will be "tags" which you can use in the C<link_for> method.
The values is what you'll get in return arrayref. B<Note:> if the value
contains a comma it will be split on and the elements of that split will
be considered as tags, thus you can use predefined tags to group several
links together. B<Defaults to:> nothing, only predefined tags mentioned
in C<TAGS> section.

=head3 db_file

    ->new( db_file => 'cpan_links_to_docs.db' );

B<Optional>. Specifies the name of the file where the module should store
the working
links. This will be an SQLite database so you could possibly edit it
with other tools. B<Defaults to:> C<cpan_links_to_docs.db>

=head3 message_404

    ->new( message_404 => 'NO DOCS!' );

B<Optional>.
If the "tag" was not found in predefined tags (see C<link_for> method
and C<TAGS> section) the "link" for the tag will contain whatever you
specify as C<message_404> argument to the constructor. B<Defaults to:>
C<Not found>

=head3 timeout

    ->new( timeout => 10 );

B<Optional>. Specifies the C<timeout> argument of L<LWP::UserAgent>'s
constructor, which is used for checking 404s. B<Defaults to:> C<30> seconds.

=head3 ua

    ->new( ua => LWP::UserAgent->new( agent => 'Foos!' ) );

B<Optional>. If the C<timeout> argument is not enough for your needs
of mutilating the L<LWP::UserAgent> object used for checking, feel free
to specify the C<ua> argument which takes an L<LWP::UserAgent> object
as a value. B<Note:> the C<timeout> argument to the constructor will
not do anything if you specify the C<ua> argument as well. B<Defaults to:>
plain boring default L<LWP::UserAgent> object with C<timeout> argument
set to whatever C<CPAN::LinksToDocs::No404s::Remember>' C<timeout> argument is
set to as well as C<agent> argument is set to mimic Firefox.

=head1 METHODS

=head2 link_for

    my $links_ref = $linker->link_for('map,grep,some,BOTH');

Returns a (possibly empty) arrayref of links to documentation. Takes
one mandatory scalar argument which is one or more "tags" separated by
commas. See L<TAGS> section below for possible tags. If the tag was not
found in predefined tags the returning link will be
C<http://search.cpan.org/perldoc?TAG_YOU_GAVE_THAT_WAS_NOT_FOUND> this
way you can link to custom made modules available on CPAN. B<However,> the
module will connect to L<http://search.cpan.org/> and make sure that module
exists. If the module doesn't exist the "link" for this tag will be
your C<message_404> (see constructor). If a network error occured while
checking the "link" will match C<qr/^Network error:/> and will contain
the description of the error.

=head2 tags

    my $tags_ref = $linker->tags;

    $tags_ref->{foos} = 'http://bars/';
    $linker->tags( $tags_ref );

Returns a hashref of currently set tags. Takes one optional argument which
must be a hashref of tags. The format is the same as the C<tags> argument
to the constructor.

=head2 response

    my $last_response_obj = $linker->response;

Takes no arguments, returns the L<HTTP::Response> object which was obtained
while checking a non-predefined "tag".

=head2 message_404

    my $old_message = $linker->message_404;

    $linker->message_404('YOU GOT 404!');

Returns a currently set C<message_404> message (see constructor's
C<message_404> argument's description). Takes one optional argument. If
you call it with an argument, the argument you provide will be a new
C<message_404> message.

=head2 dbh

    my $dbh = $linker->dbh;

Takes no arguments. Returns L<DBI>'s database handle used for stuffing
working links into the database.

=head2 ua

    my $old_LWP_UA_obj = $linker->ua;

    $linker->ua( LWP::UserAgent->new( timeout => 10, agent => 'foos' );

Returns a currently used L<LWP::UserAgent> object used for checking 404s.
Takes one optional argument which must be an L<LWP::UserAgent>
object, and the object you specify will be used in any subsequent checks
of non-predefined "tags".

=head1 TAGS

The module has a LOT of predefined tags... and I am shamelessly going to
semi-quote Juerd's site:

You can B<leave out> the redundant C<perl> part. Except for C<perltie>,
because C<tie> is also a function.

The following groups and special "tags" are known:

C<FAQ>, C<MOD>, C<OO>, C<OOP>, C<RE>, C<REF>, C<UNI>, C<bp>, C<cws>,
C<include>, C<kp>, C<perlpodtut>, C<perltut>, C<podtut>, C<sfb>, C<tut>,
C<tutorial>.

C<S\d\d>, C<A\d\d> and C<E\d\d> for Perl 6 language design documents.

Below are the known tags for CPAN::LinksToDocs::No404s::Remember module:

    my @perldoc = qw(
        perl perl5004delta perl5005delta perl5100delta perl561delta perl56delta
        perl570delta perl571delta perl572delta perl573delta perl581delta
        perl582delta perl583delta perl584delta perl585delta perl586delta
        perl587delta perl588delta perl58delta perl590delta perl591delta
        perl592delta perl593delta perl594delta perl595delta perl5db.pl perlXStut
        perlamiga perlapi perlapio perlartistic perlbook perlboot perlbot perlbug
        perlcall perlce perlcheat perlclib perlcn perlcommunity perlcompile
        perldata perldbmfilter perldebguts perldebtut perldebug perldelta perldgux
        perldiag perldoc perldos perldsc perlebcdic perlembed perlfaq perlfaq1
        perlfaq2 perlfaq3 perlfaq4 perlfaq5 perlfaq6 perlfaq7 perlfaq8 perlfaq9
        perlfilter perlfork perlform perlfunc perlglob.bat perlglossary perlgpl
        perlguts perlhack perlhist perlintern perlintro perliol perlipc perlivp
        perljp perlko perllexwarn perllocale perllol perlmod perlmodinstall
        perlmodlib perlmodstyle perlnetware perlnewmod perlnumber perlobj perlop
        perlopentut perlos2 perlothrtut perlpacktut perlplan9 perlpod perlpodspec
        perlport perlpragma perlre perlreapi perlrebackslash perlrecharclass
        perlref perlreftut perlreguts perlrequick perlreref perlretut perlrun
        perlsec perlstyle perlsub perlsyn perlthrtut perltie perltoc perltodo
        perltooc perltoot perltrap perltw perlunicode perlunifaq perluniintro
        perlunitut perlutil perluts perlvar perlvms perlwin32 perlxs
    );

    my @perlfunc = qw(
        abs accept alarm atan2 bind binmode bless break caller chdir chmod chomp
        chop chown chr chroot close closedir connect continue cos crypt dbmclose
        dbmopen defined delete die do dump each endgrent endhostent endnetent
        endprotoent endpwent endservent eof eval exec exists exit exp fcntl fileno
        flags flock fork format formline getc getgrent getgrgid getgrnam
        gethostbyaddr gethostbyname gethostent getlogin getnetbyaddr getnetbyname
        getnetent getpeername getpgrp getppid getpriority getprotobyname
        getprotobynumber getprotoent getpwent getpwnam getpwuid getservbyname
        getservbyport getservent getsockname getsockopt glob gmtime goto grep hex
        import index int ioctl join keys kill last lc lcfirst length link listen
        local localtime lock log lstat m map mkdir msgctl msgget msgrcv msgsnd my
        next no oct open opendir ord order our pack package pipe pop pos precision
        print printf prototype push qq qr q qw qx quotemeta rand read readdir
        readline readlink readpipe recv redo ref rename require reset return
        reverse rewinddir rindex rmdir s say scalar seek seekdir select semctl
        semget semop send setgrent sethostent setnetent setpgrp setpriority
        setprotoent setpwent setservent setsockopt shift shmctl shmget shmread
        shmwrite shutdown sin size sleep socket socketpair sort splice split
        sprintf sqrt srand stat state study sub substr symlink syscall sysopen
        sysread sysseek system syswrite tell telldir tie tied time times tr
        truncate uc ucfirst umask undef unlink unpack unshift untie use utime
        values vec vector wait waitpid wantarray warn write -X y
    );

    my @stdmods = qw(
        AnyDBM_File Archive::Extract Archive::Tar Archive::Tar::File
        Attribute::Handlers attributes attrs AutoLoader AutoSplit autouse B base
        B::Concise B::Debug B::Deparse Benchmark bigint bignum bigrat blib B::Lint
        B::Showlex B::Terse B::Xref bytes Carp Carp::Heavy CGI CGI::Apache
        CGI::Carp CGI::Cookie CGI::Fast CGI::Pretty CGI::Push CGI::Switch CGI::Util
        charnames Class::ISA Class::Struct Compress::Raw::Zlib Compress::Zlib
        Config constant CORE CPAN CPAN::API::HOWTO CPAN::FirstTime CPAN::Kwalify
        CPAN::Nox CPANPLUS CPANPLUS::Dist::Base CPANPLUS::Dist::Sample
        CPANPLUS::Shell::Classic CPANPLUS::Shell::Default::Plugins::HOWTO
        CPAN::Version Cwd Data::Dumper DB DB_File DBM_Filter DBM_Filter::compress
        DBM_Filter::encode DBM_Filter::int32 DBM_Filter::null DBM_Filter::utf8
        Devel::DProf Devel::InnerPackage Devel::Peek Devel::SelfStubber diagnostics
        Digest Digest::base Digest::file Digest::MD5 Digest::SHA DirHandle
        Dumpvalue DynaLoader Encode Encode::Alias Encode::Byte Encode::CJKConstants
        Encode::CN Encode::CN::HZ Encode::Config Encode::EBCDIC Encode::Encoder
        Encode::Encoding Encode::GSM0338 Encode::Guess Encode::JP Encode::JP::H2Z
        Encode::JP::JIS7 Encode::KR Encode::KR::2022_KR Encode::MIME::Header
        Encode::MIME::Name Encode::PerlIO Encode::Supported Encode::Symbol
        Encode::TW Encode::Unicode Encode::Unicode::UTF7 encoding
        encoding::warnings English Env Errno Exporter Exporter::Heavy
        ExtUtils::CBuilder ExtUtils::CBuilder::Platform::Windows ExtUtils::Command
        ExtUtils::Command::MM ExtUtils::Constant ExtUtils::Constant::Base
        ExtUtils::Constant::Utils ExtUtils::Constant::XS ExtUtils::Embed
        ExtUtils::Install ExtUtils::Installed ExtUtils::Liblist ExtUtils::MakeMaker
        ExtUtils::MakeMaker::bytes ExtUtils::MakeMaker::Config
        ExtUtils::MakeMaker::FAQ ExtUtils::MakeMaker::Tutorial
        ExtUtils::MakeMaker::vmsish ExtUtils::Manifest ExtUtils::Mkbootstrap
        ExtUtils::Mksymlists ExtUtils::MM ExtUtils::MM_AIX ExtUtils::MM_Any
        ExtUtils::MM_BeOS ExtUtils::MM_Cygwin ExtUtils::MM_DOS ExtUtils::MM_MacOS
        ExtUtils::MM_NW5 ExtUtils::MM_OS2 ExtUtils::MM_QNX ExtUtils::MM_Unix
        ExtUtils::MM_UWIN ExtUtils::MM_VMS ExtUtils::MM_VOS ExtUtils::MM_Win32
        ExtUtils::MM_Win95 ExtUtils::MY ExtUtils::Packlist ExtUtils::ParseXS
        ExtUtils::testlib Fatal Fcntl feature fields File::Basename FileCache
        File::CheckTree File::Compare File::Copy File::DosGlob File::Fetch
        File::Find File::Glob File::GlobMapper FileHandle File::Path File::Spec
        File::Spec::Cygwin File::Spec::Epoc File::Spec::Functions File::Spec::Mac
        File::Spec::OS2 File::Spec::Unix File::Spec::VMS File::Spec::Win32
        File::stat File::Temp filetest Filter::Simple Filter::Util::Call FindBin
        GDBM_File Getopt::Long Getopt::Std Hash::Util Hash::Util::FieldHash
        I18N::Collate I18N::Langinfo I18N::LangTags I18N::LangTags::Detect
        I18N::LangTags::List if integer IO IO::Compress::Base IO::Compress::Deflate
        IO::Compress::Gzip IO::Compress::RawDeflate IO::Compress::Zip IO::Dir
        IO::File IO::Handle IO::Pipe IO::Poll IO::Seekable IO::Select IO::Socket
        IO::Socket::INET IO::Socket::UNIX IO::Uncompress::AnyInflate
        IO::Uncompress::AnyUncompress IO::Uncompress::Base IO::Uncompress::Gunzip
        IO::Uncompress::Inflate IO::Uncompress::RawInflate IO::Uncompress::Unzip
        IO::Zlib IPC::Cmd IPC::Open2 IPC::Open3 IPC::SysV IPC::SysV::Msg
        IPC::SysV::Semaphore less lib List::Util locale Locale::Constants
        Locale::Country Locale::Currency Locale::Language Locale::Maketext
        Locale::Maketext::Simple Locale::Maketext::TPJ13 Locale::Script
        Log::Message Log::Message::Config Log::Message::Handlers Log::Message::Item
        Math::BigFloat Math::BigInt Math::BigInt::Calc Math::BigInt::CalcEmu
        Math::BigInt::FastCalc Math::BigRat Math::Complex Math::Trig Memoize
        Memoize::AnyDBM_File Memoize::Expire Memoize::ExpireFile
        Memoize::ExpireTest Memoize::NDBM_File Memoize::SDBM_File Memoize::Storable
        MIME::Base64 MIME::QuotedPrint Module::Build Module::Build::API
        Module::Build::Authoring Module::Build::Base Module::Build::Compat
        Module::Build::ConfigData Module::Build::Cookbook Module::Build::ModuleInfo
        Module::Build::Notes Module::Build::Platform::aix
        Module::Build::Platform::Amiga Module::Build::Platform::cygwin
        Module::Build::Platform::darwin Module::Build::Platform::Default
        Module::Build::Platform::EBCDIC Module::Build::Platform::MacOS
        Module::Build::Platform::MPEiX Module::Build::Platform::os2
        Module::Build::Platform::RiscOS Module::Build::Platform::Unix
        Module::Build::Platform::VMS Module::Build::Platform::VOS
        Module::Build::Platform::Windows Module::Build::PPMMaker
        Module::Build::YAML Module::CoreList Module::Load Module::Load::Conditional
        Module::Loaded Module::Pluggable Module::Pluggable::Object mro NDBM_File
        Net::Cmd Net::Config Net::Domain Net::FTP Net::hostent Net::libnetFAQ
        Net::netent Net::Netrc Net::NNTP Net::Ping Net::POP3 Net::protoent
        Net::servent Net::SMTP Net::Time NEXT O ODBM_File Opcode open ops overload
        Package::Constants Params::Check PerlIO PerlIO::encoding PerlIO::scalar
        PerlIO::via PerlIO::via::QuotedPrint Pod::Checker Pod::Escapes Pod::Find
        Pod::Functions Pod::Html Pod::InputObjects Pod::LaTeX Pod::Man
        Pod::ParseLink Pod::Parser Pod::ParseUtils Pod::Perldoc::ToChecker
        Pod::Perldoc::ToMan Pod::Perldoc::ToNroff Pod::Perldoc::ToPod
        Pod::Perldoc::ToRtf Pod::Perldoc::ToText Pod::Perldoc::ToTk
        Pod::Perldoc::ToXml Pod::Plainer Pod::PlainText Pod::Select Pod::Simple
        Pod::Simple::Checker Pod::Simple::Debug Pod::Simple::DumpAsText
        Pod::Simple::DumpAsXML Pod::Simple::HTML Pod::Simple::HTMLBatch
        Pod::Simple::LinkSection Pod::Simple::Methody Pod::Simple::PullParser
        Pod::Simple::PullParserEndToken Pod::Simple::PullParserStartToken
        Pod::Simple::PullParserTextToken Pod::Simple::PullParserToken
        Pod::Simple::RTF Pod::Simple::Search Pod::Simple::SimpleTree
        Pod::Simple::Subclassing Pod::Simple::Text Pod::Simple::TextContent
        Pod::Simple::XMLOutStream Pod::Text Pod::Text::Color Pod::Text::Overstrike
        Pod::Text::Termcap Pod::Usage POSIX re Safe Scalar::Util SDBM_File
        Search::Dict SelectSaver SelfLoader Shell sigtrap Socket sort Storable
        strict subs Switch Symbol Sys::Hostname Sys::Syslog
        Sys::Syslog::win32::Win32 Term::ANSIColor Term::Cap Term::Complete
        Term::ReadLine Term::UI Test Test::Builder Test::Builder::Module
        Test::Builder::Tester Test::Builder::Tester::Color Test::Harness
        Test::Harness::Assert Test::Harness::Iterator Test::Harness::Point
        Test::Harness::Results Test::Harness::Straps Test::Harness::TAP
        Test::Harness::Util Test::More Test::Simple Test::Tutorial Text::Abbrev
        Text::Balanced Text::ParseWords Text::Soundex Text::Tabs Text::Wrap Thread
        Thread::Queue threads Thread::Semaphore threads::shared Tie::Array
        Tie::File Tie::Handle Tie::Hash Tie::Hash::NamedCapture Tie::Memoize
        Tie::RefHash Tie::Scalar Tie::SubstrHash Time::gmtime Time::HiRes
        Time::Local Time::localtime Time::Piece Time::Piece::Seconds Time::tm
        Unicode::Collate Unicode::Normalize Unicode::UCD UNIVERSAL User::grent
        User::pwent utf8 vars version vmsish warnings warnings::register Win32
        Win32API::File Win32CORE XS::APItest XSLoader XS::Typemap
    );

    my %tags = (
        UNI => 'perlunitut,perlunifaq,Encode,perluniintro,perlunicode,utf8',
        RE  => 'perlrequick,perlretut,perlre,perlreref',
        REF => 'perlreftut,perllol,perldsc,perlref',
        OO  => 'perlboot,perltoot,perltooc,perlbot',
        OOP => 'perlboot,perltoot,perltooc,perlbot',
        FAQ => (join ',', "perlfaq1" .. "perlfaq9"),
        MOD => 'perlmod,perlmodlib,perlmodstyle,perlmodinstall,perlnewmod',
        kp => 'http://pastebot.nd.edu/perlhelp',
        bp => 'http://learn.perl.org/library/beginning_perl/',
        cws => 'http://perl.plover.com/FAQs/Namespaces.html',
        sfb => 'http://perl.plover.com/FAQs/Buffering.html',
        include => 'http://perlmonks.org/?node_id=393426',
        podtut => 'http://juerd.nl/site.plp/perlpodtut',
        perlpodtut => 'http://juerd.nl/site.plp/perlpodtut',
        perltut => 'http://www.steve.gb.com/perl/tutorial.html',
        tut => 'http://www.steve.gb.com/perl/tutorial.html',
        tutorial => 'http://www.steve.gb.com/perl/tutorial.html',
    );

=head1 SEE ALSO

L<http://tnx.nl/404>, L<CPAN::LinksToDocs>,
L<CPAN::LinksToDocs::No404s>,
L<POE::Component::CPAN::LinksToDocs::No404s::Remember>
L<POE::Component::CPAN::LinksToDocs::No404s>,
L<POE::Component::IRC::Plugin::CPAN::LinksToDocs>,
L<POE::Component::IRC::Plugin::CPAN::LinksToDocs::No404s>,
L<POE::Component::IRC::Plugin::CPAN::LinksToDocs::No404s::Remember>

=head1 AUTHOR

Thanks to Juerd Waalboer, the author of L<http://tnx.nl/404> for providing
base code.

Zoffix Znet, C<< <zoffix at cpan.org> >>
(L<http://zoffix.com>, L<http://haslayout.net>)

=head1 BUGS

Please report any bugs or feature requests to C<bug-cpan-linkstodocs-no404s-remember at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=CPAN-LinksToDocs-No404s-Remember>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc CPAN::LinksToDocs::No404s::Remember

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=CPAN-LinksToDocs-No404s-Remember>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/CPAN-LinksToDocs-No404s-Remember>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/CPAN-LinksToDocs-No404s-Remember>

=item * Search CPAN

L<http://search.cpan.org/dist/CPAN-LinksToDocs-No404s-Remember>

=back

=head1 COPYRIGHT & LICENSE

Copyright 2008 Zoffix Znet, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
