use strict;
use warnings;

package HTTP::Spider::Worker;

=head1 NAME

HTTP::Spider::Worker - Process response content for HTTP::Spider

=head1 SYNOPSIS

    use HTTP::Spider::Worker;

    $worker = HTTP::Spider::Worker->new(
        chat => 1,
        urls => [
            {
                url => qr/page_\d+\.html/,
                #no_task => 1,
                task_handler => \&task_handler,
                data_handler => \&data_handler,
                #refer => qr/\/?$/,
                property => {
                    pri => 3,
                    interval => { hour => 3 }
                }
            }
        ]
      );

=head1 DESCRIPTION

This module is used by HTTP::Spider module, to process the response content (to save data to database or file ...) and generate new tasks (urls) for the spider.

=cut

use Carp;
use vars qw(@EXPORT_OK $VERSION);
use Exporter qw(import);
use HTTP::Spider::Task;
use HTTP::Spider::Log;
use File::Path qw/make_path/;

$VERSION = '1.01';

@EXPORT_OK = qw(get_abs_url get_abs_urls);


=head2 $chat

Set to above zero if you'd like more infomation.
Defaults to off.

=cut

my $chat = 0;

=over 4

=item $worker = HTTP::Spider::Worker->new(%ops)

  $worker = HTTP::Spider::Worker->new(
    chat => 1,
    urls => [
        {
            url => qr/page_\d+\.html/,
            #no_task => 1,
            task_handler => \&task_handler,
            data_handler => \&data_handler,
            #refer => qr/\/?$/,
            property => {
                pri => 3,
                interval => { hour => 3 }
            }
        }
    ]
  );

=cut
sub new {
	my $class = shift;
	my $self = {@_};
    croak "Need the config for urls." unless $self->{urls};
    $chat = $self->{chat} if exists $self->{chat};
	return bless $self, $class;
}


=item get_abs_url($url, $baseurl)

  get_abs_url('/a.html', 'http://www.example.com/c.html'); 
  #return 'http://www.example.com/a.html'

