package Astro::Correlate;

=head1 NAME

Astro::Correlate - Class for cross-correlating astronomical catalogues.

=head1 SYNOPSIS

  use Astro::Correlate;

  my $corr = new Astro::Correlate( catalog1 => $cat1,
                                 catalog2 => $cat2 );

  $result = $corr->correlate( method => $method );

=head1 DESCRIPTION

Class for cross-correlating astronomical catalogues.

=cut

use 5.006;
use strict;
use warnings;
use warnings::register;
use Carp;

our $VERSION = '0.01';

=head1 METHODS

=head2 CONSTRUCTOR

=over 4

=item B<new>

Create a new instance of an C<Astro::Correlate> object.

  $corr = new Astro::Correlate( catalog1 => $cat1,
                                catalog2 => $cat2 );

The two mandatory named arguments must be defined and must be
C<Astro::Catalog> objects. Both catalogs must be comparable --
the C<Astro::Catalog::Star> objects in those catalogs must have
x/y or RA/Dec defined, or be able to calculate one from the other
using a C<Starlink::AST> FrameSet.

=cut

sub new {
  my $proto = shift;
  my $class = ref( $proto ) || $proto;

  my %args = @_;

  if( ! defined( $args{'catalog1'} ) ||
      ! UNIVERSAL::isa( $args{'catalog1'}, "Astro::Catalog" ) ||
      ! defined( $args{'catalog2'} ) ||
      ! UNIVERSAL::isa( $args{'catalog2'}, "Astro::Catalog" ) ) {
    croak "Must supply two Astro::Catalog objects to Astro::Correlate constructor.\n";
  }
  my $cat1 = $args{'catalog1'};
  my $cat2 = $args{'catalog2'};

  my $corr = {};

  $corr->{CATALOG1} = $cat1;
  $corr->{CATALOG2} = $cat2;

  bless( $corr, $class );
  return $corr;
}

=back

=head2 General Methods

=over 4

=item B<correlate>

Cross-correlates two catalogues using the supplied method.

  ( $corrcat1, $corrcat2 ) = $corr->correlate( method => $method );

This method takes one mandatory named argument, a string describing
which method is to be used for cross-correlation. Currently-available
cross-correlation methods are FINDOFF. This string is case-insensitive.

This method returns two catalogues, both containing stars that matched
in the two catalogues passed to the constructor. The returned catalogues
are C<Astro::Catalog> objects, and each matched C<Astro::Catalog::Star>
object has the same ID number in either catalogue.

=cut

sub correlate {
  my $self = shift;

  my %args = @_;

  if( ! defined( $args{'method'} ) ) {
    croak "Must supply cross-correlation method";
  }

  # Find out what the cross-correlation class is called.
  my $corrclass = _load_corr_plugin( $args{'method'} );
  if( ! defined( $corrclass ) ) {
    croak "Could not load cross-correlation method class for " . $args{'method'} . " method";
  }

  # Set up the correlated catalogues.
  my $corrcat1;
  my $corrcat2;

  # And do the correlation.
  ( $corrcat1, $corrcat2 ) = $corrclass->correlate;

  # Return the correlated catalogues;
  return( $corrcat1, $corrcat2 );
}

=back

=begin __PRIVATE_METHODS__

=head2 Private Methods

The following methods are private to the module.

=over 4

=item B<_load_corr_plugin>

Loads a correlation plugin module.

  $class = _load_corr_plugin( $method );

Returns the class name on successful load. If the class cannot be
found or loaded, issues a warning and returns undef.

=cut

sub _load_corr_plugin {
  my $method = shift;

  # Set method to uppercase.
  $method = uc( $method );

  # Special case some modules so they don't all have to be
  # upper-case.

  # Set the class name.
  my $class = "Astro::Correlate::Method::$method";

  # Eval the class to see if it loads, issuing a warning
  # if it fails.
  eval "use $class;";
  if( $@ ) {
    warnings::warnif( "Error loading correlation plugin module $class: $@" );
    return undef;
  }

  return $class;
}

=back

=end __PRIVATE_METHODS__

=head1 REVISION

$Id$

=head1 AUTHORS

Brad Cavanagh E<lt>b.cavanagh@jach.hawaii.eduE<gt>

=head1 COPYRIGHT

Copyright (C) 2005 Particle Physics and Astronomy Research Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

1;
