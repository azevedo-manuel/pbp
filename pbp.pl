#!/usr/bin/env perl

use constant version     => "0.2 - 28.Apr.2015";
use constant programName => "phone background push - pbp";
use constant developer   => "Manuel Azevedo";


use strict;
use Config::Std;
use LWP::UserAgent;
use XML::Bare;
use Data::Dumper +qw(Dumper);
use Getopt::Long;
use SOAP::Lite;#  +trace => 'debug';
use Sys::RunAlone;


# Record time when the script starts
my $runTime = time();

# Global program variables
# Change them here, not in the code bellow

my $configFile = 'pbp.conf';   # Assume file is local to the app
my $debug      = 0;            # 0 for FALSE, anything else is TRUE

# Configuration parameters
# These are used globally througout the script
# They are first checked if existing on the configuration file and for set values, set accordingly
# If there is a switch it will overwrite the configuration file
# If after these two steps the variable is still undefined

my %configData = (
    quiet         => 0,
    bkgusername   => undef,
    bkgpassword   => undef,
    axlusername   => undef,
    axlpassword   => undef,
    cucm          => undef,
    thumbnailURL  => undef,
    backgroundURL => undef,
    logging       => 1,
    logfile       => "STDIN",
    dummy         => 1,
    rischunksize  => 200,
);

# This array will contain all devices and will be updated by the various steps

my %devices;

#
# function debugMsg($x[,$y][,$z])
#
# Print a debug line if '$debug' is defined. First argument can be a printf string
sub debugMsg{
    if ($debug) {
	printf "DEBUG > $_[0]\n",$_[1],$_[2];
	$|=1;
    }
}


#
# function statusMsg($x[,$y][,$z])
#
# Print a status message if quiet is undefined
sub statusMsg{
    if (!$configData{quiet}){
	printf "$_[0]\n",$_[1],$_[2],$_[3];
	$|=1;
    }
}



#
# function setBackground($user,$password,$phoneIP,$bkgURL,$bkgThn)
#
# Pushes the configuration to the phone and returns either an error or a sucess response status
#
# Usage:
# ($error,$response) = setBackground ($username,$password,$phoneIP,$bkgURL,$bkgThn)
#
# where:
# $username and $password are from CUCM's End User that has both phones associated with
# $phoneIP is the IP address of the web and customization enabled phone
# $bkgURL is the background image URL.
# $bkgThn is the background image thumbnail URL.
#
# The function returns $error and $response. If $error is defined then the background push failed for some reason
sub setBackground {
    
    my $user    =@_[0];
    my $password=@_[1];
    my $phoneIP =@_[2];
    my $bkgURL  =@_[3];
    my $bkgThn  =@_[4];
    my $error;
    my $response;
   
    # This XML request is pushed to the Phone
    my $setBkgXML = "<setBackground><background><image>$bkgURL</image><icon>$bkgThn</icon></background></setBackground>";
    my $phoneWeb  = "http://$phoneIP/CGI/Execute";
    
    # Create new connection
    my $ua = LWP::UserAgent->new();
    
    # Phone's will query CUCM for authorization.
    $ua->credentials("$phoneIP:80","user",$user,$password);
    # Timeout was lowered from 300s to 5s
    $ua->timeout(5);
    
    # Use HTTP post to send the 'XML' parameter to the phone
    my $post = $ua->post($phoneWeb, {'XML' => $setBkgXML} );
    
    # Test if the answer from the HTTP connection is OK.
    # This does not yet mean the phone background was set, but could indicated the phone's web-service is not enabled
    # or the phone is not reachable.
    if ($post->is_success){
	
	# HTTP request was a sucess. Let's decode the phone's answer
	my $content = $post->decoded_content();
	
	# Usually the phone answers with a XML response. Let's decode it.
	my $xmlObj = new XML::Bare (text=>$content);
	my $xmlAns = $xmlObj->parse();
	
	# If there was an error setting the image, the phone returns this value
	$error=$xmlAns->{CiscoIPPhoneError}->{Number}->{value};
	# If the background was correctly pushed, the phone will answer in this value
	$response=$xmlAns->{CiscoIPPhoneResponse}->{ResponseItem}->{Data}->{value};
    } else {
	# There was an HTTP error. Report the error
	$error = $post->status_line;
    }
    # Return data to caller
    return($error,$response);
}

