package HTTP::Spider::Task;

use strict;
use warnings;

use base qw(HTTP::Spider::DBI);
use Encode qw(encode_utf8);
use Digest::MD5 qw(md5_hex);
use Time::Piece;
use Exporter qw(import);
use vars qw(@EXPORT);

use constant {
    STATUS_UNDO  => 0,
    STATUS_DOING => 1,
    STATUS_SUCC  => 2,
    STATUS_SUCC2 => 3,
    STATUS_IGNOR => -1,
    STATUS_FAIL  => -2,
};

@EXPORT = qw(
    STATUS_UNDO
    STATUS_DOING
    STATUS_SUCC
    STATUS_SUCC2
    STATUS_IGNOR
    STATUS_FAIL
);

our $VERSION = '1.01';

__PACKAGE__->table('task');

__PACKAGE__->columns(ALL => qw/id url weight instant_weight status create_at last_time next_time last_code custom1 custom2 custom3/);
__PACKAGE__->columns(Primary => qw/id/);

__PACKAGE__->has_a(
    last_time => 'Time::Piece',
    deflate => 'epoch',
);

__PACKAGE__->has_a(
    next_time => 'Time::Piece',
    deflate => 'epoch',
);

{
    sub before_insert {
        my $task = shift;
        $task->tid(__PACKAGE__->gen_id($task->url));
        my $time = time;
        $task->create_at($time);
        $task->last_time($time);
        $task->next_time($time);
    }
    
    __PACKAGE__->add_trigger(before_create => \&before_insert);
}

sub get_undo_tasks {
    my ($class, $limit, $conds) = @_;
    
    $conds ||= {};
    my $where = {status => STATUS_UNDO, weight => { '>' => 0 }, %{$conds}}; 
    my $attrs = { 
        order_by => ['instant_weight DESC', 'weight DESC', 'create_at ASC'],
        limit_dialect => 'LimitOffset',
        limit => $limit
    };
    return $class->search_where($where, $attrs);
}

sub accessor_name_for {
    my ($class, $column) = @_;
    return 'tid' if $column eq 'id';
    return $column;
}

sub has_task {
    my $task = shift->get_task(shift);
    return !! $task;
}

sub get_task {
    my ($class, $url) = @_;
    $class = ref $class || $class;
    my $id = $class->gen_id($url);
    my $task = $class->retrieve($id);
    return $task;
}

sub reset_status {
    my $class = shift;
    my $origin_status = shift || STATUS_DOING;
    my $table = $class->table;
    my $to_status = STATUS_UNDO;
    $class->db_Main->do(qq{
       UPDATE  $table
       SET status=${to_status}
       WHERE status=${origin_status}
    });
}

sub set_status {
    my ($class, $tasks, $status) = @_;
    if (ref $tasks ne 'ARRAY') {
        $tasks = [$tasks];
    }
    my @ids = map { "'".$_->id."'" } @{$tasks};
    my $ids = join ',', @ids;
    my $sets = "status=$status";
    if ($status != STATUS_UNDO and $status != STATUS_DOING) {
        $sets .= ",instant_weight=0";
    }
    return $class->do(qq{
        UPDATE __TABLE__ 
        SET $sets 
        WHERE id in ($ids)
    });
}

sub reset_tasks {
    my $time = time;
    return shift->do("
        UPDATE __TABLE__ SET `status`=".STATUS_UNDO."
        WHERE `status` != ".STATUS_UNDO."
        AND `status` != ".STATUS_DOING."
        AND next_time < $time
    ");
}

sub do {
    my ($class, $sql) = @_;
    my $table = $class->table;
    $sql =~ s/__TABLE__/$table/;
    return $class->db_Main->do($sql);
}


sub gen_id {
    my (undef, $url) = @_;
    $url =~ s{(/|#.+)$}{};
    return md5_hex(encode_utf8(lc $url));
}

sub stringify_self {
    my $self = shift;
    return "Task:".$self->url;
}

sub create_mysql_table {
    my $class = shift;
    my $table = $class->table;
    $class->db_Main->do(qq{
        CREATE TABLE IF NOT EXISTS `$table` (
            `id` char(32) NOT NULL comment 'md5_hex(encode_utf8(lc url))',
            `url` varchar(255) NOT NULL,
            `weight` int(11) NOT NULL default '0',
            `instant_weight` int(11) NOT NULL default '0',
            `status` int(11) NOT NULL default '0',
            `create_at` int(11) NOT NULL default '0',
            `last_time` int(11) NOT NULL default '0',
            `next_time` int(11) NOT NULL default '0',
            `last_code` int(11) NOT NULL default '0',
            `custom1` varchar(255) default NULL,
            `custom2` varchar(255) default NULL,
            `custom3` varchar(255) default NULL,
            PRIMARY KEY  (`id`),
            KEY `status_index` (`status`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8 
    });
}

sub create_sqlite_table {
    my $class = shift;
    my $table = $class->table;
    $class->db_Main->do(qq{
        CREATE TABLE IF NOT EXISTS `$table` (
            `id` TEXT PRIMARY KEY,
            `url` TEXT,
            `weight` INT DEFAULT 0,
            `instant_weight` INT DEFAULT 0,
            `status` INT DEFAULT 0,
            `create_at` INT DEFAULT 0,
            `last_time` INT DEFAULT 0,
            `next_time` INT DEFAULT 0,
            `last_code` INT DEFAULT 0,
            `custom1` TEXT,
            `custom2` TEXT,
            `custom3` TEXT
        );
    });
    
    $class->db_Main->do(qq{
        CREATE INDEX IF NOT EXISTS status_idx ON $table(status);
    });
}

1;
