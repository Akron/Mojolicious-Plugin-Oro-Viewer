#!/usr/bin/env perl
use Test::Mojo;
use Test::More;
use Mojolicious::Lite;
use Mojo::DOM;

use lib '../lib', 'lib';

plugin Oro => {
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
    next => '<span>&gt;</span>',
    prev => '<span>&lt;</span>'
};

plugin 'Oro::Viewer' => {
  default_count => 10,
  max_count => 15
};

my $t = Test::Mojo->new;

my $app = $t->app;

# Don't warn
sub no_warn (&) {
  local $SIG{__WARN__} = sub {};
  $_[0]->();
};

is($app->oro_view(display => ['Name' => 'prename']), '[No table selected]', 'Error');
no_warn {
  is($app->oro_view(display => ['Name' => 'prename'], table => 'Book2'), '[Unable to list result]', 'Error');
};

my $view = $app->oro_view(display => ['Name' => 'prename'], table => 'Book');

like($view, qr!<span>1</span>!, 'Correct current page number');
like($view, qr!<span>&gt;</span>!, 'Correct next page');
like($view, qr!<span>&lt;</span>!, 'Correct next page');
like($view, qr!<tr><td></td></tr>!, 'Correct cells');
like($view, qr!<th class="oro-sortable oro-ascending">!, 'Correct header');

$view = $app->oro_view(display => ['Name' => 'prename'], query => { sortBy => 'prename' }, table => 'Name');

like($view, qr!<span>1</span>!, 'Correct current page number');
like($view, qr!<span>&gt;</span>!, 'Correct next page');
like($view, qr!<span>&lt;</span>!, 'Correct next page');
foreach (qw/Barbara Charles David Dorothy Elizabeth James/) {
  like($view, qr!<tr><td>$_</td></tr>!, 'Correct cells');
};
like($view, qr!<th class="oro-sortable oro-active oro-descending">!, 'Correct header');


$view = $app->oro_view(display => ['Name' => 'prename'], query => { sortBy => 'prename', count => 2 }, table => 'Name');

like($view, qr!<span>1</span>!, 'Correct current page number');
like($view, qr!<span>1</span>!, 'Correct current page number');
like($view, qr!<span>&gt;</span>!, 'Correct next page');
like($view, qr!<span>&lt;</span>!, 'Correct next page');
foreach (qw/Barbara Charles/) {
  like($view, qr!<tr><td>$_</td></tr>!, 'Correct cells');
};
foreach (qw/David Dorothy Elizabeth James/) {
  unlike($view, qr!<tr><td>$_</td></tr>!, 'Correct cells');
};
like($view, qr!<th class="oro-sortable oro-active oro-descending">!, 'Correct header');

$view = $app->oro_view(
  display => [
    'Name' => 'prename',
    Surname => [
      'surname',
      process => sub {
	return '--' . $_[1]->{surname} . '--'
      }]
  ],
  query => {
    sortBy => 'prename',
    count => 2
  },
  table => 'Name'
);

like($view, qr!<tr><td>Barbara</td><td>--White--</td></tr>!, 'Correct cells');
like($view, qr!<tr><td>Charles</td><td>--Davies--</td></tr>!, 'Correct cells');
like($view, qr!<th class="oro-sortable oro-active oro-descending">!, 'Correct header');

$view = $app->oro_view(
  display => [
    'Name' => ['prename', class => 'test1'],
    Surname => [
      'surname',
      process => sub {
	return ('--' . $_[1]->{surname} . '--')
      },
      class => 'test2']
  ],
  query => {
    sortBy => 'prename',
    sortOrder => 'descending',
    count => 2
  },
  table => 'Name'
);

like($view, qr!<tr><td class="test1">William</td><td class="test2">--Williams--</td></tr>!, 'Correct cells');

like($view, qr!<tr><td class="test1">Thomas</td><td class="test2">--Wright--</td></tr>!, 'Correct cells');
like($view, qr!<th class="oro-sortable oro-active oro-ascending">!, 'Correct header');

