# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

# There seems to be a problem with an undeclared `Perl_byterun';
# the problem disappears if we do `lazy dynaloading':
BEGIN
{
    delete $ENV{PERL_DL_NONLAZY};
}


# Now for some black magic to print on failure.
BEGIN
{
    $| = 1;
    print "1..1\n";
}


END
{
    print "not ok 1\n" unless $loaded;
}


use B::Fathom;
$loaded = 1;
print "ok 1\n";

# End of black magic.

# More tests to come.  Any ideas about a clean way to write a test
# for a compiler module, and to integrate it with a MakeMaker
# makefile, are welcomed.