# Check the configuration file for the parameters
# Update the global config hash with any value found on the config file
sub readConfigFile {
    # Does the config file exist?
    if ( -e $configFile ) {
	debugMsg("Config file: File $configFile found");
	
	# Read the configuration from configuration file
	read_config $configFile => my %config;
	
	# Update the global %configData hash with the options read from the config file
	foreach my $confKey (sort keys %configData) {
	    if ($config{''}{$confKey}){
		$configData{$confKey} = $config{''}{$confKey};
		debugMsg("Config file: %-15s = %s ",$confKey,$configData{$confKey});
	    } else {
		debugMsg("Config file: %-15s = ** Undefined in config file **",$confKey);
	    }
	}
    } else {
	debugMsg("Config file: No '$configFile' found. Assuming default values");
    }
}


#
# function readCLIArguments()
#
# Read command line arguments and parse them.
# Display help and version information
# As CLI options take priority over configuration file options
# validate if 'axlusername' was defined until now. If not, assume it's the same as the 'bkgusername'
sub readCLIArguments{
    
    my $help;
    my $version;

    # Get the arguments from the CLI
    Getopt::Long::Configure ("bundling");
    GetOptions(
	'quiet|q'         => \$configData{quiet},
	'bkgusername=s'   => \$configData{bkgusername},
	'bkgpassword=s'   => \$configData{bkgpassword},
        'axlusername=s'   => \$configData{axlusername},
	'axlpassword=s'   => \$configData{axlpassword},
	'cucm=s'          => \$configData{cucm},
	'thumbnailURL=s'  => \$configData{thumbnailURL},
	'backgroundURL=s' => \$configData{backgroundURL},
	'logging|l'       => \$configData{logging},
	'logfile'         => \$configData{logfile},
	'rischunksize'    => \$configData{rischunksize},
	'help|h'          => \$help,
	'version|V'	  => \$version
    );
    
    # If the AXL username is not defined, assume it's the same as the bkgusername/bkgpassword
    if (!defined($configData{axlusername})){
	debugMsg("CLIArg: AXL username not defined. Assume it's the same as bkgusername");
	$configData{axlusername}=$configData{bkgusername};
	$configData{axlpassword}=$configData{bkgpassword};
    }
    
    # Only used to troubleshoot config data merge
    if ($debug) {
	foreach my $confKey (sort keys %configData) {
	    if ($configData{$confKey}){
		debugMsg("Final config: %-15s = %s ",$confKey,$configData{$confKey});
	    } else {
		debugMsg("Final config: %-15s = ** Undefined **",$confKey);
	    }
	}
    }
    
    # Print help to the user. Exit!
    if ($help){
	print "\nUsage: ";
	print $0." -options \n\n";
	print "where options are:\n";
	print " --quiet or -q          Don't show any output. DEFAULT is '$configData{quiet}' \n";
	print " --bkgusername value    End user's username that has the phones associated with\n";
	print " --bkgpassword value    End user's password\n";
	print " --axlusername value    Application/End user username for CUCM AXL access.\n";
	print "                        If not present, assume same as 'bkgusername'\n";
	print " --axlpassword value    Application/End user password for CUCM AXL access.\n";
	print "                        If 'axlusername' is not defined, assume same as 'bkgpassword'\n";
	print " --cucm value           CUCM AXL server's address\n";
	print " --thumbnailURL value   The URL where the thumbnail image is. \n";
	print "                        Use * to replace with phone model resolution directory\n";
	print " --backgroundURL value  The URL where the background image is. \n";
	print "                        Use * to replace with phone model resolution directory\n";
	print " --logging or -l        List phones that are being used and push status\n";
	print " --logfile              Export to loggin to a file. DEFAULT: log into STDIN\n";
	print " --version or -v        This program's version. When refering to bugs, get the version here\n";
	print " --rischunksize         The number of devices per RIS request. DEFAULT is '$configData{rischunksize}'\n";
	print " --help or -h           This menu\n\n";
	print "Only options with DEFAULT values are optional. All the remaining\n";
	print "need to be configured either in the $configFile or as an command line argument\n\n";
	exit 0;
    }
    
    # Print version information
    if ($version){
	print "\n";
	print "Application : ".programName."\n";
	print "Version     : ".version."\n";
	print "Copyright   : ".developer."\n";
	print "Platform    : $^O\n\n";
	exit 0;
    }
}


