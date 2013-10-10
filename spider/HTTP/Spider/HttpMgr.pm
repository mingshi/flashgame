use strict;
use warnings;
#Most code of this file from HTTP::Async::Polite
package HTTP::Spider::HttpMgr;
use base 'HTTP::Async';

our $VERSION = '0.05';

use Carp;
use Data::Dumper;
use Time::HiRes qw( time sleep );
use URI;

=head1 NAME

HTTP::Spider::HttpMgr - politely process multiple HTTP requests

=head1 SYNOPSIS

See L<HTTP::Async> - the usage is unchanged.

=head1 DESCRIPTION

This L<HTTP::Async> module allows you to have many requests going on at once.
This can be very rude if you are fetching several pages from the same domain.
This module add limits to the number of simultaneous requests to a given
domain and adds an interval between the requests.

In all other ways it is identical in use to the original L<HTTP::Async>.

=head1 NEW METHODS

=head2 send_interval

Getter and setter for the C<send_interval> - the time in seconds to leave
between each request for a given domain. By default this is set to 5 seconds.

=cut

sub send_interval {
    my $self = shift;
    return scalar @_
      ? $self->_set_opt( 'send_interval', @_ )
      : $self->_get_opt('send_interval');
}

sub domain_limit {
    my $self = shift;
    return scalar @_
      ? $self->_set_opt( 'domain_limit', @_ )
      : $self->_get_opt('domain_limit');
}

=head1 OVERLOADED METHODS

These methods are overloaded but otherwise work exactly as the original
methods did. The docs here just describe what they do differently.

=head2 new

Sets the C<send_interval> value to the default of 5 seconds.

=cut

sub new {
    my $class = shift;

    my $self = $class->SUPER::new;

    # Set the interval between sends.
    $self->{opts}{send_interval} = 2;    # seconds
    $self->{opts}{domain_limit} = 2;
    $self->{opts}{connect_timeout} = 10;
    $class->_add_get_set_key('send_interval');
	$class->_add_get_set_key('domain_limit');
    $self->_init(@_);
    return $self;
}

=head2 add_with_opts

Adds the request to the correct queue depending on the domain.

=cut

sub add_with_opts {
    my $self = shift;
    my $req  = shift;
    my $opts = shift;
    my $id   = $self->_next_id;

    # Instead of putting this request and opts directly onto the to_send array
    # instead get the domain and add it to the domain's queue. Store this
    # domain with the opts so that it is easy to get at.
    my $uri    = URI->new( $req->uri );
    my $host   = $uri->host;
    my $port   = $uri->port;
    my $domain = "$host:$port";
    $opts->{_domain} = $domain;

    # Get the domain array - create it if needed.
    my $domain_arrayref = $self->{domain_stats}{$domain}{to_send} ||= [];

    push @{$domain_arrayref}, [ $req, $id ];
    $self->{id_opts}{$id} = $opts;

    $self->poke;

    return $id;
}

=head2 to_send_count

Returns the number of requests waiting to be sent. This is the number in the
actual queue plus the number in each domain specific queue.

=cut

sub to_send_count {
    my $self = shift;
    $self->poke;

    my $count = scalar @{ $$self{to_send} };

    $count += scalar @{ $self->{domain_stats}{$_}{to_send} }
      for keys %{ $self->{domain_stats} };

    return $count;
}

sub _process_to_send {
    my $self = shift;
	my $domain_limit = $self->{opts}{domain_limit};
    # Go through the domain specific queues and add all requests that we can
    # to the real queue.
    foreach my $domain ( keys %{ $self->{domain_stats} } ) {

        my $domain_stats = $self->{domain_stats}{$domain};
        next unless scalar @{ $domain_stats->{to_send} };

        # warn "TRYING TO ADD REQUEST FOR $domain";
        # warn        sleep 5;

        # Check that this request is good to go.
        next if ($domain_stats->{count} || 0) >= $domain_limit;
        next unless time > ( $domain_stats->{next_send} || 0 );

        # We can add this request.
        $domain_stats->{count}++;
        push @{ $self->{to_send} }, shift @{ $domain_stats->{to_send} };
    }

    # Use the original to send the requests on the queue.
    return $self->SUPER::_process_to_send;
}

# Go through all the values on the select list and check to see if
# they have been fully received yet.

