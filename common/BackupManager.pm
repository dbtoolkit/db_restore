# Description:  公共函数
# Authors:  
#   zhaoyunbo

package BackupManager;

use strict;
use warnings;

use DBI;
use POSIX qw(:signal_h);
use DateTime;
use Digest::MD5;
use File::Path qw(make_path remove_tree);
use Net::FTP;
use Log::Log4perl;


# 构造函数
sub new {
    my ( $class, %args ) = @_;
    
    my $self = {};  # create a hash ref
    
    my $log = Log::Log4perl->get_logger(""); 

    # 接收$dbconfigObj对象
    for (qw(dbconfigObj)) {
        if ( $args{$_} ) {
            $self->{$_} = $args{$_};
        } else {
            $log->error("got no $_");
            die "got no $_!";
        }
    }
    
    bless ( $self, $class );
    
    return $self;
}

# @Description:  获取当前时间
# @Param: 
# @Return:  $currTime
sub getCurrentTime {
    my $self = @_;
    
    my $currTime = `date "+%Y-%m-%d %H:%M:%S"`;
    chomp($currTime);
    
    return $currTime;
}

# @Description:  获取当前日期
# @Param: 
# @Return:  $currDate
sub getCurrentDate {
    my $self = @_;

    my $log = Log::Log4perl->get_logger("");
    
    my ( $sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst ) = localtime();
    $year += 1900;
    $mon = ($mon<9)?"0".($mon+1):$mon;
    $mday = ($mday<10)?"0$mday":$mday;
    
    my $currDate = "$year$mon$mday";
    chomp($currDate);
    
    $log->info("get current date is $currDate");
    
    return $currDate;
}

# @Description:  获取当前datetime
# @Param: 
# @Return:  $currDatetime
sub getCurrentDatetime {
    my $self = @_;

    my $log = Log::Log4perl->get_logger("");
    
    my ( $sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst ) = localtime();
    $year += 1900;
    $mon = ($mon<9)?"0".($mon+1):$mon;
    $mday = ($mday<10)?"0$mday":$mday;
    
    my $currDatetime = "$year$mon$mday$hour$min$sec";
    chomp($currDatetime);
    
    $log->info("get current datetime is $currDatetime");

    return $currDatetime;
}

# @Description:  初始化log4perl
sub initLog4Perl {
    my ( $self,$logFile ) = @_;

    my $logConf = q(
        log4perl.rootLogger                = DEBUG, logfile
        log4perl.appender.logfile          = Log::Log4perl::Appender::File
        log4perl.appender.logfile.mode     = append
        log4perl.appender.logfile.layout   = Log::Log4perl::Layout::PatternLayout
        log4perl.appender.logfile.layout.ConversionPattern = [%d{yyyy-MM-dd HH:mm:ss}] [%p] [%F{1}:%L %M]  %m%n
        #log4perl.appender.logfile.layout.ConversionPattern = %d{yyyy-MM-dd HH:mm:ss}  [%p] [%M] %m%n
    );
    $logConf .= "log4perl.appender.logfile.filename = $logFile";
    
    Log::Log4perl->init( \$logConf );
    my $log = Log::Log4perl->get_logger(""); 
    if ( !$log ){
        Log::Log4perl->init( \$logConf );
    }
    
    return $log;
}

# @Description:  连接mysql
# @Param:  $host, $port, $user, $pass, $dbname
# @Return:  $dbh
sub mysqlConnect {
    my ( $self, $host, $port, $dbname, $user, $pass ) = @_;

    my $log = Log::Log4perl->get_logger("");
    
    my $dsn = "DBI:mysql:database=$dbname;host=$host;port=$port";
  
    $log->debug("$dsn, user:$user, pass:****");
    
    # 连接mysql     
    my $dbh = DBI->connect( $dsn, $user, $pass, { PrintError => 0, RaiseError => 0, 
                           AutoCommit => 1} );
    
    return $dbh;
}

# @Description:  获取一行, 使用fetchrow_hashref函数，返回哈希引用
# @Param:  $dbh, $sql
# @Return:  $row or undef
sub mysqlQuery {
    my ( $self, $dbh, $sql ) = @_;

    my $log = Log::Log4perl->get_logger("");
        
    $log->debug("$sql");
    
    my $sth = $dbh->prepare($sql);
    my $res = $sth->execute();
    
    # 若结果为空, 则返回undef
    if ( !$res ){
        return undef;
    }
    
    my $row = $sth->fetchrow_hashref();
    $sth->finish();
    
    return $row;
}

# @Description:  获取一行, 使用fetchrow_array函数，返回数组
# @Param:  $dbh, $sql
# @Return:  @row or undef
sub mysqlQueryOneArray {
    my ( $self, $dbh, $sql ) = @_;

    my $log = Log::Log4perl->get_logger("");
        
    $log->debug("$sql");
    
    my $sth = $dbh->prepare($sql);
    my $res = $sth->execute();
    
    # 若结果为空, 则返回undef
    if ( !$res ){
        return undef;
    }
    
    my @row = $sth->fetchrow_array();
    $sth->finish();
    
    return @row;
}

# @Description:  获取所有结果集, 使用fetchall_arrayref函数, 返回数组哈希引用
# @Param:  $dbh, $sql
# @Return:  $arrRef or undef
sub mysqlQueryMulti {
    my ( $self, $dbh, $sql ) = @_;

    my $log = Log::Log4perl->get_logger("");

    $log->debug("$sql");
        
    my $sth = $dbh->prepare($sql);
    my $res = $sth->execute();
    
    # 若结果为空, 则返回undef
    if (!$res){
        return undef;
    }

    my $arrRef = $sth->fetchall_arrayref();
    $sth->finish();
 
    return $arrRef;
}

# @Description:  执行更新操作
# @Param:  $dbh, $sql
# @Return:  成功:1  失败:0
sub mysqlExecute {
    my ( $self, $dbh, $sql ) = @_;

    my $log = Log::Log4perl->get_logger("");
    
    my $exitCode = 0;
    
    $log->debug("$sql");
    
    my $timeout = 60;

    my $timeoutMsg = "EXECUTE_SQL_TIMEOUT"; 
    my $sigset = POSIX::SigSet->new( SIGALRM );  # signals to mask in the handler
    my $action = POSIX::SigAction->new( sub { die $timeoutMsg; },$sigset,);
    my $oldaction = POSIX::SigAction->new();
    sigaction( SIGALRM, $action, $oldaction ); 
    
    eval {
        alarm $timeout;
        $dbh->do($sql);
        alarm 0;
    };
    alarm 0; # race condition protection
    sigaction( SIGALRM, $oldaction );  # restore original signal handler
    
    if ($@){
        $log->error("execute sql failed, error msg: $@");
    }else{
        $log->info("execute sql success");
        $exitCode = 1;
    }
    
    return $exitCode;
}

# @Description:  执行查询, 不返回结果集
# @Param: dbh, $sql
# @Return: 无
sub mysqlExecuteOnly {
    my ( $self, $dbh, $sql ) = @_;

    my $log = Log::Log4perl->get_logger("");
    
    $log->debug("$sql");
    
    my $sth = $dbh->prepare($sql);
    $sth->execute();
    $sth->finish();
    
    return;
}

# @Description:  关闭mysql连接
# @Param:  $dbh
# @Return:  无
sub mysqlDisconnect {
    my ( $self,$dbh ) = @_;
    
    my $log = Log::Log4perl->get_logger("");
      
    if ( defined($dbh) ) {
        eval {
            $log->info("mysql disconnect");
            $dbh->disconnect();         
        };
        if($@){
            undef $@;
        }
    }
}

# @Description:  获取my.cnf配置文件
# @Param:  
# @Return:  $port,$mytab
sub getMycnf {   
    my ( $self,$port,$mytab ) = @_;

    my $log = Log::Log4perl->get_logger("");

    my $myCnf;
    open MYTAB,$mytab or $log->error("open file $mytab failed");
    while ( my $line=<MYTAB> ){
        chomp($line);
        $line =~ s/^\s+//g;
        next if $line =~ m/^#/;
        if ( $line =~ m/$port/ ){
            $myCnf = (split(/\s+/,$line))[1];
        }
    }
    close(MYTAB);
    
    return $myCnf;
}

# @Description:  获取备份资料库数据库连接参数
# @Param:  
# @Return:  $repoHost,$repoPort,$repoUser,$repoPass,$repoDb
sub getRepoInfo {
    my ( $self ) = @_;

    my $log = Log::Log4perl->get_logger("");
    
    # 数据库ip
    my $repoHost = $self->{dbconfigObj}->get('repoHost');
    
    # 数据库端口
    my $repoPort = $self->{dbconfigObj}->get('repoPort');
    
    # 数据库用户名
    my $repoUser = $self->{dbconfigObj}->get('repoUser');
    
    # 数据库密码
    my $repoPass = $self->{dbconfigObj}->get('repoPassword');
    
    # 数据库名称
    my $repoDb = $self->{dbconfigObj}->get('repoDb');
    
    $log->info("get repo info: repoHost:$repoHost repoPort:$repoPort repoUser:$repoUser repoPass:*** repoDb:$repoDb");

    return ($repoHost,$repoPort,$repoUser,$repoPass,$repoDb);
}

# @Description:  获取mysql默认连接配置
# @Param:  
# @Return:  $defaultConfig or undef
sub getMysqlDefaultConfig {
    my ( $self ) = @_;

    my $log = Log::Log4perl->get_logger("");
    
    # 获取备份资料库数据库连接信息
    my ( $repoHost,$repoPort,$repoUser,$repoPass,$repoDb ) = $self->getRepoInfo();
    
    # 连接备份资料库
    my $dbh = $self->mysqlConnect($repoHost,$repoPort,$repoDb,$repoUser,$repoPass);
    if ( !$dbh ){
        $log->error("connect to $repoHost:$repoPort failed");
        
        # 连接mysql异常，返回undef
        return undef;
    }
    $log->info("connect to $repoHost:$repoPort success"); 

    # SQL语句
    my $sql = "select ip,port,db_name,db_username,db_password from backup_global_config where db_name='mysql' limit 1";

    $log->info($sql);

    # 执行查询操作
    my $defaultConfig = $self->mysqlQuery($dbh,$sql);
    if ( !$defaultConfig ){
        $log->error("get mysql default config failed");
        
        # 查询结果为空，返回undef
        return undef;
    }
    
    $log->info("get mysql default config success");
    
    return $defaultConfig;
}

# @Description:  获取mongodb默认连接配置
# @Param:  
# @Return:  $defaultConfig or undef
sub getMongoDefaultConfig {
    my ( $self ) = @_;

    my $log = Log::Log4perl->get_logger("");
    
    # 获取备份资料库数据库连接信息
    my ( $repoHost,$repoPort,$repoUser,$repoPass,$repoDb ) = $self->getRepoInfo();
    
    # 连接备份资料库
    my $dbh = $self->mysqlConnect($repoHost,$repoPort,$repoDb,$repoUser,$repoPass);
    if ( !$dbh ){
        $log->error("connect to $repoHost:$repoPort failed");
        
        # 连接mysql异常，返回undef
        return undef;
    }
    $log->info("connect to $repoHost:$repoPort success"); 

    # SQL语句
    my $sql = "select ip,port,db_name,db_username,db_password from backup_global_config where db_name='mongodb' limit 1";

    $log->info($sql);

    # 执行查询操作
    my $defaultConfig = $self->mysqlQuery($dbh,$sql);
    if ( !$defaultConfig ){
        $log->error("get mongodb default config failed");
        
        # 查询结果为空，返回undef
        return undef;
    }
    
    $log->info("get mongodb default config success");
    
    return $defaultConfig;
}

# @Description:  根据变量名称获取mysql变量值
# @Param:  $dbh,$sql
# @Return:  $value
sub getMysqlVariableValue {
    my ( $self, $dbh, $sql ) = @_;

    my $log = Log::Log4perl->get_logger("");
        
    my $sth = $dbh->prepare($sql);
    $sth->execute();
    my @row = $sth->fetchrow_array();
    my $value = $row[0];
    $sth->finish();
    
    if ( defined($value) ){
        $log->info("[$sql] get value: $value");
    }
    
    return $value;
}

# @Description:  获取加密秘钥串
# @Param:
# @Return: $encryptKey or undef
sub getEncryptKey {
    my ($self,$host,$port,$dbType,$bakType,$startTime) = @_;

    my $log = Log::Log4perl->get_logger("");
   
    # 获取备份资料库数据库连接参数
    my ($repoHost,$repoPort,$repoUser,$repoPass,$repoDb) = $self->getRepoInfo();
    
    # 连接备份资料库
    my $dbh = $self->mysqlConnect($repoHost,$repoPort,$repoDb,$repoUser,$repoPass);
    if ( !$dbh ){
        $log->error("connect to $repoHost:$repoPort failed");
        
        # 连接mysql异常，返回undef
        return undef;
    }
    $log->info("connect to $repoHost:$repoPort success");

    # 存储过程语句
    my $sql = "call dbms.proc_genkey('$host','$port','$dbType','$bakType','$startTime');";

    $log->info($sql);
        
    my $encryptKey = $self->mysqlQuery($dbh,$sql);
    if ( !$encryptKey ){
        $log->error("get $host:$port encrypt key failed");
        
        # 查询结果为空，返回undef
        return undef;
    }
    
    $log->info("get $host:$port encrypt key success");
    
    return $encryptKey;
}