get '/' => sub {
  my $c = shift;

  my $param = $c->req->params->to_hash;

  $param->{fields} //= 'id,prename,surname,age';
  unless ($param->{fields} =~ /(^|\s*,\s*)id(\s*,\s*|$)/) {
    $param->{fields} .= ',id';
  };

  my $view = $c->oro_view(
    oro_handle => 'default',
    table      => 'Name',
    query      => {
      sortBy => 'prename',
      count  => 25,
      %$param
    },
    display    => [
      'Vorname'   => 'prename',
      'Nachname'  => ['surname', class => 'test3'],
      'Alter'     => ['age', class => 'ageclass'],
      'Action' => sub {
	# Makes it possible to return json as well on request
	my $c = shift;
	my $row = shift;
	return '<a href="/delete/?user=' . $row->{id} . '">Delete</a>'
      }
    ]
  );

  return $c->render( inline => $view );
};

get '/secure' => sub {
  my $c = shift;

  my $view = $c->oro_view(
    oro_handle => 'default',
    table      => 'Name',
    valid_fields => [qw/id prename surname age sex/],
    default_fields => [qw/id prename surname age/],
    min_fields => [qw/id/],
    query      => {
      sortBy => 'prename',
      count  => 25,
      %{ $c->req->params->to_hash }
    },
    display    => [
      'Vorname'   => 'prename',
      'Geschlecht' => ['sex', class => 'sexclass'],
      'Nachname'  => ['surname', class => 'test3'],
      'Alter'     => ['age', class => 'ageclass'],
      'Action' => sub {
	# Makes it possible to return json as well on request
	my $c = shift;
	my $row = shift;
	return '<a href="/delete/?user=' . $row->{id} . '">Delete</a>'
      }
    ]
  );

  return $c->render( inline => $view );
};


get '/secure' => sub {
  my $c = shift;

  my $view = $c->oro_view(
    oro_handle => 'default',
    table      => 'Name',
    default_fields => [qw/id prename surname age/],
    query      => {
      sortBy => 'prename',
      count  => 25,
      %{ $c->req->params->to_hash }
    },
    display    => [
      'Vorname'   => 'prename',
      'Nachname'  => ['surname', class => 'test3'],
      'Geschlecht' => ['sex', class => 'sexclass'],
      'Alter'     => ['age', class => 'ageclass'],
      'Action' => sub {
	# Makes it possible to return json as well on request
	my $c = shift;
	my $row = shift;
	return '<a href="/delete/?user=' . $row->{id} . '">Delete</a>'
      }
    ]
  );

  return $c->render( inline => $view );
};

get '/sortcallback' => sub {
  my $c = shift;

  my $view = $c->oro_view(
    oro_handle => 'default',
    table      => 'Name',
    default_fields => [qw/id prename surname age/],
    valid_fields   => [qw/id prename surname age sex/],
    min_fields     => [qw/id sex/],
    query      => {
      sortBy => 'prename',
      count  => 25,
      %{ $c->req->params->to_hash }
    },
    display    => [

      # Single value
      'Vorname'   => 'prename',

      # Array
      'Nachname'  => ['surname', class => 'test3'],

      # Array with process
      'Geschlecht' => ['sex', process => sub {
	  return '--' . $_[1]->{sex} . '--';
	}, class => 'sexclass'],

      # Hash
      'Alter'     => {
	col => ['age', 'integer'],
	row => sub {
	  return pop->{sex} . 'rowclass';
	},
	cell => sub {
	  return pop->{age}, 'ageclass';
	}
      },

      # Callback
      'Action' => sub {
	# Makes it possible to return json as well on request
	my $c = shift;
	my $row = shift;
	return '<a href="/delete/?user=' . $row->{id} . '">Delete</a>'
      }
    ]
  );

  return $c->render( inline => $view );
};


