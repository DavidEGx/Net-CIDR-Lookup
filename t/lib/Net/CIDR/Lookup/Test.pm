package Net::CIDR::Lookup::Test;

use strict;
use warnings;
use parent 'My::Test::Class';
use Test::More;
use Test::Exception;
use Socket qw/ inet_aton /;
#-------------------------------------------------------------------------------

sub check_methods : Test(startup => 8) {
    my $t = shift->class->new;
    can_ok($t,'add');
    can_ok($t,'add_num');
    can_ok($t,'add_range');
    can_ok($t,'lookup');
    can_ok($t,'lookup_num');
    can_ok($t,'clear');
    can_ok($t,'to_hash');
    can_ok($t,'walk');
}

sub before : Test(setup) {
    my $self = shift;
    $self->{tree} = $self->class->new;
}

#-------------------------------------------------------------------------------

sub add : Tests(3) {
    my $t = shift->{tree};
    $t->add('192.168.0.129/25', 42);
    $t->add('1.2.0.0/15', 23);
    is($t->lookup('192.168.0.161'), 42, 'Block 192.168.0.129/25 lookup OK');
    is($t->lookup('1.3.123.234'), 23, 'Block 1.2.0.0/15 lookup OK');
    is($t->lookup('2.3.4.5'), undef, 'No result outside blocks');
}

sub lookup_num : Tests(2) {
    my $t = shift->{tree};
    $t->add('192.168.0.129/25', 42);
    $t->add('1.2.0.0/15', 23);
    is($t->lookup_num(_dq2int('192.168.0.130')), 42, 'lookup_num() found in range');
    is($t->lookup_num(_dq2int('192.188.0.1')), undef, 'lookup_num() not found outside');
}

sub add_range : Tests(4) {
    my $t = shift->{tree};
    $t->add_range('192.168.0.130-192.170.0.1', 42);
    $t->add_range('1.3.123.234 - 1.3.123.240', 23);
    is($t->lookup('192.169.0.22'), 42, 'Range 192.168.0.130 - 192.170.0.1');
    is($t->lookup('1.3.123.235'),  23, 'Range 1.3.123.234 - 1.3.123.240');
    is($t->lookup('2.3.4.5'), undef, 'No result outside blocks');
    my $h = $t->to_hash;
    is(scalar keys %$h, 19, 'Range expansion: number of keys');
}

sub collision : Test(1) {
    my $t = shift->{tree};
    $t->add('192.168.0.129/25', 42);
    dies_ok(sub { $t->add('192.168.0.160/31', 23) }, 'Collision: add() failed as expected');
}

sub benign_collision : Test(1) {
    my $t = shift->{tree};
    $t->add('192.168.0.129/25', 42);
    lives_ok(sub { $t->add('192.168.0.160/31', 42) }, 'Benign collision: add() succeeded');
}

sub merger : Tests(2) {
    my $t = shift->{tree};
    $t->add('192.168.0.130/25', 42);
    $t->add('192.168.0.0/25', 42);
    my $h = $t->to_hash;
    is(scalar keys %$h, 1, 'Merged block: number of keys');
    my ($k,$v) = each %$h;
    is($k, '192.168.0.0/24', 'Merged block: correct merged net block');
}

sub recursive_merger : Tests(2) {
    my $t = shift->{tree};
    $t->add('0.1.1.0/24', 42);
    $t->add('0.1.0.128/25', 42);
    $t->add('0.1.0.0/25', 42);
    my $h = $t->to_hash;
    is(scalar keys %$h, 1, 'Recursively merged block: number of keys');
    my ($k,$v) = each %$h;
    is($k, '0.1.0.0/23', 'Recursively merged block: correct merged net block');
}

sub nonmerger : Tests(1) {
    my $t = shift->{tree};
    $t->add('192.168.0.130/25', 42);
    $t->add('192.168.0.0/25', 23);
    my $h = $t->to_hash;
    is(scalar keys %$h, 2, 'Unmerged adjacent blocks: correct number of keys');
}

sub equalrange : Tests(2) {
    my $t = shift->{tree};
    $t->add('192.168.0.130/25', 1);
    $t->add('192.168.0.130/25', 1);
    my $h = $t->to_hash;
    is(0+keys %$h, 1, 'Got single block from two equal inserts');
    is($h->{'192.168.0.128/25'}, 1, 'Got correct block');
}

sub subrange1 : Tests(2) {
    my $t = shift->{tree};
    $t->add('192.168.0.1/24', 1);
    $t->add('192.168.0.1/25', 1);
    my $h = $t->to_hash;
    is(0+keys %$h, 1, 'Immediate subrange: resulted in single block');
    is($h->{'192.168.0.0/24'}, 1, 'Immediate subrange: got correct block');
}

sub subrange2 : Tests(2) {
    my $t = shift->{tree};
    $t->add('192.168.0.1/24', 1);
    $t->add('192.168.0.1/28', 1);
    my $h = $t->to_hash;
    is(0+keys %$h, 1, 'Small subrange: resulted in single block');
    is($h->{'192.168.0.0/24'}, 1, 'Small subrange: got correct block');
}

sub superrange1 : Tests(2) {
    my $t = shift->{tree};
    $t->add('192.168.0.128/25', 1);
    $t->add('192.168.0.0/24', 1);
    my $h = $t->to_hash;
    is(0+keys %$h, 1, 'Immediate superrange: resulted in single block');
    is($h->{'192.168.0.0/24'}, 1, 'Immediate superrange: got correct block');
}

sub superrange2 : Tests(2) {
    my $t = shift->{tree};
    $t->add('192.168.160.128/25', 1);
    $t->add('192.168.160.0/20', 1);
    my $h = $t->to_hash;
    is(0+keys %$h, 1, 'Big superrange: resulted in single block');
    is($h->{'192.168.160.0/20'}, 1, 'Big superrange: got correct block');
}

sub clear : Tests(1) {
    my $t = shift->{tree};
    $t->add('192.168.0.129/25', 42);
    $t->clear;
    is(scalar keys %{$t->to_hash}, 0, 'Reinitialized tree');
}

#-------------------------------------------------------------------------------
sub _dq2int { unpack "N", inet_aton($_[0]) }

1;

