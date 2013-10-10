use strict;
use warnings;

package HTTP::Spider::Log;

use Time::Piece;
use vars qw(@EXPORT);
use Exporter qw(import);

use constant {
    LOG_DEBUG => 7,
    LOG_INFO  => 6,
    LOG_NOTICE => 5,
    LOG_WARNING => 4,
    LOG_ERR => 3,
    LOG_CRIT => 2,
    LOG_ALERT => 1,
    LOG_EMERG => 0,
};

@EXPORT = qw(
    LOG_DEBUG
    LOG_INFO
    LOG_NOTICE
    LOG_WARNING
    LOG_ERR
    LOG_CRIT
    LOG_ALERT
    LOG_EMERG
    spider_log
);

our $log_pri = LOG_INFO;

my $fh;
my $log_file_name = 'spider.log';

sub log_file_name {
    my (undef, $name) = @_;
    return $log_file_name unless $name;
    if ($log_file_name ne $name) {
        if ($fh) {
            close $fh;
            $fh = undef;
        }
        $log_file_name = $name;
    }
}

sub _get_log_file_handler {
    return $fh if $fh;
    open $fh, '>>'.$log_file_name or die "Open log file $log_file_name failed:$!\n";
    return $fh;
}

sub spider_log {
    my ($msg, $pri) = (@_);
    $pri = LOG_INFO unless defined $pri;
    return $msg if $pri > $log_pri;
    
    my %types = (
        &LOG_DEBUG => 'debug',
        &LOG_INFO  => 'info',
        &LOG_NOTICE => 'notice',
        &LOG_WARNING => 'warning',
        &LOG_ERR => 'error',
        &LOG_ALERT => 'alert',
        &LOG_EMERG => 'emerg',
    );
    
    my $t = localtime;
    my $fh = _get_log_file_handler;
    print $fh '[', $t->ymd, ' ', $t->hms, '][', $types{$pri}, '] ', $msg, "\n";
    
    return $msg;
}
1;
