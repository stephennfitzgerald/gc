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
   my($species_name, $assembly_name) = split'::', $sel_species;
   if(my $sel_feature = param('selected_feature')) {
    my $binary_str = $dbh->selectrow_array("SELECT feature
                                            FROM feature ft 
                                            INNER JOIN assembly ass
                                            WHERE ft.feature_type = \"$sel_feature\" 
                                            AND ass.name = \"$assembly_name\"");
    my $data_str = thaw $binary_str;
    
    if(my $sel_file = upload('selected_file')) {
     my $sel_file_name = $sel_file->tempname;
     $sel_file_name =~ s/.*\///xms;
     $sel_file->copy_to("$file_dir");
     open IN, "$file_dir/$sel_file_name" or croak("can't open file $file_dir/$sel_file_name");
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
      my $feature_range = $data_str->{ $sr };
      if($feature_range) {
       for(my$i=0;$i<@{ $feature_range };$i++) {
        my($feat_from, $feat_to) = ($feature_range->[$i]->[0], $feature_range->[$i]->[1]); 
        if($fr <= $feat_to && $to >= $feat_from) { # overlap
         my $end_ol = $to - $feat_to > 0 ? $to : $feat_from - 1;
         my $str_ol = $feat_from - $fr > 0 ? $fr : $feat_to + 1;
         if($end_ol == ($feat_from - 1) && $str_ol == ($feat_to + 1)) {
          last; # skip - input frag is fully covered by a feature
         }
         elsif($str_ol == $fr && $end_ol == ($feat_from - 1)) { # 5' end of feature overlaps 3' end of frag
          push@{ $NOL{ $sr } }, [$str_ol, $end_ol];
         }
         elsif($str_ol == ($feat_to + 1) && $end_ol == $to) { # 3' end of feature overlaps 5' end of frag
          $fr = $str_ol;
         }
         elsif($str_ol == $fr && $end_ol == $to) { # split frag  - feature is fully covered by frag 
          push@{ $NOL{ $sr } }, [$fr, $feat_from - 1];
          $fr = $feat_to + 1;
         }
        }
        elsif($feat_from > $to) { # no overlap - keep
         push@{ $NOL{ $sr } }, [$fr, $to];
         last;
        }
       }
      }
     }
    }
   }
  }
print Dumper \%NOL;
 
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
