use strict;
use warnings;
package Moose::ProfiledLoadingGenerator;

use List::MoreUtils 'uniq';


=head1 DESCRIPTION

Write a module which, when loaded, performs C<require>s of the modules
in the __DATA__ section in a way that L<Devel::NYTProf> can see.

=head1 SYNOPSIS

 perl -I lib -MMoose::ProfiledLoadingGenerator=save -e 1

 perl -I lib -MMoose::ProfiledLoading -e 'use App::Foo'

 perl -d:NYTProf -I lib -e 'use App::Foo; do_it()'
 nytprofhtml -l lib

=head1 FUNCTIONS

This is quick'n'dirty code...


=head2 packages()

List of package names to load

=cut

my @pkgs;
sub packages {
    unless (@pkgs) {
        @pkgs = uniq grep { ! /^\s*(#|$)/ } <DATA>;
        chomp @pkgs;
    }
    return @pkgs;
}


=head2 symified(@packages)

Returns package names mapped into a namespace suitable for use on
C<sub>.

=cut

sub symified {
    return map { my $pkg = $_; $pkg =~ s/::/___/g; $pkg } @_;
}


=head2 loader_subs($package)

Return text of subroutines definitions to require and import the
package.

=cut

sub loader_subs {
    my ($pkg, $import_str) = @_;
    $import_str = '' unless defined $import_str;

    my ($sym) = symified($pkg);
    return qq{
sub load__$sym {
  require $pkg;
  1;
}

sub use__$sym {
  eval "use $pkg $import_str; 1" ||
    die "use $pkg $import_str: \$@";
  1;
}

};
}

sub call_subs {
    my ($interleave, @pkg) = @_;
    my @sym = symified(@pkg);

    return join "\n",
      ($interleave
       ? ((map {qq{  load__$_();\n   use__$_();}} @sym), '')
       : ((map {qq{load__$_();}} @sym), '',
          (map {qq{use__$_();}} @sym), '') );
}


=head2 write_neighbour()

Write the generated module code out into the directory containing this
one.  Assuming it is your git checkout, and you know not to commit the
result.

=cut

sub write_neighbour {
    my @arg = @_;
    my ($fn) = __FILE__;
    $fn =~ s/Generator\.pm$/.pm/ or die "Can't make name from $fn";
    open my $fh, '>', $fn or die "Can't overwrite to $fn: $!";

    print $fh module_text(@arg);
}

sub module_text {
    my ($interleave, $import_str) = @_;

    my $pkg = 'package';
    local $" = "\n";
    return <<"EOF";
$pkg Moose::ProfiledLoading;
use strict;
use warnings;

@{[ map { loader_subs($_, $import_str) } packages() ]}

sub LOAD_ALL {
@{[ call_subs($interleave, packages()) ]}
  1;
}
LOAD_ALL();

1;
EOF
}

sub import {
    my ($called, @arg) = @_;
    if (0 == @arg) {
        # nop
    } elsif (1 == @arg && $arg[0] eq 'save') {
        write_neighbour(0, '()');
    } else {
        die "Cannot import @arg";
    }
}

1;

__DATA__

# from Moose 0.93

Scalar::Util
Carp

Moose::Exporter

Class::MOP

Moose::Meta::Class
Moose::Meta::TypeConstraint

metaclass
Moose::Util::TypeConstraints
Moose::Meta::Attribute

Moose::Meta::TypeCoercion
Moose::Meta::Attribute
Moose::Meta::Instance

Moose::Object

Moose::Meta::Role
Moose::Meta::Role::Composite
Moose::Meta::Role::Application
Moose::Meta::Role::Application::RoleSummation
Moose::Meta::Role::Application::ToClass
Moose::Meta::Role::Application::ToRole
Moose::Meta::Role::Application::ToInstance

Moose::Util

Moose::Meta::Attribute::Native

Moose
