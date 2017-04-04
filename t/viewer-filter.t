#!/usr/bin/env perl
use Test::Mojo;
use Test::More;
use Mojolicious::Lite;
use lib ('../lib', 'lib');

app->plugin(Oro => {
  default => {
    file => ':memory:',
    init => sub {
      my $oro = shift;

      $oro->do(<<NAME) or return -1;
  CREATE TABLE Name (
  id       INTEGER PRIMARY KEY,
  prename  TEXT NOT NULL,
  surname  TEXT,
  age      INTEGER,
  sex      TEXT
)
NAME

      $oro->insert(
        Name =>
          [qw/sex prename surname age/] => (
            [qw/male James Smith 31/],
            [qw/male John Jones 32/],
            [qw/male Robert Taylor 33/],
            [qw/male Michael Brown 34/],
            [qw/male William Williams 35/],
            [qw/male David Wilson 36/],
            [qw/male Richard Johnson 37/],
            [qw/male Charles Davies 38/],
            [qw/male Joseph Robinson 39/],
            [qw/male Thomas Wright 40/],
            [qw/female Mary Thompson 31/],
            [qw/female Patricia Evans 32/],
            [qw/female Linda Walker 33/],
            [qw/female Elizabeth Roberts 35/],
            [qw/female Jennifer Green 36/],
            [qw/female Maria Hall 37/],
            [qw/female Susan Wood 38/],
            [qw/female Margaret Jackson 39/],
            [qw/female Dorothy Clarke 40/]
          )
        ) or return -1;
    }
  }
});

plugin 'Oro::Viewer' => {
  default_count => 10,
  max_count => 15
};

ok(my $view = app->oro_view(
  display => [
    Name => 'prename'
  ],
  table => 'Name',
  query => {
    sortBy => 'sex'
  }
), 'View is fine');

my $dom = Mojo::DOM->new->parse($view);
like($dom->at('thead > tr > th > a')->attr('href'), qr!sortOrder=ascending!, 'Link');
like($dom->at('thead > tr > th > a')->attr('href'), qr!sortBy=prename!, 'Link');
unlike($dom->at('thead > tr > th > a')->attr('href'), qr!filterBy!, 'Link');
is($dom->at('tbody > tr:nth-child(1) > td')->text, 'Dorothy', 'Sort');
is($dom->at('tbody > tr:nth-child(3) > td')->text, 'Jennifer', 'Sort');
is($dom->at('tbody > tr:nth-child(10) > td')->text, 'Charles', 'Sort');

ok($view = app->oro_view(
  display => [
    Name => {
      col => 'prename',
      filter => 1
    }
  ],
  table => 'Name',
  query => {
    sortBy => 'sex',
    filterBy => 'age',
    filterOp => 'equals',
    filterValue => '37'
  }
), 'View is fine');


$dom = Mojo::DOM->new->parse($view);
is($dom->at('tbody > tr:nth-child(1) > td > a')->text, 'Maria', 'Filter');
is($dom->at('tbody > tr:nth-child(2) > td > a')->text, 'Richard', 'Filter');
ok(!$dom->at('tbody > tr:nth-child(3)'), 'Filter');


# Test filter with demon
my $t = Test::Mojo->new;

get '/' => sub {
  my $c = shift;
  return $c->render(
    inline => $c->oro_view(
      display => [
        Name => {
          col => 'prename',
          filter => 1
        }
      ],
      table => 'Name',
    )
  );
};

get '/line' => sub {
  my $c = shift;
  return $c->render(
    inline => $c->oro_filter_rule
  );
};

$t->get_ok('/')
  ->text_is('tbody tr:nth-child(1) td a', 'Dorothy')
  ->text_is('tbody tr:nth-child(9) td a', 'Susan')
  ->element_exists('tbody tr:nth-child(10)')
  ->element_exists_not('tr.oro-filter');

$t->get_ok('/?sortBy=prename&sortOrder=ascending')
  ->text_is('tbody tr:nth-child(1) td a', 'Charles')
  ->element_exists('tbody tr:nth-child(10)')
  ->element_exists_not('tr.oro-filter');

$t->get_ok('/?sortBy=prename&sortOrder=ascending&filterBy=sex&filterOp=equals&filterValue=female')
  ->text_is('tbody tr:nth-child(1) td a', 'Dorothy')
  ->element_exists('tr.oro-filter')
  ->text_is('tr.oro-filter th span.oro-filter-rule', '"sex" equals "female"')
  ->element_exists("tr.oro-filter th a[href*='sortBy=prename'][href*=sortOrder]:not([href*=filterBy])")
  ->text_is('tbody tr:nth-child(1) td a', 'Dorothy')
  ->text_is('tbody tr:nth-child(9) td a', 'Susan')
  ->element_exists_not('tbody tr:nth-child(10)')
  ;

$t->get_ok('/line?sortBy=prename&sortOrder=ascending&filterBy=sex&filterOp=equals&filterValue=female')
  ->text_is('span.oro-filter-rule', '"sex" equals "female"')
  ->element_exists('a.remove-filter')
  ->element_exists('a.remove-filter span');


$t->get_ok('/line?sortBy=prename&sortOrder=ascending')
  ->element_exists_not('span.oro-filter-rule')
  ->element_exists_not('a.remove-filter')
  ->element_exists_not('a.remove-filter span');


# TODO: Check for injection!


# Value not existent
app->oro->insert(
  Name => {
    prename => 'Hannes',
    surname => 'Mitweida',
  });

get '/extended' => sub {
  my $c = shift;
  return $c->render(
    inline => $c->oro_view(
      display => [
        Name => {
          col => 'prename',
          filter => 1
        },
        Sex => {
          col => 'sex',
          filter => 1
        }
      ],
      table => 'Name',
    )
  );
};

$t->get_ok('/extended?filterOp=equals&filterBy=prename&filterValue=Hannes')
  ->text_is('tbody tr td:nth-child(1) a', 'Hannes')
  ->element_exists_not('tbody tr td:nth-child(2) a')
  ;

done_testing;