#
# function validateConfig()
#
# After reading the configuration from the configuration file or commandline arguments
# if there are any undefined values, print error and abort.
#
sub validateConfig{
    my $error;
    foreach my $confKey (sort keys %configData){
	unless (defined($configData{$confKey})) {
	    print "ERROR: Paramenter '$confKey' is not defined!\n";
	    $error=1;
	}
    }
    if ($error){
	print "ERROR: There are undefined paramenters. Cannot continue\n";
	exit 1;
    }
}

#
# function getPhoneInfo($phoneID);
# Returns model and resolution if found, otherwise, model is 0
#
# Usage: my ($model,$res) = getPhoneInfo($phoneID);
#
sub getPhoneInfo{

    # Get the ID from the function call
    my $phoneID = $_[0];
    
    # Data retrieved from CUCM 10.5
    # I imagine it won't change between versions
    # Needs to be checked
    #
    my %phones = (
	369   => {model =>'7906', res =>'95x34x1'   },
	307   => {model =>'7911', res =>'95x34x1'   },
	434   => {model =>'7942', res =>'320x196x4' },
	435   => {model =>'7945', res =>'320x212x16'},
	404   => {model =>'7962', res =>'320x212x16'},
	436   => {model =>'7965', res =>'320x196x4' },
	30006 => {model =>'7970', res =>'320x212x12'},
	119   => {model =>'7971', res =>'320x212x12'},
	437   => {model =>'7975', res =>'320x216x16'},
	302   => {model =>'7985', res =>'800x600x16'},
	36217 => {model =>'8811', res =>'800x480x24'},
	683   => {model =>'8841', res =>'800x480x24'},
	684   => {model =>'8851', res =>'800x480x24'},
	685   => {model =>'8861', res =>'800x480x24'},
	586   => {model =>'8941', res =>'640x480x24'},
	585   => {model =>'8945', res =>'640x480x24'},
	540   => {model =>'8961', res =>'640x480x24'},
	537   => {model =>'9951', res =>'640x480x24'},
	493   => {model =>'9971', res =>'640x480x24'},
    );
    

    # If found, return model and resolution
    if (exists$phones{$phoneID}){
	debugMsg("PhoneInfo: Found model for ID '%s'",$phoneID);
	return($phones{$phoneID}{model},$phones{$phoneID}{res});
    } else { # Otherwise, return '0'
	debugMsg("PhoneInfo: Phone ID not found");
	return(0);
    }
}

#
# function getUserPhoneList();
#
# This function uses the global configuration variable, no need to pass it any argument
#
sub getUserPhoneList {
    
    # Usually CUCM is implemented with self-signed certificates and AXL
    # cannot be accessed over HTTP, only with HTTPS.
    # The following command disables SSL hostname verification
    # so you don't have to put CUCM's certificate in your trust store.
    # ** BE SURE YOU UNDERSTAND WHAT THAT MEANS **
    $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}=0;
 
    # Passing credentials in the SOAP::Lite request does not seem to work with CUCM.
    # Therefore we push the credentials anytime a request is made
    # This has the benefict of: ignoring the realm, directly authenticates
    # However it looks ugly!
    BEGIN {
    	sub SOAP::Transport::HTTP::Client::get_basic_credentials {
    	    return ($configData{axlusername} => $configData{axlpassword});
    	};
    }
    
    # Built and tested for version 8.5 on a 10.5 CUCM!
    my $cm = new SOAP::Lite
	on_action   => (sub {return "CMDB:DB ver=8.5"}),
	proxy       => "https://$configData{cucm}:8443/axl/",
	ns          => "http://www.cisco.com/AXL/API/8.5";
    
    # Make an AXL getUser request for userid defined in the global config data.
    my $res = $cm->getUser(SOAP::Data->name("userid" => $configData{bkgusername}));
    
    my $registered;
    
    # Process the answer
    unless ($res->fault){
	# Get on the answer from the XML tree
	my @AXLdevices = $res->valueof('//getUserResponse/return/user/associatedDevices/device');
	
	# Get each phone
	foreach (@AXLdevices){
	    debugMsg("Get phone list: Found device '%s'",$_);
	    
	    # Define a data structure to store the device data
	    # Define it here so it initializes for a new hash so you can push it into the %devices hash
	    my %device = (
		devicename  => undef,
		ipaddress   => undef,
		model       => undef,
		status      => undef,
		description => undef
	    );
	    
	    # Defining the value for both key and hash value is usefull further on
	    $device{devicename} = $_;
	    $devices{$_}=\%device;
	    $registered++;
	}
    } else {
	# For some reason could not connect to CUCM. There's no reason to continue
	printf "CUCM error: %s - %s\n",$res->faultcode,$res->faultstring;
	exit 1;
    }
    # Return the total number of configured phones found
    return($registered++);
}

