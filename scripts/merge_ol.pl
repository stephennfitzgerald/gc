use strict;
use warnings;
use Data::Dumper;

my%A;

while(<>){
 chomp;
 my($sr,$fr,$to,$ty)=split"\t",$_;
 push@{ $A{$sr} }, [$fr, $to, $ty];
}

foreach my $sr(keys %A) {
 for(my$i=0;$i<@{ $A{ $sr } }-1;$i++) {
  if( $A{ $sr }->[$i]->[1] >= $A{ $sr }->[$i+1]->[0] ) {
   if( $A{ $sr }->[$i]->[1] < $A{ $sr }->[$i+1]->[1] ) {
    $A{ $sr }->[$i]->[1] = $A{ $sr }->[$i+1]->[1];
   }
#   push @{ $A{ $sr }->[$i]->[3] }, @{ $A{ $sr }->[$i+1]->[3] };
   splice @{ $A{ $sr } }, $i+1, 1;
   $i--;
  }
 }
}

foreach my $sr(sort keys %A) {
 foreach my $ele(@{ $A{$sr} }) {
#  my %E;
#  foreach my $anno(@{ $ele->[3] }) {
#   $E{ $anno }++;
#  }
#  my $anno_merge = join"::", keys %E;
  print join("\t", $sr, $ele->[0], $ele->[1], $ele->[2]), "\n";
 }
}