sub _process_in_progress {
    my $self = shift;

  HANDLE:
    foreach my $s ( $self->_io_select->can_read(0) ) {

        my $id = $self->{fileno_to_id}{ $s->fileno };
        die unless $id;
        my $hashref = $$self{in_progress}{$id};
        my $tmp     = $hashref->{tmp} ||= {};

        # warn Dumper $hashref;

        # Check that we have not timed-out.
        if (   time > $hashref->{timeout_at}
            || time > $hashref->{finish_by} )
        {

            # warn sprintf "Timeout: %.3f > %.3f",    #
            #   time, $hashref->{timeout_at};

            $self->_add_error_response_to_return(
                id       => $id,
                code     => 504,
                request  => $hashref->{request},
                previous => $hashref->{previous},
                content  => 'Timed out',
            );

            $self->_io_select->remove($s);
            delete $$self{fileno_to_id}{ $s->fileno };
            next HANDLE;
        }

        # If there is a code then read the body.
        if ( $$tmp{code} ) {
            my $buf;
            my $n = $s->read_entity_body( $buf, 1024 * 16 );    # 16kB
            $$tmp{is_complete} = 1 unless $n;
            $$tmp{content} .= $buf;

            # warn "Received " . length( $buf ) ;

            # Reset the timeout.
            # warn( "reseting the timeout " . time );
            $hashref->{timeout_at} = time + $self->_get_opt( 'timeout', $id );

            # warn $buf;
        }

        # If no code try to read the headers.
        else {
            $s->flush;

            my ( $code, $message, %headers );

            eval {
                ( $code, $message, %headers ) =
                  $s->read_response_headers( laxed => 1, junk_out => [] );
            };

            if ($@) {
                $self->_add_error_response_to_return(
                    'code'     => 504,
                    'content'  => $@,
                    'id'       => $id,
                    'request'  => $hashref->{request},
                    'previous' => $hashref->{previous}
                );
                $self->_io_select->remove($s);
                delete $$self{fileno_to_id}{ $s->fileno };
                next HANDLE;
            }

            if ($code) {

                # warn "Got headers: $code $message " . time;

                $$tmp{code}    = $code;
                $$tmp{message} = $message;
                my @headers_array = map { $_, $headers{$_} } keys %headers;
                $$tmp{headers} = \@headers_array;

                # Reset the timeout.
                $hashref->{timeout_at} =
                  time + $self->_get_opt( 'timeout', $id );
            }
        }

        # If the message is complete then create a request and add it
        # to 'to_return';
        if ( $$tmp{is_complete} ) {
            delete $$self{fileno_to_id}{ $s->fileno };
            $self->_io_select->remove($s);

            # warn Dumper $$hashref{content};

            my $response =
              HTTP::Response->new(
                @$tmp{ 'code', 'message', 'headers', 'content' } );

            $response->request( $hashref->{request} );
            $response->previous( $hashref->{previous} ) if $hashref->{previous};

            # If it was a redirect and there are still redirects left
            # create a new request and unshift it onto the 'to_send'
            # array.
            if (
                $response->is_redirect            # is a redirect
                && $hashref->{redirects_left} > 0 # and we still want to follow
                && $response->code != 304         # not a 'not modified' reponse
              )
            {

                $hashref->{redirects_left}--;

                my $loc = $response->header('Location');
                my $uri = $response->request->uri;

                warn "Problem: " . Dumper( { loc => $loc, uri => $uri } )
                  unless $uri && ref $uri && $loc && !ref $loc;

                my $url = _make_url_absolute( url => $loc, ref => $uri );

                my $request = HTTP::Request->new( 'GET', $url );
                $hashref->{previous} = $response;
                $self->_send_request( [ $request, $id ] );
            }
            else {
                $self->_add_to_return_queue( [ $response, $id ] );
                delete $$self{in_progress}{$id};
            }

            delete $hashref->{tmp};
        }
    }

    return 1;
}


