set proj_dir [get_property directory [current_project]]
set plain_src [file normalize [file join $proj_dir ".." ".local" "hw_platform" "iprepo" "ipdefs" "other_ipdefs" "clk_metadata_adapter_v1_0" "hdl" "clk_metadata_adapter_v1_0_vl_rfs.v"]]
set pxi_src [file normalize [file join $proj_dir ".." ".local" "hw_platform" "iprepo" "ipdefs" "pxi_ii_infra" "clk_metadata_adapter_v1_0" "hdl" "clk_metadata_adapter_v1_0_vl_rfs.v"]]

if {![file exists $plain_src]} {
  puts "INFO: \[U55C workaround\] plain clk_metadata_adapter source not found: $plain_src"
  return
}

if {[file exists $pxi_src]} {
  file copy -force $plain_src $pxi_src
  puts "INFO: \[U55C workaround\] patched platform IP source: $pxi_src"
}

set patched 0
set pattern [file join $proj_dir "prj.gen" "my_rm" "bd" "ulp" "ipshared" "*" "hdl" "clk_metadata_adapter_v1_0_vl_rfs.v"]
foreach target [glob -nocomplain $pattern] {
  file copy -force $plain_src $target
  incr patched
  puts "INFO: \[U55C workaround\] patched $target"
}

if {$patched == 0} {
  puts "INFO: \[U55C workaround\] no clk_metadata_adapter targets matched: $pattern"
} else {
  puts "INFO: \[U55C workaround\] patched $patched clk_metadata_adapter source file(s)"
}
