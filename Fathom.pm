package B::Fathom;


=head1 NAME

B::Fathom - a module to evaluate the readability of Perl code

=head1 SYNOPSIS

    perl -MO=Fathom <script>

or

    perl -MO=Fathom,-v <script>

where E<lt>scriptE<gt> is the name of the Perl program that you
want to evaluate.

C<-v> activates verbose mode, which currently reports the subs
that have been skipped over because they seem to be imported.

=head1 DESCRIPTION

C<B::Fathom> is a backend to the Perl compiler; it analyzes the syntax
of your Perl code, and estimates the readability of your program.

=head1 CAVEATS

Because of the nature of the compiler, C<Fathom> has to do some
guessing about the syntax of your program.  See the comments in the
module for specifics.

C<Fathom> doesn't work very well on modules yet.

=head1 AUTHOR

Kurt Starsinic E<lt>F<kstar@isinet.com>E<gt>

=head1 COPYRIGHT

    Copyright (c) 1998 Kurt Starsinic.
    This module is free software; you may redistribute it
    and/or modify it under the same terms as Perl itself.

=cut


use strict;

use B;

use vars qw($VERSION);
$VERSION = 0.03;


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
        if (/-v(.*)/) { # -v or -vn
            $Verbose += $1 || 1;
        }
    }

    return \&do_compile;
}


sub do_compile
{
    B::walksymtable(\%::, 'tally_symrefs', sub { 1 });
    B::walksymtable(\%::, 'queue_subs',    sub { 0 });

    if ($Verbose) {
        foreach (sort keys %Taken) {
            print "Skipping imported sub `$Name{$_}'\n" if $Taken{$_} > 1;
        }
    }

    foreach my $op (B::main_root(), @Subs_queue) {
        # Call the method `tally_op' on each OP in each of the
        # optrees we're looping over:
        B::walkoptree($op, 'tally_op');
    }

    $Sub++;     # The body of the program counts as 1 subroutine.

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


###
### The next three subs are all in package B::OBJECT; this is so
### that all OP's will inherit the subs as methods.
###


# This method is called on each OP in the tree we're examining; see
# do_compile() above.  It examines the OP, and then increments the
# count of tokens, expressions, statements, and subroutines as
# appropriate.
sub B::OBJECT::tally_op
{
    my ($self)      = @_;
    my $ppaddr      = $self->can('ppaddr') ? $self->ppaddr : undef;

    printf("%-15s %s\n", $ppaddr, ref($self)) if ($Verbose > 1);

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
    } elsif ($ppaddr eq 'pp_entersub') {    # foo()
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


# Keep track of the sub associated with each symbol.  If we find multiple
# symbol table entries pointing to one sub, then we'll guess (in
# do_compile()) that the sub is imported, and we'll ignore it.  Thanks
# to Mark-Jason Dominus for suggesting this strategy.
sub B::OBJECT::tally_symrefs
{
    my ($symbol)    = @_;
    my $name        = full_subname($symbol);

    # We're creating a `symbolic reference' in this block
    # (see perlref(1)), which is why we need `no strict':
    if ($name) {
        no strict;
        my $coderef = \&{"$name"};

        $Taken{$coderef}++;
        $Name{$coderef} = $name;
    }
}


# Create an array of OP's for introspection.  These are the `root' OP's
# of each sub that we're going to examine.
sub B::OBJECT::queue_subs
{
    my ($symbol)    = @_;
    my $name        = full_subname($symbol);

    # We're creating a `symbolic reference' in this block
    # (see perlref(1)), which is why we need `no strict':
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


