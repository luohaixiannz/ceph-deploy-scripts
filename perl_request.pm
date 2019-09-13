use Switch;
use JSON qw(encode_json decode_json to_json);
use OVP::Storage;
use OVP::Esan::ceph_deploy;
my $request = $ARGV[0];
switch($request) {
	case "update_mon_to_storage" {
		OVP::Storage::update_mon_to_storage();
	}
	case "storage_disable_node" {
		OVP::Storage::storage_disable_node(undef, $ARGV[1]);
	}
	case "get_osd_map_serial" {
		my $esan_info_file = "/etc/ovp/local/esan_info";
		my $esan_info = undef;
		my $fh = undef;

		if(-e $esan_info_file){
        		open $fh,"$esan_info_file" or "die open file error";
        		while (my $line = <$fh>) {
                		$esan_info.=$line;
       			}   
        		$esan_info = decode_json($esan_info) if defined $esan_info;
        		close $fh if $fh;

        		my $osds_info = $esan_info->{osds};
        		foreach my $osd (keys %$osds_info) {
            	    		print "$osd=$osds_info->{$osd}->{serial_num} ";
        		}
		}	
	}
	case "del_osd_info_from_esan_info" {
		eval {
			OVP::Esan::ceph_deploy::del_osd_info_from_esan_info($ARGV[1]);
		};
		if($@) {
			print "del_osd_info_from_esan_info error:$@\n";
		}
	}
	else {
		print "unknow request\n";
	}
}
