# Description:  数据库备份系统配置参数
# Authors:  
#   zhaoyunbo

package Dbconfig;

use strict;
use warnings;
use Log::Log4perl;


# @Description:  load config data
sub load {
    my $self = shift;
    $self->{dbbackupDir} = "/home/mysql/dbadmin/scripts/dbbackup/";
    $self->{mysqldumpSplitScript} = "/home/mysql/dbadmin/scripts/dbbackup/common/mysqldump_split.sh";
    $self->{hotbakFlushTableLockLimit} = 300;
    $self->{dumpFlushTableLockLimit} = 300;
    $self->{mysqlHomedir} = "/home/mysql";
    $self->{mysqlBaseLogdir} = "/home/mysql/dbadmin/logs";
    $self->{mongodbBaseLogdir} = "/home/mongodb/dbadmin/logs";
    $self->{infinidbBaseLogdir} = "/home/infinidb/dbadmin/logs";
    $self->{mytab} = "/etc/mytab";
    $self->{excuteCmdTimeout} = 60;    # dbbackup.pm $timeout 

    # ftp server 
    $self->{ftpuser} = 'ftpbak';
    $self->{ftppass} = 'ftpbak';
    
    # 备份资料库
    $self->{repoHost} = '10.100.100.60';
    $self->{repoPort} = '3306';
    $self->{repoDb} = 'dbms';
    $self->{repoUser} = 'dbms';
    $self->{repoPassword} = 'dbms'; 
}

# @Description: 构造函数
# @Return: 对象
sub new {
    my ( $class, %args ) = @_;
    
    my $self = {};  # allocate new hash for object
    bless( $self, $class );  # statement object type
    
    # load config
    $self->load();
    
    return $self;
}

# @Description: 根据key获取value
# @Param: 键
# @Return: 值
sub get {
    my ( $self, $key ) = @_;
    return $self->{$key};
}

# @Description: 
# @Param: 
# @Return: 
sub set {
	my ( $self, $key, $value ) = @_;
	$self->{$key} = $value;
}

1;