$t->get_ok('/')
  ->text_is('tbody tr td', 'Barbara')
  ->text_is('tbody tr td.test3', 'White')
  ->text_is('tbody tr:nth-child(1) td', 'Barbara')
  ->text_is('tbody tr:nth-child(2) td', 'Charles')
  ->text_is('tbody tr:nth-child(3) td', 'David')
  ->text_is('tbody tr:nth-child(15) td', 'Patricia')
  ->element_exists_not('tbody tr:nth-child(16) td')
  ->text_is('tbody tr td a[href]', 'Delete')
  ->text_is('th.oro-sortable.oro-active.oro-descending a[href]', 'Vorname')
  ->text_is('th.oro-sortable.oro-ascending a[href]', 'Nachname')
  ->text_is('th:nth-child(4)', 'Action');

$t->get_ok('/?sortBy=surname')
  ->text_is('tbody tr td', 'Michael')
  ->text_is('tbody tr td.test3', 'Brown')
  ->text_is('tbody tr:nth-child(1) td', 'Michael')
  ->text_is('tbody tr:nth-child(2) td', 'Dorothy')
  ->text_is('tbody tr:nth-child(3) td', 'Charles')
  ->text_is('tbody tr:nth-child(15) td', 'Linda')
  ->element_exists_not('tbody tr:nth-child(16) td')
  ->text_is('tbody tr td a[href]', 'Delete')
  ->text_is('th.oro-sortable.oro-active.oro-descending a[href]', 'Nachname')
  ->text_is('th.oro-sortable.oro-ascending a[href]', 'Vorname')
  ->text_is('th:nth-child(4)', 'Action');

$t->get_ok('/?sortBy=surname&count=2')
  ->text_is('tbody tr td', 'Michael')
  ->text_is('tbody tr td.test3', 'Brown')
  ->text_is('tbody tr:nth-child(1) td', 'Michael')
  ->text_is('tbody tr:nth-child(2) td', 'Dorothy')
  ->element_exists_not('tbody tr:nth-child(3) td')
  ->text_is('tbody tr td a[href]', 'Delete')
  ->text_is('th.oro-sortable.oro-active.oro-descending a[href]', 'Nachname')
  ->text_is('th.oro-sortable.oro-ascending a[href]', 'Vorname')
  ->text_is('th:nth-child(4)', 'Action');

$t->get_ok('/?sortBy=surname&count=2&fields=prename,age')
  ->text_is('tbody tr td', 'Michael')
  ->element_exists_not('tbody tr td.test3')
  ->text_is('tbody tr:nth-child(1) td', 'Michael')
  ->text_is('tbody tr:nth-child(1) td.ageclass', 34)
  ->element_exists_not('tbody tr:nth-child(1) td.sexclass')
  ->text_is('tbody tr:nth-child(2) td', 'Dorothy')
  ->text_is('tbody tr:nth-child(2) td.ageclass', 40)
  ->element_exists_not('tbody tr:nth-child(3) td')
  ->text_is('tbody tr td a[href]', 'Delete')
  ->text_is('th.oro-sortable.oro-ascending a[href]', 'Vorname')
  ->text_is('th:nth-child(3)', 'Action')
  ->text_is('.pagination a:nth-last-child(2) span', 10);


no_warn {
  $t->get_ok('/?sortBy=surname&count=2&fields=prename,age,check')
    ->element_exists_not('tbody tr');
};

$t->get_ok('/secure?sortBy=surname&count=2&fields=prename,age,check,sex')
  ->text_is('tbody tr td', 'Michael')
  ->element_exists_not('tbody tr td.test3')
  ->text_is('tbody tr:nth-child(1) td', 'Michael')
  ->text_is('tbody tr:nth-child(1) td.ageclass', 34)
  ->text_is('tbody tr:nth-child(1) td.sexclass', 'male')
  ->text_is('tbody tr:nth-child(2) td', 'Dorothy')
  ->text_is('tbody tr:nth-child(2) td.ageclass', 40)
  ->text_is('tbody tr:nth-child(1) td.sexclass', 'male')
  ->element_exists_not('tbody tr:nth-child(3) td')
  ->text_is('tbody tr td a[href]', 'Delete')
  ->text_is('th.oro-sortable.oro-ascending a[href]', 'Vorname')
  ->text_is('th:nth-child(2) a', 'Geschlecht')
  ->text_is('th:nth-child(3) a', 'Alter')
  ->text_is('th:nth-child(4)', 'Action')
  ->text_is('.pagination a:nth-last-child(2) span', 10);

