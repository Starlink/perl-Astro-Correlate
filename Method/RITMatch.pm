package Astro::Correlate::Method::RITMatch;

=head1 NAME

Astro::Correlate::Method::RITMatch - Correlation using RIT Match.

=head1 SYNOPSIS

  ( $corrcat1, $corrcat2 ) = Astro::Correlate::Match::RITMatch->correlate( catalog1 => $cat1, catalog2 => $cat2 );

=head1 DESCRIPTION

This class implements catalogue cross-correlation using the RIT Match
application.

=cut

use 5.006;
use strict;
use warnings;
use warnings::register;

use Carp;
use File::Temp qw/ tempfile /;
use File::SearchPath qw/ searchpath /;
use Storable qw/ dclone /;

our $VERSION = '0.01';
our $DEBUG = 0;

=head1 METHODS

=head2 General Methods

=over 4

=item B<correlate>

Cross-correlates two catalogues.

  ( $corrcat1, $corrcat2 ) = Astro::Correlate::Method::RITMatch->correlate( catalog1 => $cat1,
                                                                            catalog2 => $cat2 );

This method takes two mandatory arguments, both C<Astro::Catalog> objects.
It returns two C<Astro::Catalog> objects containing C<Astro::Catalog::Star>
objects that matched spatially between the two input catalogues. The
first returned catalogue contains matched objects from the first input
catalogue, and ditto for the second. The C<Astro::Catalog::Star> objects
in the returned catalogues are not in the original order, nor do they have
the same IDs as in the input catalogues. A matched object has the same ID
in the two returned catalogues, allowing for further comparisons between
matched objects.

This method takes the following optional named arguments:

=item cat1magtype - The magnitude type to use for the first supplied
catalogue. If not defined, will default to 'mag'. This is used for
Astro::Catalog::Item objects that have fluxes that are not standard
magnitudes (for example, one might set this to 'mag_iso' for
magnitudes that come from the MAG_ISO column of a SExtractor
catalogue).

=item cat2magtype - As for cat1magtype, but for the second supplied
catalogue.

=item keeptemps - If this argument is set to true (1), then this
method will keep temporary files used in processing. Defaults to
false.

=item messages - If set to true (1), then this method will print
messages from the FINDOFF task during processing. Defaults to false.

=item temp - Set the directory to hold temporary files. If not set,
then a new temporary directory will be created using File::Temp.

=item timeout - Set the time in seconds to wait for the CCDPACK
monolith to time out. Defaults to 60 seconds.

=item verbose - If this argument is set to true (1), then this method will
print progress statements. Defaults to false.

This method usees the RIT Match application. In order for this method
to work it must be able to find the match binary. It looks in the
directory pointed to by the MATCH_DIR environment variable, and if
that fails, looks through your $PATH. If it cannot be found, this
method will croak.

=cut

