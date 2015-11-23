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
our $set_id = 'B'; # id for input data 
our $feat_id = 'A'; # id for feature data
our @file_formats = ('select', '0-based (BED)', '1-based');
our @return_type = ('select', 'novel', 'all');


get '/' => sub {

 template 'index', {
  'check_for_overlaps_url' => uri_for('/check_for_overlaps'), 
  'upload_a_file_url'      => uri_for('/upload_a_file'),
  'delete_a_feature_url'   => uri_for('/delete_a_feature'),
 };
};

get '/delete_a_feature' => sub {
 
 my $dbh = get_schema();
 if(my $feature_id = param('feat_id')) {
   $dbh->do('CALL DeleteFeature(?)', undef, $feature_id);
 }
 my $sfv_sth = $dbh->prepare("SELECT * FROM SpeciesFeatureView");
 $sfv_sth->execute;
 my $species_features = $sfv_sth->fetchall_arrayref;
 unshift @{ $species_features }, 'select';

 template 'delete_a_feature', {
  'species_features' => $species_features,
  'delete_a_feature_url'   => uri_for('/delete_a_feature'),
 };
};

post '/upload_a_file' => sub {
 
 my $species_lst = get_species();
 my $feature_lst = get_features();
 my $sff = param('selected_file_format');
 my $ifn = param('input_feature_name');
 my $sas = param('assembly_id'); 
 my $template = 'upload_a_file';
 my $sel_file = upload('selected_file');
 my $err_str = 0;
 my $add_to_fr = 0;

 if( $sff && $ifn && $sas && $sel_file ) {
  my $dbh = get_schema();
  $template = 'index';
  my $file_info = open_file($sel_file);
  my $fh = $file_info->[0];
  $add_to_fr = $sff eq '0-based (BED)' ? $add_to_fr + 1 : $add_to_fr;
  my %A;
  while(my $line = <$fh>) {
   next if $line=~/^#/;
   chomp $line;
   my($sr,$fr,$to,$ty)=split"\t",$line;
   $fr += $add_to_fr;
   push@{ $A{$sr} }, [ $fr, $to, $feat_id, $ifn ];
  }

  foreach my $sr(keys %A) {
   @{ $A{$sr} } = sort {$a->[0] <=> $b->[0]} @{ $A{$sr} };
   for(my$i=0;$i<@{ $A{ $sr } }-1;$i++) {
    if( $A{ $sr }->[$i]->[1] >= $A{ $sr }->[$i+1]->[0] ) { 
     if( $A{ $sr }->[$i]->[1] < $A{ $sr }->[$i+1]->[1] ) { 
      $A{ $sr }->[$i]->[1] = $A{ $sr }->[$i+1]->[1];
     }   
     splice @{ $A{ $sr } }, $i+1, 1;
     $i--;
    }
   }
  }
  my $blob = nfreeze \%A;
  my $chk_sth = $dbh->prepare("CALL CheckFeature(?,?)");
  $chk_sth->execute($sas, "$ifn");
  my $ret_chk = $chk_sth->fetchall_arrayref;
  if( ! $ret_chk->[0] ) { 
   $dbh->do('INSERT INTO feature (assembly_id, feature_type, feature) VALUES(?,?,?)', undef, $sas, "$ifn", $blob);
  } else {
   $err_str = 1;
   $template = 'upload_a_file';
  }
 }

 template "$template", {
  'err_str'        => $err_str,
  'species_lst'    => $species_lst,
  'feature_lst'    => $feature_lst,
  'file_formats'   => \@file_formats,
  'return_type'    => \@return_type,
  'check_for_overlaps_url' => uri_for('/check_for_overlaps'),
  'upload_a_file_url'      => uri_for('/upload_a_file'),
 };
};

get '/check_for_overlaps' => sub {

  my $species_lst = get_species();
  my $feature_lst = get_features();

  template 'check_for_overlaps', {
   'species_lst'    => $species_lst,
   'feature_lst'    => $feature_lst,
   'file_formats'   => \@file_formats,
   'return_type'    => \@return_type,
   'get_input_data_url' => uri_for('/get_input_data'),
  };

};

