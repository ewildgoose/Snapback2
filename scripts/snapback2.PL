#!/usr/bin/perl
##!~_~perlpath~_~

## ---------- ---------- ---------- ---------- ---------- ----------
## snapback2 -- 1.Jan.2004 -- Mike Heins
## - rsync and hard-link backup script, enhanced
## - based on research by Mike Rubel
## - based on original snapback by Art Mulder
##   www.http://www.mikerubel.org/computers/rsync_snapshots/
## - This works on a "pull" basis.  The backup server runs this
##   script and rsync's to the client machine(s) to backup the
##   requested directories.
##
## ---------- ---------- ---------- ---------- ---------- ----------
## snapback -- 15.May.2002 -- Art Mulder
## - rsync and hard-link backup script
## - based on research by Mike Rubel
##   www.http://www.mikerubel.org/computers/rsync_snapshots/
##
## ---------- ---------- ---------- ---------- ---------- ----------
## Logic Layout:
##  - startup, usage, read config file
##  - rotate the snapshot directories
##  - rsync the client/backup directories
##  - create daily/wkly/monthly backup-link directories if needed
##  - notify admin's of log results.  (flag errors?)
## ---------- ---------- ---------- ---------- ---------- ----------
## TODO: Is there a better way of catching the cp/rsync errors?

## ---------- ---------- ---------- ---------- ---------- ----------
## Variables and other Setups

use Getopt::Std;        ## standard command-line processing functions
use Sys::Hostname;
use File::Path;
use Config::ApacheFormat;
use POSIX qw/strftime/;
use strict;

use vars qw/$VERSION/;

$VERSION = '0.3';

=head1 NAME

snapback2 -- rsync and hard-link backup script

=head1 SYNOPSIS

  snapback2 [-c configfile] [-df] [-p PAT] [-P PAT] [configfile-base]

=head1 DESCRIPTION

Snapback2 does backup of systems via ssh and rsync. It creates rolling "snapshots"
based on hourly, daily, weekly, and monthly rotations. When it runs for
some period of time, you will end up with a target backup directory
that looks like:

	drwx--x--x   81 106      staff    4096 Jan  1 05:54 daily.0
	drwx--x--x   81 106      staff    4096 Dec 31 05:55 daily.1
	drwx--x--x   81 106      staff    4096 Dec 30 05:55 daily.2
	drwx--x--x   81 106      staff    4096 Dec 29 05:54 daily.3
	drwx--x--x   81 106      staff    4096 Dec 28 05:53 daily.4
	drwx--x--x   81 106      staff    4096 Dec 27 05:53 daily.5
	drwx--x--x   81 106      staff    4096 Dec 26 05:53 daily.5
	drwx--x--x   81 106      staff    4096 Jan  1 05:54 hourly.0
	drwx--x--x   81 106      staff    4096 Dec 31 17:23 hourly.1
	drwx--x--x   81 106      staff    4096 Jan  1 05:54 monthly.0
	drwx--x--x   81 106      staff    4096 Dec  1 05:54 monthly.1
	drwx--x--x   81 106      staff    4096 Dec 28 05:53 weekly.0
	drwx--x--x   81 106      staff    4096 Dec 21 05:53 weekly.1
	drwx--x--x   81 106      staff    4096 Dec 14 05:53 weekly.2
	drwx--x--x   81 106      staff    4096 Dec  7 05:53 weekly.3

You might think this would take up lots of space. However, snapback2
hard-links the files to create the images. If the file doesn't change,
only a link is necessary, taking very little space. It is possible to
create a complete yearly backup in just over 2x the actual
storage space consumed by the image. 

See www.http://www.mikerubel.org/computers/rsync_snapshots/ for detailed
information on the principles used.

Apache-style configuration files are used. A configuration file for
a basic backup might look like

	Hourlies    4
	Dailies     7
	Weeklies    4
	Monthlies  12
	AutoTime   Yes

	AdminEmail mikeh@perusion.com

	LogFile    /var/log/snapback.log
	Exclude *debug
	Exclude core.*
	SnapbackRoot /etc/snapback

	Destination /mnt/backup1

	<Backup mike.perusion.com>
		Destination /space
		Hourlies 2
		Directory /home/mike/
		Directory /etc/
		Directory /var/lib/mysql/
		Directory /var/lib/pgsql/
		<BackupDirectory /home/work/>
			Hourlies 4
		</BackupDirectory>
	</Backup>

	<Backup jean.perusion.com>
		Hourlies 2
		Directory /home/jean/
		Directory /var/mail/
	</Backup>

The above configuration will be discussed in detail below.