#
# function getPhoneStatus();
#
# This function checks and sets the status of the phones existing in the global %devices hash
# It returns the total number of registered phones found
sub getPhoneStatus{

    # Usually CUCM is implemented with self-signed certificates and AXL
    # cannot be accessed over HTTP, only with HTTPS.
    # The following command disables SSL hostname verification
    # so you don't have to put CUCM's certificate in your trust store.
    # ** BE SURE YOU UNDERSTAND WHAT THAT MEANS **
    $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}=0;
    
   
    # Two little hacks to make SOAP to work correctly with CUCM
    BEGIN {
	# Passing credentials in the SOAP::Lite request does not seem to work with CUCM.
	# Therefore we push the credentials anytime a request is made
	# This has the benefict of: ignoring the realm, directly authenticates
	# However it looks ugly!
	sub SOAP::Transport::HTTP::Client::get_basic_credentials {
	    return ($configData{axlusername} => $configData{axlpassword});
	};

	# Let's ignore the WSDL custom types - this is dangerous, but will work!
	# For some reason (my ignorance surely) I cannot make SOAP::Lite understand
	# the answer from CUCM. Even though the type is defined in the WSDL.
	# So this basically makes SOAP::Lite ignore the type
	sub SOAP::Deserializer::typecast {
	    shift;
	    return shift
	};
    }
    
    # Built and tested for version 8.5 on a 10.5 CUCM!
    my $cm = new SOAP::Lite
	encodingStyle => '',
	on_action     => (sub {return "CUCM:DB ver=8.5"}),
	proxy         => "https://$configData{cucm}:8443/realtimeservice/services/RisPort",
        ns            => "http://schemas.cisco.com/ast/soap/";
	
   
    # RISDB has a limit on the maximum of devices
    # By default it's 200, but can be defined by the 'rischunksize' parameter
    my @chunks;
    
    # As the keys are the phone's devicenames, we can return all the keys into an array
    my @phones = keys %devices;
    
    # Lets create an array of arrays containing each a maximum of phones defined in 'rischunksize'
    push @chunks, [splice @phones,0,$configData{rischunksize}] while @phones;
    
    my $numberChunks = scalar(@chunks);
    debugMsg("Get phone status: Created %i chunk(s), each with a maximum of %i phones",$numberChunks,$configData{rischunksize});
    
    my $i=1;
    
    # Total number of registered phones found
    my $registered;
  
    # For each chunk, create a request
    for my $deviceList (@chunks){
	debugMsg("Get phone status: Getting chunk %i",$i);
	# Create an array for the selection
	my @selection=();
	my $selectionItem;
	# Build a soap device list to include in the query
	foreach (@$deviceList){
	    $selectionItem = SOAP::Data->name("SelectItem" => \SOAP::Data->value(SOAP::Data->name("Item" => "$_")));
	    push (@selection,$selectionItem);
	}
	
	# Make the request to CUCM
	# As @selection is an array, SOAP will created the correct SelectItems :)
	my $res = $cm->SelectCmDevice(
	    SOAP::Data->name("CmSelectionCriteria" => \SOAP::Data->value(
		SOAP::Data->name("Status"      => "Registered"),
		SOAP::Data->name("SelectBy"    => "Name"),
		SOAP::Data->name("SelectItems" => \@selection)
		)
	    )
	);
	
	# Check the answer
	unless($res->fault){
	    # Get the answer from the XML tree
	    my @resNode = $res->valueof('//SelectCmDeviceResponse/SelectCmDeviceResult/CmNodes/item/CmDevices/item');
	    # For each answer, update the global %devices hash
	    foreach (@resNode){
		$devices{$_->{Name}}{ipaddress}     = $_->{IpAddress};
		$devices{$_->{Name}}{model}         = $_->{Model};
		$devices{$_->{Name}}{status}        = $_->{Status};
		$devices{$_->{Name}}{description}   = $_->{Description};
	    }
	    debugMsg("Get phone status: %i phone(s) are registered in chunk %i",scalar(@resNode),$i);
	    # Count how many registered devices we collected so far
	    $registered +=scalar(@resNode);
	} else {
	    # Oops, CUCM connection failed...
	    statusMsg("CUCM error: %s - %s\n",$res->faultcode,$res->faultstring);
	    exit 1;
	}
	$i++;
    }
    # Return the total number of registered phones found
    return $registered;
}

