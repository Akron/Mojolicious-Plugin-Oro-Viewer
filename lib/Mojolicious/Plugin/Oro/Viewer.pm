package Mojolicious::Plugin::Oro::Viewer;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::ByteStream 'b';
use Mojo::Util qw/xml_escape quote/;

our $VERSION = '0.05';

# Todo: Support fields that are not columns (but may be colored)
# Todo: Support filter_by_row (which filters by the value of a field,
#       making all row values links)
# Todo: Support filter_by_search (which introduces an input field
#       for searching below the table header)
# Todo: Compare with
#       https://simonwillison.net/2017/Nov/13/datasette/

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
  $param->{del_marker}    //= 'x';

  # Load pagination plugin
  unless ($mojo->renderer->helpers->{'pagination'}) {
    $mojo->plugin('TagHelpers::Pagination');
  };

  # Establish 'oro_filter_by' helper
  $mojo->helper(
    oro_filter_by => sub {
      my $c = shift;

      my $view = shift if @_ == 3;
      my ($key, $value) = @_;

      return '' unless $value;

      return $c->link_to(
        $view // $value,
        $c->url_with->query({
          startPage   => 1,
          filterBy    => $key,
          filterOp    => 'equals',
          filterValue => $value
        })
      );
    }
  );


  # Line with filter information
  $mojo->helper(
    oro_filter_rule => sub {
      my ($c, $del_marker) = @_;
      $del_marker //= $param->{del_marker};

      return '' unless $c->param('filterBy');

      # Add filter description
      my $str = '';
      $str .= quote($c->param('filterBy'));
      $str .= ' ' . ($c->param('filterOp') // 'equals');
      if (my $v = $c->param('filterValue')) {
        $str .= ' ' . quote($v);
      };

      my $query = $c->url_with;

      # Remove filter parameters
      $query->query->remove('filterBy')->remove('filterOp')->remove('filterValue');

      # Escape filter description
      return b(
        '<span class="oro-filter-rule">' . xml_escape($str) . '</span> ' .
          # Add remove link
          $c->link_to(b('<span>' . $del_marker . '</span>'), $query, class => 'remove-filter')
        );
    }
  );

  # Establish 'oro_view' helper
  $mojo->helper(
    oro_view => sub {
      my $c = shift;

      my %param = @_ % 2 ? %{ shift() } : @_;

      # Get result (as from DBIx::Oro::list)
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
        # No count set
        unless ($query->{count}) {

          # Set to default
          $query->{count} = $param{default_count} // $param->{default_count}
        }

        # Requested count exceeds maximum count
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
      my $table = '<table class="oro-view">' . "\n";
      $table .= "  <thead>\n";

      # Get fields from result
      my (%result_fields, $rf);
      if ($result->{fields}) {
        $result_fields{$_} = 1 foreach @{$result->{fields}};
        $rf = join(',', keys %result_fields);
      };

      # Reorganize display
      my @order;
      for (my $i = 0; $i < scalar @$display; $i += 2) {

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

      # Add filter info
      if ($result->{filterBy}) {

        # Set filter parameter
        $c->param(filterBy => $result->{filterBy});
        $c->param(filterValue => $result->{filterValue}) if $result->{filterValue};
        $c->param(filterOp => $result->{filterOp}) if $result->{filterOp};

        # Pass to filter line
        $table .= '    <tr class="oro-filter"><th colspan="' . scalar @order . '">';
        $table .= $c->oro_filter_rule($param{del_marker});
        $table .= "</th></tr>\n";
      };

      $table .= '    <tr>';

      # Create table head
      foreach (@order) {
        my @column_classes;

        # Field name
        my $field;

        # Simple field value
        if (!ref $_->[1]) {
          $field = $_->[1];
        }

        # Hash field value
        elsif (ref $_->[1] eq 'HASH') {
          if (my $col = $_->[1]->{col}) {

            # Col is a string
            unless (ref $col) {
              $field = $col;
            }

            # Col is an array reference
            else {
              $field = $col->[0];
              push @column_classes, @{$col}[1..$#{$col}];
            };
          };
        }

        # Array field value
        elsif (ref $_->[1] eq 'ARRAY' && !ref $_->[1][0]) {
          $field = $_->[1][0];
        };

        # There is a field defined - it's sortable!
        my $th = '';
        if ($field) {

          # Preset sorting field for URL
          my %hash = ( sortBy => $field );

          # Preset fields for URL
          $hash{fields} = $rf if $rf;
          push @column_classes, 'oro-sortable';

          # Check for sorting
          if ($result->{sortBy} && ($result->{sortBy} eq $field)) {

            # Is the active column
            push @column_classes, 'oro-active';

            # Check sort order
            if (!$result->{sortOrder} || $result->{sortOrder} eq 'ascending') {
              push @column_classes, 'oro-' . ($hash{sortOrder} = 'descending');
            }

            # Default to ascending sort order
            else {
              push @column_classes, 'oro-' . ($hash{sortOrder} = 'ascending');
            };
          }

          # No sorting given - default to ascending
          else {
            push @column_classes, 'oro-' . ($hash{sortOrder} = 'ascending');
          };

          if ($result->{filterBy}) {
            $hash{filterBy} = $result->{filterBy};
            $hash{filterOp} = $result->{filterOp} if $result->{filterOp};
            $hash{filterValue} = $result->{filterValue} if $result->{filterValue};
          };

          # Create links
          $th = '<a href="' . xml_escape($c->url_with->query(\%hash)) . '">' .
            $_->[0] . '</a>';
        }
        else {
          $th = $_->[0];
        };

        $table .= '<th';
        $table .= ' class="' . join(' ', @column_classes) . '"' if @column_classes;
        $table .= '>' . $th . '</th>';
      };

      $table .= "</tr>\n";
      $table .= "  </thead>\n";

      # Create table footer with pagination
      $table .= "  <tfoot>\n";
      $table .= '    <tr><td class="pagination" colspan="' . scalar @order . '">';

      # Add pagination
      $table .= $c->pagination(
        $result->{startPage},
        $pages,
        $c->url_with->query({startPage => '{page}'})
      );
      $table .= "</td></tr>\n";
      $table .= "  </tfoot>\n";


      # Create table border
      $table .= "  <tbody>\n";

      # Iterate over all result entries
      foreach my $v (@{$result->{entry}}) {

        my @row_classes = ();

        my $cells;
        # Iterate over all displayable columns
        foreach (@order) {

          my @cell_classes = ();
          my $value;

          # Field name complex
          if (ref $_->[1]) {

            # Array reference
            if (ref $_->[1] eq 'ARRAY') {
              my ($first, %attributes) = @{$_->[1]};

              # First is a callback - treat as cell
              if (ref $first) {
                $value = $first->( $c, $v );
              }

              # Deprecated
              elsif ($attributes{process}) {
                $value = $attributes{process}->( $c, $v );
              }

              # First is cell content
              else {
                $value = xml_escape( $v->{ $first } ) if $v->{ $first };
              };

              # Deprecated
              if ($attributes{class}) {
                push @cell_classes, $attributes{class};
              };
            }

            # Cell value is given as a hash
            elsif (ref $_->[1] eq 'HASH') {
              my $hash = $_->[1];
              if ($hash->{cell}) {
                ($value, @cell_classes) = $hash->{cell}->( $c, $v );
              }

              # Use column by default
              else {
                $value = $v->{ $hash->{col} };
              };

              if ($hash->{row}) {
                push @row_classes, $hash->{row}->( $c, $v );
              };

              # Wrap in a filter
              if ($hash->{filter}) {

                # Embed filter link
                $value = $c->oro_filter_by(
                  $value => ($hash->{col}, $v->{ $hash->{col} })
                );
              };
            }

            # Callback
            else {
              $value = $_->[1]->( $c, $v );
            };

            # Append attribute information
            #      while (my ($n, $v) = each %attributes) {
            #        $cells .= qq{ $n="$v"} if $v && $n ne 'process';
            #      };
          }

          # Field name is simple
          else {
            $value .= xml_escape( $v->{ $_->[1] } ) if $v->{ $_->[1] };
          }

          $cells .= '<td';
          @cell_classes = grep { $_ } @cell_classes;
          $cells .= ' class="' . join(' ', @cell_classes) . '"' if @cell_classes;
          $cells .= '>';
          $cells .= $value if $value;
          $cells .= '</td>';
        };

        $table .= '<tr';
        @row_classes = grep { $_ } @row_classes;
        $table .= ' class="' . join(' ', @row_classes) . '"' if @row_classes;
        $table .= '>' . $cells . "</tr>\n";
      };
      $table .= "  </tbody>\n";

      # Return generated value
      return b($table . "</table>\n");
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

=encoding utf8

=head1 NAME

Mojolicious::Plugin::Oro::Viewer - Show Oro tables in your Mojolicious apps


=head1 SYNOPSIS

  # In Mojolicious::Lite startup
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

  %# In Templates
  %= oro_view display => [Name => 'name', Alter => 'age'], table => 'User'

  # <table class="oro-view">
  #   <thead>
  #     <tr>
  #       <th class="oro-sortable oro-ascending">
  #         <a href="?sortOrder=ascending&amp;sortBy=name">Name</a>
  #       </th>
  #       <th class="oro-sortable oro-ascending">
  #         <a href="?sortOrder=ascending&amp;sortBy=age">Alter</a>
  #       </th>
  #     </tr>
  #   </thead>
  #   <tfoot>
  #     <tr>
  #       <td class="pagination" colspan="2">
  #         <a rel="prev">&lt;</a>&nbsp;
  #         <a rel="self">[1]</a>&nbsp;
  #         <a rel="next">&gt;</a>
  #       </td>
  #     </tr>
  #   </tfoot>
  #   <tbody>
  #     <tr><td>James</td><td>31</td></tr>
  #     <tr><td>John</td><td>32</td></tr>
  #     <tr><td>Michael</td><td>34</td></tr>
  #     <tr><td>Robert</td><td>33</td></tr>
  #   </tbody>
  # </table>


=head1 DESCRIPTION

Display L<DBIx::Oro> tables in your Mojolicious applications with support
for sorting and paging - normally based on query parameters.

B<This is early software, please use it with care!>
B<Things may change or this module may be deprecated until it is on CPAN!>

=head1 METHODS

=head2 register

  # Mojolicious
  $app->plugin('Oro::Viewer' => {
    max_count => 200,
    default_count => 10
  });

Called when registering the plugin.
Supports the parameters C<max_count> for maximum visible entries
per page (defaults to C<100>) and C<default_count>, for default
visible entries per page (defaults to C<25>).

All parameters can be set as part of the configuration
file with the key C<Oro-Viewer> or on registration
(that can be overwritten by configuration).


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

Render a html table with results of an L<DBIx::Oro> table.
Accepts various parameters:

=over 2

=item C<cache>

Cache support as defined in L<DBIx::Oro/select>.

=item C<default_count>

Overwrite the plugin parameter C<default_count>.

=item C<default_fields>

Preselect a set of fields that can be overwritten by the query parameter.

=item C<display>

  %= oro_view display => ['User-Name' => 'name', 'User-Age' => 'age'], table => 'User'

Define the field display by passing an array reference with pairs of field names
(to display in the head line of the table view) and field values.

  %= oro_view display => ['User' => 'name']

Field values can be passed as simple strings, refering to the name of the field column.

  %= oro_view display => ['User' => sub { my ($c, $row) = @_; return $row->{id}; } ]

Field values can be passed as a callback, returning the cell value.

  %= oro_view display => ['User' => { col => 'handle'}]

Field values can also be passed as hash references, with the following parameters.

=over 4

=item C<col>

  col => 'handle'
  col => [qw/handle handle-class/]

The column to display.
In case of an array reference, the first parameter is the field column name,
following parameters will be added to the C<class> attribute
of the table column.


=item C<cell>

  cell => sub {
    my ($c, $row) = @_;
    return $row->{id};
  }

The cell content to display, returned from a callback.
Further values returned may be class names attached to the cell.
If the cell value is not given explicitely, the raw value from
C<col> is returned.


=item C<filter>

  filter => 1

If true, the field value is wrapped in a filtering link using col.


=item C<row>

  row => sub {
    my ($c, $row) = @_;
    return ($row->{id} % 2) ? 'odd' : 'even';
  }

Return class values attached to the row by a callback.

=back

=item C<fields>

An array of fields. In case this is defined, query fields are being ignored.

=item C<max_count>

Overwrite the plugin parameter C<max_count>.

=item C<min_fields>

Array of fields that are necessary, although they are not queried.

=item C<oro_handle>

The L<DBIx::Oro> handle, defaults to C<default>

=item C<query>

A hash of query parameters for L<DBIx::Oro/list>, defaults to C<$c-E<gt>req-E<gt>params>.

=item C<result>

A L<DBIx::Oro/list> formatted result array.
This will override all other query or filter related parameters.

=item C<startIndex>

I<startIndex is not supported - in favor of C<startPage>!>

=item C<table>

The L<DBIx::Oro> table to display.

=item C<valid_fields>

Give an array of field names that are valid for querying.
Invalid fields are ignored.

=back

=head1 DEPENDENCIES

L<Mojolicious>,
L<DBIx::Oro>,
L<Mojolicious::Plugin::TagHelpers::Pagination>,
L<Mojolicious::Plugin::Oro>.


=head1 AVAILABILITY

  https://github.com/Akron/Mojolicious-Plugin-Oro-Viewer


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2015-2017, L<Nils Diewald|http://nils-diewald.de/>.

This program is free software, you can redistribute it
and/or modify it under the terms of the Artistic License version 2.0.

=cut
