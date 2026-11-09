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

set impl_jobs 8
if {[info exists ::env(U55C_RTL_IMPL_JOBS)] && $::env(U55C_RTL_IMPL_JOBS) ne ""} {
  set impl_jobs $::env(U55C_RTL_IMPL_JOBS)
}

set impl_to_step route_design
if {[info exists ::env(U55C_RTL_IMPL_TO_STEP)] && $::env(U55C_RTL_IMPL_TO_STEP) ne ""} {
  set impl_to_step $::env(U55C_RTL_IMPL_TO_STEP)
}

set xpr [file join $root_dir build vivado_rtl $project_name "$project_name.xpr"]
open_project $xpr

launch_runs impl_1 -to_step $impl_to_step -jobs $impl_jobs
wait_on_run impl_1
open_run impl_1

set report_dir [file join $root_dir build vivado_rtl reports]
file mkdir $report_dir

set timing_rpt [file join $report_dir "${project_name}_impl_timing_summary.rpt"]
set util_rpt   [file join $report_dir "${project_name}_impl_utilization.rpt"]
set clock_rpt  [file join $report_dir "${project_name}_impl_clock_utilization.rpt"]

report_timing_summary -file $timing_rpt -warn_on_violation
report_utilization -file $util_rpt
report_clock_utilization -file $clock_rpt

close_project
exit
