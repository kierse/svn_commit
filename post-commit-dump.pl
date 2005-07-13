#!/usr/bin/perl -w

#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#
#
#   Author:      Kier Elliott
#
#   Date:        July 8, 2005
#
#   Description: Dump script that gets called by post-commit hook script.
#                Script dumps revision committed to repository that triggered
#                its execution and places the dump file in the backup folder
#                containing the most recent hot backup.
#
#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#

use strict;
use warnings; 

#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#
# variables                                                                   #
#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#

# path of svnadmin binary
my $svnadmin = '/usr/local/bin/svnadmin';

# path to svn repository
my $repository = "";

# revision number to be dumped
my $revision;

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
$Errors[2] = { level => 3, message => "Backup directory has incorrect write permissions" };
$Errors[3] = { level => 3, message => "Repository does not exist" };
$Errors[4] = { level => 3, message => "Given revision number is not numeric" };
$Errors[5] = { level => 2, message => "Could not close log file" };

#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#
# methods                                                                     #
#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#

sub setup
{
   logMessage("BEGIN: Commencing incremental dump of revision $revision...", 2);
   
   # get list of svn backups in given backup folder...
   #
   my @List = getListOfDirectories();

   # determine which folder contains the most current
   # hot-backup
   #
   my $newest = getMostCurrentDirectory(@List);

   # open log file for later use
   #
   open($LOG, ">>", "$backupDir/$newest/$logFile") or throwError(0, "Does script file have permission to write to '$backupDir/$newest/$logFile'?");

   logMessage("BEGIN: Commencing incremental dump of revision $revision...", 3);

   return "$backupDir/$newest";
}

sub getListOfDirectories
{
   logMessage("Exploring destination for existing backups", 2);

	throwError(1, "($backupDir)") unless( -d $backupDir );

	my @Dirs;
	opendir(DEST, $backupDir) or throwError(2, "($backupDir)");
   
	# get name of all files and directories in given folder
   # excluding '.' and '..'
	#
	foreach my $file (readdir(DEST))
	{
      next if "$backupDir/$file" =~ /^(\.|\.\.)$/; # skip if pointer is '.' or '..'
      next unless -d "$backupDir/$file";         # skip if pointer is not a directory

      push @Dirs, $file;
	}
	closedir(DEST);
   
   return sort @Dirs;
}

sub getMostCurrentDirectory
{
   my (@Dirs) = @_;

   logMessage("Locating most current hot-backup", 2);
   
   my @Sorted = reverse @Dirs;

   # return the newest folder (based on folder
   # name)
   #
   return $Sorted[0];
}

sub performDump
{
   my ($dest) = @_;

   logMessage("Performing dump");

	# check to ensure that the given repositor and backup directory
	# exists, and the revision is numerical otherwise throw error and exit
	#
   throwError(3, "($repository)") unless( -d $repository );
	throwError(1, "($dest)") unless( -d $dest );
	throwError(4, "($revision)") unless( $revision =~ /^\d+$/ );

   # perform incremental dump on repository using given revision number.  Pipe
   # results to svn-$revision.dump in destination folder
   my $result = `$svnadmin dump $repository --incremental --revision $revision > $dest/svn-$revision.dump`;

   logMessage($result);
}

sub cleanup()
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
   close($LOG) or throwError(5);
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

# script takes 3 arguments, if 3 aren't supplied show a little
# help message
#
if(scalar @ARGV != 3)
{
   print "usage: post-commit-dump.pl <REPOS_PATH> <DEST_PATH> <REVISION>\n";
   exit(-1);
}

# store repos and destination path in
# nicer variables :)
#
($repository, $backupDir, $revision) = @ARGV;

my $dest = setup();

# perform repository dump using given repository
# location and revision number.  Put dump file
# in the directory determined above
#
performDump($dest);

# clean up environment
#
cleanup();

exit(0);
