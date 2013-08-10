#!/usr/bin/perl -w
# Based on script by Andrew Rich, VK4TEC. 
# Thanks to MSOF & KC8BLL for perl contributions.
# John Ronan, EI7IG, 2013
# Darren Long, G0HWW, 2013

# MSOF: using standard libraries needed (perl modules)
# MSOF: One might consider adding:
# use strict;
# MSOF: to enable the strict parsing, but this may require some editing

use Socket;
use Net::Telnet;
use Math::Round;

# MSOF: Default values for global variables
# MSOF: "my" scope means only active in the main body not subroutines
# MSOF: I have changed to "local" to allow subroutines to see them

# Radio options, 
local $model = 101; #101 for FT-847 #226 for Kenwood D700

# Change for your radios baud rate
local $baud_rate = 57600;

# Change for your serial port
local $com_port = "/dev/ttyS5";

# I use -2 as the keps can be a little off.
local $elevation_mask = -2;
local $default_frequency = 145825000;

# beacon options
local $bcn_port = "1200mk";
local $bcn_call = "EI7IG";
local $bcn_path = "APRS ARISS";
local $bcn_lat = "5209.96N";
local $bcn_long = "00709.65W";
local $bcn_char = "=";
local $bcn_sym_1 = "/";
local $bcn_sym_2 = "y";
local $bcn_text = "Xastir 2.07 SatGate";

#utilities
local $rig_ctl = "/usr/local/bin/rigctl";
local $bcn_bin = "/usr/local/sbin/beacon";

#beacon data
local $bcn_cmd      = "$bcn_bin -s -c \"$bcn_call\" -d \"$bcn_path\" \"$bcn_port\" \"$bcn_char$bcn_lat$bcn_sym_1$bcn_long$bcn_sym_2$bcn_text\"";
local $bcn_print    = "Sending beacon from $bcn_call via $bcn_path with text: $bcn_text\n";

# On and off commands
# These commands work with the Westmountainradio Rigrunner 4005i
local $user = "username";
local $pass = "password";
local $dest = "a.b.c.d"
local $on_cmd   = "curl -s --user \"$user\":\"$pass\" http://\"$dest\" --data \"RAILENA0=1\" > /dev/null ";
local $off_cmd  = "curl -s --user \"$user\":\"$pass\" http://\"$dest\" --data \"RAILENA0=0\" > /dev/null ";


local $frequency = $default_frequency;
local $port;
local $predict_server;
local $satellite;

# Set to 1 to enable debug information
local $debug = 1;
local $rig_on = 0;

# Set initial sleep interval to 1 second
local $sleep = 1;
# MSOF: Parsing cmd line arguments
# If the no of args is 2 (i.e. <cmd> $ARGV[1] $ARGV[2])
if ($#ARGV == 1) { 
  $predict_server = $ARGV[0];
  $port		  = $ARGV[1];
} else {
  # Print Usage and assume default values
  print "WARNING: Use syntax \"predict_control.pl hostname portnum\" (i.e., predict_control localhost port)\n";
  print "Substituting default arguments\n";
  $predict_server = "localhost";
  $port = 1210;
} 

# End parsing cmd line arguments
if ($debug)
  {
    print ("Initialising Radio state to off\n");
  }

system($off_cmd);

# MSOF: Associative array of name=>value pairs
# MSOF: associate arrays have no order, so my hack here
#       is to prepend a letter denoting order that I then strip off
#	- awkward as must use original version as key to get value

my %sats = (
    "aPCSAT"	=>      14582700,
    "bISS" 	=>	14582500,
    "cSTRAND 1"  => 	43756800,
#    "cISS" 	=>	43755000,
#    "eFAST1" 	=>	43734500,
#    "eNANOSAILD"  =>	43727000
#    "eOOREOS" 	=>	43730500,
#    "fRAX" 	=>	43750500
#    "cLUSAT"	=>      14582700,
#    "cXIWANG-1"	=>      43567500,
#   "bOSCAR-57" 	=>      14580000,
#   "cCAPE-1"         =>	43524500,
#   "dOSCAR-32"	=>      43522500,
#  " cXI-V" 	      =>      43746500,
#    "eOSCAR-51"   =>      43515000,
#   "fOSCAR-50"         =>      43679500,
#  "hPO-28 [+]"         =>      42995000,
#  "hRS-22"         =>      43535200,
#  "fHAMSAT"         =>      14586000,
#  "iCUTE-1"         =>	43740000,
#    "jOSCAR-27"	=>	43679500
);
do{	
  foreach $sat (sort keys %sats) {
        # MSOF: hack to strip off prepended letter to force PCSAT 1st
	my $satstrip = substr($sat,1);
	if ($debug) 
	{
	  print "Calling: $satstrip \t $sats{$sat} \n";
        }
        
	my_main($predict_server,$port,$satstrip,$sats{$sat});	# Call with key and value
 
  }
 
  print("Nothing available...sleeping for $sleep seconds\n");

 sleep $sleep;  
}while (1);