=cut
sub get_abs_url {
	if (@_ != 2) {
		carp "stage: get_bas_url(\$url, \$baseurl)\n";
		return '';
	}
	my($url, $baseurl) = @_;
	return $url if $url =~ /^http/i;
	return $url unless $baseurl =~ /^http/i;
	if ($url =~ m{^/}) {
		(my $domain = $baseurl) =~ s{(https?://[^/]+)(/.*$)?}{$1}i;
		return $domain . $url;
	}
	$baseurl =~ s{(?<!:/)/[^/]*$}{};
	return $baseurl.'/'.$url;
}

=item get_abs_urls ($urls, $baseurl)

    my $urls = ['a.html', '/d/b.html'];
    get_abs_urls($urls, 'http://www.a.com/b/b.html');
    #return ['http://www.a.com/b/a.html', 'http://www.a.com/d/b.html']

=cut
sub get_abs_urls {
    if (@_ != 2 or not ref $_[0] or ref $_[0] ne 'ARRAY') {
        carp "stage: get_abs_urls(\$urls, \$baseurl)\n";
        return [];
    }
    my ($urls, $baseurl) = @_;
    my $ret = [];
    for my $url (@$urls) {
        my $abs_url = get_abs_url($url, $baseurl);
        push @$ret, $abs_url if $abs_url;
    }
    return $ret;
}

=item $worker->get_url_opt ($url)
=cut
sub get_url_opt {
    my ($self, $url) = @_;
    for my $opt (@{$self->{urls}}) {
        return $opt if $url =~ $opt->{url};
    }
    return undef;
}


sub is_valid_url {
    my ($self, $url) = @_;
    return $self->get_url_opt($url);
}

=item $worker->process ($content_ref, $refer_url)
    
process the response content. 

return new task urls (array ref) or undef

=cut
sub process {
    my ($self, $response, $refer_url, $task) = @_;
    my $url_opt = $self->get_url_opt($refer_url);
	
	if (not $url_opt) {
		warn spider_log("A valid url '$refer_url' to process", LOG_WARNING) if $chat;
		return;
	}
	
    print "process content of $refer_url\n" if $chat;
	if (exists $url_opt->{data_handler}) {
		eval {
			$url_opt->{data_handler}($self, $response, $refer_url, $task);
		};
		if ($@) {
			carp spider_log("A error occured when execute data handlder for $refer_url:$@", LOG_WARNING);
		}
	} elsif ($refer_url =~ m{\.(jpg|gif|png|jpeg)$}i or
			 $response->header('Content-Type') =~ m{^image/(\S+)}i) {
		#Is a image
		my $code_ref = $self->{image_path} || $url_opt->{image_path};
		
		if (! $code_ref) {
			carp spider_log("Defined no image path handler for $refer_url\n", LOG_WARNING);
			return;
		}
		
		my $image_type = lc $1;
		$image_type = 'jpg' if $image_type eq 'jpeg';
		
		my ($origin_basename) = $refer_url =~ m{([^/]+)$}i;
		$origin_basename =~ s{[^\w.-]}{}g;
		
		my $image_path = &$code_ref($origin_basename, $image_type, $refer_url, $task);
		
		my ($dirname, $basename) = $image_path =~ m{^(.+?)/([^/]+)$};
		
		eval {
			if (! -d $dirname) {
				make_path($dirname);
			}
			open my $fp, '>:raw', $image_path;
			print $fp $response->content;
			close $fp;
		};
		
		if ($@) {
			spider_log($@, LOG_ERR);
			return;
		}
		
		my $callback = $self->{after_save_image} || $url_opt->{after_save_image};
		
		$callback and &$callback($basename, $image_path, $task);
		
		return;
	}
	
    return $self->get_tasks($response, $refer_url, $url_opt, $task);
}

#you can define a sub handle in url config item
#or you can debine a property 'no_task' in url config item
#or use default
sub get_tasks {
    my ($self, $response, $refer_url, $url_opt, $task) = @_;
	
	$url_opt ||= {};
	
    #use custom task handler
    if (exists $url_opt->{handler}) {
		my $tasks = [];
		eval {
			$tasks = $url_opt->{handler}($self, 
                $response, 
                $refer_url,
				$task
			);
		};
		if ($@) {
			carp spider_log("A error occured when execute the task handler for $refer_url:$@", LOG_WARNING);
			return;
		}
		$tasks ||= [];
		my $tasks_ok = [];
		for $task (@$tasks) {
			my $opt = $self->get_url_opt($task->{url});
			next unless $opt;
			my $property = $opt->{property} || {};
			push @$tasks_ok, {%{$property}, %{$task}};
		}
		$tasks = $tasks_ok;
        print "Get ", $tasks ? scalar @$tasks : "0",
            " task from $refer_url\n" if $chat;
        return $tasks;
    }
	
	#the url has no new task
    if ($url_opt->{no_task}) {
        print "There is no task in $refer_url\n" if $chat;
        return;
    }
	
    #default process
    my $content = $response->decoded_content;
	#$url_opt{tags}
	my $tags = $self->{allow_img} || $url_opt->{allow_img} ? ['a', 'img'] : ['a'];
	my $reg = '<(?:'.join('|', @$tags).')\b.+?>';
	my @elems = $content =~ m{$reg}gi;
	my $ret = [];
	for my $elem (@elems) {
		my $is_img = $elem =~ /<img/i;
		my $attr = $is_img ? 'src' : 'href';
		my(undef, $url) = $elem =~ m{$attr\s*=\s*(['"]?)([^'"<>\s]+)\1}is;
        next if !$url or $url =~ m{^(#|[a-z\s]:)}i;
		$url =~ s/#.*$//g;
		$url = get_abs_url($url, $refer_url);
		next if not $url or length($url) > 254;
		my $url_opt = $self->get_url_opt($url);
		next unless $url_opt;
		next if exists $url_opt->{refer} and $refer_url !~ $url_opt->{refer};
		my $property = $url_opt->{property} || {};

        my $new_task = {%{$property}, url => $url};

		if ($url_opt->{set_property}) {
			$url_opt->{set_property}($new_task, $refer_url, $task);
		}

        if ($url_opt->{check_handler} && !$url_opt->{check_handler}($new_task)) {
            next;
        }

		push @$ret, $new_task;
	}
    warn "Get ", $ret ? scalar @$ret : "0",
            " task from $refer_url\n" if $chat;
	return $ret;
}
1;
