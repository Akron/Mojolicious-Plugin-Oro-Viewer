package Mojolicious::Plugin::Oro::Viewer;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::ByteStream 'b';
use Mojo::Util qw/xml_escape/;

our $VERSION = 0.01;

# Support Javascript by providing javascript code that takes
# the pagination and uses it as a template for further pagination
# and of course for sorting!

# Maybe not as Oro::Viewer but as Mojolicious::Plugin::TableView
# In that case it only accepts hash refs etc. and works fine with DBIx::Oro::ComplexValues!
# table_view({ itemsPerPage => ..., sortBy => });


sub register {
  my ($plugin, $mojo, $param) = @_;

  $param->{max_count} //= 20;

  unless ($mojo->renderer->helpers->{'pagination'}) {
    $mojo->plugin('TagHelpers::Pagination');
  };

  $mojo->helper(
    oro_view => sub {
      my $c = shift;
      my %param = @_ % 2 ? %{ shift() } : @_;

      my $oro_handle = $param{oro_handle} // undef;
      my $table      = $param{table};
      my $query      = $param{query} // $c->req->params->to_hash;
      my $display    = $param{display};

      # startIndex is not supported
      delete $query->{startIndex};

      unless ($query->{count}) {
	$query->{count} = $param->{default_count}
      }
      elsif ($query->{count} > $param->{max_count}) {
	$query->{count} = $param->{max_count}
      };

      my $oro = $c->oro($oro_handle)->table($table);

      # Retrieve from database
      # Todo: Support caching!
      my $result = $oro->list($query);

      my $sort_by = $result->{sortBy};

      my $pages = int($result->{totalResults} / $result->{itemsPerPage}) +
	(($result->{totalResults} % $result->{itemsPerPage}) == 0 ? 0 : 1);

      # Check here for result!

      my $x = '<table class="oro-view">' . "\n  <thead>\n    <tr>";

      my @order;
      for (my $i = 0; $i < scalar @$display; $i+=2) {
	push(@order, [$display->[$i] => $display ->[$i+1]]);
      };


      foreach (@order) {
	$x .= '<th';

	unless (ref $_->[1]) {
	  my %hash = ( sortBy => $_->[1] );
	  $x .= ' class="oro-sortable';
	  if ($result->{sortBy} && ($result->{sortBy} eq $_->[1])) {
	    $x .= ' oro-active';
	    if (!$result->{sortOrder} || $result->{sortOrder} eq 'ascending') {
	      $hash{sortOrder} = 'descending';
	      $x .= ' oro-descending';
	    }
	    else {
	      $hash{sortOrder} = 'ascending';
	      $x .= ' oro-ascending';
	    };
	  }
	  else {
	    $hash{sortOrder} = 'ascending';
	    $x .= ' oro-ascending';
	  };
	  $x .= '"><a href="' . $c->url_with->query([%hash]) . '">';
	  $x .= $_->[0] . '</a></th>';
	}
	else {
	  $x .= '>' . $_->[0] . '</th>';
	};
      };
      $x .= "</tr>\n  </thead>\n";
      $x .= "  <tfoot>\n";
      $x .= '    <tr><td class="oro-pagination" colspan="' . scalar @order . '">';

      $x .= $c->pagination(
	$result->{startPage},
	$pages,
	$c->url_with->query([startPage => '{page}'])
      );

      $x .= "</td></tr>\n";
      $x .= "  </tfoot>\n";
      $x .= "  <tbody>\n";

      # HTML;
      foreach my $v (@{$result->{entry}}) {
	$x .= '    <tr>';
	foreach (@order) {
	  $x .= '<td>';

	  unless (ref $_->[1]) {
	    $x .= xml_escape( $v->{ $_->[1] } ) if $v->{ $_->[1] };
	  }
	  else {
	    $x .= $_->[1]->(  $c,$v );
	  }

	  $x .= '</td>';
	};
	$x .= "</tr>\n";
      };

      $x .= "  </tbody>\n";
      $x .= "</table>\n";

      return b($x);
    }
  );
};

1;

__END__


plugin 'Oro::Viewer' => {
  query => ['select' => []]
}


# Simple select:
->oro_viewer(User => [qw/name age/] => { age => { gt => 14 }})

# Joined select
->oro_viewer([
  User => [qw/name age/] => { id => 1 },
  Book => [qw/title/] => { author_id }
] => { age => { gt => 14 }})
