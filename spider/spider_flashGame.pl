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

HTTP::Spider::Log->log_file_name('logs/spider.log');

HTTP::Spider::DBI->set_db('Main', 'dbi:mysql:flashgame:127.0.0.1', 'root', '');
HTTP::Spider::DBI->db_Main('SET NAMES UTF8');
HTTP::Spider::Task->table('flash_task');
HTTP::Spider::Task->create_mysql_table;

my $image_base_dir = 'images';

#获取分类