#
#
# Main program execution
#
#

debugMsg('Main: Getting configuration file');
readConfigFile();

debugMsg('Main: Getting configurtion from command line');
readCLIArguments();

debugMsg('Main: Validating if there are undefined options');
validateConfig();

debugMsg('Main: Querying the AXL database for phones associated with %s',$configData{bkgusername});
my $totalConfiguredPhones = getUserPhoneList();;

if ($totalConfiguredPhones) {
    statusMsg("Found %i device(s) associated to user '%s'",$totalConfiguredPhones,$configData{bkgusername});
} else {
    statusMsg("No configured devices found. You need to associated devices to user '%s'",$configData{bkgusername});
    statusMsg("or configure another user");
    exit 1;
}

my $totalRegistered=getPhoneStatus();

statusMsg("Found %i device(s) registered",$totalRegistered);

if ($totalRegistered) {
    my $i=1;
    #take care of pushing the background to the phones
    # ($error,$response) = setBackground ($username,$password,$phoneIP,$bkgURL,$bkgThn)
    debugMsg('Main: Checking all devices. If registered, push background');
    foreach my $device (values %devices) {
	if ($device->{status} eq 'Registered') {
	    debugMsg("Main: $device->{devicename} : $device->{ipaddress} is registered");
	    (my $model, my $res) = getPhoneInfo($device->{model});
	    if ($model) {
		debugMsg("Main: $device->{devicename} model is '$model' and resolution is '$res'");
		my $pushURL = $configData{backgroundURL};
		my $pushThn = $configData{thumbnailURL};
		$pushURL =~ s/\*/$res/g;
		$pushThn =~ s/\*/$res/g;
		debugMsg("Main: Background URL to push to device $device->{devicename} is '$pushURL'");
		debugMsg("Main: Thumbnail URL to push to device $device->{devicename} is '$pushThn'");
		
		(my $error,my $response) = setBackground (
		    $configData{bkgusername},
		    $configData{bkgpassword},
		    $device->{ipaddress},
		    $pushURL,
		    $pushThn
		);
		
		if($response){
		    statusMsg("$i/$totalRegistered - Device '$device->{devicename}' update status: $response")
		} else {
		    statusMsg("$i/$totalRegistered - Device '$device->{devicename}' update failed: $error")
		}
		
	    } else{
		statusMsg("$i/$totalRegistered - Device '$device->{devicename}' is not a supported model");
	    }
	$i++;
	}
	
    }
} else {
    debugMsg("Main: Total number of registered phones returned is %i",$totalRegistered);
    statusMsg("There seem to be no phones registered");
    exit 0
}

$runTime = time()-$runTime;
statusMsg("Finished in $runTime seconds!");

__END__
