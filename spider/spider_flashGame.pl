#!/usr/bin/env perl 
#===============================================================================
#
#         FILE: spider_flashGame.pl
#
#        USAGE: ./spider_flashGame.pl  
#
#  DESCRIPTION: 
#
#      OPTIONS: ---
# REQUIREMENTS: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Mingshi (deepwarm.com), fivemingshi@gmail.com
# ORGANIZATION: 
#      VERSION: 1.0
#      CREATED: 2013/10/10 18时10分52秒
#     REVISION: ---
#===============================================================================

use Modern::Perl;
use utf8;
use HTTP::Spider;
use HTTP::Spider::Task;
use HTTP::Spider::Worker qw/get_abs_url/;
use HTTP::Spider::Log;
use Mojo::Util qw/md5_sum/;
use Carp;
use FLASH::Source;
use FLASH::Category;


HTTP::Spider::Log->log_file_name('logs/spider.log');

HTTP::Spider::DBI->set_db('Main', 'dbi:mysql:flashgame:127.0.0.1', 'root', '');
HTTP::Spider::DBI->db_Main('SET NAMES UTF8');
HTTP::Spider::Task->table('flash_task');
HTTP::Spider::Task->create_mysql_table;

my $image_base_dir = 'images';

#获取分类
sub generate_category_in_page {
    my ($worker, $response, $url, $task) = @_;

    my $dom = Mojo::DOM->new($response->decoded_content(charset => 'gbk'));

    my $cate_name = $dom->at('div.crumbs_nav a:last-of-type')->text;
    my $cate_url = $dom->at('div.crumbs_nav a:last-of-type')->attr('href');
    my ($cate_mini_url) = $cate_url =~ m{/(\d+)/};

    unless ($cate_name) {
        carp spider_log("Not match category name in page:$url", LOG_WARNING);
        return;
    }

    my $tasks = eval {
        my $cate_id = FLASH::Source->get_new_id(md5_sum($cate_name));

        #创建分类
        unless ($cate_id) {
            my $cate = FLASH::Category->insert({
                category_name => $cate_mini_url,
                display_name => $cate_name,
            });
            
            $cate_id = $cate->id;

            FLASH::Source->insert({
                origin_id   =>  md5_sum($cate_name),
                new_id      =>  $cate_id,
            });
        }

        my $tasks = $worker->get_tasks($response, $url, {}, $task) || [];
        print $task;

    };
}

my $urls = [
    {
        #home page
        url =>  qr{^http://www\.abab\.com/$}oi,
        interval => ONE_DAY,
        property => {
            weight => 10,
        }
    },
    {
        #Every Game Index Page
        url =>  qr{^http://www.abab.com/play/\d+\.html}oi,
        interval => ONE_DAY * 10,
        property => {
            weight => 5,
        },
        handler => \&generate_category_in_page,
    },
];

my $worker = HTTP::Spider::Worker->new(
    chat    =>  1,
    urls    =>  $urls,
);

my $spider = HTTP::Spider->new(
    worker  =>  $worker,
    http    =>  {
        domain_limit => 5,
        queue_length => 30,
    },
    start_tasks => [
        {
            url =>  'http://www.abab.com',
            weight => 10,
        }
    ]
);

$spider->run;

