use strict;
use warnings;
use Data::Dumper;

my%A;

while(<>){
 chomp;
 my($sr,$fr,$to)=split"\t",$_;
 push@{ $A{$sr} }, [$fr, $to];
}

foreach my $sr(keys %A) {
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

foreach my $sr(sort keys %A) {
 foreach my $ele(@{ $A{$sr} }) {
  print join("\t", $sr, @{ $ele }), "\n";
 }
}
