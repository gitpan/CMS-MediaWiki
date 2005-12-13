package CMS::MediaWiki;
#######################################################################
# Author: Reto Schär
# Copyright (C) 2005 by Reto Schär
#
# This library is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself, either Perl version 5.8.6 or,
# at your option, any later version of Perl 5 you may have available.
#######################################################################
use strict;
my $package = __PACKAGE__;

our $VERSION = '0.80.05';

use LWP::UserAgent;
use HTTP::Request::Common;

# GLOBAL VARIABLES
my %Var = ();
my $contentType = "";
my $ua;

$| = 1;

#-----  FORWARD DECLARATIONS & PROTOTYPING
sub Error($);
sub Debug($);

sub new {
	my $type = shift;
	my %params = @_;
	my $self = {};

	$self->{'host'  } = $params{'host'};
	$self->{'path'  } = $params{'path'};
	$self->{'debug' } = $params{'debug'}; # 0, 1, 2
	$Var{'SERVER_SIG'} = '*Unknown*';
	$Var{'EDIT_TIME_BEFORE'} = '*Unknown*';

	Debug "$package V$VERSION" if $self->{'debug'};

	$ua = LWP::UserAgent->new(
		agent => 'Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.0; T312461)' ,
		'cookie_jar' => {file => "lwpcookies.txt", autosave => 1}
	);

	bless $self, $type;
}

sub login {
	my $self = shift;
	my %args = @_;

	if ($self->{'debug'}) {
		Debug "[login] $_ = $args{$_}" foreach keys %args;
	}

	$args{'path'} ||= $self->{'path'};
	$self->{'path'} = $args{'path'}; # globalize, if it was set here

	$args{'host'} ||= $self->{'host'};
	$self->{'host'} = $args{'host'}; # globalize

	my %tags = ();
	$tags{'wpName'        } = $args{'user'};
	$tags{'wpPassword'    } = $args{'pass'};
	$tags{'wpLoginattempt'} = 'Log in';

	my $index_path = "/index.php";
	   $index_path = "/$args{'path'}/index.php" if $args{'path'};

	my $login_url = "http://$args{'host'}$index_path?title=Special:Userlogin&amp;action=submitlogin";

	Debug "[login] POST $login_url\..." if $self->{'debug'};

	my $resp = $ua->request(
		POST $login_url ,
		Content_Type  => 'application/x-www-form-urlencoded' ,
		Content       => [ %tags ]
	);

	my $login_okay = 0;
	foreach (keys %{$resp->{'_headers'}}) {
		Debug "(header) $_ = " . $resp->{'_headers'}->{$_} if $self->{'debug'} > 1;
		if ($_ =~ /^set-cookie$/i) {
			my $arr = $resp->{'_headers'}->{$_};
			if ($arr =~ /^ARRAY(.+)$/) {
				foreach (@{$arr}) {
					Debug "- (cookie) $_" if $self->{'debug'} > 1;
					# wikiUserID or wikidbUserID
					if ($_ =~ /UserID=\d+\;/i) {
						# Success!
						$login_okay = 1;
					}
					Debug "(cookie) $_" if $self->{'debug'} > 1;
				}
			}
			else {
				Debug "=====> cookie: $arr" if $self->{'debug'};
			}
		}
		if ($_ =~ /^server$/i) {
			$Var{'SERVER_SIG'} = $resp->{'_headers'}->{$_};
		}
	}

	return $login_okay ? 0 : 1;
}

