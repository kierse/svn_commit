#!/usr/bin/perl -w

#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#
#
#   Author:      Kier Elliott
#
#   Date:        July 3, 2005
#
#   Description: Backup script that is responsible for backing up
#                subversion repositories.  Basic idea is that subversion
#                repository can be rebuilt using last hotbackup and all
#                incremental dump files made since last backup.  This
#                script attempts a hotbackup of given repository; if 
#                successful, it cleans up the backup directory by removing
#                the last hotbackup and all dump files as they are no
#                longer necessary.
#
#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#

use strict;
use warnings; 

#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#
# variables                                                                   #
#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#

# path to subversion hotbackup script
my $hotbackup = '/usr/local/share/subversion/backup/hot-backup.py';

# specify how many weeks of backups to maintain
my $backupHistory = 4;

# path to svn repository
my $repository = "";

# path to backup directory
my $backupDir = "";

# name of log file
my $logFile = "log";

# keeps track of highest error level encountered during execution
my $highestError = 0;

# array that contains all possible errors
my @Errors;

# file pointer to log file defined in $logFile
my $LOG; # filehandler

#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#
# error messages                                                              #
#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#

# error messages
# 1 => Warning, 2 => Alert, 3 => ERROR
$Errors[0] = { level => 3, message => "Could not open file for writing" };
$Errors[1] = { level => 3, message => "Directory does not exist" };
$Errors[2] = { level => 3, message => "Can't open directory for reading" };
$Errors[3] = { level => 3, message => "Repository does not exist" };
$Errors[4] = { level => 3, message => "Backup directory has incorrect write permissions" };
$Errors[5] = { level => 1, message => "Tempory backup directory already exists" };
$Errors[6] = { level => 3, message => "Unable to create temporary directory" };
$Errors[7] = { level => 3, message => "Backup of repository failed" };
$Errors[8] = { level => 2, message => "Could not cliose log file" };

#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#
# methods                                                                     #
#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#

sub setup
{
   # if log file already exists, rename it to log.old
   #
   if( -f "$backupDir/$logFile" )
   {
      rename "$backupDir/$logFile", "$backupDir/$logFile.old";
   }
   
   # open log file for later use
   #
   open($LOG, ">", "$backupDir/$logFile") or throwError(0, "Does script file have permission to write to '$logFile'?");

   logMessage("BEGIN: Commencing hot-backup of subversion repository...");
}

sub getListOfDirectories
{
   logMessage("Exploring destination for existing backups");

	throwError(1, "($backupDir)") unless( -d $backupDir );

	my @Dirs;
	opendir(DEST, $backupDir) or throwError(2, "($backupDir)");
   
	# get name of all files and directories in given folder
   # excluding '.' and '..'
	#
	foreach my $file (readdir(DEST))
	{
      next if $file =~ /^(\.|\.\.)$/; # skip if pointer is '.' or '..'
      next unless -d $file;           # skip if pointer is not a directory

      push @Dirs, $file;
	}
	closedir(DEST);
   
   return sort @Dirs;
}

sub performHotBackup
{
   my $tmp = "tmp-repo";
   
   logMessage("Performing hot-backup");

	# check to ensure that the given repository and backup directory
	# exists, otherwise throw error and exit
	#
   throwError(3, "($repository)") unless( -d $repository );
	throwError(1, "($backupDir)") unless( -d $backupDir );
	throwError(4, "($backupDir)") unless( -w $backupDir );

   # check for existing temp directory. If found, delete, print warning, and continue
   #
   if( -d "$backupDir/$tmp" )
   {
      `rm -rf $backupDir/$tmp`;
      throwError(5, "($backupDir/$tmp)") ;
   }
   
   # make temp directory in backup folder to store new hotbackup... 
   #
   throwError(6, "($backupDir/$tmp)") unless( mkdir("$backupDir/$tmp") );

   # perform backup using given values...
   #
	my $result = `$hotbackup $repository $backupDir/$tmp 2>&1`;

   # ...log results and check for errors
   #
   logMessage($result, 3);
   throwError(7, "Consult $logFile for more details") unless( $result =~ /done/i );
}

