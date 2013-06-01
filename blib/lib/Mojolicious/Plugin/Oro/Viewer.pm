package Mojolicious::Plugin::Oro::Viewer;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::ByteStream 'b';
use Mojo::Util qw/xml_escape/;

our $VERSION = 0.01;

# Support Javascript by providing javascript code that takes
# the pagination and uses it as a template for further pagination
# and of course for sorting!

# Support json

# Maybe not as Oro::Viewer but as Mojolicious::Plugin::TableView
# In that case it only accepts hash refs etc. and works fine with DBIx::Oro::ComplexValues!
# table_view({ itemsPerPage => ..., sortBy => });

# Support:
#  - default_fields
#  - necessary_fields


# Register plugin
sub register {
  my ($plugin, $mojo, $param) = @_;

  $param ||= {};

  # Load parameter from Config file
  if (my $config_param = $mojo->config('Oro-Viewer')) {
    $param = { %$config_param, %$param };
  };

  # Default values
  $param->{max_count}     //= 100;
  $param->{default_count} //= 25;

  # Load pagination plugin
  unless ($mojo->renderer->helpers->{'pagination'}) {
    $mojo->plugin('TagHelpers::Pagination');
  };

  # Establish 'oro_view' helper
  $mojo->helper(
    oro_view => sub {
      my $c = shift;

      my %param = @_ % 2 ? %{ shift() } : @_;

      # Get result (as from DBIx::Oro::list
      my $result = $param{result};

      unless ($result) {
	my $oro_handle = $param{oro_handle} // undef;
	my $table = $param{table};

	return '[No table selected]' unless $table;

	# Get query parameter
	my $query = $param{query} // $c->req->params->to_hash;

	# startIndex is not supported
	delete $query->{startIndex};

	# Get count value and check if it is valid
	unless ($query->{count}) {

	  # Set to default
	  $query->{count} = $param{default_count} // $param->{default_count}
	}

	# requested count exceeds maximum count
	elsif ($query->{count} > ($param{max_count} // $param->{max_count})) {

	  # Has to be maximum
	  $query->{count} = ($param{max_count} // $param->{max_count});
	};

	# Fields are predefined
	if ($param{fields}) {
	  $query->{fields} = $param{fields};
	}

	# Use and check query fields
	elsif ($query->{fields}) {

	  # Filter fields
	  $query->{fields} = _filter_fields(
	    $query->{fields},
	    $param{valid_fields},
	    $param{min_fields}
	  );
	}

	# Fields are not defined
	elsif ($param->{default_fields}) {
	  $query->{fields} = $param->{default_fields};
	};

	# Support cache
	if ($param{cache}) {
	  $query->{-cache} = $param{cache};
	}

	# Do not support user cache support!
	else {
	  delete $query->{-cache};
	};

	# Get table object
	my $oro = $c->oro($oro_handle)->table($table);

	# Retrieve from database
	$result = $oro->list($query);
      };

      return '[Unable to list result]' unless $result;

      # Get display parameter
      my $display = $param{display};

      # Calculate pages
      my $pages = int($result->{totalResults} / $result->{itemsPerPage}) +
	(($result->{totalResults} % $result->{itemsPerPage}) == 0 ? 0 : 1);


      # Get sortBy value
      my $sort_by = $result->{sortBy};

      # Init table
      my $x = '<table class="oro-view">' . "\n  <thead>\n    <tr>";

      # Get fields from result
      my (%result_fields, $rf);
      if ($result->{fields}) {
	$result_fields{$_} = 1 foreach @{$result->{fields}};
	$rf = join(',', keys %result_fields);
      };

      # Reorganize display
      my @order;
      for (my $i = 0; $i < scalar @$display; $i+=2) {

	# Filter fields that are not selected
	if ($rf) {
	  my $f = $display->[$i+1];

	  # These fields are not needed
	  if (!ref $f || (ref $f eq 'ARRAY' && !ref $f->[0])) {
	    $f = $f->[0] if ref $f;

	    next unless exists $result_fields{$f};
	  };
	};

	push(@order, [$display->[$i] => $display->[$i+1]]);
      };

      # Create table head
      foreach (@order) {
	$x .= '<th';

	# Field name
	my $field;

	# Simple field value
	if (!ref $_->[1]) {
	  $field = $_->[1];
	}

	# Array field value
	elsif (ref $_->[1] eq 'ARRAY' && !ref $_->[1][0]) {
	  $field = $_->[1][0];
	};

	if ($field) {

	  # Preset sorting field for URL
	  my %hash = ( sortBy => $field );

	  # Preset fields for URL
	  $hash{fields} = $rf if $rf;
	  $x .= ' class="oro-sortable';

	  # Check for sorting
	  if ($result->{sortBy} && ($result->{sortBy} eq $field)) {

	    # Is the active column
	    $x .= ' oro-active';

	    # Check sort order
	    if (!$result->{sortOrder} || $result->{sortOrder} eq 'ascending') {
	      $x .= ' oro-' . ($hash{sortOrder} = 'descending');
	    }

	    # Default to ascending sort order
	    else {
	      $x .= ' oro-' . ($hash{sortOrder} = 'ascending');
	    };
	  }

	  # No sorting given - default to ascending
	  else {
	    $x .= ' oro-' . ($hash{sortOrder} = 'ascending');
	  };

	  # Create links
	  $x .= '"><a href="' . xml_escape($c->url_with->query([%hash])) . '">' .
	        $_->[0] . '</a></th>';
	}

	# No sorting allowed for this topic
	else {
	  $x .= '>' . $_->[0] . '</th>';
	};
      };
      $x .= "</tr>\n  </thead>\n";


      # Create table footer with pagination
      $x .= "  <tfoot>\n";
      $x .= '    <tr><td class="pagination" colspan="' . scalar @order . '">';

      # Add pagination
      $x .= $c->pagination(
	$result->{startPage},
	$pages,
	$c->url_with->query([startPage => '{page}'])
      );
      $x .= "</td></tr>\n  </tfoot>\n";


      # Create table border
      $x .= "  <tbody>\n";

      # Iterate over all result entries
      foreach my $v (@{$result->{entry}}) {
	$x .= '    <tr>';

	# Iterate over all displayable columns
	foreach (@order) {
	  $x .= '<td';

	  # Field name is simple
	  unless (ref $_->[1]) {
	    $x .= '>';
	    $x .= xml_escape( $v->{ $_->[1] } ) if $v->{ $_->[1] };
	  }

	  # Field name complex
	  else {
	    my ($value, %attributes);

	    # Array reference
	    if (ref $_->[1] eq 'ARRAY') {
	      (my $first, %attributes) = @{$_->[1]};

	      # First is a callback
	      if (ref $first) {
		$value = $first->( $c, $v );
	      }
	      elsif ($attributes{process}) {
		$value = $attributes{process}->( $c, $v );
	      }
	      else {
		$value = xml_escape( $v->{ $first } ) if $v->{ $first };
	      };
	    }

	    # Callback
	    else {
	      $value = $_->[1]->( $c, $v );
	    };

	    # Append attribute information
	    while (my ($n, $v) = each %attributes) {
	      $x .= qq{ $n="$v"} unless $n eq 'process';
	    };
	    $x .= '>';
	    $x .= $value if $value;
	  }

	  $x .= '</td>';
	};
	$x .= "</tr>\n";
      };
      $x .= "  </tbody>\n";

      # Return generated value
      return b($x . "</table>\n");
    }
  );
};


# Filter fields
sub _filter_fields {
  my ($query, $valid, $min) = @_;

  # Nothing to filter
  return $query if !$valid && !$min;

  # Create query hash
  my %query;
  foreach (ref $query ? $query : map { s/^\s*|\s$//g; $_ } split /\s*,\s*/, $query) {
    $query{$_} = 1;
  };


  # Valid array is given
  if ($valid) {

    # Create valid hash
    my %valid;
    $valid{$_} = 1 foreach @$valid;

    # Filter for validity
    foreach (keys %query) {
      delete $query{$_} unless defined $valid{$_};
    };
  };

  # No minimum fields given
  return [keys %query] unless $min;

  # Set minimum fields
  $query{$_} = 1 foreach @$min;

  # Return filtered fields
  return [keys %query];
};


1;


__END__

=pod

=head1 NAME

Mojolicious::Plugin::Oro::Viewer - Show Oro tables in your Mojolicious apps


=head1 METHODS

=head2 register

Supports also configurations at C<Oro::Viewer>.

Supports C<max_count>, defaults to C<100> and C<default_count>, defaults to C<25>.


=head1 DESCRIPTION

=head1 HELPERS

=head2 oro_view

  my $view = $c->oro_view(
    oro_handle => 'default',
    table => 'User',
    query => {
    },
    display => [
      Firstname => 'name',
      Age => ['age', 'oro-number'],
      Action => sub {
        my ($c, $row) = @_;
        return ('<a href="/delete/' . $row->{id} . '">' . $row->{id} . '</a>', 'oro-action');
      }
    ]
  );

  # In Template
  % my $result = DBIx::Oro->new('file.sqlite')->list('User' => $self->req->params);
  %= oro_view result => $result, display => [Name => 'name', Age => 'age']


C<oro_handle>, defaults to C<default>,
C<query> defaults to C<$c->req->params>.
C<startIndex> is not supported - in favor of C<startPage>.
C<default_count> can overwrite the plugin parameter C<default_count>.
C<max_count> can overwrite the plugin parameter C<max_count>.
C<default_fields> preselects a set of fields, that can be overwritten by the query parameter.
C<valid_fields> can give an array of field names that are valid for querying.
C<min_fields> can give an array of field names that are necessary, although they are not queried.
C<fields> can give an array for fields, making query fields being ignored.
C<cache> can support caches as defined in DBIx::Oro/select.

=end
