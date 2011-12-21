use strict;
use warnings;
package Devel::CompiletimeHack;

use File::Temp 'tempfile';

=head1 NAME

Devel::CompiletimeHack - on C<require>, do stuff before & after

=head1 DESCRIPTION

This would be a set of hooks allowing general before/around/after
action during C<require> (including C<use>) statements.

The idea arose from attempting to profile L<Moose> with
L<Devel::NYTProf> (v3, before compilation profiling improved).

It looks possible, but may require either making assumptions about the
code loading process or doing things to C<require> and C<do> that may
be fragile.

Incomplete - I don't need it just now.

=cut


our %hacking; # key = packagename, value is locally incremented

sub new {
    my ($called) = @_;
    return bless {}, ref($called) || $called;
}

sub Devel::CompiletimeHack::INC { # qualified, else it goes in main::
    my ($self, $filename) = @_;
    local $hacking{$filename};
    my $h = $hacking{$filename} ++;

    $INC{$filename} = TmpJunk->new($filename);

    my $val = $INC{$filename};
    $val = defined $val ? qq{'$val'} : 'undef';
    noisef("%s: INC called; \$INC{%s} = %s; hacking=%s\n", $self, $filename, $val, $h);

    if ($h) {
        # we're wired already - do not recurse - defer to next @INC
        return ();
    } else {
        # something is looking for $filename
        return $self->wanted($filename);
    }
}


sub wanted {
    my ($self, $filename) = @_;
    my $modname;

    $self->do_before;

    $self->create_wrapper; # make a sub to do the require, and hence be profiled
    $self->call_wrapper; # call require again - may break? or do nothing?

    $self->do_after; # this is the hook that's hard to reach

    return (); # defer to next
}


sub wanted_DNW {
    my ($self, $filename) = @_;
        return __mkfh(<<"CODE");
print "Here is $filename\\n";
print "Doing stuff\\n";

# This does happen - require already knows not to recurse
require "$filename";

0; # doesn't help
CODE
    }
}


# @INC hook outputs have to be more like filehandles than your average
# filehandle emulation.  This is an easy but inefficient solution.
sub __mkfh {
    my ($txt) = @_;
    my $fh = tempfile();
    my $top = tell $fh;
    die "tell failed on tmpfile: $!" if $top < 0;
    print $fh $txt or die "Failed to write into tmpfile: $!";
    seek $fh, $top, 0 or die "Failed to seek top of tmpfile: $!";
    return $fh;
}


sub install {
    my ($called) = @_;
    my $self = ref($called) ? $called : $called->new;
    unshift @INC, $self;
    noisef("%s: Installed %s to \@INC\n", $called, $self);
}



sub noisef {
    warn sprintf(shift, @_);
}

# sub do_require {
#     my ($called, $want_pkg) = @_;
# 
#     local $hacking{$want_pkg} ++;
#     die "While loading $want_pkg: recursing is not what I wanted" if $hacking{$want_pkg} > 1;
# 
#     $called->before_load($want_pkg);
# 
#     # Remove this hack from @INC
#     my $incsize = @INC;
#     local @INC = grep { $_ ne $inc_ele } @INC;
#     die 'Failed to hide my origin from @INC' unless $incsize - 1 == @INC;
# 
#     my $pkgfn = 'Class/MOP/Class.pm';
#     noisef("  Loaded the fake one from %s", $INC{$pkgfn});
#     delete $INC{$pkgfn};
# 
#     rerequire();
# 
#     noisef("  Loaded the real one from %s", $INC{$pkgfn});
# }
# 
# sub hack {
#     *Class::MOP::Class::make_immutable = \&make_immutable__NOP;
# }
# 
# sub make_immutable__NOP {
#     noisef("Class::MOP::Class::make_immutable(%s) : no-op\n", "@_");
# }
# 
# sub rerequire {
#     # in a sub, so NYTProf v3 can see the time
#     require Class::MOP::Class;
#     1;
# }
# 
# # This needs to happen early in the compilation of Moose
# load_real();
# hack() if $ENV{CLASS_MOP_NO_IMMUT};

package Devel::CompiletimeHack::FH;
our $AUTOLOAD;
sub new {
    my $called = shift;

    # Create GLOB ref - http://www.perlmonks.org/?node_id=636519
    select select my $self;

    # store our lines
    @{*$self} = @_;

    return bless $self, ref($called) || $called;
}

sub getlines {
    my ($self) = @_;
    my $lines = \@{ *$self };
    return wantarray ? splice @$lines : shift @$lines;
}

sub AUTOLOAD {
    warn "AUTOLOAD($AUTOLOAD: @_)\n";
}

package TmpJunk;
sub new { shift; bless [ @_ ], __PACKAGE__ }
sub DESTROY {
    my $self = shift;
    my ($filename) = @$self;
    warn "INC{$filename} replaced with '$INC{$filename}'";
}

1;
