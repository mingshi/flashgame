#
#===============================================================================
#
#         FILE: Games.pm
#
#  DESCRIPTION: 
#
#        FILES: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Mingshi (deepwarm.com), fivemingshi@gmail.com
# ORGANIZATION: 
#      VERSION: 1.0
#      CREATED: 2013/10/12 17时54分27秒
#     REVISION: ---
#===============================================================================

package FLASH::Games;
use strict;
use warnings;
use Digest::MD5 qw(md5_hex);
use Encode qw(encode_utf8);
use Exporter qw(import);
use vars qw(@EXPORT);

use base qw(FLASH::DBI);

use constant {
    CHINESE    =>  0,
    ENGLISH    =>  1,
    OTHER      =>  2,
};

our @EXPORT = qw(
    CHINESE
    ENGLISH
    OTHER
);

__PACKAGE__->table('games');
__PACKAGE__->columns(ALL => qw/id name cate_id collection_id size language pic swf origin_time desc operate update_time/);
__PACKAGE__->columns(Primary => qw/id/);

sub get_game_id {
    my ($class, $url_id) = @_;

    my $r = $class->retrieve(url_id => $url_id);

    return $r ? $r->id : undef;
}

sub accessor_name_for {
    my ($calss, $column) = @_;
    return 'game_id' if $column eq 'id';
    return $column;
}
1;
