#!perl

use strict;
use Test::More; # Don't know ahead of time how many
                # modules we have to test.
use File::Find; # To find modules to test.

my @modules; # This will get set in the &wanted subroutine.

# Scan through blib/ looking for modules.
find( { wanted => \&wanted,
        no_chdir => 1,
      },
      "blib" );

# Set the number of tests we're going to do.
plan tests => scalar( @modules );

# Loop through each module and check if require_ok works.
foreach my $module ( @modules ) {
  require_ok( $module );
}

# This determines whether we are interested in the module
# and then stores it in the array @modules

sub wanted {
  my $pm = $_;

  # is it a module
  return unless $pm =~ /\.pm$/;

  # Remove the blib/lib (assumes unix!)
  $pm =~ s|^blib/lib/||;

  # Translate / to ::
  $pm =~ s|/|::|g;

  # Remove .pm
  $pm =~ s/\.pm$//;

  push(@modules, $pm);
}
