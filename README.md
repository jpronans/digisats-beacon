digisats-beacon
===============

A perl script that uses Predict and Hamlib to automatically tune a radio for doppler. Also sends APRS beacons using the beacon utility.

digisats-beacon.pl requires predict and hamlib to be installed.

Before running digisats-beacon.pl, you should

1) Have a predict server running (use "predict -s") that has good keps for whichever satellite you wish to receive.

2) Set your $baud_rate and $com_port to suitable values for your receiver.

3) Set $on_cmd and $off_cmd to something meaningful for your shack. The examples given are for a West Mountain Radio 4005i with an FT-847 plugged into output 1.

When invoked, digisat_beacon.pl runs through the list of satellites and stops on the first that is above the elevation set in $elevation_mask. It loops on that satellite, tuning the receiver for doppler until it once again drops below $elevation_mask. If no other satellites are above $elevation_mask, it will power off the receiver and sleep for a short period before waking up to begin the process again.