=head2 Pre-requisites

This script is only tested on Linux at this point, but should operate
on any UNIX-based computer with the following:

	Gnu toolset, including cp, rm, and mv
	rsync 2.5.7 or higher
	ssh
	Perl 5.8 or higher
	Perl module Config::ApacheFormat

=head1 CONFIGURATION

The configuration directives use Apache format, thanks to the Config::ApacheFormat
module.

Inheritance is on -- a sub-block inherits all configuration directives
above it. You can override any configuration directive within the block
container.

If not specified with the C<-c> command line option, the following
files are checked for existence in order and the first one found is
used:

	/etc/snapback2.conf
	/etc/snapback/snapback2.conf
	/etc/snapback.conf
	/etc/snapback/snapback.conf

=head2 Block directives

There are two blocks supported:

=over 4

=item Backup

This specifies the host computer which will be backed up, and it is given
an internet address as a parameter (host name or IP address). Only one
block can be specified per hostname per configuration file, but it is
possible to make the parameter a pseudo-host by overriding the address
with the C<BackupHost> directive.

For example:

	<Backup pseudo>
		BackupHost jean.perusion.com
		Hourlies 2
		Directory /etc/
	</Backup>
 
	<Backup jean.perusion.com>
		Hourlies 4
		Directory /home/jean/
	</Backup>

Both backup configurations use C<jean.perusion.com> as the target machine.

=item BackupDirectory

This is contained within a C<Backup> block, and is an alternate method
of specifying a C<Directory>. The parameter is the directory name. The
use for this is specifying different backup parameters for that directory
only.

For example:

	## directives are not case-sensitive
	<backup perusion.com>
		Destination /mnt/backup1
		Hourlies 4
		Directory /etc/
		Directory /var/lib/mysql/
		<BackupDirectory /var/lib/catalogs/shop/orders>
			Destination /mnt/backup1/orders
			Hourlies 24
		</Backup>
	</backup>

This allows a real hourly backup of a directory where frequent backups
are needed, while cutting down the frequency of the main backup.

=head2 Other directives

The rest of the directives control various facets of the backup.

=over 4

=item AdminEmail

Email address to mail errors (or results if AlwaysEmail is set).
Default blank.

=item AlwaysEmail

Always email results even if there is not an error. Target address is
set in C<AdminEmail>.

=item AutoTime

If set to yes, which is the default, the time of the previous backup
is checked and backup is only done if appropriate. The formula for
checking appropriateness is:

	(24 / Hourlies - 0.5) * 60 * 60 < now - mtime

where I<Hourlies> is the value of the C<Hourlies> directive, I<now> is
the current time in seconds since 1970, and I<mtime> is the modification
time in seconds since 1970.

For example, if C<Hourlies> is set to 4 and the script is called every
hour, it will only run the backup if the timestamp of the latest hourly
backup is more than 5.5 hours old. Obviously this means your backup
should take less than an hour to complete; if you have an extremely
extensive backup setup that could exceed an hour you will want to break
it up into separate runs or make the script call frequency greater.

=item ChargeFile

The file where byte counts are logged in the format 

	host:YYYYMMDD:N

where YYYYMMDD is the date in quasi-ISO format and N is the number
of bytes read. This allows monitoring of bandwidth used for a particular
backup host, possibly for a bandwidth-based charging mechnism.

=item Cp

Full path to the GNU C<cp> program. Default is I</bin/cp>.

=item CreateDir

Controls whether Destination directories will be created automatically.
A Boolean (Yes/No) directive. Default is I<Yes>.

=item DailyDir

The root name of the daily backup directory, default I<daily>.
Not normally changed.

=item Debug

Sets debug output on. Equivalent to passing the C<-d> option
on the command line.

In the future, the debug level may vary with the number passed.
At the moment, there is only one debug level.

Example:

	Debug  4

=item DebugFile

Normally debug output goes to STDERR, but if you want it sent
to a file specify the file with this directive.

Example:

	DebugFile /tmp/snapback.debug

=item Destination

The destination directory for the backup. A subdirectory 
of the host address is created (providing CreateDir is yes, 
the default), and then the first part of the C<Directory>
is created. The hourly/daily/weekly directories are then
maintained there.

For example, this configuration:

	Destination /mnt/backup1
	<Backup perusion.com>
		Directory /var/lib/mysql/
		Directory /home/mike/
		Directory /home/work/
	</Backup>

