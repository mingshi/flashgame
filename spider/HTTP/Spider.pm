use strict;
use warnings;

package HTTP::Spider;

use HTTP::Request;
use HTTP::Spider::TaskMgr;
use HTTP::Spider::Task;
use HTTP::Spider::HttpMgr;
use Carp;
use Time::Seconds;

my $debug = 0;
sub new {
	my $class = shift;
	my $self = {@_};
    croak "Worker miss!" unless $self->{worker};
    $self->{task_mgr} = HTTP::Spider::TaskMgr::->new unless exists $self->{task_mgr};
	bless $self, $class;
}

sub run {
	my $self = shift;
	my $cfg = $self->{http} || {};

    #异步请求的队列长度
	my $request_queen_length = $cfg->{queue_length} || 10;

    #数据处理对象
	my $worker = $self->{worker};

    #任务管理对象
	my $task_mgr = $self->{task_mgr};

    #异步HTTP请求管理对象
	my $http_mgr = HTTP::Spider::HttpMgr->new(
		send_interval => $cfg->{send_interval} || 1,
		domain_limit => $cfg->{domain_limit} || 4,
		slots => $request_queen_length,
		timeout => 180 || $cfg->{timeout},
		max_redirects => 3
    );

	my $max_request_count = $request_queen_length * 2;

    #没有任务时的休眠时间
	my $sleep_time = 1;
	my $total_sleep_time = 0;
	
    #当前正在请求的任务表
    my %mtasks = ();

    #初始化
    if ($self->{start_tasks}) {
        for my $task (@{$self->{start_tasks}}) {
            $task_mgr->add_task($task);
        }
    }

    $task_mgr->reset_tasks;

    my $common_header = [
        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language' => 'zh-cn,zh;q=0.5',
        'User-Agent' => 'Mozilla/5.0 (Windows; U; Windows NT 5.1; zh-CN; rv:1.9.1.3) Gecko/20090824 Firefox/3.5.3',
        'Accept-Language' => 'zh-cn,zh;q=0.5',
        'Accept-Encoding' => 'gzip,deflate',
        'Accept-Charset' => 'GB2312,utf-8;q=0.7,*;q=0.7',
    ];
    
    while (1) {
		$http_mgr->poke;
		
		#当前在请求队列中的数目
		my $current_count = $http_mgr->total_count;
		print "Current request queue length:", $current_count, "\n" if $debug;
		
        #添加任务至队列
        if ($current_count < $request_queen_length) {
			print "Start fill task to queue...\n";
            my $wantted = $max_request_count - $current_count;
            my $tasks = $task_mgr->get_tasks($wantted);
            my $add_count = 0;
            if ($tasks) {
                $add_count = scalar @$tasks;
                #add task to the queen
                for my $task (@$tasks) {
                    my $opt = $worker->get_url_opt($task->url);
                    if (!$opt or $task->url !~ m/^http/i) {
                        print "Get a invalid task:", $task->url, "\n";
                        $task->status(HTTP::Spider::Task::STATUS_IGNOR);
                        $task->update;
                        next;
                    }

                    my $request = HTTP::Request->new(
                        GET => $task->url,
                        [ @{$common_header}, @{$opt->{http_header} || []}]
                    );
                    
                    $mtasks{$request->uri} = [$task, $opt];
                    
                    print "Add task to queue:", $task->url, "\n";
                    $http_mgr->add($request);
                }
            }

            #没有任务可添加，则休息一下
			if ($add_count == 0) {
                print "Completed!" and return if $current_count == 0;
                print "No task to add, queue length :",$current_count,"\n";
                print "Sleep $sleep_time\n";
				sleep $sleep_time;
				$total_sleep_time += $sleep_time;
				if ($sleep_time < 10) {
					$sleep_time = $sleep_time + 0.1;	
				} else {
                    print "Reset tasks...\n";
                    $task_mgr->reset_tasks;
                }
			} else {
				$sleep_time = 1;
				$total_sleep_time = 0;
			}
			print "End fill task to queue...$add_count\n";
		}

		#check incoming data
		$http_mgr->poke;
        
        #数据已接收
		while ($http_mgr->not_empty) {	
			if (my $response = $http_mgr->next_response) {
                $sleep_time = 1;
				$total_sleep_time = 0;
                my ($origin_response) = $response->previous;
				my $url = $origin_response ? $origin_response->request->uri : $response->request->uri;
                my $task = $mtasks{$url};
                
                if (!$task) {
                    carp "Task error:$url\n";
					$http_mgr->poke;
                    next;
                }
                delete $mtasks{$url};
                
                my $opt = $task->[1];
                my $time = time;
                $task = $task->[0];
                $task->last_time($time);
                $task->next_time($time + ($opt->{interval} || ONE_YEAR * 100));

				if ($response->is_success) {
                    print "Get response succ:", $url, "\n";

                    #process data and get new tasks
					my $new_tasks = $worker->process($response, $url, $task);
                    $task_mgr->add_tasks($new_tasks) if $new_tasks;
                    $task->status(STATUS_SUCC);
				} else {
                    print "Get response fail:", $url, "\n";
					print $response->status_line, "\n";
                    #print $response->content,"\n";
                    #set the current task status
                    $task->status(STATUS_FAIL);
					if ($opt->{on_fail}) {
						&{$opt->{on_fail}}($url, $task, $response);
					}
				}

                $task->last_code($response->code);

                #更新任务
                $task->update;
			} else {
				if ($total_sleep_time > 300) {
					print "To send count:", $http_mgr->to_send_count,
					"\n", "In progress count:", $http_mgr->in_progress_count,
					"\n", "To return count:", $http_mgr->to_return_count, "\n";
					print "Reset Https\n";
					$http_mgr->reset;
				}
				last;	
			}
			$http_mgr->poke;
		}
	}
}
1;