post '/get_input_data' => sub {

  my $dbh = get_schema();
  my (%GEN, %SEEN, %CV, %STATS, $sel_file_name, $sel_feature, $assembly_id, $sel_file_format, $out_file);
  my $ass_err = 0;
  my $template = 'stats';
  my $species_lst = get_species();
  my $feature_lst = get_features();

  if($assembly_id = param('assembly_id')) {
   if($sel_feature = param('selected_feature')) {
    my $binary_str = $dbh->selectrow_array("SELECT feature
                                            FROM feature ft 
                                            INNER JOIN assembly ass
                                            ON ass.id = ft.assembly_id
                                            WHERE ft.feature_type = \"$sel_feature\" 
                                            AND ass.id = $assembly_id");
    if( $binary_str ) {
     my $data_str = thaw $binary_str;
 
     %CV = ( 'A' => $sel_feature, 'B' => 'input data', 'O' => 'overlap' );
     %STATS = ( 'A' => 0, 'B' => 0, 'O' => 0 );
     $sel_file_format = param('selected_file_format');
 
     if(my $sel_file = upload('selected_file')) {
      my $file_info = open_file($sel_file);
      my $fh = $file_info->[0];
      $sel_file_name = $file_info->[1];
      while(my $line = <$fh>) {
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
       push@{ $GEN{$sr} }, [$fr, $to, $set_id, q{}];
      }
      close $fh;
 
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
          splice @{ $GEN{ $sr } }, $i+2, 0, [ ($GEN{ $sr }->[$i+1]->[1] + 1), $temp_end, $GEN{ $sr }->[$i]->[2] ];
          $GEN{ $sr }->[$i]->[1] = $GEN{ $sr }->[$i+1]->[0] - 1;
          if($GEN{ $sr }->[$i]->[1] < $GEN{ $sr }->[$i]->[0]) { ## start of first == start of second element
           splice @{ $GEN{ $sr } }, $i , 1;
          } else {
           $i++;
          }
        }  
       }
      }
      for(my$j=0;$j<@{ $GEN{ $sr } };$j++) {
       if(! $GEN{ $sr }->[$j]->[2] ){
        splice @{ $GEN{ $sr } }, $j , 1;
       }
      }
     }
    }
   }
   else {
    $ass_err = 1;
    $template = 'check_for_overlaps';
   }
  }
 }

 if(! $ass_err ) {
  if( keys %GEN ) {
   $out_file = $public_dir . $out_file_dir . "/$sel_file_name" . '.bed.txt';
   open OUT, ">$out_file" or croak("can't open file $out_file"); 
   my $subtr = $sel_file_format eq '0-based (BED)' ? 1 : 0;
   foreach my $sr( keys %GEN ) {
    for(my$i=0;$i<@{ $GEN{ $sr } };$i++) {
     if($i == 0 && scalar@{ $GEN{ $sr } } > 1) { # first elemen and there are > 1 elements
      if( $GEN{ $sr }->[$i]->[2] eq 'B' ) {
       if( ( $GEN{ $sr }->[$i]->[1] + 1 ) == $GEN{ $sr }->[$i+1]->[0] ) {
        $GEN{ $sr }->[$i]->[3] = 'extension';
       } else {
        $GEN{ $sr }->[$i]->[3] = 'novel';
       }
      }
      else {
       $GEN{ $sr }->[$i]->[3] = q{};
      }
     }
     elsif($i == scalar@{ $GEN{ $sr } } - 1 && scalar@{ $GEN{ $sr } } > 1) { # last element and there are > 1 elements
      if( $GEN{ $sr }->[$i]->[2] eq 'B' ) { 
       if( ( $GEN{ $sr }->[$i]->[0] - 1 ) == $GEN{ $sr }->[$i-1]->[1] ) {
        $GEN{ $sr }->[$i]->[3] = 'extension';
       } else {
        $GEN{ $sr }->[$i]->[3] = 'novel';
       }
      }
      else {
       $GEN{ $sr }->[$i]->[3] = q{};
      }
     } 
     elsif(scalar@{ $GEN{ $sr } } > 1) { # not the first or last element
      if( $GEN{ $sr }->[$i]->[2] eq 'B' ) {
       if( ( $GEN{ $sr }->[$i]->[0] - 1 ) == $GEN{ $sr }->[$i-1]->[1] || ( $GEN{ $sr }->[$i]->[1] + 1 ) == $GEN{ $sr }->[$i+1]->[0] ) {
        $GEN{ $sr }->[$i]->[3] = 'extension';
       } else {
        $GEN{ $sr }->[$i]->[3] = 'novel';
       }
      }
      else {
       $GEN{ $sr }->[$i]->[3] = q{};
      }
     }
     else { # there is only one element
      if( $GEN{ $sr }->[$i]->[2] eq 'B' ) {
       $GEN{ $sr }->[$i]->[3] = 'novel';
      }
      else {
       $GEN{ $sr }->[$i]->[3] = q{};
      }
     }
    }   
   }
   my $ret_type = param('return_type');
   foreach my $sr( keys %GEN ) {
    foreach my $loc( @{ $GEN{ $sr } } ) {
     $STATS{ $loc->[2] } += $loc->[1] - $loc->[0] + 1;
     if( $ret_type eq 'all' ) { # print all results 
      print OUT join("\t", $sr, ($loc->[0] - $subtr), $loc->[1], $CV{ $loc->[2] }, $loc->[3]), "\n";
     }  
     elsif( $ret_type eq 'novel' && ( $loc->[3] eq 'extension' || $loc->[3] eq 'novel' )) { # only print the novel bits
      print OUT join("\t", $sr, ($loc->[0] - $subtr), $loc->[1], $CV{ $loc->[2] }, $loc->[3]), "\n";
     }
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
 }
 
 template "$template", {
  'species_lst'    => $species_lst,
  'file_formats'   => \@file_formats,
  'feature_lst'    => $feature_lst,
  'return_type'    => \@return_type,
  'stats'          => \%STATS,
  'out_file'       => "$out_file",
  'sel_feat'       => "$sel_feature",
  'ass_err'        => $ass_err,
  'check_for_overlaps_url' => uri_for('/check_for_overlaps'),
 };

};

sub open_file {
 my $file_to_open = shift;
 my $copy_file_path = $public_dir . $out_file_dir;
 my $sel_file_name = $file_to_open->tempname;
 $sel_file_name =~ s/.*\///xms;
 $file_to_open->copy_to("$copy_file_path");
 open my $fileHandle, q{<}, "$copy_file_path/$sel_file_name"
   or die qq{open: $file_to_open: $!\n};
 return [ $fileHandle, $sel_file_name ];
}

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