# @Description:  上传加密秘钥串
# @Param:
# @Return:
sub uploadEncryptKey {        
    my ( $self,$host,$port,$dbType,$bakType,$encKey,$startTime ) = @_;

    my $log = Log::Log4perl->get_logger("");
        
    # 变量转换
    $dbType = lc($dbType);
    $bakType = lc($bakType);    

    # 获取备份资料库数据库连接参数
    my ( $repoHost,$repoPort,$repoUser,$repoPass,$repoDb ) = $self->getRepoInfo();
    
    # 连接备份资料库
    my $dbh = $self->mysqlConnect($repoHost,$repoPort,$repoDb,$repoUser,$repoPass);
    if ( !$dbh ){
        $log->error("connect to $repoHost:$repoPort failed");
        
        # 连接mysql异常，返回undef
        return undef;
    }

    $log->info("connect to $repoHost:$repoPort success");
    
    # SQL语句
    my $updateTime = $self->getCurrentTime();
    my $sql = "insert into backup_key(ip,port,db_type,bak_type,enc_key,backup_start_time,update_time)"
        . " values('$host','$port','$dbType','$bakType','$encKey','$startTime','$updateTime');";
    $log->info($sql);
    
    # 执行更新操作    
    $self->mysqlExecute($dbh,$sql);
       
    $log->info("$host:$port update encrypt key success");
}

# @Description:  插入备份结果信息到资料库
# @Param: 
# @Return:  last_insert_id or undef
#           返回last_insert_id, 以后根据last_insert_id更新备份状态
sub insertBackupInfo {    
    my ( $self,$host,$port,$dbType,$bakType,$level,$levelValue,
        $startTime,$endTime,$size,$status,$message,$filerDir,$fileDir,$backupsetStatus,
        $updateTime,$isSlave,$isCompressed,$isEncrypted,$masterLogFile,$masterLogPos ) = @_;

    my $log = Log::Log4perl->get_logger("");

    # 获取备份资料库数据库连接参数
    my ($repoHost,$repoPort,$repoUser,$repoPass,$repoDb) = $self->getRepoInfo();
    
    # 连接备份资料库
    my $dbh = $self->mysqlConnect($repoHost,$repoPort,$repoDb,$repoUser,$repoPass);
    if ( !$dbh ){
        $log->error("connect to $repoHost:$repoPort failed");
        
        # 连接mysql异常，返回undef
        return undef;
    }
    $log->info("connect to $repoHost:$repoPort success"); 
        
    # SQL语句
    my $sql = "insert into backup_info (ip,port,db_type,bak_type,level,level_value,"
        . "start_time,end_time,size,status,message,filer_dir,file_dir,backupset_status,update_time,"
        . "instance_role,is_compressed,is_encrypted,master_log_file,master_log_pos)"
        . " values('$host','$port','$dbType','$bakType','$level','$levelValue',"
        . " '$startTime','$endTime','$size','$status','$message','$filerDir','$fileDir',"
        . " '$backupsetStatus','$updateTime','$isSlave',"
        . " '$isCompressed','$isEncrypted','$masterLogFile','$masterLogPos')";

    $log->info($sql);

    # 执行更新操作    
    $self->mysqlExecute($dbh,$sql);
  
    # 返回 last_insert_id
    my @lastInsertId = $self->mysqlQueryOneArray($dbh,"SELECT LAST_INSERT_ID()");
    if ( !@lastInsertId ){
        $log->error("get $host:$port last_insert_id failed");
        
        # 查询结果为空，返回undef
        return undef;
    }
    
    $log->info("get $host:$port last_insert_id: $lastInsertId[0]");
    
    return $lastInsertId[0];
}

# @Description:  更新备份状态到资料库
# @Param:
# @Return: 
sub updateBackupInfo {    
    my ( $self,$id,$endTime,$size,$status,$message,$fileDir,$backupsetStatus,
        $updateTime,$masterLogFile,$masterLogPos ) = @_;
                    
    my $log = Log::Log4perl->get_logger("");
    
    # 检查变量
    chomp($id,$endTime,$size,$status,$message,$fileDir,$backupsetStatus,$updateTime,$masterLogFile,$masterLogPos);
    
    # 获取备份资料库数据库连接参数
    my ($repoHost,$repoPort,$repoUser,$repoPass,$repoDb) = $self->getRepoInfo();
    
    # 连接备份资料库
    my $dbh = $self->mysqlConnect($repoHost,$repoPort,$repoDb,$repoUser,$repoPass);
    if ( !$dbh ){
        $log->error("connect to $repoHost:$repoPort failed");
        
        # 连接mysql异常，返回undef
        return undef;
    }
    $log->info("connect to $repoHost:$repoPort success"); 
    
    my $sql = "update backup_info set end_time='$endTime', size=$size, status=$status,message='$message',"
        . "file_dir='$fileDir',backupset_status='$backupsetStatus',update_time='$updateTime',"
        . "master_log_file='$masterLogFile',master_log_pos='$masterLogPos' where id=$id";

    $log->info($sql);

    # 执行更新操作
    $self->mysqlExecute($dbh,$sql);
    
    $log->info("update backup info success");
}

# @Description:  更新备份资料库中keep_status为deleted
# @Param:
# @Return:
sub deleteBackupInfo {    
    my ($self,$host,$port,$fileDir) = @_;

    my $log = Log::Log4perl->get_logger("");
        
    # 检查变量
    chomp($host,$port,$fileDir);

    # 获取备份资料库数据库连接参数
    my ($repoHost,$repoPort,$repoUser,$repoPass,$repoDb) = $self->getRepoInfo();
    
    # 连接备份资料库
    my $dbh = $self->mysqlConnect($repoHost,$repoPort,$repoUser,$repoPass,$repoDb);
    if ( !$dbh ){
        $log->error("connect to $repoHost:$repoPort failed");
        
        # 连接mysql异常，返回undef
        return undef;
    }
    $log->info("connect to $repoHost:$repoPort success"); 
    
    # SQL语句    
    my $sql = "update backup_info set keep_status='DELETED', keep_update_time=now()"
        . " where host='$host' and port='$port' and file_dir like '$fileDir%';";
    
    $log->info($sql);
    
    # 执行更新操作    
    $self->mysqlExecute($dbh,$sql);
    
    $log->info("$host:$port update backup info success");
}

# @Description:  查询备份资料库中上一次成功备份的master_log_file
# @Param: 
# @Return:  $masterLogFile or undef
sub getMasterLogFile {    
    my ($self,$host,$port,$bakType) = @_;

    my $log = Log::Log4perl->get_logger("");
    
    # 获取备份资料库数据库连接参数
    my ( $repoHost,$repoPort,$repoUser,$repoPass,$repoDb ) = $self->getRepoInfo();
    
    # 连接备份资料库
    my $dbh = $self->mysqlConnect($repoHost,$repoPort,$repoUser,$repoPass,$repoDb);
    if ( !$dbh ){
        $log->error("connect to $repoHost:$repoPort failed");
        
        # 连接mysql异常，返回undef
        return undef;
    }
    $log->info("connect to $repoHost:$repoPort success"); 

    my $sql = "select master_log_file from backup_info where ip='$host' and port=$port and bak_type='$bakType'"
        . "and status=1 order by id desc limit 1;";

    $log->info($sql);

    # 执行查询操作
    my $masterLogFile = $self->mysqlQuery($dbh,$sql);
    if ( !$masterLogFile ){
        $log->error("get $host:$port master_log_file failed");
        
        # 查询结果为空，返回undef
        return undef;
    }
    
    $log->info("get $host:$port master_log_file: $masterLogFile success");
    
    return $masterLogFile;
}

# @Description:  获取备份调度计划
# @Param:  $host,$port
# @Return:  $backupConfig or undef
sub getBackupConfig {
    my ( $self,$host ) = @_;

    my $log = Log::Log4perl->get_logger("");

    # 获取备份资料库数据库连接参数
    my ($repoHost,$repoPort,$repoUser,$repoPass,$repoDb) = $self->getRepoInfo();
    
    # 连接备份资料库
    my $dbh = $self->mysqlConnect($repoHost,$repoPort,$repoUser,$repoPass,$repoDb);
    if ( !$dbh ){
        $log->error("connect to $repoHost:$repoPort failed");
        
        # 连接mysql异常，返回undef
        return undef;
    }
    $log->info("connect to $repoHost:$repoPort success"); 

    # SQL语句
    my $sql = "select ip,port,bak_type,level,level_value,is_compressed,is_slave,parallel,retention,"
        . "is_encrypted,schedule_type,schedule_time,storage_ip,lvm_expire_days,mysqldump_expire_days,"
        . "mongodump_expire_days,mysql_hotbak_expire_days,ftp_expire_days,"
        . "lvm_speed,mysql_binlog_speed,mysql_hotbak_throttle"
        . " from dbms.backup_config where ip='$host'";

    $log->info($sql);

    # 执行查询操作
    my $backupConfig = $self->mysqlQueryMulti($dbh,$sql);
    if ( ! $backupConfig ){
        $log->error("get $host backup config failed");
        
        # 查询结果为空，返回undef
        return undef;
    }
        
    $log->info("get $host backup schedule config success");
    
    return $backupConfig;
}

# @Description:  获取本地挂载的备份存储路径
# @Param:  $host,$port,$dbType,$storageType
# @Return:  $storageDir or undef
sub getStorageDir {
    my ($self,$host,$port,$dbType,$storageType) = @_;

    my $log = Log::Log4perl->get_logger("");
    
    # 备份存储目录
    my $storageDir;
    
    # 本地硬盘存储
    if ( lc($storageType) =~ /local/ ){
        if ( lc($dbType) =~ /mysql/ ){
            $storageDir = "/data/backups/my" . $port;
        } elsif ( lc($dbType) =~ /mongodb/ ){
            $storageDir = "/data/backups/shard" . $port;
        }
        chomp($storageDir);
        
    } else {
        if ( lc($dbType ) =~ /mysql/ ){
            $storageDir = "/home/mysql/backup_stage/$host" . "_" . $port;
        } elsif ( lc($dbType ) =~ /mongodb/ ){
            $storageDir = "/home/mongodb/backup_stage/$host" . "_" . $port;
        }
        chomp($storageDir);
        
        # 检查mfs备份目录挂载
        $log->info("start checking $storageDir is mounted or not");
        
        eval{
            # 执行mount命令，获取所有已挂载信息
            my $mountInfo = `mount`;
            chomp($mountInfo);
            
            my @mountInfoList = split(/\n/, $mountInfo);
            
            my $isMounted = grep /$storageDir/,@mountInfoList;
            if ( $isMounted == 1 ){
                $log->info("$storageDir is already mounted");    
            }else{
                $log->error("$storageDir is not mounted");
                $storageDir = "";
            }
        };
        if ( $@ ){
            $log->error("get mount info failed");
            undef $@;
        }
    }

    return $storageDir;
}

# @Description:  获取ip地址
# @Param: 
# @Return:  $ipAddr or undef
sub getIpAddr {
    my $self = @_;
    
    my $ipAddr;

    eval {
        $ipAddr = `hostname -i`;
        
        chomp($ipAddr);
        
        $ipAddr =~ s/^\s+//g;
    };
    if($@){
        undef $@;
        
        return undef;
    }
    
    return $ipAddr;
}

# @Description:  检查是否已有备份
# @Param:
# @Return:  0: 备份不存在,可发起备份  1: 备份存在,退出备份         
sub isExistBackupset {        
    my ( $self,$host,$port,$dbType,$bakType,$bakDir,$fileDir ) = @_;

    my $log = Log::Log4perl->get_logger("");
    
    my $exitCode = 1;
    
    $log->info("start checking backup directory");
        
    eval{
        if ( opendir(DBPATH,"$bakDir") ){
            my @file = grep { !/^\./ && -e "$bakDir\/$_" } readdir DBPATH;
            closedir DBPATH;
            
            if ( $#file > 0 ){
                # 获取备份资料库数据库连接参数
                my ( $repoHost,$repoPort,$repoUser,$repoPass,$repoDb ) = $self->getRepoInfo();
    
                # 连接备份资料库
                my $dbh = $self->mysqlConnect($repoHost,$repoPort,$repoDb,$repoUser,$repoPass);
                if ( !$dbh ){
                    $log->error("connect to $repoHost:$repoPort failed");
                }
                $log->info("connect to $repoHost:$repoPort success");
                
                # SQL语句
                my $sql = "select status "
                    . " from backup_info "
                    . " where ip='$host' and port=$port and db_type='$dbType' and bak_type='$bakType' and file_dir='$fileDir'"
                    . " order by id desc limit 1";

                $log->info($sql);
               
                # 执行查询
                my $row = $self->mysqlQuery($dbh,$sql);
                
                if ( defined($row) ){
                    my $status = $row->{status};
                    chomp($status);
                    if ( $status == 1 ){
                        $log->info("instance $host:$port backupset exists,status: $status");
                    }else{
                        $log->error("instance $host:$port backup dir is not empty,but backupset status is bad");
                    }
                }
            }
        }else{
            $log->info("instance $host:$port backup directory: $bakDir is empty");
            $log->info("instance $host:$port backupset not exists");

            $exitCode = 0;
        }
    };
    if ( $@ ){
        $log->error("instance $host:$port check backupset failed");
        undef $@;
    }
    
    return $exitCode;
}

