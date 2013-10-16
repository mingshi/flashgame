#
#===============================================================================
#
#         FILE: Category.pm
#
#  DESCRIPTION: 
#
#        FILES: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Mingshi (deepwarm.com), fivemingshi@gmail.com
# ORGANIZATION: 
#      VERSION: 1.0
#      CREATED: 2013/10/11 18时07分07秒
#     REVISION: ---
#===============================================================================

package FLASH::Category;

use strict;
use warnings;

use base qw(FLASH::DBI);

__PACKAGE__->table('flash_category');

__PACKAGE__->columns(ALL => qw/id category_name display_name last_update_time show_status name_key/);
__PACKAGE__->columns(Primary => qw/id/);

sub accessor_name_for {
    my ($calss, $column) = @_;
    return 'category_id' if $column eq 'id';
    return $column;
}

sub get_cate_id {
    my ($class, $name_key) = @_;

    my $r = $class->retrieve(name_key  =>  $name_key);

    return $r ? $r->id : undef;
}
__PACKAGE__->has_a(
    last_update_time => 'Time::Piece',
    deflate => 'epoch',
);
1;
