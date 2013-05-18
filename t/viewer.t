#!/usr/bin/env perl
use Test::Mojo;
use Test::More;
use Mojolicious::Lite;

use lib '../lib';

plugin 'Oro' => {
  default => {
    file => ':memory:',
    init => sub {
      my $oro = shift;
      $oro->do(<<'User') or return -1;
CREATE TABLE User (
  id    INTEGER PRIMARY KEY,
  name  TEXT,
  age   INTEGER
)
User
      $oro->do(<<'Book') or return -1;
CREATE TABLE Book (
  id        INTEGER PRIMARY KEY,
  author_id INTEGER,
  title     TEXT,
  year      INTEGER
)
Book

      $oro->insert(User => [qw/name age/] => (
	[qw/Peter 28/],
	[qw/Michael 31/],
	[qw/Jonathan 26/],
	[qw/Julian 48/],
	[qw/Christoph 9/]
      )) or return -1;

      $oro->insert(Book => [qw/title year author_id/] => (
	[qw/Es 1990 1/],
	[qw/Er 1991 1/],
	[qw/Sie 1992 2/],
	[qw/Wir 1993 3/],
      )) or return -1;
    }
  }
};
plugin 'Oro::Viewer';

my $t = Test::Mojo->new;

my $app = $t->app;

get '/' => sub {
  my $c = shift;
  my $view = $c->oro_view(
    oro_handle => 'default',
    table      => 'User',
    query      => {
      sortBy => 'name',
      %{ $c->req->params->to_hash },
      fields => [qw/id name age/],
      count  => 25
    },
    display    => [
      'Name'   => 'name',
      'Age'    => 'age',
      'Delete' => sub {
	# Makes it possible to return json as well on request
	my $c = shift;
	my $row = shift;
	return '<a href="/delete/?user=' . $row->{id} . '">Delete</a>'
      }
    ]
  );

  return $c->render( inline => $view );
};

$t->get_ok('/?sortBy=age&sortOrder=descending&count=3&startPage=1')
  ->text_is('table thead tr th.oro-sortable a', 'Name')
  ->element_exists('table tfoot tr[colspan=3]')
  ->text_is('table tbody tr td', 'Julian')
  ->text_is('table tbody tr td a', 'Delete');
