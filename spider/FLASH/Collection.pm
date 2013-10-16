#
#===============================================================================
#
#         FILE: Collection.pm
#
#  DESCRIPTION: 
#
#        FILES: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Mingshi (deepwarm.com), fivemingshi@gmail.com
# ORGANIZATION: 
#      VERSION: 1.0
#      CREATED: 2013/10/12 11时53分58秒
#     REVISION: ---
#===============================================================================

package FLASH::Collection;
use strict;
use warnings;
 
use base qw(FLASH::DBI);

__PACKAGE__->table('collection');

__PACKAGE__->columns(ALL => qw/id name url origin_id new_id update_time/);
__PACKAGE__->columns(Primary => qw/id/);

sub get_id {
    my ($class, $cate_id, $url) = @_;

    my $r = $class->retrieve(new_id => $cate_id, url => $url);

    return $r ? $r->id : undef;
}

1;
