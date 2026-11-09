set script_dir [file dirname [file normalize [info script]]]
set rtl_dir [file normalize [file join $script_dir ".."]]
set root_dir [file normalize [file join $rtl_dir ".." ".."]]

if {[info exists ::env(U55C_EFFECTIVE_BOARD_REPO_PATHS)] && $::env(U55C_EFFECTIVE_BOARD_REPO_PATHS) ne ""} {
  set repo_paths {}
  foreach rp [split $::env(U55C_EFFECTIVE_BOARD_REPO_PATHS) ":"] {
    if {$rp ne "" && [file isdirectory $rp]} {
      lappend repo_paths [file normalize $rp]
    }
  }
  if {[llength $repo_paths] > 0} {
    set_param board.repoPaths $repo_paths
    puts "INFO: Using board.repoPaths=$repo_paths"
  }
}

set project_name "u55c_template_harden_smoke_rtl"
if {[info exists ::env(U55C_RTL_PROJECT_NAME)] && $::env(U55C_RTL_PROJECT_NAME) ne ""} {
  set project_name $::env(U55C_RTL_PROJECT_NAME)
}

set part "xcu55c-fsvh2892-2L-e"
if {[info exists ::env(U55C_PART)] && $::env(U55C_PART) ne ""} {
  set part $::env(U55C_PART)
}

set build_dir [file join $root_dir build vivado_rtl]
file mkdir $build_dir

create_project -force $project_name [file join $build_dir $project_name] -part $part
set_property target_language Verilog [current_project]
# Keep explicit compile order and avoid Vivado auto-disabling sources when swapping tops.
set_property source_mgmt_mode None [current_project]

set src_files [concat \
  [glob -nocomplain [file join $rtl_dir src *.v]] \
  [glob -nocomplain [file join $rtl_dir src *.sv]] \
]
if {[llength $src_files] == 0} {
  puts "ERROR: no RTL source files found under $rtl_dir/src"
  exit 2
}
add_files $src_files

set xdc_files [glob -nocomplain [file join $rtl_dir constraints *.xdc]]
if {[llength $xdc_files] > 0} {
  add_files -fileset constrs_1 $xdc_files
  puts "INFO: Added timing constraints files: $xdc_files"
}

set tb_files [concat \
  [glob -nocomplain [file join $rtl_dir tb *.v]] \
  [glob -nocomplain [file join $rtl_dir tb *.sv]] \
]
if {[llength $tb_files] == 0} {
  puts "ERROR: no testbench files found under $rtl_dir/tb"
  exit 3
}
add_files -fileset sim_1 $tb_files

set source_top "cnn_full_pipeline_rtl"
if {[info exists ::env(U55C_RTL_SOURCE_TOP)] && $::env(U55C_RTL_SOURCE_TOP) ne ""} {
  set source_top $::env(U55C_RTL_SOURCE_TOP)
}

set sim_top "cnn_full_pipeline_tb"
if {[info exists ::env(U55C_RTL_SIM_TOP)] && $::env(U55C_RTL_SIM_TOP) ne ""} {
  set sim_top $::env(U55C_RTL_SIM_TOP)
}

set_property top $source_top [get_filesets sources_1]
set_property top $sim_top [get_filesets sim_1]

if {[info exists ::env(U55C_RTL_GENERIC)] && $::env(U55C_RTL_GENERIC) ne ""} {
  set generic_str $::env(U55C_RTL_GENERIC)
  set_property generic $generic_str [get_filesets sources_1]
  puts "INFO: Using sources_1 generic='$generic_str'"
}

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

close_project
exit
