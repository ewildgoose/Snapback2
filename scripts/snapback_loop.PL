#!/usr/local/bin/perl
##!~_~perlpath~_~

=head1 NAME

snapback_loop -- loop waiting to call snapback2

=head1 SYNOPSIS

  snapback_loop [-c configfile] &

=head1 DESCRIPTION

This script just loops looking for a file in the communication
directory, by default /tmp/backups. It then calls snapback2 with the
specified configuration file name root based in /etc/snapback.

To initiate a backup, you just put entries in crontab like:

 18 * * * * touch /tmp/backups/snapback

The filename is the name of the snapback configuration file.
The above would cause a call to:

	    /usr/local/bin/snapback2 snapback

which is equivalent to

	    /usr/local/bin/snapback2 -c /etc/snapback/snapback.conf

Errors in snapback are emailed to the C<AdminEmail> address
set in the snapback.conf configuration.

If the snapback configuration file is not specified with the C<-c>
command line option, the following files are checked for existence in
order and the first one found is used:

	/etc/snapback2.conf
	/etc/snapback/snapback2.conf
	/etc/snapback.conf
	/etc/snapback/snapback.conf

If it is still not found, the defaults will be used.

=head1 OPTIONS

=over 4

=item -c configfile

The complete path to the configuration file to use. If not specified,
defaults to:

	/etc/snapback2.conf
	/etc/snapback/snapback2.conf
	/etc/snapback.conf
	/etc/snapback/snapback.conf

=item -d 

Turns snapback2 debug on. Equivalent to setting "SnapbackOpts -d" in
the configuration file. Will not override SnapbackOpts in the config,
though.

=back

=head1 AUTHOR

Mike Heins, <mikeh@perusion.com>.

=cut

use File::Path;
use File::Copy;
use POSIX qw/strftime/;
use Config::ApacheFormat;
use Getopt::Std;
use strict;

use vars qw/$VERSION/;

$VERSION = '0.2';

my $USAGE = <<EOF;
snapback_loop -- loop to launch snapback2

Options:

	-c configfile (default /etc/snapback2.conf).

EOF

my %opt;

#---------- ---------- ---------- ---------- ---------- ----------
# Process command-line Arguments + Options

getopts('c:dh', \%opt) or die $USAGE;

if($opt{h}) {
	print $USAGE;
	exit 2;
}

my $config_file;

my @config_tries = qw(
	/etc/snapback2.conf
	/etc/snapback/snapback2.conf
	/etc/snapback.conf
	/etc/snapback/snapback.conf
);

if($ARGV[0] and -f "/etc/snapback/$ARGV[0].conf") {
	$config_file = "/etc/snapback/$ARGV[0].conf";
}
else {
	for(@config_tries) {
		next unless -e $_;
		$config_file = $_;
		last;
	}
}

my %Defaults = (
	AlwaysEmail => 'No',
	LoopDirectory => '/tmp/backups',
	sendmail => "/usr/sbin/sendmail",
	SnapbackExecutable => '/usr/local/sbin/snapback2',
	SnapbackOpts => '',
);

$Defaults{SnapbackOpts} = '-d' if $opt{d};

my %Boolean = qw(
	CreateDir        1
	AlwaysEmail      1
	AutoTime		 1
	LiteralDirectory 1
);

for(grep /[A-Z]/, keys %Defaults) {
	$Defaults{lc $_} = $Defaults{$_};
}

for(grep /[A-Z]/, keys %Boolean) {
	$Boolean{lc $_} = $Boolean{$_};
}

#---------- ---------- ---------- ---------- ---------- ----------
# Process config file
my $cfg;
if(-f $config_file) {
	$cfg = new Config::ApacheFormat
						 duplicate_directives => 'combine',
						 root_directive => 'SnapbackRoot',
						;

	$cfg->read($config_file);
}

sub get_cfg {
	my $parm = shift;
	return unless $cfg;
	my @vals;
	@vals = $cfg->get($parm) if $cfg;
	my $num = scalar(@vals);
	my $val;
	if($num == 0) {
		$val = $Defaults{lc $parm};
	}
	elsif(@vals == 1) {
		$val = $vals[0];
	}
	elsif(wantarray) {
		return @vals;
	}
	else {
		$val = \@vals;
	}

	if($Boolean{lc $parm}) {
		$val = is_yes($val);
	}
	return $val;
}

my $COMM_DIR = get_cfg('LoopDirectory') || '/tmp/backups';
my $ERR_DIR  = "$COMM_DIR/errors";
my $DONE_DIR = "$COMM_DIR/done";
my $SNAPBACK = get_cfg('SnapbackExecutable') || '/usr/local/bin/snapback2';
my $SNAPBACK_OPTS =  get_cfg('SnapbackOpts') || '';



## Number of seconds to loop on, this machine does nothing else so is
## short
my $LOOP_DELAY = 2;
my $ERROR_ADDRESS = 'root';
my $FROM_ADDRESS =  'root';
my $MAIL_PROG     = '/usr/sbin/sendmail';

if(! -d $COMM_DIR) {
	File::Path::mkpath($COMM_DIR, 1, 0700);
}

sub mail_error {
	my ($subject, $msg) = @_;
	$msg ||= $subject;
	open MAIL, "| $MAIL_PROG -t"
		or die "Can't fork $MAIL_PROG: $!\n";
	print MAIL <<EOF;
Subject: $subject
To: $ERROR_ADDRESS
From: $FROM_ADDRESS

$msg
EOF
	close MAIL
		or die "Couldn't send mail via $MAIL_PROG: $!\n";

}

for(;;) {
	opendir COMMDIR, $COMM_DIR
		or die "cannot opendir $COMM_DIR: $!\n";
	my @files = grep ! -d "$COMM_DIR/$_", readdir COMMDIR;
	for(@files) {
		my $bname      = $_;
		my $origname   = "$COMM_DIR/$_";
		my $run_name   = "$origname.inprocess";
		my $done_name  = "$origname.done";
		if(/[^-\w]/) {
			my $endtime = strftime("%Y-%m-%d-%H-%M-%S", localtime());
			open ERR, "> $ERR_DIR/$bname.$endtime"
				or die "Can't open $ERR_DIR/$bname.$endtime: $!\n";
			print ERR "Snapback error, spurious backup call to $bname.\n";
			close ERR;
			mail_error("Spurious backup call to $_");
			unlink $origname;
		}
		else {
			rename $origname, $run_name;
		}

		my $bdate     = strftime("%Y%m%d", localtime());
		my $begintime = strftime("%Y-%m-%d-%H-%M-%S", localtime());
		system "$SNAPBACK $SNAPBACK_OPTS $_";
		my $status = $?;
		my $err = $!;
		my $endtime = strftime("%Y-%m-%d-%H-%M-%S", localtime());
		unlink $run_name;
		if($? != 0) {
			my $ecode = $status >> 8;
			open ERR, "> $ERR_DIR/$bname.$endtime"
				or die "Can't open $ERR_DIR/$bname.$endtime: $!\n";
			print ERR "Snapback error $ecode (status=$status, text=$err) at $endtime\n";
			close ERR;
		}
		else {
			my $done_name = "$DONE_DIR/$bdate";
			File::Path::mkpath($done_name) unless -d $done_name;
			open DONE, "> $done_name/$bname.$endtime"
				or die "Can't open $done_name/$bname.$endtime: $!\n";
			print DONE "Snapback $bname complete.\n";
			close DONE;
		}
	}
	sleep 2;
}
