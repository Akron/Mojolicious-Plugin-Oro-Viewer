#!/usr/bin/env perl
use lib '../lib';
use Mojolicious::Lite;

plugin Oro => {
  default => {
    file => 'example.sqlite',
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

      $oro->do(<<BOOK) or return -1;
CREATE TABLE Book (
  id         INTEGER PRIMARY KEY,
  title      TEXT,
  year       INTEGER,
  author_id  INTEGER,
  FOREIGN KEY (author_id)
    REFERENCES Name(id)
)
BOOK

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
      $oro->insert(Name => {
      sex => 'female',
      prename => 'Barbara',
      surname => 'White'
    }) or return -1;
    $oro->txn(
      sub {
	my $oro = shift;
	foreach my $id (1..20) {
	  $oro->insert(Book => {
	    author_id => $id,
	    title => 'My ' . $id . ' book'
	  });
	};
      });
    }
  }
};

plugin 'TagHelpers::Pagination' => {
    separator => '',
    ellipsis => '<span><i class="icon-ellipsis-horizontal"></i></span>',
    current => '<span>{current}</span>',
    page => '<span class="page-nr">{page}</span>',
    next => '<span></span>',
    prev => '<span></span>'
};

plugin 'Oro::Viewer' => {
  default_count => 10,
  max_count => 15
};

# Todo: Define class names for columns: Alter => ['age', class => 'oro-age']
get '/' => sub {
  shift->render(
    template => 'index',
    oro_view => {
      table => 'Name',
      display => [
        Firstname => 'prename',
	Surname   => 'surname',
	Age       => ['age', 'integer'],
	Delete => sub {
	  my ($c, $row) = @_;
	  return '<a href="/delete?user=' . $row->{id} . '">Delete user</a>';
	}
      ]
    }
  );
};

app->start;

__DATA__

@@ index.html.ep
<!DOCTYPE html>
<html>
  <head><title>Sort</title></head>
%= stylesheet '/css/style.css'
  <body>
%= oro_view( stash 'oro_view' );
  </body>
</html>