$t->get_ok('/secure?sortBy=surname&count=2&fields=prename,age,check,sex&startPage=2')
  ->text_is('tbody tr td', 'Charles')
  ->element_exists_not('tbody tr td.test3')
  ->text_is('tbody tr:nth-child(1) td', 'Charles')
  ->text_is('tbody tr:nth-child(1) td.ageclass', 38)
  ->text_is('tbody tr:nth-child(1) td.sexclass', 'male')
  ->text_is('tbody tr:nth-child(2) td', 'Patricia')
  ->text_is('tbody tr:nth-child(2) td.ageclass', 32)
  ->text_is('tbody tr:nth-child(1) td.sexclass', 'male')
  ->element_exists_not('tbody tr:nth-child(3) td')
  ->text_is('tbody tr td a[href]', 'Delete')
  ->text_is('th.oro-sortable.oro-ascending a[href]', 'Vorname')
  ->text_is('th:nth-child(2) a', 'Geschlecht')
  ->text_is('th:nth-child(3) a', 'Alter')
  ->text_is('th:nth-child(4)', 'Action')
  ->text_is('.pagination a:nth-last-child(2) span', 10);

$t->get_ok('/secure?sortBy=surname&count=2&fields=prename,age,check,sex&startPage=2&filterBy=surname&filterOp=startsWith&filterValue=W')
  ->text_is('tbody tr td', 'William')
  ->element_exists_not('tbody tr td.test3')
  ->text_is('tbody tr:nth-child(1) td', 'William')
  ->text_is('tbody tr:nth-child(1) td.ageclass', 35)
  ->text_is('tbody tr:nth-child(1) td.sexclass', 'male')
  ->text_is('tbody tr:nth-child(2) td', 'David')
  ->text_is('tbody tr:nth-child(2) td.ageclass', 36)
  ->text_is('tbody tr:nth-child(1) td.sexclass', 'male')
  ->element_exists_not('tbody tr:nth-child(3) td')
  ->text_is('tbody tr td a[href]', 'Delete')
  ->text_is('th.oro-sortable.oro-ascending a[href]', 'Vorname')
  ->text_is('th:nth-child(2) a', 'Geschlecht')
  ->text_is('th:nth-child(3) a', 'Alter')
  ->text_is('th:nth-child(4)', 'Action')
  ->text_is('.pagination a:nth-last-child(2) span', 3);


$t->get_ok('/sortcallback?sortBy=surname&count=2&fields=prename,age,check,sex&startPage=2&filterBy=surname&filterOp=startsWith&filterValue=W')
  ->text_is('thead tr th.integer a', 'Alter')
  ->text_is('tbody tr td', 'William')
  ->element_exists_not('tbody tr td.test3')
  ->text_is('tbody tr:nth-child(1) td', 'William')
  ->text_is('tbody tr:nth-child(1) td.ageclass', 35)
  ->text_is('tbody tr:nth-child(1) td.sexclass', '--male--')
  ->text_is('tbody tr:nth-child(2) td', 'David')
  ->text_is('tbody tr:nth-child(2) td.ageclass', 36)
  ->text_is('tbody tr:nth-child(1) td.sexclass', '--male--')
  ->text_is('tbody tr.malerowclass:nth-child(2) td.ageclass', 36)
  ->element_exists_not('tbody tr:nth-child(3) td')
  ->text_is('tbody tr td a[href]', 'Delete')
  ->text_is('th.oro-sortable.oro-ascending a[href]', 'Vorname')
  ->text_is('th:nth-child(2) a', 'Geschlecht')
  ->text_is('th:nth-child(3) a', 'Alter')
  ->text_is('th:nth-child(4)', 'Action')
  ->text_is('.pagination a:nth-last-child(2) span', 3)
;


done_testing;
__END__