# @Description:  获取filer目录
# @Param:  
# @Return:  $filer or undef
sub getFilerDir {
    my ( $self,$host,$port,$dbType,$storageType ) = @_;

    my $log = Log::Log4perl->get_logger("");
    
    my $filer;

    # 本地硬盘存储
    if ( lc($storageType) =~ /local/ ){
        if ( lc($dbType) =~ /mysql/ ){
            $filer = "/data/backups/my" . $port;
        } elsif ( lc($dbType) =~ /mongodb/ ){
            $filer = "/data/backups/shard" . $port;
        }
        chomp($filer);
        
    } else {
    # mfs存储
        my ( $filerPath,$localPath,$fType,$mfsIp );
        eval{
            $localPath = "/home/${dbType}/backup_stage/${host}_${port}";
            open MTAB,"<","/etc/mtab" or die "can't open file /etc/mtab";
            while( <MTAB> ){
                if ( $_ =~ /([\d\D]+?)\s+$localPath\s+([\d\D]+?)\s/ ){
                    $filerPath = $1;
                    $fType = $2;
                    chomp($filerPath,$localPath,$fType);
                    
                    if ( lc($fType) eq "fuse.mfs" or lc($fType) eq "fuse" ){
                        $fType = "mfs";
                        if ( $filerPath =~ /(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}):\d+/ ){
                            $mfsIp = $1;
                            chomp($mfsIp);
                        }else{
                            die "can't get mfs server ip from /etc/mtab";
                        }
                        
                        $filerPath = `ps -ef|grep [m]fsmount|grep $localPath`;
                        if ( $filerPath =~ /-S\s+([\d\D]+?)\s+/ ){
                            $filerPath = "$mfsIp:$1";
                        }else{
                            $filerPath = undef;
                            $log->error("can't get mfsmount source directory");
                        }
                    }
                    
                    last;
                }
            }
            
            if ( defined($filerPath) and defined($localPath) and defined($fType) ){
                $filer = "$fType:$filerPath";
            }else{
                $filer = undef;
            }
        };
        if ( $@ ){
            $log->error("can't get filer directory");
            
            return undef;
        }
    }
    
    return $filer;
}

# @Description:  删除过期备份集
# @Param: 
# @Return:  成功:1  失败:0
sub deleteExpiredBackupSet {
    my ( $self,$host,$port,$dbType,$bakType,$date,$bakDir,$retention,$expire,$forceDelete ) = @_;

    my $log = Log::Log4perl->get_logger("");
    
    my $exitCode = 0;
        
    $log->info("start removing expired backupSet");
    
    my ($year,$month,$day) = (substr($date,0,4),substr($date,4,2),substr($date,6,2));
    
    my $dt = DateTime->new(
        year => $year,
        month => $month,
        day => $day
    );
    
    $dt->add(days=> -$expire);
    $month = $dt->month();
    $day = $dt->day();

    if ( $month < 10 ){
        $month = "0$month";
    }
    
    if ( $day < 10 ){
        $day = "0$day";
    }

    my $expireDate = "$year$month$day";
    
    eval{
        if ( opendir(BACKDIR,"$bakDir") ){       
            my @file = grep { !/^\./ && /^\d{8}_/ && -e "$bakDir" } readdir BACKDIR;
            $log->info("current exist backup @file");
            closedir BACKDIR;
            
            my %bakGroup;
            foreach my $f (@file){
                if ( $f =~ /(\d{8})_([\d\D]+)/ ){
                    if ( !defined($bakGroup{$2}) ){
                        $bakGroup{$2} = $1;
                    }else{
                        $bakGroup{$2} = "$bakGroup{$2},$1";
                    }
                }
            }

            while ( my($keyObj, $valueDate) = each %bakGroup ){
                @file = split(/,/, $valueDate);
                if ( $#file > $retention - 1 ){
                    @file = sort {$b cmp $a} @file;
                    for ( my $i=$retention;$i<$#file+1;$i++ ){
                        if ( $file[$i] > $expireDate ){
                            $log->info("expire days is $expire, current date is $date, don't delete $file[$i]_${keyObj}");
                            next;
                        }
                        
                        remove_tree("$bakDir/$file[$i]_${keyObj}",{result=>\my $rmList,error=> \my $rmErr});
                        
                        if ( defined($$rmErr[0]) ){
                            $log->error("delete dir ${$bakDir}/$file[$i]_${keyObj} failed, error msg:$rmErr");
                            
                        }else{
                            my $opTime = $self->getCurrentTime();
                            my $bakFileDir = "$file[$i]_${keyObj}";
                            $log->debug("\$bakFileDir: $bakFileDir");
                            
                            # 更新备份资料库
                            my $deleted = $self->deleteBackupInfo($host,$port,$bakDir);
                            if ( defined($deleted) ){
                                $log->info("delete backup_info record success");
                                $exitCode = 1;
                                
                            } elsif ( !defined($deleted) and defined($forceDelete )){
                                $log->warn("force delete backup_info record");
                                $log->info("delete backup_info record success");
                                $exitCode = 1;
                                
                            } else {
                                $log->error("delete backup_info record failed");
                                
                            }
                            $log->info("delete dir ${bakDir}/$file[$i]_${keyObj} success");
                        }
                    }
                }
            }
        }else{
            $log->error("can't delete expired backupSet, open backup dir: $bakDir failed");
            return $exitCode;
        }
    };
    if ($@){
        $log->error("delete expired backupSet failed: $@");
        
        return $exitCode;
    }

    $log->info("delete expired backupSet success");
    
    return $exitCode;
}

# @Description:  删除目录
# @Param:  $dir
# @Return:  成功:1  失败:0
sub removeDirectory {
    my ( $self,$dir ) = @_;
    
    my $log = Log::Log4perl->get_logger("");    
    
    my $status = 0;
    $log->info("remove dir: $dir");
    remove_tree( "$dir",{ result=>\my $rmList,error=> \my $rmErr });
    if ( defined($$rmErr[0]) ){
        $log->error("remove dir: $dir failed, error msg: $rmErr");
        $status = 0;
    }else{
        $log->info("remove directory $dir success");
        $status = 1;
    }
    
    return $status;
}

# @Description:  对已经完成的备份目录执行加密
# @Param: 
# @Return:  成功:$encFileName  失败:0
sub encryptBackup {
    my ( $self,$host,$port,$dbType,$bakType,$bakDir,$startTime ) = @_;

    my $log = Log::Log4perl->get_logger("");

    $log->info("starting encrypt backupset");
    $log->info("backup dir: $bakDir");
    
    $log->info("retrieve encrypt key");
    my $encKey = "";
    my $genEncKeyLocal = 0;
    my $cmdResultEK = $self->getEncryptKey($host,$port,$dbType,$bakType,$startTime);
    if ( defined($cmdResultEK) ) {
        $log->info("restrieve encrypt key success");
        $encKey = $cmdResultEK->{strings};
    }else{
        $log->warn("restrieve encrypt key failed");
        
        my $md5Feed = $host.$port.$dbType.$startTime;
        $encKey = Digest::MD5->new->add($md5Feed)->hexdigest;
        $genEncKeyLocal = 1;
    }
    
    $log->info("compute backup directory size");
    my $du = `du -sh $bakDir`;
    chomp( $du );
    
    $log->debug("get \$bakDir: $bakDir");
    $log->debug("get \$du: $du");

    my ( $bakSize, $bakPath ) = split /\s+/,$du;
    chomp( $bakSize );
    $log->debug("get \$bakSize: $bakSize");
    $log->debug("get \$bakPath: $bakPath");

    $log->info("backup dir size is $bakSize");

    if ( ! defined($bakSize) ) {
        $log->error("check backup dir: $bakDir failed");
        return 0;
    }

    if ( ! -e "/bin/tar" ) { 
        $log->error("/bin/tar does not exist");
        return 0;
    }
    
    if ( ! -e "/usr/bin/openssl" ) {
        $log->error("/bin/tar does not exist!");
        return 0;
    }

    my ( $encFilePath,$encFileName,$encSrcFileName );
    if ( $bakDir =~ /^(.*)\/(.*)$/ ){
        $encFilePath = $1;
        $encSrcFileName = $2;
        $encFileName = $2.".tar.enc";
    }

    $log->info("executing encrypt and tar into encrypted file");
  
    my $encCmd = "cd $encFilePath; /bin/tar -zcf - $encSrcFileName |/usr/bin/openssl rc4 -pass pass:$encKey |dd of=$encFilePath/$encFileName 2>&1 ;echo result_code_\$?";
    $log->info("execute encrypt command: $encCmd");
    my $ret = `$encCmd`;
  
    my $retcode = $?;
    $log->debug("encrypt result :\nresult code> $retcode \ncommand information >\n $ret \n encrypt file : $encFilePath/$encFileName .");
    if ( $ret =~ /result_code_0/x && -e "$encFilePath/$encFileName" ) {
        $log->info("encrypt is completed, replace into backup directory now");
        system("rm -rf $bakDir");
        if ( -d "$bakDir" ) {
            $log->error("failed to remove old backup directory");
            
            return 0;
        }      
      
        system("mkdir -p $bakDir");
        if ( ! -d "$bakDir" ) {
            $log->error("failed to create new backup directory");
            
            return 0;
        }     

        system("mv $encFilePath/$encFileName $bakDir");
        if ( -e "$bakDir/$encFileName" ) {
            $log->info("get \$host:$host,\$port:$port,\$dbType:$dbType,\$bakType:$bakType,\$startTime:$startTime");
          
            # upload local encrypted key
            my $cmdResultUek = $self->uploadEncryptKey($host,$port,$dbType,$bakType,$encKey,$startTime);
            if ( defined($cmdResultUek) ){
                $log->info("upload encrypt key success");
            }else{
                $log->warn("upload encrypt key failed, retry upload");
                `sleep 30`;
                $cmdResultUek =  $self->uploadEncryptKey($host,$port,$dbType,$bakType,$encKey,$startTime);
                if ( defined($cmdResultUek) ){
                    $log->info("upload encrypt key success after retry");
                }else{
                    $log->warn("upload encrypt key:failed, stop retrying");
                    $log->info($encKey);
                }
            }
            $log->info("get encFileName: $encFileName");
            
            return $encFileName;
        }else {
            $log->error("move enctypted backupset file to new backup directory failed");
            
            return 0;
        } 
    }else{
        $log->error("execute tar and enctypt command failed");
        
        return 0;
    }  
}

# @Description:  对已经完成的备份目录压缩
# @Param:
# @Return:  成功:$compressFileName  0:失败
sub compressBackup {
    my ( $self,$host,$port,$dbType,$bakType,$bakDir,$startTime ) = @_;

    my $log = Log::Log4perl->get_logger("");
    
    $log->info("starting to compress backup directory");
    $log->info("backup directory is: $bakDir");

    $log->info("compute backup directory size");    
    my $du = `du --block-size=1G -s $bakDir`;
    chomp( $du );
    
    my ( $bakSize, $bakPath ) = split /\t+/, $du;
    chomp( $bakSize );

    $log->info("backup directory size is $bakSize GB");

    if ( !defined($bakSize) ) {
        $log->error("failed to check backup size from $bakDir");
        
        return 0;
    }
    
    my ( $compressFilePath,$compressFileName,$compressSrcFileName );
    if( $bakDir =~ /^(.*)\/(.*)$/ ){
        $compressFilePath = $1;
        $compressSrcFileName = $2;
        $compressFileName = $2.".tar.gz";
    }

    $log->info("executing compress and tar into file");
  
    my $encCmd = "cd $compressFilePath; tar -zcf - $compressSrcFileName | dd of=$compressFilePath/$compressFileName 2>&1 ;echo result_code_\$?";
    $log->info("execute command: $encCmd");
    
    my $ret = `$encCmd`;
    my $retcode = $?;
    $log->debug("compress result :\nresult code> $retcode \ncommand information >\n $ret \n compress file : $compressFilePath/$compressFileName .");
 
    if ( $ret =~ /result_code_0/ && -e "$compressFilePath/$compressFileName" ) {
        $log->info("compress is completed, replace into backup directory now");
      
        system("rm -rf $bakDir");
        if ( -d "$bakDir" ) {
            $log->error("failed to remove old backup directory");
            
            return 0;
        }      

        system("mkdir -p $bakDir");
        if ( ! -d "$bakDir" ) {
            $log->error("failed to create new backup directory");
            
            return 0;
        }
        
        system("mv $compressFilePath/$compressFileName $bakDir");
        if ( -e "$bakDir/$compressFileName" ){            
            return $compressFileName;
        } else {
            $log->error("failed to move enctypted backup file to new backup directory");
            
            return 0;
        } 
    } else {
        $log->error("failed to execute compress backupset");
        
        return 0;
    }  
}

# @Description:  检查备份资料库备份集状态
# @Param:  $host,$port,$bakType,$backupSet
# @Return:  $status or undef
sub getBackupsetStatus {
    my ( $self,$host,$port,$bakType,$backupSet ) = @_;
    
    my $log = Log::Log4perl->get_logger("");
        
    # 获取备份资料库数据库连接参数
    my ($repoHost,$repoPort,$repoUser,$repoPass,$repoDb) = $self->getRepoInfo();
    
    # 连接备份资料库
    my $dbh = $self->mysqlConnect($repoHost,$repoPort,$repoDb,$repoUser,$repoPass);
    if ( !$dbh ){
        $log->error("connect to $repoHost:$repoPort failed");
        
        # 连接mysql异常，返回undef
        return undef;
    }
    $log->info("connect to $repoHost:$repoPort success"); 

    my $sql = "select status from backup_info where ip='$host' and port=$port";
        $sql .= " and bak_type='$bakType' and file_dir like '%$backupSet%'";
    
    $log->info($sql);

    # 执行查询操作
    my $status = $self->mysqlQuery($dbh,$sql);
    if ( !$status ){
        $log->error("get backupset status failed");
        
        # 查询结果为空，返回undef
        return undef;
    }
    
    $log->info("get backupset status success");
    
    return $status;    
}

# @Description:  检查目录是否为空
# @Param:  $dir
# @Return:  $row or undef
sub isDirEmpty {
    my ( $self, $dir ) = @_;
    
    my $log = Log::Log4perl->get_logger("");
    
    opendir(my $dh, $dir) or $log->error("directory does not exist: $dir");
    
    return scalar(grep { $_ ne "." && $_ ne ".." } readdir($dh)) == 0;
}