sub _send_request {
    my $self     = shift;
    my $r_and_id = shift;
    my ( $request, $id ) = @$r_and_id;

    my $uri = URI->new( $request->uri );

    my %args = ();

    # We need to use a different request_uri for proxied requests. Decide to use
    # this if a proxy port or host is set.
    #
    #   http://www.w3.org/Protocols/rfc2616/rfc2616-sec5.html#sec5.1.2
    $args{Host}     = $uri->host;
    $args{PeerAddr} = $self->_get_opt( 'proxy_host', $id );
    $args{PeerPort} = $self->_get_opt( 'proxy_port', $id );
    
    my $request_is_to_proxy =
      ( $args{PeerAddr} || $args{PeerPort} )    # if either are set...
      ? 1                                       # ...then we are a proxy request
      : 0;                                      # ...otherwise not

    # If we did not get a setting from the proxy then use the uri values.
    $args{PeerAddr} ||= $uri->host;
    $args{PeerPort} ||= $uri->port;

    my $s = eval { Net::HTTP::NB->new(%args) };

    # We could not create a request - fake up a 503 response with
    # error as content.
    if ( !$s ) {

        $self->_add_error_response_to_return(
            id       => $id,
            code     => 503,
            request  => $request,
            previous => $$self{in_progress}{$id}{previous},
            content  => $@,
        );

        return 1;
    }

    my %headers = %{ $request->{_headers} };

    # Decide what to use as the request_uri
    my $request_uri = $request_is_to_proxy    # is this a proxy request....
      ? $uri->as_string                       # ... if so use full url
      : _strip_host_from_uri($uri);    # ...else strip off scheme, host and port

    croak "Could not write request to $uri '$!'"
      unless $s->write_request( $request->method, $request_uri, %headers,
        $request->content );

    $self->_io_select->add($s);

    $$self{fileno_to_id}{ $s->fileno }   = $id;
    $$self{in_progress}{$id}{request}    = $request;
    $$self{in_progress}{$id}{timeout_at} =
      time + $self->_get_opt( 'timeout', $id );
    $$self{in_progress}{$id}{finish_by} =
      time + $self->_get_opt( 'max_request_time', $id );

    $$self{in_progress}{$id}{redirects_left} =
      $self->_get_opt( 'max_redirects', $id )
      unless exists $$self{in_progress}{$id}{redirects_left};

    return 1;
}

sub _strip_host_from_uri {
    my $uri = shift;

    my $scheme_and_auth = quotemeta( $uri->scheme . '://' . $uri->authority );
    my $url             = $uri->as_string;

    $url =~ s/^$scheme_and_auth//;
    $url = "/$url" unless $url =~ m{^/};

    return $url;
}

sub _make_url_absolute {
    my %args = @_;

    my $in  = $args{url};
    my $ref = $args{ref};

    return $in if $in =~ m{ \A http:// }xms;

    my $ret = $ref->scheme . '://' . $ref->authority;
    return $ret . $in if $in =~ m{ \A / }xms;

    $ret .= $ref->path;
    return $ret . $in if $in =~ m{ \A [\?\#\;] }xms;

    $ret =~ s{ [^/]+ \z }{}xms;
    return $ret . $in;
}

sub _add_to_return_queue {
    my $self       = shift;
    my $req_and_id = shift;

    # decrement the count for this domain so that another request can start.
    # Also set the interval so that we don't scrape too fast.
    my $id          = $req_and_id->[1];
    my $domain      = $self->{id_opts}{$id}{_domain};
    my $domain_stat = $self->{domain_stats}{$domain};
    my $interval    = $self->_get_opt( 'send_interval', $id );

    $domain_stat->{count}--;
    $domain_stat->{next_send} = time + $interval;

    return $self->SUPER::_add_to_return_queue($req_and_id);
}

sub reset {
	my $self = shift;
	
	for my $s ($self->_io_select->handles) {
		my $id = $self->{fileno_to_id}{ $s->fileno };
        die unless $id;
		my $hashref = $$self{in_progress}{$id};
        my $tmp     = $hashref->{tmp} ||= {};
		
		$self->_add_error_response_to_return(
            id       => $id,
            code     => 506,
            request  => $hashref->{request},
            previous => $hashref->{previous},
            content  => 'Hang up',
        );

        $self->_io_select->remove($s);
        delete $$self{fileno_to_id}{ $s->fileno };
	}
}
=head1 SEE ALSO

L<HTTP::Async> - the module that this one is based on.

=head1 AUTHOR

Edmund von der Burg C<< <evdb@ecclestoad.co.uk> >>. 

L<http://www.ecclestoad.co.uk/>

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2006, Edmund von der Burg C<< <evdb@ecclestoad.co.uk> >>.
All rights reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY FOR THE
SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN OTHERWISE
STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES PROVIDE THE
SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED,
INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
FITNESS FOR A PARTICULAR PURPOSE. THE ENTIRE RISK AS TO THE QUALITY AND
PERFORMANCE OF THE SOFTWARE IS WITH YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE,
YOU ASSUME THE COST OF ALL NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING WILL ANY
COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR REDISTRIBUTE THE
SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE LIABLE TO YOU FOR DAMAGES,
INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES ARISING
OUT OF THE USE OR INABILITY TO USE THE SOFTWARE (INCLUDING BUT NOT LIMITED TO
LOSS OF DATA OR DATA BEING RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR
THIRD PARTIES OR A FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER
SOFTWARE), EVEN IF SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE
POSSIBILITY OF SUCH DAMAGES.

=cut

1;
