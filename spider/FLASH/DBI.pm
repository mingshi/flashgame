#
#===============================================================================
#
#         FILE: DBI.pm
#
#  DESCRIPTION: 
#
#        FILES: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Mingshi (deepwarm.com), fivemingshi@gmail.com
# ORGANIZATION: 
#      VERSION: 1.0
#      CREATED: 2013/10/10 11时10分31秒
#     REVISION: ---
#===============================================================================

use strict;
use warnings;
 
package FLASH::DBI;
use base qw(Class::DBI);
use Class::DBI::AbstractSearch;

__PACKAGE__->set_db('Main', 'dbi:mysql:flashgame:127.0.0.1', 'root', '');
__PACKAGE__->db_Main->do('SET NAMES UTF8');
1;