# @Description:  执行外部命令
# @Param:  $command
# @Return:  $result
sub runCommand {
    my ( $self, $command ) = @_;

    my $log = Log::Log4perl->get_logger("");
        
    # 获取执行命令超时时间
    my $excuteCmdTimeout = $self->{dbconfigObj}->get('excuteCmdTimeout');

    # 命令执行结果
    my $result;
    
    # 命令执行退出码
    my $exitCode;

    # 超时处理
    my $timeoutMsg = "CMD_TIMEOUT";
    my $sigset = POSIX::SigSet->new( SIGALRM );  # signals to mask in the handler
    my $action = POSIX::SigAction->new( sub { die $timeoutMsg; },$sigset,);
    my $oldaction = POSIX::SigAction->new();
    sigaction( SIGALRM, $action, $oldaction ); 
    eval {
        alarm $excuteCmdTimeout;
        
        # 执行命令
        $result = `$command`;
        $exitCode = $?;
        
        alarm 0; 
    };
    alarm 0; # race condition protection
    sigaction( SIGALRM, $oldaction );  # restore original signal handler
    
    # 异常处理
    if ( $@ ) {
        if ( $@ =~ /$timeoutMsg/ ) {
            # 超时
            $log->error("runCommand $command timeout");
        }else{
            # 其他异常
            $log->error("runCommand $command failed");
        }
        undef $@;
    }
    
    return $result;
}

# @Description:  执行外部命令
# @Param:  $command
# @Return:  $exitCode
sub runCommandReturnCode {
    my ( $self, $command ) = @_;

    my $log = Log::Log4perl->get_logger("");
        
    # 获取执行命令超时时间
    my $excuteCmdTimeout = $self->{dbconfigObj}->get('excuteCmdTimeout');

    # 命令执行结果
    my $result;
    
    # 命令执行退出码
    my $exitCode;

    $log->debug("get \$command: $command");
    
    # 超时处理
    my $timeoutMsg = "CMD_TIMEOUT";
    my $sigset = POSIX::SigSet->new( SIGALRM );  # signals to mask in the handler
    my $action = POSIX::SigAction->new( sub { die $timeoutMsg; },$sigset,);
    my $oldaction = POSIX::SigAction->new();
    sigaction( SIGALRM, $action, $oldaction ); 
    eval {
        alarm $excuteCmdTimeout;
        
        # 执行命令
        $result = `$command`;
        
        if ( defined($result) ){
            $log->debug("get \$result: $result");
        }
        
        $exitCode = $?;
        
        alarm 0; 
    };
    alarm 0; # race condition protection
    sigaction( SIGALRM, $oldaction );  # restore original signal handler
    
    # 异常处理
    if ( $@ ) {
        if ( $@ =~ /$timeoutMsg/ ) {
            # 超时
            $log->error("runCommand $command timeout");
        }else{
            # 其他异常
            $log->error("runCommand $command failed");
        }
        undef $@;
    }
    
    return $exitCode;
}

# @Description:
# @Param:
# @Return:  $row or undef
sub checkMysqldump {
    my ( $self,$host,$port,$dbname,$user,$pass,$dbType,$bakDir,$storageType ) = @_;

    my $log = Log::Log4perl->get_logger("");
    
    # 检查备份文件目录
    if ( -d $bakDir ){
        if ( $self->isDirEmpty($bakDir) ){
            $log->info("dir $bakDir exist and is empty");
        } else {
            $log->error("dir $bakDir exist and is not emprty");
        }
    }else{
        unless (mkdir $bakDir){
            $log->error("faild to create dir $bakDir");
        }
    }

    # 检查备份存储目录
    my $storageDir = $self->getStorageDir($dbType,$host,$port,$storageType);
    if ( $storageDir ){
        $log->info("get storage success,$storageDir");
    } else {
        $log->error("get storage failed,$storageDir");
    }
    
    $log->info("bak dir: $bakDir, storage dir: $storageDir");
  
    # 检查mysql环境
    my $dbh = $self->mysqlConnect($host,$port,$dbname,$user,$pass);

    my $mysqlBaseDir = $self->getMysqlVariable($dbh,"select \@\@basedir");
    $log->info("get mysql basedir is $mysqlBaseDir");
    
    # 检查bin log开启情况
    my $logBin = $self->getMysqlVariable($dbh,"select \@\@log_bin");
    $log->info("get mysql log bin is $logBin");
    
    # 检查mysql版本
    my $mysqlVersion = $self->getMysqlVariable($dbh,"select \@\@version");
    $log->info("get mysql version is $mysqlVersion");
    
    # mysql版本代码
    my $versionCode = (split(/-/,$mysqlVersion))[0];
    $versionCode = ~ s/\.//g;
        
    # 获取mysql配置文件
    my $mycnf;
    my $baseDir;
    my $mytab = "/etc/mytab";
    open MYTAB,$mytab or $log->error("failed to open file $mytab");
    while ( my $line=<MYTAB> ){
        if ( $line =~ m/$port/ ){
            $baseDir = (split(' ',$line))[0];
            $mycnf = (split(' ',$line))[1];
        }
    }
    close(MYTAB);
    
    if ( !$mycnf ){
        $log->error("can't found $mycnf file");
    }
    
    $log->info("get mysql config file: $mycnf");
}

# @Description:  获取mfs服务器Ip
# @Param:  
# @Return:  $mfsServerIp
sub getMfsServerIp {
    my ( $self,$host,$port,$dbType ) = @_;

    my $log = Log::Log4perl->get_logger("");
        
    my $mfsServerIp;
    my $mount = qq(/bin/mount);
    my @mountOutput = qx/$mount/;

    foreach my $line (@mountOutput){
        if ( $line =~ /$dbType/ and $line =~ /$host/ and $line=~ /$port/ and $line =~ /mfs/ ){
            my ( $col1,$col2,undef,undef,undef,undef ) = split(/ /, $line);
            ( $mfsServerIp,undef ) = split(/:/, $col1);
        }
    }

    return $mfsServerIp;
}

# @Description:  获取ftp服务器地址
# @Param:  $ftpServer
# @Return:  成功:$ftpServer  失败:0
sub getFtpServer {
    my ( $self,$host,$port ) = @_;
    
    my $log = Log::Log4perl->get_logger("");
    
    # 获取ip网段
    my ( $c1,$c2,$c3,undef ) = split(/\./, $host);
    my $c4 = "0";
    my $ipNet = join('.',$c1,$c2,$c3,"0");
    chomp($ipNet);
             
    # 获取备份资料库数据库连接参数
    my ($repoHost,$repoPort,$repoUser,$repoPass,$repoDb) = $self->getRepoInfo();
    
    # 连接备份资料库
    my $dbh = $self->mysqlConnect( $repoHost,$repoPort,$repoDb,$repoUser,$repoPass );
    if ( !$dbh ){
        $log->error("connect to $repoHost:$repoPort failed");
        
        # 连接mysql异常，返回undef
        return undef;
    }
    $log->info("connect to $repoHost:$repoPort success"); 
        
    # SQL语句
    my $sql = "select ftp_ip from ftp_router where ip_net='$ipNet';";
            
    $log->info($sql);
    
    # 执行查询操作
    my $res = $self->mysqlQuery($dbh,$sql);
    my $ftpIp = $res->{ftp_ip};
    if ( !$ftpIp ){
        $log->error("get ftp server ip failed");
        
        # 查询结果为空，返回0
        return 0;
    }
    
    $log->info("get ftp server ip success");
    $log->info("ftp server: $ftpIp");
        
    return $ftpIp;
}

# @Description:  更新ftp备份流水
# @Param:  
# @Return:  
sub updateFtpBackupInfo {
    my ( $self,$host,$port,$filerIp,$dumpSet,$ftpServer ) = @_;

    my $log = Log::Log4perl->get_logger("");
    
    # 获取备份资料库数据库连接参数
    my ($repoHost,$repoPort,$repoUser,$repoPass,$repoDb) = $self->getRepoInfo();
    
    # 连接备份资料库
    my $dbh = $self->mysqlConnect( $repoHost,$repoPort,$repoDb,$repoUser,$repoPass );
    if ( !$dbh ){
        $log->error("connect to $repoHost:$repoPort failed");
        
        # 连接mysql异常，返回undef
        return undef;
    }
    $log->info("connect to $repoHost:$repoPort success");

    # SQL语句
    my $sql = qq(insert into ftp_backup_info\(ip,port,filer_ip,dump_set_dir,ftp_server\) values\('$host','$port','$filerIp','$dumpSet','$ftpServer'\););
            
    $log->info($sql);

    # 执行更新操作
    $self->mysqlExecute($dbh,$sql);
    
    $log->info("$host:$port insert into ftp_backup_info success");
    
    return 1;
}

# @Description:  检查是否需要上传备份集
# @Param:  $lastFtpBackupTime,$retention
# @Return:  需要:1  不需要:0
sub isNeedUploadBackupSet {
    my ( $self,$lastFtpBackupTime,$retention ) = @_;
    
    my $log = Log::Log4perl->get_logger("");
    
    # 用$lastFtpBackupTime和当前时间比较, 看是否需要上传新的备份集
    my $keepDays = int(30/$retention);
    my $lastPlanDate = `date -d "$keepDays day ago" +"%Y%m%d"`;
    
    $log->info("last ftp backup time: $lastFtpBackupTime, last plan time: $lastPlanDate");
    if ( $lastFtpBackupTime >= $lastPlanDate ){
        # 不需要上传备份
        $log->info("no need upload backupset to ftp server");

        return 0;
    }else{
        # 需要上传备份
        $log->info("need upload backupset to ftp server");
        
        return 1;
    }
}

# @Description:  获取最新备份集
# @Param:  
# @Return:  $latestBackupDir or 0
sub getLatestBackupSet {
    my ( $self,$host,$port,$dbType,$storageType ) = @_;
    
    my $log = Log::Log4perl->get_logger("");    
    
    my $storageDumpDir;
    my $storageDir = $self->getStorageDir( $host,$port,$dbType,$storageType );
    if ( $storageDir ){
        $storageDumpDir = $storageDir . "/dump";
        chomp($storageDumpDir);
    }

    # 获取所有备份集
    my @bakDir;
    if ( -d $storageDumpDir ){
        my $cmd = qq(ls $storageDumpDir);
        @bakDir = qx/$cmd/;
    }else{
        $log->error("$storageDumpDir not exist");

        return 0;
    }

    # 获取最新备份集
    my $latestBackupSet;
    my $latestbackupDate = 0;
    foreach my $bakDir (@bakDir) {
        if ( $bakDir =~ /$host/ ){
            if ( $bakDir =~ /\d+\_\d+\.\d+\.\d+\.\d+\_\d+/ ){
                my ( $bakDate,$bakIp,$bakPort ) = split(/\_/,$bakDir );
                if ( $bakDate > $latestbackupDate ){
                    $latestbackupDate = $bakDate;
                    $latestBackupSet = $bakDir;
                    chomp($latestBackupSet);
                }
            }
        }
    }

    if ( defined($latestBackupSet) ){
        $log->info("get latest backupset directory: $latestBackupSet");
        
        my $currDate = $self->getCurrentDate();
        
        # 计算备份时间间隔
        my $intervalDays = $currDate - $latestbackupDate;
        if ( $intervalDays >= 0 and $intervalDays < 30 ){
            # 有效备份为30天内的备份
            $log->info("backupSet with today interval: $intervalDays days, is valid");
            
            my $latestBackupDir = "$storageDumpDir/$latestBackupSet";
            
            return $latestBackupDir;
        }else{
            $log->error("backupSet with today interval: $intervalDays days, is not valid");
            $log->error("ftp backup should be config with dump backup config");
            
            return 0;
        }
    }else{
        $log->error("can not found valid backupSet under $storageDumpDir");
        
        return 0;
    }
}

# @Description:  删除ftp过期备份集
# @Param: 
# @Return:  1:success  0:failed
sub deleteFtpExpireBackupSet {
    my ( $self,$host,$port,$retention,$ftpServer,$ftpUser,$ftpPass ) = @_;

    my $log = Log::Log4perl->get_logger("");
    my @bakSet;
    my @validBakSet;
    my $errMsg;
    
    # 连接到ftp server
    my $ftp = Net::FTP->new($ftpServer);
    if ( $ftp ){
        $ftp->login($ftpUser,$ftpPass) or do {
            $errMsg = $ftp->message;
            $log->error("connect to $ftpServer failed, error msg: $errMsg");
            return 0;
        };
    }else{
        $log->error("connect to $ftpServer failed, error msg: $@");
        return 0;
    }

    my $ftpDir = $host . "_" . $port;
    if ( $ftp->cwd("/$ftpDir") ){
        # 获取ftp路径下的所有目录
        @bakSet = $ftp->ls();
        foreach (@bakSet){
            # 匹配标准备份目录格式 如:20150801_10.100.20.37_3306
            if ( $_ =~ /\d+\_\d+\.\d+\.\d+\.\d+\_\d+/ ){
                push @validBakSet,$_;
            }
        }
    }else{
        $errMsg = $ftp->message;
        $log->error("cannot cwd $ftpDir, error msg: $errMsg");
        # 目录不存在
        return 0;
    }
     
    my $bakSetNum = scalar(@validBakSet);
    if ( $bakSetNum <= $retention ){
        $log->info("no need delete expire backupSet on ftp server");
        # 不需要删除
        return 1;
    }else{
        my $delCount = $bakSetNum - $retention;         
        foreach ( @validBakSet ){
            chomp($_);
            if ( $delCount>0 ){
                $ftp->rmdir("/$ftpDir/$_", "RECURSE");
                $delCount--;
                $log->info("remove ftp dir: /$ftpDir/$_");
            }
        }
        $ftp->close;
        
        return 1;
    }
}

