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
our $public_dir = './public/';
our $out_file_dir = 'uploaded_files'; 
our $set_id = 'B'; # id for input data ( feature data is 'A' )
our @file_formats = ('select', '0-based (BED)', '1-based');

get '/' => sub {

  my $species_lst = get_species();
  my $feature_lst = get_features();

  template 'index', {
   'species_lst'    => $species_lst,
   'feature_lst'    => $feature_lst,
   'file_formats'   => \@file_formats,
   'get_input_data_url' => uri_for('/get_input_data'),
  };

};

post '/get_input_data' => sub {

  my $dbh = get_schema();
  my (%GEN, %SEEN, %CV, %STATS, $sel_file_name, $sel_feature, $sel_species, $sel_file_format, $out_file);

  if($sel_species = param('selected_species')) {
   my($species_name, $assembly_name) = split'::', $sel_species;
   if($sel_feature = param('selected_feature')) {
    my $binary_str = $dbh->selectrow_array("SELECT feature
                                            FROM feature ft 
                                            INNER JOIN assembly ass
                                            WHERE ft.feature_type = \"$sel_feature\" 
                                            AND ass.name = \"$assembly_name\"");
    my $data_str = thaw $binary_str;

    %CV = ( 'A' => $sel_feature, 'B' => 'input data', 'O' => 'overlap' );
    %STATS = ( 'A' => 0, 'B' => 0, 'O' => 0 );
    $sel_file_format = param('selected_file_format');

    if(my $sel_file = upload('selected_file')) {
     my $copy_file_path = $public_dir . $out_file_dir; 
     $sel_file_name = $sel_file->tempname;
     $sel_file_name =~ s/.*\///xms;
     $sel_file->copy_to("$copy_file_path");
     open IN, "$copy_file_path/$sel_file_name" or croak("can't open file $copy_file_path/$sel_file_name");
     while(my $line = <IN>) {
      next if $line=~/##/;
      chomp($line);
      my($sr,$fr,$to) = split"\t",$line;
      ## if the input is in BED format - increment the first base
      $fr = $sel_file_format eq '0-based (BED)' ? $fr + 1 : $fr;
      $sr=~s/chr//i;
      my $fp = $sr . $fr . $to;
      if(exists($SEEN{ $fp })) {
       next;
      } else {
       $SEEN{ $fp }++;
      }
      push@{ $GEN{$sr} }, [$fr, $to, $set_id, undef];
     }
     close IN;

     foreach my $sr(keys %GEN) {
      @{ $GEN{$sr} } = sort {$a->[0] <=> $b->[0]} @{ $GEN{$sr} };
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
      if(exists( $data_str->{$sr} )) {
       push@{ $GEN{$sr} }, @{ $data_str->{$sr} };
      }
     }
     foreach my $sr(keys %GEN) {
      @{ $GEN{$sr} } = sort {$a->[0] <=> $b->[0]} @{ $GEN{$sr} };
     }
     ## check for overlaps between the feature set and the input data 
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
           # try to keep any feature data annotation
#           $GEN{ $sr }->[$i]->[3] = $GEN{ $sr }->[$i]->[3] ? $GEN{ $sr }->[$i]->[3] : $GEN{ $sr }->[$i+1]->[3];
           splice @{ $GEN{ $sr } }, $i+1, 1;
          } else { ## (3)
           $GEN{ $sr }->[$i]->[1] = $ol_end;
           $GEN{ $sr }->[$i+1]->[0] = $ol_end + 1;
          }
         } else { ## partial overlap (1) + (2)
          $GEN{ $sr }->[$i]->[1] = $ol_str - 1;
          if( $GEN{ $sr }->[$i+1]->[1] > $ol_end ) {
           $GEN{ $sr }->[$i+1]->[0] = $ol_end + 1;
          } else {
           splice @{ $GEN{ $sr } }, $i+1, 1;
          }
          splice @{ $GEN{ $sr } }, $i+1, 0, [ $ol_str, $ol_end, 'O' ];
         }
        } else { ## overlap extends past second element (5)
         $GEN{ $sr }->[$i+1]->[2] = 'O';
         my $temp_end = $GEN{ $sr }->[$i]->[1];
         $GEN{ $sr }->[$i]->[1] = $GEN{ $sr }->[$i+1]->[0] - 1;
         my $anno = $GEN{ $sr }->[$i]->[3] ? $GEN{ $sr }->[$i]->[3] : $GEN{ $sr }->[$i+1]->[3];
         splice @{ $GEN{ $sr } }, $i+2, 0, [ ($GEN{ $sr }->[$i+1]->[1] + 1), $temp_end, $GEN{ $sr }->[$i]->[2], $anno ];
         $GEN{ $sr }->[$i]->[1] = $GEN{ $sr }->[$i+1]->[0] - 1;
         if($GEN{ $sr }->[$i]->[1] < $GEN{ $sr }->[$i]->[0]) { ## start of first == start of second element
          splice @{ $GEN{ $sr } }, $i , 1;
         } else {
          $i++;
         }
       }  
      }
     }
    }
   }
  }
 }

 if( keys %GEN ) {
  $out_file = $public_dir . $out_file_dir . "/$sel_file_name" . '.bed.txt';
  open OUT, ">$out_file" or croak("can't open file $out_file"); 
  my $subtr = $sel_file_format eq '0-based (BED)' ? 1 : 0;
  foreach my $sr( keys %GEN ) {
   foreach my $loc( @{ $GEN{ $sr } } ) {
    $STATS{ $loc->[2] } += $loc->[1] - $loc->[0] + 1;
    print OUT join("\t", $sr, ($loc->[0] - $subtr), $loc->[1], $CV{ $loc->[2] }), "\n";
   }
  }
  close OUT;
 }

 if( keys %STATS ) {
  $STATS{ 'AT' } = $STATS{ 'A' } + $STATS{ 'O' }; # total number of feature bases 
  $STATS{ 'AP' } = sprintf "%.2f", ( $STATS{ 'O' } / $STATS{ 'AT' } ) * 100; # % of overlapping feature bases
  $STATS{ 'BT' } = $STATS{ 'B' } + $STATS{ 'O' }; # total number of input bases
  $STATS{ 'BP' } = sprintf "%.2f", ( $STATS{ 'O' } / $STATS{ 'BT' } ) * 100; # % of overlapping input bases
  $STATS{ 'AN' } = sprintf "%.2f", ( $STATS{ 'A' } / $STATS{ 'AT' } ) * 100; # % of non-overlapping feature bases
  $STATS{ 'BN' } = sprintf "%.2f", ( $STATS{ 'B' } / $STATS{ 'BT' } ) * 100; # % of non-overlapping input bases
 }

$out_file = $out_file_dir . "/$sel_file_name" . '.bed.txt';
 
 template 'stats', {
  'stats'          => \%STATS,
  'out_file'       => "$out_file",
  'sel_feat'       => "$sel_feature",
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
