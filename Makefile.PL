use 5.006001;
use ExtUtils::MakeMaker;
use Data::Dumper;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

sub initialize {
	my @scripts = map { "scripts/$_" } qw(
		snap_charge
		snapback_loop
		snapback2
	);
	my %X;
	$X{INSTALLDIRS}	= "perl";
	$X{clean} = {
		FILES => join(" ", 'scripts/initp.pl', @scripts, 'b_target', 'b_source'),
	};
	$X{EXE_FILES}	= [ @scripts ];
	$X{PL_FILES}	= { 'relocate.util' => [ @scripts ] };
	mk_initp(\%X);
	return \%X;
}

sub mk_initp {
	my ($ref) = @_;
	local($Data::Dumper::Terse);
	$Data::Dumper::Terse = 1;
	open (INITP, ">scripts/initp.pl")
		or die "Can't write initp.pl: $!\n";
	print INITP '$MV::Self = ';
	print INITP Dumper($ref);
	print INITP ";\n1;";
	close INITP;
}

WriteMakefile(
    NAME		    => 'Snapback2',
    VERSION_FROM	=> 'scripts/snapback2.PL', # finds $VERSION
	'MAN1PODS' => {
		'scripts/snapback2'    => '$(INST_MAN1DIR)/snapback2.$(MAN1EXT)',
		'scripts/snapback_loop'    => '$(INST_MAN1DIR)/snapback_loop.$(MAN1EXT)',
		'scripts/snap_charge'    => '$(INST_MAN1DIR)/snap_charge.$(MAN1EXT)',
    },
	EXE_FILES => [],
	PL_FILES => {},
	PM => { 'Backup/Snapback.pm' => '$(INST_LIBDIR)/Backup/Snapback.pm'},
	CONFIGURE => \&initialize,
    PREREQ_PM		=> { Config::ApacheFormat => 1.2 }, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT => 'Snapback2 -- automated rsync backup',
       AUTHOR     => 'Mike Heins <snapback2@perusion.org>') : ()),
);
