use strict;
use warnings;
package Class::MOP::Class::MONKEYPATCHER;

our $hackit;

sub noisef {
#    warn sprintf(@_);
}

sub load_and_hack {
    $hackit ++;
    die "Recursing is not what I wanted" if $hackit > 1;

    my $inc_ele = __FILE__;
    $inc_ele =~ s{/+Class/MOP/.*}{};
    noisef("Loaded monkeypatcher %s from %s via %s\n",
           __PACKAGE__, __FILE__, $inc_ele);

    my $incsize = @INC;
    local @INC = grep { $_ ne $inc_ele } @INC;
    die 'Failed to hide my origin from @INC' unless $incsize - 1 == @INC;

    my $pkgfn = 'Class/MOP/Class.pm';
    noisef("  Loaded the fake one from %s", $INC{$pkgfn});
    delete $INC{$pkgfn};

    rerequire();

    noisef("  Loaded the real one from %s", $INC{$pkgfn});

    *Class::MOP::Class::make_immutable = \&make_immutable__NOP;
}

sub make_immutable__NOP {
    noisef("Class::MOP::Class::make_immutable(%s) : no-op\n", "@_");
}

sub rerequire {
    # in a sub, so NYTProf v3 can see the time
    require Class::MOP::Class;
    1;
}

# This needs to happen early in the compilation of Moose
load_and_hack();

1;