will create the following directories on its first run:

	/mnt/backup1/perusion.com/var/lib/mysql/hourly.0
	/mnt/backup1/perusion.com/var/lib/mysql/daily.0
	/mnt/backup1/perusion.com/home/mike/hourly.0
	/mnt/backup1/perusion.com/home/mike/daily.0
	/mnt/backup1/perusion.com/home/work/hourly.0
	/mnt/backup1/perusion.com/home/work/daily.0

If the run was made on Sunday, a weekly.0 will be created. If the run
was made on the first day of the month, a monthly.0 will be created.

=item DestinationList

A list of destinations that will be checked for the proper
backup place. If this is in force, the C<Destination> directive
will be ignored.

Set to the places where you want backup to go, i.e.:

	DestinationList  /mnt/backup1 /mnt/backup2

It checks the timestamp of the hourly.0 directory at each
target, and selects the least-recently-used one for the target.

This allows spreading the backup over multiple disks for greater
reliablility.

If you want to set a single destination in a Backup sub-block,
overriding a global DestinationList, either set

	DestinationList none
	Destination     /real/destination

or just set the DestinationList directive to the single directory.

The number of Hourlies, Dailies, Weeklies, and Monthlies 
still applies at each target. 

For example, this configuration:

	DestinationList /mnt/backup1 /mnt/backup2
	Hourlies 2
	<Backup perusion.com>
		Directory /var/lib/mysql/
		Directory /home/mike/
	</Backup>

will create the following directories on its first run:

	/mnt/backup1/perusion.com/var/lib/mysql/hourly.0
	/mnt/backup1/perusion.com/var/lib/mysql/daily.0
	/mnt/backup1/perusion.com/home/mike/hourly.0
	/mnt/backup1/perusion.com/home/mike/daily.0

this on its second:

	/mnt/backup2/perusion.com/var/lib/mysql/hourly.0
	/mnt/backup2/perusion.com/var/lib/mysql/daily.0
	/mnt/backup2/perusion.com/home/mike/hourly.0
	/mnt/backup2/perusion.com/home/mike/daily.0

and this on its third:

	/mnt/backup1/perusion.com/var/lib/mysql/hourly.0
	/mnt/backup1/perusion.com/var/lib/mysql/hourly.1
	/mnt/backup1/perusion.com/var/lib/mysql/daily.0
	/mnt/backup1/perusion.com/home/mike/hourly.0
	/mnt/backup1/perusion.com/home/mike/hourly.1
	/mnt/backup1/perusion.com/home/mike/daily.0

etc.

=item Directory

The directory to be backed up. It will be created on the C<Destination>,
and hourly.N, daily.N, weekly.N, and monthly.N directories will be
maintained there. See also C<BackupDirectory>.

Only valid within a <Backup host> block.

This directive is a multiple directive, and it can be set as many
times as needed.

A trailing slash is always added if necessary unless LiteralDirectory
is set to yes (which it should not be unless you are an rsync expert).

=item Exclude

File patterns to be excluded. Passed to C<rsync> with the --exclude-pattern
option. See the documentation for C<rsync>.

It is normal to exclude core files, for example:

	Exclude core
	Exclude core.*

This directive is a multiple directive, and it can be set as many
times as needed.

=item HourlyDir

The root name of the hourly backup directory, default I<hourly>.
Not normally changed.

=item Include

Specify a file or directory to include from. If the specification
is a directory, it will include all files in the directory:

	Include clients

That is the equivalent of "Include clients/*", though that 
syntax is not supported due to Config::ApacheFormat limitations.

To include only a single file:

	Include clients/something.conf

The file specification is based in C<ServerRoot>.

=item LiteralDirectory

Normally snapback automatically appends a C</> to the source
directory name to make rsync work properly. If C<LiteralDirectory>
is set to C<Yes>, then it will not do that, with unpredictable
results.

Default is C<No>, and you should think long and hard before
changing it.  It is possible to construct useful backups without
a trailing slash, but you will have to be an rsync expert.

In other words, don't mess with this.

=item LogFile

The name of the file where backup runs are logged. Default
is I</var/log/snapback.log>.

=item MonthlyDir

The root name of the monthly backup directory, default I<monthly>.
Not normally changed.

=item Mv

Full path to the GNU C<mv> program. Default is I</bin/mv>.

=item MyHost

The name of the backup host itself, used only for reporting purposes.
Default is the result of Sys::Hostname::hostname().

=item MustExceed

The amount of time the current time must exceed the previous backup
modification time before a backup will be done, when C<AutoTime> is
on. Default is C<5 minutes>.

=item Rm

Full path to the GNU C<rm> program. Default is I</bin/rm>.

=item Rsync

Full path to the C<rsync> program. Default is I<rsync>.

=item RsyncOpts

