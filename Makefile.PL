#!/usr/bin/env perl
use 5.010001;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
  NAME         => 'Mojolicious::Plugin::Oro::Viewer',
  AUTHOR       => 'Nils Diewald',
  ABSTRACT     => 'View Oro Tables in your Application',
  VERSION_FROM => 'lib/Mojolicious/Plugin/Oro/Viewer.pm',
  BUILD_REQUIRES => {
    'Test::More' => 0
  },
  PREREQ_PM => {
    'Mojolicious' => 3.43,
    'Mojolicious::Plugin::Oro' => 0.05,
    'Mojolicious::Plugin::TagHelpers::Pagination' => 0.01,
    'DBIx::Oro' => 0.29
    },
  META_MERGE   => {
    requires  => { perl => '5.010001' },
  },
  LICENSE => 'artistic_2',
  MIN_PERL_VERSION => '5.010001',
  test => {TESTS => 't/*.t'}
);