# @Description:  删除失败的备份
# @Param: 
# @Return:  1:success  0:failed
sub deleteFailedBackup {
    my ( $self,$host,$port,$failedDir,$ftpServer,$ftpUser,$ftpPass ) = @_;
    
    my $log = Log::Log4perl->get_logger("");
    
    my $errMsg;
    
    # 连接ftp服务器
    my $ftp = Net::FTP->new($ftpServer);
    if ( $ftp ){
        $ftp->login($ftpUser,$ftpPass) or do {
            $errMsg = $ftp->message;
            $log->error("connect to $ftpServer failed, error msg: $errMsg");
            return 0;
        };
    }else{
        $log->error("connect to $ftpServer failed, error msg: $@");
        return 0;
    }
    
    # ftp备份目录
    my $ftpDir = $host . "_" . $port;
    if ( $ftp->cwd("/$ftpDir") ){
        $log->info("will be remove $failedDir");
        
        # 删除备份目录
        my $rs = $ftp->rmdir("$failedDir","RECURSE");
        $log->info("remove $failedDir success, result: $rs");
    }else{
        $errMsg = $ftp->message;
        $log->error("can't delete failed backup, error msg: $errMsg");
    }
}

# @Description:  获取上次ftp备份时间
# @Param:  
# @Return:  $lastFtpBackupTime or 0 or 2
sub getLastFtpBackupTime {
    my ( $self,$host,$port,$ftpServer,$ftpuser,$ftppass ) = @_;

    my $log = Log::Log4perl->get_logger("");
    
    my $errMsg;
    
    # 连接到ftp server
    my $ftp = Net::FTP->new($ftpServer);
    if ( $ftp ){
        $ftp->login($ftpuser,$ftppass) or do {
            $errMsg = $ftp->message;
            $log->error("connect to ftp server: $ftpServer failed, error msg: $errMsg");
            
            return 0;
        }; 
    }else{
        $errMsg = $ftp->message;
        $log->error("connect to ftp server: $ftpServer failed, error msg: $errMsg");
        
        return 0;
    }
    
    # 进入ftp备份目录
    my @allBackupSet;
    
    my $ftpDir = $host . "_" . $port;
    if ( $ftp->cwd("$ftpDir") ){
        # 获取备份目录备份集
        @allBackupSet = $ftp->ls();
        
    } else {
        $errMsg = $ftp->message;
        $log->error("cannot cwd $ftpDir, error msg: $errMsg");
        
        # 备份目录不存在
        return 0;
    }
     
    # 比较最新备份集
    my $lastFtpBackupTime = 0;
    my $backupSetStatus = 0;

    foreach my $backupSet (@allBackupSet){
        if ( $backupSet =~ /\d+\_\d+\.\d+\.\d+\.\d+\_\d+/ ){
            my ( $bakDate,$bakHost,$bakPort ) = split( /\_/,$backupSet );
            
            # 检查备份集有效性
            $backupSetStatus = $self->getBackupsetState( $bakHost,$bakPort,"ftp",$backupSet );
            $log->debug("get \$backupSetStatus: $backupSetStatus");
            
            if ( $backupSetStatus == 1 and $bakDate > $lastFtpBackupTime ){
                $lastFtpBackupTime = $bakDate;
            }
        }
    }
    
    $ftp->close;

    return $lastFtpBackupTime;  
}

# @Description:  获取实例数据目录
# @Param: 
# @Return:  $dataDir
sub getInstanceDataDir {
    my ( $self,$host,$port,$dbType,$dbh ) = @_;
    
    my $log = Log::Log4perl->get_logger("");
    
    my $dataDir;
    my $cnf;
    if ( lc($dbType) =~ /mysql/ ){
        my $sql = "show variables like 'datadir'";
        my $res = $self->mysqlQuery($dbh,$sql);
        $log->debug("get \$res: $res");
        
        $dataDir = $res->{Value};
        
    }elsif ( lc($dbType) =~ /mongodb/ ){
        # 解析/etc/mongotab配置文件
        my $mongotab = `grep -v "#" /etc/mongotab |grep -w $port |head -1`;
        chomp($mongotab);
        
        # 去掉行首空格
        $mongotab =~ s/^\s+//g;
        
        # 获取配置文件
        my ( $baseDir,$cnf,$gPort,$instanceName,$isStart ) = (split(/\s+/, $mongotab));
        
        # 从配置文件获取实例数据目录
        open CNF,"$cnf" or die "can't open $cnf";
        foreach my $line (<CNF>){
            if ( $line =~ /^\s*#/ ){
                next;
            }
            
            if ( $line =~ /dbpath\s*=\s*([\d\D]+)/ or $line =~ /logpath\s*=\s*([\d\D]+?)\/mongos.log/){
                $dataDir = $1;
                chomp($dataDir);
                last;
            }
        }
        close CNF;
        
    }
    $log->debug("get \$dataDir: $dataDir");
    
    return $dataDir;
}

# @Description:  获取mysql实例数据目录
# @Param:  $dbh
# @Return:  $dataDir
sub getMysqlInstanceDataDir {
    my ( $self,$dbh ) = @_;
    
    my $log = Log::Log4perl->get_logger("");
    
    my $dataDir;
    
    my $sql = "show variables like 'datadir'";
    
    my $res = $self->mysqlQuery($dbh,$sql);
    $log->debug("get \$res: $res");
    
    $dataDir = $res->{Value};
        
    $log->debug("get \$dataDir: $dataDir");
    
    return $dataDir;
}

# @Description:  获取mongodb实例数据目录
# @Param:  $port
# @Return:  $dataDir
sub getMongoInstanceDataDir {
    my ( $self,$port ) = @_;
    
    my $log = Log::Log4perl->get_logger("");
    
    my $dataDir;

    # 解析/etc/mongotab配置文件
    my $mongotab = `grep -v "#" /etc/mongotab |grep -w $port |head -1`;
    chomp($mongotab);
    
    # 去掉行首空格
    $mongotab =~ s/^\s+//g;
    
    # 获取配置文件
    my ( $baseDir,$cnf,$gPort,$instanceName,$isStart ) = (split(/\s+/, $mongotab));
    
    # 从配置文件获取实例数据目录
    open CNF,"$cnf" or die "can't open $cnf";
    foreach my $line (<CNF>){
        if ( $line =~ /^\s*#/ ){
            next;
        }
        
        if ( $line =~ /dbpath\s*=\s*([\d\D]+)/ or $line =~ /logpath\s*=\s*([\d\D]+?)\/mongos.log/){
            $dataDir = $1;
            chomp($dataDir);
            last;
        }
    }
    close CNF;
        
    $log->debug("get \$dataDir: $dataDir");
    
    return $dataDir;
}

# @Description:  获取mongodb实例安装目录
# @Param:  $port
# @Return:  $baseDir
sub getMongoBaseDir {
    my ( $self,$port ) = @_;

    my $log = Log::Log4perl->get_logger("");
    
    # 解析/etc/mongotab配置文件
    my $mongotab = `grep -v "#" /etc/mongotab |grep -w $port |head -1`;
    chomp($mongotab);
    
    # 去掉行首空格
    $mongotab =~ s/^\s+//g;
    
    # 获取安装目录
    my ( $baseDir,$cnf,$gPort,$instanceName,$isStart ) = (split(/\s+/, $mongotab));
    chomp($baseDir);
    
    $log->debug("get \$baseDir: $baseDir");

    return $baseDir;
}

# @Description:  设置实例实例
# @Param:  $host,$port,$dbType,$dbh,$timeout
# @Return:  1:success  0:failed
sub setMysqlInstanceLock {
    my ( $self,$host,$port,$dbType,$dbh,$dataDir,$timeout ) = @_;

    my $log = Log::Log4perl->get_logger("");
    
    my $exitCode = 0;
    
    # 给mysql加全局锁
    my $result = $self->lockMysql($host,$port,$dbh,$timeout);
    $log->debug("get lockMysql() \$result: $result");
    $log->debug("get \$dbh: $dbh");

    if ( $result ){
        # 加锁成功
        if ( -f "/tmp/lock_mysql" ){
            system("cp -f /tmp/lock_mysql $dataDir/LVM_BINLOG_POS");
            $log->info("write binlog pos to LVM_BINLOG_POS file success");
            
            $exitCode = 1;
            
        }else{
            $log->error("mysql lock file: /tmp/lock_mysql not exist");
            $log->error("write binlog pos to LVM_BINLOG_POS file failed");
        }
    }

    return $exitCode;
}

# @Description:  删除实例锁
# @Param:  $host,$port,$dbh
# @Return:  1:success  0:failed
sub removeInstanceLock {
    my ( $self,$host,$port,$dbh ) = @_;
    
    my $log = Log::Log4perl->get_logger("");
    
    my $exitCode = 0;

    my ( $sessionIdStr,$sessionId );
    
    eval {
        open LOCK,"/tmp/lock_mysql" or die "can not open /tmp/lock_mysql";
        while (<LOCK>){
            chomp($_);
            $_ =~ s/^\s+//g;
            if ( $_ =~ m/^#/ ){
                next;   
            }
            if ( $_ =~ m/session_id/ ){
                my ( $sessionIdStr,$sessionId ) = split( /\s+/, $_ );
                chomp($sessionId);
                $log->info("get session_id from file: /tmp/lock_mysql");
                $log->info("get session_id: $sessionId");
            }
        }
        close LOCK;
    };
    if ($@){
        $log->error("get session_id from /tmp/lock_mysql failed");
    } else {
        my $sql = "KILL $sessionId";
        my $res = $self->mysqlExecute($dbh, $sql);
        if ( $res ){
            $log->info("kill session_id success");
            $exitCode = 1;
                
        }else{
            $log->error("kill session_id failed");
        }
    }

    if ( -f "/tmp/lock_mysql" ){
        system("rm -f /tmp/lock_mysql");
        $log->info("remove /tmp/lock_mysql success");
    }

    return $exitCode;
}