The options for the rsync program. Default is

  -avz -e ssh --force --delete-excluded  --one-file-system --delete

Play with this at your own risk. 8-)

=item SendMail

Path to the sendmail program, used for emailing errors (or results with
C<AlwaysEmail>). Default is I</usr/sbin/sendmail>.

The program to use must accept the C<-t> option.

=item SnapbackRoot

The root directory where any Include directives will be based.
Default is I</etc/snapback>.

Example:

	SnapbackRoot  /opt/snapback

=item WeeklyDir

The root name of the weekly backup directory, default C<weekly>.
Not normally changed.

=back

=head1 OPTIONS

There are a few command line options that can be called:

=over 4

=item -c configfile

The complete path to the configuration file to use. If not specified,
defaults to:

	/etc/snapback2.conf
	/etc/snapback/snapback2.conf
	/etc/snapback.conf
	/etc/snapback/snapback.conf

Fails if one of those is not found.

=item -d 

Turns on debug output. If C<DebugFile> is set, will go there, otherwise
goes to the standard error output.

=item -p PATTERN

A pattern to apply to the <Backup foo> block. Only hosts matching
the pattern will be operated on.

To backup all hosts in the perusion.com domains, but not any others,
do:

	snapback2 -p perusion.com

=item -P PATTERN

A pattern to apply to any C<Directory> or <BackupDirectory>.
Only directories matching the pattern will be operated on.

To backup all /var/ diretories, do:

	snapback2 -P /var/

Other directories will be ignored.

To backup /var/ directories in the perusion.com domains, but not
any others, do:

	snapback2 -p perusion.com -P /var/

=back

=head1

=head1 AUTHOR AND CREDITS

Mike Heins, <mikeh@perusion.com>.

This script is heavily cribbed from the original snapback done by Art
Mulder. Some of the routines, particularly do_rotate() and do_backup(),
are much the same; the main program flow and configuration is
completely redone.

The initial principles were elucidated by Mike Rubel.

=cut


my %Locale;

my %Defaults = (
	AlwaysEmail => 'No',
	ChargeFile => '/var/log/snapback.charges',
	cp => "/bin/cp",
	CreateDir => 'Yes',
	DailyDir => 'daily',
	HourlyDir => 'hourly',
	logfile => '/var/log/snapback',
	MonthlyDir => 'monthly',
	MustExceed => '5 minutes',
	mv => "/bin/mv",
	Myhost => hostname(),
	rm => "/bin/rm",
	RsyncOpts => "-avz -e ssh --force --delete-excluded  --one-file-system --delete",
	sendmail => "/usr/sbin/sendmail",
	WeeklyDir => 'weekly',
);

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

## Tool to "rotate" logfiles.
my $CYCLELOG = "/usr/local/bin/rotate -e 15 -j ";	## 15 files, bzipped.

## Where log entries go
my @log;

my $myname = $0;
my $progname = $myname;
$progname =~ s:.*/::;

my %opt;
#---------- ---------- ---------- ---------- ---------- ----------
# Process command-line Arguments + Options
getopts('c:dfp:P:', \%opt) ||  die usage();

if($opt{h}) {
	usage();
	exit 2;
}

my $debug = 0;

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


my ($hourly, $daily, $weekly);

$hourly = $daily = $weekly =0;

if ($opt{c}) { $config_file = $opt{c};}

die "No config file ($config_file)!\n" unless -e $config_file;

#---------- ---------- ---------- ---------- ---------- ----------
# Process config file
my $maincfg = new Config::ApacheFormat
					 duplicate_directives => 'combine',
					 root_directive => 'SnapbackRoot',
					;

$maincfg->read($config_file);

my $cfg = $maincfg;

sub time_to_seconds {
    my($str) = @_;
    my($n, $dur);

    ($n, $dur) = ($str =~ m/(\d+)[\s\0]*(\w+)?/);
    return undef unless defined $n;
    if (defined $dur) {
        local($_) = $dur;
        if (m/^s|sec|secs|second|seconds$/i) {
        }
        elsif (m/^m|min|mins|minute|minutes$/i) {
            $n *= 60;
        }
        elsif (m/^h|hour|hours$/i) {
            $n *= 60 * 60;
        }
        elsif (m/^d|day|days$/i) {
            $n *= 24 * 60 * 60;
        }
        elsif (m/^w|week|weeks$/i) {
            $n *= 7 * 24 * 60 * 60;
        } 
        else {
            return undef; 
        }
    }

    $n;
}

