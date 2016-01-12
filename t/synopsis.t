#!/usr/bin/env perl
use Test::Mojo;
use Test::More;
use Mojolicious::Lite;

plugin 'Oro' => {
  default => {
    file => ':memory:',
    init => sub {
      my $oro = shift;

      $oro->do(<<NAME) or return -1;
  CREATE TABLE User (
    id    INTEGER PRIMARY KEY,
    name  TEXT NOT NULL,
    age   INTEGER
  )
NAME

      $oro->insert(
	User =>
	  [qw/name age/] => (
	    [qw/James 31/],
	    [qw/John 32/],
	    [qw/Robert 33/],
	    [qw/Michael 34/]
          )
        );
    }
  }
};

plugin 'Oro::Viewer' => {
  default => 10,
  max_count => 15
};

my $t = Test::Mojo->new;


my $view = $t->app->oro_view(display => [Name => 'name', Alter => 'age'], table => 'User');

like($view, qr!Name!, 'Titel - Name');
like($view, qr!Alter!, 'Titel - Alter');
like($view, qr!James!, 'Name');
like($view, qr!John!, 'Name');
like($view, qr!Michael!, 'Name');
like($view, qr!Robert!, 'Name');

done_testing;
