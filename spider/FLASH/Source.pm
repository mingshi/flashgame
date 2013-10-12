#
#===============================================================================
#
#         FILE: Source.pm
#
#  DESCRIPTION: 
#
#        FILES: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Mingshi (deepwarm.com), fivemingshi@gmail.com
# ORGANIZATION: 
#      VERSION: 1.0
#      CREATED: 2013/10/11 14时39分12秒
#     REVISION: ---
#===============================================================================
package FLASH::Source;
use strict;
use warnings;

use base qw(FLASH::DBI);

__PACKAGE__->table('flash_source');

__PACKAGE__->columns(ALL => qw/origin_id new_id update_time/);
__PACKAGE__->columns(Primary => qw/origin_id/);

sub get_new_id {
    my ($class, $origin_id) = @_;

    my $r = $class->retrieve($origin_id);

    return $r ? $r->new_id : undef;
}
1;
 

