package Devel::TimeComplexity;

use strict;
use warnings;

use Time::HiRes qw( gettimeofday tv_interval );
use Statistics::Regression; # CPAN


=head1 NAME

Devel::TimeComplexity - how slow is my code likely to run?

=head1 SYNOPSIS

 my $tc = Devel::TimeComplexity->new("busy loop");
 $tc->measure(25, sub {
      my ($n, $of_N) = @_;
      for (my $i = 0; $i < $n * $n * 1E4; $i++) {
	# busy loop
      }
    });
 # (counts to a few hundred million)

 $tc->print; # execution time shows a strong correlation with n^2

=head1 DESCRIPTION

Requires a name, a function (code), an iteration count (N) and an
optional function (setup).

Iterates

  code(n, N, setup(n, N)) foreach n in (0 .. N-1)

taking timings for the execution of code (but ignoring the setup
time), then estimates the order of time complexity by linear
regression against an assortment of functions f(n).

Regression results are dumped out.  This should help you figure out
the "big Oh notation" for your code.


=head1 METHODS

=head2 new($name)

Construct object.  The name is used in output text.

The set of factors against which we correlate are hardwired here, but
could be changed easily enough.

=cut

sub new {
    my ($proto, $name) = @_;
    my $class = ref($proto) || $proto;

    my @factor =
      (const     => sub { 1 },
       'ln(n)'   => sub { $_[0] ? log($_[0]) : -10 }, # must cope with n=0
       'sqrt(n)' => sub { sqrt( $_[0] ) },
       n         => sub { $_[0] },
       'n^2'     => sub { $_[0] * $_[0] },
      );

    # split them up from temporary but convenient format
    my (@f_ttl, @f_code);
    while (my ($t, $c) = splice @factor, 0, 2) {
	push @f_ttl, $t;
	push @f_code, $c;
    }

    # Currently there is one regression, but more could be used
    # e.g. to separate CPU time from wallclock time
    my $regr = Statistics::Regression->new("$name (CPUsec)", \@f_ttl);

    my $self = { name => $name,
		 regr => $regr,
		 verbose => 1,
		 factors => \@f_ttl,
		 mkfactors => \@f_code,
#		 times => [], # centisec of CPUtime
	       };
    bless $self, $class;

    return $self;
}


=head2 measure($points, $code, $setup)

For each $n (0 .. $points-1), run some code and store the timings.
$points should be a positive integer, and not too large.

Runs

 my @args = $setup ? $setup->($n, $points) : ();
 $code->($n, $points, @args); # TIMED

=cut

sub measure {
    my ($self, $count, $code, $setup) = @_;
    die "Can only 'measure' once per object instance" if $$self{times};
    my $verbose = $$self{verbose};

    $$self{times}      = Devel::TimeComplexity::meanvar->new;
    $$self{times_lsdp} = Devel::TimeComplexity::meanvar->new;

    my ($sum, $sum_sq, $numint) = (0, 0, 0);
    for (my $n=0; $n < $count; $n++) {
	print STDERR "$n / $count: setup   \r" if $verbose;
	my @args = $setup ? $setup->($n, $count) : ();
	print STDERR "$n / $count:   code  \r" if $verbose;
	my $t = __cputime($code, $n, $count, @args);

	# Build the (1, n, n^2, ln(n) ... ) factors
	my @factor = map { $_->($n) } @{ $$self{mkfactors} };

	$$self{regr}->include($t, \@factor);

	# Keep stats on $t
#	push @{ $$self{times_data} }, $t;
	$$self{times}->add($t);

	# Keep stats on the precision of $t
	$$self{times_lsdp}->add( __lsdp($t) );
    }
    print STDERR " " x 24, "\n" if $verbose;
}

sub __lsdp {
    my ($n) = @_;
    my $dig = $n;

    # Round away any insignificant precision
    $dig =~ s/\.(\d*[1-9]|)000000*([0-4]|000\d\d)$/.$1/;
    $dig =~ s/\.(\d*[0-8]|)999999*([5-9]|999\d\d)$/.$1/;

    my $prec;
    if ($dig =~ /^-?\d+\.(\d+)$/) {
	# count the decimal places
	$prec = -length($1);
    } elsif ($dig =~ /^-?(\d*?)(0*)\.?$/) {
	# count the multiples of ten
	$prec = $1 ? length($2) : -9;
    } else {
	die "no rule to get least significant decimal place from '$dig' (n=$n)";
    }

#warn "(n=$n --> $dig) => l.s.dp=$prec\n" if $prec < -2;
    return $prec;
}


=head2 print()

Send to STDOUT some info about the correlations detected.  Currently
calls L<Statistics::Regression/print> and dumps stats on the output
times.

=cut

sub print {
    my ($self) = @_;

    print("\ntimes & least significant decimal place (sufficient precision indictor)\n",
	  "   value\t", $$self{times}->to_string, "\n",
	  "   l.s.dp.\t", $$self{times_lsdp}->to_string, "\n\n");

    $$self{regr}->print;

    # print map {"$_\n"} @{ $$self{times_data} };
}


sub __walltime { # precise, but accuracy is subject to machine load
    my ($code, @args) = @_;
    my $t0 = [ gettimeofday ];
    $code->(@args);
    return tv_interval($t0, [gettimeofday]);
}


sub __cputime { # more accurate, but precision probably limited to 0.01s
    my ($code, @args) = @_;
    my $t0 = (times)[0];
    $code->(@args);
    return (times)[0] - $t0;
}

=head1 CAVEATS

First note the caveats in L<Statistics::Regression>, which is the
heart of this class.

=over 4

=item *

L</measure> currently uses CPU time only.

=item *

It can be difficult to portion the work per iteration so that the
total measurement time is not too large and (partly as a result of
using CPU time) the individual measurements are large enough to be
significant.

=item *

L</measure> may only be called once per object.  This interface is
likely to change, if a solution to the problems surfaces.

=back


=head1 AUTHOR

 Copyright (c) 2009 Genome Research Ltd.
 Author: Matthew Astley <mca@sanger.ac.uk>

This file is part of the perl-junkbox (pending separation into a
specific project).

This  perl-junkbox is free  software; you  can redistribute  it and/or
modify  it  under the  terms  of the  GNU  General  Public License  as
published by  the Free  Software Foundation; either  version 2  of the
License, or (at your option) any later version.

This program  is distributed in the  hope that it will  be useful, but
WITHOUT   ANY  WARRANTY;   without  even   the  implied   warranty  of
MERCHANTABILITY  or FITNESS  FOR A  PARTICULAR PURPOSE.   See  the GNU
General Public License for more details.

You  should have received  a copy  of the  GNU General  Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

=cut

1;


package Devel::TimeComplexity::meanvar; # small utility class for mean/variance
use strict;
use warnings;

sub new {
    my $self =
      { count => 0,
	sum => 0,
	sum_sq => 0 };
    bless $self, __PACKAGE__;
    return $self;
}

sub add {
    my ($self, $n) = @_;
    $$self{count}++;
    $$self{sum} += $n;
    $$self{sum_sq} += $n * $n;
    return ();
}

sub mean {
    my ($self) = @_;
    return $$self{sum} / $$self{count};
}

sub var {
    my ($self) = @_;
    my $mean = $self->mean;
    return $$self{sum_sq} / $$self{count} - $mean ** 2;
}

sub to_string {
    my ($self) = @_;
    return sprintf
      ("count=%d, mean=%.3g, var=%.3g",
       $$self{count}, $self->mean, $self->var);
}

1;