sub cleanupBackupDir
{
   my (@List) = @_;
   
   logMessage("Removing old backups");

   # if log.old exists in backup directory, move to
   # folder containing newest hot-backup other than
   # current one.
   #
   if( -f "$backupDir/$logFile.old" )
   {
      my $newest = $List[-1];
      `mv $backupDir/$logFile.old $backupDir/$newest/$logFile`;
   }

   # if list is empty, return
   # if $backupHistory is set to 0, return.
   # this will not remove any old backups at all!
   #
   return unless(@List and $backupHistory);

   # loop through given directories and isolate those
   # which are backup dirs.  Build hash containing
   # backupdir and last modify time 
   #
   my %Stats;
   foreach my $dir (@List)
   {
      # YYYY.MM.DD
      next unless $dir =~ /^\d{4}\.\d{2}\.\d{2}$/;

      my @Info = stat $dir;

      # last modify time => dir
      $Stats{ $Info[9] } = $dir;
   }

   # if there are fewer backups than specified in $backupHistory
   # return
   #
   return if(scalar( keys %Stats ) < $backupHistory);

   # go through hash and unlink oldest ones 
   # until only ($backupHistory - 1) remains
   #
   my @Keys = sort( keys %Stats );
   foreach my $key (splice @Keys, 0, (scalar @Keys - $backupHistory) + 1)
   {  
      my $dir = $Stats{$key};
      `rm -rf $backupDir/$dir`;
   }
}

sub organizeBackupDir
{
   my $tmp = "tmp-repo";

   logMessage("Performing final cleanup");
   
   my @Time = localtime();
   my $year = $Time[5] + 1900;
   my $month = sprintf("%02d", $Time[4] + 1);
   my $day = sprintf("%02d", $Time[3]);

   # move the new backup from the temp directory 
   #
   my $result = `mv $backupDir/$tmp $backupDir/$year.$month.$day`;
   
   cleanup();
   
   # finally, move the log file to the new directory
   #
   `mv $backupDir/$logFile $backupDir/$year.$month.$day`;
}

sub cleanup
{
   # print specific message depending on the error level encountered while running application.
   #
   if( $highestError == 3 )
   {
      logMessage("END: The backup script encountered errors, please consult the error log at '$backupDir/$logFile' for more details", 2);
   }
   else
   {
      logMessage("END: The hot-backup was completed successfully");
   }

   # close log file
   #
   close($LOG) or throwError(8);

}

sub getTime
{
    my @Time = localtime();

    # YYYY/MM/DD HH:MM:SS
    return "[" . (1900 + $Time[5]) . "/" . sprintf("%02d", $Time[4] + 1) . "/" . sprintf("%02d", $Time[3]) . " " . sprintf("%02d", $Time[2]) . ":" . sprintf("%02d", $Time[1]) . ":" . sprintf("%02d", $Time[0]) . "] - ";
}

sub logMessage
{
    my ($message, $dest) = @_;
    $dest ||= 1;

    return unless $message;

    my $time = getTime();

    # must check to see what $dest is set to
    # 1 => screen and log
    # 2 => screen only
    # 3 => log only
    #
    if($LOG)
    {
        print $LOG $time . $message . "\n" unless(3 % $dest);
    }
    print $time . $message . "\n" unless(2 % $dest);
}

sub throwError
{
   my ($num, $message) = @_;
   $message ||= "";

   my $time = getTime();

   my $error = $Errors[$num];
   if( $$error{"level"} == 1 )
   { # WARNING
      my $msg = $time . "WARNING: " . $$error{"message"} . ": $message\n";

      print $LOG $msg if $LOG;
      print $msg;

      # update $highestError
      #
      $highestError = 1 if $highestError < 1;
   }
   elsif( $$error{"level"} == 2)
   { # ALERT
      my $msg = $time . "ALERT: " . $$error{"message"} . ": $message\n";

		print $LOG $msg if $LOG;
		print $msg;
		
		# update $highestError
		#
		$highestError = 2 if $highestError < 2;
	}
	else
	{ # ERROR
		my $msg = $time . "ERROR: " . $$error{"message"} . ": $message\n";
		
		print $LOG $msg if $LOG;
		print $msg;
		
		# update $highestError
		#
		$highestError = 3;
		
		cleanup();
		exit(-3);
	}
}

#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#
# main                                                                        #
#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#

# script takes at least 2 arguments, if 2 aren't supplied show a little
# help message
#
if(scalar @ARGV != 2)
{
   print "usage: hot-backup-plus.pl <REPOS_PATH> <DEST_PATH>\n";
   exit(-1);
}

# store repos and destination path in
# nicer variables :)
#
($repository, $backupDir) = @ARGV;

setup();

# get list of svn backups in given backup folder...
#
my @List = getListOfDirectories();

# perform backup of repository 
#
performHotBackup();

# expunge old backup data...
#
cleanupBackupDir(@List);

# finish up by moving new backup to destination folder
#
organizeBackupDir();

exit(0);

