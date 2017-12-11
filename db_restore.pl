#!/usr/bin/env perl
# Description:  数据库恢复主脚本
# Authors:  
#   zhaoyunbo

use strict;
use warnings;

use File::Spec;
use Log::Log4perl;
use Fcntl qw(:flock);
use POSIX qw(strftime);
use POSIX qw(:signal_h);

use FindBin qw($Bin);
use lib "$Bin/common";

use BackupManager;
use ManagerUtil;


my $dbconfigObj = new Dbconfig();
if ( !$dbconfigObj ){
    $dbconfigObj = new Dbconfig();
}
my $backupManagerObj = new BackupManager( dbconfigObj => $dbconfigObj );
if ( !$backupManagerObj ){
    $backupManagerObj = new BackupManager( dbconfigObj => $dbconfigObj );
}

# 获取当前日期
my $curDate = `date "+%Y%m%d"`;
chomp($curDate);

# 设置日志目录
my $logDir = "/data/logs/db_restore";

my $logFile;
if ( -e $logDir ){
    $logFile = "${logDir}/db_restore" . $curDate .".log";
}else{
    mkdir($logDir, 0755);
    $logFile = "${logDir}/db_restore" . $curDate .".log";
}

# 初始化log4perl
my $log = $dbbackupObj->initLog4Perl($logFile);

# 获取参数
GetOptions(
    "source_ip=s" => \$sourceIp,
    "source_port=i" => \$sourcePort,
    "bak_type=s" => \$bakType,
    "db_type=s" => \$dbType,
    "level=s" => \$level,
    "level_value=s" => \$levelValue,
    "is_compressed=s" => \$isCompressed,
    "is_encrypted=s" => \$isEncrypted,
    "dec_key=s" => \$decKey,
    "is_slave=s" => \$isSlave,
    "storage_ip=s" => \$storageIp,
    "storage_type=s" => \$storageType,
    "bak_time=s" => \$bakTime,
    "data_dir=s" => \$dataDir,
    "target_ip=s" => \$targetIp,
    "target_port=i" => \$targetPort,
    "help" => \$help
);

# 检查参数
my $scriptName = $0;
if ( $help ) {
    system("pod2text $scriptName");
    exit 0;
}

my $optionsNeeded;
( defined($sourceIp) ) or $options_needed .= "--source_ip is needed\n";
( defined($sourcePort) ) or $options_needed .= "--source_port is needed\n";
( defined($bakType) ) or $options_needed .= "--bak_type is needed\n";
( defined($dbType) ) or $options_needed .= "--db_type is needed\n";
( defined($isCompressed) ) or $options_needed .= "--is_compressed is needed\n";
( defined($isEncrypted) ) or $options_needed .= "--is_encrypted is needed\n";
( defined($decKey) ) or $options_needed .= "--dec_key is needed\n";
( defined($isSlave) ) or $options_needed .= "--is_slave is needed\n";
( defined($storageType) ) or $options_needed .= "--storage_type is needed\n";
( defined($bakTime) ) or $options_needed .= "--bak_time is needed\n";
( defined($dataDir) ) or $options_needed .= "--data_dir is needed\n";
( defined($targetIp) ) or $options_needed .= "--target_ip is needed\n";
( defined($targetPort) ) or $options_needed .= "--target_port is needed\n";

# 获取备份集信息
my $backupSet = $backupManagerObj->getBackupSet($sourceIp,$sourcePort,$dbType,$bakType);
if ( !defined($backupSet) ){
    $log->error("get backupSet info failed");
}
$log->info("get backupset info success");

my $bakDir = $backupSet->{bak_dir};
my $bakTime = $backupSet->{end_time};

# 挂载filer分区
my $checkMfsmount = $backupManagerObj->checkMfsmount();
if ( !$checkMfsmount ){
    $log->error("check mfsmount command failed");
    exit 1;
}
$log->info("check mfsmount success");

# 挂载mfs
my $mountMfs = $backupManagerObj->mountMfs($host,$port,$filerDir,$fileDir);
if ( !$mountMfs ){
    $log->error("mount mfs failed");
}
$log->info("mount mfs success");

# 拷贝数据
my $copyToTargetDir = $backupManagerObj->copyToTargetDir($targetIp,$targetPort,$targetDir,$speed);
if ( $copyToTargetDir ){
    $log->info("copy backupset to target dir success");
}else{
    $log->error("copy backupset to target dir failed");
}

# 解压缩
if ( lc($isCompressed) eq "y" && lc($isEncrypted) eq "n" ){
    $log->info("backupset is compressed, but not encrypted");
    
    my $decompressBackupSet = $backupManagerObj->decompressBackupSet($backupSet,$outputDir);
    if ( $decompressBackupSet ){
        $log->info("decompress backupset: $backupSet success, outputDir:$outputDir");
    }else{
        $log->error("decompress backupset failed");
    }
}

# 解密
if ( lc($isEncrypted) eq "y" ){
    $log->info("backupset is encrypted");
    
    my $decryptBackupSet = $backupManagerObj->decryptBackupSet($backupSet,$decKey,$outputDir);
    if ( $decryptBackupSet ){
        $log->info("decrypt backupSet: $backupSet success, outputDir:$outputDir");
    }else{
        $log->error("decrypt backupset failed");        
    }
}

# 卸载filer分区
my $umountMfs = $backupManagerObj->umountMfs($host,$port,$dbType);
if ( !$umountMfs ){
    $log->error("umount mfs filer failed");
}
$log->info("umount mfs filer success");

if ( lc($dbType) eq "mysql" ){
    if ( lc($bakType) eq "xtrabackup" ){
    
        # 应用重做日志
        my $recover = $backupManagerObj->recover($dataDir,$backupMycnf);
        if ( $recover ){
            $log->info("recover backupset success");
        }else{
            $log->error("recover backkupset failed");
        }
    }

    # 创建配置文件
    my $createMycnf = $backupManagerObj->createMycnf($host,$port,$memSize,$dataDir,$mycnfTemplate,
        $backupMycnf,$otherVariables);
    if ( $createMycnf ){
        $log->info("create my.cnf config file success");
    }else{
        $log->error("create my.cnf config file failed");
    }

    # 启动实例
    my $startMysqlInstance = $backupManagerObj->startMysqlInstance($port);
    if ( $startMysqlInstance ){
        $log->info("start mysql instance success");
    }else{
        $log->error("start mysql instance failed");
    }
    
    # 检查mysql服务
    my $checkMysqlService = $backupManagerObj->checkMysqlService($port);
    if ( $checkMysqlService ){
        $log->info("check mysql instance success");
    }else{
        $log->error("check mysql instance failed");
    }
    
    # 杀掉mysql实例
    my $stopMysqlInstance = $backupManagerObj->backupManagerObj($port);
    if ( $stopMysqlInstance ){
        $log->info("kill instance: $port pid success");
    }else{
        $log->error("kill instance: $port pid failed");
    }
}
