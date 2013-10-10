#!perl
package HTTP::Spider::TaskMgr;

=head1 NAME

HTTP::Spider::TaskMgr - Manage the task for HTTP::Spider

=head1 SYNOPSIS

    use HTTP::Spider::TaskMgr;

    $taskmgr = HTTP::Spider::TaskMgr->new(
        
    );

=head1 DESCRIPTION

This module is used by HTTP::Spider module for task management, including tasks to add, access, delete, update

=cut
use strict;
use warnings;
use vars qw($VERSION);
use Carp;
use Data::Dump qw(dump);
use HTTP::Spider::Task;

$VERSION = '1.01';

=head2 $chat

Set to true if you'd like more information 

=cut
my $chat = 0;

=over 4

=item HTTP::Spider::TaskMgr->new(%opt)

=cut
sub new {
    my $class = shift;

    my $self = bless {@_}, $class;
    HTTP::Spider::Task->reset_status;
    return $self;
}

sub get_tasks {
    my ($self, $limit) = (shift, shift || 1);

    my @tasks = HTTP::Spider::Task->get_undo_tasks($limit, $self->{task_conds} || {});
    return 0 unless @tasks;
	HTTP::Spider::Task->set_status(\@tasks, STATUS_DOING);
    return \@tasks;
}

sub add_task {
    my ($self, $data) = @_;
    HTTP::Spider::Task->insert($data) 
        or 
    print "Fail to add task:$data->{url}\n"
    unless HTTP::Spider::Task->has_task($data->{url});
}

sub add_tasks {
	my ($self, $datas) = @_;
	for my $data (@$datas) {
		$self->add_task($data);
	}
}

sub reset_tasks {
    my $affected = HTTP::Spider::Task->reset_tasks;
    print "Reset tasks $affected.\n" if $chat;
}
1;