# MSOF: Finish
exit; 

#================================================================

# MSOF: Wrapped as new sub routine
sub my_main {
  # MSOF: Perl arguments passed in array @_ in elements $_[0]...$_[N]
  #  do {
  # MSOF: Set values to arguments 
  # MSOF: (no checking as we did this ourselves and it should be right)
  $predict_server = $_[0];
  $port		  = $_[1];
  $satellite 	  = $_[2];
  $frequency 	  = $_[3];

  if ($debug)     
  {
    print "Sleep is $sleep\n";
  }
  # Doing unix-style DNS calls here
  
  my ($d1, $d2, $d3, $d4, $rawserver) = gethostbyname($predict_server);
  my $serveraddr = pack("Sna4x8", 2, $port, $rawserver);
  my $prototype = getprotobyname('udp');
  my $server_response = 0;
  my ($name, $lon, $lat, $az, $el, $aos_seconds, $foot) = split /\n/, $server_response;

  do{
    socket(SOCKET,2,SOCK_DGRAM,$prototype) 
	|| die("No Socket\n"); 
  
    $| = 1;  # no buffering
    $SIG{ALRM} = \&time_out;
    alarm(10);  # Force exit if no response from server

    # Send request to predict
    send(SOCKET, "GET_SAT $satellite\0" , 0 , $serveraddr) 
      or die("UDP send failed $!. Is predict running?\n");
  
    $server_response = '';  # required by recv function
    recv(SOCKET, $server_response, 100, 0)
      or die "UDP recv failed $!\n";
    
    # Extract individual responses
    ($name, $lon, $lat, $az, $el, $aos_seconds, $foot) = split /\n/, $server_response;
    my $aos_time_date = gmtime($aos_seconds);
  
    # We have the Elevation now
    send(SOCKET, "GET_DOPPLER $satellite\0" , 0 , $serveraddr) 
      or die ("UDP send failed $!\n");
    my $server_response = '';  # required by recv function
    recv(SOCKET, $server_response, 100, 0) or die "UDP recv failed $!\n";
    alarm(0);

    # Hmm, forgotten, why I did it this way.. 
    $shift = (($server_response * ($frequency/10000000)) / 10 );
    $newfreq = (int($frequency + $shift));
    $rounded = nearest(1,$newfreq) ;
    if ( $debug )
    {
      # MSOF: Replaced backtick with qx// notation
      $date = qx/date +%d\/%m\/%y" "%H:%M:%S/;
      chop $date;
      print "DATE: $date \n";
      print "SAT: $satellite \n";
      print "BASE: $frequency \n";
      print "HOST: $predict_server \n";
      print "PORT: $port \n";
      print "SHIFT $shift \n";
      print "TUNE: $rounded"."00"."\n";
      print "DOPP: $shift \n";
      print "ELE: $el\n";
    }
    $sendtorig = $rounded."0";  
    # If the satellite is above the elevation mask, begin looping on this satellite
    # We want to get is from AOS to LOS while above the elevation mask
    if ( $el > $elevation_mask)
    {
      $sleep = 27;
      if ( $rig_on == 0 ){
        system($on_cmd);
        $rig_on = 1;
        # Pause to give the radio a chance to come on
        sleep 2;
        # FM Mode please, radio may have been on 6m SSB last time it was used ;)
        system("$rig_ctl -m $model -r $com_port -s $baud_rate M FM 15000");

      }
      print "SAT: $satellite \n";
      print  "Elevation: $el\n";
      print "TUNE: $rounded"."00"."\n\n";
      # Calls hamlib to change the frequency of the radio
      system("$rig_ctl -m $model -r $com_port -s $baud_rate F $sendtorig"); 
      # 1 second delay to leave freq settle
      sleep 1;
      if ($satellite eq "ISS"){
        # If the ISS is overhead, try and beacon through it
        print $bcn_print;
        system ($bcn_cmd);
      }
    }
  close(SOCKET);
  # Go to sleep for a bit
  sleep $sleep;
  # If the satellite is over the horizon, stay with it until AOS    
  } while ($el > $elevation_mask);
  
  # Satellite is gone below the horizon, switch off radio
  if ( $rig_on){
    system($off_cmd);
    $rig_on = 0;
  }
  # set the sleeping interval to 30 seconds between check
   $sleep = 30;   
} # MSOF: End my_main()

sub time_out {
 	die "Server not responding for satellite $satellite\n";
}