sub correlate {
  my $class = shift;

# Grab the arguments, and make sure they're defined and are
# Astro::Catalog objects (the catalogues, at least).
  my %args = @_;
  my $cat1 = dclone( $args{'catalog1'} );
  my $cat2 = dclone( $args{'catalog2'} );

  if( ! defined( $cat1 ) ||
      ! UNIVERSAL::isa( $cat1, "Astro::Catalog" ) ) {
    croak "catalog1 parameter to Astro::Correlate::Method::RITMatch->correlate "
        . "method must be defined and must be an Astro::Catalog object"
        ;
  }
  if( ! defined( $cat2 ) ||
      ! UNIVERSAL::isa( $cat2, "Astro::Catalog" ) ) {
    croak "catalog2 parameter to Astro::Correlate::Method::RITMatch->correlate "
        . "method must be defined and must be an Astro::Catalog object"
        ;
  }

  my $keeptemps = defined( $args{'keeptemps'} ) ? $args{'keeptemps'} : 0;
  my $temp;
  if( exists( $args{'temp'} ) && defined( $args{'temp'} ) ) {
    $temp = $args{'temp'};
  } else {
    $temp = tempdir ( UNLINK => ! $keeptemps );
  }
  my $verbose = defined( $args{'verbose'} ) ? $args{'verbose'} : 0;
  my $cat1magtype = defined( $args{'cat1magtype'} ) ? $args{'cat1magtype'} : 'mag';
  my $cat2magtype = defined( $args{'cat2magtype'} ) ? $args{'cat2magtype'} : 'mag';

# Try to find the match binary in the directory pointed to by the
# MATCH_DIR environment variable. If that doesn't work, check the
# user's $PATH. If that doesn't work, croak.
  my $match_bin;
  if( defined( $ENV{'MATCH_DIR'} ) &&
      -d $ENV{'MATCH_DIR'} &&
      -e File::Spec->catfile( $ENV{'MATCH_DIR'}, "match" ) ) {
    $match_bin = File::Spec->catfile( $ENV{'MATCH_DIR'}, "match" );
  } else {
    $match_bin = searchpath( "match" );
    if( ! defined( $match_bin ) ) {
      croak "Could not find match binary. Ensure MATCH_DIR environment variable is set";
    }
  }

  print "match binary is in $match_bin\n" if $DEBUG;

# Get two temporary filenames for catalog files.
  ( undef, my $catfile1 ) = tempfile( DIR => $temp );
  ( undef, my $catfile2 ) = tempfile( DIR => $temp );

# Write the two input catalogues for match.
  print "Writing catalog 1 to $catfile1 using $cat1magtype magnitude.\n" if $DEBUG;
  $cat1->write_catalog( Format => 'RITMatch',
                        File => $catfile1,
                        mag_type => $cat1magtype );
  print "Input catalog 1 written to $catfile1.\n" if $DEBUG;
  print "Writing catalog 2 to $catfile2 using $cat2magtype magnitude.\n" if $DEBUG;
  $cat2->write_catalog( Format => 'RITMatch',
                        File => $catfile2,
                        mag_type => $cat2magtype );
  print "Input catalog 2 written to $catfile2.\n" if $DEBUG;

# Create a base filename for the output catalogues. Put it in the
# temporary directory previously set up.
  my $outfilebase = File::Spec->catfile( $temp, "outfile$$" );

# Set up the parameter list for match.
  my @matchargs = ( "$catfile1",
                    "1",
                    "2",
                    "3",
                    "$catfile2",
                    "1",
                    "2",
                    "3",
                    "outfile=$outfilebase",
                    "nobj=30",
                    "id1=0",
                    "id2=0",
                  );

# Run match.
  my $pid = open my $stdout, "$match_bin " . ( join ' ', @matchargs ) . "|" or croak "Could not execute match: $!";
  close $stdout;

# Read in the first output catalogue of matching objects. The old ID
# will be in the comment field.
  my $tempcat = new Astro::Catalog( Format => 'RITMatch',
                                    File => $outfilebase . ".mtA" );

# Loop through the stars, making a new catalogue with new stars using
# a combination of the new ID and the old information.
  my $corrcat1 = new Astro::Catalog();
  my @stars = $tempcat->stars;
  my $newid = 1;
  foreach my $star ( @stars ) {

    my $id = $star->id;
    my $oldstar1 = $cat1->popstarbyid( $id );
    $oldstar1 = $oldstar1->[0];
    next if ! defined( $oldstar1 );
    $oldstar1->id( $newid );
    $corrcat1->pushstar( $oldstar1 );
    $newid++;
  }

# And do the same for the second catalogue.
  $tempcat = new Astro::Catalog( Format => 'RITMatch',
                                 File => $outfilebase . ".mtB" );

  my $corrcat2 = new Astro::Catalog();
  @stars = $tempcat->stars;
  $newid = 1;
  foreach my $star ( @stars ) {
    my $id = $star->id;
    my $oldstar2 = $cat2->popstarbyid( $id );
    $oldstar2 = $oldstar2->[0];
    next if ! defined( $oldstar2 );
    $oldstar2->id( $newid );
    $corrcat2->pushstar( $oldstar2 );
    $newid++;
  }

  return ( $corrcat1, $corrcat2 );
}

=back

=head1 SEE ALSO

C<Astro::Correlate>

http://spiff.rit.edu/match/

=head1 REVISION

$Id$

=head1 AUTHORS

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2006 Particle Physics and Astronomy Research Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place,Suite 330, Boston, MA  02111-1307, USA

=cut

1;
