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

set xpr [file join $root_dir build vivado_rtl $project_name "$project_name.xpr"]
open_project $xpr

set sim_fs [get_filesets sim_1]

set sim_incremental 0
if {[info exists ::env(U55C_XSIM_INCREMENTAL)] && $::env(U55C_XSIM_INCREMENTAL) ne ""} {
  set sim_incremental $::env(U55C_XSIM_INCREMENTAL)
}
set xsim_mt_level "off"
if {[info exists ::env(U55C_XSIM_MT_LEVEL)] && $::env(U55C_XSIM_MT_LEVEL) ne ""} {
  set xsim_mt_level $::env(U55C_XSIM_MT_LEVEL)
}
set xelab_debug_level "off"
if {[info exists ::env(U55C_XSIM_ELAB_DEBUG_LEVEL)] && $::env(U55C_XSIM_ELAB_DEBUG_LEVEL) ne ""} {
  set xelab_debug_level $::env(U55C_XSIM_ELAB_DEBUG_LEVEL)
}
set xelab_relax 1
if {[info exists ::env(U55C_XSIM_ELAB_RELAX)] && $::env(U55C_XSIM_ELAB_RELAX) ne ""} {
  set xelab_relax $::env(U55C_XSIM_ELAB_RELAX)
}
set xelab_more_options "--nosignalhandlers"
if {[info exists ::env(U55C_XELAB_MORE_OPTIONS)] && $::env(U55C_XELAB_MORE_OPTIONS) ne ""} {
  set xelab_more_options $::env(U55C_XELAB_MORE_OPTIONS)
}
set force_no_glbl 0
if {[info exists ::env(U55C_XSIM_FORCE_NO_GLBL)] && $::env(U55C_XSIM_FORCE_NO_GLBL) ne ""} {
  set force_no_glbl $::env(U55C_XSIM_FORCE_NO_GLBL)
}

set_property INCREMENTAL $sim_incremental $sim_fs
set_property FORCE_NO_COMPILE_GLBL 0 $sim_fs
set_property XSIM.ELABORATE.DEBUG_LEVEL $xelab_debug_level $sim_fs
set_property XELAB.DEBUG_LEVEL $xelab_debug_level $sim_fs
set_property XSIM.ELABORATE.RELAX $xelab_relax $sim_fs
set_property XELAB.RELAX $xelab_relax $sim_fs
if {$xelab_more_options ne ""} {
  set_property -name XSIM.ELABORATE.XELAB.MORE_OPTIONS -value $xelab_more_options -objects $sim_fs
  set_property -name XELAB.MORE_OPTIONS -value $xelab_more_options -objects $sim_fs
} else {
  set_property XSIM.ELABORATE.XELAB.MORE_OPTIONS "" $sim_fs
  set_property XELAB.MORE_OPTIONS "" $sim_fs
}
set_property XSIM.ELABORATE.LOAD_GLBL [expr {!$force_no_glbl}] $sim_fs
set_property XELAB.LOAD_GLBL [expr {!$force_no_glbl}] $sim_fs

set_property XSIM.ELABORATE.MT_LEVEL $xsim_mt_level $sim_fs
set_property XELAB.MT_LEVEL $xsim_mt_level $sim_fs

puts "INFO: Simulation settings: INCREMENTAL=$sim_incremental FORCE_NO_COMPILE_GLBL=$force_no_glbl XSIM.ELABORATE.MT_LEVEL=$xsim_mt_level XSIM.ELABORATE.DEBUG_LEVEL=$xelab_debug_level XSIM.ELABORATE.RELAX=$xelab_relax XELAB.MORE_OPTIONS='$xelab_more_options'"
catch {close_sim -force}
reset_simulation -simset sim_1 -mode behavioral
launch_simulation
run all
catch {close_sim -force}
close_project
exit