sub send_mail {
    my($body, $opt) = @_;

	$opt ||= {};

	$opt->{to} ||= get_cfg('AdminEmail');

	$opt->{subject} ||= "Snapback results for " . get_cfg('myhost');

	my %non_header = ();
	my @headers;
    
	for(keys %$opt) {
		my $hdr = $_;
		next if $non_header{$_};
		$hdr =~ s/_+/-/g;
		$hdr =~ s/-+/-/g;
		$hdr =~ s/(\w+)/\u$1/g;
		push @headers, "$hdr: $opt->{$_}";
	}
	log_debug("send_mail: to=$opt->{to} subj=$opt->{subject}\n");

    my $ok = 0;
    my $none;
    my $using = get_cfg('SendMail');

    if($using =~ /^(none|Net::SMTP)$/i) {
        $none = 1;
        $ok = 1;
    }

    SEND: {
        last SEND if $none;
        open(MVMAIL,"|$using -t") or last SEND;
        my $mime = '';
        for(@headers) {
            s/\s*$/\n/;
            print MVMAIL $_
                or last SEND;
        }
		print MVMAIL "\n";
        print MVMAIL $body
            or last SEND;
		close MVMAIL or last SEND;
        $ok = ($? == 0);
    }

	if (!$ok) {
        log_error("Unable to send mail using %s\nTo: %s\nSubject: %s\n\n%s",
                $using,
                $opt->{to},
                $opt->{subject},
                $body,
        );
    }

	return $ok;
}

sub is_yes {
	my $val = shift;
	$val = lc $val;
	$val =~ s/\W+//g;
	my %true = qw(
		y      1
		yes    1
		on     1
		true   1
		1      1
	);
	$val = $true{$val} || 0;
	return $val;
}

