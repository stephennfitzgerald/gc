package GC::GC_app;
use strict;
use warnings;
use Dancer2;
use DBI;
use Carp;
use Storable qw(nfreeze thaw);
use Data::Dumper;

our $VERSION = '0.1';
our $db_name = 'gencode_sf5_gc';
our $file_dir = 'public/uploaded_files'; 


get '/' => sub {
  my $species_lst = get_species();
  my $feature_lst = get_features();

  template 'index', {
   'species_lst'    => $species_lst,
   'feature_lst'    => $feature_lst,
   'get_input_data_url' => uri_for('/get_input_data'),
  };

};

post '/get_input_data' => sub {

  my $species_lst = get_species();
  my $feature_lst = get_features();
  my $dbh = get_schema();
  my (%NOL, %SEEN);

  if(my $sel_species = param('selected_species')) {
   if(my $sel_feature = param('selected_feature')) {
    if(my $sel_file = upload('selected_file')) {
     my $sel_file_name = $sel_file->tempname;
     $sel_file_name =~ s/.*\///xms;
     $sel_file->copy_to("$file_dir");
     open IN, "$file_dir/$sel_file_name" or croak("can't open file $file_dir/$sel_file_name");
     my $regions_sth = $dbh->do("CALL get_feature(?,?)", undef, );
     while(my $line = <IN>) {
      next if $line=~/##/;
      chomp($line);
      my($sr,$fr,$to) = split"\t",$line;
      $sr=~s/chr//i;
      my $fp = $sr . $fr . $to;
      if(exists($SEEN{ $fp })) {
       next;
      } else {
       $SEEN{ $fp }++;
      }
     }  
    }
   }
  }
 template 'index', {
  'species_lst'    => $species_lst,
  'feature_lst'    => $feature_lst,
  'get_input_data' => uri_for('/get_input_data'),
 };

};

sub get_features {
 my $dbh = get_schema();
 my $ft_sth = $dbh->prepare('SELECT * FROM FeatureView');
 $ft_sth->execute;
 my $feature_lst = $ft_sth->fetchall_arrayref;
 unshift @{ $feature_lst }, 'select';
 return $feature_lst;
}

sub get_species {
  my $dbh = get_schema();
  my $sp_sth = $dbh->prepare('SELECT * FROM SpeciesView');
  $sp_sth->execute;
  my $species_lst = $sp_sth->fetchall_arrayref;
  unshift @{ $species_lst }, 'select';
  return $species_lst;
}

sub get_schema { 
 my ( $host, $port ) = ( $ENV{'GC_HOST'}, $ENV{'GC_PORT'} );
 return DBI->connect( "DBI:mysql:$db_name;host=$host;port=$port",
    $ENV{'GC_USER'}, $ENV{'GC_PASS'} )
    or die "Cannot connect to database $db_name\n$?";
}

true;
