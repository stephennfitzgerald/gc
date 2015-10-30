use strict;
use warnings;
use DBI;
use Storable qw(nfreeze thaw);
use Data::Dumper;
use IO::Compress::Gzip qw(gzip $GzipError);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);

my %H;

my $dbh = get_schema();

while(<>){
 chomp;
 my($name,$fr,$to,$set_id,$biotype) = split"\t",$_;
 push@{ $H{ $name } }, [$fr,$to,$set_id,$biotype];
}

my $blob = nfreeze \%H;
my ($zblob, $zunblob);
#gzip \$blob => \$zblob;


$dbh->do('INSERT INTO feature (assembly_id, feature_type, feature) VALUES(?,?,?)', undef, 1, 'exon', $blob);


my $bs = $dbh->selectrow_array("select feature from feature");

#gunzip \$bs => \$zunblob;

my $data_str = thaw $bs;

print Dumper $data_str;

sub get_schema { 
 my $db_name = 'gencode_sf5_gc';
 my ( $host, $port ) = ( $ENV{'GC_HOST'}, $ENV{'GC_PORT'} );
 return DBI->connect( "DBI:mysql:$db_name;host=$host;port=$port",
    $ENV{'GC_USER'}, $ENV{'GC_PASS'} )
    or die "Cannot connect to database $db_name\n$?";
}
# 
