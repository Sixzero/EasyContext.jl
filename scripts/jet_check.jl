# JET.jl static analysis — reports possible method errors / Nothing slip-throughs.
# Run: julia --project=@jet scripts/jet_check.jl   (CI installs JET into a temp env)
using JET
using EasyContext

res = report_package(EasyContext; toplevel_logger=nothing, target_modules=(EasyContext,))
show(IOContext(stdout, :limit => false), res)
n = length(JET.get_reports(res))
println("\nJET found $n possible errors")
exit(n == 0 ? 0 : 1)