sub get_cfg {
	my $parm = shift;
	my $block = shift || $cfg;
	my @vals = $block->get($parm);
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

my $myhost = get_cfg('myhost');

if ($opt{d} or get_cfg 'debug' )  {
	$debug = 1;
}

my $cp    = get_cfg('cp')    || 'cp';
my $mv    = get_cfg('mv')    || 'mv';
my $rm    = get_cfg('rm')    || 'rm';
my $rsync = get_cfg('rsync') || 'rsync';

my $r_opts= get_cfg('rsyncopts');

# Sanity-check the config file.
die "Malformed config file: Hourlies must be > 0\n" unless get_cfg('hourlies');

#---------- ---------- ---------- ---------- ---------- ----------
# Set up logging

sub log_arbitrary {
	my ($file, $msg) = @_;
	open TMPLOG, ">> $file"
		or die "Cannot log to file $file: $!\n";
	print TMPLOG $msg;
	close TMPLOG;
}

sub log_error {
	my ($msg, @args) = @_;
	my $logfile = $cfg->get('logfile');
	my $long = length($msg) > 400;

	$msg = $Locale{$msg} if ! $long and defined $Locale{$msg};
	if(ref $msg) {
		my $ref = $msg;
		$msg = $ref->[0];
		@args = @args[ @{ $ref->[1] } ];
	}

	$msg = sprintf($msg, @args) if @args;
	$msg =~ s/[\r\n]*$/\n/ unless $long;
	push @log, $msg;
	log_arbitrary($logfile, $msg);
}

if($debug) {
	my $debuglog = get_cfg('debuglog');
	if($debuglog) {
		open DEBUG, ">> $debuglog"
			or die "Can't open debug log $debuglog: $!\n";
	}
	else {
		open DEBUG, ">&STDERR";
	}
}

sub log_debug {
	return unless $debug;
	my $msg = shift;
	$msg =~ s/\n*$/\n/;
	print DEBUG $msg;
}

my $errors_logged = 0;

my $rsync_log = "/tmp/rsync_log$$";
system ("touch $rsync_log");


log_error "$myname : $myhost\n";
my @start_time = localtime();
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = @start_time;
log_error strftime("begin \@ %H:%M:%S %Y/%m/%d...\n", @start_time );

#---------- ---------- ---------- ---------- ---------- ----------
# Main Body - Loop through the list of clients

my $client_re;
## Check if we have a pattern of clients to apply to
if($opt{p}) {
	$client_re = qr/$opt{p}/
		or die "Bad regex in -p option '$opt{p}'.\n";
}

my $dir_re;
## Check if we have a pattern of client directories to apply to
if($opt{P}) {
	$dir_re = qr/$opt{P}/
		or die "Bad regex in -P option '$opt{P}'.\n";
}

use Data::Dumper;
$Data::Dumper::Terse = 1;

my @backups = $cfg->get('backup');

#print Dumper(\@backups);

for(@backups) {
	if(! ref($_)) {
		die "Bad backup configuration structure.";
	}
	my ($directive, $domain) = @$_;
	if($client_re) {
		next unless $domain =~ $client_re;
	}
	my $domaincfg = $maincfg->block( $directive => $domain );
	$cfg = $domaincfg;
	my @excl = get_cfg('exclude');
#print Dumper(\@excl);

	my @dirs = get_cfg('directory');

	my $host = get_cfg('backuphost') || $domain;
	my $literal = get_cfg('LiteralDirectory');
	for my $d (@dirs) {
		if($dir_re) {
			next unless $d =~ $dir_re;
		}
		$d =~ s:/*$:/: unless $literal;
		do_backup($host, $d, \@excl);
	}

	## Now do the alternative way
	my @blocks = $cfg->get('backupdir');
	push @blocks, $cfg->get('backupdirectory');
	foreach my $bd (@blocks) {
		if(! ref($bd)) {
			die "Bad backup structure.";
		}
		my ($bdom, $bdir) = @$bd;
		if($dir_re) {
			next unless $bdir =~ $dir_re;
		}
		my $blockcfg = $domaincfg->block( $bdom => $bdir );
		$cfg = $blockcfg;
		my @excl = get_cfg('exclude');
#print Dumper(\@excl);
		my @dirs = $bdir;
		my $host = get_cfg('backuphost') || $domain;
		my $literal = is_yes(get_cfg('LiteralDirectory'));
		for my $d (@dirs) {
			$d =~ s:/*$:/: unless $literal;
			do_backup($host, $d, \@excl);
		}
	}
}

## clean up log files
log_error strftime("end \@ %H:%M:%S %Y/%m/%d...\n", localtime() );

## TODO check the rsync log file for errors from rsync
## - set errors_logged if so

my %charges;

## - create new log file, important info at top, rsync detail at bottom
GETLOGINFO: {
	open RSYNC, "< $rsync_log";
	my $client;
	while(<RSYNC>) {
		push @log, $_;
		if(/^client\s+(.*)/) {
			$client = $1;
		}
		elsif(/^wrote\s+\d+\s+bytes\s+read\s+(\d+)\s+bytes/) {
			$charges{$client} += $1;
		}
	}
	close RSYNC;
}

my $charge_time = strftime('%Y%m%d', localtime());
my $clog = get_cfg('ChargeFile');

for(keys %charges) {
	log_arbitrary $clog, sprintf("%s:%s:%d\n", $_, $charge_time, $charges{$_});
}

## email results to admin's
if (get_cfg('AlwaysEmail') || $errors_logged) {
	send_mail(join "", @log);
}

## END

## ---------- ---------- ---------- ---------- ---------- ----------
## ---------- ---------- ---------- ---------- ---------- ----------


## ---------- ---------- ---------- ---------- ---------- ----------
sub usage {
  print <<EOU;
$myname: Rsync/Hard-Link/Snapshot-like backup script.

USAGE: $progname [-c config-file -d ]
	-c config-file : config file (default: /etc/snapback2.conf)
	-d : debug mode (default: Off)
	-f : force backup even if AutoTime says no (default: Off)
	-p : Pattern to include domains/clients on.
	-P : Pattern to include directories on.
EOU
}

## ---------- ---------- ---------- ---------- ---------- ----------
sub do_backup {
	my($fqdn,$dir,$excl) = @_;		## Long form of hostname


	## We want long version since we might have many domains
	my $host = $fqdn;

	my $rotate_all = 0;	## flag for do_rotate routine
	my $hr_dir = get_cfg('HourlyDir');
	my $daily_dir = get_cfg('DailyDir');
	my $weekly_dir = get_cfg('WeeklyDir');
	my $monthly_dir = get_cfg('MonthlyDir');

	my $dest;
	my @destlist =  get_cfg('DestinationList');

	if( @destlist = get_cfg('DestinationList')
		and $destlist[0]
		and lc($destlist[0]) ne 'none'
		)
	{
		log_debug("DestinationList is " . join(" ", @destlist));
		my %dest;
		foreach my $prospect (@destlist) {
			my $prefix = $prospect . "/" . $host . $dir ;
			my $backupdir = $prefix . $hr_dir;
			my $mtime = (stat "$backupdir.0")[9] || 0;
			$dest{$prospect} = $mtime;
		}

		my $actual;
		my $min;
		for (keys %dest) {
			if(! defined $min) {
				$min = $dest{$_};
				$actual = $_;
			}
			elsif($min > $dest{$_}) {
				$min = $dest{$_};
				$actual = $_;
			}
		}
		$dest = $actual;
		log_debug("Selected DestinationList destination $dest");
	}
	else {
		$dest = get_cfg('Destination');
		log_debug("destination from Destination is $dest");
	}

	if(! $dest) {
		log_error("Refuse to do backup for %s%s without destination.", $host, $dir);
		return;
	}

	my $prefix = $dest . "/" . $host . $dir ;
	my $backupdir = $prefix . $hr_dir;

	## ----------
	## STEP 1: check the clock and verify if we are just doing 
	##  the hourly backups, or also the daily/weekly/monthlies.

	## If the timestamp on the current backup dir does not match
	## todays date, then this must be the first run after midnight,
	## so we  check the dailies/weeklies/monthlies also.
	## Not very efficient, since we check this for each backup set
	## that we run, instead of just once for all.  Oh well.

	## Check the file
	my $mtime = (stat "$backupdir.0")[9];
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($mtime);
	my $backup_date = $yday;

    my $hr_backup = get_cfg('Hourlies');

	if($hr_backup < 1) {
		log_error("Hourly backup must be greater than or equal to 1.");
		return;
	}

	## This mode doesn't back up unless the formula
	## 
	##    (24 / $hr_backup - 1) * 60 * 60 > time() - $mtime
	## 
	## is satisfied.
	if(! $opt{f} and get_cfg('AutoTime')) {
		my $must_hours = 24 / $hr_backup - 0.5;
		my $must_exceed = $must_hours * 60 * 60;
		if(my $min_exceed = get_cfg('MustExceed')) {
			$min_exceed = time_to_seconds($min_exceed);
			if($min_exceed > $must_exceed) {
				$must_hours = sprintf "%.1f", $min_exceed / 60 / 60;
				$must_exceed = $min_exceed;
				log_debug("Setting minimum exceed time $must_hours hours.");
			}
		}
		my $interval = time() - $mtime;
		unless ($interval > $must_exceed) {
			my $real_hours = sprintf "%.1f", $interval / 60 / 60;
			my $msg = sprintf(	
						"Skipping backup of %s%s, only %s hours old, want %s hours",
						$fqdn, $dir, $real_hours, $must_hours,
					  );
			log_debug($msg);
			return;
		}
	}

    log_debug "DEBUG: backup_date=$backup_date dir=$backupdir\n";

	## Check the clock
	($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

	log_debug "DEBUG: yday=$yday dir=$backupdir\n";

    ## we assume (dangerous I know) that if the timestamp on the directory
    ## is not the same date as today, then it must be yesterday.  In any
    ## case, this is then the first run after midnight today.
    my ($do_dailies, $do_weeklies, $do_monthlies );
	if ($backup_date != $yday)  {
		$do_dailies = 1;	
		log_debug "DEBUG: do_dailies=true\n";
		
		if ($mday == 1) { $do_monthlies = 1;}  ## ... And first of month.
		if ($wday == 0) { $do_weeklies = 1;}   ## ... And First of Week.
	}

    ## ----------
    ## STEP 2: housekeeping - is the backup destination directory 
    ##  set up? Make it if CreateDir option is set.
	unless (-d $prefix) {
		if (-e $prefix) {
			die "Destination $prefix is not a directory\n";
		}
		elsif( get_cfg('CreateDir') ) {
			File::Path::mkpath($prefix)
				or die "Unable to make directory $prefix";
		}
		else {
			die "Missing destination $prefix\n";
		}
	}

	## Process the exclusions
	my $e_opts;
	if($excl) {
		my @excl;
		if(ref($excl) ne 'ARRAY') {
			$excl  = [ split /[\s,]+/, $excl ];
		}
		for (@$excl) {
			push @excl, qq{--exclude=\\"$_\\"};
		}
		$e_opts = join " ", @excl;
	}

  ## ----------
  ## STEP 3: Process Hourly backups

  ## 3.1: Rotate older backups

  log_debug "DEBUG: do_rotate($hr_backup,$backupdir)";
  do_rotate($hr_backup, $backupdir, $rotate_all);

  ## 3.2: Hard link from the newest backup: 
  if (-d "$backupdir.0") { 
    log_debug "DEBUG: Hard Link newest backup\n";
    system("$cp -al $backupdir.0 $backupdir.1") == 0
      or die "FAILED: $cp -al $backupdir.0 $backupdir.1";
  } 	

  ## 3.3:
  ## Now rsync from the client dir into the latest snapshot 
  ## (notice that rsync behaves like cp --remove-destination by
  ## default, so the destination is unlinked first.  If it were not
  ## so, this would copy over the other snapshot(s) too!

  log_debug "DEBUG: $rsync $r_opts $fqdn:$dir $backupdir.0\n";
  log_arbitrary $rsync_log, "client $fqdn\n";
  log_arbitrary $rsync_log, "--\n$rsync $r_opts $e_opts $fqdn:$dir $backupdir.0\n\n"; 
  system ("$rsync $r_opts $fqdn:$dir $backupdir.0 >> $rsync_log") == 0
    or die "FAILED: $rsync $r_opts $fqdn:$dir $backupdir.0 >> $rsync_log";

  # update the mtime of hourly.0 to reflect the snapshot time
  system ("touch $backupdir.0");

  ## ----------
  ## STEP 4: Process Daily/Weekly/Monthly backups
  ## -- simpler than above, the rsync is already done.  We just need
  ## to "rotate" the old backups, and then hard link to the
  ## newest hourly backup from yesterday.  NOTE that will be the
  ##  .1 version, not the .0 version -- the .0 version is from today.

  my $yesterdays_hourly = "$backupdir.0";
  $rotate_all=1;	## flag for do_rotate routine

  ## Daily Backups - similar steps to above, rotate, hard link
  if ($do_dailies) {
    $backupdir = $prefix . $daily_dir;
    do_rotate(get_cfg('Dailies'), $backupdir, $rotate_all);

    ## No rsync necessary, just hard-link from the most-recent hourly.
    if (-d "$yesterdays_hourly") { 
      system("$cp -al $yesterdays_hourly $backupdir.0") == 0
      or die "FAILED: $cp -al $yesterdays_hourly $backupdir.0";
    } 	
  }

  ## Weekly Backups
  if ($do_weeklies) {
    $backupdir = $prefix . $weekly_dir;
    do_rotate(get_cfg('Weeklies'), $backupdir, $rotate_all);
    if (-d "$yesterdays_hourly") { 
      system("$cp -al $yesterdays_hourly $backupdir.0") == 0
      or die "FAILED: $cp -al $yesterdays_hourly $backupdir.0";
    } 	
  }

  ## Monthly Backups
  if ($do_monthlies) {
    $backupdir = $prefix . $monthly_dir;
    do_rotate(get_cfg('Monthlies'), $backupdir, $rotate_all);
    if (-d "$yesterdays_hourly") { 
      system("$cp -al $yesterdays_hourly $backupdir.0") == 0
      or die "FAILED: $cp -al $yesterdays_hourly $backupdir.0";
    } 	
  }
}


## ---------- ---------- ---------- ---------- ---------- ----------
# Age/rotate the old backup directories.
# -- the backup dirs are named like: back.0, back.1, back.2
# -- so the count is 3 (3 backups)
# -- we deleted the oldest (back.2) and move the next-oldest up
#    so back.2 becomes back.3, back.1 becomes, back.2, etc.
# -- then make a hard link from back.0 to back.1
# $maxbackups = number of copies they keep,  we count from Zero,
# so for 4 copies, we'd have 0,1,2,3.  In the comments below
# we'll give examples assuming a $maxbackup of 4.

sub do_rotate {
  my ($maxbackups, $dir, $rotate_all) = @_;
  
  ## Step 1: nothing to do if they're only keeping 1 copy
  if (($maxbackups == 1) && ($rotate_all==0)) { return ; }

  ## Step 2: delete the oldest copy.  (eg: $dir.3)
  my $count = $maxbackups - 1;
  my $countplus = $maxbackups - 1;

  if (-d "$dir.$count") {
    log_debug "DEBUG: $rm -rf $dir.$count\n";
    system("$rm -rf $dir.$count") == 0
      or die "FAILED: $rm -rf $dir.$count";
    }
  $count--;

  ## Step 3: rotate/rename the "middle" copies (eg: $dir.1,2,3)
  ## DO NOTHING with the most recent backup (eg: $dir.0) of hourlies.
  ## Rotate same as the rest for dailies/weeklies/etc.

  my $smallest;

  if ($rotate_all) { $smallest = 0 } else {$smallest = 1};

  while ($count >= $smallest) {
    #log_debug "DEBUG: count = $count";
    if (-d "$dir.$count") { 
      log_debug "DEBUG: $mv  $dir.$count $dir.$countplus\n";
      system("$mv $dir.$count $dir.$countplus" ) == 0
      	or die "FAILED: $mv $dir.$count $dir.$countplus";
    }
    $count--; $countplus--;
  }

}

## ---------- ---------- ---------- ---------- ---------- ----------
## Need a local "die" equivalent function, to 
## print an error and clean up, and ensure that the
## admin's are emailed results.  Tie into the normal end-of-program?