sub editPage {
	my $self = shift;
	my %args = @_;

	if ($self->{'debug'}) {
		Debug "[editPage] $_ = \"$args{$_}\"" foreach keys %args;
		Debug "[editPage] VAR $_ = \"$Var{$_}\"" foreach keys %Var;
	}

	my $WHOST = $self->{'host'} || 'localhost';
	my $WPATH = $self->{'path'} || '';

	$args{'text   '} ||= '* No text *';
	$args{'summary'} ||= '';
	$args{'section'} ||= '';

	Debug "Editing page '$args{'title'}' (section '$args{'section'}')..." if $self->{'debug'};

	my $edit_section = length($args{'section'}) > 0 ? "\&section=$args{'section'}" : '';

	# (Pre)fetch page...
	my $resp = $ua->request(GET "http://$WHOST/$WPATH/index.php?title=$args{'title'}&action=edit$edit_section");
	my @lines = split /\n/, $resp->content();
	my $token = my $edit_time = '';
	foreach (@lines) {
		#Debug "X $_";
		if (/wpEditToken/) {
			s/type=.?hidden.? *value="(.+)" *name/$1/i;
			$token = $1;
		}
		if (/wpEdittime/) {
			s/type=.?hidden.? *value="(.+)" *name/$1/i;
			$edit_time = $1 || '';
			$Var{EDIT_TIME_BEFORE} = $edit_time;
		}
		if (/<title>/i) {
			s/<title>(.+)<\/title>/$1/i;
			$Var{PAGE_TITLE} = $1 || '';
		}
		if (/index.php\?title=(.+?):Copyright.+/i) {
			$Var{WIKI_NAME} = $1 || '';
		}
	}

	if ($self->{'debug'}) {
		Debug "token = $token" if $self->{'debug'} > 1;
		Debug "edit_time (before update) = $edit_time";
	}

	my %tags = ();
	$tags{'wpTextbox1' } = $args{'text'};
	$tags{'wpEdittime' } = $edit_time;
	$tags{'wpSave'     } = 'Save page';
	$tags{'wpSection'  } = $args{'section'};
	$tags{'wpSummary'  } = $args{'summary'};
	$tags{'wpEditToken'} = $token;

	$tags{'title' } = $args{'title'};
	$tags{'action' } = 'submit';

	$resp = $ua->request(
		POST "http://$WHOST/$WPATH/index.php?title=$args{'title'}&amp;action=submit" ,
		Content_Type  => 'application/x-www-form-urlencoded' ,
		Content       => [ %tags ]
	);

	foreach (sort keys %{$resp->{'_headers'}}) {
		Debug "(header) $_ = " . $resp->{'_headers'}->{$_} if $self->{'debug'} > 1;
	}
	my $response_location = $resp->{'_headers'}->{'location'} || '';
	Debug "Response Location: $response_location" if $self->{'debug'};
	Debug "Comparing with \"/$args{'title'}\"" if $self->{'debug'};
	if ($response_location =~ /[\/=]$args{'title'}/i) {
		Debug "Success!" if $self->{'debug'};
		return 0;
	}
	else {
		Debug "NOK!" if $self->{'debug'};
		return 1;
	}
}

sub get {
	my $self = shift;
	my $Key  = shift;
	$Var{$Key};
}

sub let {
	my $self  = shift;
	my $Key   = shift;
	my $Value = shift;

	Debug "[let] $Key = $Value" if $self->{'debug'};
	$Var{$Key} = $Value;
}

sub Error ($) {
	print "Content-type: text/html\n\n" unless $contentType;
	print "<b>ERROR</b> ($package): $_[0]\n";
	exit(1);
}

sub Debug ($)  { print "[ $package ] $_[0]\n"; }

####  Used Warning / Error Codes  ##########################
#	Next free W Code: 1000
#	Next free E Code: 1000

1;

__END__

=head1 NAME

CMS::MediaWiki - Perl extension for creating and updating MediaWiki pages

=head1 SYNOPSIS

  use CMS::MediaWiki;

  my $mw = CMS::MediaWiki->new(
	host  => 'localhost',
	path  => 'wiki' ,     #  Can be empty on 3rd-level domain Wikis
	debug => 0            #  0=no debug msgs, 1=some msgs, 2=more msgs
  );

=head1 DESCRIPTION

Create or update MediaWiki pages. An update of a MediaWiki page can also be
reduced to a specific page section. You may update many pages with the same
object handle ($mw in the shown example).

You could change the login name between an update. This might be necessary
if you would like to update a public page *and* a protected page by the
WikiSysop user in just one cycle.

=head2 Login example

	$rc = $mw->login( user => 'Reto' , pass => 'yourpass' );

=head2 Another login example

	$rc = $mw->login(
		host => 'localhost' ,  # optional here, but wins if (re-)set here
		path => 'wiki',        # optional here, but wins
		user => 'Reto' ,
		pass => 'yourpass' ,
	);

=head2 Edit a Wiki page

	$rc = $mw->editPage(
		title   => 'Online_Directory:Computers:Software:Internet:Authoring' ,

	    	section => '' ,	#  2 means edit second section etc.
        	                # '' = no section means edit the full page

        	text    => "== foo ==\nbar foo\n\n",

		summary => "Your summary." ,
	);

In general, $rc returns 0 on success unequal 0 on failure.

=head3 Tip

After a successful call of the editPage function you had the
following information available:

  print "Edit time (before) was ", $mw->get('EDIT_TIME_BEFORE'), "\n";
  print "Page title was "        , $mw->get('PAGE_TITLE')      , "\n";
  print "The Wiki name was "     , $mw->get('WIKI_NAME')       , "\n";

=head2 EXPORT

None by default.

=head1 SEE ALSO

http://www.infocopter.com/perl/modules/

http://www.infocopter.com/know-how/mediawiki-reference/Perl-CMS-MediaWiki.html

=head1 AUTHOR

Reto Schär, E<lt>retoh@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005 by Reto Schär

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.6 or,
at your option, any later version of Perl 5 you may have available.

http://www.infocopter.com/perl/licencing.html

=cut
