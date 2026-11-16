#!/usr/bin/perl
# Loads MediaRemoteAdapter.dylib into Apple's signed perl (which macOS still lets talk to
# MediaRemote) and runs it. Usage: /usr/bin/perl mr-bridge.pl /path/to/MediaRemoteAdapter.dylib
use strict;
use warnings;
use DynaLoader;

my $lib = shift @ARGV or die "usage: mr-bridge.pl <MediaRemoteAdapter.dylib>\n";
my $handle = DynaLoader::dl_load_file($lib, 0) or die "load failed: " . DynaLoader::dl_error() . "\n";
my $symbol = DynaLoader::dl_find_symbol($handle, "adapter_run") or die "symbol missing: " . DynaLoader::dl_error() . "\n";
DynaLoader::dl_install_xsub("main::adapter_run", $symbol);
adapter_run();
