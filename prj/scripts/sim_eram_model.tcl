# Default portable model, or explicit installed vendor library for acceptance.
# Source after vmap; pass $eram_sim_top to vsim so the vendor GSR root is present.
set eram_sim_top {}
if {[info exists eram_vendor_dir] && $eram_vendor_dir ne ""} {
    vlog -work work [file join $eram_vendor_dir ph1p_phy_gsr.v] [file join $eram_vendor_dir ph1p_logic_eram.v]
    set eram_sim_top work.PH1P_PHY_GSR
} else {
    vlog -work work [file join $root src sim ph1p_logic_eram_stub.v]
}