# @Description:  获取挂载点
# @Param:  $host,$port,$dbh,$timeout
# @Return:  $fs,$mp
sub getLvmFsMp {
    my ( $self,$host,$port,$dbType,$dataDir ) = @_;
    
    my $log = Log::Log4perl->get_logger("");

    my $exitCode = 0;
    
    my ( $fs,$mp );
    eval {
        if ( defined($dataDir) ){
            $log->info("get \$dataDir: $dataDir");
            
            my @dataDirArr = split(/\//,$dataDir);
            $log->info($dataDirArr[1]);
            
            open DF,"df -P|" or die "can not run command: df -P";
            while (<DF>){
                my @row = split( /\s+/, $_ );
              
                my $tmpMp = $row[5];
              
                my @tmpMpArr = split(/\//,$tmpMp);
              
                if ( defined($dataDirArr[1] ) && defined($tmpMpArr[1]) && $dataDirArr[1] eq $tmpMpArr[1] ){
                    
                    if ( defined($mp) and length($mp) < length($tmpMpArr[1]) ){
                        ( $fs,$mp ) = ( $row[0],$tmpMpArr[1]) ;
                    }else{
                        ( $fs,$mp ) = ( $row[0],$row[5] );
                        }
                    }
                }
            close DF;
            $log->info("get filesystem: $fs, mount point: $mp");
            
            open LVDSP,"lvdisplay $fs|" or die "can not run command: lvdisplay";
            while ( <LVDSP> ){
                if ( $_ =~ /LV Path/ ){
                    last;
                } elsif ( $_ =~ /LV Name\s+([\d\D]+?)$/ ){
                    $fs = $1;
                    $log->info("change Lv Name to $fs");
                }
            }
            close LVDSP;
        }else{
            $log->error("get instance dataDir failed");
        }
    };
    if ($@){
        $log->error("get lvm logical volumn failed, error msg: $@");
    }
    
    return ( $fs,$mp );
}

# @Description:  获取lvm version
# @Param:  $fs,$mp
# @Return:   $lvmVersion,$exitCode
sub getLvmVersion {
    my ( $self ) = @_;
    
    my $log = Log::Log4perl->get_logger("");
    
    my $exitCode = 0;
    
    my $lvmVersion;
    eval {
        open(LVM,"lvs --version|") || die "run lvs --version failed";
        while (<LVM>){
            if ( $_ =~ /LVM\s+version\s*:\s*([\d\D]+)/ ){
                $lvmVersion = $1;
                chomp($lvmVersion);
                last;
            }
        }
        $log->info("get lvm version: $lvmVersion");
    };
    if ($@){
        $log->error("get lvm version failed, error msg: $@");
    } else {
        $exitCode = 1;
        $log->info("get lvm version success");
    }
    
    return ( $lvmVersion,$exitCode );
}

# @Description:  创建lvm快照
# @Param:  $fs,$mp
# @Return:   $lvPath,$lvName,$exitCode
#            成功: $exitCode为1  失败: $exitCode为0
sub createLvmSnapshot {
    my ( $self,$fs,$mp ) = @_;
    
    my $log = Log::Log4perl->get_logger("");
    
    my $exitCode = 0;
    my $lvPath = "";
    my $lvName = "";

    my $time = $self->getCurrentDatetime();
    
    $log->debug("get \$fs: $fs");
    $log->debug("get \$mp: $mp");
    
    eval {
        my $cmd = "lvcreate -l 100%FREE -s -n dbbackup${time} $fs 2>&1 > /dev/null";
        $log->debug("lvcreate -l 100%FREE -s -n dbbackup${time} $fs 2>&1 > /dev/null");
        
        # 创建lvm快照
        my $result = $self->runCommand($cmd);
        
        if ( defined($result) ){
            $exitCode = 1;
            
            open LVDISPLAY,"lvdisplay|" or die "can not run command: lvdisplay";
            while (<LVDISPLAY>){
                chomp($_);
                $_ =~ s/^\s+//g;
                if ( $_ =~ /LV\s+Path\s+/ and $_ =~ /dbbackup/ ){
                    # 获取lvpath
                    if ( $_ =~ /LV\s+Path\s+([\d\D]+?)\s*$/ ){
                        $lvPath = $1;
                        $log->debug("get \$lvPath: $lvPath");
                    }
                } elsif ( $_ =~ /LV\s+Name\s+/ and $_ =~ /dbbackup/ ){
                    # 获取lvname
                    if ( $_ =~ /LV\s+Name\s+([\d\D]+?)\s*$/ ){
                        $lvName = $1;
                        $log->debug("get \$lvName: $lvName");
                        
                        last;
                    }
                }
            }
            close LVDISPLAY;
        }
    };
    if ($@){
        $log->error("create lvm snapshot failed");
    }      
    
    return ( $lvPath,$lvName,$exitCode );
}

# @Description:  删除lvm快照
# @Param:  $mountPoint,$lvPath
# @Return:   成功:1  失败:0
sub removeLvmSnapshot {
    my ( $self,$mountPoint,$lvPath ) = @_;

    my $log = Log::Log4perl->get_logger("");

    my $exitCode = 0;
    
    # 卸载目录
    my $isUmounted = $self->runCommandReturnCode("umount $mountPoint");
    $log->debug("removeLvmSnapshot get \$mountPoint: $mountPoint");
    $log->debug("removeLvmSnapshot get \$isUmounted: $isUmounted");
    
    # 删除快照
    my $isLvremoved = $self->runCommandReturnCode("lvremove -f $lvPath 2>&1 >/dev/null");
    $log->debug("removeLvmSnapshot get lvremove \$isLvremoved: $isLvremoved");
    
    # 检查删除情况
    my $num = `lvdisplay |grep -wi "LV Path" |grep $lvPath |wc -l`;
    chomp($num);
    if ( $num == 0 ){
        $log->info("remove lvm snapshot: $lvPath success");
    }else{
        # 重新删除快照
        sleep 5;
        $log->error("remove lvm snapshot: $lvPath failed, retry remove now");
        $self->runCommandReturnCode("lvremove -f $lvPath 2>&1 >/dev/null");
    }
            
    $exitCode = 1;

    return $exitCode;
}

# @Description:  锁定MySQL,记录同步点信息
# @Param:  $host,$port,$dbh,$timeout
# @Return:  1:success  0:failed
sub lockMysql {
    my ( $self,$host,$port,$dbh,$timeout ) = @_;

    my $log = Log::Log4perl->get_logger("");
    
    my $exitCode = 0;
    
    my ( $masterHost,$masterPort,$masterLogFile,$masterLogPos,$slaveLogFile,$slaveLogPos );
    
    if ( ! $timeout ){
        $timeout = 300;
    }
    
    my $pid = fork();
    if ( !defined($pid) ){
        $log->error("run command fork() failed");
    }
    
    if ( $pid == 0 ){
        # 子进程创建锁
        eval {
            alarm($timeout);
            if ( -f "/tmp/lock_mysql" ){
                system("rm -f /tmp/lock_mysql");
            }
            
            $self->mysqlExecute($dbh,"FLUSH TABLES WITH READ LOCK");

            # 获取session会话
            my @row = $self->mysqlQueryOneArray($dbh,"select connection_id()");
            
            my $sessionId = $row[0];
            $log->debug("get \$sessionId: $sessionId");
            
            if ( defined($sessionId) ){
                
                # 获取节点show master status信息
                my $masterStatus = $self->mysqlQuery($dbh,"show master status");
            
                $masterStatus = { map { lc($_) => $masterStatus->{$_} } keys %{$masterStatus} };  # lowercase the keys
                
                $masterLogFile = defined($masterStatus->{file}) ? $masterStatus->{file}:"";
                $masterLogPos = defined($masterStatus->{position}) ? $masterStatus->{position}:"";

                # 获取节点show slave status信息
                my $slaveStatus = $self->mysqlQuery($dbh,"show slave status");
                
                $slaveStatus = { map { lc($_) => $slaveStatus->{$_} } keys %{$slaveStatus} };  # lowercase the keys
                
                $masterHost = defined($slaveStatus->{master_host}) ? $slaveStatus->{master_host}:"NULL";
                $masterPort = defined($slaveStatus->{master_port}) ? $slaveStatus->{master_port}:"NULL";
                
                $slaveLogFile = defined($slaveStatus->{relay_master_log_file}) ? $slaveStatus->{relay_master_log_file}:"NULL";
                $slaveLogPos = defined($slaveStatus->{exec_master_log_pos}) ? $slaveStatus->{exec_master_log_pos}:"NULL";
                
                # 打印同步点
                $log->info("[session_id]: $sessionId");
                $log->info("[show slave status]: master_host: $masterHost, master_port: $masterPort");
                $log->info("[show slave status]: relay_master_log_file: $slaveLogFile, exec_master_log_pos: $slaveLogPos");
                $log->info("[show master status]: file: $masterLogFile, position: $masterLogPos");
                
                # 创建锁
                open LOCK,">/tmp/lock_mysql" or die "can not access /tmp/lock_mysql";
                
                # 记录同步点到文件
                print LOCK "session_id:".$sessionId."\n";
                print LOCK "master_host:".$masterHost."\n";
                print LOCK "master_port:".$masterPort."\n";
                print LOCK "file:".$masterLogFile."\n";
                print LOCK "position:".$masterLogPos."\n";
                print LOCK "relay_master_log_file:".$slaveLogFile."\n";
                print LOCK "exec_master_log_pos:".$slaveLogPos."\n";

                close LOCK;
                
                # 检查锁
                my $waitTimes = 10;
                while ( 1==1 ){
                    if ( -e "/tmp/lock_mysql" ){
                        $log->info("child process get mysql lock file success");
                        last;
                    }
                    
                    $log->error("child process get mysql lock file failed, wait and check again");
                    
                    $waitTimes--;
                    if ( $waitTimes < 0 ){
                        die "wait mysql lock timeout";
                    }
                    sleep 5;
                }
            }
            alarm(0);
        };
        if ( $@ ){
            system("rm -f /tmp/lock_mysql");
            $log->error("child process lock mysql failed, error msg: $@"); 

        }
        exit 0;
    }else{
        # 等待子进程
        waitpid($pid,0);
        
        # 父进程检查锁获取情况
        for ( my $retry=0;$retry<5;$retry++ ){
            if ( -e "/tmp/lock_mysql" ){
                $log->info("parent process check mysql lock file success");
                $exitCode = 1;
                
                last;
            }else{
                $log->error("parent process check mysql lock file failed");
                $log->error("mysql lock:/tmp/lock_mysql has not been created, parent process wait and retry");
            }
            $log->info("parent process sleep 10s, and then retry");
                
            sleep 10;
        }
        
        return $exitCode;
    }
}

# @Description:  rsync传输备份集
# @Param:  $host,$port,$dbh,$timeout
# @Return:  1:success  0:failed
sub rsyncBackupset {
    my ( $self,$source,$target,$speed,$mountPoint,$lvPath,$lvName ) = @_;
    
    my $log = Log::Log4perl->get_logger("");    

    my $exitCode = 0;
    
    my $childMask = int(rand(999999));
    my $rsyncThreadPid;
    
    if ( fork() == 0 ){
        eval{
            system("mkdir -p $target");
            
            open(CHL,">/tmp/lvm_rsync_$childMask") or die "open /tmp/lvm_rsync_$childMask failed";
            # 保存进程号到文件
            print CHL $$;
            
            # rsync命令
            my $cmd = "rsync -av $source $target --bwlimit=$speed";
            $log->info("rsync command: $cmd");
            
            # 执行rsync传输
            my $result = `$cmd`;
            
            if ( $result =~ /error/ ){
                print CHL " rsync error\n";
            }else{
                print CHL " rsync ok\n";
            }
            close CHL;

            $log->info("rsync finish $result");
        };
        if ( $@ ){
            $log->error("rsync error, error msg: $@");
            undef $@;
        }
        exit 0;
    }
    
    # 检查快照占用空间, kill rsync: pkill -P PID
    while ( 1==1 ){
        $log->debug("sleep 60s now");
        sleep 60;
        
        my $isSnapshotOk = $self->checkSnapshotFreeSize($lvPath,$lvName);
        $log->debug("get \$isSnapshotOk: $isSnapshotOk");

        open(CHL,"</tmp/lvm_rsync_$childMask") or die "open /tmp/lvm_rsync_$childMask failed";
        while (<CHL>){
            if ( $_ =~ /(\d+)/ ){
                $rsyncThreadPid = $1;
            }

            if ( $_ =~ /rsync ok/ ){
                $log->info("rsync $source to $target success");
                $exitCode = 1;
                last;
            } elsif ( $_ =~ /rsync error/ ){
                $log->error("rsync $source to $target error");
                $exitCode = 0;
                last;
            }
        }
        close CHL;
        
        if ( $isSnapshotOk == 0 ){
            $log->info("not enough free size in lv snapshot");
            system("pkill -P $rsyncThreadPid");      
            last;
        }

        if ( $exitCode == 1 ){
            $log->info("rsync $source to $target success");
            last; 
        }
    }
    
    $log->info("rsync finish");

    return $exitCode;
}

# @Description:  检查快照剩余大小
# @Param: 
# @Return:  1:success  0:failed
sub checkSnapshotFreeSize {
    my ( $self,$lvPath,$lvName ) = @_;
    
    my $log = Log::Log4perl->get_logger("");    

    my $exitCode = 0;

    eval {
        defined($lvPath) or die "snapshot not created, please create it first";

        open(LV,"lvdisplay $lvPath|") or die "can not get lv path";
        while (<LV>){
            if ( $_ =~ /Allocated to snapshot\s+([\d\D]+?)%/ ){
                if ( $1 < 90 ){
                    $log->info("snapshot $lvPath used ${1}%");
                    
                    $exitCode = 1;
                }else{
                    $log->error("snapshot $lvPath used > 90%");
                    $log->error("snapshot $lvPath used ${1}%");
                }
            }
        }
        close LV;
    };
    if ($@){
        $log->error("check snapshot free size failed, error msg: $@");
    }

    return $exitCode;
}

# @Description:  检查快照剩余大小
# @Param: 
# @Return:  1:success  0:failed
sub getDiskfreeSize {
    my ( $self,$mountDir,$lvPath,$lvName ) = @_;
    
    my $log = Log::Log4perl->get_logger("");    

    my $exitCode = 0;

    my %diskfree;    
    my $cmd = "df -P|awk '{print \$4,\$6}'";
    eval {
        open CMD,"$cmd|" or die "can not run command: $cmd";

        while (<CMD>){
            if ( $_ =~ /^(\d+)\s+([\d\D]+?)$/ ){
                $diskfree{$2} = $1;
                $log->debug("$2     $1");
            }elsif ( $_ =~ /^Available\s+Mounted/ ){
                next;
            }else{
                $log->error("command: $cmd result format wrong");
                last;
            }
        }
        close CMD;
    };
    if ($@){
        $log->error("Load diskfree size fail ,$@");
    }

    return $exitCode;
}

# @Description:  获取目录对应的文件系统类型
# @Param:  $dir
# @Return:  $filesystemType           
sub getFilesystemType {
    my ( $self,$dir ) = @_;
    
    my $log = Log::Log4perl->get_logger("");    
    
    my $filesystemType;  
    my $mountPoint;
    
    eval{
        open DF,"df -PT|" or die "can not run command: df -PT";
        foreach my $line (<DF>){
            my @row = split( /\s+/,$line );
            my $tmpMp = $row[6];
            if ( $dir =~ /$tmpMp/ ){
                if ( defined($mountPoint) and length($mountPoint) < length($tmpMp) ){
                    ( $filesystemType,$mountPoint ) = ( $row[1],$tmpMp );
                }else{
                    ( $filesystemType,$mountPoint ) = ( $row[1],$row[6] );
                }
            }
        }
        close DF;
        
        if ( defined($filesystemType) and length($filesystemType) > 0 ){
            chomp($filesystemType);
            $log->info("get dir: $dir filesytem type: $filesystemType");
        }
    };
    if ($@){
        $log->error("get dir: $dir filesystem type failed, error msg: $@");
    }
    
    return $filesystemType;
}

# @Description:  挂载快照
# @Param:  $host,$port,$dbType,$filesystemType,$lvPath,$lvName
# @Return:  $mountPoint,$exitCode
#         1:成功  0:失败
sub mountSnapshot {
    my ( $self,$host,$port,$dbType,$filesystemType,$lvPath,$lvName ) = @_;

    my $log = Log::Log4perl->get_logger("");      

    my $exitCode = 0;
    
    # 挂载点
    my $mountPoint = "/tmp/${dbType}_$port";
    
    $log->debug("mountSnapshot get \$mountPoint: $mountPoint");
    
    eval {
        if ( -e $mountPoint ){
            # 清理挂载点目录
            rmdir "$mountPoint";
        }

        # 创建挂载点目录;
        $self->runCommand("mkdir -p $mountPoint");
        $log->debug("mkdir -p $mountPoint");
        
        # 挂载分区
        $self->runCommand("mount -t $filesystemType $lvPath $mountPoint");
        $log->debug("mount -t $filesystemType $lvPath $mountPoint");

        open(DF,"df -P|") || die "can not run command: df -P";
        foreach my $line (<DF>){
            my @row = split( /\s+/,$line );
            if ( $row[5] eq "$mountPoint" ){
                open LV,"lvdisplay $row[0]|";
                while (<LV>){
                    if ( $_ =~ /LV Name[\d\D]+?(dbbackup[\d]+)$/ ){
                        my $temp = $1;
                        chomp($temp);
                        if ( $lvName =~ /$temp/ ){
                            $log->info("mount snapshot success");
                            
                            $exitCode = 1;
                        }
                    }
                }
                close LV;
            }
        }
        close DF;
    };
    if ($@){
        $log->error("mount snapshot failed, error msg: $@");
    }

    return ( $mountPoint,$exitCode );
}

# @Description:  检查mfsmount命令
# @Param:  
# @Return:  成功:1  失败:0
sub checkMfsmount {
    my ( $self ) = @_;
    
    my $log = Log::Log4perl->get_logger("");
    
    my $exitCode = 0;
    
    # mfsmount命令
    my $mfsmountCmd = "/usr/bin/mfsmount";

    eval {
        # 检查mfsmount命令
        if ( -e $mfsmountCmd ){
            my $mfsVersion = `$mfsmountCmd --version 2>&1`;
            if ( $? == 0 ){
                $exitCode = 1;
                
                $log->info("mfsmount command is ok");
            }
        }else{
            $log->error("mfsmount command: $mfsmountCmd is not available, please install");    
        }       
    };
    if ($@){
        $log->error("check mfsmount command: $mfsmountCmd failed, error msg: $@");
        undef $@;
    }

    return $exitCode;
}

# @Description:  挂载mfs分区
# @Param:  
# @Return:  成功:1  失败:0
sub mountMfs {
    my ( $self,$host,$port,$filerDir,$fileDir ) = @_;
    
    my $log = Log::Log4perl->get_logger("");

    my $isMounted = 0;  # 是否已挂载
    my $isCanMounted = 0;   # 能否挂载
    
    # 创建备份集对象
    my $backupset = $self->{_MYSQL_OBJ}->{_BACKUPSET};
    
    my $bakDir = "/home/mysql/backup_stage/${host}_${port}";
    my $mfsmountCmd = "/usr/bin/mfsmount";

    eval {
        if ( -e $bakDir ){
            # 检查备份目录挂载情况
            $log->info("check directory: $bakDir is mounted or not");

            open MOUNT,"mount|awk '{print \$3}' |" or die "list mounted failed";
            while (<MOUNT>){
                my $dir = $_;
                chomp($dir);
                if ( $dir eq $bakDir ){
                    # 备份目录已挂载
                    $log->info("bakDir: $bakDir is mounted");
                    
                    # 卸载备份目录
                    system("umount $bakDir");
                    if ( $? != 0 ){
                        $log->error("umount bakDir: $bakDir failed");
                    }else{
                        $isCanMounted = 1;
                        
                        $log->info("umount bakDir: $bakDir success");
                    }
                    
                    last;
                }
            }
            close MOUNT;
        }else{
            # 备份目录不存在, 创建备份目录
            system("mkdir -p $bakDir");
            if ( $? != 0 ){
                $log->error("create bakDir: $bakDir failed");
            }else{
                $isCanMounted = 1;
                
                $log->info("create bakDir: $bakDir success");
            }
        }
        
        # 挂载备份目录
        if ( $isCanMounted == 1 ){
            # 备份能挂载情况
            my ( $mfsServer,$mfsDir );
            
            # 从filerDir获取mfsServer和mfsDir
            $log->info("get mfsServer and mfsDir from \$filerDir");
            
            if ( $filerDir =~ /mfs:([\d\.]+?):([\d\D]+)$/ ){
                ( $mfsServer,$mfsDir ) = ($1,$2);
                
                $log->info("get mfs server: $mfsServer, mfs dir: $mfsDir");
                
                my $mountCmd = "$mfsmount $bakDir -H $mfsServer -S $mfsDir -o nonempty -o mfscachemode=AUTO 2>&1";
                $log->debug("$mountCmd");
                
                # 挂载备份目录
                my $mountResult = `$mountCmd`;
                if ( $? != 0 ){
                    $log->error("mount mfs dir failed,  result is $mountResult");
                }else{
                    $isMounted = 1;
                    $log->info("mount mfs dir success, result is $mountResult");
                }
                
                # 获取并打印/etc/mtab信息
                open MTAB,"/etc/mtab" or warn "open /etc/mtab failed";
                while(<MTAB>){
                    $log->debug("get /etc/mtab: $_");
                }
                close MTAB;
            }else{
                $log->error("can not get mfs server and mfs dir");
            }
        }
    };
    if ($@){
        $log->error("mount mfs dir failed, error msg:$@");
        undef $@;
    }
    
    return $isMounted;
}

# @Description:  卸载mfs分区
# @Param:  
# @Return:  成功:1  失败:0
sub umountMfs {
    my ( $self,$host,$port,$dbType ) = @_;

    my $log = Log::Log4perl->get_logger("");
    
    my $exitCode = 0;

    my $bakDir = "/home/${dbType}/backup_stage/${host}_${port}";

    # 卸载备份目录
    system("umount $bakDir");
    if ( $? != 0 ){
        $log->error("umount $bakDir failed");
    }else{
        $exitCode = 1;
        
        $log->info("umount $bakDir success");
    }
    
    return $exitCode;
}

# @Description:  获取备份集信息
# @Param:  $host,$port
# @Return:  $backupset or undef
sub getBackupSet {
    my ( $self,$host,$port,$dbType,$bakType ) = @_;

    my $log = Log::Log4perl->get_logger("");

    my $exitCode = 0;

    my $baseDir = "/home/${dbType}/backup_stage";

    # 获取备份资料库数据库连接参数
    my ($repoHost,$repoPort,$repoUser,$repoPass,$repoDb) = $self->getRepoInfo();

    # 连接备份资料库
    my $dbh = $self->mysqlConnect($repoHost,$repoPort,$repoDb,$repoUser,$repoPass);
    if ( !$dbh ){
        $log->error("connect to $repoHost:$repoPort failed");

        # 连接mysql异常，返回undef
        return undef;
    }
    $log->info("connect to $repoHost:$repoPort success");

    my $backupsetDir;
    my $bakType;
    my $backupTime;
    my $isCompressed;
    my $isEncrypted;
    my $masterLogFile;
    my $masterLogPos;
    
    eval {
        # 获取备份集信息
        my $sql = "select bak_type,filer_dir,file_dir,is_compressed,is_encrypted,
            master_log_file,master_log_pos,end_time from backup_info 
            where ip='$host' and port=$port and bak_type='$bakType'  
            and status=1 order by end_time desc limit 1";
        $log->debug("$sql");

        # 执行查询
        my $backupset = $self->mysqlQuery($dbh,$sql);
        if ( defined($backupset) ){
            $backupsetDir = "$baseDir/$backupset->{file_dir}";
            $backupset->{bak_dir} = $backupsetDir;
            $bakType = $backupset->{bak_type};
            $backupTime = $backupset->{end_time};
            $isCompressed = $backupset->{is_compressed};
            $isEncrypted = $backupset->{is_encrypted};
            $masterLogFile = $backupset->{master_log_file};
            $masterLogPos = $backupset->{master_log_pos};
            
            $log->debug("get \$backupsetDir=$backupsetDir, \$bakType=$bakType");
            $log->debug("get \$backupTime=$backupTime, \$isCompressed=$isCompressed, \$isEncrypted=$isEncrypted");
            $log->debug("get \$masterLogFile=$masterLogFile, \$masterLogPos=$masterLogPos");
            
            # 检查备份集有效性
            my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blockes) = stat($backupsetDir);
            if ( defined($size) and $size > 4096 ){
                $exitCode = 1;
                
                # size加入backupset对象
                $backupset->{size} = $size;
                
                $log->info("backupset: $backupsetDir is available, size=$size");
            }else{
                $log->error("backupset: $backupsetDir is not available, real size is too small");
            }
        }else{
            $log->error("backupset not found");
        }
    };
    if ($@){
        $log->error("get backupset error, error msg: $@");
        undef $@;
    }
    
    if ( $exitCode == 1 ){
        
        return $backupset;
    }else{
        
        return undef;
    }
}

# @Description:  获取备份集mycnf配置文件
# @Param:  $bakDir
# @Return:  $mycnf or undef
sub getBackupsetMycnf {
    my ( $self,$bakDir ) = @_;

    my $log = Log::Log4perl->get_logger("");
    
    my $exitCode = 0;
    
    # mycnf配置文件
    my $mycnf;
    
    eval {
        if (opendir(BAKDIR,"$bakDir")){
            my @file = grep { !/^\./ && /\d*_[\d\D]+\.cnf/} readdir BAKDIR;
            $log->info("get mysql config file: @file");
            close BAKDIR;
            
            if ( $#file > 1 ){
                $log->error("mysql config file has more than one, @file");
            }else{
                $exitCode = 1;
                $log->info("mysql config file @file");
                
                $mycnf = "$bakDir/$file[0]";
            }
        }else{
            $log->error("can not open bakDir: $bakDir");
        }
    };
    if ($@){
        $log->error("get mysql config file from backupset error, error msg: $@");
        undef $@;        
    }
    
    # 返回值
    if ( $exitCode == 1 ){
        
        return $mycnf;
    }else{
        
        return undef;
    }
}

# @Description:  获取备份集backup-my.cnf文件
# @Param:  $bakDir
# @Return:  $backupMycnf or undef
sub getBackupsetBackupMycnf {
    my ( $self,$bakDir ) = @_;

    my $log = Log::Log4perl->get_logger("");
    
    my $exitCode = 0;
    
    my $backupMycnf;
    
    # 获取backup-my.cnf文件
    eval {
        if ( -e "$bakDir/backup-my.cnf" ){
            $exitCode = 1;
            $backupMycnf = "$bakDir/backup-my.cnf";
            
            $log->info("get backup-my.cnf file success");
        }else{
            $log->error("backup-my.cnf file not exist");
        }
    };
    if ($@){
        $log->error("get $bakDir/backup-my.cnf error,error msg: $@");
        undef $@;
    }

    # 返回值
    if ( $exitCode == 1 ){
        
        return $backupMycnf;
    }else{
        
        return undef;
    }
}

# @Description:  拷贝数据到目标目录
# @Param:  $host,$port,$targetDir,$speed
# @Return:  1:成功  0:失败
sub copyToTargetDir {
    my ( $self,$host,$port,$targetDir,$speed ) = @_;

    my $log = Log::Log4perl->get_logger("");

    my $exitCode = 0;
    
    if ( !defined($speed) ){
        $speed = 1000 * 1024;
    }
    
    my $baseDir = "/home/mysql/backup_stage";
    my $bakDir = "$baseDir/${host}_${port}";
    my $sourceDir = "$bakDir/$backupsetDir/";   
    if ( $sourceDir =~ /([\d_\.]+tar\.enc)/ ){
        $sourceDir = substr($sourceDir,0,index($sourceDir,$1));
    }
    
    my $cmd = "rsync -av $sourceDir $targetDir --bwlimit=$speed";
    $log->debug("get \$cmd: $cmd");
    
    # 创建目标目录
    system("mkdir -p $targetDir");

    $log->info("copy backupset to dir: $targetDir");
    
    # 传输数据
    my $rsyncInfo = `$cmd`;
    if ( $? != 0 ){
        $log->error("copy backupset to target dir: $targetDir failed");
        $log->error("need manual remove target dir: $targetDir");
    }else{
        $exitCode = 1;
        
        $log->info("copy backupset to target dir: $targetDir success");
    }

    return $exitCode;
}

# @Description:  xtrabackup备份数据应用重做日志
# @Param:  $innobackupex,$dataDir,$cnfFile
# @Return:  1:成功 0:失败
sub recover {
    my ( $self,$dataDir,$backupMycnf ) = @_;

    my $log = Log::Log4perl->get_logger("");
    
    my $exitCode = 0;
    
    my $cmd = "/usr/bin/innobackupex --defaults-file=$backupMycnf --apply-log $dataDir 2>&1";
    $log->debug("$cmd");

    eval {
        open RECOVER,"$cmd |" or die "run command: $cmd failed";
        while(<RECOVER>){
            $log->info($_);
        }
        close RECOVER;
        if ( $? == 0 ){
            $exitCode = 1;
            
            system("chown -R mysql.mysql $dataDir");
            $log->info("backupset apply log success");
        }else{
            $log->error("backupset apply log failed");
        }
    };
    if ($@){
        $log->error("recover backupset error, error msg: $@");
        undef $@;
    }

    return $exitCode;
}

# @Description:  获取备份加密秘钥
# @Param:  $backupSet,$encryptPass,$outputDir
# @Return:  $encKey or undef
sub getEncryptKey {
    my ( $self,$host,$port,$startTime ) = @_;

    my $log = Log::Log4perl->get_logger("");
    
    # 备份加密秘钥
    my $encKey;

    # 获取备份资料库数据库连接参数
    my ($repoHost,$repoPort,$repoUser,$repoPass,$repoDb) = $self->getRepoInfo();

    # 连接备份资料库
    my $dbh = $self->mysqlConnect($repoHost,$repoPort,$repoDb,$repoUser,$repoPass);
    if ( !$dbh ){
        $log->error("connect to $repoHost:$repoPort failed");

        # 连接mysql异常，返回undef
        return undef;
    }
    $log->info("connect to $repoHost:$repoPort success");
    
    my $sql = "select enc_key from backup_key where ip='$host' and port=$port and backup_start_time='$startTime'";
    $log->debug("$sql");

    # 执行查询
    my $row = $self->mysqlQuery($dbh,$sql);
    if ( defined($row) ){
        $encKey = $row->{enc_key};
        chomp($encKey);
    }
    
    # 返回值
    if ( defined($encKey) and $encKey ne "" ){
        $log->info("get encrypt key success");
        $log->debug("get \$encKey: $encKey");
        
        return $encKey;
    }else{
        $log->error("get encrypt key failed");
        
        return undef;
    }
}

# @Description:  解密备份集
# @Param:  $backupSet,$encryptPass,$outputDir
# @Return:  1:成功  0:失败
sub decryptBackupSet {
    my ( $self,$backupSet,$decKey,$outputDir ) = @_;

    my $log = Log::Log4perl->get_logger("");
    
    my $exitCode = 0;
 
    my $baseDir = "/home/mysql/backup_stage/${host}_${port}";

    # 获取备份资料库数据库连接参数
    my ($repoHost,$repoPort,$repoUser,$repoPass,$repoDb) = $self->getRepoInfo();

    # 连接备份资料库
    my $dbh = $self->mysqlConnect($repoHost,$repoPort,$repoDb,$repoUser,$repoPass);
    if ( !$dbh ){
        $log->error("connect to $repoHost:$repoPort failed");

        # 连接mysql异常，返回undef
        return undef;
    }
    $log->info("connect to $repoHost:$repoPort success");

    my ( $file,$bak_time ) = ($self->{_BACKUPSET_DIRECTORY},$self->{_BACKUP_TIME});

    my $bakFile;
    if ( $file =~ /.tar.enc/i ){
        $bakFile = "$baseDir/$file";
    }else{
        my @bakdirInfo = split(/\//,$file);
        $bakFile = "$baseDir/$file/$bakdirInfo[1]" . ".tar.enc";
    }

    if ( -e $outputDir ){
        my $decryptResult = $self->decrypt($backupSet,$decKey,$outputDir);
        if ( $decryptResult == 1 ){
            $exitCode = 1;

            $log->info("decrypt file: $file to dir: $outputDir success");
        }else{
            $log->error("decrypt file: $file to dir: $outputDir failed");
        }
    }else{
        $log->error("outputDir: $outputDir is not exist");
    }
    
    return $exitCode;
}

# @Description:  解密方法
# @Param:  $backupSet,$encryptPass,$outputDir
# @Return:  1:成功  0:失败
sub decryptBackupSet {
    my ( $self,$backupSet,$encKey,$outputDir ) = @_;

    my $log = Log::Log4perl->get_logger("");
    
    my $exitCode = 0;
    
    # 解密命令
    my $cmd = "dd if=$backupSet | openssl rc4 -d -pass pass:$encKey | tar zxf - -C $outputDir";
    eval{
        open CMD,"$cmd |" or die "run command: $cmd failed";
        while(<CMD>){
            $log->info("decrypt : $_");
        }
        close CMD;
        if ( $? == 0 ){
            $exitCode = 1;
            
            $log->info("decrypt backupset success");
        }else{
            $log->error("decrypt backupset failed");
        }
    };
    if ( $@ ){
        $log->error("decrypt backupset error, error msg: $@");
        undef $@;
    }
    
    return $exitCode;
}

# @Description:  解压
# @Param:  $backupSet,$outputDir
# @Return:  1:成功 0:失败
sub decompress {
    my ( $self,$backupSet,$outputDir ) = @_;

    my $log = Log::Log4perl->get_logger("");
    
    my $exitCode = 0;
    
    # 解压命令
    my $cmd = "dd if=$backupSet | tar zxf - -C $outputDir";
    eval{
        open CMD,"$cmd |" or die "run command: $cmd failed";
        while(<CMD>){
            $log->info("decompress: $_");
        }
        close CMD;
        if ( $? == 0 ){
            $exitCode = 1;
            
            $log->info("decompress backupset success");
        }else{
            $log->error("decompress backupset failed");
        }
    };
    if ( $@ ){
        $log->error("decompress backupset error, error msg: $@");
        undef $@;
    }

    return $exitCode;
}

# @Description:  创建mycnf配置文件
# @Param: 
# @Return:
sub createMycnf {
    my ( $self,$host,$port,$memSize,$dataDir,$mycnfTemplate,$backupMycnf,$otherVariables ) = @_;
    
    my $log = Log::Log4perl->get_logger("");
    
    my $exitCode = 0;
    
    # 生成server_id值
    my $serverId = int(rand(1000)*rand(10000));

    eval {
        # mycnf可变参数
        my %baseCnf = (
            server-id => $serverId,
            port => $port,
            datadir => $dataDir,
            innodb_data_home_dir => $dataDir,
            innodb_log_group_home_dir => $dataDir,
            tmpdir => $dataDir,
            character-set-server => "utf8",
            collation-server => "utf8_bin"
        );
        
        # 从备份集backup-my.cnf获取innodb参数值
        open BACKUPMYCNF,"$backupMycnf" or die "can not open $backupMycnf";
        while(<BACKUPMYCNF>){
            if ( $_ =~ /^\s*#/ ){
                next;
            }
            if ( $_ =~ /innodb_log_files_in_groups\s*=\s*([\d\D]+?)$/i ){
                $baseCnf{innodb_log_files_in_groups} = $1;
                chomp($baseCnf{innodb_log_files_in_groups});
                next;
            }elsif( $_ =~ /innodb_log_file_size\s*=\s*([\d\D]+?)$/i ){
                $baseCnf{innodb_log_file_size} = $1;
                chomp($baseCnf{innodb_log_file_size});
                next;
                
            }elsif( $_ =~ /character-set-server\s*=\s*([\w]+?)$/i ){
                $baseCnf{character-set-server} = $1;
                chomp($baseCnf{character-set-server});
                next;
                
            }elsif( $_ =~ /collation-server\s*=\s*([\w_]+?)$/i ){
                $baseCnf{collation-server} = $1;
                chomp($baseCnf{collation-server});
                next;
                
            }elsif( $_ =~ /^\s*local_infile\s*$/ ){
                $baseCnf{local_infile} = "";
                chomp($baseCnf{local_infile});
                next;
                
            }elsif( $_ =~ /innodb_data_file_path\s*=\s*([\d\D]+?)$/i ){
                $baseCnf{innodb_data_file_path} = $1;
                chomp($baseCnf{innodb_data_file_path});
                next;
                
            }elsif( $_ =~ /innodb_page_size\s*=\s*([\d\D]+?)$/i ){
                $baseCnf{innodb_page_size} = $1;
                chomp($baseCnf{innodb_page_size});
                next;
            }
        }
        close BACKUPMYCNF;
        
        # 检查获取到的backup-my.cnf数据
        my @mycnfKey = keys %baseCnf;
        if ( $#mycnfKey < 1 ){
            $log->error("get backupset backup-my.cnf failed");
        }else{
            if ( -e $configFile ){
                # 生成随机数
                my $suffix = int(rand(10000)*rand(10000));
                
                # 修改配置文件名称
                rename($configFile,"$configFile.$suffix");
                $log->info("$configFile exist, rename to ${configFile}.$suffix success");
            }

            open CONF,">$configFile" or die "can not write to mysql config file, $configFile";
            
            # 根据模板创建my.cnf配置文件
            open TEMPLATE,"$mycnfTemplate" or die "Can not open template config file, $template_file";
            while(<TEMPLATE>){
                if ( $_ =~ /^\s*([\d\D]+?=\s*)\[_MEMSIZE\]/ ){
                    # 配置innodb buffer pool size
                    my $innodbBufferPoolSize = int($memSize/2/(10**(length($memSize) - 1))+0.9) * (10**(length($memSize) - 1) / 1000000);
                    
                    $log->info("get memory size: $memSize,innodb buffer pool size: $innodbBufferPoolSize");
                    print CONF "$1 ${innodbBufferPoolSize}G\n";

                    $log->info("write $1 ${innodbBufferPoolSize}G to my.cnf success");
                    
                } elsif ( $_ =~ /^\s*([-\w_]+)\s*/i ){
                    my $variable = $1;
                    if ( defined($variable) ){
                        chomp($variable)
                    }
                    
                    if ( exists $baseCnf{$variable} ){
                        if ( defined($baseCnf{$variable}) and $baseCnf{$variable} ne "" ){
                            print CONF "$variable = $baseCnf{$variable}\n";
                        }else{
                            print CONF "$variable\n";
                        }
                    } elsif ( $_ =~ /\/data\/mysql/ ){
                        $_ =~ s/\/data\/mysql/$dataDir/;
                        print CONF "$_";
                    }else{
                        print CONF "$_";
                    }
                } elsif ( $_ =~ /\[mysqld\]/ ){
                    print CONF "$_";
                    while ( my($key,$val) = each %{$otherVariables} ){
                        if ( defined($val) and $val ne "" ){
                            print CONF "$key = $val\n";
                        }else{
                            print CONF "$key\n";
                        }   
                    }
                } else {
                    print CONF "$_";
                }
            }
            close CONF;
            close TEMPLATE;

            $exitCode = 1;
        }
    };
    if ( $@ ){
        $log->error("create my.cnf file error, error msg:$@");
        undef $@;
    }

    return $exitCode;
}

# @Description:  检查mysql存活
# @Param: 
# @Return:  1:成功  0:失败
sub isMysqlAlive {
    my ( $self,$dbh ) = $@;
    
    my $log = Log::Log4perl->get_logger("");

    my $exitCode = 0;
    
    eval{
        my $isAlive = $dbh->ping;
        if ( $isAlive == 1 ){
            
            $exitCode = 1;
            $log->info("mysql is alive");
            
        }else{
            $log->error("mysql is not alive");
        }
        $dbh->disconnect();
    };
    if ( $@ ){
        $log->error("mysql isn't alive");
        undef $@;
    }

    return $exitCode;
}

# @Description:  启动mysql实例
# @Param: 
# @Return:
sub startMysqlInstance {
    my ( $self,$port ) = @_;

    my $log = Log::Log4perl->get_logger("");

    my $exitCode = 0;
    
    my $mytab = "/etc/mytab";
    
    my $startupTimeout = 600;
    
    my $retryTimes = 10;
    
    my ( $baseDir,$mycnf,$myport,$enable,$socket );

    eval {
        alarm($startupTimeout);
        open MYTAB,"$mytab" or die "can't open $mytab";
        while(<MYTAB>){
            if ( $_ =~ /^\s*#/ or $_ =~ /^\s*$/ ){
                next;
            }

            my @line = split /\s+/, $_;
            if ( scalar(@line) == 4 ){
                ( $baseDir,$mycnf,$myport,$enable ) = @line;
                chomp(@line);
                if ( $myport == $port and lc($enable) =~ /^y$/ ){
                    my $cmd = "cd $baseDir;./bin/mysqld_safe --defaults-file=$mycnf --user=mysql > /dev/null &";
                    system($cmd);
                    foreach my $i (0..$retryTimes){
                        my $isAlive = $self->isMysqlAlive();
                        if ( $isAlive == 0 ){
                            $log->info("start mysql $port not finish yet, retry $i");
                            sleep 5;
                            next;
                        }else{
                            $exitCode = 1;
                            $log->info("start mysql $port success");
                            
                            last;
                        }
                    }
                }
                
            }else{
                $log->error("mytab: $mytab line format bad");
            }
        }
        close MYTAB;
        alarm(0);
    };
    if ( $@ ){
        $log->error("startup mysql failed, error msg: $@");
        undef $@;
    }

    return $exitCode;
}

# @Description:  停止实例mysqld进程
# @Param: 
# @Return:  2:成功  0:失败
sub stopMysqlInstance {
    my ( $self,$port ) = @_;

    my $log = Log::Log4perl->get_logger("");

    my $exitCode = 0;
    
    # 检查端口
    if ( ! $port ){
        $log->error("get instance: port failed");
        
        return 0;
    }
    
    # 此处仅为了验证备份有效性,已恢复的数据无其他用途,可直接杀进程
    eval {
        my $mysqldSafePid = `ps -ef |grep "mysqld_safe" |grep $port |grep -v grep |awk \'{print \$2}'`;
        chomp($mysqldSafePid);
        system("kill -9 $mysqldSafePid");
        if ( $? == 0 ){
            $exitCode = $exitCode + 1;
            $log->info("instance: $port kill mysqld_safe process success");
        }else{
            $log->error("instance: $port kill mysqld_safe process failed");
        }
        
        my $mysqldPid = `ps -ef |grep "mysqld" |grep $port|grep -v "mysqld_safe" |grep -v grep |awk \'{print \$2}'`;
        chomp($mysqldPid);
        system("kill -9 $mysqldPid");
        if ( $? == 0 ){
            $exitCode = $exitCode + 1;
            $log->info("instance: $port kill mysqld process success");
        }else{
            $log->error("instance: $port kill mysqld process failed");
        }
    };
    if ( $@ ){
        $log->error("kill mysqld_safe and mysqld error, error msg: $@");
        undef $@;
    }

    return $exitCode;
}

# @Description:  检查mysql服务
# @Param:  端口
# @Return:  1:成功 0:失败
sub checkMysqlService {
    my ( $self,$port ) = @_;

    my $log = Log::Log4perl->get_logger("");

    my $exitCode = 0;
    
    # 检查端口
    if ( ! $port ){
        $log->error("get instance: port failed");
        
        return 0;
    }
    
    # 获取连接mysql配置
    my $defaultConfig = $self->{dbbackupObj}->getMysqlDefaultConfig();
    
    my $defaultHost = $defaultConfig->{ip};
    my $defaultPort = $port;
    my $defaultDbname = $defaultConfig->{db_name};
    my $defaultDbuser = $defaultConfig->{db_username};
    my $defaultDbpass = $defaultConfig->{db_password};
    
    # 连接mysql
    my $dbh = $self->{dbbackupObj}->mysqlConnect($defaultHost,$defaultPort,
        $defaultDbname,$defaultDbuser,$defaultDbpass);
    
    if ( !defined($dbh) ){
        $log->error("connect mysql failed");
    }
    
    $exitCode = $self->isMysqlAlive($dbh);

    return $exitCode;
}

1;
