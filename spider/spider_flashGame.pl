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
use Time::Seconds;
use HTTP::Spider;
use HTTP::Spider::Task;
use HTTP::Spider::Worker qw/get_abs_url/;
use HTTP::Spider::Log;
use Digest::MD5 qw(md5_hex);
use Carp;
use FLASH::Category;
use FLASH::Games;
use Encode qw(encode_utf8);



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
    
    # 从游戏详情页面获得游戏分类
    my $cate_name = $dom->at('div.crumbs_nav a:last-of-type')->text;
    my $cate_url = $dom->at('div.crumbs_nav a:last-of-type')->attr('href');
    my ($cate_mini_url) = $cate_url =~ m{/(\d+)/};

    unless ($cate_name) {
        carp spider_log("Not match category name in page:$url", LOG_WARNING);
        return;
    }

    my $tasks = eval {
        my $cate_id = FLASH::Category->get_cate_id(md5_hex(encode_utf8($cate_name)));

        #创建分类
        unless ($cate_id) {
            my $cate = FLASH::Category->insert({
                category_name   =>  $cate_mini_url,
                display_name    =>  $cate_name,
                name_key        =>  md5_hex(encode_utf8($cate_name)),
            });
            
            $cate_id = $cate->id;
        }
        
        my $game_collection;
        # 从游戏详情页面获取所属合集
        if ($dom->find('div.intro_main ul:nth-of-type(2) li:nth-of-type(3)')) {
            for my $a ($dom->find('div.intro_main ul:nth-of-type(2) li:nth-of-type(3) a')->each) {
                my $collection_md5 = md5_hex($a->attr('href'));
                my $collection_id = FLASH::Collection->get_id($cate_id, $collection_md5);
                my $collection_name = $a->text;

                # 创建合集
                unless ($collection_id) {
                    my $collection = FLASH::Collection->insert({
                        'name'      =>  $collection_name,
                        'url'       =>  $collection_md5,
                        'origin_id' =>  md5_hex($cate_name),
                        'new_id'    =>  $cate_id,
                    });

                    $collection_id = $collection->id;
                }
                
                $game_collection .= $collection_id . ",";
            }
        }
        # 得到所属合集，多个合集用,隔开
        $game_collection =~ s/^,|,$//g;
        
        # 获得url中的id
        my ($url_id) = $url =~ /(\d+)\.html/;
        unless ($url_id) {
            carp spider_log("Not match Url ID in page:$url", LOG_WARNING); 
            return;
        }

        # 获取文件大小、语言、图片地址、时间、简介、操作等信息
        my $tmpSize = $dom->at('div.intro_main ul:nth-of-type(1) li:nth-of-type(2)')->all_text;
        my ($size) = $tmpSize  =~ /(\d+)/;
        
        my $tmpLan = $dom->at('div.intro_main ul:nth-of-type(1) li:nth-of-type(3)')->all_text;
        my ($language) = $tmpLan =~ s/<strong>语言：<\/strong>//g;
        $language = s/^\s+|\s+$//g;
        if ($language eq '中文') {
            $language = CHINESE;
        } elsif ($language eq '英文') {
            $language = ENGLISH;
        } else {
            $language = OTHER;
        }

        my $tasks = $worker->get_tasks($response, $url, {}, $task) || [];

        my $thumb = $dom->at('div.intro_slide div.img_app a img')->attr('src');
        push @$tasks, {
            url =>  $thumb,
            custom1 =>  $url_id,
        };

        my $tmpTime = $dom->at('div.intro_main ul:nth-of-type(2) li:first-of-type')->all_text;
        my ($time) = $tmpTime =~ /([\d{4}\-\d{2}\-\d{2}]+)/;

        my $desc = $dom->at('div.intro_main dl:first-of-type dd:nth-of-type(2)')->text;

        my $operate = $dom->at('div.intro_main dl:last-of-type dd p')->all_text;
        
        # 获得游戏名称
        my $game_name = $dom->at('div.intro_main div.tit h1')->text;
        # 创建游戏
        my $game_id = FLASH::Games->get_game_id($url_id);
        unless ($game_id) {
            my $game = FLASH::Games->insert({
                url_id          =>  $url_id,
                name            =>  $game_name,
                cate_id         =>  $cate_id,
                collection_id   =>  $game_collection,
                size            =>  $size,
                language        =>  $language,
                origin_time     =>  $time,
                desc            =>  $desc,
                operate         =>  $operate,
            });
            $game_id = $game->id;
        }

        # 获得操作页面
        my $start_url = $dom->at('div.intro_main dl.dl_start dd.startWrap a:first-of-type')->attr('href');
        push @$tasks, {
            url =>  $start_url,
            custom1 =>  $game_id,
        };

        return $tasks;
    };

    if ($@) {
        warn spider_log("Process category page error:$@");
        return 0;
    }

    return $tasks;
}

my $urls = [
    {
        #Every Game Index Page
        url =>  qr{^http://www\.abab\.com/play/\d+\.html}oi,
        interval => ONE_DAY * 3,
        property => {
            weight => 99,
        },
        handler => \&generate_category_in_page,
    },
    {
        url =>  qr{^http://www\.abab\.com/flash/\d+\.html}oi,
        interval => ONE_DAY * 3,
        property => {
            weight  =>  98,
        },
        handler => \&generate_swf_in_page,
    },
    {
        url => qr{\.(jpg|png|gif|jpeg)$}oi,
        interval => ONE_YEAR * 10,
        refer => qr{^$}oi,
        property => {
            weight  =>  97,
        },
        image_path => sub {
            my ($name, undef, undef, $task) = @_;
            return $image_base_dir . '/' . $task->custom1 . '/' . $name;
        },
        after_save_image => sub {
            my ($name, $realpath, $task) = @_;
            my $path = $task->custom1 . '/' . $name;

            my $game = FLASH::Games->retrieve($task->custom1);

            unless ($game) {
            }
        }
    }
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
            url =>  'http://www.abab.com/',
            weight => 10,
        }
    ]
);

$spider->run;

