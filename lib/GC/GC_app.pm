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
our $set_id = 'B';


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
  my (%GEN, %SEEN);

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
      push@{ $GEN{$sr} }, [$fr, $to, $set_id];
     }
     ## merge overlapping coords from the input file
     foreach my $sr(keys %GEN) {
      for(my$i=0;$i<@{ $GEN{ $sr } }-1;$i++) {
       if( $GEN{ $sr }->[$i]->[1] >= $GEN{ $sr }->[$i+1]->[0] ) { 
        if( $GEN{ $sr }->[$i]->[1] < $GEN{ $sr }->[$i+1]->[1] ) { 
         $GEN{ $sr }->[$i]->[1] = $GEN{ $sr }->[$i+1]->[1];
        }   
        splice @{ $GEN{ $sr } }, $i+1, 1;
        $i--;
       }
      }
     }
     ## merge the input coords with the feature set from the db
     foreach my $sr(keys %GEN) {
      push@{ $GEN{$sr} }, @{ $data_str->{$sr} };
      @{ $GEN{$sr} } = sort {$a->[0] <=> $b->[0]} @{ $GEN{$sr} };
     }
     
     foreach my $sr(keys %GEN) {
      for(my$i=0;$i<@{ $GEN{ $sr } } - 1;$i++) {
       next if( $GEN{ $sr }->[$i]->[2] eq $GEN{ $sr }->[$i+1]->[2] );
       if( $GEN{ $sr }->[$i]->[1] >= $GEN{ $sr }->[$i+1]->[0] ) {
        if( $GEN{ $sr }->[$i]->[1] <= $GEN{ $sr }->[$i+1]->[1] ) {
         my $ol_str = $GEN{ $sr }->[$i+1]->[0];
         my $ol_end = $GEN{ $sr }->[$i]->[1];
         if( $GEN{ $sr }->[$i]->[0] == $ol_str ) {
          $GEN{ $sr }->[$i]->[2] = 'O';
          if( $GEN{ $sr }->[$i+1]->[1] == $ol_end ) { ## complete overlap (4)
           splice @{ $GEN{ $sr } }, $i+1, 1;
          } else { ## (3)
           $GEN{ $sr }->[$i]->[1] = $ol_str - 1;
           $GEN{ $sr }->[$i+1]->[0] = $ol_end + 1;
          }
         } else { ## partial overlap (1) + (2)
          $GEN{ $sr }->[$i]->[1] = $ol_str - 1;
          $GEN{ $sr }->[$i+1]->[0] = $ol_end + 1;
          splice @{ $GEN{ $sr } }, $i, 0, [ $ol_str, $ol_end, 'O' ];
         }
        } else { ## overlap extends past second element (5)
         $GEN{ $sr }->[$i+1]->[2] = 'O';
         $GEN{ $sr }->[$i]->[1] = $GEN{ $sr }->[$i+1]->[0] - 1;
         splice @{ $GEN{ $sr } }, $i+1, 0, [ ($GEN{ $sr }->[$i+1]->[1] + 1), $GEN{ $sr }->[$i]->[1], $GEN{ $sr }->[$i]->[2] ];
         $GEN{ $sr }->[$i]->[1] = $GEN{ $sr }->[$i+1]->[0] - 1;
         $i++;
       }  
      }
     }
    }
   }
  }
 }

print Dumper \%GEN;
 
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
