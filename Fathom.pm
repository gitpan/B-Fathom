package B::Fathom;

=head1 NAME

B::Fathom - a code comprehension estimator

=head1 DESCRIPTION

C<B::Fathom> is a backend to the Perl compiler; it analyzes the syntax
of your Perl code, and estimates the readability of your program.

=head1 USAGE

Invoke this module on your code by typing

    perl -MO=Fathom <script>

where <script> is the name of the Perl program that you wish to evaluate.

=head1 CAVEATS

Because of the nature of the compiler, C<Fathom> has to do some guessing
about the syntax of your program.  See the comments in the module for
specifics.

C<Fathom> doesn't work very well on modules yet.

=head1 AUTHOR

Kurt Starsinic E<lt>F<kstar@isinet.com>E<gt>

=head1 COPYRIGHT

    Copyright (c) 1998 Kurt Starsinic.
    This module is free software; you may redistribute it
    and/or modify it under the same terms as Perl itself.

=cut

use strict;
use B qw(walksymtable walkoptree main_root);
use vars qw($VERSION);
$VERSION = 0.01;

# TODO:
#   Process format statements and prototypes
#   Do a more accurate job when processing modules, rather than scripts
#   Be smarter about parentheses
#   Find a `cooler' way to dereference CV's than using symbolic refs


my (%Taken, %Name, @Skip_sub, @Subs_queue);
my ($Tok, $Expr, $State, $Sub);
my $Verbose = 0;
my (%Boring) = (
    pp_null         => 1,
    pp_enter        => 1,
    pp_pushmark     => 1,
    pp_unstack      => 1,
    pp_lineseq      => 1,
    pp_stub         => 1,
);


# The `compile' subroutine is the meat of any compiler backend; see
# the documentation for B.pm for details.
sub compile
{
    my (@args)  = @_;

    foreach (@args) {
        if ($_ eq '-v') {
            $Verbose = 1;
        }
    }

    return \&do_compile;
}


sub do_compile
{
    walksymtable(\%::, 'tally_symrefs', sub { 1 });
    walksymtable(\%::, 'queue_subs',    sub { 0 });

    if ($Verbose) {
        foreach (sort keys %Taken) {
            print "Skipping imported sub `$Name{$_}'\n" if $Taken{$_} > 1;
        }
    }

    foreach (main_root(), @Subs_queue) {
        walkoptree($_, 'tally_op');
    }

    $Sub++;     # The body of the program counts as a subroutine.

    score_code();
}


sub score_code
{
    my ($tok_expr, $expr_state, $state_sub, $score, $opinion);

    if ($Tok   == 0) { die "No tokens; score is meaningless.\n" }
    if ($Expr  == 0) { die "No expressions; score is meaningless.\n" }
    if ($State == 0) { die "No statements; score is meaningless.\n" }
    if ($Sub   == 0) { die "No subroutines; score is meaningless.\n" }

    $tok_expr   = $Tok   / $Expr;
    $expr_state = $Expr  / $State;
    $state_sub  = $State / $Sub;

    $score = ($tok_expr * .55) + ($expr_state * .28) + ($state_sub * .08);

    if    ($score < 1) { $opinion = "trivial" }
    elsif ($score < 2) { $opinion = "easy" }
    elsif ($score < 3) { $opinion = "very readable" }
    elsif ($score < 4) { $opinion = "readable" }
    elsif ($score < 5) { $opinion = "easier than the norm" }
    elsif ($score < 6) { $opinion = "mature" }
    elsif ($score < 7) { $opinion = "complex" }
    elsif ($score < 8) { $opinion = "very difficult" }
    else               { $opinion = "obfuscated" }

    printf "%-5d token%s\n",      $Tok,   ($Tok   == 1 ? "" : "s");
    printf "%-5d expression%s\n", $Expr,  ($Expr  == 1 ? "" : "s");
    printf "%-5d statement%s\n",  $State, ($State == 1 ? "" : "s");
    printf "%-5d subroutine%s\n", $Sub,   ($Sub   == 1 ? "" : "s");
    printf "readability is %.2f (%s)\n", $score, $opinion;
}


sub B::OBJECT::tally_op
{
    my ($self)      = @_;
    my $ppaddr      = $self->can('ppaddr') ? $self->ppaddr : undef;

    if      ($Boring{$ppaddr}) {
        # Do nothing; these OPs don't count
    } elsif ($ppaddr eq 'pp_nextstate' or $ppaddr eq 'pp_dbstate') {
        $Tok += 1;             $State += 1;
    } elsif ($ppaddr eq 'pp_leavesub') {    # sub name { <xxx> }
        $Tok += 4; $Expr += 1;              $Sub += 1;
    } elsif ($ppaddr =~ /^pp_leave/) {
        # pp_leave* is already accounted for in its matching pp_enter*
    } elsif ($ppaddr eq 'pp_entertry') {    # eval { <xxx> }
        $Tok += 3; $Expr += 1;
    } elsif ($ppaddr eq 'pp_anoncode') {    # sub { <xxx> }
        $Tok += 3; $Expr += 1;
    } elsif ($ppaddr eq 'pp_scope') {       # do { <xxx> }
        $Tok += 3; $Expr += 1;
    } elsif ($self->isa('B::LOOP')) {       # for (<xxx>) { <yyy> }
        $Tok += 5; $Expr += 2;
    } elsif ($self->isa('B::LISTOP')) {     # OP(<xxx>)
        $Tok += 3; $Expr += 1;
    } elsif ($self->isa('B::BINOP')) {      # <xxx> OP <yyy>
        $Tok += 1; $Expr += 1;
    } elsif ($self->isa('B::LOGOP')) {      # <xxx> OP <yyy>
        $Tok += 1; $Expr += 1;
    } elsif ($self->isa('B::CONDOP')) {     # while (<xxx>) { <yyy> }
        $Tok += 5; $Expr += 2;
    } elsif ($self->isa('B::UNOP')) {       # OP <xxx>
        $Tok += 1; $Expr += 1;
    } else {                                # OP
        $Tok += 1;
    }
}


# Keep track of the subroutine associated with each symbol.
# If we find multiple symbol table entries pointing to one sub, then
# we'll guess that the sub is imported, and we'll ignore it.
sub B::OBJECT::tally_symrefs
{
    my ($symbol)    = @_;
    my $name        = full_subname($symbol);

    if ($name) {
        no strict;
        my $coderef = \&{"$name"};

        $Taken{$coderef}++;
        $Name{$coderef} = $name;
    }
}


sub B::OBJECT::queue_subs
{
    my ($symbol)    = @_;
    my $name        = full_subname($symbol);

    if ($name) {
        no strict;
        my $coderef = \&{"$name"};

        push @Subs_queue, $symbol->CV->ROOT unless $Taken{$coderef} > 1;
    }
}


# Given a symbol table entry $symbol, return the fully qualified subroutine
# name of the associated subroutine; if there is none, return undef.
sub full_subname
{
    my ($symbol)    = @_;

    # Build the full subname from the stashname and the symbolname:
    if ($symbol->CV->isa('B::CV')) {
        return $symbol->STASH->NAME . "::" . $symbol->NAME;
    } else {
        return undef;
    }
}


1;


